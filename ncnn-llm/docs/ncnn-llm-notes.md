# ncnn LLM 运行说明

## 1. 社区运行时

要在 ncnn 上跑 LLM，需要额外一层运行时，因为 ncnn 本身是通用推理框架，不直接提供 KV cache、自回归采样、tokenizer 等 LLM 专用逻辑。

目前已知的社区项目是 **ncnn_llm**（https://github.com/futz12/ncnn_llm），但：
- 原仓库当前已无法访问；
- 有一个只读 archive：https://github.com/LiYulin-s/ncnn_llm

## 2. ncnn_llm 支持模型

根据 archive 中的 README：
- YoutuLLM
- MiniCPM4
- Qwen3 / Qwen3.5
- Qwen2.5-VL（视觉语言）
- GLM-OCR / HunyuanOCR
- NLLB 翻译
- Jina-Embeddings / Jina-CLIP

**注意**：未明确列出 Qwen2，需要确认是否兼容或自行转换。

## 3. 模型下载

archive README 提到转换好的模型可在镜像下载：

```
https://mirrors.sdu.edu.cn/ncnn_modelzoo/
```

模型目录通常包含：
- `model.json`
- ncnn `.param` / `.bin`
- tokenizer 文件

## 4. 构建依赖

- `xmake`
- 从 master 构建的 ncnn（我们已在手机上编译好）

手机端安装 xmake：

```bash
proot-distro login ubuntu -- bash -lc "apt-get update && apt-get install -y xmake"
```

已在 proot Ubuntu 中成功安装 `xmake 2.9.9`。

## 5. 构建与运行尝试

当前推荐路径：绕过 xmake 包管理，在 proot Ubuntu（glibc）中重新编译 ncnn，再用修改后的 `xmake.lua` 构建 `llm_ncnn_run`。

```bash
# 安装依赖
proot-distro login ubuntu -- bash -lc "apt-get update && apt-get install -y xmake ninja-build libomp-dev nlohmann-json3-dev libvulkan-dev"

# 编译 glibc 版 ncnn
cd /root/Projects/gpu-cpu-phone-test/ncnn
cmake -B build-glibc -G Ninja \
  -DNCNN_VULKAN=ON \
  -DNCNN_BUILD_BENCHMARK=OFF \
  -DNCNN_BUILD_TOOLS=OFF \
  -DNCNN_BUILD_EXAMPLES=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/root/Projects/gpu-cpu-phone-test/ncnn/install-glibc
cmake --build build-glibc -j2
cmake --install build-glibc

# 修改 ncnn_llm/xmake.lua 指向 install-glibc

# 构建 runner
cd /root/Projects/gpu-cpu-phone-test/ncnn_llm
XMAKE_ROOT=y xmake build -j2 llm_ncnn_run

# 运行（需先下载模型到 assets/）
XMAKE_ROOT=y xmake run llm_ncnn_run --model ./assets/qwen3_0.6b --threads 4
XMAKE_ROOT=y xmake run llm_ncnn_run --model ./assets/qwen3_0.6b --vulkan --vulkan-device 0
```

进展：
1. ✅ 安装 `xmake 2.9.9`；
2. ✅ 克隆 `ncnn_llm` 源码到手机；
3. ✅ 网络修复后，`xmake` 成功拉取 `xmake-repo` / `build-artifacts`；
4. ✅ 清理手机存储至 30 GB 后，`xmake require -y -j2` 运行约 45 分钟；
5. ❌ `glslang-nihui` 与 `python 3.14.3` 包安装失败；
6. ❌ 手机断网，无法继续下载依赖；
7. ✅ 网络恢复，安装 `libomp-dev`、`ninja-build`、`nlohmann-json3-dev`；
8. ✅ 修改 `xmake.lua` 使用本地 ncnn + 系统依赖；
9. ❌ 发现之前 Termux 原生编译的 ncnn 是 Bionic libc，在 proot glibc 下链接失败（`__android_log_print`、`std::__ndk1::...`）；
10. ✅ 在 proot Ubuntu 中重新编译 glibc 版 ncnn（`build-glibc`）成功；
11. ✅ 链接成功，`llm_ncnn_run` 构建完成；
12. ✅ 从 https://mirrors.sdu.edu.cn/ncnn_modelzoo/ 下载 `qwen3_0.6b` fp16 模型并推送到手机 `assets/`；
13. ✅ CPU 基线跑通（prompt=`hello`，约 9 token，**40.7 s**）；
14. ⏳ Vulkan 基线正在运行中。

日志保存在 `ncnn-llm/logs/ncnn_llm_build_*.log`、`ncnn_llm_config_*.log`、`ncnn_llm_require_*.log`、`ncnn_llm_build_local_*.log`、`ncnn_glibc_build_*.log`、`ncnn_llm_phone_qwen3_0.6b_*.log`。

## 6. Mali 兼容性风险

ncnn issue [#5885](https://github.com/Tencent/ncnn/issues/5885) 指出 Mali GPU（包括 Mate 40 的 Mali-G78）上 Vulkan 推理结果可能异常。因此 ncnn_llm 即使跑通，也必须：
- 对比 CPU 和 Vulkan 的输出文本；
- 检查是否有乱码、重复、语义错误；
- 如异常，需回退 CPU 或等待 ncnn 修复。

## 7. 当前结论

在当前会话中：
- ✅ `benchncnn` 已充分验证 ncnn Vulkan 在 Mali-G78 上的行为：小网络/Transformer 比 CPU 慢，大 CNN 才能体现 GPU 优势；
- ✅ xmake 已安装，ncnn_llm 源码已推送；
- ✅ 已绕过 xmake 包管理，使用本地 glibc 版 ncnn + 系统依赖成功构建 `llm_ncnn_run`；
- ✅ Qwen3-0.6B CPU 基线已跑通，约 **40.7 s**；
- ⏳ Vulkan 基线正在运行中，等待结果以对比 CPU/GPU 速度与输出正确性。

因此优先记录 **ncnn Vulkan benchmark 结论**，把 ncnn_llm 完整跑通作为后续可选深挖项。
