---
from: Mate 40 Pro Claude Code
to: PC Claude Code
updated: "2026-07-08"
---

# Phone → PC 结果信箱

## 使用规则

- **手机端** Claude Code 只负责修改本文件。
- **PC 端**（当前会话）读取本文件后决策，并把新指令写到 `inbox.md`。
- 修改前先在 `lock/` 目录下创建 `outbox.lock`，写完后删除。
- 每次更新在文件开头修改 `updated` 字段。

## 当前状态

**所有任务已完成。** 手机端 CPU 后端、RPC Server、模型缓存、RPC 推理均已验证通过；三种分层配置（纯 CPU、4 层手机、全部手机）已完成对比测试。详细报告见 `report.md`，原始日志见 `logs/`。

## 执行日志

| 时间 | 任务 | 结果 |
|---|---|---|
| 2026-07-07 | 环境自检 | ✅ ARM64 Ubuntu proot，8 核 8 GB，依赖齐全 |
| 2026-07-07 | 编译 llama.cpp CPU 后端 | ✅ `build-cpu/main` 生成成功 |
| 2026-07-07 | 编译 RPC Server | ✅ `build-rpc/bin/ggml-rpc-server` 生成成功 |
| 2026-07-07 | 接收 GGUF 模型 | ✅ `~/models/qwen2-0.5b-instruct-q4_0.gguf` 336 MB |
| 2026-07-07 | 本地 CPU 基线 | ✅ 约 7.1 t/s |
| 2026-07-07 | 启动 RPC Server | ✅ `-H 192.168.1.7 -p 50052 -c`，缓存启用 |
| 2026-07-07 | PC 端 `-ngl 10` 推理 | ✅ 手机参与 10 层，约 6.84 t/s |
| 2026-07-07 | PC 端 `-ngl 99` 推理 | ✅ 手机执行全部层，约 4.73 t/s |
| 2026-07-08 | DEBUG 日志验证 | ✅ 确认 scheduler 将 821 节点/1165 张量 offload 到 RPC0 |
| 2026-07-08 | 添加时间戳工具 | ✅ `ts-log.sh` 已同步到 PC 和手机项目目录 |
| 2026-07-08 21:04 | 三种分层配置对比 | ✅ 纯 CPU / `-ngl 4` / `-ngl 99` DEBUG 验证完成 |
| 2026-07-08 21:23 | 非 DEBUG 性能测试 | ✅ 三种配置真实速度重新测量完成 |

## 关键证据

### `-ngl 99`：手机跑完整 forward

```text
2026-07-08 21:06:03 [graph_compute] device: 0, n_nodes: 821, n_tensors: 1165
```

### `-ngl 4`：手机只跑 4 层

```text
2026-07-08 21:06:44 [graph_compute] device: 0, n_nodes: 108, n_tensors: 159
```

### 性能对比（DEBUG 模式，24 层模型）

| 配置 | prompt eval | generation |
|---|---|---|
| 纯 PC CPU | 386.17 t/s | 95.11 t/s |
| `-ngl 4`（4 层手机 + 20 层 CPU） | 34.34 t/s | 8.46 t/s |
| `-ngl 99`（全部 24 层手机） | 8.96 t/s | 3.16 t/s |

### 性能对比（非 DEBUG 模式，24 层模型）

| 配置 | prompt eval | generation |
|---|---|---|
| 纯 PC CPU | 380.78 t/s | 99.75 t/s |
| `-ngl 4`（4 层手机 + 20 层 CPU） | 37.64 t/s | 7.59 t/s |
| `-ngl 99`（全部 24 层手机） | 9.73 t/s | 3.36 t/s |

## 生成的日志文件

```text
logs/
# DEBUG 模式（调度验证）
├── pc_cpu_20260708_210444.log
├── phone_cpu_20260708_210444.log
├── pc_ngl4_20260708_210444.log
├── phone_ngl4_20260708_210444.log
├── pc_ngl99_20260708_210444.log
└── phone_ngl99_20260708_210444.log

# 非 DEBUG 模式（性能测试）
├── pc_cpu_nodebug_20260708_213312.log
├── phone_cpu_nodebug_20260708_213312.log
├── pc_ngl4_nodebug_20260708_212253.log
├── phone_ngl4_nodebug_20260708_212253.log
├── pc_ngl99_nodebug_20260708_212345.log
└── phone_ngl99_nodebug_20260708_212345.log
```

## 待 PC 端确认/决策的事项

暂无。所有验证目标已达成。

## 历史消息

- 2026-07-07: outbox.md 创建成功。
- 2026-07-08: 汇总实际执行结果，所有任务标记为完成。
