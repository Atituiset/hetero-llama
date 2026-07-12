# Vulkan 本地 baseline 实验报告

> 分支：`feat/vulkan-local`  
> 实验时间：2026-07-11  
> 目标：在 WSL（当前机器）和 Mate 40 Pro 上分别运行 llama.cpp Vulkan backend 本地推理，验证环境可用性，并记录关键问题与规避方法。

---

## 1. 实验环境

| 项目 | WSL | Mate 40 Pro |
|------|-----|-------------|
| 设备 | 当前 WSL 主机 | Huawei Mate 40 Pro |
| SoC / GPU | x86_64（宿主机 GPU 透传） | Kirin 9000 / Mali-G78 |
| 操作系统 | WSL2 / Ubuntu | Termux + proot Ubuntu |
| llama.cpp commit | `152d337fa` | `152d337fa-dirty` |
| 编译工具链 | GNU/Linux x86_64 | Termux NDK r29（Android aarch64） |
| 模型 | `qwen2-0.5b-instruct-q4_0.gguf`（336 MB） | 同上 |
| 推理二进制 | `llama-completion` | `llama-completion` |

---

## 2. 关键问题与解决方法

### 2.1 工作树隔离

为避免影响已有的 `feat/3-machine-inference` CUDA/SSH 隧道配置，本实验在独立的 git worktree 中实施：

- 本地路径：`/home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan`
- 分支：`feat/vulkan-local`
- 原 `feat/3-machine-inference` 分支及其脚本未被修改。

### 2.2 手机端编译：`proot Ubuntu` 无法写入 SPIR-V

在 `proot-distro login ubuntu` 内直接 `cmake --build` 时，`vulkan-shaders-gen` 写 SPIR-V 文件失败：

```text
Function not implemented
```

**规避方法**：在 **Termux 原生 shell** 中执行编译，但源码仍放在 proot Ubuntu 的仓库路径下（Termux 可访问该路径）。使用的 CMake 命令：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan --target llama-completion -j$(nproc)
```

### 2.3 手机端编译：`<spawn.h>` 缺失

Termux 的 bionic libc 在头文件层面未提供 `<spawn.h>`，导致 `tools/server` 与 `tools/mtmd` 中 `vendor/sheredom/subprocess.h` 编译失败。

**规避方法**：在 Termux 系统 include 路径补充最小化的 `spawn.h`（内容来自 Bionic 公开 API）：

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

> 注意：这只是为了让 llama.cpp 的 server/mtmd 辅助代码通过编译；baseline 本身并不调用这些子进程功能。

### 2.4 手机端运行：Android ELF 不能在 proot Ubuntu 内执行

Termux 原生编译出的 `llama-completion` 是 Android ELF（interpreter `/system/bin/linker64`），在 `proot-distro login ubuntu` 内运行会报：

```text
/lib/aarch64-linux-gnu/libc.so: invalid ELF header
```

**规避方法**：手机 baseline 脚本必须在 **Termux 原生 shell** 中执行。脚本已修改为自动使用 proot Ubuntu 仓库路径的绝对路径访问模型和二进制：

- 二进制：`/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/llama.cpp/build-vulkan/bin/llama-completion`
- 模型：`/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-q4_0.gguf`

### 2.5 Vulkan 1.2 要求

Mate 40 Pro 的 Mali-G78 驱动在 Termux 中仅暴露 **Vulkan 1.1**，而当前 llama.cpp Vulkan backend 要求 **Vulkan 1.2**：

```text
ggml_vulkan: Error: Vulkan 1.2 required.
warning: no usable GPU found, --gpu-layers option will be ignored
```

因此手机端本次 baseline 实际运行在 **CPU 后端**，并未启用 GPU offload。后续若要进行 Mali GPU 推理，需要：

- 更新设备驱动/Vulkan loader 以支持 Vulkan 1.2；或
- 使用支持 Vulkan 1.2 的第三方驱动/Mesa Turnip（实验性）。

WSL 端也遇到同样的 `no usable GPU found` 提示，说明当前 WSL 未透传真实 GPU，使用的是 llvmpipe/CPU 路径。这与“当前没有 GPU PC”的前提一致。

---

## 3. 运行命令

### WSL

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan
./run_wsl_vulkan_baseline.sh 99 "你好" 5
```

### Mate 40 Pro（从 WSL 通过 SSH 调用 Termux 原生 shell）

```bash
ssh -p 8022 root@192.168.31.177 \
  'bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/run_phone_vulkan_baseline.sh 99 "你好" 5'
```

---

## 4. 实验结果

### 4.1 输出示例

| 设备 | 输入 | 输出 |
|------|------|------|
| WSL | 你好 | `你好！有什么问题或` |
| Mate 40 Pro | 你好 | `你好(OPPO)12` |

输出差异由采样随机性和温度设置导致，均说明模型加载与推理链路正常。

### 4.2 性能数据

| 设备 | 后端 | 加载时间 | prompt eval | eval（生成） |
|------|------|----------|-------------|--------------|
| WSL | CPU（llvmpipe，GPU 未启用） | 1387 ms | 344 t/s | 89.6 t/s |
| Mate 40 Pro | CPU（GPU 未启用） | 1163 ms | inf（1 token） | 5.85 t/s |

> 手机端 eval 速度较低，主因是 CPU 后端在 Android ARM 上运行，且未开启 GPU 加速。

---

## 5. 日志文件

| 日志 | 路径 |
|------|------|
| WSL baseline | `logs/wsl_vulkan_baseline_20260711_231159.log` |
| Mate 40 Pro baseline | `logs/phone_vulkan_baseline_20260711_232957.log` |

---

## 6. 结论与下一步

1. **环境可用**：WSL 和手机均能在独立 worktree 中编译并运行 llama.cpp Vulkan 后端，且未破坏 `feat/3-machine-inference`。
2. **GPU 未启用**：
   - WSL 当前无可用 GPU（llvmpipe fallback）。
   - Mate 40 Pro 的 Mali-G78 驱动仅支持 Vulkan 1.1，不满足 llama.cpp Vulkan 1.2 要求。
3. **关键 workaround**：
   - Termux 原生编译 + 运行。
   - 补充 `<spawn.h>` 头文件。
4. **下一步（Phase C：RPC 联动）**：
   - 若 GPU PC 恢复，可在 GPU PC 上编译 Vulkan/RPC 后端作为 Host，WSL/手机作为 Worker。
   - 也可尝试为手机刷入/安装支持 Vulkan 1.2 的驱动（如 Mesa Turnip）后再测 GPU offload。

---

## 7. 后续更新：OpenCL 绕开 WSL Vulkan 限制

2026-07-12 补充：由于 WSL2 当前没有可用的 Vulkan 物理设备，尝试用 **OpenCL** 调用 Intel 核显取得成功。

| 项目 | 结果 |
|------|------|
| 后端 | llama.cpp OpenCL (`GGML_OPENCL=ON`) |
| 设备 | `GPUOpenCL (Intel(R) Graphics [0x7d55])` |
| 层 offload | 25/25 层全部放到 GPU |
| eval 速度 | 56.3 t/s |
| 加载时间 | 784 ms |

完整过程、环境准备和性能分析见：

- [`docs/opencl-setup.md`](./opencl-setup.md)
- [`docs/opencl-baseline-report.md`](./opencl-baseline-report.md)
- 日志：`logs/wsl_opencl_baseline_20260712_083610.log`

> 虽然 OpenCL 成功调用了 GPU，但受模型大小和 WSL2 桥接开销影响，生成速度尚未超过 CPU 多线程。它证明了当前 WSL2 机器具备可用 GPU 算力，只是 Vulkan 这条路暂时走不通。

---

## 参考来源

- Bionic `spawn.h` 源码：[android.googlesource.com/platform/bionic/+/master/libc/include/spawn.h](https://android.googlesource.com/platform/bionic/+/master/libc/include/spawn.h)
- Bionic `spawn.cpp` 实现：[android.googlesource.com/platform/bionic/+/master/libc/bionic/spawn.cpp](https://android.googlesource.com/platform/bionic/+/master/libc/bionic/spawn.cpp)
- Termux `<spawn.h>` 缺失讨论：[termux/termux-packages#4634](https://github.com/termux/termux-packages/issues/4634)
