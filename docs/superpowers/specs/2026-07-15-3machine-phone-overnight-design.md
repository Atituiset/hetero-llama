# 3-Machine 文档对齐与手机通宵基准设计

> 状态：待实现  
> 目标：对齐 `3-machine/` 目录的文档与日志，并扩展通宵基准策略以支持完整三机拓扑（GPU PC + WSL + 手机）。

---

## 背景

`3-machine/` 目录当前存在两类内容：

1. **早期调试产物（2026-07-09/10）**：基于 Qwen2-0.5B 的双机/三机调试日志与文档。
2. **新通宵基准产物（2026-07-14）**：基于 Qwen3-1.7B 的 GPU PC 本地 CUDA + WSL RPC 双机基准。

文档与日志不匹配：
- `README.md` 前半部分仍称目录是“预留位置”、完整实现“仍在独立分支”，与后半部分“已合并到 main”矛盾。
- `docs/report.md`、`docs/reproduce.md`、`docs/plan.md`、`docs/protocol.md`、`docs/inbox.md`、`docs/outbox.md` 均为 2026-07-08/10 的 Qwen2-0.5B 内容，引用的日志文件在 `3-machine/logs/` 中已不存在。
- 手机端当前已可参与网络，但通宵脚本 `overnight_gpu_benchmark.sh` 和 `overnight_watchdog.sh` 仅支持 GPU PC + WSL 双机，未纳入手机 Worker。

---

## 设计目标

1. **文档对齐**：消除 README 矛盾，归档过时文档，建立当前 single source of truth。
2. **配置驱动**：让通宵基准支持任意 `(模型, 拓扑, ngl)` 矩阵，便于后续扩展到 Qwen3.6-35B-A3B-FP8。
3. **手机参与**：扩展脚本与 watchdog，支持完整三机拓扑（GPU PC Host + WSL RPC Worker + 手机 RPC Worker）。
4. **可复现**：保留清晰的复现手册和拓扑/协议说明。

---

## 1. 文档对齐策略

### 1.1 README.md

- 删除开头“本目录为 `feat/3-machine-inference` 分支预留位置”“完整实现仍在独立分支”等过时说明。
- 统一为：`3-machine/` 已在 main 分支可用，支持 GPU PC + WSL + 手机三机 RPC 异构推理。
- 日志说明按时间分块：
  - 早期调试（2026-07-09/10，Qwen2-0.5B）。
  - Qwen3-1.7B 双机通宵基准（2026-07-14）。
  - Qwen3-1.7B + Qwen2-0.5B 三机通宵基准（本设计实现后生成）。
- 保留并完善“通宵 watchdog 用法”。

### 1.2 归档旧文档

将以下文件移动到 `docs/historical/`，保留历史但不再作为当前入口：

| 原文件 | 归档后路径 | 说明 |
|---|---|---|
| `docs/report.md` | `docs/historical/report-20260710-qwen2-0.5b.md` | 2026-07-10 三机调试报告 |
| `docs/reproduce.md` | `docs/historical/reproduce-qwen2-0.5b.md` | Qwen2-0.5B 复现手册 |
| `docs/plan.md` | `docs/historical/plan-dual-machine-20260707.md` | 原始双机方案 |
| `docs/protocol.md` | `docs/historical/protocol-v0.2-20260710.md` | v0.2 协议（Qwen2-0.5B） |
| `docs/inbox.md` | `docs/historical/inbox-20260708.md` | PC → Phone 信箱 |
| `docs/outbox.md` | `docs/historical/outbox-20260708.md` | Phone → PC 信箱 |

### 1.3 新建/覆盖当前文档

- `docs/report.md`：基于最新通宵结果（Qwen3-1.7B + Qwen2-0.5B，local / +WSL / +Phone）的单一报告。
- `docs/reproduce.md`：当前三机复现手册，覆盖模型准备、三端编译、隧道启动、watchdog 运行。
- `docs/protocol.md`：v0.3，更新为当前三机拓扑、Qwen3-1.7B / Qwen2-0.5B、统一 commit 要求。

---

## 2. 配置驱动的通宵基准矩阵

### 2.1 新增配置文件

文件：`config/benchmark-matrix.env`

```bash
# 拓扑端点定义（在 GPU PC 上求值）
TOPOLOGY_local=""
TOPOLOGY_wsl="--rpc 127.0.0.1:50053"
TOPOLOGY_phone="--rpc 127.0.0.1:50053,127.0.0.1:50052"

# 模型定义：OLLAMA_NAME|GGUF_NAME|PROMPT|N
MODEL_qwen3_1_7b="qwen3:1.7b|qwen3-1.7b-instruct-ollama.gguf|你好|32"
MODEL_qwen2_0_5b="qwen2:0.5b|qwen2-0.5b-instruct-q4_0.gguf|你好|32"

# 运行矩阵：模型别名=空格分隔的拓扑列表
RUN_qwen3_1_7b="local wsl phone"
RUN_qwen2_0_5b="local wsl phone"

# 每组 ngl 取值
NGL_LIST="0 12 24 99"
```

### 2.2 overnight_gpu_benchmark.sh 改造

1. 读取 `config.env` 和 `config/benchmark-matrix.env`。
2. 解析所有 `RUN_*` 变量，生成执行计划 `(model, topology, ngl)`。
3. 对每个模型：
   - 通过 Ollama 拉取模型并链接到 `~/models/<GGUF_NAME>`（保持现有逻辑）。
   - 按拓扑顺序执行：local → wsl → phone。
   - 每个拓扑下循环 `NGL_LIST`。
4. 日志命名统一为：
   ```
   <model_alias>_<topology>_ngl<ngl>_<timestamp>.log
   ```
   例如：`qwen3_1_7b_phone_ngl24_20260715_020000.log`。
5. GPU 采样 CSV 同步命名为 `<model_alias>_<topology>_ngl<ngl>_<timestamp>_gpu.csv`。
6. 汇总文件 `summary_<timestamp>.txt` 收集所有结果。
7. 支持 `DRY_RUN=1`：只打印执行计划，不实际运行。

### 2.3 拓扑顺序与可扩展性

- `local` 不依赖外部 Worker。
- `wsl` 依赖当前机器 RPC Server 和反向隧道。
- `phone` 依赖手机 RPC Server、本地转发、反向隧道。
- 未来模型若跑不动 phone，只需把 `RUN_*` 中的 `phone` 去掉，无需改脚本。
- 更大模型（如 Qwen3.6-35B-A3B-FP8）只需新增 `MODEL_*` 和 `RUN_*` 行。

---

## 3. Watchdog 扩展

### 3.1 读取矩阵配置

`overnight_watchdog.sh` 读取 `config/benchmark-matrix.env`，根据实际声明的拓扑决定监控范围：

| 拓扑 | 监控对象 |
|---|---|
| `wsl` | 本地 `rpc_server` tmux 会话；本地 `reverse_tunnel` tmux 会话 |
| `phone` | 当前机器到手机的 SSH 可达性；当前机器 `phone_tunnel` 本地转发进程；手机上 `ggml-rpc-server` 进程 |

如果矩阵里没有某个拓扑，watchdog 不启动/监控对应组件。

### 3.2 手机监控实现

- **SSH 可达性**：`ssh -p 8022 -o ConnectTimeout=5 u0_a111@192.168.1.7 true`。
- **本地转发进程**：检查监听 `127.0.0.1:50052` 的 SSH 进程，不存在则重建。
- **手机 RPC Server 进程**：通过 SSH 执行 `pgrep -f "ggml-rpc-server -H 127.0.0.1 -p 50052"`，不存在则远程启动 `run_phone_rpc.sh`。

### 3.3 完成判定

保持现有逻辑：检测到 GPU PC 上生成 `summary_*.txt` 后退出 `--loop`。

### 3.4 状态文件

`~/.claude/hetero_overnight_status.md` 中追加的每一行增加当前活跃拓扑信息，例如：

```text
2026-07-15 02:00:00  topologies:local,wsl,phone; rpc_server:ok; reverse_tunnel:ok; phone_tunnel:ok; phone_rpc:ok; gpu_bench:ok; summary:pending
```

---

## 4. 运行时流程

```text
当前机器 (WSL)
  ├── 启动本地 ggml-rpc-server，绑定 127.0.0.1:50053
  ├── 建立 SSH 本地转发：127.0.0.1:50052 -> 手机 127.0.0.1:50052
  └── 建立 SSH 反向隧道到 GPU PC
        ├─R 127.0.0.1:50053 -> WSL 127.0.0.1:50053
        └─R 127.0.0.1:50052 -> WSL 127.0.0.1:50052

GPU PC (CUDA Host)
  └── overnight_gpu_benchmark.sh
        ├── 拉取/链接模型
        ├── 对 RUN_* 中每个模型：
        │     ├── local:  llama-completion ...
        │     ├── wsl:    llama-completion --rpc 127.0.0.1:50053 ...
        │     └── phone:  llama-completion --rpc 127.0.0.1:50053,127.0.0.1:50052 ...
        └── 生成 summary_*.txt

overnight_watchdog.sh（当前机器运行）
  └── 每 30 分钟检查并恢复上述组件
```

---

## 5. 中断恢复与上下文窗口安全

> 核心约束：通宵任务可能在任何时刻因网络、设备休眠、SSH 断开、Claude 会话结束等原因中断，必须能在无当前会话上下文的情况下恢复。

### 5.1 设计原则

- **会话无关**：所有状态持久化到文件，不依赖当前 Claude session 存活。
- **幂等重启**：脚本每次启动时先清理同名 tmux 会话/进程，再新建；重复执行不会产生冲突。
- **断点不丢**：每完成一个 `(model, topology, ngl)` 组合就落盘日志，summary 在全部跑完后生成。即使中途失败，已完成的组合日志保留。
- **Watchdog 自治**：`overnight_watchdog.sh --loop` 在当前机器后台循环，不依赖 GPU PC 上的交互式 session。

### 5.2 恢复机制

- **进程级恢复**：watchdog 每 30 分钟检查本地 `rpc_server`、`reverse_tunnel`、`phone_tunnel`、远程 `gpu_bench`，掉线即重启。
- **任务级恢复**：`overnight_gpu_benchmark.sh` 每次启动时检测当前模型/拓扑/ngl 是否有已存在且非空的日志文件。如果有，默认跳过（可通过 `FORCE_RERUN=1` 覆盖）。这样即便 `gpu_bench` tmux 会话被重建，也能从中断处继续。
- **状态透明**：`~/.claude/hetero_overnight_status.md` 记录每次健康检查的结果，人工查看即可知道当前进度。

### 5.3 上下文窗口安全

- 所有配置、命令、复现步骤写入仓库文件，而不是留在对话上下文中。
- 复现手册 `docs/reproduce.md` 必须包含“如果中断了怎么恢复”小节，让用户无需翻聊天记录即可继续。

## 6. 关键边界与错误处理

- **手机离线**：如果矩阵里声明了 `phone` 但手机 SSH 不可达，`setup_tunnels.sh` 和 watchdog 应打印 WARN 并降级为 wsl（仅在隧道启动阶段），或保持失败让 watchdog 持续重试。本设计选择：**watchdog 持续重试，每轮检查都尝试恢复手机链路**。
- **模型拉取失败**：`ollama pull` 失败时脚本退出，watchdog 会在下一轮重启 `gpu_bench`。
- **命名冲突**：日志名加入时间戳，避免同一夜多次运行覆盖。
- **Qwen2-0.5B 来源**：当前 Ollama 上可能不是 `qwen2:0.5b` 的精确名称；配置中保留 Ollama manifest 的自动探测逻辑，别名仅用于日志命名。

---

## 7. 交付清单

| 类别 | 文件 | 动作 |
|---|---|---|
| 文档 | `3-machine/README.md` | 更新，消除矛盾，分块说明日志 |
| 文档 | `3-machine/docs/historical/*` | 新建目录，归档 6 个旧文档 |
| 文档 | `3-machine/docs/report.md` | 重写为当前报告 |
| 文档 | `3-machine/docs/reproduce.md` | 重写为三机复现手册 |
| 文档 | `3-machine/docs/protocol.md` | 更新为 v0.3 |
| 配置 | `3-machine/config/benchmark-matrix.env` | 新增 |
| 脚本 | `3-machine/scripts/overnight_gpu_benchmark.sh` | 重构为矩阵驱动 |
| 脚本 | `3-machine/scripts/overnight_watchdog.sh` | 扩展手机监控 |
| 脚本 | `3-machine/scripts/setup_tunnels.sh` | 修复 `PHONE_REAL_HOST` 未定义 bug；验证手机链路 |
| 脚本 | `3-machine/config.env` | 修正 `MODEL_PATH` 为可覆盖，或保持由 benchmark 配置管理 |

---

## 8. 验收标准

- [ ] `README.md` 无矛盾，日志分块清晰。
- [ ] 旧文档已全部归档到 `docs/historical/`，无 stale 引用。
- [ ] `config/benchmark-matrix.env` 可被 `overnight_gpu_benchmark.sh` 正确解析，`DRY_RUN=1` 输出符合预期。
- [ ] `overnight_gpu_benchmark.sh` 能生成 Qwen3-1.7B 和 Qwen2-0.5B 的 local/wsl/phone 日志与 summary。
- [ ] `overnight_watchdog.sh` 在 `--loop` 模式下能监控并恢复 rpc_server、reverse_tunnel、phone_tunnel、phone_rpc、gpu_bench。
- [ ] `setup_tunnels.sh` 无 `PHONE_REAL_HOST` 未定义错误。
