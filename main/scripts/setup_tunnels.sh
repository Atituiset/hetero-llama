#!/bin/bash
# 在当前机器启动 RPC Server 并通过 SSH 反向隧道把 Worker 暴露给 GPU PC Host
# 用法：
#   ./setup_tunnels.sh          # 同时暴露当前机器和手机 Worker
#   ./setup_tunnels.sh phone    # 仅暴露手机 Worker（假设当前机器 Worker 已单独启动）
# 前置条件：
#   - GPU PC 已配置免密 SSH 登录（当前机器 -> atituiset@192.168.1.10）
#   - 手机已配置免密 SSH 登录（当前机器 -> u0_a111@192.168.1.7 -p 8022）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${SCRIPT_DIR}/../config.env"

MODE="${1:-all}"
LOG_DIR="${HOME}/.local/log/hetero-llama"
mkdir -p "${LOG_DIR}"

TUNNEL_PID_FILE="${LOG_DIR}/tunnel_pids"
PHONE_LOCAL_PORT="50052"
PHONE_TUNNEL_ACTIVE=0

echo "=== Hetero-LLaMA SSH 隧道启动 ==="
echo "  GPU PC : ${GPU_PC_USER}@${GPU_PC_IP}"
echo "  phone  : ${PHONE_REAL_HOST}:${PHONE_PORT}"
echo "  mode   : ${MODE}"
echo ""

# 清理旧隧道
cleanup_tunnels() {
    if [ -f "${TUNNEL_PID_FILE}" ]; then
        while read -r pid; do
            kill "${pid}" 2>/dev/null || true
        done < "${TUNNEL_PID_FILE}"
        rm -f "${TUNNEL_PID_FILE}"
    fi
    # 清理可能残留的旧 RPC Server
    killall -9 ggml-rpc-server 2>/dev/null || true
}

cleanup_tunnels

start_current_rpc() {
    if [ "${MODE}" == "all" ]; then
        echo "[1/3] 启动当前机器 RPC Server（绑定 127.0.0.1:${CURRENT_PORT}）"
        TUNNEL_MODE=1 nohup "${SCRIPT_DIR}/run_cpu_rpc_server.sh" 127.0.0.1 "${CURRENT_PORT}" \
            > "${LOG_DIR}/cpu_rpc.log" 2>&1 &
        disown
        sleep 2
        if ! pgrep -f "ggml-rpc-server -H 127.0.0.1 -p ${CURRENT_PORT}" > /dev/null; then
            echo "ERROR: 当前机器 RPC Server 启动失败" >&2
            cat "${LOG_DIR}/cpu_rpc.log" >&2
            exit 1
        fi
        echo "      OK"
    fi
}

start_phone_tunnel() {
    echo "[2/3] 建立到手机的 SSH 本地转发（127.0.0.1:${PHONE_LOCAL_PORT} -> ${PHONE_REAL_HOST}:${PHONE_PORT}）"
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o PasswordAuthentication=no -p 8022 -o BatchMode=yes \
         u0_a111@${PHONE_REAL_HOST} true 2>/dev/null; then
        echo "      WARN: 手机 SSH 不可达，跳过手机隧道"
        return 0
    fi

    PHONE_TUNNEL_ACTIVE=1

    # 在手机上启动 RPC Server（绑定 127.0.0.1）
    echo "      在手机上启动 RPC Server..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no -p 8022 \
        u0_a111@${PHONE_REAL_HOST} \
        "proot-distro login ubuntu -- bash -c 'cd /root/Projects/gpu-cpu-phone-test && TUNNEL_MODE=1 nohup ./run_phone_rpc.sh 127.0.0.1 ${PHONE_PORT} > /tmp/phone_rpc.log 2>&1 & disown; sleep 2; pgrep -f \"ggml-rpc-server -H 127.0.0.1 -p ${PHONE_PORT}\"'" 2>/dev/null || true

    # 建立本地转发
    local -a ssh_args=(
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o PasswordAuthentication=no
        -p 8022
        -o ServerAliveInterval=30
        -o ServerAliveCountMax=3
        -L "127.0.0.1:${PHONE_LOCAL_PORT}:127.0.0.1:${PHONE_PORT}"
        -N
        "u0_a111@${PHONE_REAL_HOST}"
    )
    nohup ssh "${ssh_args[@]}" > "${LOG_DIR}/phone_tunnel.log" 2>&1 &
    echo $! >> "${TUNNEL_PID_FILE}"
    disown
    sleep 2

    if timeout 2 bash -c "< /dev/tcp/127.0.0.1/${PHONE_LOCAL_PORT}" 2>/dev/null; then
        echo "      OK"
    else
        echo "      WARN: 手机隧道端口未就绪"
        PHONE_TUNNEL_ACTIVE=0
    fi
}

start_reverse_tunnels() {
    echo "[3/3] 建立到 GPU PC 的 SSH 反向隧道"
    local -a reverse_args=()
    if [ "${MODE}" == "all" ]; then
        reverse_args+=(-R "127.0.0.1:${CURRENT_PORT}:127.0.0.1:${CURRENT_PORT}")
    fi
    if [ "${PHONE_TUNNEL_ACTIVE}" == "1" ]; then
        reverse_args+=(-R "127.0.0.1:${PHONE_PORT}:127.0.0.1:${PHONE_LOCAL_PORT}")
    fi

    if [ "${#reverse_args[@]}" == "0" ]; then
        echo "      无可用 Worker，跳过反向隧道"
        return 0
    fi

    local -a ssh_args=(
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o PasswordAuthentication=no
        -o ServerAliveInterval=30
        -o ServerAliveCountMax=3
        "${reverse_args[@]}"
        -N
        "${GPU_PC_USER}@${GPU_PC_IP}"
    )
    nohup ssh "${ssh_args[@]}" > "${LOG_DIR}/gpu_pc_tunnel.log" 2>&1 &
    echo $! >> "${TUNNEL_PID_FILE}"
    disown
    sleep 2

    # 在 GPU PC 上验证端口
    local check_cmd=""
    if [ "${MODE}" == "all" ]; then
        check_cmd="nc -vz 127.0.0.1 ${CURRENT_PORT} 2>&1 | head -1"
    fi
    if [ "${PHONE_TUNNEL_ACTIVE}" == "1" ]; then
        check_cmd="${check_cmd}; nc -vz 127.0.0.1 ${PHONE_PORT} 2>&1 | head -1"
    fi
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no -o BatchMode=yes \
        "${GPU_PC_USER}@${GPU_PC_IP}" "${check_cmd}" 2>/dev/null; then
        echo "      OK"
    else
        echo "      WARN: GPU PC 上部分隧道端口未就绪"
    fi
}

start_current_rpc
start_phone_tunnel
start_reverse_tunnels

echo ""
echo "隧道已建立。请在 GPU PC 执行："
echo "  TUNNEL_MODE=1 ./run_gpu_host.sh 20 \"你好\" 5"
echo ""
echo "查看日志："
echo "  tail -f ${LOG_DIR}/*.log"
