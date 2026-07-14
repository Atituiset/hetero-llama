# MNN 环境准备与运行指南

## 1. WSL 端

### 1.1 安装依赖

```bash
cd MNN/transformers/llm/export
python3 -m pip install -r requirements.txt --break-system-packages
```

### 1.2 编译 MNNConvert

`llmexport.py` 需要本地 `MNNConvert`：

```bash
cd MNN
mkdir -p build-host
cmake -B build-host -DMNN_BUILD_CONVERTER=ON \
  -DMNN_BUILD_LLM=OFF -DMNN_BUILD_TEST=OFF \
  -DMNN_BUILD_BENCHMARK=OFF -DMNN_BUILD_QUANTOOLS=OFF \
  -DMNN_BUILD_TRAIN=OFF
make -C build-host MNNConvert -j$(nproc)
# 产物：build-host/MNNConvert
```

### 1.3 下载原始模型

```bash
mkdir -p models
cd models
git lfs install
git clone https://www.modelscope.cn/qwen/Qwen2-0.5B-Instruct.git qwen2-0.5b-instruct --depth 1
```

### 1.4 导出 MNN 模型

```bash
cd MNN/transformers/llm/export
python3 llmexport.py \
  --path /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2-0.5b-instruct \
  --export mnn --hqq \
  --dst_path /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2-0.5b-instruct-mnn \
  --mnnconvert /home/atituiset/Projects/gpu-cpu-phone-test/MNN/build-host/MNNConvert
```

### 1.5 WSL 本地验证

```bash
cd MNN
mkdir -p build-linux-llm
cmake -B build-linux-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON
make -C build-linux-llm llm_demo -j$(nproc)

echo "你好" > prompt.txt
LD_LIBRARY_PATH=build-linux-llm ./build-linux-llm/llm_demo \
  /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2-0.5b-instruct-mnn/config.json prompt.txt
```

## 2. 手机端（Termux 原生 shell）

### 2.1 安装依赖

```bash
pkg install clang cmake opencl-headers opencl-vendor-driver
```

### 2.2 同步 MNN 源码到手机

从 WSL 执行：

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test
tar czf - --exclude='MNN/.git' --exclude='MNN/build-*' MNN | \
  ssh -p 8022 u0_a111@192.168.31.177 \
  'mkdir -p /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test && cd $_ && tar xzf -'
```

### 2.3 编译 OpenCL 后端

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/MNN
cmake -B build-opencl-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_OPENCL=ON
make -C build-opencl-llm llm_demo -j4
```

**常见问题**：`GLES2/gl2.h` 缺失。

解决：编辑 `source/backend/opencl/core/OpenCLBackend.cpp`，删除 `#ifdef __ANDROID__` 块内的 `#include <GLES2/gl2.h>`（该头文件实际未被使用）。

### 2.4 编译 Vulkan 后端

```bash
cmake -B build-vulkan-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_VULKAN=ON
make -C build-vulkan-llm llm_demo -j4
```

### 2.5 推送模型到手机

从 WSL 执行：

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2-0.5b-instruct-mnn
tar czf - . | ssh -p 8022 u0_a111@192.168.31.177 \
  'mkdir -p /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn && cd $_ && tar xzf -'
```

### 2.6 生成后端配置文件

在手机上：

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn
# CPU
sed 's/"backend_type": "cpu"/"backend_type": "cpu"/' config.json > config.cpu.json
# OpenCL normal
sed 's/"backend_type": "cpu"/"backend_type": "opencl"/; s/"precision": "low"/"precision": "normal"/; s/"memory": "low"/"memory": "normal"/' config.json > config.opencl.normal.json
# Vulkan
sed 's/"backend_type": "opencl"/"backend_type": "vulkan"/' config.opencl.normal.json > config.vulkan.json
```

### 2.7 运行

```bash
printf "hello" > /data/data/com.termux/files/home/mnn_prompt.txt

# CPU
time LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn/config.json \
  /data/data/com.termux/files/home/mnn_prompt.txt

# OpenCL
time LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn/config.opencl.normal.json \
  /data/data/com.termux/files/home/mnn_prompt.txt

# Vulkan
time LD_LIBRARY_PATH=./OFF ./llm_demo \
  /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/qwen2-0.5b-instruct-mnn/config.vulkan.json \
  /data/data/com.termux/files/home/mnn_prompt.txt
```

## 3. 验证 GPU 是否被调用

```bash
clinfo | grep -E "Device Name|Device Type|Max compute units"
vulkaninfo --summary | grep -E "deviceName|deviceType|apiVersion"
```
