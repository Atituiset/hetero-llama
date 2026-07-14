# mnn 模式：用 MNN 在手机端跑 LLM

本目录记录把 Qwen2 模型通过 **MNN** 导出并在 **Mate 40 Pro（Mali-G78）** 上推理的全过程，重点验证 OpenCL / Vulkan 后端能否调用手机 GPU。

- 状态：✅ 0.5B / 1.5B / 3B CPU 已跑通；OpenCL/Vulkan 能调用 Mali-G78，但 0.5B/1.5B 比 CPU 慢，3B OpenCL normal OOM，OpenCL low 可稳定跑完但比 CPU 慢
- 框架：MNN（fork 自 https://github.com/alibaba/MNN）
- 模型：`Qwen2-0.5B-Instruct`、`Qwen2-1.5B-Instruct`、`Qwen2.5-3B-Instruct`
- 手机：华为 Mate 40 Pro（Kirin 9000，Mali-G78 MP24）

## 目录

- `config.env` — 路径与默认参数
- `scripts/` — 导出、手机 baseline 脚本
- `docs/` — 报告与环境说明
- `logs/` — 运行日志

## 快速开始

### 1. 在 WSL 上导出 MNN 模型

```bash
./scripts/export_qwen2_mnn.sh /path/to/Qwen2-0.5B-Instruct /path/to/output-mnn-dir
```

### 2. 在 WSL 上验证导出的模型

```bash
cd ../MNN/build-linux-llm
LD_LIBRARY_PATH=. ./llm_demo /path/to/output-mnn-dir/config.json prompt.txt
```

### 3. 在手机上编译并运行

```bash
# 从 WSL 推送到手机
./scripts/push_model_to_phone.sh /path/to/output-mnn-dir

# 在 Termux 原生 shell 中
bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/mnn/scripts/run_phone_mnn_baseline.sh cpu
bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/mnn/scripts/run_phone_mnn_baseline.sh opencl
bash /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/mnn/scripts/run_phone_mnn_baseline.sh vulkan
```

## 关键结论

| 后端 | 设备 | 0.5B 运行时间 | 1.5B 运行时间 | 3B 运行时间 | 结论 |
|---|---|---|---|---|---|
| CPU | ARM82（8 线程） | ~1.7 s | ~4.7 s | ~57.0 s | 当前最快，3B 仍可跑完 |
| OpenCL | Mali-G78 GPU | ~23 s（normal） | ~45.5 s（normal） | ~85.6 s（low）<br>normal OOM | 能调用 GPU，但不快；3B normal 不稳 |
| Vulkan | Mali-G78 GPU | ~6 m 37 s | 预计更慢 | 未跑 | 能调用 GPU，但极慢 |

> 详细分析见 `docs/mnn-baseline-report.md`。MNN 在 Mali 上目前**不适合作为 GPU 加速方案**；3B normal 配置直接触发崩溃，只有 low 内存配置能跑完。

## 可复现执行路径

### 手机端编译 MNN LLM demo

```bash
cd /root/Projects/gpu-cpu-phone-test/MNN

# OpenCL 后端
cmake -B build-opencl-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_OPENCL=ON -DCMAKE_BUILD_TYPE=Release
make -C build-opencl-llm llm_demo -j2

# Vulkan 后端
cmake -B build-vulkan-llm -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
make -C build-vulkan-llm llm_demo -j2
```

### 手机端运行 baseline（以 3B 为例）

```bash
# CPU
cd /root/Projects/gpu-cpu-phone-test/MNN/build-opencl-llm
{ time LD_LIBRARY_PATH=./OFF ./llm_demo \
  /root/models/qwen2.5-3b-instruct-mnn/config.cpu.json \
  /data/data/com.termux/files/home/mnn_prompt_3b.txt ; } \
  > /root/Projects/gpu-cpu-phone-test/mnn/logs/mnn_phone_3b_cpu_$(date +%Y%m%d_%H%M%S).log 2>&1

# OpenCL low-memory（3B normal 会 OOM）
{ time LD_LIBRARY_PATH=./OFF ./llm_demo \
  /root/models/qwen2.5-3b-instruct-mnn/config.opencl.low.json \
  /data/data/com.termux/files/home/mnn_prompt_3b.txt ; } \
  > /root/Projects/gpu-cpu-phone-test/mnn/logs/mnn_phone_3b_opencl_low_$(date +%Y%m%d_%H%M%S).log 2>&1
```

### 从 ModelScope 下载 3B MNN 模型（WSL）

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test
modelscope download --model 'MNN/Qwen2.5-3B-Instruct-MNN' \
  --local_dir './models/qwen2.5-3b-instruct-mnn'
```

### 推送模型到手机

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/models/qwen2.5-3b-instruct-mnn
tar czf - . | ssh -p 8022 u0_a111@192.168.31.177 \
  'mkdir -p /root/models/qwen2.5-3b-instruct-mnn && cd $_ && tar xzf -'
```

## 文档

| 文档 | 内容 |
|---|---|
| `docs/mnn-setup.md` | MNN 环境准备、导出、编译、常见问题 |
| `docs/mnn-baseline-report.md` | 0.5B 模型 baseline 完整报告与现象分析 |

## 下一步

- **A. 换 ncnn**：MNN 在 Mali 上 GPU 路径明显落后 CPU，且 3B 规模下 OpenCL normal 崩溃，继续尝试 ncnn 的 Vulkan 后端。
