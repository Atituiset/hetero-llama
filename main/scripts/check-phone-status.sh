#!/bin/bash
# 检查 Mate 40 Pro 上 Claude Code Agent 的执行状态

set -euo pipefail

HOST_IP="${MATE40_IP:-192.168.1.7}"
HOST_PORT="${MATE40_PORT:-8022}"
REMOTE_BASE="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

echo "================================"
echo "Mate 40 Pro Agent 状态检查"
echo "目标: ${HOST_IP}:${HOST_PORT}"
echo "================================"
echo ""

echo "--- inbox.md (PC 端指令) ---"
ssh ${SSH_OPTS} -p ${HOST_PORT} u0_a111@${HOST_IP} "cat ${REMOTE_BASE}/inbox.md" | head -n 20
echo ""

echo "--- outbox.md (手机端汇报) ---"
ssh ${SSH_OPTS} -p ${HOST_PORT} u0_a111@${HOST_IP} "cat ${REMOTE_BASE}/outbox.md"
echo ""

echo "--- lock 文件状态 ---"
ssh ${SSH_OPTS} -p ${HOST_PORT} u0_a111@${HOST_IP} "ls -l ${REMOTE_BASE}/lock/ 2>/dev/null || echo '无 lock 文件'"
echo ""

echo "--- 关键文件最近修改时间 ---"
ssh ${SSH_OPTS} -p ${HOST_PORT} u0_a111@${HOST_IP} "ls -lth ${REMOTE_BASE}/inbox.md ${REMOTE_BASE}/outbox.md ${REMOTE_BASE}/protocol.md"
echo ""

echo "--- llama.cpp 构建目录状态 ---"
ssh ${SSH_OPTS} -p ${HOST_PORT} u0_a111@${HOST_IP} "ls -ld ${REMOTE_BASE}/llama.cpp/build-cpu 2>/dev/null || echo 'build-cpu 尚未创建'"
echo ""

echo "--- 进程快照 ---"
ssh ${SSH_OPTS} -p ${HOST_PORT} u0_a111@${HOST_IP} "ps aux 2>/dev/null | grep -E 'llama|claude|cmake|make' | grep -v grep || echo '无相关进程'"
echo ""

echo "================================"
echo "状态检查完成"
echo "================================"
