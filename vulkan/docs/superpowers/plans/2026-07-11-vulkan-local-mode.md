# Vulkan Local Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Vulkan backend baseline scripts and configuration in a dedicated worktree so that both WSL and Mate 40 Pro can run local llama.cpp inference without touching the CUDA three-machine setup.

**Architecture:** Use a git worktree on branch `feat/vulkan-local`; share the existing `llama.cpp` source tree via absolute paths; add environment-check and baseline runner scripts; keep all CUDA scripts untouched.

**Tech Stack:** bash, llama.cpp Vulkan backend, cmake, vulkan-tools

---

## File Structure

All changes happen inside the worktree at `.claude/worktrees/vulkan` on branch `feat/vulkan-local`. The main repository at `feat/3-machine-inference` is not modified.

| File | Action | Responsibility |
|------|--------|----------------|
| `config.env` | Modify | Network addresses, build directories, default params for Vulkan experiment |
| `check-vulkan-env.sh` | Create | Verify `vulkaninfo`, Vulkan binaries, and model path before running |
| `run_wsl_vulkan_baseline.sh` | Create | Run `llama-completion` with Vulkan backend on WSL |
| `run_phone_vulkan_baseline.sh` | Create | Run `llama-cli` with Vulkan backend on the phone |
| `docs/vulkan-setup.md` | Create | Step-by-step environment setup and reproduction guide |

The `llama.cpp` source tree is shared with the main repository through the absolute path `${HOME}/Projects/gpu-cpu-phone-test/llama.cpp`, so no second copy of the source is needed.

---

### Task 1: Ensure worktree and branch exist

**Files:**
- Create worktree: `.claude/worktrees/vulkan`
- Branch: `feat/vulkan-local`

- [ ] **Step 1: Create branch from current `feat/3-machine-inference`**

```bash
git branch feat/vulkan-local
git worktree add .claude/worktrees/vulkan feat/vulkan-local
```

- [ ] **Step 2: Verify the worktree HEAD includes the design doc**

Run:

```bash
cd .claude/worktrees/vulkan
git log --oneline -3
ls docs/superpowers/specs/2026-07-11-vulkan-local-mode-design.md
```

Expected: the design doc exists and the latest commit is `0cf537a docs: Vulkan local/dual-device experiment design` or newer.

---

### Task 2: Update `config.env` for Vulkan mode

**Files:**
- Modify: `.claude/worktrees/vulkan/config.env`

- [ ] **Step 1: Replace the file contents with the Vulkan-specific configuration**

```bash
# Hetero-LLaMA Vulkan 双机实验配置
# 在 feat/vulkan-local 分支 / worktree 中使用

# -----------------------------
# 节点地址
# -----------------------------

# 当前机器（WSL，Vulkan Host / Worker）
CURRENT_REAL_IP="172.26.88.148"
CURRENT_IP="${CURRENT_REAL_IP}"
CURRENT_PORT="50053"

# Mate 40 Pro（Vulkan Host / Worker）
PHONE_REAL_HOST="192.168.31.177"
PHONE_HOST="${PHONE_REAL_HOST}"
PHONE_PORT="50052"

# -----------------------------
# llama.cpp 构建路径
# -----------------------------

# 当前机器上 Vulkan 本地 baseline 构建目录
CURRENT_LLAMA_CPP_DIR="${HOME}/Projects/gpu-cpu-phone-test/llama.cpp"
CURRENT_BUILD_DIR="${CURRENT_LLAMA_CPP_DIR}/build-vulkan"

# 手机上 Vulkan 本地 baseline 构建目录
PHONE_LLAMA_CPP_DIR="${HOME}/Projects/gpu-cpu-phone-test/llama.cpp"
PHONE_BUILD_DIR="${PHONE_LLAMA_CPP_DIR}/build-vulkan"

# 后续 RPC 联动时使用的构建目录
CURRENT_RPC_BUILD_DIR="${CURRENT_LLAMA_CPP_DIR}/build-vulkan-rpc"
PHONE_RPC_BUILD_DIR="${PHONE_LLAMA_CPP_DIR}/build-vulkan-rpc"

# -----------------------------
# 模型与缓存
# -----------------------------

MODEL_PATH="${HOME}/models/qwen2-0.5b-instruct-q4_0.gguf"
CACHE_DIR="${HOME}/.cache/llama.cpp/rpc"

# -----------------------------
# 默认推理参数
# -----------------------------

DEFAULT_NGL="99"
DEFAULT_PROMPT="你好"
DEFAULT_N="5"
```

- [ ] **Step 2: Verify the file loads without errors**

Run:

```bash
cd .claude/worktrees/vulkan
bash -c 'source config.env && echo "PHONE_REAL_HOST=$PHONE_REAL_HOST CURRENT_BUILD_DIR=$CURRENT_BUILD_DIR"'
```

Expected:

```text
PHONE_REAL_HOST=192.168.31.177 CURRENT_BUILD_DIR=/home/atituiset/Projects/gpu-cpu-phone-test/llama.cpp/build-vulkan
```

- [ ] **Step 3: Commit**

```bash
cd .claude/worktrees/vulkan
git add config.env
git commit -m "config(vulkan): switch config.env to Vulkan experiment"
```

---

### Task 3: Add `check-vulkan-env.sh`

**Files:**
- Create: `.claude/worktrees/vulkan/check-vulkan-env.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# 检查 Vulkan 环境、llama.cpp 构建产物、模型路径
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

err() {
  echo "ERROR: $*" >&2
  exit 1
}

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    err "$1 not found. Install vulkan-tools (on phone: also vulkan-loader + ICD)."
  fi
}

echo "=== Vulkan 环境检查 ==="

# 1. vulkaninfo
check_cmd vulkaninfo
if ! vulkaninfo --summary >/dev/null 2>&1; then
  err "vulkaninfo --summary failed; Vulkan loader/ICD may be missing"
fi
echo "OK: vulkaninfo works"

# 2. build directory and binaries
WSL_BIN="${CURRENT_LLAMA_CPP_DIR}/build-vulkan/bin/llama-completion"
PHONE_BIN="${PHONE_LLAMA_CPP_DIR}/build-vulkan/bin/llama-cli"

if [[ "$(uname -m)" == "x86_64" ]]; then
  [ -x "${WSL_BIN}" ] || err "WSL Vulkan binary not found: ${WSL_BIN}"
  echo "OK: WSL Vulkan binary found: ${WSL_BIN}"
elif [[ "$(uname -m)" == "aarch64" ]]; then
  [ -x "${PHONE_BIN}" ] || err "Phone Vulkan binary not found: ${PHONE_BIN}"
  echo "OK: Phone Vulkan binary found: ${PHONE_BIN}"
else
  err "Unsupported architecture: $(uname -m)"
fi

# 3. model
[ -f "${MODEL_PATH}" ] || err "Model not found: ${MODEL_PATH}"
echo "OK: model found: ${MODEL_PATH}"

echo ""
echo "All Vulkan environment checks passed."
```

- [ ] **Step 2: Make executable and check syntax**

```bash
cd .claude/worktrees/vulkan
chmod +x check-vulkan-env.sh
bash -n check-vulkan-env.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Run the check and expect failure because Vulkan is not yet built**

```bash
cd .claude/worktrees/vulkan
./check-vulkan-env.sh
```

Expected: fails with `ERROR: vulkaninfo not found` or `WSL Vulkan binary not found` (this proves the script catches missing environments).

- [ ] **Step 4: Commit**

```bash
cd .claude/worktrees/vulkan
git add check-vulkan-env.sh
git commit -m "feat(vulkan): add Vulkan environment check script"
```

---

### Task 4: Add `run_wsl_vulkan_baseline.sh`

**Files:**
- Create: `.claude/worktrees/vulkan/run_wsl_vulkan_baseline.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# WSL 端 Vulkan 本地推理 baseline
# 用法：./run_wsl_vulkan_baseline.sh [ngl] [prompt] [n]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

BIN="${CURRENT_LLAMA_CPP_DIR}/build-vulkan/bin/llama-completion"

echo "=== WSL Vulkan 本地推理 ==="
echo "  binary : ${BIN}"
echo "  model  : ${MODEL_PATH}"
echo "  ngl    : ${NGL}"
echo "  prompt : ${PROMPT}"
echo "  n      : ${N}"
echo ""

if [ ! -x "${BIN}" ]; then
  echo "ERROR: ${BIN} not found" >&2
  echo "Build with:" >&2
  echo "  cd ${CURRENT_LLAMA_CPP_DIR} && cmake -B build-vulkan -DGGML_VULKAN=ON && cmake --build build-vulkan -j" >&2
  exit 1
fi

cd "$(dirname "${MODEL_PATH}")" || exit 1
exec "${BIN}" -m "${MODEL_PATH}" -ngl "${NGL}" -p "${PROMPT}" -n "${N}"
```

- [ ] **Step 2: Make executable and check syntax**

```bash
cd .claude/worktrees/vulkan
chmod +x run_wsl_vulkan_baseline.sh
bash -n run_wsl_vulkan_baseline.sh
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd .claude/worktrees/vulkan
git add run_wsl_vulkan_baseline.sh
git commit -m "feat(vulkan): add WSL Vulkan baseline runner"
```

---

### Task 5: Add `run_phone_vulkan_baseline.sh`

**Files:**
- Create: `.claude/worktrees/vulkan/run_phone_vulkan_baseline.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# 手机端 Vulkan 本地推理 baseline
# 用法：./run_phone_vulkan_baseline.sh [ngl] [prompt] [n]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

BIN="${PHONE_LLAMA_CPP_DIR}/build-vulkan/bin/llama-cli"

echo "=== 手机 Vulkan 本地推理 ==="
echo "  binary : ${BIN}"
echo "  model  : ${MODEL_PATH}"
echo "  ngl    : ${NGL}"
echo "  prompt : ${PROMPT}"
echo "  n      : ${N}"
echo ""

if [ ! -x "${BIN}" ]; then
  echo "ERROR: ${BIN} not found" >&2
  echo "Build with:" >&2
  echo "  cd ${PHONE_LLAMA_CPP_DIR} && cmake -B build-vulkan -DGGML_VULKAN=ON && cmake --build build-vulkan -j" >&2
  exit 1
fi

cd "$(dirname "${MODEL_PATH}")" || exit 1
exec "${BIN}" -m "${MODEL_PATH}" -ngl "${NGL}" -p "${PROMPT}" -n "${N}"
```

- [ ] **Step 2: Make executable and check syntax**

```bash
cd .claude/worktrees/vulkan
chmod +x run_phone_vulkan_baseline.sh
bash -n run_phone_vulkan_baseline.sh
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd .claude/worktrees/vulkan
git add run_phone_vulkan_baseline.sh
git commit -m "feat(vulkan): add phone Vulkan baseline runner"
```

---

### Task 6: Add `docs/vulkan-setup.md`

**Files:**
- Create: `.claude/worktrees/vulkan/docs/vulkan-setup.md`

- [ ] **Step 1: Write the documentation**

```markdown
# Vulkan 实验环境准备

> 适用于 `feat/vulkan-local` 分支下的 WSL 和手机双机实验。

---

## WSL 端

### 1. 安装 Vulkan tools

```bash
sudo apt update
sudo apt install vulkan-tools mesa-vulkan-drivers
```

### 2. 验证 GPU 透传

```bash
vulkaninfo --summary
```

能看到物理设备（如 Intel/NVIDIA/AMD）说明宿主机 GPU 已透传到 WSL。

### 3. 编译 llama.cpp Vulkan backend

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan -j
```

### 4. 运行 baseline

```bash
cd ~/.claude/worktrees/vulkan
./check-vulkan-env.sh
./run_wsl_vulkan_baseline.sh 99 "你好" 5
```

---

## 手机端（Termux / proot Ubuntu）

### 1. 安装 Vulkan loader 和 tools

在 Termux 中：

```bash
pkg update
pkg install vulkan-tools vulkan-loader-android
```

在 proot Ubuntu 中，如果无法直接访问 ICD，可以尝试挂载 Termux 的 `/system/lib64` 和 `/vendor/lib64`，或在 proot 中安装 `mesa-vulkan-drivers`。

### 2. 验证 Vulkan

```bash
vulkaninfo --summary
```

期望看到 `Mali-G78`。

### 3. 编译 llama.cpp Vulkan backend

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan -j
```

### 4. 运行 baseline

```bash
cd ~/Projects/gpu-cpu-phone-test
./check-vulkan-env.sh
./run_phone_vulkan_baseline.sh 99 "你好" 5
```

---

## 常见问题

- **WSL 中 `vulkaninfo` 看不到设备**：确认 Windows 宿主机已安装支持 WSL 的 GPU 驱动，且 `d3d12` 适配可用。
- **手机 proot 中 `vulkaninfo` 失败**：通常是 ICD 路径或 `/dev` 节点映射问题，优先在 Termux 原生环境测试，再解决 proot 映射。
- **编译时找不到 Vulkan SDK**：安装 `libvulkan-dev`（Ubuntu）或 `vulkan-headers`（Termux）。
```

- [ ] **Step 2: Commit**

```bash
cd .claude/worktrees/vulkan
git add docs/vulkan-setup.md
git commit -m "docs(vulkan): add Vulkan setup guide"
```

---

### Task 7: Set up Vulkan on WSL

**Files:**
- None (environment-only task)

- [ ] **Step 1: Install Vulkan tools**

```bash
sudo apt update
sudo apt install -y vulkan-tools mesa-vulkan-drivers
```

- [ ] **Step 2: Verify `vulkaninfo`**

```bash
vulkaninfo --summary | head -20
```

Expected: output lists at least one physical device (GPU name or "llvmpipe").

- [ ] **Step 3: Re-run `check-vulkan-env.sh` and expect the binary check to be the next failure**

```bash
cd .claude/worktrees/vulkan
./check-vulkan-env.sh
```

Expected: passes `vulkaninfo` and model checks, then fails on missing `llama-completion` binary.

---

### Task 8: Build llama.cpp Vulkan backend on WSL

**Files:**
- Modify (build outputs): `~/Projects/gpu-cpu-phone-test/llama.cpp/build-vulkan/`

- [ ] **Step 1: Configure and build**

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan -j
```

- [ ] **Step 2: Verify the binary exists**

```bash
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-vulkan/bin/llama-completion
```

Expected: file exists and is executable.

---

### Task 9: Run WSL Vulkan baseline

**Files:**
- None (validation task)

- [ ] **Step 1: Run the check script**

```bash
cd .claude/worktrees/vulkan
./check-vulkan-env.sh
```

Expected: all checks pass.

- [ ] **Step 2: Run the baseline**

```bash
cd .claude/worktrees/vulkan
./run_wsl_vulkan_baseline.sh 99 "你好" 5
```

Expected: model loads and prints a Chinese response like `你好！有什么可以帮助你的`.

- [ ] **Step 3: Save a log**

```bash
cd .claude/worktrees/vulkan
./run_wsl_vulkan_baseline.sh 99 "你好" 5 2>&1 | tee logs/wsl_vulkan_$(date +%Y%m%d_%H%M%S).log
```

---

### Task 10: Set up Vulkan on the phone

**Files:**
- None (environment-only task, run via SSH)

- [ ] **Step 1: SSH to phone and install Vulkan tools**

```bash
ssh -p 8022 u0_a111@192.168.31.177
pkg update
pkg install -y vulkan-tools vulkan-loader-android
```

- [ ] **Step 2: Verify `vulkaninfo` in Termux**

```bash
vulkaninfo --summary | head -20
```

Expected: output lists `Mali-G78` or a Mali device.

- [ ] **Step 3: Enter proot and verify the check script passes up to binary check**

```bash
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test
./check-vulkan-env.sh
```

Expected: passes `vulkaninfo` and model checks, then fails on missing `llama-cli` binary.

---

### Task 11: Build llama.cpp Vulkan backend on the phone

**Files:**
- Modify (build outputs): `~/Projects/gpu-cpu-phone-test/llama.cpp/build-vulkan/`

- [ ] **Step 1: Build in proot Ubuntu**

```bash
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan -j
```

- [ ] **Step 2: Verify the binary exists**

```bash
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-vulkan/bin/llama-cli
```

Expected: file exists and is executable.

---

### Task 12: Run phone Vulkan baseline

**Files:**
- None (validation task)

- [ ] **Step 1: Run the check script**

```bash
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test
./check-vulkan-env.sh
```

Expected: all checks pass.

- [ ] **Step 2: Run the baseline**

```bash
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test
./run_phone_vulkan_baseline.sh 99 "你好" 5
```

Expected: model loads and prints a Chinese response.

- [ ] **Step 3: Save a log**

```bash
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test
./run_phone_vulkan_baseline.sh 99 "你好" 5 2>&1 | tee logs/phone_vulkan_$(date +%Y%m%d_%H%M%S).log
```

---

### Task 13: Final commit of all worktree changes

**Files:**
- Commit in `.claude/worktrees/vulkan`

- [ ] **Step 1: Review changes**

```bash
cd .claude/worktrees/vulkan
git status
```

Expected: only new Vulkan files and modified `config.env` are staged/committed; no changes to `setup_tunnels.sh`, `run_gpu_host.sh`, etc.

- [ ] **Step 2: Commit any remaining changes**

```bash
cd .claude/worktrees/vulkan
git add -A
git commit -m "feat(vulkan): complete local Vulkan baseline on WSL and phone"
```

- [ ] **Step 3: Verify main repository is untouched**

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test
git status
```

Expected: only the pre-existing `config.env`, `setup_tunnels.sh`, and the design doc commit are present; no Vulkan files show up in the main tree.

---

## Self-Review

- **Spec coverage:** Every section of `2026-07-11-vulkan-local-mode-design.md` is covered: worktree isolation, `config.env` update, environment check, WSL baseline, phone baseline, docs, and final commit.
- **No placeholders:** All scripts contain complete code; all commands are explicit.
- **Type consistency:** `config.env` variables (`CURRENT_LLAMA_CPP_DIR`, `PHONE_LLAMA_CPP_DIR`, `MODEL_PATH`) are used consistently across `check-vulkan-env.sh`, `run_wsl_vulkan_baseline.sh`, and `run_phone_vulkan_baseline.sh`.
- **Isolation:** Tasks repeatedly verify that the main repository `feat/3-machine-inference` remains unchanged.
