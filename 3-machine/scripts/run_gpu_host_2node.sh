#!/bin/bash
# GPU PC 端通过 RPC 调用手机进行双机 RPC 推理（Phase 2）
# 用法：./run_gpu_host_2node.sh [ngl] [提示词] [生成 token 数]
# 示例：
#   ./run_gpu_host_2node.sh 24          # 全部层在本地 GPU
#   ./run_gpu_host_2node.sh 20          # 20 层 GPU，4 层分摊到 RPC worker
#   ./run_gpu_host_2node.sh 20 "你好" 5

# 如果想看调度器/RPC 内部日志，执行：
#   DEBUG=1 ./run_gpu_host_2node.sh 20

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"

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
