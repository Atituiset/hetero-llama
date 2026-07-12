# Hetero-LLaMA 三机异构推理设计文档

> 状态：设计已确认  
> 目标：将现有 PC CPU + Mate 40 Pro 双机 RPC 推理扩展到 **GPU PC + 当前机器 + Mate 40 Pro** 三机协同推理。

---

## 1. 背景与目标

### 1.1 当前状态

项目已实现 `v0.1.0`：

- PC（x86_64 纯 CPU）运行 `llama-completion` 作为 Host。
- Mate 40 Pro（ARM64，Termux + Ubuntu proot）运行 `ggml-rpc-server` 作为 RPC Worker。
- 通过 `-ngl` 控制 offload 到手机的层数。
- 通信协议见 [`protocol.md`](../../../protocol.md)，版本 `v0.1`。

### 1.2 新目标

引入第三台机器：

- **GPU PC**：`192.168.1.10`，用户 `Atituiset`，6GB NVIDIA GPU，CUDA 后端。
- **当前机器**：运行 Claude Code 的 WSL/Linux，作为第二个 RPC Worker（CPU 后端）。
- **Mate 40 Pro**：`192.168.1.7`，保持现有 CPU 后端 RPC Worker。

最终形成 **Host（GPU PC CUDA）+ 2× RPC Worker（当前机器 CPU、手机 CPU）** 的三机推理链路。

---

## 2. 架构设计

### 2.1 角色分配

```text
+-------------------------------------------------+
| GPU PC (192.168.1.10)                           |
| llama-completion / llama-cli                    |
| - CUDA backend (6 GB)                           |
| - RPC client to two workers                     |
+-------------------------------------------------+
            |                           |
            | TCP                       | TCP
            v                           v
+-------------------------+   +-------------------------+
| 当前机器                 |   | Mate 40 Pro (192.168.1.7)|
| ggml-rpc-server         |   | ggml-rpc-server         |
| CPU backend             |   | CPU backend             |
+-------------------------+   +-------------------------+
```

### 2.2 两阶段落地

| 阶段 | 拓扑 | 用途 |
|---|---|---|
| **Phase 1** | GPU PC Host + 当前机器 RPC + 手机 RPC | 验证三机都能参与推理 |
| **Phase 2** | GPU PC Host + 手机 RPC，当前机器只旁观 | 验证最小可用双 worker 配置 |

Phase 1 成功后，Phase 2 只需停用当前机器的 RPC Server 并切换 host 脚本。

---

## 3. 网络与地址

### 3.1 固定地址

| 节点 | IP | 端口 | 说明 |
|---|---|---|---|
| GPU PC | `192.168.1.10` | N/A（Host） | 运行主程序 |
| 当前机器 | 自动检测 / 手动覆盖 | `50053` | RPC Worker |
| Mate 40 Pro | `192.168.1.7` | `50052` | RPC Worker，保持现有 |

### 3.2 自动检测当前机器 IP

脚本默认通过 `hostname -I` 获取第一个非回环 IPv4 地址。多网卡/WSL 环境下可能不准，因此 `config.env` 中提供 `CURRENT_IP` 手动覆盖变量。

---

## 4. 文件变更计划

### 4.1 新增文件

| 文件 | 用途 | 运行位置 |
|---|---|---|
| `config.env` | 三机地址、端口、模型路径、llama.cpp 路径 | 所有脚本 source |
| `run_gpu_host.sh` | GPU PC 启动 host 推理 | GPU PC |
| `run_cpu_rpc_server.sh` | 当前机器启动 RPC Server | 当前机器 |
| `run_gpu_host_2node.sh` | Phase 2：GPU PC 只连手机 | GPU PC |

### 4.2 修改文件

| 文件 | 修改内容 |
|---|---|
| `run_phone_rpc.sh` | 从 `config.env` 读取 `PHONE_HOST` / `PHONE_PORT`，保持独立可运行 |
| `protocol.md` | 升级到 `v0.2`，新增三机角色、地址约定、变更日志 |
| `reproduce.md` | 增加 GPU PC CUDA + RPC Client 编译、三机启动、Phase 1/2 复现步骤 |
| `report.md` | 新增三机推理性能对比章节 |

### 4.3 保留文件

| 文件 | 说明 |
|---|---|
| `run_pc_rpc.sh` | 保留旧双机 CPU+手机 模式，向后兼容 |
| `run_phone_baseline.sh` | 手机本地 CPU 基线，不变 |

---

## 5. 编译配置

### 5.1 GPU PC

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-cuda-rpc
cd build-cuda-rpc
cmake .. -DGGML_CUDA=ON -DGGML_RPC=ON
make -j
```

产物：

- `bin/llama-completion`
- `bin/llama-cli`
- `bin/ggml-rpc-server`

### 5.2 当前机器

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-rpc
cd build-rpc
cmake .. -DGGML_RPC=ON
make -j ggml-rpc-server
```

产物：

- `bin/ggml-rpc-server`

### 5.3 手机

复用现有 `build-rpc/bin/ggml-rpc-server`，无需重新编译。

---

## 6. 分层调度策略

### 6.1 原则

- **GPU 为主**：尽量让 GPU PC 本地 CUDA 承担主要计算。
- **RPC 为辅**：当前机器和手机只承担少量层，用于验证三机链路。
- **以实测为准**：`-ngl` 在多 backend（CUDA + CPU + 2×RPC）下的实际 split 由 `GGML_SCHED_DEBUG` 日志确认。

### 6.2 推荐实验组合

对 24 层 Qwen2-0.5B-Instruct-Q4_0：

| 配置 | `-ngl` | 预期效果 | 验证目标 |
|---|---|---|---|
| GPU 基线 | `24` | 全部层在 GPU PC CUDA | 确认 CUDA 后端可用 |
| GPU 为主 + 少量 RPC | `20` | 20 层 CUDA，4 层分摊到两个 RPC | 验证 RPC worker 连接 |
| GPU 为主 + 更多 RPC | `16` | 16 层 CUDA，8 层分摊到两个 RPC | 观察三机参与度 |
| Phase 2 双节点 | `20` | 20 层 CUDA，4 层给手机 | 验证最小双 worker |

> 注：`-ngl` 控制 offload 到本地 GPU 的层数，其余层由 scheduler 在本地 CPU 和 RPC backend 之间分配。实际分布以 `grep "## SPLIT"` 输出为准。

---

## 7. 运行流程

### 7.1 Phase 1（三机）

1. 当前机器执行：`./run_cpu_rpc_server.sh`
2. 手机执行：`./run_phone_rpc.sh`
3. GPU PC 执行：`./run_gpu_host.sh 20 "你好" 5`
4. 观察 GPU PC 日志中的 `## SPLIT` 和手机/当前机器日志中的 `graph_compute`。

### 7.2 Phase 2（双机）

1. 手机执行：`./run_phone_rpc.sh`
2. GPU PC 执行：`./run_gpu_host_2node.sh 20 "你好" 5`
3. 当前机器只用于查看日志和下发命令。

---

## 8. 协议升级

将 [`protocol.md`](../../../protocol.md) 从 `v0.1` 升级到 `v0.2`：

- **后端分配约定**：新增 GPU PC（Host，CUDA）和当前机器（RPC Worker，CPU）。
- **地址约定**：记录三个节点的默认 IP/端口。
- **版本号**：`v0.2`，日期 `2026-07-09`。
- **变更日志**：新增三机拓扑条目。

---

## 9. 风险与回退

| 风险 | 影响 | 回退方案 |
|---|---|---|
| 当前机器 IP 自动检测错误 | host 连不上 RPC worker | `config.env` 中手动设置 `CURRENT_IP` |
| `-ngl` 行为与预期不符 | 分层比例不可控 | 以 DEBUG 日志为准，调整 `-ngl` 并记录 |
| GPU PC CUDA 编译失败 | 无法使用 GPU | 回退到 CPU host + 双 RPC worker，仍可实现三机 |
| 网络延迟导致性能差 | 三机不如 GPU 单机 | 这是预期实验结果，重点在验证链路 |

---

## 10. 成功标准

1. GPU PC 上 `llama-completion` 能同时连接当前机器和手机两个 RPC Server。
2. 运行 `./run_gpu_host.sh` 后，三机日志均显示有 `graph_compute` 或 `SPLIT` 参与。
3. 能通过 `-ngl` 调节 GPU PC 承担的比例。
4. `protocol.md` 更新到 `v0.2`。
5. `reproduce.md` 包含 GPU PC 的逐行复现步骤。

---

## 11. 后续可扩展

- 手机端启用 Vulkan backend（Mali-G78）。
- 自动分层搜索脚本（枚举 `-ngl` 组合并测速）。
- USB 网络共享降低 RTT。
- 长上下文 KV Cache 传输开销测试。
