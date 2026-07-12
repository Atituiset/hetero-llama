# WSL OpenCL 本地 baseline 实验报告

> 分支：`feat/vulkan-local`  
> 实验时间：2026-07-12  
> 目标：在 WSL2 中绕过 Vulkan 限制，使用 llama.cpp OpenCL 后端调用 Intel 核显进行本地 GPU 推理，并记录关键问题与规避方法。

---

## 1. 实验环境

| 项目 | WSL |
|------|-----|
| 设备 | 当前 WSL2 / Ubuntu |
| SoC / GPU | x86_64 / Intel Graphics [0x7d55] |
| 操作系统 | WSL2 / Ubuntu 24.04 |
| llama.cpp commit | `152d337fa` |
| 后端 | OpenCL（`GGML_OPENCL=ON`） |
| OpenCL 平台 | Intel(R) OpenCL Graphics 3.0 |
| 模型 | `qwen2-0.5b-instruct-q4_0.gguf`（336 MB） |
| 推理二进制 | `llama-completion` |

---

## 2. 关键发现

### 2.1 Vulkan 在 WSL2 中无法识别 Intel GPU

- `vulkaninfo --summary` 只能看到 `llvmpipe`（CPU 软解）。
- 强制加载 `intel_icd.json` 后报错 `Failed to detect any valid GPUs`。
- 系统里没有 Mesa Dozen（`dzn`）驱动，无法把 Vulkan 调用转译为 D3D12。
- 结论：**当前环境下 llama.cpp Vulkan 后端无法使用 Intel GPU**。

### 2.2 OpenCL 可以正常识别 Intel GPU

安装 Intel Compute Runtime 后，`clinfo` 输出：

```text
Number of platforms                               1
  Platform Name                                   Intel(R) OpenCL Graphics
  Platform Version                                OpenCL 3.0
Number of devices                                 1
  Device Name                                     Intel(R) Graphics [0x7d55]
  Device Vendor                                   Intel(R) Corporation
  Device Version                                  OpenCL 3.0 NEO
```

这说明 WSL2 的 `/dev/dxg` 桥接对 OpenCL 是有效的。

### 2.3 编译 OpenCL 后端的两个注意点

1. **必须关闭 Adreno 专用内核**
   llama.cpp 默认 `GGML_OPENCL_USE_ADRENO_KERNELS=ON`，在非 Adreno GPU 上会直接把设备标记为不支持并 fallback 到 CPU。需要显式关闭：
   ```bash
   cmake -B build-opencl -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF
   cmake --build build-opencl --target llama-completion -j$(nproc)
   ```

2. **OpenCL 头文件缺失**
   默认 apt 源无法下载 `opencl-c-headers`。本次从 Windows 宿主机已安装的 Python venv（ComfyUI 依赖）中复制了 `/usr/include/CL` 头文件：
   ```bash
   sudo cp -r /mnt/c/Users/Atituiset/AppData/Local/Programs/AI\ Playground/resources/ComfyUI/.venv/include/CL /usr/include/
   ```
   同时需要确保 `libOpenCL.so` 软链接存在：
   ```bash
   sudo ln -sf /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so
   ```

---

## 3. 运行命令

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan
./run_wsl_opencl_baseline.sh 99 "你好" 5
```

脚本会自动使用 `config.env` 中定义的 `CURRENT_OPENCL_BUILD_DIR` 和 `MODEL_PATH`，并写入 `logs/wsl_opencl_baseline_YYYYMMDD_HHMMSS.log`。

---

## 4. 实验结果

### 4.1 输出示例

| 输入 | 输出 |
|------|------|
| 你好 | `你好(OPPO)华为Mate` |

> 输出看起来比较乱，是因为 `-no-cnv` 关闭了对话模板后，模型仍按基础采样生成；这不影响 GPU offload 的验证。

### 4.2 GPU 分配确认（来自日志）

```text
llama_prepare_model_devices: using device GPUOpenCL (Intel(R) Graphics [0x7d55]) (unknown id) - 13696 MiB free
load_tensors: offloaded 25/25 layers to GPU
```

### 4.3 性能数据

| 后端 | 加载时间 | prompt eval | eval（生成） | 备注 |
|------|----------|-------------|--------------|------|
| CPU（Vulkan baseline，llvmpipe） | 1387 ms | 344 t/s | 89.6 t/s | 18 线程 x86 CPU |
| OpenCL（Intel GPU） | 784 ms | inf（1 token） | 56.3 t/s | 25/25 层 offload |

> 虽然 OpenCL 成功调用了 GPU，但生成速度反而比 CPU 慢。主要原因：
> - 模型极小（0.5B），GPU 调度和内存拷贝开销占比高。
> - Intel 核显通过 WSL2 的 `/dev/dxg` + D3D12 桥接，本身有一定额外延迟。
> - 对更大的模型或更长序列，GPU offload 的收益会更明显。

### 4.4 内存分配

```text
memory breakdown [MiB]
  - GPUOpenCL (Intel(R) Graphics [0x7d55]) | 14720 = 13696 + (1012 = 330 + 384 + 298) + 11
  - Host                                   |                   173 =   137 +       0 +      35
```

模型权重（330 MiB）和计算缓冲都放在了 GPUOpenCL 设备上。

---

## 5. 日志文件

| 日志 | 路径 |
|------|------|
| WSL OpenCL baseline | `logs/wsl_opencl_baseline_20260712_083610.log` |

---

## 6. 结论

1. **Vulkan 在 WSL2 当前环境不可用**：只有 `llvmpipe` CPU 软解，缺少 `dzn` 驱动。
2. **OpenCL 是可行的替代方案**：安装 Intel Compute Runtime 后，llama.cpp OpenCL 后端能识别并 offload 到 Intel 核显。
3. **GPU 已真正参与推理**：25/25 层全部 offload，内存分配在 GPUOpenCL 上。
4. **性能尚未超过 CPU**：对 0.5B 小模型，核显+WSL2 桥接开销导致生成速度低于多核 CPU；可作为后续大模型/长序列实验的基础。

---

## 参考来源

- Intel Compute Runtime (OpenCL NEO): https://github.com/intel/compute-runtime
- llama.cpp OpenCL backend: https://github.com/ggerganov/llama.cpp/blob/master/docs/backend/OpenCL.md
- WSL2 GPU 半虚拟化：Microsoft WDDM GPU-PV + `/dev/dxg`
