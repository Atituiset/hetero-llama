# mistralrs-bridge 模式：mistral.rs TCP 桥接分层推理

使用 [mistral.rs](https://github.com/Atituiset/mistral.rs)（EricLBuehler/mistral.rs 的 fork，`feat/remote-layer-split` 分支，含 19 个自定义 commits）的 TCP 桥接功能，实现 GPU / CPU 跨机异构推理。

- 状态：✅ **27B（3.6/3.8）和 35B-A3B 跨机桥接均端到端跑通且输出正确**；27B decode ~2.5 T/s，35B 经稀疏 MoE 修复后 decode ~3.4 T/s（限长输出正常；无限 decode 数万 token 会长程退化重复并撑爆内存，务必设 max_tokens）
- 框架：mistral.rs v0.9.0-dev + bridge commits + qwen35/qwen35moe GGUF 支持（`f19aaaa88`，已提交并推送）
- 模型：`Qwen2-0.5B-Instruct-Q4_0`（已验证）、`Qwen3.6-27B-Q3_K_M`（✅ 正确）、`Qwen3.8-27B-Q3_K_M`（✅ 正确）、`Qwen3.6-35B-A3B-Q3_K_M`（✅ 正确，稀疏 MoE 修复后 ~3.4 T/s）、`Qwen3.5-0.8B-Q4_K_M`（数值调试基准）
- 设备：GPU PC（RTX 4050 Laptop 6GB 显存 + 15GB 内存）+ WSL（CPU 15GB 内存，worker ≤16 层，超限会把 WSL 搞崩）+ 手机（可选，5 层 ~1.2GB）

## 目录

- `config.env` — 节点地址、模型路径
- `scripts/` — remote worker、bridge host、GPU 编译、WSL 反向隧道等脚本
- `topologies/` — 双机/三机桥接 YAML 拓扑文件（含 27B/35B 实测拓扑 `qwen36_*.yml`）
- `docs/` — 源码更改报告、通宵 session 报告、8/16-8/18 攻坚报告（`session-2026-08-16.md`）
- `logs/` — 运行日志

## 架构

```
┌─────────────────────────┐
│ GPU PC (RTX 4050 6GB)   │
│ mistralrs run --topology│
│ Layers 0-7: cuda[0]     │ ──TCP── ┌──────────────────────┐
│                         │         │ WSL (CPU 15GB)        │
└─────────────────────────┘         │ mistralrs remote-worker│
                                    │ Layers 8-23: CPU      │
                                    └──────────────────────┘
```

## 快速开始

> 最快路径（推荐）：`./scripts/run_qwen_27b_bridge.sh 3.8 "prompt"` —— worker + 隧道 + host 一键完成，`-i` 进交互模式。以下是其内部展开的四个手动步骤。

### 1. 编译 mistral.rs 源码

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/mistral.rs
cargo build --release -p mistralrs-cli
```

### 2. 启动 WSL Remote Worker

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/mistralrs-bridge
./scripts/run_remote_worker.sh Qwen_Qwen3.6-27B-Q3_K_M.gguf 127.0.0.1:5051 49-63
```

### 3. 建立 WSL → GPU PC 反向隧道（跨机时必需）

WSL2 是 NAT 网络，GPU PC 连不进来，需反向隧道把 GPU PC 的 127.0.0.1:5051 转发到 WSL：

```bash
./scripts/start_wsl_tunnel.sh   # 前台保持运行
```

### 4. 启动桥接 Host 推理（GPU PC 上）

```bash
scp topologies/qwen36_27b_bridge.yml $GPU_PC_IP:/tmp/
ssh $GPU_PC_IP '~/projects/gpu-cpu-phone-test/mistral.rs/target/release/mistralrs run \
  --format gguf --topology /tmp/qwen36_27b_bridge.yml \
  -m ~/models -f Qwen_Qwen3.6-27B-Q3_K_M.gguf --max-seq-len 2048 -i "你好"'
```

注意：`-n` 短 flag 是 `--device-layers` 而非 max-tokens，别用它限制输出长度。

### 5. 编译 GPU PC CUDA 二进制（首次或更新后）

GPU PC 只有 15GB RAM，必须单任务编译且只编 `cuda` feature（flash-attn 的并行 nvcc 曾把机器干到 OOM 重启）：

```bash
./scripts/build_gpu_binary.sh 1
```

## 与 llama.cpp RPC 对比

| 特性 | mistral.rs Bridge | llama.cpp RPC |
|------|-------------------|---------------|
| 通信协议 | 自定义 TCP 二进制 | 自定义 TCP（ggml-rpc） |
| 卸载粒度 | 任意连续层范围（块边界一次往返） | 张量/算子级（`-ngl` 按层尾卸载） |
| 远端设备语法 | `remote:tcp://IP:PORT` (YAML) | `--rpc IP:PORT` (CLI) |
| 手机支持 | ⚠️ 需手机编译 worker | ✅ Termux arm64 编译（3-machine 模式已验证） |
| Qwen3.6 SSM 支持 | ✅ 已实现 | ✅ 支持（0.8B RPC 实测正确） |
| 生产就绪 | ❌ 实验阶段 | ✅ 可用 |

**同模型同 prompt 三机实测（Qwen3.8-27B Q3_K_M，2026-08-20）**：

| 拓扑 | mistral.rs Bridge | llama.cpp RPC | 倍数 |
|------|-------------------|---------------|------|
| 双机（GPU PC + WSL） | decode **2.56 T/s** | decode 0.32 T/s | 8x |
| 三机（+手机） | decode **1.29 T/s** | decode 0.22 T/s | 6x |

根因：ggml RPC 是算子级卸载，decode 每 token 每算子都有网络往返；本桥按连续层块卸载，每 token 每个远程块只一次 20KB hidden state 往返。详见 `docs/threeway-challenge-2026-08-19.md`。

> 为什么仍选 mistral.rs：项目动机是自研学习（数值修复、稀疏 MoE 等改动需要读懂并修改引擎源码，Rust/candle 比 ggml 易改）；且当时 llama.cpp RPC 三机的运维链路（SSH 隧道 + 手机掉线）稳定性差。论生产可用性 llama.cpp RPC 是更省力的路径。

## 验证状态

| 测试项 | 状态 | 性能 |
|--------|------|------|
| Qwen2-0.5B 跨机桥接 | ✅ 通过 | 197 T/s prompt, 46 T/s decode |
| Qwen3.5-0.8B 纯 CPU / loopback / 三段拓扑 | ✅ 输出全正确 | 纯 CPU 20 T/s |
| **Qwen3.6-27B 三段桥接**（12 cuda + 37 cpu + 15 remote） | ✅ **输出正确** | prompt 5.2 T/s, decode 2.42 T/s |
| **Qwen3.6-35B-A3B 三段桥接**（8 cuda + 17 cpu + 15 remote） | ✅ **输出正确** | decode ~3.4 T/s（稀疏 MoE 修复后，~200x）；限长输出正常，无限 decode 长程退化 |
| **Qwen3.8-27B 三段桥接**（12 cuda + 37 cpu + 15 remote） | ✅ **输出正确** | TTFT 4.59s, prompt 5.59 T/s, decode 2.56 T/s |
| **Qwen3.8-27B 四段三机桥接**（12 cuda + 33 cpu + 14 WSL + 5 手机） | ✅ **输出正确** | TTFT 7.06s, prompt 3.56 T/s, decode 1.29 T/s |
| qwen35 数值逐层对照 llama.cpp | ✅ 24 层 <1% 偏差 | — |

## 源码

桥接源码在独立 git 仓库：`../mistral.rs/`，远程: `https://github.com/Atituiset/mistral.rs`（`feat/remote-layer-split` 分支，已推送）。

### 源码改动整体总结（19 commits，+3696/-315 行，32 文件）

**一、TCP 远程层卸载（核心，13 commits）**——从零实现的跨机分层推理：

- 拓扑/设备层（`f4cb782b9`）：拓扑 YAML 支持 `remote:tcp://IP:PORT`，`RemoteLayerMapper`（DeviceMapper 新实现，本地 cuda/cpu 与远端混排）
- 线协议 + 连接池（`device_map/remote.rs`，~330 行）：`[cmd][layer_start][layer_end][past_kv][len][F32 张量 payload]` 二进制协议，`RemoteConnectionPool` 持久连接 + 断线重连
- 模型侧部分前向（`1fc61596e`、`aa6249c2f` 等）：给全部 7 个量化 GGUF 模型文件加 `forward_from_layer(hidden, start, end, past_kv)`——从预计算的 hidden state 只执行指定层范围，worker 不需要 embedding/lm_head
- 性能（`ba1ae3b08`）：连续远程块每 token 每块只一次 TCP 往返（~20KB），而非每层一次——比 llama.cpp RPC 快 6-8 倍的关键
- 正确性修复（7 个 fix commits）：past_kv 位置跨设备传递（RoPE 错位）、causal mask、输出张量回移输入设备、CUDA DeviceId 规范化、KV cache Option<Device>、多线程 worker 单连接池、RoPE 预创建重复 push

**二、qwen35/qwen35moe GGUF 模型支持（3 commits）**——上游当时不支持的混合 SSM 架构：

- `1aed6ecc3`：Qwen35MoE arch 注册；`c03ba7d3a`+`35a7aec02`：qwen3_moe 加 Gated DeltaNet SSM 层（713 行）
- `f19aaaa88`（最大单 commit，+1615/-239）：新文件 `quantized_qwen35.rs`（1151 行）dense 完整实现 + **6 个数值 bug 修复**（conv1d 核方向、DeltaNet 递推顺序、norm_gated eps 位置、warmup 污染 SSM 状态、MTP 层误执行、v 头 tiled repeat 顺序）——输出从乱码变正确的关键

**三、Remote worker 分层加载（1 commit）**——`e9cd3b850`：worker 用 `--layers S-E` 只加载指定层权重，范围外不分配 KV/SSM state，embedding/lm_head 用 dummy 跳过。手机（8GB）能参与 27B 的前提。

**四、稀疏 MoE CPU 前向（1 commit，即上游 PR #2380）**——`a9f7a8d3b`：x86_64 上 MoE 前向不再全量反量化 256 个 expert（~380MB/层/token），按 expert 切分原始量化字节流只算路由到的 top-8。35B decode 从 ~1 token/min 到 3.4 T/s（~200x）。

**附带基础设施**：`pipeline/gguf.rs` topology 优先于 auto device mapping；`device_map/mappers.rs` `is_partial()` 区分 host/worker；`mistralrs-quant/cublaslt/api.rs` 报错携带张量形状；hidden state 全设备 F32 不变量。

### 详细文档

- 前 16 个 bridge/SSM commits 实现分析：`docs/report.md`
- 第 17-19 个（部分加载 + qwen35 dense + 数值修复、稀疏 MoE）：`docs/session-2026-08-16.md` 第八、九节
