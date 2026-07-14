# ncnn Vulkan Benchmark 报告（Mate 40 Pro）

## 1. 实验目标

验证 Tencent ncnn 的 Vulkan 后端能否在 Mate 40 Pro 的 Mali-G78 上正常工作，并通过标准 CNN benchmark 观察 GPU 相对 CPU 的加速规律。

## 2. 环境

- **手机**：华为 Mate 40 Pro
- **SoC**：Kirin 9000
- **GPU**：Mali-G78 MP24
- **Vulkan**：1.1.191（`vulkaninfo`）
- **ncnn 版本**：master shallow clone（2026-07-12）

## 3. 编译

```bash
cd /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/Projects/gpu-cpu-phone-test/ncnn
cmake -B build -DNCNN_VULKAN=ON -DNCNN_BUILD_BENCHMARK=ON \
  -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_TESTS=OFF
cmake --build build --target benchncnn -j4
```

## 4. 运行结果

命令：

```bash
cd build/benchmark
cp ../../benchmark/models/*.param .
# CPU
./benchncnn 4 1 0 -1 0
# Vulkan
./benchncnn 4 1 0 0 0
```

### CPU（1 线程）

| 网络 | 平均耗时 (ms) |
|---|---|
| squeezenet | 10.75 |
| mobilenet | 19.31 |
| mobilenet_v2 | 12.20 |
| googlenet | 41.26 |
| resnet18 | 28.00 |
| resnet50 | 85.50 |
| vgg16 | 159.32 |
| vision_transformer | 421.80 |
| FastestDet | 5.84 |

### Vulkan（Mali-G78）

| 网络 | 平均耗时 (ms) | 与 CPU 比值 |
|---|---|---|
| squeezenet | 29.69 | 2.8× 慢 |
| mobilenet | 35.47 | 1.8× 慢 |
| mobilenet_v2 | 37.75 | 3.1× 慢 |
| googlenet | 77.26 | 1.9× 慢 |
| resnet18 | 55.17 | 2.0× 慢 |
| resnet50 | 99.70 | 1.2× 慢 |
| vgg16 | 77.11 | **2.1× 快** |
| vision_transformer | 10786.36 | **25.6× 慢** |
| FastestDet | 34.34 | 5.9× 慢 |

## 5. 分析

1. **Vulkan 后端可用**：没有 crash，能正确枚举 Mali-G78 设备。
2. **加速具有选择性**：只有像 VGG16 这种“大卷积、重计算”的网络，GPU 才明显快于 CPU；小网络反而更慢。
3. **Transformer 在 Vulkan 上极慢**：`vision_transformer` 在 Vulkan 上比 CPU 慢 25 倍，说明 ncnn 当前对 Mali 的 Transformer 算子（或整个 graph 调度）优化不足。
4. **对 LLM 的启示**：LLM 推理本质上就是大量 Transformer block 的重复计算。如果 benchncnn 里单个 vision_transformer 都这么慢，可以预期未经专门优化的 LLM Vulkan 路径在 Mali 上也不会快。

## 6. 已知 Mali 兼容性问题

GitHub issue [#5885](https://github.com/Tencent/ncnn/issues/5885) 报告：
- 设备：华为 Mate 40（Mali-G78）等 Mali GPU
- 现象：Vulkan 推理输出异常（如检测框数值异常）
- 临时解决：关闭 Vulkan，回退 CPU

这意味着即使 ncnn_llm 跑通 Vulkan，也需要单独验证输出正确性。

## 7. 结论

- ncnn Vulkan 在 Mate 40 Pro 上**可运行**，但**不是通用加速方案**。
- 对当前目标（本地 LLM GPU 加速），ncnn 没有明显优于 MNN 的证据；两者都受限于 Mali GPU 对 Transformer/LLM workload 的低效支持。
- 如果继续深挖 ncnn LLM，需要：
  - 安装 xmake 并编译 ncnn_llm；
  - 准备已转换的 Qwen/MiniCPM ncnn 模型；
  - 实测并验证输出正确性。

## 8. ncnn_llm LLM 实测补充（Qwen3-0.6B）

后续按上述思路继续，最终成功构建 `ncnn_llm` 并跑了 Qwen3-0.6B（fp16）。

### 构建要点

- 不要用 Termux 原生 shell 编译的 ncnn（Bionic libc），否则在 proot Ubuntu（glibc）链接会报 `__android_log_print`、`std::__ndk1::...` 等符号缺失。
- 必须在 proot Ubuntu 内重新编译 glibc 版 ncnn，再修改 `ncnn_llm/xmake.lua` 指向本地 ncnn + 系统 `nlohmann-json3-dev` + `libomp`。

### 运行结果（prompt=`hello`，约 9 token）

| 后端 | 运行时间 | 结论 |
|---|---|---|
| CPU（4 线程） | **40.7 s** | 能正常输出 |
| Vulkan（Mali-G78） | > 100 min CPU time / 无有效输出 | 进程卡在首次推理，无法完成 |

CPU 输出示例：

```text
Assistant: <think>
Okay, the user just said "hello"... 
</think>

Hello! How can I assist you today? 😊
```

Vulkan 现象：
- 日志只打印到模型加载和 `User:`，之后没有任何 assistant 输出；
- 进程 CPU 时间持续增长（超过 100 分钟），占用约 2.8 GB 内存；
- 与 ncnn issue #5885 描述的 Mali Vulkan 异常一致。

### 结论

对 Qwen3-0.6B 这种小 LLM：
- **ncnn CPU 可用但较慢**（40.7 s 生成约 9 token）。
- **ncnn Vulkan 在 Mali-G78 上基本不可用**，首次推理即卡住/极慢。

这与 benchncnn 中 `vision_transformer` Vulkan 比 CPU 慢 25 倍的现象一致：ncnn/Mali 对 Transformer/LLM 的 GPU 路径尚未优化到可用程度。
