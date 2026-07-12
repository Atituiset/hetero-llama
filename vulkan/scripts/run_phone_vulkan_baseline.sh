#!/usr/bin/env bash
# 手机端 Vulkan 本地推理 baseline
# 用法：./run_phone_vulkan_baseline.sh [ngl] [prompt] [n]
#
# 注意：llama.cpp 使用 Termux 原生工具链编译，生成的是 Android ELF，
# 必须在 Termux 原生 shell（而不是 proot-distro 里的 Ubuntu）中运行。
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

# 在 Termux 原生环境中，config.env 里的 $HOME 不是 /root，
# 因此把路径锚定到本脚本所在的仓库根目录。
REPO_DIR="${SCRIPT_DIR}"
PHONE_LLAMA_CPP_DIR="${REPO_DIR}/llama.cpp"
# 模型存放在 proot Ubuntu 的 /root/models，从 Termux 原生路径访问：
PHONE_MODEL_PATH="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-q4_0.gguf"
if [ -f "${MODEL_PATH}" ]; then
  PHONE_MODEL_PATH="${MODEL_PATH}"
fi

BIN="${PHONE_LLAMA_CPP_DIR}/build-vulkan/bin/llama-completion"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/phone_vulkan_baseline_${TIMESTAMP}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== 手机 Vulkan 本地推理 ==="
echo "  binary : ${BIN}"
echo "  model  : ${PHONE_MODEL_PATH}"
echo "  ngl    : ${NGL}"
echo "  prompt : ${PROMPT}"
echo "  n      : ${N}"
echo "  log    : ${LOG_FILE}"
echo ""

if [ ! -x "${BIN}" ]; then
  echo "ERROR: ${BIN} not found or not executable" >&2
  echo "Build with:" >&2
  echo "  cd ${PHONE_LLAMA_CPP_DIR} && cmake -B build-vulkan -DGGML_VULKAN=ON && cmake --build build-vulkan --target llama-completion -j" >&2
  exit 1
fi

exec "${BIN}" -m "${PHONE_MODEL_PATH}" -ngl "${NGL}" -p "${PROMPT}" -n "${N}" -no-cnv
