#!/bin/bash
# 在 GPU PC 上通宵跑 GPU 基线 + WSL RPC 基线
# 用法：tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'

set -e

PROJECT_DIR="${HOME}/projects/gpu-cpu-phone-test"
MODEL_DIR="${HOME}/models"
LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

OLLAMA_MODEL="qwen3:1.7b"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始通宵基准测试"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 拉取模型 ${OLLAMA_MODEL} ..."
ollama pull "${OLLAMA_MODEL}"

# 自动探测 Ollama 模型目录（系统服务 vs 用户模式）
if [ -n "${OLLAMA_MODELS}" ]; then
    OLLAMA_DIR="${OLLAMA_MODELS}"
elif [ -d "/usr/share/ollama/.ollama/models" ]; then
    OLLAMA_DIR="/usr/share/ollama/.ollama/models"
elif [ -d "${HOME}/.ollama/models" ]; then
    OLLAMA_DIR="${HOME}/.ollama/models"
else
    echo "ERROR: 无法找到 Ollama models 目录" >&2
    exit 1
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ollama 模型目录: ${OLLAMA_DIR}"

MANIFEST="${OLLAMA_DIR}/manifests/registry.ollama.ai/library/qwen3/1.7b"
if [ ! -f "${MANIFEST}" ]; then
    echo "ERROR: Ollama manifest 不存在: ${MANIFEST}" >&2
    exit 1
fi

MODEL_BLOB=$(python3 - "${MANIFEST}" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for layer in m.get('layers', []):
    mt = layer.get('mediaType', '')
    if 'model' in mt or mt.endswith('model'):
        print(layer['digest'])
        break
PY
)

if [ -z "${MODEL_BLOB}" ]; then
    echo "ERROR: 无法从 manifest 找到 model blob" >&2
    exit 1
fi

SRC="${OLLAMA_DIR}/blobs/${MODEL_BLOB//:/-}"
MODEL_NAME="qwen3-1.7b-instruct-ollama.gguf"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"
mkdir -p "${MODEL_DIR}"
ln -sf "${SRC}" "${MODEL_PATH}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 模型已链接: ${MODEL_PATH} -> ${SRC}"

BIN_DIR="${PROJECT_DIR}/llama.cpp/build-cuda-rpc/bin"
PROMPT="你好"
N=32

run_with_gpu_log() {
    local name=$1
    shift
    local gpu_log="${LOG_DIR}/${name}_gpu.csv"
    echo "timestamp,power.draw[W],memory.used[MiB],utilization.gpu[%],temperature.gpu[C]" > "${gpu_log}"
    nvidia-smi --query-gpu=timestamp,power.draw,memory.used,utilization.gpu,temperature.gpu --format=csv,noheader -l 1 >> "${gpu_log}" 2>/dev/null &
    local smi_pid=$!
    local log="${LOG_DIR}/${name}.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始 ${name} ..."
    "$@" 2>&1 | tee "${log}"
    kill "${smi_pid}" 2>/dev/null || true
    wait "${smi_pid}" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 完成 ${name}"
}

# GPU PC 本地 CUDA 基线
echo ""
echo "=== GPU PC 本地 CUDA 基线 ==="
for ngl in 0 12 24 99; do
    run_with_gpu_log "gpu_local_ngl${ngl}" \
        "${BIN_DIR}/llama-completion" -m "${MODEL_PATH}" -p "${PROMPT}" -n "${N}" -ngl "${ngl}" -no-cnv
done

# GPU PC + WSL RPC 双机基线（通过反向隧道 127.0.0.1:50053）
echo ""
echo "=== GPU PC + WSL RPC 双机基线 ==="
for ngl in 0 12 24 99; do
    run_with_gpu_log "gpu_rpc_ngl${ngl}" \
        "${BIN_DIR}/llama-completion" -m "${MODEL_PATH}" --rpc "127.0.0.1:50053" -p "${PROMPT}" -n "${N}" -ngl "${ngl}" -no-cnv
done

# 汇总
SUMMARY="${LOG_DIR}/summary_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "通宵基准测试汇总"
    echo "生成时间: $(date)"
    echo "模型: ${MODEL_PATH}"
    echo ""
    echo "=== GPU PC 本地 CUDA ==="
    grep -H "eval time" "${LOG_DIR}"/gpu_local_ngl*.log 2>/dev/null || true
    echo ""
    echo "=== GPU PC + WSL RPC ==="
    grep -H "eval time" "${LOG_DIR}"/gpu_rpc_ngl*.log 2>/dev/null || true
} > "${SUMMARY}"

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 全部完成。汇总: ${SUMMARY}"
