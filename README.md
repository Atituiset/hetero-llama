# Hetero-LLaMA

> **TL;DR**
> - **做了什么**：多台各自装不下大模型的异构设备——GPU PC（RTX 4050 Laptop 6GB 显存 + 15GB 内存）、WSL 机器（15GB 内存）、华为 Mate 40 Pro 手机（Kirin 9000，Mali-G78 MP24 GPU + 8GB 内存）——通过自研 TCP 层切分联合推理。
> - **实测结果**：Qwen3.6-27B / Qwen3.8-27B / Qwen3.6-35B-A3B（混合 SSM 架构）跨机跑通且输出正确，decode 1.3~3.4 T/s；同 prompt 三机实测自研桥 1.29 T/s vs llama.cpp RPC 0.22 T/s。
> - **核心工作**：mistral.rs 深度改造（fork [`Atituiset/mistral.rs`](https://github.com/Atituiset/mistral.rs)，19 个自定义 commits）——qwen35/qwen35moe GGUF 支持（混合 Gated DeltaNet SSM + Full Attention，修复 6 处数值 bug）、TCP 远程层卸载、x86 稀疏 MoE 前向（~200x 提速）。
> - **上游贡献**：稀疏 MoE 修复已提上游 [PR #2380](https://github.com/EricLBuehler/mistral.rs/pull/2380)（仅 MoE 性能修复这一块；TCP 桥接与 qwen35 支持暂留 fork，见 [Discussion #2381](https://github.com/EricLBuehler/mistral.rs/discussions/2381)）。
> - **证据**：[`mistralrs-bridge/`](./mistralrs-bridge/README.md)、[攻坚记录](./mistralrs-bridge/docs/session-2026-08-16.md)、[三机对比实验](./mistralrs-bridge/docs/threeway-challenge-2026-08-19.md)。

---

> GPU / CPU / Phone 异构推理实验仓库。  
> main 分支按**模式**组织，每个模式有独立的配置、脚本、文档和日志；顶层 README 只负责导航。

---

## Quick Start

```bash
# 最快的验证：27B 双机桥接一键启动（worker + 隧道 + host 全自动）
cd mistralrs-bridge
./scripts/run_qwen_27b_bridge.sh 3.8 "用中文写一段关于秋天的短诗"   # 3.6/3.8 可选，-i 进交互模式
```

更多模式见下表，进入对应目录查看各自 README。

---

## 模式总览（按时间线，2026）

| 时间 | 模式 | 节点构成 | 状态 | 一句话说明 |
|------|------|----------|------|------------|
| 07-07 ~ 07-09 | **main（基础 RPC）** | GPU PC + 手机（两机） | ✅ 可用 | llama.cpp RPC 双机协同推理的首个验证 |
| 07-10 ~ 07-14 | **vulkan** | WSL + 手机（两机） | ✅ 可用 | 本地 Vulkan/OpenCL baseline |
| 07-10 ~ 07-14 | **mnn** | 手机单机 | ✅ 已完成 | 用 MNN 在 Mate 40 Pro 上跑 LLM；OpenCL/Vulkan 能调用 GPU 但比 CPU 慢 |
| 07-10 ~ 07-14 | **ncnn-llm** | 手机单机 | ✅ 已完成 | ncnn_llm 构建成功；Qwen3-0.6B CPU 40.7 s，Vulkan 卡住无输出 |
| 07-15 ~ 08-20 | **3-machine（llama.cpp RPC）** | GPU PC + WSL + 手机（三机） | ✅ 跑通 | llama.cpp ggml-rpc 三机异构推理；Qwen3.8-27B decode 0.22 T/s |
| 07-24 ~ 08-19 | **mistralrs-bridge** | GPU PC + WSL + 手机（三机） | ✅ 跑通 | mistral.rs TCP 桥接（fork [`Atituiset/mistral.rs`](https://github.com/Atituiset/mistral.rs)，19 commits）；3.6/3.8-27B decode ~2.5 T/s，35B-A3B ~3.4 T/s，三机 1.29 T/s |
| 贯穿 | **common** | — | ✅ 已启用 | 跨模式共享脚本（`ts-log.sh`、`check-phone-status.sh`、配置模板） |

---

## 总体结论

所有手机 GPU 加速尝试的汇总见 [`docs/gpu-acceleration-summary.md`](./docs/gpu-acceleration-summary.md)。

当前在 Mate 40 Pro（Mali-G78）上：
- **llama.cpp Vulkan**：驱动版本不够（需要 Vulkan 1.2）。
- **llama.cpp OpenCL**：Mali 不在白名单。
- **MNN OpenCL/Vulkan**：能调用 GPU，但比 CPU 慢；3B 模型下 OpenCL 直接 OOM 崩溃。
- **ncnn LLM**：CPU 可跑通（Qwen3-0.6B 40.7 s）；Vulkan 首次推理卡住，基本不可用。
- **ncnn Vulkan**：CNN 有选择性加速，Transformer/LLM 极慢。

手机上所有 **GPU** 路径均不实用：llama.cpp Vulkan（驱动版本不够）、llama.cpp OpenCL（Mali 不在白名单）、MNN/ncnn 的 GPU 后端（能跑但比 CPU 慢 10-200 倍）。目前手机上实用的 LLM 推理路径只有 **CPU**：llama.cpp CPU、MNN ARM82、ncnn_llm CPU。PC 侧 GPU 路径为 llama.cpp CUDA / mistral.rs CUDA（RTX 4050 Laptop）。

PC 侧跨机分层推理由 **mistralrs-bridge** 模式自研实现（mistral.rs TCP 桥接）：Qwen3.6-27B / 3.8-27B / 35B-A3B（混合 SSM 架构）在 GPU PC + WSL 三段拓扑下输出正确，27B decode ~2.5 T/s，35B 经 x86 稀疏 MoE 修复后 ~3.4 T/s。三机（含手机）同 prompt 实测：**mistralrs 桥 1.29 T/s vs llama.cpp RPC 0.22 T/s**（详见 `mistralrs-bridge/docs/threeway-challenge-2026-08-19.md`）。

> 注意：MNN / ncnn 实验均为**手机单机推理**。WSL 仅负责模型导出/编译 x86 工具，并未与手机 GPU 做分层协同；`3-machine/` 的 llama.cpp RPC 分层方案对 MNN/ncnn 不适用。

---

## 公共依赖

- **llama.cpp**：fork [`Atituiset/llama.cpp`](https://github.com/Atituiset/llama.cpp)，当前基于 upstream master（2026-08，`2e92ecd`+；早期实验 pin 在 `152d337`）。源码不提交到本仓库，各模式脚本自行指向本地构建目录。
- **mistral.rs**：fork [`Atituiset/mistral.rs`](https://github.com/Atituiset/mistral.rs)，工作分支 `feat/remote-layer-split`（19 个自定义 commits：TCP 远程层卸载、qwen35/qwen35moe GGUF 支持、x86 稀疏 MoE）。本地路径 `mistral.rs/`（独立 git 仓库），为 mistralrs-bridge 模式的唯一引擎；上游 PR [#2380](https://github.com/EricLBuehler/mistral.rs/pull/2380) 在审。
- **模型**：
  - `qwen2-0.5b-instruct-q4_0.gguf`（336 MB，24 层 transformer）—— 各模式默认小模型，默认路径 `~/models/qwen2-0.5b-instruct-q4_0.gguf`，可在各模式 `config.env` 中修改
  - 大模型（`~/models/`，多机各一份）：`Qwen_Qwen3.6-27B-Q3_K_M.gguf`（14.8GB）、`Qwen3.8-27B-Q3_K_M.gguf`（14.6GB）、`Qwen_Qwen3.6-35B-A3B-Q3_K_M.gguf`（16GB）、`Qwen3.5-0.8B-Q4_K_M.gguf`（数值调试用）
- **系统工具**：`cmake`、`ninja/make`、`git`、`ssh`（部分模式需要）

---

## 目录结构

```text
hetero-llama/
├── README.md                 # 本文件（导航）
├── main/
│   ├── README.md             # 基础 RPC 模式说明（GPU PC + 手机两机 llama.cpp RPC）
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── vulkan/
│   ├── README.md             # Vulkan / OpenCL baseline 模式说明（WSL + 手机本地）
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── mnn/
│   ├── README.md             # MNN 手机单机 LLM 实验（CPU/OpenCL/Vulkan 三后端对比）
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── ncnn-llm/
│   ├── README.md             # ncnn 手机单机实验（ncnn_llm CPU / ncnn Vulkan）
│   ├── config.env
│   ├── scripts/
│   ├── docs/
│   └── logs/
├── 3-machine/
│   ├── README.md             # llama.cpp RPC 三机模式说明（ggml-rpc，GPU PC+WSL+手机）
│   ├── config.env
│   ├── scripts/              # 组网/基准脚本 + overnight_watchdog.sh
│   ├── docs/
│   └── logs/
├── mistralrs-bridge/
│   ├── README.md              # mistral.rs TCP 桥接模式说明（自研，GPU PC+WSL+手机）
│   ├── config.env
│   ├── scripts/
│   │   ├── run_remote_worker.sh      # 启动 TCP remote worker
│   │   ├── run_qwen_27b_bridge.sh    # 27B 双机桥接一键启动（3.6/3.8，含 -i 交互模式）
│   │   ├── run_llamacpp_threeway.sh  # llama.cpp RPC 三机一键启动（对比实验用）
│   │   ├── run_bridge_host.sh        # 启动桥接 Host
│   │   ├── start_wsl_tunnel.sh       # WSL→GPU PC SSH 反向隧道（跨机必需）
│   │   ├── run_cpu_safe.sh           # 纯 CPU 安全运行（早期）
│   │   ├── run_gpu_cuda_split.sh     # GPU 本地 CUDA/CPU 分层（早期）
│   │   └── build_gpu_binary.sh       # GPU PC CUDA 编译（单任务，防 OOM）
│   ├── topologies/
│   │   ├── qwen36_27b_bridge.yml       # 3.6-27B 三段拓扑（12 cuda+37 cpu+15 remote，双机）
│   │   ├── qwen38_27b_bridge.yml       # 3.8-27B 三段拓扑（双机）
│   │   ├── qwen36_35b_bridge.yml       # 35B-A3B 三段拓扑（8 cuda+17 cpu+15 remote，双机）
│   │   ├── qwen38_27b_threeway.yml     # 3.8-27B 四段拓扑（三机，含手机 59-63 层）
│   │   ├── threeway_0.8b_smoke.yml     # 三机 0.8B 冒烟测试拓扑
│   │   └── ...                         # loopback/早期双机拓扑
│   ├── docs/
│   │   ├── report.md                  # 早期 16 个 bridge commits 源码更改报告
│   │   ├── overnight-session.md       # 通宵 session 报告
│   │   ├── session-2026-08-16.md      # 8/16-8/19 攻坚报告（数值修复 + 三模型跑通 + 上游 PR）
│   │   └── threeway-challenge-2026-08-19.md  # 三机对比实验（mistralrs 1.29 vs llama.cpp RPC 0.22 T/s）
│   └── logs/
└── common/
    ├── config.env.template
    └── scripts/
        ├── check-phone-status.sh
        └── ts-log.sh
```

---

## 实验流程

每个模式目录独立自洽：读 README → 改 `config.env` → 跑脚本（日志进 `logs/`）→ 结论写进 `docs/`。
