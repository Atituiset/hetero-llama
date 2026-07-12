# Hetero-LLaMA

> GPU / CPU / Phone 异构推理实验仓库。  
> main 分支按**模式**组织，每个模式有独立的配置、脚本、文档和日志；顶层 README 只负责导航。

---

## 模式总览

| 模式 | 目录 | 状态 | 一句话说明 |
|------|------|------|------------|
| **main（基础 RPC）** | [`main/`](./main/README.md) | ✅ 可用 | PC + 手机 CPU 通过 llama.cpp RPC 协同推理 |
| **vulkan** | [`vulkan/`](./vulkan/README.md) | ✅ 可运行 | WSL + Mate 40 Pro 本地 Vulkan/OpenCL baseline |
| **3-machine** | [`3-machine/`](./3-machine/README.md) | ⏸️ 预留 | 完整实现见 `feat/3-machine-inference` 分支 |
| **common** | [`common/`](./common/) | ⏸️ 预留 | 跨模式共享脚本（如模型下载、环境检查） |

进入对应目录查看各自的 README 获取详细用法。

---

## 公共依赖

- **llama.cpp commit**：`152d337fadb93c2a099653c4072d5512c92c5bfd`  
  源码不提交到本仓库，各模式脚本自行指向本地构建目录。
- **模型**：`qwen2-0.5b-instruct-q4_0.gguf`（336 MB，24 层 transformer）  
  默认路径 `~/models/qwen2-0.5b-instruct-q4_0.gguf`，可在各模式 `config.env` 中修改。
- **系统工具**：`cmake`、`ninja/make`、`git`、`ssh`（部分模式需要）

---

## 目录结构

```text
hetero-llama/
├── README.md                 # 本文件（导航）
├── main/
│   ├── README.md             # 基础 RPC 模式说明
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── vulkan/
│   ├── README.md             # Vulkan / OpenCL 模式说明
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── 3-machine/
│   └── README.md             # 3-machine 模式说明（预留）
└── common/
    └── .gitkeep
```

---

## 实验流程

1. 进入对应模式目录：`cd main` / `cd vulkan` / `cd 3-machine`
2. 阅读该目录的 `README.md`
3. 编辑 `config.env`
4. 运行脚本并保留日志到该模式 `logs/`
5. 更新该模式 `docs/` 中的报告

---

## 分支说明

| 分支 | 用途 | 与 main 的关系 |
|------|------|----------------|
| `main` | 多模式组织后的主分支 | — |
| `feat/vulkan-local` | Vulkan/OpenCL 实验开发分支 | 内容已整理进 `vulkan/`，可删除 |
| `feat/3-machine-inference` | 3-machine 完整实现 | 独立验证中，稳定后迁入 `3-machine/` |
