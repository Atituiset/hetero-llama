#!/usr/bin/env bash
# 在 Mate 40 Pro 上运行 MNN LLM baseline（CPU / OpenCL / Vulkan）
# 用法：run_phone_mnn_baseline.sh [cpu|opencl|vulkan] [prompt] [n-repeat]
# 必须在 Termux 原生 shell 中运行。
set -e

BACKEND="${1:-cpu}"
PROMPT="${2:-hello}"
REPEAT="${3:-1}"

MODEL_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn"
MNN_BUILD_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/MNN"
PROMPT_FILE="/data/data/com.termux/files/home/mnn_prompt.txt"

printf "%s" "${PROMPT}" > "${PROMPT_FILE}"

case "${BACKEND}" in
  cpu)
    CONFIG="${MODEL_DIR}/config.json"
    BUILD="${MNN_BUILD_DIR}/build-opencl-llm"  # CPU binary also linked here
    ;;
  opencl)
    CONFIG="${MODEL_DIR}/config.opencl.normal.json"
    BUILD="${MNN_BUILD_DIR}/build-opencl-llm"
    ;;
  vulkan)
    CONFIG="${MODEL_DIR}/config.vulkan.json"
    BUILD="${MNN_BUILD_DIR}/build-vulkan-llm"
    ;;
  *)
    echo "Usage: $0 [cpu|opencl|vulkan] [prompt] [repeat]" >&2
    exit 1
    ;;
esac

BIN="${BUILD}/llm_demo"
if [ ! -x "${BIN}" ]; then
    echo "ERROR: ${BIN} not found. Build it first." >&2
    exit 1
fi

cd "${BUILD}"
mkdir -p tmp

for i in $(seq 1 "${REPEAT}"); do
    echo "=== Run ${i}/${REPEAT}: backend=${BACKEND} ==="
    time LD_LIBRARY_PATH=./OFF "${BIN}" "${CONFIG}" "${PROMPT_FILE}"
done
