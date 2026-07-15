#!/bin/bash
# 手机端启动 llama.cpp RPC Server（在 proot-distro Ubuntu 内运行）
# 用法：./run_phone_rpc.sh [host] [port]
# 优先级：CLI 参数 > config.env > 默认值
# 在隧道模式下，推荐绑定 proot 内的 127.0.0.1，配合 run_phone_proxy.sh 暴露给 Termux。
# 如果想看 RPC 内部日志，执行：
#   DEBUG=1 ./run_phone_rpc.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"

# 默认绑定 proot 内的 127.0.0.1，避免 Android/Termux 无法访问自身 LAN IP 的问题
HOST="${1:-${PHONE_BIND_HOST:-127.0.0.1}}"
PORT="${2:-${PHONE_PORT}}"
CACHE_DIR="${HOME}/.cache/llama.cpp/rpc"
SERVER="${PHONE_BUILD_DIR}/bin/ggml-rpc-server"

if [ ! -x "${SERVER}" ]; then
    echo "ERROR: 找不到手机 RPC Server：${SERVER}" >&2
    echo "请先在手机 proot 环境中编译 llama.cpp（RPC Server 后端）。" >&2
    exit 1
fi

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
