#!/usr/bin/env bash
# 在 GPU PC 上通过 SSH 编译 mistral.rs CUDA 二进制
#
# GPU PC RTX 4050 只有 6GB VRAM + 15GB RAM，必须限制并行编译 job 数避免 OOM。
# 用法: ./build_gpu_binary.sh [jobs]
# 默认: CARGO_BUILD_JOBS=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

JOBS="${1:-1}"

echo "=== Building mistral.rs CUDA binary on GPU PC ==="
echo "GPU PC:       ${GPU_PC_USER}@${GPU_PC_IP}"
echo "Build jobs:   ${JOBS} (limited to avoid OOM)"
echo "=================================================="

echo "Syncing source to GPU PC..."
rsync -avz \
    --exclude 'target/' \
    --exclude '.git/' \
    "${MISTRALRS_DIR}/" \
    "${GPU_PC_USER}@${GPU_PC_IP}:${GPU_PC_MISTRALRS_DIR}/"

# flash-attn 的 nvcc 会在 15GB RAM 上并行起多个 3GB+ 的 cicc 进程导致 OOM，
# 默认只编 cuda feature；确需 flash-attn 时显式传入（如: ./build_gpu_binary.sh 1 'cuda flash-attn'）
FEATURES="${2:-cuda}"

echo "Building features: ${FEATURES} (this may take 10-60 minutes)..."
ssh "${GPU_PC_USER}@${GPU_PC_IP}" 'bash -s' <<EOF
    export PATH=\$HOME/.cargo/bin:\$PATH
    cd ${GPU_PC_MISTRALRS_DIR}
    CARGO_BUILD_JOBS=${JOBS} cargo build --release -p mistralrs-cli --features '${FEATURES}' 2>&1
EOF
echo "Build complete."
