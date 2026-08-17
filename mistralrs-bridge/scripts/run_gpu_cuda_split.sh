#!/usr/bin/env bash
# GPU PC 单机 CUDA+CPU 分层推理
# 在 GPU PC 上执行: ./run_gpu_cuda_split.sh
#
# 层分配估算 (Qwen3.6-35B-A3B Q3_K_M, 16GB, 41层):
#   CUDA (6GB VRAM): 15层 × ~390MB ≈ 5.9GB
#   CPU (15GB RAM):  26层 × ~390MB + embedding/lm_head/KV ≈ 12GB

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

MODEL="${1:-${DEFAULT_MODEL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
CUDA_LAYERS="${3:-15}"

MODEL_DIR=$(dirname "$MODEL")
MODEL_FILE=$(basename "$MODEL")
LOGDIR="${MODE_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="${LOGDIR}/gpu_cuda${CUDA_LAYERS}_$(echo ${MODEL_FILE%%.gguf} | tr '.' '_')_${TIMESTAMP}.log"

echo "=== GPU PC CUDA+CPU Split ==="
echo "CUDA layers: ${CUDA_LAYERS}"
echo "Model:       ${MODEL_FILE}"
echo "Prompt:      ${PROMPT}"
echo "Log:         ${LOGFILE}"
echo "============================="

{
    echo "=== START $(date) ==="
    echo "CUDA layers: ${CUDA_LAYERS}"
    echo "Model: ${MODEL_DIR}/${MODEL_FILE}"
    free -h
    nvidia-smi --query-gpu=memory.used,memory.free --format=csv 2>/dev/null || echo "nvidia-smi NA"
    echo "==="

    /usr/bin/time -v "${MISTRALRS_BIN}" run \
        --format gguf \
        -m "${MODEL_DIR}" \
        -f "${MODEL_FILE}" \
        --device-layers "0:${CUDA_LAYERS}" \
        --max-seq-len 2048 \
        -i "${PROMPT}" \
        2>&1

    echo "=== END $(date) ==="
} > "${LOGFILE}" 2>&1

echo "Log saved: ${LOGFILE}"
tail -30 "${LOGFILE}"
