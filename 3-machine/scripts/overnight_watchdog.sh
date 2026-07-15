#!/usr/bin/env bash
# Hetero-LLaMA 通宵基准 watchdog
# 用法：
#   ./overnight_watchdog.sh           # 单次健康检查并尝试恢复
#   ./overnight_watchdog.sh --loop    # 每 30 分钟循环守护，直到基准完成
#
# 本脚本在当前机器（WSL）运行，根据 config/benchmark-matrix.env 中的矩阵
# 决定需要监控哪些 Worker（wsl / phone）。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"
# shellcheck source=../config/benchmark-matrix.env
source "${SCRIPT_DIR}/../config/benchmark-matrix.env"

# -----------------------------
# 可配置项
# -----------------------------
STATUS_FILE="${STATUS_FILE:-${HOME}/.claude/hetero_overnight_status.md}"
LOOP_INTERVAL_SEC="${LOOP_INTERVAL_SEC:-1800}"
GPU_PC="${GPU_PC_USER}@${GPU_PC_IP}"
GPU_PC_PROJECT_DIR="${HOME}/projects/gpu-cpu-phone-test"
LOCAL_PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${LOCAL_PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

# 从矩阵中聚合需要监控的拓扑
NEED_WSL=0
NEED_PHONE=0
for var in $(env | grep -E '^RUN_' | cut -d= -f1); do
    for topo in ${!var}; do
        case "${topo}" in
            wsl) NEED_WSL=1 ;;
            phone) NEED_PHONE=1 ;;
        esac
    done
done

# -----------------------------
# 辅助函数
# -----------------------------
log_status() {
    mkdir -p "$(dirname "${STATUS_FILE}")"
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${STATUS_FILE}"
}

has_tmux_session() {
    tmux has-session -t "$1" 2>/dev/null
}

has_gpu_pc_tmux_session() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "tmux has-session -t $1" 2>/dev/null
}

start_rpc_server() {
    echo "[watchdog] 启动本地 RPC Server 会话：rpc_server"
    tmux kill-session -t rpc_server 2>/dev/null || true
    tmux new-session -d -s rpc_server -c "${LOCAL_PROJECT_DIR}" \
        "bash -c 'TUNNEL_MODE=1 ./scripts/run_cpu_rpc_server.sh 127.0.0.1 ${CURRENT_PORT}'"
    sleep 2
}

start_reverse_tunnel() {
    echo "[watchdog] 启动反向隧道会话：reverse_tunnel"
    tmux kill-session -t reverse_tunnel 2>/dev/null || true
    tmux new-session -d -s reverse_tunnel -c "${LOCAL_PROJECT_DIR}" \
        "bash -c 'ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o PasswordAuthentication=no \
            -o BatchMode=yes \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -R 127.0.0.1:${CURRENT_PORT}:127.0.0.1:${CURRENT_PORT} \
            -N ${GPU_PC}'"
    sleep 2
}

phone_ssh_reachable() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -p 8022 "u0_a111@${PHONE_REAL_HOST}" true 2>/dev/null
}

has_phone_tunnel() {
    ss -ltn 2>/dev/null | grep -q "127.0.0.1:50052"
}

start_phone_tunnel() {
    echo "[watchdog] 启动手机隧道：phone_tunnel"
    pkill -f "ssh.*-L 127.0.0.1:50052" 2>/dev/null || true
    sleep 1
    tmux kill-session -t phone_tunnel 2>/dev/null || true
    tmux new-session -d -s phone_tunnel \
        "bash -c 'ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o PasswordAuthentication=no \
            -p 8022 \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -L 127.0.0.1:50052:127.0.0.1:${PHONE_PORT} \
            -N u0_a111@${PHONE_REAL_HOST}'"
    sleep 3
}

start_phone_rpc() {
    echo "[watchdog] 在手机上启动 RPC Server"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -p 8022 \
        -o BatchMode=yes \
        "u0_a111@${PHONE_REAL_HOST}" \
        "proot-distro login ubuntu -- bash -c 'cd /root/Projects/gpu-cpu-phone-test && TUNNEL_MODE=1 nohup ./3-machine/scripts/run_phone_rpc.sh 127.0.0.1 ${PHONE_PORT} > /tmp/phone_rpc.log 2>&1 & disown; sleep 2; pgrep -f \"ggml-rpc-server -H 127.0.0.1 -p ${PHONE_PORT}\"'" 2>/dev/null || true
}

start_gpu_bench() {
    echo "[watchdog] 在 GPU PC 上启动基准会话：gpu_bench"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "tmux kill-session -t gpu_bench 2>/dev/null || true; sleep 1; tmux new-session -d -s gpu_bench -c ${GPU_PC_PROJECT_DIR} \"bash scripts/overnight_gpu_benchmark.sh\""
    sleep 2
}

gpu_pc_summary_exists() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "ls ${GPU_PC_PROJECT_DIR}/logs/summary_*.txt >/dev/null 2>&1"
}

# -----------------------------
# 单次健康检查
# -----------------------------
health_check() {
    local status_parts=()
    status_parts+=("topologies:wsl=${NEED_WSL},phone=${NEED_PHONE}")

    # 1. WSL RPC Server
    if [ "${NEED_WSL}" == "1" ]; then
        if has_tmux_session rpc_server; then
            status_parts+=("rpc_server:ok")
        else
            status_parts+=("rpc_server:restarted")
            start_rpc_server
        fi
    fi

    # 2. 反向隧道
    if [ "${NEED_WSL}" == "1" ]; then
        if has_tmux_session reverse_tunnel; then
            status_parts+=("reverse_tunnel:ok")
        else
            status_parts+=("reverse_tunnel:restarted")
            start_reverse_tunnel
        fi
    fi

    # 3. Phone 链路
    if [ "${NEED_PHONE}" == "1" ]; then
        if phone_ssh_reachable; then
            status_parts+=("phone_ssh:ok")
            if has_phone_tunnel; then
                status_parts+=("phone_tunnel:ok")
            else
                status_parts+=("phone_tunnel:restarted")
                start_phone_tunnel
            fi
            start_phone_rpc
            status_parts+=("phone_rpc:started")
        else
            status_parts+=("phone_ssh:unreachable")
        fi
    fi

    # 4. GPU PC 基准任务
    if has_gpu_pc_tmux_session gpu_bench; then
        status_parts+=("gpu_bench:ok")
    else
        status_parts+=("gpu_bench:restarted")
        start_gpu_bench
    fi

    # 5. 是否完成
    local is_complete=1
    if gpu_pc_summary_exists; then
        status_parts+=("summary:ready")
        echo "[watchdog] 基准已完成（summary 文件已生成）"
        is_complete=0
    else
        status_parts+=("summary:pending")
    fi

    local status_line
    status_line="$(IFS='; '; echo "${status_parts[*]}")"
    log_status "${status_line}"

    return "${is_complete}"
}

# -----------------------------
# 主入口
# -----------------------------
show_help() {
    cat <<EOF
Hetero-LLaMA 通宵基准 watchdog

用法：
  ./overnight_watchdog.sh [选项]

选项：
  --loop      每 ${LOOP_INTERVAL_SEC} 秒循环检查，直到 GPU PC 上生成 summary 文件
  --help      显示本帮助

环境变量：
  STATUS_FILE       状态文件路径（默认 ${STATUS_FILE}）
  LOOP_INTERVAL_SEC 循环间隔秒数（默认 ${LOOP_INTERVAL_SEC}）
EOF
}

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --loop)
            echo "[watchdog] 进入循环模式，间隔 ${LOOP_INTERVAL_SEC} 秒"
            echo "[watchdog] 监控拓扑: wsl=${NEED_WSL}, phone=${NEED_PHONE}"
            while true; do
                if health_check; then
                    log_status "benchmark_complete"
                    exit 0
                fi
                echo "[watchdog] 等待 ${LOOP_INTERVAL_SEC} 秒后下一次检查 ..."
                sleep "${LOOP_INTERVAL_SEC}"
            done
            ;;
        "")
            health_check
            ;;
        *)
            echo "未知参数：$1" >&2
            show_help >&2
            exit 1
            ;;
    esac
}

main "$@"
