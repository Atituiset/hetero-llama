# ncnn-llm 模式：验证 ncnn Vulkan 在手机 GPU 上的表现

本目录记录使用 **Tencent ncnn** 框架（及社区 `ncnn_llm` 运行时）在手机端验证 GPU 加速可能性的实验。

- 状态：✅ ncnn + Vulkan 编译并跑通 benchmark；✅ ncnn_llm 已构建成功；✅ Qwen3-0.6B CPU 基线已跑通（40.7 s）；⏳ Vulkan 基线正在运行中
- 框架：ncnn（https://github.com/Tencent/ncnn）
- 社区 LLM 运行时：ncnn_llm（https://github.com/futz12/ncnn_llm，当前仓库已不可访问，使用 archive `LiYulin-s/ncnn_llm`）
- 手机：华为 Mate 40 Pro（Kirin 9000，Mali-G78 MP24）

## 目录

- `scripts/` — 编译与 benchmark 脚本
- `docs/` — 报告与说明
- `logs/` — 运行日志

## 快速结论

| 测试 | 后端 | 关键结果 |
|---|---|---|
| `benchncnn` | CPU（1 线程） | squeezenet 10.75 ms，vgg16 159.32 ms，vision_transformer 421.80 ms |
| `benchncnn` | Vulkan（Mali-G78） | squeezenet 29.69 ms，vgg16 77.11 ms，vision_transformer 10786 ms |

解读：
- **ncnn Vulkan 在 Mali-G78 上能正常初始化并运行**。
- 对小网络（squeezenet、mobilenet）Vulkan 比 CPU 慢；对重计算网络（vgg16）Vulkan 更快。
- 说明 Mali GPU 的优势需要 **“计算量足够大”** 才能体现，小模型/小算子反而受调度开销拖累。

## 与 MNN 的联系

MNN LLM 的 0.5B/1.5B 模型在 OpenCL/Vulkan 上也很慢，和 ncnn `vision_transformer` 在 Vulkan 上比 CPU 慢 25 倍的现象一致：
- Transformer/LLM 推理由大量小矩阵乘、softmax、layernorm 组成，单算子计算量小。
- Mali GPU 的 tile-based 架构在这种 workload 下效率低。

## 文档

| 文档 | 内容 |
|---|---|
| `docs/ncnn-benchmark-report.md` | `benchncnn` CPU/Vulkan 完整结果与分析 |
| `docs/ncnn-llm-notes.md` | 关于 ncnn_llm 运行时、模型库、Mali 兼容性问题的说明 |

## 构建尝试日志

`ncnn-llm/logs/ncnn_llm_build_*.log`、`ncnn_llm_config_*.log`、`ncnn_llm_require_*.log`、`ncnn_llm_build_local_*.log`、`ncnn_glibc_build_*.log` 记录了手机端 xmake 构建 ncnn_llm 的过程。关键节点：

1. ✅ 在 proot Ubuntu 中安装 `xmake 2.9.9`；
2. ✅ 克隆 `ncnn_llm` 源码到手机；
3. ✅ 网络修复后，`xmake` 成功拉取 `xmake-repo` / `build-artifacts`；
4. ✅ 清理手机存储至 30 GB 后，用 `xmake require -y -j2` 安装依赖，运行约 45 分钟；
5. ❌ `glslang-nihui` 与 `python 3.14.3` 包安装失败；
6. ❌ 随后手机网络中断，proot 内无法解析 `ports.ubuntu.com` / `github.com`；
7. ✅ 网络恢复后，安装 `libomp-dev`、`ninja-build`；
8. ✅ 修改 `ncnn_llm/xmake.lua`，绕过 xmake 包管理，直接使用本机 ncnn、系统 `nlohmann-json3-dev` 和 `libomp`；
9. ❌ 用之前 Termux 原生编译的 ncnn 链接时，出现 `__android_log_print`、`std::__ndk1::...` 等 Android/Bionic 符号未定义；
10. ✅ 在 proot Ubuntu 中重新编译 glibc 版 ncnn（`/root/Projects/gpu-cpu-phone-test/ncnn/build-glibc`）成功；
11. ✅ 用 `install-glibc` 链接成功，`llm_ncnn_run` 构建完成；
12. ✅ 从 https://mirrors.sdu.edu.cn/ncnn_modelzoo/ 下载 `qwen3_0.6b` fp16 模型并推送到手机 `assets/`；
13. ✅ CPU 基线跑通（prompt=`hello`，约 9 token，**40.7 s**）；
14. ⏳ Vulkan 基线正在运行中。

之前主要阻塞：默认 `-j10` 编译大依赖时 Termux/proot 被系统杀掉；降低并行度并释放空间后重试。最新状态：ncnn_llm 已构建成功，CPU 已跑通，等待 Vulkan 结果。

## 可复现执行路径

### 1. ncnn + benchncnn（已完成）

```bash
# 在手机上（proot Ubuntu）
cd /root/Projects/gpu-cpu-phone-test/ncnn
mkdir -p build && cd build
cmake .. -DNCNN_VULKAN=ON -DNCNN_BUILD_BENCHMARK=ON -DCMAKE_BUILD_TYPE=Release
make -j2 benchncnn

# CPU
./benchmark/benchncnn 4 1 0 -1 0
# Vulkan
./benchmark/benchncnn 4 1 0 0 0
```

### 2. ncnn_llm 构建（当前尝试中）

```bash
# 安装 xmake 与构建工具
proot-distro login ubuntu -- bash -lc "apt-get update && apt-get install -y xmake ninja-build libomp-dev nlohmann-json3-dev libvulkan-dev"

# 在 proot Ubuntu（glibc）中重新编译 ncnn，供 ncnn_llm 链接
cd /root/Projects/gpu-cpu-phone-test/ncnn
rm -rf build-glibc install-glibc
cmake -B build-glibc -G Ninja \
  -DNCNN_VULKAN=ON \
  -DNCNN_BUILD_BENCHMARK=OFF \
  -DNCNN_BUILD_TOOLS=OFF \
  -DNCNN_BUILD_EXAMPLES=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/root/Projects/gpu-cpu-phone-test/ncnn/install-glibc
cmake --build build-glibc -j2
cmake --install build-glibc

# 修改 ncnn_llm/xmake.lua 使用本地 ncnn + 系统依赖（详见仓库内 xmake.lua）

# 构建 LLM runner
cd /root/Projects/gpu-cpu-phone-test/ncnn_llm
XMAKE_ROOT=y xmake build -j2 llm_ncnn_run

# 运行（需先下载模型到 assets/）
XMAKE_ROOT=y xmake run llm_ncnn_run --model ./assets/qwen3_0.6b --threads 4
XMAKE_ROOT=y xmake run llm_ncnn_run --model ./assets/qwen3_0.6b --vulkan --vulkan-device 0
```

> 注意：
> - proot Ubuntu 默认是 root，必须加 `XMAKE_ROOT=y` 或 `--root`。
> - 不要用 Termux 原生 shell 编译的 ncnn，它是 Bionic libc，会在 proot glibc 链接时报 `__android_log_print` 等符号缺失。


## 下一步

- 等待 Vulkan 基线运行完成；
- 对比 CPU / Vulkan 输出文本是否正常（参考 ncnn issue #5885）；
- 把 CPU / Vulkan 结果更新到 `docs/ncnn-benchmark-report.md` 与 `docs/gpu-acceleration-summary.md`。

鉴于 Mali 在 benchncnn 上的规律，**Vulkan 收益可能有限甚至为负**。

## 参考

- ncnn 官方 Vulkan FAQ：https://ncnn.readthedocs.io/en/latest/how-to-use-and-FAQ/FAQ-ncnn-vulkan.html
- ncnn_llm 社区项目（已不可访问，archive）：https://github.com/LiYulin-s/ncnn_llm
- Mali GPU 推理异常 issue：https://github.com/Tencent/ncnn/issues/5885
