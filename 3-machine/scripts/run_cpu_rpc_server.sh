#!/bin/bash
# 当前机器启动 llama.cpp RPC Server（CPU 后端）
# 用法：./run_cpu_rpc_server.sh [host] [port]
# 如果想看 RPC 内部日志，执行：
#   DEBUG=1 ./run_cpu_rpc_server.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

HOST="${1:-${CURRENT_IP}}"
PORT="${2:-${CURRENT_PORT}}"
CACHE_DIR="${HOME}/.cache/llama.cpp/rpc"
SERVER="${CURRENT_BUILD_DIR}/bin/ggml-rpc-server"

if [ ! -x "${SERVER}" ]; then
    echo "ERROR: RPC Server not found: ${SERVER}" >&2
    echo "Please build it first:" >&2
    echo "  cd ${CURRENT_LLAMA_CPP_DIR} && mkdir -p build-rpc && cd build-rpc" >&2
    echo "  cmake .. -DGGML_RPC=ON && make -j ggml-rpc-server" >&2
    exit 1
fi

echo "=== 启动当前机器 RPC Server ==="
echo "  endpoint : ${HOST}:${PORT}"
echo "  cache    : ${CACHE_DIR}"
if [ "${DEBUG:-0}" == "1" ]; then
    echo "  debug    : enabled (GGML_RPC_DEBUG=1)"
    export GGML_RPC_DEBUG=1
fi
echo ""

# 清理可能残留的旧 RPC Server 进程，避免端口被占用
if killall -9 ggml-rpc-server 2>/dev/null; then
    echo "  已清理旧 RPC Server 进程"
    sleep 1
fi

mkdir -p "${CACHE_DIR}"
cd "$(dirname "${MODEL_PATH}")" || exit 1

exec "${SERVER}" -H "${HOST}" -p "${PORT}" -c
