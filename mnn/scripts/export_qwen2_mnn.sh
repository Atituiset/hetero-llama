#!/usr/bin/env bash
# 导出 Qwen2 模型为 MNN 格式
# 用法：./export_qwen2_mnn.sh <原始模型目录> <输出目录>
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MNN_DIR="${REPO_DIR}/MNN"
MNNCONVERT="${MNN_DIR}/build-host/MNNConvert"

MODEL_DIR="${1:-${REPO_DIR}/models/qwen2-0.5b-instruct}"
DST_DIR="${2:-${REPO_DIR}/models/qwen2-0.5b-instruct-mnn}"

if [ ! -f "${MNNCONVERT}" ]; then
    echo "ERROR: ${MNNCONVERT} not found. Build it first with:" >&2
    echo "  cd ${MNN_DIR} && cmake -B build-host -DMNN_BUILD_CONVERTER=ON && make -C build-host MNNConvert -j" >&2
    exit 1
fi

if [ ! -d "${MODEL_DIR}" ]; then
    echo "ERROR: model directory not found: ${MODEL_DIR}" >&2
    exit 1
fi

mkdir -p "${DST_DIR}"

cd "${MNN_DIR}/transformers/llm/export"
python3 llmexport.py \
    --path "${MODEL_DIR}" \
    --export mnn --hqq \
    --dst_path "${DST_DIR}" \
    --mnnconvert "${MNNCONVERT}"

echo "Exported MNN model to ${DST_DIR}"
