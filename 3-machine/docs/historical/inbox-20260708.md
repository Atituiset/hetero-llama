---
from: PC Claude Code
to: Mate 40 Pro Claude Code
updated: "2026-07-08"
---

# PC → Phone 指令信箱

## 使用规则

- **PC 端**（当前会话）只负责修改本文件。
- **手机端** Claude Code 读取本文件后执行，并把结果/日志写到 `outbox.md`。
- 修改前先在 `lock/` 目录下创建 `inbox.lock`，写完后删除，避免两端同时写。
- 每次更新在文件开头修改 `updated` 字段。

## 说明

由于本次任务实际通过“单 Agent + SSH 直连手机”模式完成，未走双 Agent 自动通信流程。本文件中的任务已执行完毕，结果汇总在 `outbox.md` 和 `report.md` 中。

## 当前指令（已执行完毕）

### Task 1: 环境自检 ✅

已完成：手机为 ARM64 Ubuntu proot，8 核，8 GB 内存，已安装 git/cmake/clang/build-essential/make。

### Task 2: 安装依赖并编译 llama.cpp CPU 后端 ✅

已完成：`llama.cpp/build-cpu` 编译成功，生成本地主程序。

### Task 3: 下载 Qwen-0.5B 模型 ✅

已完成：336 MB 的 `qwen2-0.5b-instruct-q4_0.gguf` 已下载到 `~/models/`。

### Task 4: 本地 CPU 推理基线测试 ✅

已完成：手机本地 CPU 推理约 7.1 t/s。

### Task 5: RPC Server 编译与启动 ✅

已完成：编译 `ggml-rpc-server`，启动 `-H 192.168.1.7 -p 50052 -c`，PC 端成功连接。

### Task 6: PC + 手机异构推理验证 ✅

已完成：
- `-ngl 10`：手机参与 10 层，约 6.84 t/s。
- `-ngl 99`：手机执行全部层，约 4.73 t/s（正常模式）。
- `DEBUG=1` 重新验证：确认 scheduler 把 821 个节点、1165 个张量的计算图 offload 到手机 RPC backend。

## 待办任务

- [x] 初始化通信信箱
- [x] Task 1: 环境自检
- [x] Task 2: 安装依赖并编译 CPU 后端
- [x] Task 3: 下载模型
- [x] Task 4: 本地推理基线测试
- [x] Task 5: RPC Server 编译与启动
- [x] Task 6: PC + 手机异构推理验证

## 历史消息

- 2026-07-07: 信箱初始化完成，PC 端下发首次任务。
- 2026-07-08: 任务实际通过单 Agent + SSH 模式完成，inbox/outbox 同步为已完成状态。
