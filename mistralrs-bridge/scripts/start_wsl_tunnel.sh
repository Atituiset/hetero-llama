#!/usr/bin/env bash
# 建立 WSL → GPU PC 的 SSH 反向隧道，把 GPU PC 的 127.0.0.1:5051 转发到 WSL 的 5051。
# 背景：WSL2 是 NAT 网络，GPU PC 无法直接连 WSL；桥接 host 在 GPU PC 上，
# 它连 127.0.0.1:5051 时经此隧道到达 WSL 上运行的 remote worker。
#
# 用法: ./start_wsl_tunnel.sh   （前台运行，Ctrl-C 断开；断开即桥接中断）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

echo "=== WSL → GPU PC 反向隧道 ==="
echo "GPU PC 127.0.0.1:${WSL_PORT}  →  WSL 127.0.0.1:${WSL_PORT}"
echo "保持此进程运行；Ctrl-C 断开"
echo "============================="

exec ssh -N \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -R "127.0.0.1:${WSL_PORT}:127.0.0.1:${WSL_PORT}" \
    "${GPU_PC_USER}@${GPU_PC_IP}"
