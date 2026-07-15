# 异构推理通信协议

## 核心原则

1. **默认不改动 `ggml-rpc.cpp` 的序列化格式**。任何结构体、内存对齐、量化格式的变更都必须先在此文档记录，并同步两端版本号。
2. 两端 Agent 在修改 C/C++ 代码前，必须先确认 `protocol.md` 中的相关条目。
3. 版本号格式：`vMAJOR.MINOR`，变更时更新 `updated` 字段。

---

## 当前版本

- **version**: v0.2
- **updated**: 2026-07-10
- **状态**: 三机拓扑版本。GPU PC 作为 Host（CUDA），当前机器与 Mate 40 Pro 作为 RPC Worker（CPU）。

---

## Tensor 传输约定

### Hidden State（层间隐状态）

| 项 | 约定 |
|---|---|
| 数据类型 | FP16 (`GGML_TYPE_F16`) |
| 维度 | `[batch_size, hidden_dim]`，由模型配置决定 |
| 内存布局 | 行主序（row-major）连续内存 |
| 对齐要求 | 默认 16 bytes；如需修改，必须同步更新本文件并两端适配 |
| 传输频率 | Decode 阶段每个 token 传输一次 |

### KV Cache

当前架构 **不跨设备传输 KV Cache**，KV Cache 保留在各自节点本地管理。

---

## 后端分配约定

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA | `192.168.1.10` |
| 当前机器 | RPC Worker | CPU | `172.26.88.148:50053` |
| Mate 40 Pro | RPC Worker | CPU | `192.168.1.7:50052` |

- GPU PC 运行 `llama-completion` / `llama-cli`，带 `-DGGML_CUDA=ON` 编译。
- 当前机器和手机运行 `ggml-rpc-server`。
- 默认手机使用 CPU 后端；Vulkan 作为后续独立阶段。
- 三端必须使用同一 llama.cpp commit，当前锁定为 `152d337fadb93c2a099653c4072d5512c92c5bfd`。

---

## 地址约定

| 节点 | 默认地址 | 配置变量 |
|---|---|---|
| GPU PC Host | `192.168.1.10` | `GPU_PC_IP` |
| 当前机器 RPC Worker | `172.26.88.148:50053` | `CURRENT_IP`, `CURRENT_PORT` |
| Mate 40 Pro RPC Worker | `192.168.1.7:50052` | `PHONE_HOST`, `PHONE_PORT` |

所有地址统一维护在 `config.env` 中。

### 直连模式

Host 直接通过 `CURRENT_IP:50053` 和 `PHONE_HOST:50052` 连接 Worker：

```bash
--rpc 172.26.88.148:50053,192.168.1.7:50052
```

**要求**：Worker 的 IP:PORT 必须能从 Host 直接访问。WSL2 默认 NAT 入站受限，Android Termux 也通常拒绝入站连接，因此三机场景推荐隧道模式。

### 隧道模式（推荐）

当前机器作为 SSH 跳板，通过反向隧道把两个 Worker 映射到 GPU PC 的 `127.0.0.1`：

```
GPU PC Host ──SSH 反向隧道──┬── 127.0.0.1:50053 ── 当前机器 RPC Worker
                            └── 127.0.0.1:50052 ── 当前机器 ──SSH 正向隧道── 手机 RPC Worker
```

启用方式：

```bash
# 当前机器
TUNNEL_MODE=1 ./setup_tunnels.sh

# GPU PC
TUNNEL_MODE=1 ./run_gpu_host.sh 20 "你好" 5
```

此时 Host 的 `--rpc` 端点变为 `127.0.0.1:50053,127.0.0.1:50052`。

---

## 模型约定

- 第一阶段使用 **Qwen2-0.5B-Instruct-Q4_0**。
- 后续如需更换模型，必须确认两端都能加载同一 GGUF 文件，并更新本文件。

---

## 变更日志

| 版本 | 日期 | 变更内容 | 影响端 |
|---|---|---|---|
| v0.2 | 2026-07-10 | 新增三机拓扑：GPU PC CUDA Host + 当前机器 CPU RPC + Mate 40 Pro CPU RPC；锁定统一 commit | 三端 |
| v0.1 | 2026-07-07 | 初始版本，使用原生 ggml-rpc 协议 | 两端 |
