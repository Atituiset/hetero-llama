# Hetero-LLaMA 3-Machine Inference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Hetero-LLaMA from 2-machine (PC CPU + phone) to 3-machine (GPU PC CUDA + current machine CPU + phone CPU) RPC inference.

**Architecture:** GPU PC (192.168.1.10) runs `llama-completion` with CUDA backend as host; current machine and Mate 40 Pro run `ggml-rpc-server` as CPU workers. A central `config.env` drives all scripts. Two host scripts cover Phase 1 (3 workers) and Phase 2 (GPU + phone only).

**Tech Stack:** Bash, llama.cpp RPC/CUDA, Markdown docs.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `config.env` | Create | Single source of truth for IPs, ports, paths, model location |
| `run_phone_rpc.sh` | Modify | Source `config.env`; keep ability to run standalone with CLI args |
| `run_cpu_rpc_server.sh` | Create | Start `ggml-rpc-server` on current machine |
| `run_gpu_host.sh` | Create | Phase 1: GPU PC host connects to current machine + phone |
| `run_gpu_host_2node.sh` | Create | Phase 2: GPU PC host connects to phone only |
| `protocol.md` | Modify | Upgrade to v0.2, document 3-machine roles and addresses |
| `reproduce.md` | Modify | Add GPU PC CUDA build and 3-machine run steps |
| `report.md` | Modify | Add 3-machine inference results section placeholder |

---

### Task 1: Create `config.env`

**Files:**
- Create: `config.env`

- [ ] **Step 1: Write the config file**

```bash
# Hetero-LLaMA 三机推理拓扑配置
# 在所有脚本开头 source 使用

# -----------------------------
# 节点地址
# -----------------------------

# GPU PC（Host，运行 llama-completion，带 CUDA）
GPU_PC_IP="192.168.1.10"
GPU_PC_USER="Atituiset"

# Mate 40 Pro（RPC Worker，CPU 后端）
PHONE_HOST="192.168.1.7"
PHONE_PORT="50052"

# 当前机器（RPC Worker，CPU 后端）
# 多网卡/WSL 环境下请手动覆盖
CURRENT_IP="${CURRENT_IP:-$(hostname -I | awk '{print $1}')}"
CURRENT_PORT="50053"

# -----------------------------
# llama.cpp 构建路径
# -----------------------------

# GPU PC 上 CUDA + RPC 构建目录
GPU_PC_LLAMA_CPP_DIR="${HOME}/Projects/gpu-cpu-phone-test/llama.cpp"
GPU_PC_BUILD_DIR="${GPU_PC_LLAMA_CPP_DIR}/build-cuda-rpc"

# 当前机器上 RPC Server 构建目录
CURRENT_LLAMA_CPP_DIR="${HOME}/Projects/gpu-cpu-phone-test/llama.cpp"
CURRENT_BUILD_DIR="${CURRENT_LLAMA_CPP_DIR}/build-rpc"

# 手机上 RPC Server 构建目录
PHONE_LLAMA_CPP_DIR="${HOME}/Projects/gpu-cpu-phone-test/llama.cpp"
PHONE_BUILD_DIR="${PHONE_LLAMA_CPP_DIR}/build-rpc"

# -----------------------------
# 模型与缓存
# -----------------------------

MODEL_PATH="${HOME}/models/qwen2-0.5b-instruct-q4_0.gguf"
CACHE_DIR="${HOME}/.cache/llama.cpp/rpc"

# -----------------------------
# 默认推理参数
# -----------------------------

DEFAULT_NGL="20"
DEFAULT_PROMPT="你好"
DEFAULT_N="5"
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n config.env`
Expected: No output (success).

- [ ] **Step 3: Test sourcing**

Run: `source config.env && echo "PHONE=$PHONE_HOST:$PHONE_PORT CURRENT=$CURRENT_IP:$CURRENT_PORT"`
Expected: Prints `PHONE=192.168.1.7:50052 CURRENT=<detected-ip>:50053`.

- [ ] **Step 4: Commit**

```bash
git add config.env
git commit -m "feat: add central config.env for 3-machine topology

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Modify `run_phone_rpc.sh` to source `config.env`

**Files:**
- Modify: `run_phone_rpc.sh`

- [ ] **Step 1: Read current file**

Already read during design. Current hard-coded values:
- `HOST="${1:-192.168.1.7}"`
- `PORT="${2:-50052}"`
- `SERVER="$HOME/Projects/gpu-cpu-phone-test/llama.cpp/build-rpc/bin/ggml-rpc-server"`

- [ ] **Step 2: Apply the rewrite**

Replace the top of the file so it sources `config.env` and falls back to CLI args.

```bash
#!/bin/bash
# 手机端启动 llama.cpp RPC Server
# 用法：./run_phone_rpc.sh [host] [port]
# 优先级：CLI 参数 > config.env > 默认值
# 如果想看 RPC 内部日志，执行：
#   DEBUG=1 ./run_phone_rpc.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

HOST="${1:-${PHONE_HOST}}"
PORT="${2:-${PHONE_PORT}}"
CACHE_DIR="${HOME}/.cache/llama.cpp/rpc"
SERVER="${PHONE_BUILD_DIR}/bin/ggml-rpc-server"
```

Keep the rest of the file unchanged (cleanup, mkdir, exec).

- [ ] **Step 3: Validate syntax**

Run: `bash -n run_phone_rpc.sh`
Expected: No output.

- [ ] **Step 4: Dry-run help**

Run: `./run_phone_rpc.sh --help 2&1 | head -5 || true`
Expected: Script exits because `--help` is not handled; this confirms parsing does not crash before `exec`.

- [ ] **Step 5: Commit**

```bash
git add run_phone_rpc.sh
git commit -m "refactor: run_phone_rpc.sh sources config.env

Allows central configuration while preserving CLI overrides.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Create `run_cpu_rpc_server.sh`

**Files:**
- Create: `run_cpu_rpc_server.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# 当前机器启动 llama.cpp RPC Server（CPU 后端）
# 用法：./run_cpu_rpc_server.sh [host] [port]
# 如果想看 RPC 内部日志，执行：
#   DEBUG=1 ./run_cpu_rpc_server.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

HOST="${1:-${CURRENT_IP}}"
PORT="${2:-${CURRENT_PORT}}"
CACHE_DIR="${HOME}/.cache/llama.cpp/rpc"
SERVER="${CURRENT_BUILD_DIR}/bin/ggml-rpc-server"

if [ ! -x "${SERVER}" ]; then
    echo "ERROR: RPC Server not found: ${SERVER}" >&2
    echo "Please build it first:" >&2
    echo "  cd ${CURRENT_LLAMA_CPP_DIR} && mkdir -p build-rpc && cd build-rpc" >&2
    echo "  cmake .. -DGGML_RPC=ON && make -j ggml-rpc-server" >&2
    exit 1
fi

echo "=== 启动当前机器 RPC Server ==="
echo "  endpoint : ${HOST}:${PORT}"
echo "  cache    : ${CACHE_DIR}"
if [ "${DEBUG:-0}" == "1" ]; then
    echo "  debug    : enabled (GGML_RPC_DEBUG=1)"
    export GGML_RPC_DEBUG=1
fi
echo ""

# 清理可能残留的旧 RPC Server 进程，避免端口被占用
if killall -9 ggml-rpc-server 2>/dev/null; then
    echo "  已清理旧 RPC Server 进程"
    sleep 1
fi

mkdir -p "${CACHE_DIR}"
cd "$(dirname "${MODEL_PATH}")" || exit 1

exec "${SERVER}" -H "${HOST}" -p "${PORT}" -c
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n run_cpu_rpc_server.sh`
Expected: No output.

- [ ] **Step 3: Test error path when binary missing**

Run: `CURRENT_BUILD_DIR=/nonexistent ./run_cpu_rpc_server.sh 2&1 | head -3`
Expected: `ERROR: RPC Server not found: /nonexistent/bin/ggml-rpc-server`.

- [ ] **Step 4: Commit**

```bash
git add run_cpu_rpc_server.sh
git commit -m "feat: add run_cpu_rpc_server.sh for current machine worker

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Create `run_gpu_host.sh` (Phase 1: 3 workers)

**Files:**
- Create: `run_gpu_host.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# GPU PC 端通过 RPC 调用当前机器和手机进行三机推理
# 用法：./run_gpu_host.sh [ngl] [提示词] [生成 token 数]
# 示例：
#   ./run_gpu_host.sh 24          # 全部层在本地 GPU
#   ./run_gpu_host.sh 20          # 20 层 GPU，4 层分摊到两个 RPC worker
#   ./run_gpu_host.sh 20 "你好" 5

# 如果想看调度器/RPC 内部日志，执行：
#   DEBUG=1 ./run_gpu_host.sh 20

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

BIN_DIR="${GPU_PC_BUILD_DIR}/bin"
RPC_ENDPOINTS="${CURRENT_IP}:${CURRENT_PORT},${PHONE_HOST}:${PHONE_PORT}"
LOG_ARGS=""

if [ "${DEBUG:-0}" == "1" ]; then
    export GGML_SCHED_DEBUG=1
    export GGML_RPC_DEBUG=1
    export LLAMA_ARG_LOG_VERBOSITY=5
    LOG_ARGS="--log-file /tmp/llama_rpc_debug.log"
    echo "=== GPU PC 端三机 RPC 推理（DEBUG 模式） ==="
else
    echo "=== GPU PC 端三机 RPC 推理 ==="
fi

echo "  model    : ${MODEL_PATH}"
echo "  rpc      : ${RPC_ENDPOINTS}"
echo "  ngl      : ${NGL}"
echo "  prompt   : ${PROMPT}"
echo "  n        : ${N}"
if [ "${DEBUG:-0}" == "1" ]; then
    echo "  log file : /tmp/llama_rpc_debug.log"
fi
echo ""

if [ ! -x "${BIN_DIR}/llama-completion" ]; then
    echo "ERROR: llama-completion not found: ${BIN_DIR}/llama-completion" >&2
    echo "Build on GPU PC with:" >&2
    echo "  cd ${GPU_PC_LLAMA_CPP_DIR} && mkdir -p build-cuda-rpc && cd build-cuda-rpc" >&2
    echo "  cmake .. -DGGML_CUDA=ON -DGGML_RPC=ON && make -j" >&2
    exit 1
fi

cd "${BIN_DIR}" || exit 1
exec ./llama-completion \
  -m "${MODEL_PATH}" \
  --rpc "${RPC_ENDPOINTS}" \
  -ngl "${NGL}" \
  -p "${PROMPT}" \
  -n "${N}" \
  ${LOG_ARGS}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n run_gpu_host.sh`
Expected: No output.

- [ ] **Step 3: Test error path when binary missing**

Run: `GPU_PC_BUILD_DIR=/nonexistent ./run_gpu_host.sh 2&1 | head -3`
Expected: `ERROR: llama-completion not found: /nonexistent/bin/llama-completion`.

- [ ] **Step 4: Commit**

```bash
git add run_gpu_host.sh
git commit -m "feat: add run_gpu_host.sh for 3-machine Phase 1

GPU PC CUDA host connects to current machine and phone RPC workers.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Create `run_gpu_host_2node.sh` (Phase 2: GPU + phone)

**Files:**
- Create: `run_gpu_host_2node.sh`

- [ ] **Step 1: Write the script**

Identical to `run_gpu_host.sh` except `RPC_ENDPOINTS` only includes the phone.

```bash
#!/bin/bash
# GPU PC 端通过 RPC 调用手机进行双机推理（Phase 2）
# 用法：./run_gpu_host_2node.sh [ngl] [提示词] [生成 token 数]
# 示例：
#   ./run_gpu_host_2node.sh 20 "你好" 5

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

BIN_DIR="${GPU_PC_BUILD_DIR}/bin"
RPC_ENDPOINTS="${PHONE_HOST}:${PHONE_PORT}"
LOG_ARGS=""

if [ "${DEBUG:-0}" == "1" ]; then
    export GGML_SCHED_DEBUG=1
    export GGML_RPC_DEBUG=1
    export LLAMA_ARG_LOG_VERBOSITY=5
    LOG_ARGS="--log-file /tmp/llama_rpc_debug.log"
    echo "=== GPU PC 端双机 RPC 推理（DEBUG 模式） ==="
else
    echo "=== GPU PC 端双机 RPC 推理 ==="
fi

echo "  model    : ${MODEL_PATH}"
echo "  rpc      : ${RPC_ENDPOINTS}"
echo "  ngl      : ${NGL}"
echo "  prompt   : ${PROMPT}"
echo "  n        : ${N}"
if [ "${DEBUG:-0}" == "1" ]; then
    echo "  log file : /tmp/llama_rpc_debug.log"
fi
echo ""

if [ ! -x "${BIN_DIR}/llama-completion" ]; then
    echo "ERROR: llama-completion not found: ${BIN_DIR}/llama-completion" >&2
    exit 1
fi

cd "${BIN_DIR}" || exit 1
exec ./llama-completion \
  -m "${MODEL_PATH}" \
  --rpc "${RPC_ENDPOINTS}" \
  -ngl "${NGL}" \
  -p "${PROMPT}" \
  -n "${N}" \
  ${LOG_ARGS}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n run_gpu_host_2node.sh`
Expected: No output.

- [ ] **Step 3: Diff against Phase 1 script to confirm only RPC_ENDPOINTS differs**

Run: `diff run_gpu_host.sh run_gpu_host_2node.sh`
Expected: Only lines containing `RPC_ENDPOINTS` and header comments differ.

- [ ] **Step 4: Commit**

```bash
git add run_gpu_host_2node.sh
git commit -m "feat: add run_gpu_host_2node.sh for Phase 2 (GPU + phone)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Update `protocol.md` to v0.2

**Files:**
- Modify: `protocol.md`

- [ ] **Step 1: Update current version block**

Replace lines 11-16:

```markdown
## 当前版本

- **version**: v0.2
- **updated**: 2026-07-09
- **状态**: 三机拓扑版本。GPU PC 作为 Host（CUDA），当前机器与 Mate 40 Pro 作为 RPC Worker（CPU）。
```

- [ ] **Step 2: Update 后端分配约定 section**

Replace the existing backend section with:

```markdown
## 后端分配约定

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA | `192.168.1.10` |
| 当前机器 | RPC Worker | CPU | 自动检测 / 手动配置，端口 `50053` |
| Mate 40 Pro | RPC Worker | CPU | `192.168.1.7:50052` |

- GPU PC 运行 `llama-completion` / `llama-cli`，带 `-DGGML_CUDA=ON` 编译。
- 当前机器和手机运行 `ggml-rpc-server`。
- 默认手机使用 CPU 后端；Vulkan 作为后续独立阶段。
```

- [ ] **Step 3: Add address convention section**

After 后端分配约定，add:

```markdown
## 地址约定

| 节点 | 默认 IP | 默认端口 | 配置变量 |
|---|---|---|---|
| GPU PC Host | `192.168.1.10` | N/A | `GPU_PC_IP` |
| 当前机器 RPC | 自动检测 | `50053` | `CURRENT_IP`, `CURRENT_PORT` |
| Mate 40 Pro RPC | `192.168.1.7` | `50052` | `PHONE_HOST`, `PHONE_PORT` |

所有地址统一维护在 `config.env` 中。Host 通过 `--rpc` 同时连接所有 worker endpoint，格式：

```bash
--rpc <current_ip>:50053,<phone_ip>:50052
```
```

- [ ] **Step 4: Update changelog**

Append to the changelog table:

```markdown
| v0.2 | 2026-07-09 | 新增三机拓扑：GPU PC CUDA Host + 当前机器 CPU RPC + Mate 40 Pro CPU RPC | 三端 |
```

- [ ] **Step 5: Commit**

```bash
git add protocol.md
git commit -m "docs(protocol): upgrade to v0.2 for 3-machine topology

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Update `reproduce.md` with GPU PC build steps

**Files:**
- Modify: `reproduce.md`

- [ ] **Step 1: Insert GPU PC build section after Section 5.3**

Add as new Section 5.4:

```markdown
### 5.4 GPU PC 端编译 CUDA + RPC Client

#### 5.4.1 命令

```bash
# GPU PC 执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-cuda-rpc
cd build-cuda-rpc
cmake .. -DGGML_CUDA=ON -DGGML_RPC=ON
make -j
```

#### 5.4.2 关键输出

```text
-- Using CUDA backend
-- CUDA found
-- Including RPC backend
...
[100%] Built target llama-completion
```

#### 5.4.3 验证

```bash
# GPU PC 执行
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-cuda-rpc/bin/llama-completion
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-cuda-rpc/bin/ggml-rpc-server
```
```

- [ ] **Step 2: Insert 当前机器 RPC Server build section after new 5.4**

Add as Section 5.5:

```markdown
### 5.5 当前机器编译 RPC Server

```bash
# 当前机器执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-rpc
cd build-rpc
cmake .. -DGGML_RPC=ON
make -j ggml-rpc-server
```

验证：

```bash
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-rpc/bin/ggml-rpc-server
```
```

- [ ] **Step 3: Append 3-machine run section at end**

Add as Section 16:

```markdown
## 16. 三机推理运行（Phase 1）

### 16.1 当前机器启动 RPC Server

```bash
# 当前机器执行
cd ~/Projects/gpu-cpu-phone-test
./run_cpu_rpc_server.sh
```

### 16.2 手机启动 RPC Server

```bash
# 手机执行
cd ~/Projects/gpu-cpu-phone-test
./run_phone_rpc.sh
```

### 16.3 GPU PC 启动 Host

```bash
# GPU PC 执行
cd ~/Projects/gpu-cpu-phone-test
./run_gpu_host.sh 20 "你好" 5
```

### 16.4 验证三机都参与

GPU PC 日志：

```bash
grep -E "## SPLIT" /tmp/llama_rpc_debug.log
```

手机日志：

```bash
grep "graph_compute" /tmp/phone_rpc_*.log
```

当前机器日志：

```bash
grep "graph_compute" /tmp/cpu_rpc_*.log
```

## 17. Phase 2：GPU PC + 手机

停用当前机器 RPC Server，GPU PC 改用：

```bash
# GPU PC 执行
./run_gpu_host_2node.sh 20 "你好" 5
```
```

- [ ] **Step 4: Commit**

```bash
git add reproduce.md
git commit -m "docs(reproduce): add GPU PC CUDA build and 3-machine run steps

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Update `report.md` with 3-machine section placeholder

**Files:**
- Modify: `report.md`

- [ ] **Step 1: Append new section before 致谢 / License**

Insert before `## 致谢`:

```markdown
## 10. 三机推理实验（待填充）

### 10.1 实验配置

- Host: GPU PC (`192.168.1.10`)，CUDA 6GB
- RPC Worker 1: 当前机器（CPU）
- RPC Worker 2: Mate 40 Pro (`192.168.1.7`，CPU）
- 模型: Qwen2-0.5B-Instruct-Q4_0

### 10.2 运行命令

Phase 1（三机）：

```bash
# 当前机器
./run_cpu_rpc_server.sh

# 手机
./run_phone_rpc.sh

# GPU PC
./run_gpu_host.sh 20 "你好" 5
```

Phase 2（GPU + 手机）：

```bash
# 手机
./run_phone_rpc.sh

# GPU PC
./run_gpu_host_2node.sh 20 "你好" 5
```

### 10.3 性能对比（待实测）

| 配置 | prompt eval | generation | 备注 |
|---|---|---|---|
| GPU PC 本地 CUDA | - t/s | - t/s | 基线 |
| Phase 1：GPU + 当前机器 + 手机 | - t/s | - t/s | 三机 |
| Phase 2：GPU + 手机 | - t/s | - t/s | 双机 |

### 10.4 关键观察（待实测）

- `## SPLIT` 输出中应出现多个 RPC endpoint。
- 手机端 `graph_compute` 节点数应随 `-ngl` 变化。
- 当前机器端也应有 `graph_compute` 日志。
```

- [ ] **Step 2: Commit**

```bash
git add report.md
git commit -m "docs(report): add 3-machine inference results placeholder

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Final validation

**Files:**
- All modified scripts and docs

- [ ] **Step 1: Lint all shell scripts**

Run:

```bash
for f in config.env run_phone_rpc.sh run_cpu_rpc_server.sh run_gpu_host.sh run_gpu_host_2node.sh; do
  echo "Checking $f"
  bash -n "$f"
done
```

Expected: No output for all files.

- [ ] **Step 2: Verify executable bits**

Run:

```bash
chmod +x run_phone_rpc.sh run_cpu_rpc_server.sh run_gpu_host.sh run_gpu_host_2node.sh
ls -l run_*.sh config.env
```

Expected: All four `.sh` files have `x` permission; `config.env` does not need it.

- [ ] **Step 3: Confirm git status**

Run: `git status --short`
Expected: Clean working tree (all changes committed).

- [ ] **Step 4: Commit permission fix if needed**

```bash
git add run_*.sh config.env
git commit -m "chore: ensure new scripts are executable

Co-Authored-By: Claude <noreply@anthropic.com>" || echo "No permission changes to commit"
```

---

## Self-Review Checklist

| Spec Section | Implementing Task | Notes |
|---|---|---|
| 2.1 角色分配（GPU Host + 2 workers） | Task 1, 4, 5 | `config.env` + two host scripts |
| 2.2 两阶段落地 | Task 4, 5 | `run_gpu_host.sh` and `run_gpu_host_2node.sh` |
| 3. 网络与地址 | Task 1 | `config.env` |
| 4. 文件变更计划 | All tasks | Covered |
| 5. 编译配置 | Task 7 | `reproduce.md` Section 5.4/5.5 |
| 6. 分层调度策略 | Task 4, 5, 8 | `-ngl` args + report placeholder |
| 7. 运行流程 | Task 7 | `reproduce.md` Section 16/17 |
| 8. 协议升级 | Task 6 | `protocol.md` v0.2 |
| 9. 风险与回退 | N/A | Documented in spec |
| 10. 成功标准 | Task 9 | Validation steps |
| 11. 后续可扩展 | N/A | Documented in spec |

**Placeholder scan:** All code blocks contain complete commands; no TBD/TODO.

**Type consistency:** All scripts source the same `config.env` and use identical variable names (`CURRENT_IP`, `PHONE_HOST`, `GPU_PC_BUILD_DIR`, etc.).

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-09-hetero-llama-3-machine-plan.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
