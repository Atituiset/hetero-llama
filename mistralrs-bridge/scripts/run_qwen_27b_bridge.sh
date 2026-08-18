#!/usr/bin/env bash
# Qwen 27B 三段跨机桥接一键启动（在 WSL 上运行）
#
# 拓扑: 0-11 cuda(GPU PC) + 12-48 cpu(GPU PC) + 49-63 remote(WSL)
# 顺序: WSL worker -> SSH 反向隧道 -> GPU PC host 推理
#
# 用法: ./run_qwen_27b_bridge.sh [model_tag] [prompt]
#   model_tag: 3.6 (默认, Qwen3.6-27B) | 3.8 (Qwen3.8-27B)
# 日志: logs/bridge_27b_<tag>_<timestamp>.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

TAG="${1:-3.6}"
PROMPT="${2:-$DEFAULT_PROMPT}"

case "${TAG}" in
    3.6) MODEL_FILE="Qwen_Qwen3.6-27B-Q3_K_M.gguf"; TOPOLOGY="${MODE_DIR}/topologies/qwen36_27b_bridge.yml" ;;
    3.8) MODEL_FILE="Qwen3.8-27B-Q3_K_M.gguf";       TOPOLOGY="${MODE_DIR}/topologies/qwen38_27b_bridge.yml" ;;
    *) echo "ERROR: unknown model tag '${TAG}' (use 3.6 or 3.8)"; exit 1 ;;
esac

TS="$(date +%Y%m%d_%H%M%S)"
LOG="${MODE_DIR}/logs/bridge_27b_${TAG}_${TS}.log"
GPU_PC_TOPO="/tmp/$(basename "${TOPOLOGY}")"
GPU_PC_BIN="${GPU_PC_MISTRALRS_DIR}/target/release/mistralrs"

echo "=== Qwen${TAG}-27B 三段桥接 ==="
echo "Model:   ${MODEL_FILE}"
echo "Prompt:  ${PROMPT}"
echo "Log:     ${LOG}"
echo "============================="

for f in "${HOME}/models/${MODEL_FILE}"; do
    [ -f "$f" ] || { echo "ERROR: WSL 缺模型文件: $f"; exit 1; }
done
ssh "${GPU_PC_USER}@${GPU_PC_IP}" "[ -f ~/models/${MODEL_FILE} ]" \
    || { echo "ERROR: GPU PC 缺模型文件: ~/models/${MODEL_FILE}"; exit 1; }

# 1. WSL remote worker（49-63 层，后台）
echo "[1/4] 启动 WSL remote worker (layers 49-63)..."
"${SCRIPT_DIR}/run_remote_worker.sh" "${MODEL_FILE}" "127.0.0.1:${WSL_PORT}" "49-63" \
    > "${MODE_DIR}/logs/worker_27b_${TAG}_${TS}.log" 2>&1 &
WORKER_PID=$!
trap 'kill ${WORKER_PID} ${TUNNEL_PID:-} 2>/dev/null || true' EXIT

# 2. SSH 反向隧道（WSL2 NAT 绕过，后台）
echo "[2/4] 建立 WSL -> GPU PC 反向隧道..."
"${SCRIPT_DIR}/start_wsl_tunnel.sh" > "${MODE_DIR}/logs/tunnel_${TS}.log" 2>&1 &
TUNNEL_PID=$!

# 等 worker 加载完（约 15 层 ~3.4GB）：探测本地 5051 端口
echo "[3/4] 等待 worker 就绪..."
for i in $(seq 1 90); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${WSL_PORT}") 2>/dev/null; then
        exec 3>&- 3<&-
        break
    fi
    sleep 5
done

# 3. 拓扑传到 GPU PC（/tmp 重启会丢，每次都重新 scp）
scp -q "${TOPOLOGY}" "${GPU_PC_USER}@${GPU_PC_IP}:${GPU_PC_TOPO}"

# 4. GPU PC host 推理（前台，输出进日志）
echo "[4/4] GPU PC host 推理..."
ssh "${GPU_PC_USER}@${GPU_PC_IP}" \
    "${GPU_PC_BIN} run --format gguf --topology ${GPU_PC_TOPO} -m ~/models -f ${MODEL_FILE} --max-seq-len 2048 -i '${PROMPT}'" \
    2>&1 | tee "${LOG}"

echo "=== 完成，日志: ${LOG} ==="
