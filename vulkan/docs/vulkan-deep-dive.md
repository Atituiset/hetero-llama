# Vulkan 阶段问题深入分析

> 目标：把 WSL（当前机器）和华为 Mate 40 Pro 的 Vulkan baseline 实验中遇到的问题逐条拆开，讲清楚**现象、根因、验证过程和规避/修复路径**。  
> 如果你只想快速复现，直接看 [`vulkan-setup.md`](./vulkan-setup.md) 和 [`opencl-setup.md`](./opencl-setup.md)。

---

## 0. 实验目标与环境

| 端 | 设备 / SoC / GPU | OS / 运行环境 | llama.cpp 后端 |
|---|---|---|---|
| WSL | x86_64 / Intel Graphics [0x7d55] | WSL2 / Ubuntu 24.04 | Vulkan / OpenCL |
| Mate 40 Pro | Kirin 9000 / Mali-G78 | Termux + proot Ubuntu | Vulkan |

共同前提：没有独立 GPU PC；Windows 宿主机能看到 Intel GPU/NPU，但 WSL2 与手机都要靠自己。

---

## 1. 问题总览

| # | 问题 | 影响端 | 严重程度 | 是否解决 |
|---|---|---|---|---|
| 1 | Vulkan 只能看到 `llvmpipe`，看不到 Intel GPU | WSL | 🔴 阻断 GPU offload | ❌ 未解决，绕到 OpenCL |
| 2 | `vulkan-shaders-gen` 在 proot Ubuntu 中写 SPIR-V 失败 | 手机 | 🟡 阻断编译 | ✅ 改 Termux 原生编译 |
| 3 | Termux Bionic 缺少 `<spawn.h>` | 手机 | 🟡 阻断部分 target 编译 | ✅ 补最小头文件 |
| 4 | Android ELF 在 proot Ubuntu 中运行报 `invalid ELF header` | 手机 | 🟡 阻断运行 | ✅ 改 Termux 原生运行 |
| 5 | Mali-G78 只支持 Vulkan 1.1，llama.cpp 要求 1.2 | 手机 | 🔴 阻断 GPU offload | ❌ 未解决，需换驱动 |
| 6 | OpenCL 默认启用 Adreno kernel，把 Intel 丢弃 | WSL | 🟡 阻断 OpenCL GPU | ✅ 关闭 Adreno kernel |
| 7 | OpenCL 头文件 `CL/cl.h` 缺失 | WSL | 🟡 阻断编译 | ✅ 从 Windows venv 复制 |

---

## 2. WSL 端：Vulkan 为什么看不到 Intel GPU

### 2.1 现象

```bash
vulkaninfo --summary
```

只列出 `llvmpipe`（Mesa 的 CPU 软解实现），没有 Intel 物理设备。当前实际输出：

```text
==========
VULKANINFO
==========

Vulkan Instance Version: 1.3.275
...
Devices:
========
GPU0:
	apiVersion         = 1.4.318
	deviceType         = PHYSICAL_DEVICE_TYPE_CPU
	deviceName         = llvmpipe (LLVM 20.1.2, 256 bits)
	driverID           = DRIVER_ID_MESA_LLVMPIPE
	driverName         = llvmpipe
```

运行：

```bash
./run_wsl_vulkan_baseline.sh 99 "你好" 5
```

日志里出现：

```text
warning: no usable GPU found, --gpu-layers option will be ignored
```

### 2.2 根因：WSL2 的 GPU 透传不等于 Vulkan ICD 可用

Windows 宿主机能看到 Intel GPU/NPU，是因为有 Intel 显卡驱动 + WDDM。WSL2 通过 **GPU-PV（GPU Paravirtualization）** 把 GPU 暴露给 Linux 虚拟机，核心机制是：

- `/dev/dxg`：WSL2 里的虚拟 GPU 设备。
- D3D12：用户态通过 D3D12 调用 Windows 宿主 GPU 驱动。

这个路径对 **DirectX 12 / CUDA / OpenCL** 有效，但对 **Vulkan** 需要额外的一层：**Mesa Dozen (`dzn`)**，即 Vulkan-on-D3D12 翻译层。当前 Ubuntu 没有安装 `dzn`，也没有 Intel 原生 Vulkan ICD（`intel_icd.x86_64.json` 在 WSL2 里无法直接驱动真实硬件）。

因此 `vulkaninfo` 只能回退到 Mesa 的 LLVM pipe（CPU 软解）。

### 2.3 验证过的尝试

1. **强制加载 Intel ICD**

   手动把 Windows 侧或 Ubuntu 的 `intel_icd.json` 丢到 `/usr/share/vulkan/icd.d/`，`vulkaninfo` 报：

   ```text
   Failed to detect any valid GPUs
   ```

   原因：ICD 需要访问真实 PCIe GPU，而 WSL2 里没有这个路径。

2. **检查 Mesa Dozen**

   ```bash
   dpkg -l | grep -i dzn
   ```

   无结果。`dzn` 是 Vulkan 1.1/1.2 到 D3D12 的转译驱动，没装它就不可能把 Vulkan 调用桥接到 WSL2 的 D3D12。

### 2.4 结论

- **当前 WSL2 环境下，llama.cpp Vulkan 后端无法使用 Intel GPU**。
- 想要 Vulkan GPU offload，可选路径：
  1. 安装 Mesa Dozen（`vulkan-dzn` / `mesa-vulkan-drivers` 中是否包含视发行版而定）。
  2. 直接装原生 Linux（非 WSL2），使用 Intel `ANV` Vulkan 驱动。
  3. 换用 NVIDIA/AMD 独显 PC，WSL2 对 NVIDIA Vulkan 支持更好（有官方 ICD）。

---

## 3. 手机端：编译与运行陷阱

### 3.1 问题：proot Ubuntu 里编译 `vulkan-shaders-gen` 写 SPIR-V 失败

#### 现象

在 `proot-distro login ubuntu` 里执行：

```bash
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan --target llama-completion -j
```

到生成 SPIR-V 时：

```text
Function not implemented
```

#### 根因

`vulkan-shaders-gen` 需要某些文件/内存映射或 `futex`/`eventfd` 等机制。proot 是对系统调用的用户态重定向，**没有完整实现所有 syscall**，特别是与进程间同步、内存映射相关的调用。写 SPIR-V 时触发了未实现的 syscall，直接返回 `ENOSYS`（Function not implemented）。

#### 规避

改在 **Termux 原生 shell** 中编译。Termux 直接跑在 Android Bionic libc 上，syscall 路径完整。源码仍放在 proot Ubuntu 目录下（Termux 能访问），但编译命令在 Termux 中执行：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan --target llama-completion -j$(nproc)
```

---

### 3.2 问题：Termux Bionic 缺少 `<spawn.h>`

#### 现象

编译 `tools/server` 或 `tools/mtmd` 时：

```text
fatal error: 'spawn.h' file not found
```

#### 根因

Termux 的 Bionic libc 头文件在某些版本里没有提供 `<spawn.h>`，而 llama.cpp 的 `vendor/sheredom/subprocess.h` 依赖 POSIX spawn API。 baseline 本身不调用 spawn，但 CMake target 默认会编译这些辅助代码，导致整体构建失败。

#### 规避

在 Termux 系统 include 路径补充一个最小化的 `spawn.h`：

```bash
cat > /data/data/com.termux/files/usr/include/spawn.h <<'EOF'
#ifndef _SPAWN_H_
#define _SPAWN_H_
#include <sys/cdefs.h>
#include <sys/types.h>
#include <sched.h>
#include <signal.h>
__BEGIN_DECLS
typedef struct __posix_spawnattr* posix_spawnattr_t;
typedef struct __posix_spawn_file_actions* posix_spawn_file_actions_t;
int posix_spawn(pid_t* __pid, const char* __path, const posix_spawn_file_actions_t* __actions, const posix_spawnattr_t* __attr, char* const __argv[], char* const __envp[]);
int posix_spawnp(pid_t* __pid, const char* __file, const posix_spawn_file_actions_t* __actions, const posix_spawnattr_t* __attr, char* const __argv[], char* const __envp[]);
int posix_spawn_file_actions_init(posix_spawn_file_actions_t* __actions);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t* __actions);
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t* __actions, int __fd, const char* __path, int __flags, mode_t __mode);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t* __actions, int __fd);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t* __actions, int __fd, int __new_fd);
__END_DECLS
#endif
EOF
```

> 注意：这只是让编译通过；baseline 不实际调用 spawn。

---

### 3.3 问题：Android ELF 不能在 proot Ubuntu 里运行

#### 现象

在 Termux 原生编译出 `llama-completion` 后，回到 `proot-distro login ubuntu` 运行：

```text
/lib/aarch64-linux-gnu/libc.so: invalid ELF header
```

#### 根因

Termux 原生工具链生成的是 **Android ELF**，动态链接器是 `/system/bin/linker64`，依赖 Bionic libc。proot Ubuntu 里是 glibc + `/lib/ld-linux-aarch64.so.1`，二者 ABI 不兼容，无法加载 Android ELF。

#### 规避

运行时也必须在 **Termux 原生 shell** 中。脚本 [`run_phone_vulkan_baseline.sh`](../scripts/run_phone_vulkan_baseline.sh) 已自动使用 Termux 可访问的绝对路径指向 proot Ubuntu 目录下的源码和模型。

---

### 3.4 问题：Mali-G78 只支持 Vulkan 1.1

#### 现象

Termux 里 `vulkaninfo --summary` 能看到 `Mali-G78`，但运行 baseline 时：

```text
ggml_vulkan: Error: Vulkan 1.2 required.
warning: no usable GPU found, --gpu-layers option will be ignored
```

最终 fallback 到 CPU，eval 约 5.85 t/s。

#### 根因

llama.cpp 的 Vulkan backend 明确依赖 Vulkan 1.2（可能用到 timeline semaphore、shader float16/int8 扩展、subgroup 操作等）。Mate 40 Pro 的 Mali-G78 驱动/loader 在 Termux 中只报告 **Vulkan 1.1**，因此初始化直接失败。

#### 为什么不是硬件不支持

Mali-G78 硬件本身支持 Vulkan 1.3/1.4（已通过 [Khronos 认证](https://www.khronos.org/conformance/adopters/conformant-products/vulkan)），但华为/Termux 当前提供的用户态驱动和 `libvulkan.so` loader 只暴露了 1.1。要升级有下面几条路：

| 方案 | 复杂度 | 是否需要 root | 成功率 | 说明 |
|---|---|---|---|---|
| **A. 换用 OpenCL backend** | 低 | 否 | ❌ 已验证失败 | llama.cpp OpenCL 后端只支持 Adreno/Intel，Mali 被丢弃。 |
| **B. 安装 `mesa-vulkan-icd-wrapper`** | 中 | 否 | 中 | Termux 社区方案，用 Mesa/PanVK 替代系统 loader。若它把 Mali-G78 驱动到 Vulkan 1.2+，则 `ggml_vulkan` 可通过。 |
| **C. 刷入第三方 Vulkan 驱动包** | 中高 | 通常需要 | 中低 | 如 Eden/Uzuy 等模拟器预置的 Mali 驱动包，可替换系统 `libGLES_mali.so`/`libvulkan.so`，但依赖内核/firmware 匹配。 |
| **D. 刷机 + 自定义内核 + PanVK** | 很高 | 是 | 低 | Mesa PanVK 对 Mali v10（含 G78）已有早期支持，但在 Android/Termux 上跑通需大量适配。 |
| **E. 等华为/Termux 官方更新** | 低 | 否 | 低 | Mate 40 Pro 已停更主要版本，官方 Vulkan 1.2 更新可能性极小。 |

#### 推荐先尝试 B：`mesa-vulkan-icd-wrapper`

社区已经有 Mali 设备成功先例（参考 [termux-mali-gpu-acceleration](https://github.com/Theguilherm3/termux-mali-gpu-acceleration) 和 [xMeM/vulkan-wsi-layer](https://github.com/xMeM/vulkan-wsi-layer)）。在 Termux 原生 shell 中大致流程：

```bash
# 1. 移除软件 ICD，安装通用 loader
pkg remove '*icd-swrast'
pkg install vulkan-loader-generic wget openssl

# 2. 安装 mesa-vulkan-icd-wrapper（版本号以 release 页面最新为准）
cd
wget https://github.com/ar37-rs/virgl-angle/releases/download/latest/mesa-vulkan-icd-wrapper_25.0.0-1_aarch64.deb
dpkg -i mesa-vulkan-icd-wrapper_25.0.0-1_aarch64.deb
apt --fix-broken install

# 3. 指定 ICD
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/wrapper_icd.aarch64.json

# 4. 验证
vulkaninfo --summary
```

关键看 `vulkaninfo --summary` 里的 `apiVersion`：

- 如果显示 **1.2.xxx 或更高**：恭喜，Mali-G78 已可用 Vulkan 1.2+，重新编译 `GGML_VULKAN=ON` 即可。
- 如果仍显示 **1.1.xxx**：说明 wrapper 也没有把 G78 的 Vulkan 版本提上来，只能退回方案 A（OpenCL）或方案 D（刷机）。

> ⚠️ 注意：`mesa-vulkan-icd-wrapper` 并不能保证所有 Mali 设备都到 1.2；Mali-G78 在 Mesa PanVK 里的支持仍在演进中（[Phoronix 报道](https://www.phoronix.com/news/PanVK-Vulkan-Mali-v10)、[Vulkan 1.2 合并报道](https://www.phoronix.com/news/PanVK-Vulkan-1.2-Merged-Mesa)）。

#### 结论

- **当前 Mate 40 Pro 上，Vulkan 和 OpenCL 都无法 GPU offload**。
- **唯一不修改源码的出路**：接受 CPU fallback，或在测试机上尝试 `mesa-vulkan-icd-wrapper` 看能不能把 Vulkan 提到 1.2。

### 3.5 补充验证：OpenCL backend 也不支持 Mali-G78

我们在手机上实际安装了 Termux 的 OpenCL 环境并编译了 `GGML_OPENCL=ON`，结果遇到新的阻断点：llama.cpp OpenCL 后端目前**只支持 Adreno 和 Intel**，Mali 不在白名单里。

安装命令：

```bash
pkg install -y clinfo ocl-icd opencl-headers opencl-vendor-driver
```

`clinfo` 能正确识别 Mali-G78：

```text
Number of platforms                               1
  Platform Name                                   ARM Platform
  Platform Version                                OpenCL 3.0 v1.r34p0-...
Number of devices                                 1
  Device Name                                     Mali-G78 r0p1
  Device Version                                  OpenCL 3.0 v1.r34p0-...
```

但运行 `llama-completion` 时：

```text
0.00.155.807 W ggml_opencl: unsupported GPU 'Mali-G78 r0p1'.
0.00.155.850 W ggml_opencl: drop unsupported device 'Mali-G78 r0p1'.
warning: no usable GPU found, --gpu-layers option will be ignored
```

#### 根因

`ggml-opencl.cpp` 的 `ggml_opencl_is_device_supported` 里硬编码了：

```cpp
if (strstr(dev_ctx->device_name.c_str(), "Adreno") ||
    strstr(dev_ctx->device_name.c_str(), "Qualcomm") ||
    strstr(dev_ctx->device_version.c_str(), "Adreno")) {
    dev_ctx->gpu_family = GPU_FAMILY::ADRENO;
} else if (strstr(dev_ctx->device_name.c_str(), "Intel")) {
    dev_ctx->gpu_family = GPU_FAMILY::INTEL;
} else {
    GGML_LOG_WARN("ggml_opencl: unsupported GPU '%s'.\n", ...);
    return false;
}
```

后端大量分支都按 `ADRENO` / `INTEL` 写死（subgroup size、kernel 选择、buffer 策略等），把 Mali 加进去等于要写一套 Mali 专用后端，不是简单改一行能解决的。

#### 结论

- **Mate 40 Pro 上，llama.cpp 的 OpenCL backend 同样无法 GPU offload**。
- 这次 fallback 到 CPU 后 eval 约 **38 t/s**（见 `logs/phone_opencl_baseline_20260712_112233.log`），比 Vulkan CPU fallback 的 5.85 t/s 快，但仍不是 GPU 加速。
- 因此，在 **不修改 llama.cpp 源码** 的前提下，手机端目前只能接受 CPU fallback。

---

## 4. OpenCL 替代路径的问题

既然 Vulkan 在两端都走不通，回到 WSL 端尝试 OpenCL。安装 `intel-opencl-icd` 后，`clinfo` 能正确识别核显：

```text
Number of platforms                               1
  Platform Name                                   Intel(R) OpenCL Graphics
  Platform Vendor                                 Intel(R) Corporation
  Platform Version                                OpenCL 3.0
Number of devices                                 1
  Device Name                                     Intel(R) Graphics [0x7d55]
  Device Vendor                                   Intel(R) Corporation
  Device Version                                  OpenCL 3.0 NEO
```

这说明 WSL2 的 `/dev/dxg` 桥接对 OpenCL 是有效的，只是 Vulkan 还缺一层转译。

### 4.1 问题：OpenCL 默认启用 Adreno kernel，Intel 被标记为不支持

#### 现象

编译运行后日志提示：

```text
drop unsupported device 'Intel(R) Graphics ...'
```

模型全部跑在 CPU 上。

#### 根因

llama.cpp 的 CMake 默认：

```cmake
option(GGML_OPENCL_USE_ADRENO_KERNELS "Use Adreno optimized kernels" ON)
```

Adreno kernel 路径里有一组高通 GPU 特化的 kernel 和 check；非 Adreno 设备会被直接丢弃。

#### 规避

显式关闭：

```bash
cmake -B build-opencl -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF
cmake --build build-opencl --target llama-completion -j
```

---

### 4.2 问题：OpenCL 头文件 `CL/cl.h` 缺失

#### 现象

```text
fatal error: CL/cl.h: No such file or directory
```

#### 根因

当前 Ubuntu apt 源无法下载 `opencl-c-headers`（网络/源问题）。

#### 规避

从 Windows 宿主机已有的 Python/ComfyUI venv 中复制头文件：

```bash
sudo cp -r /mnt/c/Users/Atituiset/AppData/Local/Programs/AI\ Playground/resources/ComfyUI/.venv/include/CL /usr/include/
sudo ln -sf /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so
```

---

## 5. 性能与正确性验证

### 5.1 WSL Vulkan（CPU fallback）

```text
load time      = 1387 ms
prompt eval    = 344 t/s
eval           = 89.6 t/s
```

说明模型加载和推理链路正常，只是没 GPU。

### 5.2 手机 Vulkan（CPU fallback）

```text
ggml_vulkan: Error: Vulkan 1.2 required.
warning: no usable GPU found, --gpu-layers option will be ignored
...
eval = 5.85 t/s
```

说明 Mali GPU 没被使用，纯 CPU 跑在 ARM NEON 上。

### 5.3 WSL OpenCL（GPU offload 成功）

```text
llama_prepare_model_devices: using device GPUOpenCL (Intel(R) Graphics [0x7d55]) ...
load_tensors: offloaded 25/25 layers to GPU
load time      = 784 ms
eval           = 56.3 t/s
memory breakdown:
  GPUOpenCL (Intel(R) Graphics [0x7d55]) | 14720 = 13696 + (1012 = 330 + 384 + 298) + 11
  Host                                     | 173
```

权重（330 MiB）、KV cache（384 MiB）、compute buffer（298 MiB）都落在 GPUOpenCL 上，证明是真正的 GPU offload。

---

## 6. 为什么 OpenCL 能成而 Vulkan 不能

| 维度 | Vulkan | OpenCL |
|---|---|---|
| WSL2 透传机制 | 需要 Mesa Dozen (`dzn`) 把 Vulkan 转 D3D12 | 直接通过 `/dev/dxg` + Intel Compute Runtime 到 D3D12 |
| WSL2 驱动现状 | 无 Intel Vulkan ICD，无 dzn | 有 `intel-opencl-icd`，OpenCL 3.0 可用 |
| 手机端 | 需要 Vulkan 1.2，Mali 驱动只到 1.1 | 未在手机端测试 OpenCL，但 Mali-G78 硬件支持 OpenCL 2.0，理论上可行 |
| llama.cpp 支持 | 要求严格（1.2 + 特定扩展） | 路径更成熟，Intel NEO 支持好 |

核心差异：**WSL2 对 OpenCL 的桥接已经由 Intel Compute Runtime 完成，而 Vulkan 还缺一层 `dzn` 转译。**

---

## 7. 可行的下一步与修复成本

### 7.1 WSL 端：让 Vulkan 真正工作

| 方案 | 复杂度 | 成功率 | 备注 |
|---|---|---|---|
| 安装 Mesa Dozen | 中 | 中 | 需确认 Ubuntu 包名和 Vulkan 1.2 支持 |
| 换用原生 Linux 双系统 | 高 | 高 | 直接走 Intel ANV 驱动，但需额外安装系统 |
| 使用 NVIDIA/AMD 独显 PC | 高 | 高 | 不在当前设备范围 |
| 继续用 OpenCL | 低 | 已验证 | 当前最优解 |

### 7.2 手机端：让 Vulkan 真正工作

| 方案 | 复杂度 | 成功率 | 备注 |
|---|---|---|---|
| 刷入支持 Vulkan 1.2 的华为/麒麟驱动 | 很高 | 低 | 华为官方未开放 |
| Mesa Turnip | 很高 | 低 | 主要面向 Adreno，Mali 支持实验性 |
| 改用 OpenCL / CLBlast | 中 | 中 | Mali-G78 支持 OpenCL 2.0，可试 |
| 继续 CPU RPC | 低 | 已验证 | 当前 main 模式的选择 |

### 7.3 推荐后续动作

1. **WSL 端**：用 OpenCL 继续做大模型/长序列实验，验证 GPU offload 收益曲线。
2. **手机端**：尝试 OpenCL backend（`GGML_OPENCL=ON`）在 Termux 原生编译运行，看 Mali-G78 是否能被识别。
3. **跨端联动**：如果后续拿到 GPU PC，可在 GPU PC 上编译 `GGML_VULKAN=ON + GGML_RPC=ON` 作为 Host，WSL/手机作为 Vulkan RPC Worker（前提是各自 Vulkan 已可用）。

---

## 8. 参考

- `vulkan/logs/wsl_vulkan_baseline_20260711_231159.log`
- `vulkan/logs/phone_vulkan_baseline_20260711_232957.log`
- `vulkan/logs/wsl_opencl_baseline_20260712_083610.log`
- `vulkan/docs/vulkan-baseline-report.md`
- `vulkan/docs/opencl-baseline-report.md`
- `vulkan/docs/vulkan-setup.md`
- `vulkan/docs/opencl-setup.md`
- Intel Compute Runtime: https://github.com/intel/compute-runtime
- llama.cpp OpenCL backend: https://github.com/ggerganov/llama.cpp/blob/master/docs/backend/OpenCL.md
- Mesa Dozen (`dzn`): https://docs.mesa3d.org/drivers/dzn.html
- Bionic `spawn.h`: https://android.googlesource.com/platform/bionic/+/master/libc/include/spawn.h
- Termux spawn.h 讨论: https://github.com/termux/termux-packages/issues/4634
