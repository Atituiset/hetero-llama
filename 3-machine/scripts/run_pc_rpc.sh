#!/bin/bash
# PC 端通过 RPC 调用 Worker 进行推理（GPU PC 作为 Host 时使用）
# 用法：./run_pc_rpc.sh [ngl] [提示词] [生成 token 数] [RPC host] [RPC port] [模型路径]
# 示例：
#   ./run_pc_rpc.sh 99          # 全部层 offload 到 Worker
#   ./run_pc_rpc.sh 10          # 只 offload 10 层
#   ./run_pc_rpc.sh 99 "你好" 32 192.168.1.7 50052 /home/atituiset/models/...

# 如果想看调度器/RPC 内部日志，执行：
#   DEBUG=1 ./run_pc_rpc.sh 99

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"

NGL="${1:-${DEFAULT_NGL}}"
PROMPT="${2:-${DEFAULT_PROMPT}}"
N="${3:-${DEFAULT_N}}"
RPC_HOST="${4:-${PHONE_HOST}}"
RPC_PORT="${5:-${PHONE_PORT}}"
MODEL="${6:-${MODEL_PATH}}"

BIN_DIR="${GPU_PC_BUILD_DIR}/bin"
LOG_ARGS=""

if [ "${DEBUG:-0}" == "1" ]; then
    export GGML_SCHED_DEBUG=1
    export GGML_RPC_DEBUG=1
    export LLAMA_ARG_LOG_VERBOSITY=5
    LOG_ARGS="--log-file /tmp/llama_rpc_debug.log"
    echo "=== PC 端 RPC 推理（DEBUG 模式） ==="
else
    echo "=== PC 端 RPC 推理 ==="
fi

echo "  model    : ${MODEL}"
echo "  rpc      : ${RPC_HOST}:${RPC_PORT}"
echo "  ngl      : ${NGL}"
echo "  prompt   : ${PROMPT}"
echo "  n        : ${N}"
if [ "${DEBUG:-0}" == "1" ]; then
    echo "  log file : /tmp/llama_rpc_debug.log"
fi
echo ""

cd "${BIN_DIR}" || exit 1
exec ./llama-completion \
  -m "${MODEL}" \
  --rpc "${RPC_HOST}:${RPC_PORT}" \
  -ngl "${NGL}" \
  -p "${PROMPT}" \
  -n "${N}" \
  ${LOG_ARGS}
