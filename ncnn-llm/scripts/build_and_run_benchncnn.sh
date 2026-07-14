#!/usr/bin/env bash
# 在 Mate 40 Pro 上编译并运行 ncnn benchncnn（CPU / Vulkan）
# 必须在 Termux 原生 shell 中运行。
set -e

NCNN_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/ncnn"
BUILD_DIR="${NCNN_DIR}/build"

cd "${NCNN_DIR}"

echo "=== Configure ncnn with Vulkan ==="
cmake -B build -S . \
    -DNCNN_VULKAN=ON \
    -DNCNN_BUILD_BENCHMARK=ON \
    -DNCNN_BUILD_EXAMPLES=OFF \
    -DNCNN_BUILD_TOOLS=OFF \
    -DNCNN_BUILD_TESTS=OFF

echo "=== Build benchncnn ==="
cmake --build build --target benchncnn -j4

echo "=== Prepare benchmark params ==="
cd "${BUILD_DIR}/benchmark"
cp ../../benchmark/models/*.param .

echo "=== CPU benchmark ==="
./benchncnn 4 1 0 -1 0

echo "=== Vulkan benchmark ==="
./benchncnn 4 1 0 0 0
