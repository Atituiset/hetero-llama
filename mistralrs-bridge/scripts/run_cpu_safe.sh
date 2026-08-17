#!/usr/bin/env bash
# CPU-only 推理安全包装 — 带内存限制和完整日志
# 用法: ./run_cpu_safe.sh <model> <prompt>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

MODEL="${1:-${DEFAULT_MODEL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"

MODEL_DIR=$(dirname "$MODEL")
MODEL_FILE=$(basename "$MODEL")
LOGDIR="${MODE_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="${LOGDIR}/cpu_only_${MODEL_FILE%%.gguf}_${TIMESTAMP}.log"

echo "=== CPU-only Safe Run ==="
echo "Model:      ${MODEL_FILE}"
echo "Prompt:     ${PROMPT}"
echo "Log:        ${LOGFILE}"
echo "Memory:     $(free -h | awk '/Mem:/{print $7" available"}')"
echo "========================="

# Safety: limit virtual memory to prevent hard OOM (14GB cap = total RAM - 1GB system)
ulimit -v 14680064 2>/dev/null || echo "Warning: ulimit -v not supported (WSL?)"

# Reduce KV cache to f16 to save memory
export MISTRALRS_CPU_KV_F32=0

{
    echo "=== START $(date) ==="
    echo "Model: ${MODEL_DIR}/${MODEL_FILE}"
    echo "Prompt: ${PROMPT}"
    echo "Memory before:"
    free -h
    echo "==="

    /usr/bin/time -v "${MISTRALRS_BIN}" run \
        --format gguf \
        -m "${MODEL_DIR}" \
        -f "${MODEL_FILE}" \
        --max-seq-len 2048 \
        -i "${PROMPT}" \
        2>&1

    RC=$?
    echo "=== Exit code: ${RC} ==="
    echo "Memory after:"
    free -h
    echo "=== END $(date) ==="
} > "${LOGFILE}" 2>&1

echo "Log saved: ${LOGFILE}"
tail -20 "${LOGFILE}"
