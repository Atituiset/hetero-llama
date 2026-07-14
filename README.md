# Hetero-LLaMA

> GPU / CPU / Phone 异构推理实验仓库。  
> main 分支按**模式**组织，每个模式有独立的配置、脚本、文档和日志；顶层 README 只负责导航。

---

## 模式总览

| 模式 | 目录 | 状态 | 一句话说明 |
|------|------|------|------------|
| **main（基础 RPC）** | [`main/`](./main/README.md) | ✅ 可用 | PC + 手机 CPU 通过 llama.cpp RPC 协同推理 |
| **vulkan** | [`vulkan/`](./vulkan/README.md) | ✅ 可运行 | WSL + Mate 40 Pro 本地 Vulkan/OpenCL baseline |
| **mnn** | [`mnn/`](./mnn/README.md) | ✅ 已验证 | 用 MNN 在 Mate 40 Pro 上跑 LLM；OpenCL/Vulkan 能调用 GPU 但比 CPU 慢 |
| **ncnn-llm** | [`ncnn-llm/`](./ncnn-llm/README.md) | ✅ 已验证 | ncnn_llm 已构建成功；Qwen3-0.6B CPU 40.7 s，Vulkan 卡住无输出 |
| **3-machine** | [`3-machine/`](./3-machine/README.md) | ✅ 可用 | GPU PC + WSL + 手机三机 llama.cpp RPC 异构推理；含通宵基准与 watchdog |
| **common** | [`common/`](./common/) | ✅ 已启用 | 跨模式共享脚本（`ts-log.sh`、`check-phone-status.sh`、配置模板） |

进入对应目录查看各自的 README 获取详细用法。

---

## 总体结论

所有手机 GPU 加速尝试的汇总见 [`docs/gpu-acceleration-summary.md`](./docs/gpu-acceleration-summary.md)。

当前在 Mate 40 Pro（Mali-G78）上：
- **llama.cpp Vulkan**：驱动版本不够（需要 Vulkan 1.2）。
- **llama.cpp OpenCL**：Mali 不在白名单。
- **MNN OpenCL/Vulkan**：能调用 GPU，但比 CPU 慢；3B 模型下 OpenCL 直接 OOM 崩溃。
- **ncnn LLM**：CPU 可跑通（Qwen3-0.6B 40.7 s）；Vulkan 首次推理卡住，基本不可用。
- **ncnn Vulkan**：CNN 有选择性加速，Transformer/LLM 极慢。

手机上目前唯一可用的 LLM 路径是 **手机 CPU（MNN ARM82 / ncnn_llm CPU）**；PC/WSL 上唯一可用的 GPU 路径是 **llama.cpp OpenCL（Intel）**。

> 注意：MNN / ncnn 实验均为**手机单机推理**。WSL 仅负责模型导出/编译 x86 工具，并未与手机 GPU 做分层协同；`3-machine/` 的 llama.cpp RPC 分层方案对 MNN/ncnn 不适用。

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
├── mnn/
│   ├── README.md             # MNN 手机端 LLM 实验说明
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── ncnn-llm/
│   ├── README.md             # ncnn Vulkan / ncnn_llm 实验说明
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── 3-machine/
│   ├── README.md             # 3-machine 模式说明
│   ├── config.env
│   ├── scripts/
│   │   └── overnight_watchdog.sh  # 通宵基准 watchdog
│   ├── docs/
│   └── logs/
└── common/
    ├── config.env.template
    └── scripts/
        ├── check-phone-status.sh
        └── ts-log.sh
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
| `feat/vulkan-local` | Vulkan/OpenCL 实验开发分支 | 已合并到 `vulkan/`，已删除 |
| `feat/3-machine-inference` | 3-machine 完整实现 | 已合并到 `3-machine/`，已删除 |
| `feat/reorg-modes` | 目录重组分支 | 已合入 main，已删除 |
