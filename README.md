# Hetero-LLaMA

> GPU / CPU / Phone 异构推理实验仓库。main 分支按模式组织代码，每个模式独立配置、脚本、文档和日志。

---

## 模式总览

| 模式 | 目录 | 状态 | 说明 |
|------|------|------|------|
| **main（基础 RPC）** | `main/` | ✅ 可用 | PC + 手机 CPU 通过 llama.cpp RPC 协同推理 |
| **vulkan** | `vulkan/` | ✅ 可用 | WSL + Mate 40 Pro 本地 Vulkan/OpenCL baseline |
| **3-machine** | `3-machine/` | ⏸️ 预留 | 完整实现见 `feat/3-machine-inference` 分支，验证稳定后迁入 |
| **common** | `common/` | ⏸️ 预留 | 跨模式共享脚本（如模型下载、环境检查） |

---

## 目录结构

```text
hetero-llama/
├── .gitignore
├── README.md                 # 本文件
├── main/                     # 基础 RPC 模式
│   ├── config.env
│   ├── scripts/
│   │   ├── check-phone-status.sh
│   │   ├── run_pc_rpc.sh
│   │   ├── run_phone_baseline.sh
│   │   ├── run_phone_rpc.sh
│   │   ├── setup_tunnels.sh
│   │   └── ts-log.sh
│   ├── docs/
│   │   ├── inbox.md
│   │   ├── outbox.md
│   │   ├── plan.md
│   │   ├── protocol.md
│   │   ├── report.md
│   │   └── reproduce.md
│   └── logs/                 # 基础 RPC 运行日志
├── vulkan/                   # Vulkan / OpenCL 本地推理模式
│   ├── config.env
│   ├── scripts/
│   │   ├── check-vulkan-env.sh
│   │   ├── run_phone_vulkan_baseline.sh
│   │   ├── run_wsl_opencl_baseline.sh
│   │   └── run_wsl_vulkan_baseline.sh
│   ├── docs/
│   │   ├── opencl-baseline-report.md
│   │   ├── opencl-setup.md
│   │   ├── vulkan-baseline-report.md
│   │   └── vulkan-setup.md
│   └── logs/                 # Vulkan / OpenCL 运行日志
├── 3-machine/                # 3-machine 异构模式（预留）
│   └── README.md
└── common/                   # 公共脚本（预留）
    └── .gitkeep
```

---

## 快速开始

### main 模式（PC + 手机 RPC）

```bash
cd main
# 1. 编辑配置
vim config.env
# 2. 启动手机 RPC Server
./scripts/run_phone_rpc.sh
# 3. PC 端发起 RPC 推理
./scripts/run_pc_rpc.sh 99 "你好" 5
```

### vulkan 模式（WSL + 手机本地推理）

```bash
cd vulkan
# 1. 环境准备（WSL）
#    见 docs/vulkan-setup.md 或 docs/opencl-setup.md
cat docs/opencl-setup.md

# 2. 运行 WSL OpenCL baseline（推荐，可调用 Intel GPU）
./scripts/run_wsl_opencl_baseline.sh 99 "你好" 5

# 3. 或运行 WSL Vulkan baseline（仅 CPU 软解）
./scripts/run_wsl_vulkan_baseline.sh 99 "你好" 5

# 4. 手机 Vulkan baseline
./scripts/run_phone_vulkan_baseline.sh 99 "你好" 5
```

---

## 各模式核心结论

### main 模式

- **分层调度有效**：`-ngl 4` 时手机端只跑约 108 个计算节点，`-ngl 99` 时手机端跑完整 821 节点 forward。
- **RPC 缓存必不可少**：336 MB 模型权重必须配合 `ggml-rpc-server -c` 缓存在手机本地。
- 详细报告见 `main/docs/report.md`。

### vulkan 模式

- **WSL Vulkan 当前无可用 GPU**：`vulkaninfo` 只显示 `llvmpipe`。
- **手机 Mali-G78 仅支持 Vulkan 1.1**：llama.cpp Vulkan 后端要求 1.2，因此手机也是 CPU fallback。
- **OpenCL 可调用 WSL2 Intel 核显**：25/25 层成功 offload，见 `vulkan/docs/opencl-baseline-report.md`。

---

## 分支说明

| 分支 | 用途 | 与 main 的关系 |
|------|------|----------------|
| `main` | 多模式组织后的主分支 | — |
| `feat/vulkan-local` | Vulkan/OpenCL 实验开发分支 | 内容已整理进 `vulkan/`，后续可删除 |
| `feat/3-machine-inference` | 3-machine 完整实现 | 独立验证中，稳定后迁入 `3-machine/` |

---

## 依赖版本

基于官方 llama.cpp 源码构建，**不推送源码**，只记录使用的 commit：

```text
152d337fadb93c2a099653c4072d5512c92c5bfd
```

模型：`Qwen2-0.5B-Instruct-Q4_0.gguf`（336 MB，24 层 transformer）。

---

## 贡献/实验流程

1. 在对应模式目录下修改脚本或配置。
2. 运行并保留日志到该模式的 `logs/` 目录。
3. 更新该模式的 `docs/` 文档。
4. 如新增跨模式公共脚本，放入 `common/`。
