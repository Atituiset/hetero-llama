#!/bin/bash
# PC 端通过 RPC 调用手机进行推理
# 用法：./run_pc_rpc.sh [ngl] [提示词] [生成 token 数] [RPC host] [RPC port] [模型路径]
# 示例：
#   ./run_pc_rpc.sh 99          # 全部层 offload 到手机
#   ./run_pc_rpc.sh 10          # 只 offload 10 层
#   ./run_pc_rpc.sh 99 "你好" 32 192.168.1.7 50052 /home/atituiset/models/...

# 如果想看调度器/RPC 内部日志，执行：
#   DEBUG=1 ./run_pc_rpc.sh 99

set -e

NGL="${1:-99}"
PROMPT="${2:-你好}"
N="${3:-32}"
RPC_HOST="${4:-192.168.1.7}"
RPC_PORT="${5:-50052}"
MODEL="${6:-/home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf}"

BIN_DIR="$HOME/llama.cpp-host/build-rpc/bin"
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
