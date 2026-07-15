#!/bin/bash
# GPU PC 上通宵跑配置驱动的基准测试
# 用法：tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'
# 环境变量：
#   DRY_RUN=1     只打印执行计划
#   FORCE_RERUN=1 强制重跑已有日志的组合

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.env
source "${SCRIPT_DIR}/../config.env"
# shellcheck source=../config/benchmark-matrix.env
source "${SCRIPT_DIR}/../config/benchmark-matrix.env"

PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODEL_DIR="${HOME}/models"
LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

DRY_RUN="${DRY_RUN:-0}"
FORCE_RERUN="${FORCE_RERUN:-0}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# -----------------------------
# 辅助函数
# -----------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 解析 MODEL_别名 变量
# 输入：MODEL_qwen3_1_7b 的值
# 输出：OLLAMA_NAME GGUF_NAME PROMPT N
parse_model() {
    local spec="$1"
    IFS='|' read -r ollama_name gguf_name prompt n <<< "${spec}"
    echo "${ollama_name}" "${gguf_name}" "${prompt}" "${n}"
}

# 获取所有声明的模型别名
get_model_aliases() {
    env | grep -E '^RUN_' | sed 's/^RUN_//' | cut -d= -f1 | sort -u
}

# 获取某个模型要跑的拓扑列表
get_topologies_for_model() {
    local alias="$1"
    local var="RUN_${alias}"
    echo "${!var}"
}

# 链接 Ollama 模型到 ~/models/
link_ollama_model() {
    local ollama_name="$1"
    local gguf_name="$2"

    log "拉取模型 ${ollama_name} ..."
    ollama pull "${ollama_name}"

    if [ -n "${OLLAMA_MODELS}" ]; then
        OLLAMA_DIR="${OLLAMA_MODELS}"
    elif [ -d "/usr/share/ollama/.ollama/models" ]; then
        OLLAMA_DIR="/usr/share/ollama/.ollama/models"
    elif [ -d "${HOME}/.ollama/models" ]; then
        OLLAMA_DIR="${HOME}/.ollama/models"
    else
        log "ERROR: 无法找到 Ollama models 目录" &>2
        exit 1
    fi
    log "Ollama 模型目录: ${OLLAMA_DIR}"

    local manifest_path="${OLLAMA_DIR}/manifests/registry.ollama.ai/library/${ollama_name%:*}/${ollama_name#*:}"
    if [ ! -f "${manifest_path}" ]; then
        log "ERROR: Ollama manifest 不存在: ${manifest_path}" &>2
        exit 1
    fi

    local model_blob
    model_blob=$(python3 - "${manifest_path}" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for layer in m.get('layers', []):
    mt = layer.get('mediaType', '')
    if 'model' in mt or mt.endswith('model'):
        print(layer['digest'])
        break
PY
)

    if [ -z "${model_blob}" ]; then
        log "ERROR: 无法从 manifest 找到 model blob" &>2
        exit 1
    fi

    local src="${OLLAMA_DIR}/blobs/${model_blob//:/-}"
    local model_path="${MODEL_DIR}/${gguf_name}"
    mkdir -p "${MODEL_DIR}"
    ln -sf "${src}" "${model_path}"
    log "模型已链接: ${model_path} -> ${src}"
    echo "${model_path}"
}

# 记录 GPU 采样
run_with_gpu_log() {
    local name="$1"
    shift
    local gpu_log="${LOG_DIR}/${name}_gpu.csv"
    echo "timestamp,power.draw[W],memory.used[MiB],utilization.gpu[%],temperature.gpu[C]" > "${gpu_log}"
    nvidia-smi --query-gpu=timestamp,power.draw,memory.used,utilization.gpu,temperature.gpu --format=csv,noheader -l 1 >> "${gpu_log}" 2>/dev/null &
    local smi_pid=$!
    local log="${LOG_DIR}/${name}.log"
    log "开始 ${name} ..."
    "$@" 2>&1 | tee "${log}"
    kill "${smi_pid}" 2>/dev/null || true
    wait "${smi_pid}" 2>/dev/null || true
    log "完成 ${name}"
}

# -----------------------------
# 主流程
# -----------------------------

log "开始通宵基准测试"
log "DRY_RUN=${DRY_RUN}, FORCE_RERUN=${FORCE_RERUN}"

BIN_DIR="${GPU_PC_BUILD_DIR}/bin"

# 生成执行计划
PLAN=()
for alias in $(get_model_aliases); do
    model_var="MODEL_${alias}"
    read -r ollama_name gguf_name prompt n < <(parse_model "${!model_var}")
    if [ -z "${ollama_name}" ] || [ -z "${gguf_name}" ]; then
        log "WARN: 模型 ${alias} 定义无效，跳过"
        continue
    fi
    for topo in $(get_topologies_for_model "${alias}"); do
        topo_var="TOPOLOGY_${topo}"
        rpc_args="${!topo_var}"
        for ngl in ${NGL_LIST}; do
            name="${alias}_${topo}_ngl${ngl}_${TIMESTAMP}"
            PLAN+=("${alias}|${topo}|${ngl}|${name}|${ollama_name}|${gguf_name}|${prompt}|${n}|${rpc_args}")
        done
    done
done

if [ ${#PLAN[@]} -eq 0 ]; then
    log "ERROR: 执行计划为空，请检查 config/benchmark-matrix.env" &>2
    exit 1
fi

log "执行计划共 ${#PLAN[@]} 项"
for item in "${PLAN[@]}"; do
    log "  ${item}"
done

if [ "${DRY_RUN}" == "1" ]; then
    log "DRY_RUN 模式，退出"
    exit 0
fi

if [ ! -x "${BIN_DIR}/llama-completion" ]; then
    log "ERROR: llama-completion not found: ${BIN_DIR}/llama-completion" &>2
    exit 1
fi

# 执行
CURRENT_MODEL=""
MODEL_PATH=""
for item in "${PLAN[@]}"; do
    IFS='|' read -r alias topo ngl name ollama_name gguf_name prompt n rpc_args <<< "${item}"

    if [ "${CURRENT_MODEL}" != "${ollama_name}" ]; then
        MODEL_PATH=$(link_ollama_model "${ollama_name}" "${gguf_name}")
        CURRENT_MODEL="${ollama_name}"
    fi

    log_file="${LOG_DIR}/${name}.log"
    if [ "${FORCE_RERUN}" != "1" ] && [ -s "${log_file}" ]; then
        log "跳过（已有非空日志）: ${name}"
        continue
    fi

    args=(
        "${BIN_DIR}/llama-completion"
        -m "${MODEL_PATH}"
        -p "${prompt}"
        -n "${n}"
        -ngl "${ngl}"
        -no-cnv
    )
    if [ -n "${rpc_args}" ]; then
        # shellcheck disable=SC2206
        args+=(${rpc_args})
    fi

    echo ""
    echo "=== ${name} ==="
    run_with_gpu_log "${name}" "${args[@]}"
done

# 汇总
SUMMARY="${LOG_DIR}/summary_${TIMESTAMP}.txt"
{
    echo "通宵基准测试汇总"
    echo "生成时间: $(date)"
    echo "模型: ${CURRENT_MODEL:-N/A}"
    echo ""
    for alias in $(get_model_aliases); do
        model_var="MODEL_${alias}"
        read -r ollama_name gguf_name _ _ < <(parse_model "${!model_var}")
        echo "=== ${alias} (${ollama_name}) ==="
        for topo in $(get_topologies_for_model "${alias}"); do
            echo "--- ${topo} ---"
            grep -H "eval time" "${LOG_DIR}/${alias}_${topo}_ngl*_${TIMESTAMP}.log" 2>/dev/null || true
        done
        echo ""
    done
} > "${SUMMARY}"

log "全部完成。汇总: ${SUMMARY}"
