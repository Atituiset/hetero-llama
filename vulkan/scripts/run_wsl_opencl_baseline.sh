#!/usr/bin/env bash
# WSL OpenCL 本地推理 baseline
# 用法：./run_wsl_opencl_baseline.sh [ngl] [prompt] [n]
#
# 说明：当前 WSL2 的 Vulkan 后端无法识别 Intel 核显（仅 llvmpipe），
# 但 OpenCL 可以通过 Intel Compute Runtime 调用 GPU。本脚本使用
# llama.cpp 的 OpenCL 后端进行本地 GPU offload 推理。
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/../config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"

BIN="${CURRENT_OPENCL_BUILD_DIR}/bin/llama-completion"
MODEL="${MODEL_PATH}"

LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "${LOG_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/wsl_opencl_baseline_${TIMESTAMP}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== WSL OpenCL 本地推理 ==="
echo "  binary : ${BIN}"
echo "  model  : ${MODEL}"
echo "  ngl    : ${NGL}"
echo "  prompt : ${PROMPT}"
echo "  n      : ${N}"
echo "  log    : ${LOG_FILE}"
echo ""

if [ ! -x "${BIN}" ]; then
  echo "ERROR: ${BIN} not found or not executable" >&2
  echo "Build with:" >&2
  echo "  cd ${CURRENT_LLAMA_CPP_DIR} && cmake -B build-opencl -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF && cmake --build build-opencl --target llama-completion -j" >&2
  exit 1
fi

# -v 用于在日志中打印 layer 分配和 OpenCL 设备信息
exec "${BIN}" -m "${MODEL}" -ngl "${NGL}" -p "${PROMPT}" -n "${N}" -no-cnv -v
