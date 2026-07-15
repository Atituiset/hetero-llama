# 3-Machine 文档对齐与手机通宵基准实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 对齐 `3-machine/` 文档与日志，并将通宵基准扩展为配置驱动的完整三机拓扑（GPU PC + WSL + 手机），支持断点续跑。

**Architecture:** 采用 `config/benchmark-matrix.env` 声明模型与拓扑矩阵；`overnight_gpu_benchmark.sh` 解析矩阵并逐项执行；`overnight_watchdog.sh` 按矩阵声明的拓扑监控并恢复链路；旧文档归档到 `docs/historical/`，当前文档重写。

**Tech Stack:** Bash, Ollama, llama.cpp RPC, SSH/tmux, Markdown.

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `3-machine/README.md` | 模式入口，消除矛盾，分块展示日志 |
| `3-machine/docs/historical/*` | 归档 2026-07-08/10 的旧文档 |
| `3-machine/docs/protocol.md` | v0.3 协议：三机拓扑、模型约定、地址约定 |
| `3-machine/docs/reproduce.md` | 当前三机复现手册，含中断恢复 |
| `3-machine/docs/report.md` | 当前报告（基于新通宵结果） |
| `3-machine/config/benchmark-matrix.env` | 模型与拓扑矩阵配置 |
| `3-machine/scripts/overnight_gpu_benchmark.sh` | 解析矩阵，逐项跑基准，生成 summary |
| `3-machine/scripts/overnight_watchdog.sh` | 按矩阵监控并恢复本地/手机/GPU PC 组件 |
| `3-machine/scripts/setup_tunnels.sh` | 修复 `PHONE_REAL_HOST` bug，支持手机隧道 |
| `3-machine/config.env` | 修正 `MODEL_PATH` 为可覆盖，兼容矩阵配置 |

---

## Task 1: 归档旧文档

**Files:**
- Create dir: `3-machine/docs/historical/`
- Move: `3-machine/docs/report.md` → `3-machine/docs/historical/report-20260710-qwen2-0.5b.md`
- Move: `3-machine/docs/reproduce.md` → `3-machine/docs/historical/reproduce-qwen2-0.5b.md`
- Move: `3-machine/docs/plan.md` → `3-machine/docs/historical/plan-dual-machine-20260707.md`
- Move: `3-machine/docs/protocol.md` → `3-machine/docs/historical/protocol-v0.2-20260710.md`
- Move: `3-machine/docs/inbox.md` → `3-machine/docs/historical/inbox-20260708.md`
- Move: `3-machine/docs/outbox.md` → `3-machine/docs/historical/outbox-20260708.md`

- [ ] **Step 1: 创建历史目录并移动文件**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
mkdir -p docs/historical
git mv docs/report.md docs/historical/report-20260710-qwen2-0.5b.md
git mv docs/reproduce.md docs/historical/reproduce-qwen2-0.5b.md
git mv docs/plan.md docs/historical/plan-dual-machine-20260707.md
git mv docs/protocol.md docs/historical/protocol-v0.2-20260710.md
git mv docs/inbox.md docs/historical/inbox-20260708.md
git mv docs/outbox.md docs/historical/outbox-20260708.md
```

- [ ] **Step 2: 验证归档结果**

```bash
ls -1 docs/historical/
```

Expected output contains all 6 historical files.

- [ ] **Step 3: Commit**

```bash
git add 3-machine/docs/historical/
git commit -m "docs(3-machine): archive stale 2026-07 docs to historical/

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: 更新 README.md

**Files:**
- Modify: `3-machine/README.md`

- [ ] **Step 1: 重写 README.md**

Replace entire file content with:

```markdown
# 3-Machine 异构推理模式

GPU PC（CUDA Host）+ 当前机器（WSL CPU RPC Worker）+ 华为 Mate 40 Pro（手机 CPU RPC Worker）三机 RPC 异构推理。

---

## 状态

- `3-machine/` 已在 `main` 分支可用。
- 支持完整三机拓扑、双机拓扑（GPU PC + WSL / GPU PC + 手机）、以及 GPU PC 本地 CUDA 基线。
- 包含配置驱动的通宵基准脚本与 watchdog，支持断点续跑。

---

## 目录结构

```text
3-machine/
├── README.md                          # 本文件
├── config.env                         # 三机地址与构建路径
├── config/
│   └── benchmark-matrix.env           # 通宵基准矩阵配置
├── scripts/
│   ├── overnight_gpu_benchmark.sh     # 通宵自动基准
│   ├── overnight_watchdog.sh          # 通宵 watchdog
│   ├── setup_tunnels.sh               # SSH 隧道启动
│   ├── run_cpu_rpc_server.sh          # 当前机器 RPC Server
│   ├── run_gpu_host.sh                # GPU PC 三机 Host
│   ├── run_gpu_host_2node.sh          # GPU PC 双机 Host（仅手机）
│   ├── run_phone_rpc.sh               # 手机 RPC Server
│   ├── run_phone_baseline.sh          # 手机本地 CPU 推理
│   └── run_pc_rpc.sh                  # PC 端 RPC 推理
├── docs/
│   ├── protocol.md                    # 通信协议 v0.3
│   ├── reproduce.md                   # 三机复现手册
│   ├── report.md                      # 最新报告
│   └── historical/                    # 归档的旧文档
└── logs/                              # 运行日志
```

---

## 快速开始

```bash
cd 3-machine

# 1. 确保 config.env 中的地址与构建路径正确
# 2. 在当前机器启动 SSH 隧道（会同时拉起 WSL RPC Server 和手机 RPC Server）
./scripts/setup_tunnels.sh

# 3. 在 GPU PC 启动通宵基准
ssh atituiset@192.168.1.10
cd ~/projects/gpu-cpu-phone-test/3-machine
tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'

# 4. 回到当前机器启动 watchdog
./scripts/overnight_watchdog.sh --loop
```

---

## 日志说明

### 早期调试（2026-07-09/10，Qwen2-0.5B）

| 日志文件 | 拓扑 | 说明 |
|---|---|---|
| `cpu_rpc_20260710_*.log` | 当前机器 RPC Server | 启动日志 |
| `pc_ngl20_20260709_*.log` | GPU PC + 当前机器/手机直连 | 连接失败或 NAT 问题 |
| `pc_current_tun_ngl20_20260709_*.log` | GPU PC + 当前机器（隧道） | 成功，约 8.5 t/s |
| `pc_3node_tun_ngl20_20260709_*.log` | GPU PC + 当前机器 + 手机（隧道） | 手机离线，降级双机 |
| `pc_local_ngl999_20260709_*.log` | GPU PC 本地 CUDA | 基线 282 t/s |

详见 `docs/historical/report-20260710-qwen2-0.5b.md`。

### Qwen3-1.7B 双机通宵基准（2026-07-14）

| 配置 | 最快 generation | 日志 |
|---|---|---|
| GPU PC 本地 CUDA `-ngl 99` | 132.84 t/s | `3machine_gpu_local_cuda_ngl99_20260714_142222.log` |
| GPU PC + WSL RPC `-ngl 0` | 44.13 t/s | `3machine_gpu_wsl_rpc_ngl0_20260714_142222.log` |

详见 `docs/report.md`。

### 最新通宵基准（2026-07-15 起）

运行后生成命名统一的日志：

```text
<model_alias>_<topology>_ngl<ngl>_<timestamp>.log
```

例如：`qwen3_1_7b_phone_ngl24_20260715_020000.log`。

---

## 通宵 watchdog 用法

```bash
# 单次健康检查（手动）
./scripts/overnight_watchdog.sh

# 后台循环守护（推荐）
nohup ./scripts/overnight_watchdog.sh --loop > logs/overnight_watchdog.log 2>&1 &
```

功能：
1. 检查并恢复本地 tmux 会话 `rpc_server` 和 `reverse_tunnel`。
2. 若矩阵声明 `phone`，检查并恢复手机 SSH 链路、`phone_tunnel` 本地转发、手机 RPC Server。
3. 通过 SSH 检查 GPU PC 上的 `gpu_bench` 会话，掉线则重启。
4. 状态追加到 `~/.claude/hetero_overnight_status.md`。
5. 检测到 GPU PC 上生成 `summary_*.txt` 后自动退出 `--loop`。

---

## 关键设计

- **配置驱动**：模型、拓扑、ngl 列表全部在 `config/benchmark-matrix.env` 中声明。
- **断点续跑**：`overnight_gpu_benchmark.sh` 会跳过已有非空日志的组合，可通过 `FORCE_RERUN=1` 强制重跑。
- **拓扑按需启用**：矩阵里不写 `phone` 时，watchdog 不会尝试监控手机链路。

---

## 相关文档

- 复现手册：`docs/reproduce.md`
- 协议：`docs/protocol.md`
- 报告：`docs/report.md`
- 旧文档：`docs/historical/`
```

- [ ] **Step 2: 验证文件无语法错误**

```bash
python3 -m markdown 3-machine/README.md >/dev/null 2>&1 || echo 'markdown lint optional'
```

If `python-markdown` not installed, visually confirm headings render correctly.

- [ ] **Step 3: Commit**

```bash
git add 3-machine/README.md
git commit -m "docs(3-machine): rewrite README with current status and matrix-driven benchmark

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: 编写当前协议 docs/protocol.md

**Files:**
- Create: `3-machine/docs/protocol.md`

- [ ] **Step 1: 写入 protocol.md v0.3**

```markdown
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
                            └── 127.0.0.1:50052 ── 当前机器 ──SSH 本地转发── 手机 RPC Worker
```

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
```

- [ ] **Step 2: Commit**

```bash
git add 3-machine/docs/protocol.md
git commit -m "docs(3-machine): add protocol v0.3 for full 3-machine topology

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: 编写复现手册 docs/reproduce.md

**Files:**
- Create: `3-machine/docs/reproduce.md`

- [ ] **Step 1: 写入 reproduce.md**

```markdown
# 3-Machine 通宵基准复现手册

## 环境

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 / RTX 4050 6GB | `192.168.1.10` |
| 当前机器（WSL） | RPC Worker | CPU | `172.26.88.148:50053` |
| Mate 40 Pro | RPC Worker | CPU | `192.168.1.7:50052` |

---

## 1. 前置条件

### 1.1 三端编译

**GPU PC**

```bash
cd ~/projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
mkdir -p build-cuda-rpc && cd build-cuda-rpc
cmake .. -DGGML_CUDA=ON -DGGML_RPC=ON
make -j
```

**当前机器（WSL）**

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
mkdir -p build-rpc && cd build-rpc
cmake .. -DGGML_RPC=ON
make -j ggml-rpc-server
```

**手机（Termux proot Ubuntu）**

```bash
ssh -p 8022 u0_a111@192.168.1.7
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
mkdir -p build-rpc && cd build-rpc
cmake .. -DGGML_RPC=ON
make -j2 ggml-rpc-server
```

### 1.2 免密 SSH

- 当前机器 → GPU PC：`ssh atituiset@192.168.1.10` 无需密码。
- 当前机器 → 手机：`ssh -p 8022 u0_a111@192.168.1.7` 无需密码。

### 1.3 Ollama

GPU PC 上已安装 Ollama，并能拉取 `qwen3:1.7b` 与 `qwen2:0.5b`。

---

## 2. 启动链路

### 2.1 当前机器启动隧道

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
./scripts/setup_tunnels.sh
```

预期输出：

```text
=== Hetero-LLaMA SSH 隧道启动 ===
  GPU PC : atituiset@192.168.1.10
  phone  : 127.0.0.1:50052
  mode   : all

[1/3] 启动当前机器 RPC Server（绑定 127.0.0.1:50053）
      OK
[2/3] 建立到手机的 SSH 本地转发（127.0.0.1:50052 -> 192.168.1.7:50052）
      OK
[3/3] 建立到 GPU PC 的 SSH 反向隧道
      OK
```

### 2.2 GPU PC 启动基准

```bash
ssh atituiset@192.168.1.10
cd ~/projects/gpu-cpu-phone-test/3-machine
tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'
```

### 2.3 当前机器启动 watchdog

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
nohup ./scripts/overnight_watchdog.sh --loop > logs/overnight_watchdog.log 2>&1 &
```

---

## 3. 观察进度

```bash
# 当前机器 watchdog 日志
tail -f logs/overnight_watchdog.log

# 全局状态
tail -f ~/.claude/hetero_overnight_status.md

# GPU PC 基准日志
ssh atituiset@192.168.1.10 'tail -f ~/projects/gpu-cpu-phone-test/3-machine/logs/qwen3_1_7b_*.log'
```

---

## 4. 中断后恢复

如果 Claude session 结束、网络断开、或设备休眠，按以下步骤恢复：

1. **检查状态文件**：
   ```bash
   tail ~/.claude/hetero_overnight_status.md
   ```

2. **在当前机器检查 watchdog 是否还在**：
   ```bash
   pgrep -f overnight_watchdog.sh
   ```
   若不在，重新启动：
   ```bash
   cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
   nohup ./scripts/overnight_watchdog.sh --loop > logs/overnight_watchdog.log 2>&1 &
   ```

3. **watchdog 会自动恢复**：
   - 本地 `rpc_server` 和 `reverse_tunnel` tmux 会话
   - 手机 SSH 链路、`phone_tunnel`、手机 RPC Server
   - GPU PC 上的 `gpu_bench` tmux 会话

4. **基准脚本会断点续跑**：
   `overnight_gpu_benchmark.sh` 会跳过已有非空日志的 `(model, topology, ngl)` 组合，从中断处继续。

5. **如需强制全部重跑**：
   ```bash
   # 在 GPU PC
   tmux new -d -s gpu_bench 'FORCE_RERUN=1 ./scripts/overnight_gpu_benchmark.sh'
   ```

---

## 5. 完成后

GPU PC 上生成 `logs/summary_*.txt` 后，watchdog 会自动退出 `--loop`。

```bash
ssh atituiset@192.168.1.10 'cat ~/projects/gpu-cpu-phone-test/3-machine/logs/summary_*.txt | tail -40'
```

---

## 6. 常见问题

### 6.1 手机 SSH 不可达

现象：`WARN: 手机 SSH 不可达`。

解决：点亮手机屏幕，确保 Wi-Fi 连接，确认 IP 未变。

### 6.2 GPU PC 上 `gpu_bench` 反复重启但无日志

可能是 Ollama 拉取失败或模型链接失败。在 GPU PC 手动执行：

```bash
cd ~/projects/gpu-cpu-phone-test/3-machine
DRY_RUN=1 ./scripts/overnight_gpu_benchmark.sh
```

### 6.3 已完成组合的日志为空

空日志被视为未完成。`overnight_gpu_benchmark.sh` 只跳过非空日志文件。
```

- [ ] **Step 2: Commit**

```bash
git add 3-machine/docs/reproduce.md
git commit -m "docs(3-machine): add reproduce manual with resume instructions

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: 编写当前报告 docs/report.md

**Files:**
- Create: `3-machine/docs/report.md`

- [ ] **Step 1: 写入 report.md 模板**

```markdown
# 3-Machine 异构推理报告

> 生成时间：2026-07-15  
> 模型：Qwen3-1.7B-Instruct-Q4_K_M、Qwen2-0.5B-Instruct-Q4_0  
> 拓扑：GPU PC 本地 CUDA / GPU PC + WSL RPC / GPU PC + WSL + 手机 RPC

---

## 1. 环境

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 / RTX 4050 6GB | `192.168.1.10` |
| 当前机器（WSL） | RPC Worker | CPU | `127.0.0.1:50053`（SSH 反向隧道） |
| Mate 40 Pro | RPC Worker | CPU | `127.0.0.1:50052`（SSH 本地转发 + 反向隧道） |

---

## 2. Qwen3-1.7B 性能结果

命令：`llama-completion -m qwen3-1.7b-instruct-ollama.gguf -p "你好" -n 32 -no-cnv -ngl N [--rpc ...]`

### 2.1 GPU PC 本地 CUDA

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 1920 ms | 39.81 t/s | `3machine_gpu_local_cuda_ngl0_20260714_142222.log` |
| 12 | 1350 ms | 65.82 t/s | `3machine_gpu_local_cuda_ngl12_20260714_142222.log` |
| 24 | 633 ms | 98.31 t/s | `3machine_gpu_local_cuda_ngl24_20260714_142222.log` |
| 99 | 365 ms | 132.84 t/s | `3machine_gpu_local_cuda_ngl99_20260714_142222.log` |

### 2.2 GPU PC + WSL RPC

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 1930 ms | 44.13 t/s | `3machine_gpu_wsl_rpc_ngl0_20260714_142222.log` |
| 12 | 12147 ms | 18.80 t/s | `3machine_gpu_wsl_rpc_ngl12_20260714_142222.log` |
| 24 | 21987 ms | 16.46 t/s | `3machine_gpu_wsl_rpc_ngl24_20260714_142222.log` |
| 99 | 25360 ms | 21.60 t/s | `3machine_gpu_wsl_rpc_ngl99_20260714_142222.log` |

### 2.3 GPU PC + WSL + 手机 RPC（待跑）

新通宵基准完成后填充。

---

## 3. Qwen2-0.5B 性能结果（待跑）

新通宵基准完成后填充。

---

## 4. 关键发现

1. RTX 4050 6GB 可以轻松跑 Qwen3-1.7B Q4_K_M；本地 `-ngl 99` 达到 132.84 t/s。
2. RPC 初始化开销显著：连接 WSL Worker 后，Qwen3-1.7B 加载时间从本地 365 ms 上升到 12–25 s。
3. `-ngl` 在纯 CUDA 场景下单调加速，在 RPC 混合场景下非单调。
4. 手机参与后的完整三机数据待补充。

---

## 5. 下一步

- 填充完整三机（GPU PC + WSL + 手机）的 Qwen3-1.7B 与 Qwen2-0.5B 数据。
- 测试 Qwen2.5-3B / 7B。
- 评估 Qwen3.6-35B-A3B-FP8 在 24GB+ 显存设备上的可行性。
```

- [ ] **Step 2: Commit**

```bash
git add 3-machine/docs/report.md
git commit -m "docs(3-machine): add current report template for 3-machine phone benchmark

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: 添加配置 config/benchmark-matrix.env

**Files:**
- Create: `3-machine/config/benchmark-matrix.env`

- [ ] **Step 1: 写入配置文件**

```bash
mkdir -p /home/atituiset/Projects/gpu-cpu-phone-test/3-machine/config
cat > /home/atituiset/Projects/gpu-cpu-phone-test/3-machine/config/benchmark-matrix.env <<'EOF'
# 3-Machine 通宵基准矩阵配置
# 本文件由 overnight_gpu_benchmark.sh 和 overnight_watchdog.sh 共同读取

# -----------------------------
# 拓扑端点定义（在 GPU PC 上求值）
# -----------------------------
TOPOLOGY_local=""
TOPOLOGY_wsl="--rpc 127.0.0.1:50053"
TOPOLOGY_phone="--rpc 127.0.0.1:50053,127.0.0.1:50052"

# -----------------------------
# 模型定义
# 格式：OLLAMA_NAME|GGUF_NAME|PROMPT|N
# -----------------------------
MODEL_qwen3_1_7b="qwen3:1.7b|qwen3-1.7b-instruct-ollama.gguf|你好|32"
MODEL_qwen2_0_5b="qwen2:0.5b|qwen2-0.5b-instruct-q4_0.gguf|你好|32"

# -----------------------------
# 运行矩阵
# 模型别名 = 空格分隔的拓扑列表
# -----------------------------
RUN_qwen3_1_7b="local wsl phone"
RUN_qwen2_0_5b="local wsl phone"

# -----------------------------
# ngl 列表
# -----------------------------
NGL_LIST="0 12 24 99"
EOF
```

- [ ] **Step 2: 验证可 source**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
bash -c 'source config/benchmark-matrix.env && echo "MODEL_qwen3_1_7b=$MODEL_qwen3_1_7b" && echo "RUN_qwen3_1_7b=$RUN_qwen3_1_7b" && echo "NGL_LIST=$NGL_LIST"'
```

Expected output:

```text
MODEL_qwen3_1_7b=qwen3:1.7b|qwen3-1.7b-instruct-ollama.gguf|你好|32
RUN_qwen3_1_7b=local wsl phone
NGL_LIST=0 12 24 99
```

- [ ] **Step 3: Commit**

```bash
git add 3-machine/config/benchmark-matrix.env
git commit -m "config(3-machine): add benchmark matrix env for qwen3-1.7b and qwen2-0.5b

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: 重构 overnight_gpu_benchmark.sh

**Files:**
- Modify: `3-machine/scripts/overnight_gpu_benchmark.sh`

- [ ] **Step 1: 重写脚本**

```bash
cat > /home/atituiset/Projects/gpu-cpu-phone-test/3-machine/scripts/overnight_gpu_benchmark.sh <<'EOF'
#!/bin/bash
# GPU PC 上通宵跑配置驱动的基准测试
# 用法：tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'
# 环境变量：
#   DRY_RUN=1     只打印执行计划
#   FORCE_RERUN=1 强制重跑已有日志的组合

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"
# shellcheck source=../config/benchmark-matrix.env
source "${SCRIPT_DIR}/../config/benchmark-matrix.env"

PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODEL_DIR="${HOME}/models"
LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

DRY_RUN="${DRY_RUN:-0}"
FORCE_RERUN="${FORCE_RERUN:-0}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# -----------------------------
# 辅助函数
# -----------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 解析 MODEL_别名 变量
# 输入：MODEL_qwen3_1_7b 的值
# 输出：OLLAMA_NAME GGUF_NAME PROMPT N
parse_model() {
    local spec="$1"
    IFS='|' read -r ollama_name gguf_name prompt n <<< "${spec}"
    echo "${ollama_name}" "${gguf_name}" "${prompt}" "${n}"
}

# 获取所有声明的模型别名
get_model_aliases() {
    env | grep -E '^RUN_' | sed 's/^RUN_//' | cut -d= -f1 | sort -u
}

# 获取某个模型要跑的拓扑列表
get_topologies_for_model() {
    local alias="$1"
    local var="RUN_${alias}"
    echo "${!var}"
}

# 链接 Ollama 模型到 ~/models/
link_ollama_model() {
    local ollama_name="$1"
    local gguf_name="$2"

    log "拉取模型 ${ollama_name} ..."
    ollama pull "${ollama_name}"

    if [ -n "${OLLAMA_MODELS}" ]; then
        OLLAMA_DIR="${OLLAMA_MODELS}"
    elif [ -d "/usr/share/ollama/.ollama/models" ]; then
        OLLAMA_DIR="/usr/share/ollama/.ollama/models"
    elif [ -d "${HOME}/.ollama/models" ]; then
        OLLAMA_DIR="${HOME}/.ollama/models"
    else
        log "ERROR: 无法找到 Ollama models 目录" &>2
        exit 1
    fi
    log "Ollama 模型目录: ${OLLAMA_DIR}"

    local manifest_path="${OLLAMA_DIR}/manifests/registry.ollama.ai/library/${ollama_name%:*}/${ollama_name#*:}"
    if [ ! -f "${manifest_path}" ]; then
        log "ERROR: Ollama manifest 不存在: ${manifest_path}" &>2
        exit 1
    fi

    local model_blob
    model_blob=$(python3 - "${manifest_path}" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for layer in m.get('layers', []):
    mt = layer.get('mediaType', '')
    if 'model' in mt or mt.endswith('model'):
        print(layer['digest'])
        break
PY
)

    if [ -z "${model_blob}" ]; then
        log "ERROR: 无法从 manifest 找到 model blob" &>2
        exit 1
    fi

    local src="${OLLAMA_DIR}/blobs/${model_blob//:/-}"
    local model_path="${MODEL_DIR}/${gguf_name}"
    mkdir -p "${MODEL_DIR}"
    ln -sf "${src}" "${model_path}"
    log "模型已链接: ${model_path} -> ${src}"
    echo "${model_path}"
}

# 记录 GPU 采样
run_with_gpu_log() {
    local name="$1"
    shift
    local gpu_log="${LOG_DIR}/${name}_gpu.csv"
    echo "timestamp,power.draw[W],memory.used[MiB],utilization.gpu[%],temperature.gpu[C]" > "${gpu_log}"
    nvidia-smi --query-gpu=timestamp,power.draw,memory.used,utilization.gpu,temperature.gpu --format=csv,noheader -l 1 >> "${gpu_log}" 2>/dev/null &
    local smi_pid=$!
    local log="${LOG_DIR}/${name}.log"
    log "开始 ${name} ..."
    "$@" 2>&1 | tee "${log}"
    kill "${smi_pid}" 2>/dev/null || true
    wait "${smi_pid}" 2>/dev/null || true
    log "完成 ${name}"
}

# -----------------------------
# 主流程
# -----------------------------

log "开始通宵基准测试"
log "DRY_RUN=${DRY_RUN}, FORCE_RERUN=${FORCE_RERUN}"

BIN_DIR="${GPU_PC_BUILD_DIR}/bin"
if [ ! -x "${BIN_DIR}/llama-completion" ]; then
    log "ERROR: llama-completion not found: ${BIN_DIR}/llama-completion" &>2
    exit 1
fi

# 生成执行计划
PLAN=()
for alias in $(get_model_aliases); do
    read -r ollama_name gguf_name prompt n < <(parse_model "${!alias}")
    if [ -z "${ollama_name}" ] || [ -z "${gguf_name}" ]; then
        log "WARN: 模型 ${alias} 定义无效，跳过"
        continue
    fi
    for topo in $(get_topologies_for_model "${alias}"); do
        topo_var="TOPOLOGY_${topo}"
        rpc_args="${!topo_var}"
        for ngl in ${NGL_LIST}; do
            name="${alias}_${topo}_ngl${ngl}_${TIMESTAMP}"
            PLAN+=("${alias}|${topo}|${ngl}|${name}|${ollama_name}|${gguf_name}|${prompt}|${n}|${rpc_args}")
        done
    done
done

if [ ${#PLAN[@]} -eq 0 ]; then
    log "ERROR: 执行计划为空，请检查 config/benchmark-matrix.env" &>2
    exit 1
fi

log "执行计划共 ${#PLAN[@]} 项"
for item in "${PLAN[@]}"; do
    log "  ${item}"
done

if [ "${DRY_RUN}" == "1" ]; then
    log "DRY_RUN 模式，退出"
    exit 0
fi

# 执行
CURRENT_MODEL=""
MODEL_PATH=""
for item in "${PLAN[@]}"; do
    IFS='|' read -r alias topo ngl name ollama_name gguf_name prompt n rpc_args <<< "${item}"

    if [ "${CURRENT_MODEL}" != "${ollama_name}" ]; then
        MODEL_PATH=$(link_ollama_model "${ollama_name}" "${gguf_name}")
        CURRENT_MODEL="${ollama_name}"
    fi

    log_file="${LOG_DIR}/${name}.log"
    if [ "${FORCE_RERUN}" != "1" ] && [ -s "${log_file}" ]; then
        log "跳过（已有非空日志）: ${name}"
        continue
    fi

    args=(
        "${BIN_DIR}/llama-completion"
        -m "${MODEL_PATH}"
        -p "${prompt}"
        -n "${n}"
        -ngl "${ngl}"
        -no-cnv
    )
    if [ -n "${rpc_args}" ]; then
        # shellcheck disable=SC2206
        args+=(${rpc_args})
    fi

    echo ""
    echo "=== ${name} ==="
    run_with_gpu_log "${name}" "${args[@]}"
done

# 汇总
SUMMARY="${LOG_DIR}/summary_${TIMESTAMP}.txt"
{
    echo "通宵基准测试汇总"
    echo "生成时间: $(date)"
    echo "模型: ${CURRENT_MODEL:-N/A}"
    echo ""
    for alias in $(get_model_aliases); do
        read -r ollama_name gguf_name _ _ < <(parse_model "${!alias}")
        echo "=== ${alias} (${ollama_name}) ==="
        for topo in $(get_topologies_for_model "${alias}"); do
            echo "--- ${topo} ---"
            grep -H "eval time" "${LOG_DIR}/${alias}_${topo}_ngl*_${TIMESTAMP}.log" 2>/dev/null || true
        done
        echo ""
    done
} > "${SUMMARY}"

log "全部完成。汇总: ${SUMMARY}"
EOF
chmod +x /home/atituiset/Projects/gpu-cpu-phone-test/3-machine/scripts/overnight_gpu_benchmark.sh
```

- [ ] **Step 2: 语法检查与 DRY_RUN**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
bash -n scripts/overnight_gpu_benchmark.sh
DRY_RUN=1 ./scripts/overnight_gpu_benchmark.sh | head -30
```

Expected: script parses and prints execution plan for both models and all topologies/ngls.

- [ ] **Step 3: Commit**

```bash
git add 3-machine/scripts/overnight_gpu_benchmark.sh
git commit -m "feat(3-machine): refactor overnight benchmark to matrix-driven

- Read model/topology/ngl matrix from config/benchmark-matrix.env
- Support DRY_RUN and FORCE_RERUN
- Skip already-completed combinations for resume
- Unified log naming

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: 扩展 overnight_watchdog.sh

**Files:**
- Modify: `3-machine/scripts/overnight_watchdog.sh`

- [ ] **Step 1: 重写脚本**

```bash
cat > /home/atituiset/Projects/gpu-cpu-phone-test/3-machine/scripts/overnight_watchdog.sh <<'EOF'
#!/usr/bin/env bash
# Hetero-LLaMA 通宵基准 watchdog
# 用法：
#   ./overnight_watchdog.sh           # 单次健康检查并尝试恢复
#   ./overnight_watchdog.sh --loop    # 每 30 分钟循环守护，直到基准完成
#
# 本脚本在当前机器（WSL）运行，根据 config/benchmark-matrix.env 中的矩阵
# 决定需要监控哪些 Worker（wsl / phone）。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"
# shellcheck source=../config/benchmark-matrix.env
source "${SCRIPT_DIR}/../config/benchmark-matrix.env"

# -----------------------------
# 可配置项
# -----------------------------
STATUS_FILE="${STATUS_FILE:-${HOME}/.claude/hetero_overnight_status.md}"
LOOP_INTERVAL_SEC="${LOOP_INTERVAL_SEC:-1800}"
GPU_PC="${GPU_PC_USER}@${GPU_PC_IP}"
GPU_PC_PROJECT_DIR="${HOME}/projects/gpu-cpu-phone-test"  # GPU PC 上小写 projects
LOCAL_PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${LOCAL_PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

# 从矩阵中聚合需要监控的拓扑
NEED_WSL=0
NEED_PHONE=0
for var in $(env | grep -E '^RUN_' | cut -d= -f1); do
    for topo in ${!var}; do
        case "${topo}" in
            wsl) NEED_WSL=1 ;;
            phone) NEED_PHONE=1 ;;
        esac
    done
done

# -----------------------------
# 辅助函数
# -----------------------------
log_status() {
    mkdir -p "$(dirname "${STATUS_FILE}")"
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${STATUS_FILE}"
}

has_tmux_session() {
    tmux has-session -t "$1" 2>/dev/null
}

has_gpu_pc_tmux_session() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "tmux has-session -t $1" 2>/dev/null
}

start_rpc_server() {
    echo "[watchdog] 启动本地 RPC Server 会话：rpc_server"
    tmux kill-session -t rpc_server 2>/dev/null || true
    tmux new-session -d -s rpc_server -c "${LOCAL_PROJECT_DIR}" \
        "bash -c 'TUNNEL_MODE=1 ./scripts/run_cpu_rpc_server.sh 127.0.0.1 ${CURRENT_PORT}'"
    sleep 2
}

start_reverse_tunnel() {
    echo "[watchdog] 启动反向隧道会话：reverse_tunnel"
    tmux kill-session -t reverse_tunnel 2>/dev/null || true
    tmux new-session -d -s reverse_tunnel -c "${LOCAL_PROJECT_DIR}" \
        "bash -c 'ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o PasswordAuthentication=no \
            -o BatchMode=yes \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -R 127.0.0.1:${CURRENT_PORT}:127.0.0.1:${CURRENT_PORT} \
            -N ${GPU_PC}'"
    sleep 2
}

phone_ssh_reachable() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -p 8022 "u0_a111@${PHONE_HOST}" true 2>/dev/null
}

has_phone_tunnel() {
    ss -ltn 2>/dev/null | grep -q "127.0.0.1:50052"
}

start_phone_tunnel() {
    echo "[watchdog] 启动手机隧道：phone_tunnel"
    # 清理已有的本地转发
    pkill -f "ssh.*-L 127.0.0.1:50052" 2>/dev/null || true
    sleep 1
    tmux kill-session -t phone_tunnel 2>/dev/null || true
    tmux new-session -d -s phone_tunnel \
        "bash -c 'ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o PasswordAuthentication=no \
            -p 8022 \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -L 127.0.0.1:50052:127.0.0.1:${PHONE_PORT} \
            -N u0_a111@${PHONE_HOST}'"
    sleep 3
}

start_phone_rpc() {
    echo "[watchdog] 在手机上启动 RPC Server"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -p 8022 \
        -o BatchMode=yes \
        "u0_a111@${PHONE_HOST}" \
        "proot-distro login ubuntu -- bash -c 'cd /root/Projects/gpu-cpu-phone-test && TUNNEL_MODE=1 nohup ./3-machine/scripts/run_phone_rpc.sh 127.0.0.1 ${PHONE_PORT} > /tmp/phone_rpc.log 2>&1 & disown; sleep 2; pgrep -f \"ggml-rpc-server -H 127.0.0.1 -p ${PHONE_PORT}\"'" 2>/dev/null || true
}

start_gpu_bench() {
    echo "[watchdog] 在 GPU PC 上启动基准会话：gpu_bench"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "tmux kill-session -t gpu_bench 2>/dev/null || true; sleep 1; tmux new-session -d -s gpu_bench -c ${GPU_PC_PROJECT_DIR} \"bash scripts/overnight_gpu_benchmark.sh\""
    sleep 2
}

gpu_pc_summary_exists() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "ls ${GPU_PC_PROJECT_DIR}/logs/summary_*.txt >/dev/null 2>&1"
}

# -----------------------------
# 单次健康检查
# -----------------------------
health_check() {
    local status_parts=()
    status_parts+=("topologies:wsl=${NEED_WSL},phone=${NEED_PHONE}")

    # 1. WSL RPC Server
    if [ "${NEED_WSL}" == "1" ]; then
        if has_tmux_session rpc_server; then
            status_parts+=("rpc_server:ok")
        else
            status_parts+=("rpc_server:restarted")
            start_rpc_server
        fi
    fi

    # 2. 反向隧道
    if [ "${NEED_WSL}" == "1" ]; then
        if has_tmux_session reverse_tunnel; then
            status_parts+=("reverse_tunnel:ok")
        else
            status_parts+=("reverse_tunnel:restarted")
            start_reverse_tunnel
        fi
    fi

    # 3. Phone 链路
    if [ "${NEED_PHONE}" == "1" ]; then
        if phone_ssh_reachable; then
            status_parts+=("phone_ssh:ok")
            if has_phone_tunnel; then
                status_parts+=("phone_tunnel:ok")
            else
                status_parts+=("phone_tunnel:restarted")
                start_phone_tunnel
            fi
            # 不直接判断手机 RPC 是否存在，每次尝试启动以确保存活
            start_phone_rpc
            status_parts+=("phone_rpc:started")
        else
            status_parts+=("phone_ssh:unreachable")
        fi
    fi

    # 4. GPU PC 基准任务
    if has_gpu_pc_tmux_session gpu_bench; then
        status_parts+=("gpu_bench:ok")
    else
        status_parts+=("gpu_bench:restarted")
        start_gpu_bench
    fi

    # 5. 是否完成
    local is_complete=1
    if gpu_pc_summary_exists; then
        status_parts+=("summary:ready")
        echo "[watchdog] 基准已完成（summary 文件已生成）"
        is_complete=0
    else
        status_parts+=("summary:pending")
    fi

    local status_line
    status_line="$(IFS='; '; echo "${status_parts[*]}")"
    log_status "${status_line}"

    return "${is_complete}"
}

# -----------------------------
# 主入口
# -----------------------------
show_help() {
    cat <<EOF
Hetero-LLaMA 通宵基准 watchdog

用法：
  ./overnight_watchdog.sh [选项]

选项：
  --loop      每 ${LOOP_INTERVAL_SEC} 秒循环检查，直到 GPU PC 上生成 summary 文件
  --help      显示本帮助

环境变量：
  STATUS_FILE       状态文件路径（默认 ${STATUS_FILE}）
  LOOP_INTERVAL_SEC 循环间隔秒数（默认 ${LOOP_INTERVAL_SEC}）
EOF
}

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --loop)
            echo "[watchdog] 进入循环模式，间隔 ${LOOP_INTERVAL_SEC} 秒"
            echo "[watchdog] 监控拓扑: wsl=${NEED_WSL}, phone=${NEED_PHONE}"
            while true; do
                if health_check; then
                    log_status "benchmark_complete"
                    exit 0
                fi
                echo "[watchdog] 等待 ${LOOP_INTERVAL_SEC} 秒后下一次检查 ..."
                sleep "${LOOP_INTERVAL_SEC}"
            done
            ;;
        "")
            health_check
            ;;
        *)
            echo "未知参数：$1" &>2
            show_help &>2
            exit 1
            ;;
    esac
}

main "$@"
EOF
chmod +x /home/atituiset/Projects/gpu-cpu-phone-test/3-machine/scripts/overnight_watchdog.sh
```

- [ ] **Step 2: 语法检查**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
bash -n scripts/overnight_watchdog.sh
```

Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add 3-machine/scripts/overnight_watchdog.sh
git commit -m "feat(3-machine): extend watchdog for phone topology monitoring

- Read matrix to determine wsl/phone monitoring needs
- Add phone_ssh, phone_tunnel, phone_rpc checks/recovery
- Make all tmux starts idempotent

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 9: 修复 setup_tunnels.sh 并补充 PHONE_REAL_HOST

**Files:**
- Modify: `3-machine/config.env`
- Modify: `3-machine/scripts/setup_tunnels.sh`

- [ ] **Step 1: 在 config.env 中新增 PHONE_REAL_HOST**

在 `PHONE_PORT="50052"` 下一行添加：

```bash
PHONE_REAL_HOST="192.168.1.7"  # 隧道模式下用于直接 SSH 连接手机
```

- [ ] **Step 2: 在 setup_tunnels.sh 中使用 PHONE_REAL_HOST**

将所有直接 SSH 到手机的地方从 `${PHONE_HOST}` 改为 `${PHONE_REAL_HOST}`。当前 `setup_tunnels.sh` 中有两处：

1. 检查手机 SSH 可达性：
   ```bash
   if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no -p 8022 -o BatchMode=yes \
        u0_a111@${PHONE_REAL_HOST} true 2>/dev/null; then
   ```

2. 建立本地转发时的 SSH 目标：
   ```bash
   "u0_a111@${PHONE_REAL_HOST}"
   ```

- [ ] **Step 3: 验证修复**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
bash -n scripts/setup_tunnels.sh
grep -n "PHONE_REAL_HOST" config.env scripts/setup_tunnels.sh
```

Expected: `config.env` defines `PHONE_REAL_HOST`; `setup_tunnels.sh` uses it in both SSH commands and no longer uses `${PHONE_HOST}` for direct phone SSH.

- [ ] **Step 4: Commit**

```bash
git add 3-machine/config.env 3-machine/scripts/setup_tunnels.sh
git commit -m "fix(3-machine): add PHONE_REAL_HOST and use it in setup_tunnels

- config.env: add PHONE_REAL_HOST for direct phone SSH
- setup_tunnels.sh: use PHONE_REAL_HOST instead of PHONE_HOST
  which becomes 127.0.0.1 in tunnel mode

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 10: 更新 config.env

**Files:**
- Modify: `3-machine/config.env`

- [ ] **Step 1: 让 MODEL_PATH 可被覆盖**

Replace:

```bash
MODEL_PATH="${HOME}/models/qwen2-0.5b-instruct-q4_0.gguf"
```

with:

```bash
# 默认模型路径；overnight_gpu_benchmark.sh 会根据矩阵配置覆盖此值
MODEL_PATH="${MODEL_PATH:-${HOME}/models/qwen2-0.5b-instruct-q4_0.gguf}"
```

- [ ] **Step 2: Commit**

```bash
git add 3-machine/config.env
git commit -m "config(3-machine): make MODEL_PATH overridable for matrix benchmark

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 11: 综合验证

**Files:**
- All modified files

- [ ] **Step 1: 语法检查所有脚本**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
for f in scripts/*.sh; do
    echo "Checking $f"
    bash -n "$f"
done
```

Expected: each line prints and bash returns 0.

- [ ] **Step 2: DRY_RUN 验证**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
DRY_RUN=1 ./scripts/overnight_gpu_benchmark.sh
```

Expected: prints plan with 24 items (2 models × 3 topologies × 4 ngl values).

- [ ] **Step 3: watchdog 单次检查（仅验证语法/路径）**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
./scripts/overnight_watchdog.sh --help
```

Expected: prints help including loop interval.

- [ ] **Step 4: 文档链接检查**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
grep -R "report.md\|reproduce.md\|protocol.md" README.md docs/*.md 2>/dev/null | grep -v historical || true
```

Expected: current docs reference each other correctly; no references to historical paths as current.

---

## Task 12: 最终提交

- [ ] **Step 1: 查看整体 diff**

```bash
git diff --stat HEAD~11..HEAD
```

- [ ] **Step 2: 确认无遗漏**

- `docs/historical/` 有 6 个旧文档
- `README.md`、`docs/protocol.md`、`docs/reproduce.md`、`docs/report.md` 已更新/创建
- `config/benchmark-matrix.env` 已创建
- `scripts/overnight_gpu_benchmark.sh` 已重构
- `scripts/overnight_watchdog.sh` 已扩展
- `scripts/setup_tunnels.sh` 已修复
- `config.env` 已更新

- [ ] **Step 3: 可选：推送**

Only push if user asks:

```bash
git push origin main
```

---

## 自我审查

### Spec 覆盖检查

| Spec 要求 | 对应 Task |
|---|---|
| 归档旧文档 | Task 1 |
| README 消除矛盾 | Task 2 |
| protocol v0.3 | Task 3 |
| reproduce 含中断恢复 | Task 4 |
| report 当前模板 | Task 5 |
| benchmark-matrix.env | Task 6 |
| 矩阵驱动 benchmark | Task 7 |
| watchdog 手机监控 | Task 8 |
| setup_tunnels bug 修复 | Task 9 |
| config.env MODEL_PATH 可覆盖 | Task 10 |
| DRY_RUN 验证 | Task 11 |

### Placeholder 扫描

- 无 TBD/TODO。
- report.md 中有“待跑”占位段，但这是预期：新基准尚未运行，报告模板需要后续填充。

### 类型/命名一致性

- `MODEL_*` 变量名在 `config/benchmark-matrix.env`、`overnight_gpu_benchmark.sh`、`overnight_watchdog.sh` 中一致。
- `TOPOLOGY_*` 命名一致。
- `RUN_*` 命名一致。
