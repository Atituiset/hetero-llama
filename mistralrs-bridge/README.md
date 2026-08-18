# mistralrs-bridge 模式：mistral.rs TCP 桥接分层推理

使用 [mistral.rs](https://github.com/Atituiset/mistral.rs)（EricLBuehler/mistral.rs 的 fork，`feat/remote-layer-split` 分支，含 18 个自定义 commits）的 TCP 桥接功能，实现 GPU / CPU 跨机异构推理。

- 状态：✅ **27B（3.6/3.8）和 35B-A3B 跨机桥接均端到端跑通且输出正确**；27B decode ~2.5 T/s，35B 经稀疏 MoE 修复后 decode ~3.4 T/s（长输出有重复退化待查）
- 框架：mistral.rs v0.9.0-dev + bridge commits + qwen35/qwen35moe GGUF 支持（`f19aaaa88`，已提交并推送）
- 模型：`Qwen2-0.5B-Instruct-Q4_0`（已验证）、`Qwen3.6-27B-Q3_K_M`（✅ 正确）、`Qwen3.6-35B-A3B-Q3_K_M`（✅ 正确/慢）、`Qwen3.5-0.8B-Q4_K_M`（数值调试基准）
- 设备：GPU PC（RTX 4050 6GB + 15GB RAM）+ WSL（CPU 15GB，worker ≤16 层，超限会把 WSL 搞崩）

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
| 通信协议 | 自定义 TCP 二进制 | gRPC |
| 层粒度 | 任意连续层范围 | 从第 N 层开始卸载 |
| 远端设备语法 | `remote:tcp://IP:PORT` (YAML) | `--rpc IP:PORT` (CLI) |
| 手机支持 | ⚠️ 需手机编译 worker | ✅ Termux arm64 编译 |
| Qwen3.6 SSM 支持 | ✅ 已实现 | ❌ 不支持 |
| 生产就绪 | ❌ 实验阶段 | ✅ 可用 |

## 验证状态

| 测试项 | 状态 | 性能 |
|--------|------|------|
| Qwen2-0.5B 跨机桥接 | ✅ 通过 | 197 T/s prompt, 46 T/s decode |
| Qwen3.5-0.8B 纯 CPU / loopback / 三段拓扑 | ✅ 输出全正确 | 纯 CPU 20 T/s |
| **Qwen3.6-27B 三段桥接**（12 cuda + 37 cpu + 15 remote） | ✅ **输出正确** | prompt 5.2 T/s, decode 2.42 T/s |
| **Qwen3.6-35B-A3B 三段桥接**（8 cuda + 17 cpu + 15 remote） | ✅ **输出正确** | decode ~3.4 T/s（稀疏 MoE 修复后，~200x）；长输出重复退化待查 |
| **Qwen3.8-27B 三段桥接**（12 cuda + 37 cpu + 15 remote） | ✅ **输出正确** | TTFT 4.59s, prompt 5.59 T/s, decode 2.56 T/s |
| qwen35 数值逐层对照 llama.cpp | ✅ 24 层 <1% 偏差 | — |

## 源码

桥接源码在独立 git 仓库：`../mistral.rs/`，远程: `https://github.com/Atituiset/mistral.rs`（`feat/remote-layer-split` 分支，已推送）。

19 个自定义 commits（`f4cb782b9` → `a9f7a8d3b`）：早期 16 个 bridge/SSM commits 实现内容详见 `docs/report.md`；第 17-18 个（remote worker 部分加载 + qwen35 dense GGUF 支持及全部数值修复）与第 19 个（x86 CPU 稀疏 MoE 前向，35B 提速 ~200x）见 `docs/session-2026-08-16.md` 第八、九节。
