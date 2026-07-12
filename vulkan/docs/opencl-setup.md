# WSL OpenCL 实验环境准备

> 适用于 `feat/vulkan-local` 分支下的 WSL 端。当 Vulkan 后端只能看到 `llvmpipe` 时，可以用 OpenCL 后端调用 Intel 核显。

---

## 前置条件

- 当前 worktree：`/home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan`
- 模型路径：`~/models/qwen2-0.5b-instruct-q4_0.gguf`
- llama.cpp 位于 `~/Projects/gpu-cpu-phone-test/llama.cpp`，commit 与 `README.md` 一致。

---

## 1. 安装 OpenCL 运行时

```bash
sudo apt update
sudo apt install -y clinfo ocl-icd-opencl-dev intel-opencl-icd libclblast-dev
```

`intel-opencl-icd` 会把 Intel 核显作为 OpenCL 平台暴露出来。

---

## 2. 验证 OpenCL 设备

```bash
clinfo | head -60
```

期望看到类似：

```text
Number of platforms                               1
  Platform Name                                   Intel(R) OpenCL Graphics
  Platform Version                                OpenCL 3.0
Number of devices                                 1
  Device Name                                     Intel(R) Graphics [0x7d55]
```

---

## 3. 补齐 OpenCL 头文件（如果 apt 无法下载）

如果 `apt install opencl-c-headers` 因网络失败，可以从 Windows 宿主机已有的 Python/AI 环境复制：

```bash
sudo cp -r /mnt/c/Users/Atituiset/AppData/Local/Programs/AI\ Playground/resources/ComfyUI/.venv/include/CL /usr/include/
sudo ln -sf /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so
```

确保头文件已到位：

```bash
ls /usr/include/CL/cl.h
```

---

## 4. 编译 llama.cpp OpenCL 后端

**注意：必须关闭 Adreno 专用内核，否则非 Adreno GPU 会被丢弃。**

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
cmake -B build-opencl -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF
cmake --build build-opencl --target llama-completion -j$(nproc)
```

---

## 5. 运行 baseline

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan
./run_wsl_opencl_baseline.sh 99 "你好" 5
```

日志会写入 `logs/wsl_opencl_baseline_YYYYMMDD_HHMMSS.log`。

---

## 常见问题

- **OpenCL 平台数为 0**：
  - 确认 Windows 端 Intel 显卡驱动较新，且 `wsl --update` 已执行。
  - 重启 WSL：`wsl --shutdown` 后再进。

- **编译报错找不到 `CL/cl.h`**：
  - 按第 3 步补齐头文件。

- **运行时提示 `drop unsupported device 'Intel(R) Graphics ...'`**：
  - 重新编译时加上 `-DGGML_OPENCL_USE_ADRENO_KERNELS=OFF`。

- **生成速度比 CPU 慢**：
  - 对 0.5B 小模型，核显+WSL 桥接开销大，属于正常现象；可换更大模型再测。
