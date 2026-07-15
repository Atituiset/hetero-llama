# CPU + Mate 40 Pro + GPU PC 异构推理项目报告

> 生成时间：2026-07-10
> 结论：**GPU PC（CUDA）作为 Host，通过 SSH 隧道成功调度当前机器（CPU RPC Worker）完成异构推理；三机链路因手机 WiFi 离线未完成端到端验证，但脚本与隧道机制已就绪。**

---

## 1. 项目目标

在原有 PC + 手机双机 RPC 推理基础上，引入 GPU PC（NVIDIA RTX 4050）作为 llama.cpp Host，构建三机异构推理拓扑：

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA | `192.168.1.10` |
| 当前机器 | RPC Worker | CPU | `172.26.88.148:50053` |
| Mate 40 Pro | RPC Worker | CPU | `192.168.1.7:50052` |

---

## 2. 三机推理实施结果

### 2.1 已验证：GPU PC + 当前机器（SSH 隧道模式）

由于 WSL2 默认 NAT 入站受限，当前机器无法被 GPU PC 直接访问。通过新增 `setup_tunnels.sh` 建立 SSH 反向隧道后，GPU PC 成功连接当前机器 RPC Worker 并完成推理。

命令：

```bash
# 当前机器
cd ~/Projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./setup_tunnels.sh

# GPU PC
cd ~/projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./run_gpu_host.sh 20 "你好" 5
```

输出：

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

性能：

| 指标 | 数值 |
|---|---|
| load time | 16,384.89 ms |
| prompt eval | 12.88 t/s |
| eval | 8.55 t/s |

作为对比，GPU PC 本地 CUDA（无 RPC）性能：

| 指标 | 数值 |
|---|---|
| load time | 194.44 ms |
| prompt eval | 1,273.71 t/s |
| eval | 282.63 t/s |

说明：RPC 隧道的初始化与跨设备传输引入显著开销，但推理链路可正常工作。

### 2.2 未验证：完整三机链路（手机离线）

测试期间 Mate 40 Pro 无法通过网络访问（ping/SSH 均失败），因此 GPU PC + 当前机器 + 手机的三机端到端推理未能完成。失败信息：

```text
Failed to connect to 127.0.0.1:50052
```

手机离线时，`setup_tunnels.sh` 会自动跳过手机隧道，系统降级为 GPU PC + 当前机器双机运行。

### 2.3 根因说明：WSL2 入站网络

GPU PC 能 `nc -vz 172.26.88.148 50053` 建立 TCP 握手，但发送 HELLO 数据后无响应。这是 WSL2 默认 NAT 网络的已知行为：外部 LAN 主机可与 WSL2 VM 建立 TCP 连接，但数据包常被丢弃。解决方式：

1. **当前实现**：SSH 反向隧道（已验证可用）。
2. **更优方案**：在 Windows 侧启用 WSL2 `networkingMode=mirrored`（需 WSL 重启）。

---

## 3. 原始双机目标

验证在 PC（x86_64，纯 CPU）与华为 Mate 40 Pro（ARM64，Termux + Ubuntu proot）之间，通过 `llama.cpp` 的原生 RPC 后端实现跨设备异构推理，并验证 `-ngl` 参数对分层调度的实际控制效果。

---

## 2. 实际执行流程（时间线）

| 时间 | 操作 | 结果 |
|---|---|---|
| 2026-07-07 | 手机端编译 llama.cpp CPU 后端 | ✅ 成功 |
| 2026-07-07 | 手机端编译 RPC Server (`ggml-rpc-server`) | ✅ 成功 |
| 2026-07-07 | PC 端编译 RPC Client (`llama-completion`) | ✅ 成功 |
| 2026-07-07 | 将 336 MB 的 Qwen2-0.5B-Instruct-Q4_0 GGUF 传入手机 | ✅ 成功 |
| 2026-07-07 | 手机本地 CPU 基线测试 | ✅ 约 7.1 t/s |
| 2026-07-07 | PC + 手机 RPC 连接，默认调度 | ✅ 连接成功，但调度器选择 PC CPU（96 t/s） |
| 2026-07-07 | PC + 手机 RPC，`-ngl 10` | ✅ 手机参与 10 层，约 6.84 t/s |
| 2026-07-07 | PC + 手机 RPC，`-ngl 99` | ✅ 手机跑全部层，约 4.73 t/s（非 DEBUG） |
| 2026-07-08 | 添加 DEBUG 日志脚本 | ✅ `run_phone_rpc.sh`、`run_pc_rpc.sh` 支持 `DEBUG=1` |
| 2026-07-08 19:42 | 跑一次带 wall-clock 时间戳的 DEBUG 推理 | ✅ 确认 scheduler 将 821 节点 offload 到 RPC0 |
| **2026-07-08 21:04** | **三种分层配置对比验证** | ✅ 见下表 |

---

## 3. 三种分层配置对比（最新验证）

模型：`Qwen2-0.5B-Instruct-Q4_0`（24 层 transformer），prompt `"你好"`，生成 5 tokens。

| 配置 | 命令 | prompt eval | generation (eval) | 手机 graph 节点数 | 日志文件 |
|---|---|---|---|---|---|
| **全部在 PC CPU** | `./llama-completion`（无 `--rpc`） | **386.17 t/s** | **95.11 t/s** | 0（未连接） | `pc_cpu_20260708_210444.log` |
| **4 层手机 + 20 层 CPU** | `./run_pc_rpc.sh 4` | **34.34 t/s** | **8.46 t/s** | 108 节点 / 159 张量 | `pc_ngl4_20260708_210444.log` |
| **全部 24 层手机** | `./run_pc_rpc.sh 99` | **8.96 t/s** | **3.16 t/s** | 821 节点 / 1165 张量 | `pc_ngl99_20260708_210444.log` |

> 注：本次对比的 RPC 运行均开启 `DEBUG=1`，日志开销会降低推理速度。真实性能数据见第 5 节“性能数据汇总”。

### 关键观察

1. **`-ngl` 确实控制了手机参与的比例**：
   - `-ngl 4` 时手机端 `graph_compute` 只有 **108 节点**。
   - `-ngl 99` 时手机端 `graph_compute` 达到 **821 节点**（完整 forward）。

2. **DEBUG 模式下中间配置速度仍高于全 offload**：
   - 纯 PC CPU 最快（95.11 t/s）。
   - 4 层 offload 到手机后降到 8.46 t/s。
   - 全部 offload 后降到 3.16 t/s。
   - 真实（非 DEBUG）数据见第 5 节。

3. **分层调度的数据流**：
   - 纯 CPU：无网络传输。
   - `-ngl 4`：PC 与手机之间出现 `set_tensor` / `get_tensor`，但张量数量和尺寸明显小于 `-ngl 99`。
   - `-ngl 99`：每次 token 都要把 embd 发到手机，再把 logits 取回。

---

## 4. 核心验证结论

### 4.1 是“分层调度推理”

llama.cpp 的 `ggml scheduler` 把一次 forward 的计算图切成了多个 split：

```text
## SPLIT #0: CPU # 0 inputs
## SPLIT #1: RPC0[192.168.1.7:50052] # 6 inputs
```

- `SPLIT #0` 在 PC 本机 CPU 上执行少量前置/输入处理。
- `SPLIT #1` 通过 RPC 分发到手机，执行主体 transformer 计算。

### 4.2 手机确实在干活

手机 RPC Server 日志中能看到完整的张量收发和计算：

```text
2026-07-08 21:06:03 [graph_compute] device: 0, n_nodes: 821, n_tensors: 1165
2026-07-08 21:06:04 [graph_compute] device: 0, n_nodes: 821, n_tensors: 1165
...
2026-07-08 21:06:44 [graph_compute] device: 0, n_nodes: 108, n_tensors: 159
```

821 节点对应 `-ngl 99`（全部层），108 节点对应 `-ngl 4`（4 层）。

### 4.3 模型权重确实缓存在手机

手机端启动 RPC Server 时加了 `-c` 参数，权重首次传输后缓存在：

```text
/root/.cache/llama.cpp/rpc/
```

DEBUG 运行时手机端内存占用约 **1012 MiB**（权重 330M + 上下文 384M + 计算缓冲 298M）。

---

## 5. 性能数据汇总（全量）

### 5.1 真实性能对比（非 DEBUG 模式）

以下数据为**关闭 DEBUG 日志**后的实际推理速度，可用于评估三种配置的真实性能。

| 模式 | prompt eval | generation | 手机参与层数 | 日志文件 |
|---|---|---|---|---|
| PC 本地 CPU（无 RPC） | **380.78 t/s** | **99.75 t/s** | 0 层 | `pc_cpu_nodebug_20260708_213312.log` |
| PC + 手机 RPC（`-ngl 4`） | **37.64 t/s** | **7.59 t/s** | 4 层 | `pc_ngl4_nodebug_20260708_212253.log` |
| PC + 手机 RPC（`-ngl 99`） | **9.73 t/s** | **3.36 t/s** | 24 层（全部） | `pc_ngl99_nodebug_20260708_212345.log` |

### 5.2 DEBUG 模式下的性能（用于验证调度细节）

开启 `DEBUG=1` 后，大量日志写入会拖慢推理，数据仅用于验证 scheduler 和手机实际工作量。

| 模式 | prompt eval | generation | 手机 graph 节点数 | 日志文件 |
|---|---|---|---|---|
| PC 本地 CPU（无 RPC） | 386.17 t/s | 95.11 t/s | 0 | `pc_cpu_20260708_210444.log` |
| PC + 手机 RPC（`-ngl 4`） | 34.34 t/s | 8.46 t/s | 108 节点 / 159 张量 | `pc_ngl4_20260708_210444.log` |
| PC + 手机 RPC（`-ngl 99`） | 8.96 t/s | 3.16 t/s | 821 节点 / 1165 张量 | `pc_ngl99_20260708_210444.log` |

### 5.3 历史数据参考

| 模式 | generation | 备注 |
|---|---|---|
| 手机本地 CPU | ~7.1 t/s | 2026-07-07 基线 |
| PC + 手机 RPC（默认调度） | ~96 t/s | scheduler 选择 PC CPU，手机未参与 |
| PC + 手机 RPC（`-ngl 10`） | ~6.84 t/s | 2026-07-07 测试 |
| PC + 手机 RPC（`-ngl 99`） | ~4.73 t/s | 2026-07-07 非 DEBUG 测试，与本次 3.36 t/s 有差异（手机温度/网络状态不同） |

---

## 6. 交付文件清单

### 6.1 报告与协议

```text
/home/atituiset/Projects/gpu-cpu-phone-test/
├── report.md              # 本报告（最新）
├── reproduce.md           # 逐行复现手册
├── plan.md                # 原始规划
├── protocol.md            # 双/三 Agent 通信协议 v0.2
├── inbox.md               # PC → 手机任务信箱
├── outbox.md              # 手机 → PC 结果信箱
├── config.env             # 三机拓扑配置
└── ../common/scripts/ts-log.sh  # 给日志加 wall-clock 时间戳的小工具
```

### 6.2 一键脚本

```text
run_phone_rpc.sh         # 手机端启动 RPC Server（支持 DEBUG=1）
run_phone_baseline.sh    # 手机端本地 CPU 推理
run_pc_rpc.sh            # PC 端 RPC 推理（支持 DEBUG=1）
run_cpu_rpc_server.sh    # 当前机器启动 RPC Server
run_gpu_host.sh          # GPU PC 三机 Host
run_gpu_host_2node.sh    # GPU PC 双机 Host（仅手机）
setup_tunnels.sh         # 当前机器建立 SSH 隧道
```

### 6.3 日志（按时间命名，可区分）

```text
logs/
# 三机验证（最新）
├── pc_current_final_ngl20_*.log      # GPU PC + 当前机器 双机验证
├── pc_3node_tun_ngl20_*.log          # GPU PC + 当前机器 + 手机（手机离线）
├── pc_2node_ngl20_*.log              # GPU PC + 手机直连尝试（手机离线）
└── pc_local_ngl999_*.log             # GPU PC 本地 CUDA 基线

# 历史双机验证
# DEBUG 模式（用于验证 scheduler 和张量传输）
├── pc_cpu_20260708_210444.log            # 纯 PC CPU
├── phone_cpu_20260708_210444.log         # 说明：本次无 RPC Server
├── pc_ngl4_20260708_210444.log           # 4 层手机 + 20 层 CPU
├── phone_ngl4_20260708_210444.log        # 手机端对应日志
├── pc_ngl99_20260708_210444.log          # 全部 24 层手机
└── phone_ngl99_20260708_210444.log       # 手机端对应日志

# 非 DEBUG 模式（用于真实性能测试）
├── pc_cpu_nodebug_20260708_213312.log    # 纯 PC CPU
├── phone_cpu_nodebug_20260708_213312.log # 说明：本次无 RPC Server
├── pc_ngl4_nodebug_20260708_212253.log   # 4 层手机 + 20 层 CPU
├── phone_ngl4_nodebug_20260708_212253.log# 手机端对应日志
├── pc_ngl99_nodebug_20260708_212345.log  # 全部 24 层手机
└── phone_ngl99_nodebug_20260708_212345.log# 手机端对应日志
```

---

### 6.4 怎么看日志

每份日志都加了 `YYYY-MM-DD HH:MM:SS` 的 wall-clock 时间戳。重点看两类特征：PC 端的 **scheduler split** 和手机端的 **graph_compute 节点数**。

#### PC 端日志关键 grep

```bash
# 看 scheduler 把图切成了几块、分别给谁
$ grep -E "## SPLIT" logs/pc_ngl99_20260708_210444.log | head -3
## SPLIT #0: CPU # 0 inputs
## SPLIT #1: RPC0[192.168.1.7:50052] # 6 inputs : [embd (31K)] ...

# 看最终性能
$ grep "eval time" logs/pc_ngl99_20260708_210444.log
prompt eval time = 1004.90 ms / 9 tokens (111.66 ms per token, 8.96 tokens per second)
eval time        = 1264.33 ms / 4 runs   (316.08 ms per token, 3.16 tokens per second)
```

#### 手机端日志关键 grep

```bash
# 看手机实际跑了多少节点
$ grep "graph_compute" logs/phone_ngl99_20260708_210444.log | head -3
2026-07-08 21:06:03 [graph_compute] device: 0, n_nodes: 821, n_tensors: 1165
2026-07-08 21:06:04 [graph_compute] device: 0, n_nodes: 821, n_tensors: 1165

$ grep "graph_compute" logs/phone_ngl4_20260708_210444.log | head -3
2026-07-08 21:06:44 [graph_compute] device: 0, n_nodes: 108, n_tensors: 159
2026-07-08 21:06:45 [graph_compute] device: 0, n_nodes: 108, n_tensors: 159

# 看 PC 和手机之间的 tensor 收发
$ grep -E "set_tensor|get_tensor" logs/phone_ngl99_20260708_210444.log | head -6
[set_tensor] buffer: ..., size: 3584      ← PC 发输入给手机
[set_tensor] buffer: ..., size: 4
[graph_compute] device: 0, n_nodes: 821  ← 手机计算
[get_tensor] buffer: ..., size: 607744    ← PC 从手机取结果
```

#### 三种配置在日志上的区别

| 配置 | PC 端特征 | 手机端特征 |
|---|---|---|
| 纯 PC CPU | 无 `SPLIT #1`，无 `connected to 192.168` | `phone_cpu_*.log` 显示无 RPC |
| `-ngl 4` | 有 `SPLIT #1: RPC0` | `graph_compute n_nodes: 108` |
| `-ngl 99` | 有 `SPLIT #1: RPC0` | `graph_compute n_nodes: 821` |

---

## 7. 最简复现

### 7.1 纯 PC CPU

```bash
cd /home/atituiset/llama.cpp-host/build-rpc/bin
./llama-completion \
  -m /home/atituiset/models/qwen2-0.5b-instruct-q4_0.gguf \
  -p "你好" -n 5
```

### 7.2 4 层手机 + 20 层 CPU

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test
DEBUG=1 ./run_pc_rpc.sh 4 "你好" 5 2>&1 | ../common/scripts/ts-log.sh | tee logs/pc_ngl4_$(date +%Y%m%d_%H%M%S).log
```

### 7.3 全部层手机

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test
DEBUG=1 ./run_pc_rpc.sh 99 "你好" 5 2>&1 | ../common/scripts/ts-log.sh | tee logs/pc_ngl99_$(date +%Y%m%d_%H%M%S).log
```

### 7.4 手机端启动 RPC Server（带时间戳）

```bash
ssh -p 8022 u0_a111@192.168.1.7
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test
DEBUG=1 ./run_phone_rpc.sh 2>&1 | ../common/scripts/ts-log.sh > /tmp/phone_rpc_$(date +%Y%m%d_%H%M%S).log
```

---

## 8. 三机新增交付文件

```text
/home/atituiset/Projects/gpu-cpu-phone-test/
├── config.env              # 三机拓扑配置（含 TUNNEL_MODE）
├── setup_tunnels.sh        # 当前机器一键启动隧道
├── run_cpu_rpc_server.sh   # 当前机器 RPC Server
├── run_gpu_host.sh         # GPU PC 三机 Host
├── run_gpu_host_2node.sh   # GPU PC 双机 Host（仅手机）
├── protocol.md             # 三机通信协议 v0.2
├── reproduce.md            # 三机复现手册
└── report.md               # 本报告
```

日志目录：

```text
logs/
├── pc_current_final_ngl20_*.log      # GPU PC + 当前机器 双机验证
├── pc_3node_tun_ngl20_*.log          # GPU PC + 当前机器 + 手机（手机离线）
├── pc_2node_ngl20_*.log              # GPU PC + 手机直连尝试（手机离线）
└── pc_local_ngl999_*.log             # GPU PC 本地 CUDA 基线
```

---

## 9. 关键发现

1. **SSH 隧道可解决 WSL2/Android 入站网络问题**：`setup_tunnels.sh` 把两个 Worker 映射到 GPU PC 本地端口，Host 无需直接访问 WSL2/手机 IP。
2. **`-ngl` 在 CUDA + RPC 混合场景下行为需关注**：实测 ngl=20 时，scheduler 将 5 层放 GPU PC CPU、15 层放 RPC Worker、5 层放 GPU CUDA，与直觉不符，可能是 scheduler 对 RPC backend 内存估计导致。
3. **RPC 初始化开销显著**：即便 ngl=999，只要连接 RPC Worker，模型加载时间就上升到约 20s（本地 CUDA 仅 200ms）。
4. **统一 commit 是 RPC 互通前提**：三端 commit 不一致时会直接报 `Remote RPC server crashed or returned malformed response`。
5. **手机网络稳定性是端到端验证的瓶颈**：本次手机 WiFi 离线导致三机链路未能跑通。

---

## 10. 下一步建议

- 手机重新联网后，运行完整 `TUNNEL_MODE=1 ./run_gpu_host.sh 20 "你好" 5` 三机验证。
- 尝试 `-ngl 999` 或 `-ngl 0` 等极端配置，理解 scheduler 在 CUDA+RPC 混合后端下的分配策略。
- 评估 WSL2 `networkingMode=mirrored` 对性能的影响。
- 尝试手机端 Vulkan backend，利用 Mali-G78 GPU。

---

## 11. 追加：Qwen3-1.7B GPU + WSL RPC 通宵基准（2026-07-15）

> 目标：在 GPU PC（RTX 4050 6GB）上验证更大模型的 CUDA 基线，并测试 GPU PC + 当前 WSL 机器（CPU RPC Worker）的双机异构推理。
> 模型：`qwen3:1.7b`（Ollama 拉取，实际量化 Q4_K_M，约 2.0B 参数）。
> 命令：`llama-completion -m qwen3-1.7b-instruct-ollama.gguf -p "你好" -n 32 -no-cnv -ngl N [--rpc 127.0.0.1:50053]`

### 11.1 环境

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 | `192.168.1.10` |
| 当前 WSL | RPC Worker | CPU | `127.0.0.1:50053`（SSH 反向隧道） |

### 11.2 GPU PC 本地 CUDA 性能

| ngl | load time | prompt eval | generation | 观察 |
|---|---|---|---|---|
| 0（纯 CPU） | 1920 ms | 1 token / inf t/s | 32 runs / 39.81 t/s | 全部在 CPU，GPU 几乎空闲 |
| 12 | 1350 ms | 1 token / inf t/s | 32 runs / 65.82 t/s | 12 层 GPU |
| 24 | 633 ms | 1 token / inf t/s | 32 runs / 98.31 t/s | 24 层 GPU |
| 99（全部 GPU） | 365 ms | 1 token / inf t/s | 32 runs / **132.84 t/s** | 全部层 offload 到 RTX 4050 |

> prompt 只有 `"你好"` 1 个 token，所以 prompt eval 时间为 0，速度显示为 `inf`。

### 11.3 GPU PC + WSL RPC 双机性能

| ngl | load time | prompt eval | generation | 观察 |
|---|---|---|---|---|
| 0（全部 RPC） | 1930 ms | 1 token / inf t/s | 32 runs / **44.13 t/s** | 全部层在 WSL CPU， surprisingly 比本地 CPU 快 |
| 12 | 12147 ms | 1 token / inf t/s | 32 runs / 18.80 t/s | GPU + RPC 混合，RPC 初始化开销大 |
| 24 | 21987 ms | 1 token / inf t/s | 32 runs / 16.46 t/s | 更多层 offload 到 RPC，但网络 RTT 成为瓶颈 |
| 99 | 25360 ms | 1 token / inf t/s | 32 runs / 21.60 t/s | scheduler 把大量计算放回 GPU PC，RPC 只跑少量 |

### 11.4 GPU 功耗与显存占用

采样方式：`nvidia-smi --query-gpu=power.draw,memory.used,utilization.gpu,temperature.gpu --format=csv -l 1`

| 配置 | 平均功耗 | 平均显存占用 | 平均利用率 | 平均温度 | 采样数 |
|---|---|---|---|---|---|
| gpu_local_ngl0 | 11.7 W | 206 MiB | 0.0 % | 41.2 °C | 4 |
| gpu_local_ngl12 | 16.3 W | 1154 MiB | 3.7 % | 42.7 °C | 3 |
| gpu_local_ngl24 | 17.8 W | 530 MiB | 0.0 % | 43.0 °C | 2 |
| gpu_local_ngl99 | 25.7 W | 2377 MiB | 0.0 % | 44.0 °C | 2 |
| gpu_rpc_ngl0 | 22.8 W | 206 MiB | 0.0 % | 45.0 °C | 4 |
| gpu_rpc_ngl12 | 16.1 W | 453 MiB | 0.3 % | 45.1 °C | 18 |
| gpu_rpc_ngl24 | 16.1 W | 603 MiB | 0.3 % | 45.9 °C | 31 |
| gpu_rpc_ngl99 | 15.1 W | 620 MiB | 0.9 % | 46.4 °C | 35 |

> 显存占用采样较稀疏，存在数值波动；可看出 `-ngl 99` 时显存占用最高（约 2.4 GB），而 RPC 混合配置显存占用较低。

### 11.5 关键发现

1. **RTX 4050 6GB 可以轻松跑 Qwen3-1.7B Q4_K_M**：本地 `-ngl 99` 达到 **132.84 t/s**，显存占用约 2.4 GB。
2. **`-ngl` 在纯 CUDA 场景下呈单调加速**：ngl 0 → 12 → 24 → 99，generation 速度从 39.81 提升到 132.84 t/s，符合预期。
3. **RPC 混合场景的 `-ngl` 行为非单调**：
   - `ngl=0` 时速度反而最快（44.13 t/s），说明 scheduler 把全部层放到了 WSL CPU。
   - `ngl=12/24` 时加载时间暴增到 12–22 s，且速度下降到 16–18 t/s，说明跨 WSL 网络（RTT ~90 ms）的传输开销显著。
   - `ngl=99` 时速度回升到 21.60 t/s，scheduler 倾向于把计算留在本地 GPU。
4. **RPC 初始化开销与模型大小相关**：对于 1.7B Q4_K_M，首次连接 RPC Worker 的加载时间为 12–25 s；后续同 Worker 复用可缩短（本次脚本每次启动新进程，未复用）。
5. **WSL 反向隧道稳定**：整晚运行中 `rpc_server` 与 `reverse_tunnel` 会话保持存活，双机链路可复现。

### 11.6 新增脚本

```text
scripts/overnight_gpu_benchmark.sh   # GPU PC 通宵自动基准脚本
```

该脚本：
- 自动探测 Ollama 模型目录（系统服务 `/usr/share/ollama/.ollama/models` 或用户目录）。
- 拉取模型并链接为 GGUF。
- 运行本地 CUDA + WSL RPC 多组 `-ngl` 基线。
- 同步记录 `nvidia-smi` 功耗/显存/利用率/温度。
- 自动生成汇总文件。

---

## 12. 更新后的下一步建议

- 用同一套脚本测试 **Qwen2.5-3B / 7B**，验证 RTX 4050 6GB 的显存上限和速度衰减。
- 测试 **手机 RPC Worker** 加入后的三机链路（当前手机未参与）。
- 如果目标是 **Qwen3.6-35B-A3B-FP8**，需要升级到 24GB+ 显存的 GPU 或云端实例；当前脚本可直接复用。
- 优化 RPC 加载时间：考虑让 RPC Worker 预加载权重，或复用 `llama-server` 长连接。

---

详细复现步骤请见 `reproduce.md`。通信协议请见 `protocol.md`。
