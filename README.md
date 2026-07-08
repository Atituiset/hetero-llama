# Hetero-LLaMA

> GPU / CPU / Phone 异构推理实验：用 llama.cpp 的 RPC 后端把 PC 和手机拼成一台分布式推理机。

---

## 项目简介

Hetero-LLaMA 验证在多台异构设备之间通过 `llama.cpp` 原生 RPC 协议共享一次大模型推理：

- **PC 端**：x86_64 纯 CPU（后续可扩展 6G 显存 GPU）
- **手机端**：华为 Mate 40 Pro（ARM64，Termux + Ubuntu proot）
- **调度方式**：llama.cpp 的 `ggml scheduler` 通过 `-ngl` 参数控制每层张量放到哪个 backend

目前跑通的是 **PC CPU + 手机 CPU** 协同推理；GPU 端是下一步探索方向。

---

## 核心结论

1. **分层调度真实有效**：`-ngl 4` 时手机端只跑约 108 个计算节点，`-ngl 99` 时手机端跑完整 821 节点 forward。
2. **`-ngl` 精确控制手机参与度**：对 24 层的 Qwen2-0.5B，`-ngl 4` = 4 层手机 + 20 层 CPU，`-ngl 99` = 全部 24 层手机。
3. **当前小模型场景下 RPC 有性能损失**：纯 PC CPU 最快，手机参与越多越慢（见性能表）。
4. **RPC 缓存必不可少**：336 MB 模型权重必须配合 `ggml-rpc-server -c` 缓存在手机本地，否则全 offload 会触发重复传输或崩溃。

---

## 性能数据

模型：`Qwen2-0.5B-Instruct-Q4_0`（24 层 transformer），prompt `"你好"`，生成 5 tokens。

### 非 DEBUG 真实性能

| 配置 | prompt eval | generation | 手机参与层数 |
|---|---|---|---|
| PC 本地 CPU（无 RPC） | **380.78 t/s** | **99.75 t/s** | 0 层 |
| PC + 手机 RPC（`-ngl 4`） | **37.64 t/s** | **7.59 t/s** | 4 层 |
| PC + 手机 RPC（`-ngl 99`） | **9.73 t/s** | **3.36 t/s** | 24 层 |

### DEBUG 模式验证（日志含 scheduler 细节）

| 配置 | prompt eval | generation | 手机 graph 节点数 |
|---|---|---|---|
| PC 本地 CPU | 386.17 t/s | 95.11 t/s | 0 |
| PC + 手机 RPC（`-ngl 4`） | 34.34 t/s | 8.46 t/s | 108 节点 / 159 张量 |
| PC + 手机 RPC（`-ngl 99`） | 8.96 t/s | 3.16 t/s | 821 节点 / 1165 张量 |

> DEBUG 模式因大量日志写入会拖慢速度，仅用于验证调度细节。

---

## 目录结构

```text
hetero-llama/
├── .gitignore              # 排除 llama.cpp 源码、模型、构建产物、日志
├── README.md               # 本文件
├── report.md               # 更详细的实验报告
├── reproduce.md            # 逐行复现手册
├── plan.md                 # 原始规划
├── protocol.md             # 双 Agent 通信协议（v0.1）
├── inbox.md / outbox.md    # PC ↔ Phone Agent 通信信箱
├── ts-log.sh               # 给日志加 wall-clock 时间戳的小工具
├── run_phone_rpc.sh        # 手机端启动 RPC Server
├── run_phone_baseline.sh   # 手机端本地 CPU 推理
├── run_pc_rpc.sh           # PC 端 RPC 推理
├── check-phone-status.sh   # 检查手机状态
├── llama.cpp/              # 子目录，本仓库不推送源码，见下方说明
└── logs/                   # 运行时生成的日志（本仓库不提交）
```

---

## 依赖版本

### llama.cpp

本项目基于官方 llama.cpp 源码构建，**不推送源码**，只记录使用的 commit：

```text
commit: 152d337fadb93c2a099653c4072d5512c92c5bfd
date:   2026-07-03 15:40:06 +0200
message: spec: support spec-draft-p-min in DFlash (#25246)
```

复现前请自行克隆官方仓库并 checkout 到该 commit：

```bash
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
```

### 模型

- **Qwen2-0.5B-Instruct-Q4_0**
- 大小：约 336 MB
- 下载：`https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF`
- 本仓库不提交模型文件。

### 环境

- **PC**：Linux x86_64，cmake ≥ 3.12，gcc/clang
- **手机**：Android + Termux + Ubuntu proot，ARM64，cmake，clang，build-essential

---

## 快速开始

### 1. 手机端启动 RPC Server

```bash
ssh -p 8022 u0_a111@192.168.1.7
proot-distro login ubuntu
cd ~/Projects/hetero-llama
./run_phone_rpc.sh
```

### 2. PC 端跑推理

```bash
cd /path/to/hetero-llama

# 全部层 offload 到手机
./run_pc_rpc.sh 99 "你好" 5

# 只 offload 4 层到手机，其余 20 层在 PC CPU
./run_pc_rpc.sh 4 "你好" 5

# 纯 PC CPU（无 RPC）
cd /path/to/llama.cpp-host/build-rpc/bin
./llama-completion -m /path/to/qwen2-0.5b-instruct-q4_0.gguf -p "你好" -n 5
```

详细复现步骤请见 [`reproduce.md`](reproduce.md)。

---

## 日志查看

每次运行建议带 `ts-log.sh` 保存 wall-clock 时间戳：

```bash
DEBUG=1 ./run_pc_rpc.sh 99 "你好" 5 2>&1 | ./ts-log.sh | tee logs/pc_ngl99_$(date +%Y%m%d_%H%M%S).log
```

关键 grep：

```bash
# PC 端：看 scheduler 怎么切图
grep -E "## SPLIT" logs/pc_ngl99_*.log

# PC 端：看性能
grep "eval time" logs/pc_ngl99_*.log

# 手机端：看实际跑了多少节点
grep "graph_compute" logs/phone_ngl99_*.log
```

---

## 下一步计划

- [ ] 接入 PC 端 6G 显存 GPU（CUDA / Vulkan）
- [ ] 尝试手机端 Vulkan backend，利用 Mali-G78 GPU
- [ ] 评估 USB 网络共享对 RTT 的改善
- [ ] 长上下文下的 KV Cache 传输开销测试
- [ ] 自动化的分层策略搜索（根据各后端算力动态决定 `-ngl`）

---

## 致谢

- [llama.cpp](https://github.com/ggerganov/llama.cpp) 提供 RPC backend 和 scheduler
- [Qwen](https://huggingface.co/Qwen) 提供 0.5B 测试模型

---

## License

MIT（脚本与文档部分）；llama.cpp 与模型文件遵循其各自许可证。
