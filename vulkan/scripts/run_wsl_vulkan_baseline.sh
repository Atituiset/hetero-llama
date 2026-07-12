#!/usr/bin/env bash
# WSL 端 Vulkan 本地推理 baseline
# 用法：./run_wsl_vulkan_baseline.sh [ngl] [prompt] [n]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/../config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

BIN="${CURRENT_LLAMA_CPP_DIR}/build-vulkan/bin/llama-completion"

LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "${LOG_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/wsl_vulkan_baseline_${TIMESTAMP}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== WSL Vulkan 本地推理 ==="
echo "  binary : ${BIN}"
echo "  model  : ${MODEL_PATH}"
echo "  ngl    : ${NGL}"
echo "  prompt : ${PROMPT}"
echo "  n      : ${N}"
echo "  log    : ${LOG_FILE}"
echo ""

if [ ! -x "${BIN}" ]; then
  echo "ERROR: ${BIN} not found or not executable" >&2
  echo "Build with:" >&2
  echo "  cd ${CURRENT_LLAMA_CPP_DIR} && cmake -B build-vulkan -DGGML_VULKAN=ON && cmake --build build-vulkan -j" >&2
  exit 1
fi

exec "${BIN}" -m "${MODEL_PATH}" -ngl "${NGL}" -p "${PROMPT}" -n "${N}"
