# 异构推理通信协议 v0.3

## 核心原则

1. 默认不改动 `ggml-rpc.cpp` 的序列化格式。任何结构体、内存对齐、量化格式的变更都必须先在此文档记录，并同步两端版本号。
2. 两端 Agent 在修改 C/C++ 代码前，必须先确认本文件中的相关条目。
3. 版本号格式：`vMAJOR.MINOR`，变更时更新 `updated` 字段。

---

## 当前版本

- **version**: v0.3
- **updated**: 2026-07-15
- **状态**: 完整三机拓扑。GPU PC 作为 Host（CUDA），当前机器（WSL）与 Mate 40 Pro 作为 RPC Worker（CPU）。

---

## 节点角色

| 节点 | 角色 | 后端 | 地址/说明 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 / RTX 4050 6GB | `192.168.1.10` |
| 当前机器 | RPC Worker | CPU（WSL2） | `172.26.88.148:50053`；隧道模式下映射为 `127.0.0.1:50053` |
| Mate 40 Pro | RPC Worker | CPU（Termux + proot Ubuntu） | `192.168.1.7:50052`；隧道模式下映射为 `127.0.0.1:50052` |

---

## 地址约定

所有地址统一维护在 `config.env` 中：

| 节点 | 默认地址 | 配置变量 |
|---|---|---|
| GPU PC Host | `192.168.1.10` | `GPU_PC_IP` |
| 当前机器 RPC Worker | `172.26.88.148:50053` | `CURRENT_IP`, `CURRENT_PORT` |
| Mate 40 Pro RPC Worker | `192.168.1.7:50052` | `PHONE_HOST`, `PHONE_PORT` |

### 直连模式

Host 直接通过 `CURRENT_IP:50053` 和 `PHONE_HOST:50052` 连接 Worker：

```bash
--rpc 172.26.88.148:50053,192.168.1.7:50052
```

### 隧道模式（默认/推荐）

当前机器作为 SSH 跳板，通过反向隧道把两个 Worker 映射到 GPU PC 的 `127.0.0.1`：

```text
GPU PC Host ──SSH 反向隧道──┬── 127.0.0.1:50053 ── 当前机器 RPC Worker
                            └── 127.0.0.1:50052 ── 当前机器 ──SSH 本地转发──
                                                                          │
                                    ┌─ Unix socket ─┐                     │
                                    │  /data/data/.../.phone_rpc_50052.sock │
                                    └──────┬────────┘                     │
                                           │                              │
                                    socat（proot 内）                     │
                                           │                              │
                                    手机 RPC Worker（proot 127.0.0.1:50052）
```

说明：
- Android/Termux 无法连接自身的 LAN IP（`192.168.1.7`），因此手机 RPC Server 绑定在 proot 内的 `127.0.0.1:50052`。
- 在 proot 内运行 `socat`，把 proot 的 `127.0.0.1:50052` 桥接到 Termux 可见的 Unix socket。
- 当前机器通过 SSH 本地转发连接该 Unix socket，再通过反向隧道暴露给 GPU PC。

启用方式：

```bash
# 当前机器
./scripts/setup_tunnels.sh

# GPU PC
TUNNEL_MODE=1 ./scripts/run_gpu_host.sh 20 "你好" 5
```

---

## 模型约定

当前矩阵支持以下模型：

| 模型 | 来源 | 备注 |
|---|---|---|
| Qwen3-1.7B-Instruct-Q4_K_M | Ollama `qwen3:1.7b` | 约 2.0B 参数，本地 `-ngl 99` 可达 132 t/s |
| Qwen2-0.5B-Instruct-Q4_0 | Ollama `qwen2:0.5b` | 24 层 transformer，早期验证模型 |

后续添加模型只需在 `config/benchmark-matrix.env` 中声明。

---

## 统一 commit

三端必须使用同一 llama.cpp commit。当前推荐：

```bash
# 在 GPU PC、当前机器、手机上分别执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
```

若后续升级 commit，必须更新本文件并重新编译三端。

---

## 变更日志

| 版本 | 日期 | 变更内容 | 影响端 |
|---|---|---|---|
| v0.3 | 2026-07-15 | 更新为完整三机拓扑；支持 Qwen3-1.7B / Qwen2-0.5B；模型矩阵配置化 | 三端 |
| v0.2 | 2026-07-10 | 新增 GPU PC CUDA Host + 当前机器 CPU RPC + Mate 40 Pro CPU RPC；锁定统一 commit | 三端 |
| v0.1 | 2026-07-07 | 初始版本，使用原生 ggml-rpc 协议 | 两端 |
