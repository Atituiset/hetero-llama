# 异构推理通信协议

## 核心原则

1. **默认不改动 `ggml-rpc.cpp` 的序列化格式**。任何结构体、内存对齐、量化格式的变更都必须先在此文档记录，并同步两端版本号。
2. 两端 Agent 在修改 C/C++ 代码前，必须先确认 `protocol.md` 中的相关条目。
3. 版本号格式：`vMAJOR.MINOR`，变更时更新 `updated` 字段。

---

## 当前版本

- **version**: v0.1
- **updated**: 2026-07-07
- **状态**: 初始版本，使用 llama.cpp 原生 RPC 协议，无自定义修改。

---

## Tensor 传输约定

### Hidden State（层间隐状态）

| 项 | 约定 |
|---|---|
| 数据类型 | FP16 (`GGML_TYPE_F16`) |
| 维度 | `[batch_size, hidden_dim]`，由模型配置决定 |
| 内存布局 | 行主序（row-major）连续内存 |
| 对齐要求 | 默认 16 bytes；如需修改，必须同步更新本文件并两端适配 |
| 传输频率 | Decode 阶段每个 token 传输一次 |

### KV Cache

当前架构 **不跨设备传输 KV Cache**，KV Cache 保留在各自节点本地管理。

---

## 后端分配约定

- PC 端（x86 CPU）：运行 `llama.cpp` 主程序 + RPC Client。
- Mate 40 Pro 端：运行 `llama-rpc-server`，后端可选 CPU 或 Vulkan。
- 默认使用 CPU 后端跑通链路，再挑战 Vulkan。

---

## 模型约定

- 第一阶段使用 **Qwen2-0.5B-Instruct-Q4_0**。
- 后续如需更换模型，必须确认两端都能加载同一 GGUF 文件，并更新本文件。

---

## 变更日志

| 版本 | 日期 | 变更内容 | 影响端 |
|---|---|---|---|
| v0.1 | 2026-07-07 | 初始版本，使用原生 ggml-rpc 协议 | 两端 |
