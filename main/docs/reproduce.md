# CPU + Mate 40 Pro 异构推理逐行复现手册

> 目标：每一步都有 PC 端命令、手机端命令、预期输出/报文表现。

---

## 0. 前置条件检查

### 0.1 PC 端检查网络连通

```bash
# PC 端执行
ping -c 3 192.168.1.7
```

预期输出：

```text
PING 192.168.1.7 (192.168.1.7) 56(84) bytes of data.
64 bytes from 192.168.1.7: icmp_seq=1 ttl=64 time=2.34 ms
64 bytes from 192.168.1.7: icmp_seq=2 ttl=64 time=1.89 ms
```

### 0.2 手机端检查环境

```bash
# 手机端执行
cat /etc/os-release
uname -a
nproc
free -h
```

预期输出类似：

```text
PRETTY_NAME="Ubuntu 25.10"
...
Linux localhost 6.17.0-PRoot-Distro #1 SMP PREEMPT_DYNAMIC aarch64 GNU/Linux
8
              total        used        free
Mem:          7.3Gi       1.2Gi       6.1Gi
```

### 0.3 PC 端检查工具

```bash
# PC 端执行
git --version
cmake --version
ssh -V
```

---

## 1. 安装依赖

### 1.1 手机端

```bash
# 手机端执行
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y git cmake clang build-essential make wget pkg-config
```

预期输出（节选）：

```text
Setting up clang (1:20.0-63ubuntu1) ...
Setting up pkg-config (1.8.1-4build1) ...
```

验证：

```bash
# 手机端执行
which git cmake clang make wget
```

预期输出：

```text
/usr/bin/git
/usr/bin/cmake
/usr/bin/clang
/usr/bin/make
/usr/bin/wget
```

### 1.2 PC 端

```bash
# PC 端执行
sudo apt update
sudo apt install -y git cmake build-essential make wget
```

---

## 2. 下载 llama.cpp 源码

### 2.1 手机端

```bash
# 手机端执行
mkdir -p ~/Projects/gpu-cpu-phone-test
cd ~/Projects/gpu-cpu-phone-test
git clone https://github.com/ggerganov/llama.cpp.git
```

预期输出：

```text
Cloning into 'llama.cpp'...
remote: Enumerating objects: ..., done.
Receiving objects: 100% (...), done.
```

### 2.2 PC 端

```bash
# PC 端执行
cd ~
git clone https://github.com/ggerganov/llama.cpp.git llama.cpp-host
```

---

## 3. 手机端编译 CPU 后端

### 3.1 命令

```bash
# 手机端执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-cpu
cd build-cpu
cmake .. -DLLAMA_RPC=OFF -DLLAMA_VULKAN=OFF
make -j2
```

### 3.2 关键输出

CMake 阶段：

```text
-- CMAKE_SYSTEM_PROCESSOR: aarch64
-- GGML_SYSTEM_ARCH: ARM
-- Including CPU backend
-- ARM detected
-- Configuring done
-- Generating done
```

编译完成：

```text
[100%] Linking CXX executable ../../bin/llama-cli
[100%] Built target llama-cli
```

### 3.3 验证

```bash
# 手机端执行
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-cpu/bin/llama-cli
```

预期输出：

```text
-rwxr-xr-x 1 root root 71K ... llama-cli
```

---

## 4. 手机端编译 RPC Server

### 4.1 命令

```bash
# 手机端执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-rpc
cd build-rpc
cmake .. -DLLAMA_RPC=ON -DLLAMA_VULKAN=OFF
make -j2 ggml-rpc-server
```

### 4.2 关键输出

```text
-- Using RPC backend
--   RDMA transport disabled
-- Including RPC backend
...
[100%] Linking CXX executable ../../bin/ggml-rpc-server
[100%] Built target ggml-rpc-server
```

### 4.3 验证

```bash
# 手机端执行
ls -lh ~/Projects/gpu-cpu-phone-test/llama.cpp/build-rpc/bin/ggml-rpc-server
```

---

## 5. PC 端编译 RPC Client

### 5.1 命令

```bash
# PC 端执行
cd ~/llama.cpp-host
mkdir -p build-rpc
cd build-rpc
cmake .. -DLLAMA_RPC=ON
make -j
```

### 5.2 关键输出

```text
[100%] Built target llama-completion
[100%] Built target llama-cli
[100%] Built target ggml-rpc-server
```

### 5.3 验证

```bash
# PC 端执行
ls -lh ~/llama.cpp-host/build-rpc/bin/llama-completion
ls -lh ~/llama.cpp-host/build-rpc/bin/llama-cli
ls -lh ~/llama.cpp-host/build-rpc/bin/ggml-rpc-server
```

---

## 6. 模型下载（PC 端）

```bash
# PC 端执行
mkdir -p ~/models
cd ~/models
python3 - <<'PY'
import urllib.request, os

blob = "sha256:8de95da68dc485c0889c205384c24642f83ca18d089559c977ffc6a3972a71a8"
url = f"https://registry.ollama.ai/v2/library/qwen2/blobs/{blob}"
out = "qwen2-0.5b-instruct-q4_0.gguf"

if os.path.exists(out) and os.path.getsize(out) == 352151968:
    print("Already downloaded")
else:
    urllib.request.urlretrieve(url, out)

print("Size:", os.path.getsize(out))
PY
```

预期输出：

```text
Size: 352151968
```

验证魔数：

```bash
# PC 端执行
python3 -c "f=open('/home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf','rb'); print(f.read(4)); f.close()"
ls -lh ~/models/qwen2-0.5b-instruct-q4_0.gguf
```

预期输出：

```text
b'GGUF'
-rw-r--r-- 1 atituiset atituiset 336M ... qwen2-0.5b-instruct-q4_0.gguf
```

---

## 7. 模型传输到手机

### 7.1 PC 端分片

```bash
# PC 端执行
cd ~/models
split -b 50M qwen2-0.5b-instruct-q4_0.gguf qwen2-0.5b-instruct-q4_0.gguf.part_
ls -lh qwen2-0.5b-instruct-q4_0.gguf.part_*
```

### 7.2 PC 端逐片 SCP

```bash
# PC 端执行
for part in aa ab ac ad ae af ag; do
  scp -P 8022 \
    /home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf.part_$part \
    u0_a111@192.168.1.7:/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/models/
done
```

### 7.3 手机端重组并验证

```bash
# 手机端执行
mkdir -p ~/models
cd ~/models
cat qwen2-0.5b-instruct-q4_0.gguf.part_* > qwen2-0.5b-instruct-q4_0.gguf
ls -lh qwen2-0.5b-instruct-q4_0.gguf
xxd -l 4 qwen2-0.5b-instruct-q4_0.gguf
rm -f qwen2-0.5b-instruct-q4_0.gguf.part_*
```

预期输出：

```text
-rw-r--r-- 1 root root 336M ... qwen2-0.5b-instruct-q4_0.gguf
00000000: 4747 5546                                GGUF
```

---

## 8. 手机端本地 CPU 推理基线

```bash
# 手机端执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp/build-cpu/bin
./llama-cli -m ~/models/qwen2-0.5b-instruct-q4_0.gguf -p "你好" -n 32
```

预期输出：

```text
> 你好

你好！有什么可以帮助你的吗？

[ Prompt: 97.4 t/s | Generation: 7.1 t/s ]

> 
```

按 `Ctrl+C` 退出。

---

## 9. 启动手机 RPC Server

### 9.1 命令

```bash
# 手机端执行
mkdir -p /root/.cache/llama.cpp/rpc
cd ~/models
~/Projects/gpu-cpu-phone-test/llama.cpp/build-rpc/bin/ggml-rpc-server \
  -H 192.168.1.7 -p 50052 -c
```

### 9.2 预期输出

```text
Starting RPC server v4.0.1
  endpoint       : 192.168.1.7:50052
  local cache    : /root/.cache/llama.cpp/rpc/
Devices:
  CPU: CPU (7488 MiB, 7488 MiB free)
  transport      : TCP
```

### 9.3 PC 端验证端口

```bash
# PC 端执行
nc -vz 192.168.1.7 50052
```

预期输出：

```text
Connection to 192.168.1.7 50052 port [tcp/*] succeeded!
```

---

## 10. PC 端默认 RPC 模式（手机几乎不参与计算）

### 10.1 命令

```bash
# PC 端执行
cd ~/llama.cpp-host/build-rpc/bin
./llama-completion \
  -m /home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf \
  --rpc 192.168.1.7:50052 \
  -p "你好" -n 32
```

### 10.2 PC 端输出

```text
> 你好
assistant
你好！有什么我可以帮助你的吗？

prompt eval time = 22.85 ms / 9 tokens (393.86 tokens per second)
eval time        = 82.88 ms / 8 runs  (96.53 tokens per second)
```

### 10.3 手机端 RPC Server 报文表现

```text
Accepted client connection
Client connection closed
Accepted client connection
Client connection closed
...
```

---

## 11. PC 端 offload 10 层到手机

### 11.1 命令

```bash
# PC 端执行
cd ~/llama.cpp-host/build-rpc/bin
./llama-completion \
  -m /home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf \
  --rpc 192.168.1.7:50052 -ngl 10 \
  -p "你好" -n 32
```

### 11.2 PC 端输出

```text
load time        = 13330.24 ms
prompt eval time = 470.51 ms / 9 tokens (19.13 tokens per second)
eval time        = 1316.25 ms / 9 runs (6.84 tokens per second)
```

### 11.3 手机端报文表现

同样大量：

```text
Accepted client connection
Client connection closed
...
```

缓存目录会出现文件：

```bash
# 手机端执行
ls -lh /root/.cache/llama.cpp/rpc/
```

---

## 12. PC 端 offload 全部层到手机

### 12.1 命令

```bash
# PC 端执行
cd ~/llama.cpp-host/build-rpc/bin
./llama-completion \
  -m /home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf \
  --rpc 192.168.1.7:50052 -ngl 99 \
  -p "你好" -n 32
```

### 12.2 PC 端输出

```text
load time        = 18548.45 ms
prompt eval time = 1070.85 ms / 9 tokens (8.40 tokens per second)
eval time        = 4858.91 ms / 23 runs (4.73 tokens per second)
```

### 12.3 手机端缓存验证

```bash
# 手机端执行
ls -lh /root/.cache/llama.cpp/rpc/
```

预期输出：

```text
total 139M
-rw-r--r-- 1 root root 138M ... 82dd81180c3a7a43
```

---

## 13. 结果汇总

| 模式 | Prompt (t/s) | Generation (t/s) | 手机是否实际参与 |
|---|---|---|---|
| 手机本地 CPU | 97.4 | **7.1** | ✅ |
| PC + 手机 RPC（默认） | 393.86 | **96.53** | ❌ |
| PC + 手机 RPC（-ngl 10） | 19.13 | **6.84** | ✅ 10 层 |
| PC + 手机 RPC（-ngl 99） | 8.40 | **4.73** | ✅ 全部 |

---

## 14. 常见问题

### 14.1 SSH 连不上手机

将 PC 公钥写入手机 `authorized_keys`：

```bash
# PC 端
cat ~/.ssh/id_ed25519.pub

# 手机 Termux 中
echo "<paste pubkey>" >> ~/.ssh/authorized_keys
```

### 14.2 RPC Server 端口被占用

```bash
# 手机端
killall -9 ggml-rpc-server
```

### 14.3 `-ngl 99` 崩溃

必须加 `-c` 启用 RPC Server 本地缓存。

### 14.4 `llama-cli` 不退出

改用 `llama-completion`。

---

## 15. 可执行脚本

详见同目录下的：

- `run_phone_rpc.sh` — 手机端启动 RPC Server
- `run_phone_baseline.sh` — 手机端本地 CPU 推理
- `run_pc_rpc.sh` — PC 端以 RPC 模式推理

---

## 16. 三机拓扑：GPU PC + 当前机器 + Mate 40 Pro

### 16.1 拓扑说明

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA | `192.168.1.10` |
| 当前机器 | RPC Worker | CPU | `172.26.88.148:50053` |
| Mate 40 Pro | RPC Worker | CPU | `192.168.1.7:50052` |

由于 WSL2 默认 NAT 入站受限、Android Termux 通常拒绝入站连接，三机场景必须使用 **SSH 隧道模式**。

### 16.2 GPU PC 编译 CUDA + RPC Host

```bash
# GPU PC 端执行
cd ~/projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-cuda-rpc
cd build-cuda-rpc
cmake .. -DGGML_CUDA=ON -DGGML_RPC=ON
make -j
```

预期输出：

```text
-- Using CUDA backend
-- Using RPC backend
...
[100%] Built target llama-completion
```

### 16.3 当前机器编译 RPC Server

```bash
# 当前机器执行
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
mkdir -p build-rpc
cd build-rpc
cmake .. -DGGML_RPC=ON
make -j ggml-rpc-server
```

### 16.4 统一 commit

三端必须使用同一 llama.cpp commit，当前锁定为：

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
# 在 GPU PC 和手机重复同样操作并重新编译
```

### 16.5 隧道模式启动（当前机器执行）

```bash
# 当前机器执行
cd ~/Projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./setup_tunnels.sh
```

预期输出：

```text
=== Hetero-LLaMA SSH 隧道启动 ===
  GPU PC : atituiset@192.168.1.10
  phone  : 127.0.0.1:50052
  mode   : all

[1/3] 启动当前机器 RPC Server（绑定 127.0.0.1:50053）
      OK
[2/3] 建立到手机的 SSH 本地转发（127.0.0.1:150052 -> 127.0.0.1:50052）
      OK   # 若手机离线则显示 WARN
[3/3] 建立到 GPU PC 的 SSH 反向隧道
Connection to 127.0.0.1 50053 port [tcp/*] succeeded!
      OK
```

### 16.6 GPU PC 端启动三机推理

```bash
# GPU PC 端执行
cd ~/projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./run_gpu_host.sh 20 "你好" 5
```

预期输出（手机离线时 127.0.0.1:50052 会失败，其余 Worker 仍可运行）：

```text
=== GPU PC 端三机 RPC 推理 ===
  model    : /home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf
  rpc      : 127.0.0.1:50053,127.0.0.1:50052
  ngl      : 20
  prompt   : 你好
  n        : 5

Failed to connect to 127.0.0.1:50052
...
> 你好
assistant
你好！有什么可以帮助你的
```

### 16.7 双机 Phase 2（GPU PC + 手机）

若只想验证 GPU PC 与手机：

```bash
# 当前机器执行：仅暴露手机 Worker
./setup_tunnels.sh phone

# GPU PC 执行
TUNNEL_MODE=1 ./run_gpu_host_2node.sh 20 "你好" 5
```

### 16.8 常见问题

#### GPU PC 无法直连当前机器 RPC Server

现象：`Remote RPC server crashed or returned malformed response`。

原因：WSL2 默认 NAT 下，从 LAN 到 WSL2 VM 的数据路径异常（TCP 握手成功，但后续数据被丢弃）。

解决：使用隧道模式。

#### 手机 SSH 不可达

现象：`WARN: 手机 SSH 不可达，跳过手机隧道`。

原因：手机 WiFi 休眠、IP 变化或被路由器隔离。

解决：重新点亮手机屏幕、重新连接 WiFi，或确认路由器 DHCP 分配的 IP。
