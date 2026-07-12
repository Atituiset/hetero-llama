# Vulkan 实验环境准备

> 适用于 `feat/vulkan-local` 分支下的 WSL 和手机双机实验。

## 前置条件

- 确保 worktree 中的 `config.env` 路径配置正确，尤其是 `MODEL_PATH`、`CURRENT_LLAMA_CPP_DIR`、`PHONE_LLAMA_CPP_DIR`。
- 默认模型路径为 `~/models/qwen2-0.5b-instruct-q4_0.gguf`；如不存在，可从 `https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF` 下载。
- llama.cpp 应检出到与 `README.md` 一致的提交：`152d337fadb93c2a099653c4072d5512c92c5bfd`。

---

## WSL 端

### 1. 安装 Vulkan tools

```bash
sudo apt update
sudo apt install vulkan-tools mesa-vulkan-drivers libvulkan-dev
```

### 2. 验证 GPU 透传

```bash
vulkaninfo --summary
```

能看到物理设备（如 Intel/NVIDIA/AMD）说明宿主机 GPU 已透传到 WSL。

### 3. 编译 llama.cpp Vulkan backend

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan -j
```

### 4. 运行 baseline

```bash
cd ~/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan
./check-vulkan-env.sh
./run_wsl_vulkan_baseline.sh 99 "你好" 5
```

---

## 手机端（Termux / proot Ubuntu）

### 1. 安装 Vulkan loader 和 tools

在 Termux 中：

```bash
pkg update
pkg install vulkan-tools vulkan-loader-android
```

### 2. 验证 Vulkan

```bash
vulkaninfo --summary
```

期望看到 `Mali-G78`。注意当前 Mate 40 Pro 驱动只支持 Vulkan 1.1，而 llama.cpp Vulkan backend 要求 Vulkan 1.2，因此后续 baseline 可能会 fallback 到 CPU。

### 3. 编译 llama.cpp Vulkan backend

> 重要：llama.cpp 必须在 **Termux 原生 shell** 中编译，生成 Android ELF。源码可以放在 proot Ubuntu 的目录里（Termux 可以访问），但编译命令要在 Termux 中执行。

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON
cmake --build build-vulkan --target llama-completion -j$(nproc)
```

#### 常见问题：`<spawn.h>` 缺失

如果编译 `tools/server` 或 `tools/mtmd` 时遇到：

```text
fatal error: 'spawn.h' file not found
```

说明 Termux 的 bionic 头文件没有提供 `<spawn.h>`。创建最小头文件：

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

然后重新编译即可。

### 4. 运行 baseline

llama.cpp 使用 Termux 原生工具链编译出的是 Android ELF，必须在 Termux 原生 shell 中运行，不能在 `proot-distro login ubuntu` 里运行（否则会报 `/lib/aarch64-linux-gnu/libc.so: invalid ELF header`）。

```bash
ssh -p 8022 root@192.168.31.177 \
  'bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/run_phone_vulkan_baseline.sh 99 "你好" 5'
```

脚本会自动使用 Termux 可访问的绝对路径访问 proot Ubuntu 目录下的源码和模型。

---

## 常见问题

- **WSL 中 `vulkaninfo` 看不到设备**：确认 Windows 宿主机已安装支持 WSL 的 GPU 驱动，且 `d3d12` 适配可用。
- **手机 proot 中 `vulkaninfo` 失败**：通常是 ICD 路径或 `/dev` 节点映射问题，优先在 Termux 原生环境测试，再解决 proot 映射。
- **编译时找不到 Vulkan SDK**：安装 `libvulkan-dev`（Ubuntu）或 `vulkan-headers`（Termux）。
- **手机编译 `vulkan-shaders-gen` 写 SPIR-V 失败（Function not implemented）**：改在 Termux 原生 shell 中编译。
- **手机运行报 `invalid ELF header`**：Android ELF 必须在 Termux 原生 shell 中运行。
- **`ggml_vulkan: Error: Vulkan 1.2 required.`**：当前 Mali-G78 驱动只支持 Vulkan 1.1，llama.cpp 会 fallback 到 CPU。需要 Vulkan 1.2 驱动才能 GPU offload。
