# vulkan 模式：WSL + Mate 40 Pro 本地 Vulkan/OpenCL 推理

本目录用于在 WSL（当前机器）和华为 Mate 40 Pro 上分别运行 llama.cpp 的 **Vulkan** 与 **OpenCL** 后端本地推理，验证 GPU 可用性并记录 workaround。

- 状态：✅ 可运行；WSL GPU 需走 OpenCL，手机 Vulkan 暂为 CPU fallback
- 模型：`Qwen2-0.5B-Instruct-Q4_0.gguf`（336 MB，24 层）
- llama.cpp commit：`152d337fadb93c2a099653c4072d5512c92c5bfd`

## 目录

- `config.env` — 构建路径、模型路径、默认推理参数
- `scripts/` — baseline 脚本
- `docs/` — 报告与 setup 指南
- `logs/` — 运行日志

## 快速开始

### 1. 环境检查

```bash
./scripts/check-vulkan-env.sh
```

### 2. WSL Vulkan baseline（CPU fallback）

```bash
./scripts/run_wsl_vulkan_baseline.sh 99 "你好" 5
```

### 3. WSL OpenCL baseline（调用 Intel GPU）

```bash
./scripts/run_wsl_opencl_baseline.sh 99 "你好" 5
```

### 4. 手机 Vulkan baseline（需从 Termux 原生 shell 运行）

```bash
ssh -p 8022 root@<手机IP> \
  'bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/vulkan/scripts/run_phone_vulkan_baseline.sh 99 "你好" 5'
```

或在手机 Termux 原生 shell 中直接：

```bash
bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/vulkan/scripts/run_phone_vulkan_baseline.sh 99 "你好" 5
```

## 脚本说明

| 脚本 | 用途 | 推荐度 |
|---|---|---|
| `check-vulkan-env.sh` | 检查 Vulkan/OpenCL 环境、二进制、模型路径 | ⭐ 先跑 |
| `run_wsl_vulkan_baseline.sh` | WSL Vulkan 本地推理 | 仅用于验证环境 |
| `run_wsl_opencl_baseline.sh` | WSL OpenCL 本地 GPU 推理 | ⭐ 推荐 |
| `run_phone_vulkan_baseline.sh` | 手机 Vulkan 本地推理 | 仅用于验证环境 |

## 关键结论

| 后端 | 设备 | GPU offload | eval 速度 | 结论 |
|---|---|---|---|---|
| Vulkan / WSL | `llvmpipe` | ❌ | 89.6 t/s | WSL2 无 Intel Vulkan ICD，CPU fallback |
| Vulkan / Mate 40 Pro | CPU fallback | ❌ | 5.85 t/s | Mali-G78 驱动仅 Vulkan 1.1，不满足 1.2 要求 |
| OpenCL / WSL | `Intel(R) Graphics [0x7d55]` | ✅ 25/25 层 | 56.3 t/s | 可用 GPU 路径，但小模型未超 CPU |

详细分析与日志见 `docs/`。

## 构建要点

### WSL Vulkan

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan --target llama-completion -j
```

### WSL OpenCL

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-opencl -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF
cmake --build build-opencl --target llama-completion -j
```

### 手机 Vulkan（Termux 原生编译）

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan --target llama-completion -j$(nproc)
```

注意：

- 必须在 **Termux 原生 shell** 中编译和运行，生成的是 Android ELF。
- 若遇到 `fatal error: 'spawn.h' file not found`，按 `docs/vulkan-setup.md` 补充最小 `spawn.h`。
- 若 proot Ubuntu 中编译报 `Function not implemented` 写 SPIR-V，也改到 Termux 原生 shell。

## 日志说明

`logs/` 下每个日志都由对应 baseline 脚本自动生成，文件名带时间戳：

| 日志文件 | 产生命令 | 运行位置 | 关键结果 |
|---|---|---|---|
| `wsl_vulkan_baseline_20260711_231159.log` | `./run_wsl_vulkan_baseline.sh 99 "你好" 5` | WSL | Vulkan 无可用 GPU，fallback 到 `llvmpipe` CPU；eval 89.6 t/s |
| `phone_vulkan_baseline_20260711_232957.log` | `./run_phone_vulkan_baseline.sh 99 "你好" 5`（Termux 原生 shell） | Mate 40 Pro | `ggml_vulkan: Error: Vulkan 1.2 required.`，fallback 到 CPU；eval 5.85 t/s |
| `wsl_opencl_baseline_20260712_083610.log` | `./run_wsl_opencl_baseline.sh 99 "你好" 5` | WSL | OpenCL 识别 `Intel(R) Graphics [0x7d55]`，25/25 层 offload；eval 56.3 t/s |

> WSL Vulkan 和手机 Vulkan 日志都证明当前环境无法使用 Vulkan GPU；OpenCL 日志是目前 WSL 上唯一成功 GPU offload 的记录。

## 文档

| 文档 | 内容 |
|---|---|
| `docs/vulkan-baseline-report.md` | Vulkan baseline 完整报告 |
| `docs/opencl-baseline-report.md` | OpenCL baseline 完整报告 |
| `docs/vulkan-setup.md` | Vulkan 环境准备与常见问题 |
| `docs/opencl-setup.md` | OpenCL 环境准备与常见问题 |

## 注意

- 本模式是**本地推理**，不走 RPC；如需把 WSL/手机作为 RPC Worker 与 GPU PC 联动，请参考 [`../3-machine/`](../3-machine/README.md) 模式。
- `config.env` 中 `CURRENT_OPENCL_BUILD_DIR` 用于 OpenCL 脚本；`CURRENT_BUILD_DIR` 用于 Vulkan 脚本。
