# mistralrs-bridge 模式：mistral.rs TCP 桥接分层推理

使用 [mistral.rs](https://github.com/Atituiset/mistral.rs)（EricLBuehler/mistral.rs 的 fork，含 16 个自定义 bridge commits）的 TCP 桥接功能，实现 GPU / CPU 跨机异构推理。

- 状态：⚠️ Qwen2-0.5B 跨机桥接验证通过；Qwen3.6-35B-A3B 端到端未完成（GPU PC OOM 崩溃中断）
- 框架：mistral.rs v0.9.0-dev + 16 bridge commits
- 模型：`Qwen2-0.5B-Instruct-Q4_0`、`Qwen3.6-35B-A3B-Q3_K_M`（目标）
- 设备：GPU PC（RTX 4050 6GB）+ WSL（CPU 15GB）+ Mate 40 Pro（CPU 8GB，未实际参与）

## 目录

- `config.env` — 节点地址、模型路径
- `scripts/` — remote worker、bridge host、GPU 编译脚本
- `topologies/` — 双机/三机桥接 YAML 拓扑文件
- `docs/` — 源码更改报告 + 通宵 session 报告
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
./scripts/run_remote_worker.sh
```

### 3. 启动桥接 Host 推理

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/mistralrs-bridge
./scripts/run_bridge_host.sh topologies/gpu_wsl_bridge.yml
```

### 4. 编译 GPU PC CUDA 二进制（可选）

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
| TCP 协议 + RemoteConnectionPool | ✅ 通过 | — |
| Qwen3.6-35B-A3B GGUF 解析 | ✅ 通过 | 41 层, 248320 vocab |
| SSM 层 forward pass | ⚠️ 编译通过, 未数值验证 | — |
| Qwen3.6-35B-A3B 端到端推理 | 🚧 PENDING | — |
| 跨机桥接 + Qwen3.6-35B-A3B | 🚧 PENDING | — |
| GPU CUDA 二进制 | 🚧 PENDING | OOM 崩溃后未重建 |
| 手机参与桥接 | ❌ 未测试 | — |

## 源码

桥接源码在独立 git 仓库：`../mistral.rs/`，远程: `https://github.com/Atituiset/mistral.rs`。

16 个 bridge commits（`e527fbeb7` → `f66ff28c2`）实现内容详见 `docs/report.md`。
