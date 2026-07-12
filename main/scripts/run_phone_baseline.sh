#!/bin/bash
# 手机端本地 CPU 推理基线
# 用法：./run_phone_baseline.sh [模型路径] [提示词] [生成 token 数]
# 示例：./run_phone_baseline.sh ~/models/qwen2-0.5b-instruct-q4_0.gguf "你好" 32

set -e

MODEL="${1:-$HOME/models/qwen2-0.5b-instruct-q4_0.gguf}"
PROMPT="${2:-你好}"
N="${3:-32}"
CLI="$HOME/Projects/gpu-cpu-phone-test/llama.cpp/build-cpu/bin/llama-cli"

echo "=== 手机本地 CPU 推理 ==="
echo "  model : ${MODEL}"
echo "  prompt: ${PROMPT}"
echo "  n     : ${N}"
echo ""

exec "${CLI}" -m "${MODEL}" -p "${PROMPT}" -n "${N}"
