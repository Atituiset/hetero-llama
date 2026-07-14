#!/usr/bin/env bash
# Hetero-LLaMA 通宵基准 watchdog
# 用法：
#   ./overnight_watchdog.sh           # 单次健康检查并尝试恢复
#   ./overnight_watchdog.sh --loop    # 每 30 分钟循环守护，直到基准完成
#
# 功能：
#   - 在当前机器（WSL）维护 tmux 会话：rpc_server、reverse_tunnel
#   - 在 GPU PC 上维护 tmux 会话：gpu_bench
#   - 自动读取最新日志并追加状态到 ~/.claude/hetero_overnight_status.md
#   - 检测到 GPU PC 上生成 summary_*.txt 后，自动退出 loop 模式
#
# 前置条件：
#   - 当前机器 -> GPU PC 已配置免密 SSH
#   - 已安装 tmux
#   - GPU PC 上存在同一份 repo：~/projects/gpu-cpu-phone-test

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"

# -----------------------------
# 可配置项
# -----------------------------
STATUS_FILE="${STATUS_FILE:-${HOME}/.claude/hetero_overnight_status.md}"
LOOP_INTERVAL_SEC="${LOOP_INTERVAL_SEC:-1800}"  # 默认 30 分钟
GPU_PC="${GPU_PC_USER}@${GPU_PC_IP}"
GPU_PC_PROJECT_DIR="${HOME}/projects/gpu-cpu-phone-test"  # GPU PC 上的路径（小写 projects）
LOCAL_PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# -----------------------------
# 辅助函数
# -----------------------------
log_status() {
    mkdir -p "$(dirname "${STATUS_FILE}")"
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${STATUS_FILE}"
}

has_tmux_session() {
    local session="$1"
    tmux has-session -t "${session}" 2>/dev/null
}

has_gpu_pc_tmux_session() {
    local session="$1"
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "tmux has-session -t ${session}" 2>/dev/null
}

start_rpc_server() {
    echo "[watchdog] 启动本地 RPC Server 会话：rpc_server"
    tmux new-session -d -s rpc_server -c "${LOCAL_PROJECT_DIR}" \
        "bash -c 'TUNNEL_MODE=1 ./scripts/run_cpu_rpc_server.sh 127.0.0.1 ${CURRENT_PORT}'"
    sleep 2
}

start_reverse_tunnel() {
    echo "[watchdog] 启动反向隧道会话：reverse_tunnel"
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

start_gpu_bench() {
    echo "[watchdog] 在 GPU PC 上启动基准会话：gpu_bench"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "tmux new-session -d -s gpu_bench -c ${GPU_PC_PROJECT_DIR} \"bash scripts/overnight_gpu_benchmark.sh\""
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

gpu_pc_recent_logs() {
    ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        "${GPU_PC}" \
        "ls -t ${GPU_PC_PROJECT_DIR}/logs/gpu_*_ngl*.log ${GPU_PC_PROJECT_DIR}/logs/summary_*.txt 2>/dev/null | head -5" 2>/dev/null
}

# -----------------------------
# 单次健康检查
# -----------------------------
health_check() {
    local status_parts=()

    # 1. 本地 RPC Server
    if has_tmux_session rpc_server; then
        status_parts+=("rpc_server:ok")
    else
        status_parts+=("rpc_server:restarted")
        start_rpc_server
    fi

    # 2. 本地反向隧道
    if has_tmux_session reverse_tunnel; then
        status_parts+=("reverse_tunnel:ok")
    else
        status_parts+=("reverse_tunnel:restarted")
        start_reverse_tunnel
    fi

    # 3. GPU PC 基准任务
    if has_gpu_pc_tmux_session gpu_bench; then
        status_parts+=("gpu_bench:ok")
    else
        status_parts+=("gpu_bench:restarted")
        start_gpu_bench
    fi

    # 4. 最近日志
    local recent_logs
    recent_logs="$(gpu_pc_recent_logs)"
    if [ -n "${recent_logs}" ]; then
        status_parts+=("recent_logs:$(echo "${recent_logs}" | tr '\n' ',' | sed 's/,$//')")
    fi

    # 5. 是否完成
    if gpu_pc_summary_exists; then
        status_parts+=("summary:ready")
        echo "[watchdog] 基准已完成（summary 文件已生成）"
        is_complete=0
    else
        status_parts+=("summary:pending")
        is_complete=1
    fi

    # 追加状态
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
