#!/bin/bash
# 手机端 Unix-domain-socket 代理
# 在 proot-distro Ubuntu 内运行，把 127.0.0.1:PHONE_PORT 桥接到 Termux 可见的 Unix socket，
# 从而绕过 Android/Termux 无法连接自身 LAN IP 的限制。
#
# 用法（在 proot 内）：
#   ./run_phone_proxy.sh
#
# 前置条件：
#   - 已安装 socat
#   - run_phone_rpc.sh 已启动并绑定 127.0.0.1:PHONE_PORT

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"

PORT="${1:-${PHONE_PORT}}"
# 必须放在 Termux 可见的路径下，这样 Termux sshd 做 local forward 时能连接到此 socket
SOCKET_DIR="/data/data/com.termux/files/home"
SOCKET_PATH="${SOCKET_DIR}/.phone_rpc_${PORT}.sock"

if ! command -v socat >/dev/null 2>&1; then
    echo "ERROR: 未找到 socat，请先安装：apt-get install -y socat" >&2
    exit 1
fi

mkdir -p "${SOCKET_DIR}"
rm -f "${SOCKET_PATH}"

echo "=== 启动手机 RPC Unix socket 代理 ==="
echo "  上游     : 127.0.0.1:${PORT}"
echo "  Unix socket : ${SOCKET_PATH}"
echo ""

# 清理旧代理
killall -9 socat 2>/dev/null || true
sleep 1

exec socat UNIX-LISTEN:"${SOCKET_PATH}",fork TCP:127.0.0.1:"${PORT}"
