# 手机端 GPU 加速尝试总览

> 记录到目前为止在华为 Mate 40 Pro（Kirin 9000，Mali-G78 MP24）上尝试过的所有 GPU 加速路径。

## 硬件信息

| 项目 | 值 |
|---|---|
| 手机 | 华为 Mate 40 Pro |
| SoC | Kirin 9000 |
| GPU | Mali-G78 MP24 |
| OpenCL | 3.0，ARM Platform，设备名 `Mali-G78 r0p1`，24 CU |
| Vulkan | 1.1.191 |

## 各框架/后端尝试结果

### 1. llama.cpp Vulkan

| 平台 | 结果 | 速度 |
|---|---|---|
| WSL | CPU fallback（`llvmpipe`） | 89.6 t/s |
| 手机 | ❌ 无法使用 GPU | — |

**根因**：
- WSL2 没有 Intel Vulkan ICD，只有 Mesa llvmpipe。
- 手机 Mali 驱动只暴露 Vulkan 1.1，而 llama.cpp Vulkan 后端要求 1.2。

### 2. llama.cpp OpenCL

| 平台 | 结果 | 速度 |
|---|---|---|
| WSL | ✅ GPU  offload 25/25 | 56.3 t/s |
| 手机 | ❌ GPU 被丢弃 | 38.05 t/s（CPU） |

**根因**：
- WSL Intel OpenCL 可用。
- 手机端 `ggml_opencl: unsupported GPU 'Mali-G78 r0p1'`，llama.cpp OpenCL 后端只支持 Adreno/Intel。

### 3. MNN LLM

| 模型 | 后端 | 运行时间（prompt=`hello`，约 9 token） | 结论 |
|---|---|---|---|
| Qwen2-0.5B | CPU | 1.7 s | 快 |
| Qwen2-0.5B | OpenCL | 23 s | 比 CPU 慢 ~13 倍 |
| Qwen2-0.5B | Vulkan | 6 m 37 s | 极慢 |
| Qwen2-1.5B | CPU | 4.7 s | 快 |
| Qwen2-1.5B | OpenCL | 45.5 s | 比 CPU 慢 ~10 倍 |
| Qwen2-1.5B | Vulkan | 未跑 | 预计更慢 |
| Qwen2.5-3B | CPU | 57.0 s | 仍能跑完，但已明显变慢 |
| Qwen2.5-3B | OpenCL normal | ❌ OOM 崩溃 | 运行中 SSH 断开，sshd 失联 |
| Qwen2.5-3B | OpenCL low | 85.6 s | 降低内存/精度后可稳定运行，仍慢于 CPU |
| Qwen2.5-3B | Vulkan | 未跑 | 预计同样崩溃或极慢 |

**结论**：MNN 能调用 Mali-G78 的 OpenCL/Vulkan，但 LLM 推理 GPU 路径比 CPU 慢很多；3B 下 OpenCL normal 直接 OOM，只有 low 内存配置能跑完。

### 4. ncnn LLM（Qwen3-0.6B）

| 后端 | 运行时间（prompt=`hello`，约 9 token） | 结论 |
|---|---|---|
| CPU（4 线程） | **40.7 s** | 可正常输出 |
| Vulkan（Mali-G78） | > 100 min CPU time / 无有效输出 | 卡在首次推理，基本不可用 |

**结论**：ncnn_llm 能在 Mate 40 Pro 上跑通 CPU 路径，但 Vulkan 路径对 0.6B LLM 也卡住，与 benchncnn 中 `vision_transformer` 慢 25 倍的现象一致。

### 5. ncnn Vulkan benchmark

| 测试 | CPU（1 线程） | Vulkan（Mali-G78） | 结论 |
|---|---|---|---|
| squeezenet | 10.75 ms | 29.69 ms | GPU 慢 |
| mobilenet | 19.31 ms | 35.47 ms | GPU 慢 |
| vgg16 | 159.32 ms | 77.11 ms | GPU 快 2.1 倍 |
| vision_transformer | 421.80 ms | 10786 ms | GPU 慢 25 倍 |

**结论**：ncnn Vulkan 在 Mali 上可运行，但只在大卷积网络上加速；Transformer 类模型反而极慢。

## 综合分析

| 框架 | 能否调用 Mali GPU | LLM 是否加速 | 主要瓶颈 |
|---|---|---|---|
| llama.cpp Vulkan | 否（驱动版本不够） | 否 | Vulkan 1.2 要求 |
| llama.cpp OpenCL | 否（GPU 白名单） | 否 | 只支持 Adreno/Intel |
| MNN OpenCL | ✅ | 否（慢 10 倍 / 3B 崩溃） | LLM kernel 对 Mali 不友好 / OOM |
| MNN Vulkan | ✅ | 否（极慢 / 预计 3B 崩溃） | shader 编译/调度开销、显存不足 |
| ncnn Vulkan | ✅ | 否（CNN 选择性加速；LLM 卡住/极慢） | Transformer 在 Mali 上极慢；ncnn_llm Vulkan 首次推理卡住 |

**注意**：MNN / ncnn 均为单机 runtime，本项目未实现 WSL 与手机之间的跨设备分层推理；WSL 只负责模型导出/编译工具，推理全部在手机上执行。最初 `feat/3-machine-inference` 分支的 llama.cpp RPC 分层方案与 MNN/ncnn 不通用。

## 当前有效 GPU 路径

- **WSL OpenCL + llama.cpp**：Intel GPU 可 offload 25/25 层，56.3 t/s。
- **手机 CPU（MNN ARM82 / ncnn_llm CPU）**：当前手机上唯一能用的 LLM 推理方式。

手机上 Mali-G78 的 **OpenCL/Vulkan LLM 路径目前均无法实用化**：
- llama.cpp： outright 不支持 Mali；
- MNN：能调用 GPU，但比 CPU 慢 10 倍，3B 还 OOM；
- ncnn：LLM Vulkan 首次推理即卡住。

## 下一步建议

1. **换 Adreno 手机测试**：Mali-G78 对通用 GPU 算子支持不佳，Adreno 可能是更好的目标。
2. **接受 CPU 方案**：手机端用 MNN CPU，PC 端用 llama.cpp OpenCL，通过 RPC 协同。
3. **等待框架优化**：MNN/ncnn 对 Mali 的 LLM GPU kernel 有明显优化空间，但不在本项目可控范围内。

## 相关文档

- `vulkan/docs/vulkan-deep-dive.md`
- `vulkan/docs/opencl-baseline-report.md`
- `mnn/docs/mnn-baseline-report.md`
- `ncnn-llm/docs/ncnn-benchmark-report.md`
