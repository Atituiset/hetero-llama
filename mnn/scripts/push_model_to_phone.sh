#!/usr/bin/env bash
# 把 WSL 上导出的 MNN 模型推送到手机
# 用法：./push_model_to_phone.sh <本地模型目录> [手机用户@IP]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_DIR="${1:-${REPO_DIR}/models/qwen2-0.5b-instruct-mnn}"
PHONE="${2:-u0_a111@192.168.31.177}"
PHONE_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/$(basename "${LOCAL_DIR}")"

if [ ! -d "${LOCAL_DIR}" ]; then
    echo "ERROR: local model dir not found: ${LOCAL_DIR}" >&2
    exit 1
fi

echo "Pushing $(basename "${LOCAL_DIR}") to ${PHONE}:${PHONE_DIR} ..."
tar czf - -C "${LOCAL_DIR}" . | ssh -p 8022 "${PHONE}" "mkdir -p ${PHONE_DIR} && cd ${PHONE_DIR} && tar xzf -"
echo "Done."
