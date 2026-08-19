#!/usr/bin/env bash
# llama.cpp RPC 三机 27B 推理（在 WSL 上运行）
#
# 拓扑: GPU PC host(-ngl 12 CUDA) + WSL rpc-server(50052) + 手机 rpc-server(50053)
# 两个 rpc-server 均经 ssh -R 反向隧道映射到 GPU PC 的 127.0.0.1
#
# 用法: ./run_llamacpp_threeway.sh [prompt]
# 日志: logs/llamacpp_threeway_<timestamp>.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE_DIR="$(dirname "$SCRIPT_DIR")"
source "${MODE_DIR}/config.env"

PROMPT="${1:-用中文写一段关于秋天的短诗，然后解释你最喜欢的一句。}"
MODEL_FILE="Qwen3.8-27B-Q3_K_M.gguf"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="${MODE_DIR}/logs/llamacpp_threeway_${TS}.log"
LLAMA_BIN="${GPU_PC_MISTRALRS_DIR}/../llama.cpp/build-cuda-rpc/bin/llama-completion"

echo "=== llama.cpp RPC 三机 27B ==="
echo "Prompt: ${PROMPT}"
echo "Log:    ${LOG}"

# 前置检查：两个 rpc 隧道
for p in 50052 50053; do
    ssh "${GPU_PC_USER}@${GPU_PC_IP}" "(exec 3<>/dev/tcp/127.0.0.1/${p}) 2>/dev/null" \
        && exec 3>&- 3<&- || { echo "ERROR: GPU PC 侧 ${p} 不可达（检查 rpc-server 和隧道）"; exit 1; }
done

ssh "${GPU_PC_USER}@${GPU_PC_IP}" \
    "LD_LIBRARY_PATH=\$HOME/projects/gpu-cpu-phone-test/llama.cpp/build-cuda-rpc.stale/bin \
     ~/projects/gpu-cpu-phone-test/llama.cpp/build-cuda-rpc.stale/bin/llama-completion \
     -m ~/models/${MODEL_FILE} \
     --rpc 127.0.0.1:50052,127.0.0.1:50053 \
     -ngl 12 \
     -p '${PROMPT}' -n 512" \
    2>&1 | tee "${LOG}"

echo "=== 完成，日志: ${LOG} ==="
