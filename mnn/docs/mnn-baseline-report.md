# MNN Baseline 报告（Qwen2-0.5B-Instruct on Mate 40 Pro）

## 1. 实验目标

验证阿里巴巴 MNN 框架能否在华为 Mate 40 Pro 的 Mali-G78 GPU 上运行 LLM 推理，并对比 CPU / OpenCL / Vulkan 三后端性能。

## 2. 环境

- **手机**：华为 Mate 40 Pro
- **SoC**：Kirin 9000
- **GPU**：Mali-G78 MP24
- **系统**：Android（Termux 原生 shell）
- **MNN 版本**：3.6.0（fork 自 https://github.com/alibaba/MNN）
- **模型**：Qwen2-0.5B-Instruct

## 3. 导出结果

| 产物 | 大小 | 说明 |
|---|---|---|
| `llm.mnn` | 410 KB | 模型结构 |
| `llm.mnn.weight` | 265 MB | 4-bit 量化权重 |
| `tokenizer.mtok` | 3.9 MB | tokenizer |
| `config.json` | 502 B | 运行时配置 |
| **总计** | **271 MB** | — |

导出命令：

```bash
cd MNN/transformers/llm/export
python3 llmexport.py \
  --path /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2-0.5b-instruct \
  --export mnn --hqq \
  --dst_path /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2-0.5b-instruct-mnn \
  --mnnconvert /home/atituiset/Projects/gpu-cpu-phone-test/MNN/build-host/MNNConvert
```

## 4. WSL 验证

在 WSL x86_64 上编译 `llm_demo`，CPU 推理正常：

```text
prompt tokens num = 20
decode tokens num = 9
prefill time = 0.07 s
 decode time = 0.13 s
prefill speed = 276.59 tok/s
 decode speed = 68.12 tok/s
```

说明导出的 MNN 模型本身可用。

## 5. 手机端编译

### 5.1 OpenCL 后端

```bash
cmake -B build-opencl-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_OPENCL=ON
make llm_demo -j4
```

**问题**：编译时提示 `GLES2/gl2.h` 缺失。
- 根因：MNN OpenCL backend 在 `__ANDROID__` 下无条件 `#include <GLES2/gl2.h>`，但实际代码中并未使用 GL 相关符号。
- 解决：删除 `source/backend/opencl/core/OpenCLBackend.cpp` 中对应的 include 行。

### 5.2 Vulkan 后端

```bash
cmake -B build-vulkan-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_VULKAN=ON
make llm_demo -j4
```

配置和编译均成功；手机 Vulkan 版本为 1.1.191，MNN Vulkan 后端可以初始化。

## 6. 手机端运行结果

Prompt：`hello`（生成约 9 个 token）

| 后端 | 配置文件 | 运行时间 | 备注 |
|---|---|---|---|
| CPU | `config.json` | 1.7 s | ARM82 优化有效 |
| OpenCL low | `config.opencl.json` | 36–43 s | cache 文件写入失败 |
| OpenCL normal | `config.opencl.normal.json` | 23.1 s | 比 low 快 |
| Vulkan | `config.vulkan.json` | **6 m 37 s** | 第二次运行 6 m 48 s，无缓存改善 |

## 7. 现象分析

### 7.1 OpenCL / Vulkan 确实调用了 GPU

`clinfo` 输出：

```text
Device Name         Mali-G78 r0p1
Device Version      OpenCL 3.0 v1.r34p0-...
Device Type         GPU
Max compute units   24
```

`vulkaninfo --summary` 输出：

```text
GPU0:
  apiVersion    = 1.1.191
  deviceName    = Mali-G78
  deviceType    = INTEGRATED_GPU
```

因此不是 CPU fallback，而是 GPU 路径本身很慢。

### 7.2 为什么 GPU 比 CPU 慢？

可能原因：

1. **模型太小**：0.5B 模型层数少、隐藏维度小，GPU 调度/内存拷贝开销占比过大。
2. **MNN LLM 的 GPU kernel 对 Mali 不友好**：当前实现偏通用，未针对 ARM Mali 的 tile-based 架构做算子融合。
3. **量化与内存格式**：4-bit HQQ 权重在 GPU 上的反量化、transpose 可能成为瓶颈。
4. **Vulkan shader 编译无缓存**：首次和第二次运行时间相近，说明没有有效缓存离线 shader。
5. **cache 文件路径问题**：MNN 默认写 `tmp/mnn_cachefile.bin`，在 Termux 下路径不存在，导致 OpenCL tune 缓存失败。

## 8. 1.5B 模型补充实验

为验证“模型变大后 GPU 是否会反超 CPU”，导出并测试了 **Qwen2-1.5B-Instruct**（MNN 导出后 835 MB）。

| 后端 | 运行时间（prompt=`hello`，生成约 9 token） | 与 0.5B 对比 |
|---|---|---|
| CPU | 4.7 s | 0.5B 的 2.8 倍 |
| OpenCL normal | 45.5 s | 0.5B 的 2.0 倍 |
| Vulkan | 未跑（0.5B 已需 6 m+，预计更慢） | — |

结论：**模型从 0.5B 增大到 1.5B 后，OpenCL 依然比 CPU 慢约 10 倍**，没有因为计算量增加而反超。说明 MNN LLM 的 OpenCL/Vulkan 路径在 Mali-G78 上的瓶颈不只是“调度开销”，而是 kernel 本身效率低。

## 9. 3B 模型补充实验

为验证“模型继续变大后 GPU 是否会反超 CPU”，从 ModelScope 下载了 **Qwen2.5-3B-Instruct-MNN**（4.5 GB，4-bit 量化）。

### 9.1 CPU 结果

| 后端 | 运行时间（prompt=`hello`） | 与 1.5B 对比 | 备注 |
|---|---|---|---|
| CPU | **56.97 s** | 1.5B 的 12.1 倍 | 输出较长，约数百 token |

CPU 时间从 1.5B 的 4.7 s 跳到 3B 的 57 s，增幅远大于模型参数增幅，说明 3B 已经超出手机 CPU 的“舒适区”。

### 9.2 OpenCL 结果

第一次用 `precision=normal, memory=normal` 运行时，手机 SSH 连接中断，随后 `Connection refused`，推测是 **OpenCL 分配显存/系统内存时 OOM 导致 Termux/sshd 被系统杀掉或手机重启**。

改用 **`precision=low, memory=low`** 后重新测试，OpenCL 可以稳定跑完：

| 后端 | 运行时间（prompt=`hello`） | 与 CPU 对比 | 备注 |
|---|---|---|---|
| OpenCL low | **1 m 25.6 s** | 比 CPU 慢 ~1.5 倍 | 内存配置为 low 后稳定 |

虽然仍慢于 CPU，但相比 1.5B OpenCL normal（45.5 s）的增幅，3B 低内存 OpenCL 的 85.6 s 说明 **降低内存/精度后 Mali GPU 可以承载 3B 模型**，只是效率仍不及 ARM82 CPU。

### 9.3 3B 结论

- CPU 仍能跑完，但延迟已到数十秒级别。
- OpenCL normal 在 3B 下 OOM 崩溃；OpenCL low 可稳定运行但比 CPU 慢。
- **MNN LLM 的 Mali GPU 路径在 0.5B/1.5B 已显著慢于 CPU，3B 又出现 OOM/低精度慢于 CPU**，说明当前实现既不快也不稳。

## 10. 关于 WSL ↔ 手机分层推理

本项目最初的分支 `feat/3-machine-inference` 确实尝试 **WSL 主机 + 手机通过 SSH tunnel 做 llama.cpp RPC 分层推理**。但切换到 MNN / ncnn 后：

- **WSL 仅作为“工具机”**：clone 源码、编译 x86 工具（如 `MNNConvert`）、导出/下载模型。
- **手机作为唯一推理设备**：`llm_demo`、`benchncnn` 全部在手机上运行，单机选择 backend（`cpu`/`opencl`/`vulkan`）。
- **没有跨设备分层**：MNN LLM runtime 未暴露类似 llama.cpp RPC 的多机协同接口；ncnn 的 runtime 同样是单机方案。因此这两个框架无法把 WSL CPU 和手机 GPU 拼成一张卡。

## 11. 下一步

- **A. 换 ncnn**：尝试 ncnn 的 Vulkan 后端，看是否在 Mali 上有更好的 LLM 性能。

## 12. 参考命令

手机端 OpenCL 运行：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/MNN/build-opencl-llm
LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn/config.opencl.normal.json \
  /data/data/com.termux/files/home/mnn_prompt.txt
```

手机端 Vulkan 运行：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/MNN/build-vulkan-llm
LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn/config.vulkan.json \
  /data/data/com.termux/files/home/mnn_prompt.txt
```

3B CPU 运行：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/MNN/build-opencl-llm
LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2.5-3b-instruct-mnn/config.cpu.json \
  /data/data/com.termux/files/home/mnn_prompt_3b.txt
```

3B OpenCL low-memory 运行：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/MNN/build-opencl-llm
LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2.5-3b-instruct-mnn/config.opencl.low.json \
  /data/data/com.termux/files/home/mnn_prompt_3b.txt
```
