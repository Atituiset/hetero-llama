#!/usr/bin/env bash
# 启动 mistral.rs TCP remote worker（在 WSL 或手机上运行）
#
# 用法: ./run_remote_worker.sh [model_file] [listen_addr] [layers]
# 默认: qwen2-0.5b, 0.0.0.0:5051, "0-0"（全部层）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

MODEL_FILE="${1:-$(basename "$DEFAULT_MODEL")}"
LISTEN_ADDR="${2:-0.0.0.0:${WSL_PORT}}"
LAYERS="${3:-0-0}"

MODEL_PATH="$(dirname "$DEFAULT_MODEL")/${MODEL_FILE}"

echo "=== mistral.rs Remote Worker ==="
echo "Model:        ${MODEL_PATH}"
echo "Listen:       ${LISTEN_ADDR}"
echo "Layers:       ${LAYERS}"
echo "Binary:       ${MISTRALRS_BIN}"
echo "================================"

[ -f "$MODEL_PATH" ] || { echo "ERROR: Model not found: ${MODEL_PATH}"; exit 1; }
[ -f "$MISTRALRS_BIN" ] || { echo "ERROR: Binary not found: ${MISTRALRS_BIN}"; exit 1; }

exec "${MISTRALRS_BIN}" remote-worker \
    --model-dir "$(dirname "$MODEL_PATH")" \
    --model-file "$MODEL_FILE" \
    --listen "$LISTEN_ADDR" \
    --layers "$LAYERS"
