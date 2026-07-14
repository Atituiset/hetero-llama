# CPU + 华为 Mate 40 Pro 异构推理玩具项目方案

> 目标：在 PC 端纯 CPU 与 Mate 40 Pro 之间，通过 `llama.cpp` 的 RPC 能力做 Layer-wise Offloading，把模型的一部分层放到手机上跑，验证跨架构异构推理链路。

---

## 1. 架构定位

```
+------------------+        Wi-Fi 6 / USB 网络共享        +------------------+
|   PC (x86 CPU)   |  <---- 隐状态 H (约 4KB/token) ---->  |  Mate 40 Pro     |
|  llama.cpp main  |                                     | llama-rpc-server |
|   - RPC Client   |                                     |  - CPU / Vulkan  |
+------------------+                                     +------------------+
```

- **PC 端**：Host，跑 `llama.cpp` 主程序和大部分层。
- **Mate 40 Pro**：RPC Worker，跑 `llama-rpc-server`，承接部分 Transformer 层。
- 传输的是**层间隐状态**，不是 KV Cache，数据量极小。

### 关键预期

- **能跑通**：链路完整，token 能一个一个出来。
- **性能大概率不如 PC 单独跑**：Wi-Fi RTT 1–3ms 会把 decode 锁死在 5–15 tokens/s 左右。
- **价值**：理解 `llama.cpp` RPC、Vulkan 后端、异构调度和双 Agent 协同。

---

## 2. 前置条件

### PC 端

- x86_64 Linux（WSL / Ubuntu 均可）
- `git`, `cmake`, `build-essential`
- 可选：`aarch64-linux-gnu-gcc` 交叉编译工具链

### Mate 40 Pro 端

- Termux 已安装
- 开启 SSH（默认 8022 端口）
- 建议开启 Wi-Fi 6 或 USB 网络共享，降低 RTT
- 可用内存 ≥ 6GB（系统会占用一部分）

---

## 3. 步骤一：手机端先单独点亮模型

先不急着 RPC，先在手机里把 `llama.cpp` 跑起来，确认 CPU/Vulkan 基线。

### 3.1 安装依赖

```bash
pkg update
pkg install -y git cmake clang build-essential openssl
# 如果想尝试 Vulkan（可选）
pkg install -y vulkan-headers vulkan-loader-generic
```

### 3.2 克隆并编译

```bash
cd ~
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
mkdir -p build && cd build

# 先编译 CPU 后端，保证链路最稳
cmake .. -DLLAMA_RPC=OFF -DLLAMA_VULKAN=OFF
make -j2
```

> 注意：Termux 下 `-j4` 以上可能触发 Android LMK，建议 `-j2`。

### 3.3 下载极小模型并测试

```bash
cd ~
mkdir -p models && cd models

# 推荐 Qwen-0.5B Q4_0
wget https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0.5b-instruct-q4_0.gguf
# 或 TinyLlama-1.1B
# wget https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_0.gguf

cd ~/llama.cpp/build
./main -m ~/models/qwen2-0.5b-instruct-q4_0.gguf -p "你好" -n 32
```

记录此时的 `tokens/s`，这就是手机单兵作战的基准。

### 3.4（可选）挑战 Vulkan 后端

如果 CPU 基准已经跑通，再试 Vulkan：

```bash
cd ~/llama.cpp/build
rm -rf *
cmake .. -DLLAMA_VULKAN=ON
make -j2
./main -m ~/models/qwen2-0.5b-instruct-q4_0.gguf -p "你好" -n 32
```

> 如果 `vulkan-loader-generic` 无法识别 Mali GPU，回退到 CPU 后端即可。

---

## 4. 步骤二：PC 端编译 RPC Client

```bash
cd ~
git clone https://github.com/ggerganov/llama.cpp.git llama.cpp-host
cd llama.cpp-host
mkdir -p build && cd build

cmake .. -DLLAMA_RPC=ON
make -j
```

> 如果 PC 没有 NVIDIA GPU，不需要 `-DLLAMA_CUDA=ON`。

---

## 5. 步骤三：启动 RPC 并做异构推理

### 5.1 手机端启动 RPC Server

```bash
cd ~/llama.cpp/build
./llama-rpc-server -p 50052
```

### 5.2 PC 端运行主程序

```bash
cd ~/llama.cpp-host/build

# -ngl 0 表示 PC 端不用本地 GPU，全部交给调度器分配
./main \
  -m ~/models/qwen2-0.5b-instruct-q4_0.gguf \
  --rpc 192.168.1.7:50052 \
  -ngl 0 \
  -p "你好" \
  -n 32
```

> `llama.cpp` 的调度器会自动决定哪些层在本地 CPU、哪些层在手机 RPC。如果你想强制更多层在手机，可以调整 `-ngl` 或修改源码中的调度逻辑。

---

## 6. 步骤四：对照实验

建议做 4 组对比，验证链路价值：

| 编号 | 方案 | 预期结果 |
|---|---|---|
| A | PC 纯 CPU 跑完整模型 | 基准速度 |
| B | Mate 40 Pro 纯 CPU 跑完整模型 | 手机基准 |
| C | PC CPU + Mate 40 Pro CPU RPC | 验证链路，通常比 A/B 慢 |
| D | PC CPU + Mate 40 Pro Vulkan RPC | 若 Vulkan 可用，可能接近或略超 B |

记录每组 `tokens/s` 和手机温度/是否降频。

---

## 7. 步骤五：降低网络延迟的小技巧

### 7.1 使用 USB 网络共享

如果 PC 和手机通过 USB 共享网络，RTT 通常比 Wi-Fi 更低、更稳定。

### 7.2 关闭手机省电模式

省电模式会进一步限制 CPU/GPU 频率。

### 7.3 给 Termux 加锁

在 Mate 40 Pro 的**应用启动管理**里把 Termux 设为“手动管理 + 允许后台活动”，减少被系统杀后台的概率。

---

## 8. 步骤六：双 Claude Code 协同工作流

如果你想让 PC 和手机各跑一个 Claude Code 实例协同改代码，推荐 **GitOps 模式**：

### 8.1 初始化共享仓库

在 PC 端（或 GitHub/Gitea）建一个仓库：

```bash
git init llama-heterogeneous
cd llama-heterogeneous
# 添加 protocol.md、改动说明等
git add . && git commit -m "init"
```

### 8.2 两端都 clone

```bash
# PC 端
git clone <repo-url> ~/llama-heterogeneous

# 手机端
git clone <repo-url> ~/llama-heterogeneous
```

### 8.3 协作规则

1. **协议先行**：任何 `ggml-rpc.cpp` 里的结构体/对齐/序列化变更，先在 `protocol.md` 里写清楚。
2. **PC 端 Agent**：负责改发送端、交叉编译 ARM 二进制。
3. **手机端 Agent**：负责 pull 最新协议、改接收端、运行 RPC server、回传日志。
4. **用 commit message 当消息**：主机改完 push，手机端轮询 `git pull` 后执行适配。

### 8.4 推荐的手机端编译策略

不要依赖手机端 Agent 做完整编译（慢 + 容易 OOM）。PC 端配置交叉编译：

```bash
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

cd ~/llama.cpp-host
mkdir -p build-arm && cd build-arm
cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/arm64-linux-gnu.cmake -DLLAMA_RPC=ON
make -j
```

然后把二进制 `scp` 到手机：

```bash
scp -P 8022 build-arm/bin/llama-rpc-server u0_a111@192.168.1.7:~/llama.cpp/build/
```

---

## 9. 常见问题与排查

### 9.1 手机编译被系统杀掉（Killed）

- 降低并发：`make -j1`
- 关闭其他 App
- 使用 swapfile（Termux 可配置 `swapon`）

### 9.2 Vulkan 检测不到 GPU

- 确认 `pkg install vulkan-loader-generic`
- 运行 `vulkaninfo` 查看是否能列出 Mali-G78
- 如果不行，回退 CPU 后端

### 9.3 RPC 连接不上

- 确认手机和 PC 在同一网段
- 确认 `llama-rpc-server` 已在手机运行
- 用 `telnet 192.168.1.7 50052` 从 PC 测试端口

### 9.4 token 速度很慢

- 这是预期， primarily 网络 RTT 瓶颈
- 尝试 USB 网络共享
- 减少 offload 到手机的层数，让计算尽量在 PC 端完成

### 9.5 输出乱码

- 检查模型是否匹配 tokenizer
- 检查量化格式是否被后端支持

---

## 10. 推荐的最小可行模型

| 模型 | 大小 | 说明 |
|---|---|---|
| Qwen2-0.5B-Instruct-Q4_0 | ~350MB | 首选，中文好，体积小 |
| TinyLlama-1.1B-Chat-v1.0-Q4_0 | ~600MB | 英文为主 |
| Phi-3-mini-4k-instruct-Q4_0 | ~1.8GB | 若内存充裕可试 |

---

## 11. 一句话总结

这套 **PC CPU + Mate 40 Pro** 的组合作为玩具项目**完全可行**，但不要指望它比普通 PC CPU 单独跑更快。它的真正价值是帮你理解 `llama.cpp` RPC、Vulkan 后端、异构层切分和双 Agent 协同。先把 CPU 链路跑通，再挑战 Vulkan，最后才考虑让 AI Agent 自动改代码。
