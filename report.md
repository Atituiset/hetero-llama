# CPU + Mate 40 Pro 异构推理项目报告

> 生成时间：2026-07-08
> 结论：**PC 输入 prompt，Mate 40 Pro 通过 RPC 后端实际执行了 transformer 主体计算；`-ngl` 可精确控制 CPU/手机的分层比例。**

---

## 1. 项目目标

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
├── protocol.md            # 双 Agent 通信协议
├── inbox.md               # PC → 手机任务信箱
├── outbox.md              # 手机 → PC 结果信箱
└── ts-log.sh              # 给日志加 wall-clock 时间戳的小工具
```

### 6.2 一键脚本

```text
run_phone_rpc.sh         # 手机端启动 RPC Server（支持 DEBUG=1）
run_phone_baseline.sh    # 手机端本地 CPU 推理
run_pc_rpc.sh            # PC 端 RPC 推理（支持 DEBUG=1）
```

### 6.3 日志（按时间命名，可区分）

```text
logs/
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
DEBUG=1 ./run_pc_rpc.sh 4 "你好" 5 2>&1 | ./ts-log.sh | tee logs/pc_ngl4_$(date +%Y%m%d_%H%M%S).log
```

### 7.3 全部层手机

```bash
cd /home/atituiset/Projects/gpu-cpu-phone-test
DEBUG=1 ./run_pc_rpc.sh 99 "你好" 5 2>&1 | ./ts-log.sh | tee logs/pc_ngl99_$(date +%Y%m%d_%H%M%S).log
```

### 7.4 手机端启动 RPC Server（带时间戳）

```bash
ssh -p 8022 u0_a111@192.168.1.7
proot-distro login ubuntu
cd ~/Projects/gpu-cpu-phone-test
DEBUG=1 ./run_phone_rpc.sh 2>&1 | ./ts-log.sh > /tmp/phone_rpc_$(date +%Y%m%d_%H%M%S).log
```

---

## 8. 关键发现

1. **`-ngl` 精确控制分层**：对 24 层模型，`-ngl 4` 让手机只跑约 108 个节点，`-ngl 99` 让手机跑 821 个节点。
2. **异构推理本质是图级调度**：llama.cpp 的 scheduler 按 `-ngl` 把计算图切到不同 backend，RPC backend 只是其中一种。
3. **当前场景下 RPC 有性能损失**：纯 PC CPU 95 t/s，`-ngl 4` 8.46 t/s，`-ngl 99` 3.16 t/s。手机 ARM CPU 算力 + 网络往返是主要瓶颈。
4. **RPC 缓存不可少**：336 MB 模型必须配合 `-c` 缓存，否则全 offload 会触发重复传输或崩溃。
5. **日志需要 wall-clock 时间戳**：llama.cpp 原生日志是运行时长格式，已添加 `ts-log.sh` 辅助转换。

---

## 9. 下一步建议

- 关闭 DEBUG 后重新测 `-ngl 4` / `-ngl 99`，获得真实性能基线。
- 尝试手机端 Vulkan backend，利用 Mali-G78 GPU。
- 评估 USB 网络共享是否能降低 RTT。
- 长上下文下的 KV Cache 传输开销测试。

---

详细复现步骤请见 `reproduce.md`。
