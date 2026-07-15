# 3-Machine 通宵基准复现手册

## 环境

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 / RTX 4050 6GB | `192.168.1.10` |
| 当前机器（WSL） | RPC Worker | CPU | `172.26.88.148:50053` |
| Mate 40 Pro | RPC Worker | CPU | `192.168.1.7:50052` |

---

## 1. 前置条件

### 1.1 三端编译

**GPU PC**

```bash
cd ~/projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
mkdir -p build-cuda-rpc && cd build-cuda-rpc
cmake .. -DGGML_CUDA=ON -DGGML_RPC=ON
make -j
```

**当前机器（WSL）**

```bash
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
mkdir -p build-rpc && cd build-rpc
cmake .. -DGGML_RPC=ON
make -j ggml-rpc-server
```

**手机（Termux proot Ubuntu）**

```bash
ssh -p 8022 u0_a111@192.168.1.7
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test/llama.cpp
git checkout 152d337fadb93c2a099653c4072d5512c92c5bfd
mkdir -p build-rpc && cd build-rpc
cmake .. -DGGML_RPC=ON
make -j2 ggml-rpc-server
```

### 1.2 免密 SSH

- 当前机器 → GPU PC：`ssh atituiset@192.168.1.10` 无需密码。
- 当前机器 → 手机：`ssh -p 8022 u0_a111@192.168.1.7` 无需密码。

### 1.3 手机 proot 依赖

手机端需要在 proot-distro Ubuntu 内安装 `socat`：

```bash
ssh -p 8022 u0_a111@192.168.1.7
proot-distro login ubuntu
apt-get update && apt-get install -y socat
```

### 1.4 Ollama

GPU PC 上已安装 Ollama，并能拉取 `qwen3:1.7b` 与 `qwen2:0.5b`。

---

## 2. 启动链路

### 2.1 当前机器启动隧道

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
./scripts/setup_tunnels.sh
```

预期输出：

```text
=== Hetero-LLaMA SSH 隧道启动 ===
  GPU PC : atituiset@192.168.1.10
  phone  : 192.168.1.7:50052
  mode   : all

[1/3] 启动当前机器 RPC Server（绑定 127.0.0.1:50053）
      OK
[2/3] 建立到手机的 SSH 本地转发（127.0.0.1:50052 -> /data/data/com.termux/files/home/.phone_rpc_50052.sock）
      OK
[3/3] 建立到 GPU PC 的 SSH 反向隧道
      OK
```

### 2.2 GPU PC 启动基准

```bash
ssh atituiset@192.168.1.10
cd ~/projects/gpu-cpu-phone-test/3-machine
tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'
```

### 2.3 当前机器启动 watchdog

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
nohup ./scripts/overnight_watchdog.sh --loop > logs/overnight_watchdog.log 2>&1 &
```

---

## 3. 观察进度

```bash
# 当前机器 watchdog 日志
tail -f logs/overnight_watchdog.log

# 全局状态
tail -f ~/.claude/hetero_overnight_status.md

# GPU PC 基准日志
ssh atituiset@192.168.1.10 'tail -f ~/projects/gpu-cpu-phone-test/3-machine/logs/qwen3_1_7b_*.log'
```

---

## 4. 中断后恢复

如果 Claude session 结束、网络断开、或设备休眠，按以下步骤恢复：

1. **检查状态文件**：
   ```bash
   tail ~/.claude/hetero_overnight_status.md
   ```

2. **在当前机器检查 watchdog 是否还在**：
   ```bash
   pgrep -f overnight_watchdog.sh
   ```
   若不在，重新启动：
   ```bash
   cd /home/atituiset/Projects/gpu-cpu-phone-test/3-machine
   nohup ./scripts/overnight_watchdog.sh --loop > logs/overnight_watchdog.log 2>&1 &
   ```

3. **watchdog 会自动恢复**：
   - 本地 `rpc_server` 和 `reverse_tunnel` tmux 会话
   - 手机 SSH 链路、`phone_tunnel`、手机 RPC Server
   - GPU PC 上的 `gpu_bench` tmux 会话

4. **基准脚本会断点续跑**：
   `overnight_gpu_benchmark.sh` 会跳过已有非空日志的 `(model, topology, ngl)` 组合，从中断处继续。

5. **如需强制全部重跑**：
   ```bash
   # 在 GPU PC
   tmux new -d -s gpu_bench 'FORCE_RERUN=1 ./scripts/overnight_gpu_benchmark.sh'
   ```

---

## 5. 完成后

GPU PC 上生成 `logs/summary_*.txt` 后，watchdog 会自动退出 `--loop`。

```bash
ssh atituiset@192.168.1.10 'cat ~/projects/gpu-cpu-phone-test/3-machine/logs/summary_*.txt | tail -40'
```

---

## 6. 常见问题

### 6.1 手机 SSH 不可达

现象：`WARN: 手机 SSH 不可达`。

解决：点亮手机屏幕，确保 Wi-Fi 连接，确认 IP 未变。

### 6.2 GPU PC 上 `gpu_bench` 反复重启但无日志

可能是 Ollama 拉取失败或模型链接失败。在 GPU PC 手动执行：

```bash
cd ~/projects/gpu-cpu-phone-test/3-machine
DRY_RUN=1 ./scripts/overnight_gpu_benchmark.sh
```

### 6.3 已完成组合的日志为空

空日志被视为未完成。`overnight_gpu_benchmark.sh` 只跳过非空日志文件。
