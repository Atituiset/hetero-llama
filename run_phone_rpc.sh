#!/bin/bash
# 手机端启动 llama.cpp RPC Server
# 用法：./run_phone_rpc.sh [host] [port]
# 如果想看 RPC 内部日志，执行：
#   DEBUG=1 ./run_phone_rpc.sh

set -e

HOST="${1:-192.168.1.7}"
PORT="${2:-50052}"
CACHE_DIR="/root/.cache/llama.cpp/rpc"
SERVER="$HOME/Projects/gpu-cpu-phone-test/llama.cpp/build-rpc/bin/ggml-rpc-server"

echo "=== 启动手机 RPC Server ==="
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
cd "$HOME/models" || exit 1

exec "${SERVER}" -H "${HOST}" -p "${PORT}" -c
