#!/usr/bin/env bash
# 启动 mistral.rs 桥接 Host（在 GPU PC 上运行）
#
# 用法: ./run_bridge_host.sh <topology.yml> [model_file] [prompt]
#
# 拓扑文件定义每层的设备位置:
#   - cuda[0]: GPU 层
#   - cpu: CPU 层
#   - remote:tcp://IP:PORT: 远端 worker 层

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

TOPOLOGY="${1:?Usage: $0 <topology.yml> [model_file] [prompt]}"
MODEL_FILE="${2:-$(basename "$DEFAULT_MODEL")}"
PROMPT="${3:-$DEFAULT_PROMPT}"

MODEL_PATH="$(dirname "$DEFAULT_MODEL")/${MODEL_FILE}"

echo "=== mistral.rs Bridge Host ==="
echo "Topology:     ${TOPOLOGY}"
echo "Model:        ${MODEL_PATH}"
echo "Prompt:       ${PROMPT}"
echo "================================"

[ -f "$TOPOLOGY" ] || { echo "ERROR: Topology not found: ${TOPOLOGY}"; exit 1; }
[ -f "$MODEL_PATH" ] || { echo "ERROR: Model not found: ${MODEL_PATH}"; exit 1; }
[ -f "$MISTRALRS_BIN" ] || { echo "ERROR: Binary not found: ${MISTRALRS_BIN}"; exit 1; }

exec "${MISTRALRS_BIN}" run \
    --format gguf \
    --topology "$TOPOLOGY" \
    --model-id "$MODEL_PATH" \
    --max-seq-len 4096 \
    -i "$PROMPT"
