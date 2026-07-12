#!/usr/bin/env bash
# 检查 Vulkan 环境、llama.cpp 构建产物、模型路径
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_ENV="${SCRIPT_DIR}/config.env"
if [[ ! -f "${CONFIG_ENV}" ]]; then
  echo "ERROR: config.env not found at ${CONFIG_ENV}" >&2
  echo "Create it from config.env.example and fill in the required paths." >&2
  exit 1
fi

# shellcheck source=config.env
source "${CONFIG_ENV}"

err() {
  echo "ERROR: $*" >&2
  exit 1
}

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    err "$1 not found. Install vulkan-tools (on phone: also vulkan-loader + ICD)."
  fi
}

assert_var() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    err "${var_name} is not set. Add it to config.env."
  fi
}

assert_var CURRENT_LLAMA_CPP_DIR
assert_var PHONE_LLAMA_CPP_DIR
assert_var MODEL_PATH

echo "=== Vulkan 环境检查 ==="

# 1. vulkaninfo
check_cmd vulkaninfo
VULKANINFO_OUT=$(vulkaninfo --summary 2>&1) || err "vulkaninfo --summary failed; Vulkan loader/ICD may be missing"
if ! grep -Eq 'deviceName|VkPhysicalDevice' <<<"${VULKANINFO_OUT}"; then
  err "vulkaninfo --summary succeeded but no physical device was found (deviceName/VkPhysicalDevice missing). Check your Vulkan driver/ICD."
fi
echo "OK: vulkaninfo works"

# 2. build directory and binaries
HOST_TYPE="${HOST_TYPE:-$(uname -m)}"
case "${HOST_TYPE}" in
  x86_64|amd64)
    WSL_BIN="${CURRENT_LLAMA_CPP_DIR}/build-vulkan/bin/llama-completion"
    [ -x "${WSL_BIN}" ] || err "WSL Vulkan binary not found: ${WSL_BIN}"
    echo "OK: WSL Vulkan binary found: ${WSL_BIN}"
    ;;
  aarch64|arm64)
    # 手机端使用 Termux 原生编译的 Android ELF，路径以脚本所在仓库为准。
    # 如果 config.env 中的路径不存在（例如 Termux 原生 $HOME 不是 /root），
    # 则回退到脚本相对路径。
    PHONE_BIN_FALLBACK="${SCRIPT_DIR}/llama.cpp/build-vulkan/bin/llama-completion"
    PHONE_BIN="${PHONE_LLAMA_CPP_DIR}/build-vulkan/bin/llama-completion"
    [ -x "${PHONE_BIN}" ] || PHONE_BIN="${PHONE_BIN_FALLBACK}"
    [ -x "${PHONE_BIN}" ] || err "Phone Vulkan binary not found: ${PHONE_BIN}"
    echo "OK: Phone Vulkan binary found: ${PHONE_BIN}"
    ;;
  *)
    err "Unsupported architecture: ${HOST_TYPE}. Use x86_64/amd64 or aarch64/arm64. Override with HOST_TYPE=<arch>."
    ;;
esac

# 3. model
# 在 Termux 原生环境中，/root/models 要映射到 proot Ubuntu 的真实路径。
MODEL_FALLBACK="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-q4_0.gguf"
[ -f "${MODEL_PATH}" ] || MODEL_PATH="${MODEL_FALLBACK}"
[ -f "${MODEL_PATH}" ] || err "Model not found: ${MODEL_PATH}"
echo "OK: model found: ${MODEL_PATH}"

echo ""
echo "All Vulkan environment checks passed."
