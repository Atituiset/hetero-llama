# 3-Machine 异构推理模式

本目录为 `feat/3-machine-inference` 分支预留位置。

## 状态

- main 分支上已有的早期 3-machine 实验产物已先迁入本目录：
  - `scripts/run_cpu_rpc_server.sh`
  - `scripts/run_gpu_host.sh`
  - `scripts/run_gpu_host_2node.sh`
  - `scripts/setup_tunnels.sh`
  - `logs/` 下的 `cpu_rpc_*`、`pc_2node_*`、`pc_3node_*`、`pc_current_*`、`pc_local_*`、`pc_ngl20_*` 日志
- **完整、最新的 3-machine 实现仍在独立分支：`feat/3-machine-inference`**，验证稳定后会整体迁入并覆盖/合并本目录。

## 何时合入

当 `feat/3-machine-inference` 验证稳定后，会将其内容整体迁移到本目录：

```
3-machine/
├── config.env
├── scripts/
│   ├── run_cpu_rpc_server.sh
│   ├── run_gpu_host.sh
│   ├── run_gpu_host_2node.sh
│   ├── run_phone_rpc.sh
│   └── setup_tunnels.sh
├── docs/
│   └── ...
└── logs/
    └── ...
```

## 快速切换

```bash
# 查看完整实现
git checkout feat/3-machine-inference

# 回到 main
git checkout main
```

## 日志说明

`logs/` 下是从 `feat/3-machine-inference` 早期验证阶段迁移来的运行日志，按拓扑/参数/结果命名：

| 日志文件 | 产生脚本 | 拓扑与参数 | 结果 |
|---|---|---|---|
| `cpu_rpc_20260710_063630.log`<br>`cpu_rpc_20260710_065809.log` | `run_cpu_rpc_server.sh` | 当前机器 RPC Server，`172.26.88.148:50053` | Server 启动日志，含端口和缓存路径 |
| `pc_ngl20_20260709_184126.log`<br>`pc_ngl20_20260709_184654.log`<br>`pc_ngl20_20260709_190056.log` | `run_gpu_host.sh` | GPU PC 三机 Host，直连 `192.168.1.10:50053,192.168.1.7:50052`，`ngl=20`，DEBUG | 两台 Worker 均无法连接 |
| `pc_2node_ngl20_20260709_190725.log`<br>`pc_2node_ngl20_20260709_190959.log` | `run_gpu_host_2node.sh` | GPU PC + 手机双机 Host，直连 `192.168.1.7:50052`，`ngl=20`，DEBUG | 手机离线，连接失败 |
| `pc_current_ngl20_20260709_191428.log` | `run_gpu_host.sh` | GPU PC + 当前机器（直连） | 因 WSL2 NAT 入站问题导致 RPC 崩溃 |
| `pc_current_tun_ngl20_20260709_192609.log`<br>`pc_current_final_ngl20_20260709_194929.log` | `run_gpu_host.sh` | GPU PC + 当前机器，SSH 反向隧道 `127.0.0.1:50053`，`ngl=20` | 隧道成功，eval 约 8.55–8.82 t/s |
| `pc_3node_tun_ngl20_20260709_193358.log`<br>`pc_3node_tun_ngl20_debug_20260709_193614.log`<br>`pc_3node_tun_ngl999_20260709_193753.log`<br>`pc_3node_tun_nocache_ngl999_20260709_194545.log` | `run_gpu_host.sh` | GPU PC + 当前机器 + 手机，隧道模式，`ngl=20/999`，部分带 `-nocache` | 手机 `127.0.0.1:50052` 连接失败，降级为 GPU PC + 当前机器双机运行 |
| `pc_local_ngl999_20260709_194021.log` | 直接运行 `llama-completion` | GPU PC 本地 CUDA 基线，`ngl=999` | load 194 ms，eval 282.63 t/s |

> 所有日志都通过 `ts-log.sh` 加了 wall-clock 时间戳。详细分析和复现步骤见 `feat/3-machine-inference` 分支。

---

## 最新验证：Qwen3-1.7B GPU + WSL RPC（2026-07-15）

本次通宵基准在 `feat/3-machine-inference` 分支验证完成后，已整理到 `main` 的 `3-machine/` 目录。

### 环境

| 节点 | 角色 | 后端 | 地址/说明 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 / RTX 4050 6GB | `192.168.1.10` |
| 当前 WSL | RPC Worker | CPU | `127.0.0.1:50053`（SSH 反向隧道） |
| 手机 | 未参与 | — | 本次只验证 GPU PC + WSL 双机 |

### 模型

- **来源**：Ollama `qwen3:1.7b`
- **实际量化**：Q4_K_M
- **约 2.0B 参数**
- 已链接到 GPU PC `~/models/qwen3-1.7b-instruct-ollama.gguf`

### 性能结果

命令：`llama-completion -m <model> -p "你好" -n 32 -no-cnv -ngl N [--rpc 127.0.0.1:50053]`

#### GPU PC 本地 CUDA

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0（纯 CPU） | 1920 ms | 39.81 t/s | [`logs/3machine_gpu_local_cuda_ngl0_20260714_142222.log`](logs/3machine_gpu_local_cuda_ngl0_20260714_142222.log) |
| 12 | 1350 ms | 65.82 t/s | [`logs/3machine_gpu_local_cuda_ngl12_20260714_142222.log`](logs/3machine_gpu_local_cuda_ngl12_20260714_142222.log) |
| 24 | 633 ms | 98.31 t/s | [`logs/3machine_gpu_local_cuda_ngl24_20260714_142222.log`](logs/3machine_gpu_local_cuda_ngl24_20260714_142222.log) |
| 99（全部 GPU） | 365 ms | **132.84 t/s** | [`logs/3machine_gpu_local_cuda_ngl99_20260714_142222.log`](logs/3machine_gpu_local_cuda_ngl99_20260714_142222.log) |

#### GPU PC + WSL RPC

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0（全部 RPC） | 1930 ms | **44.13 t/s** | [`logs/3machine_gpu_wsl_rpc_ngl0_20260714_142222.log`](logs/3machine_gpu_wsl_rpc_ngl0_20260714_142222.log) |
| 12 | 12147 ms | 18.80 t/s | [`logs/3machine_gpu_wsl_rpc_ngl12_20260714_142222.log`](logs/3machine_gpu_wsl_rpc_ngl12_20260714_142222.log) |
| 24 | 21987 ms | 16.46 t/s | [`logs/3machine_gpu_wsl_rpc_ngl24_20260714_142222.log`](logs/3machine_gpu_wsl_rpc_ngl24_20260714_142222.log) |
| 99 | 25360 ms | 21.60 t/s | [`logs/3machine_gpu_wsl_rpc_ngl99_20260714_142222.log`](logs/3machine_gpu_wsl_rpc_ngl99_20260714_142222.log) |

> prompt 只有 `"你好"` 1 个 token，因此 prompt eval 时间为 0，速度显示为 `inf`。

### GPU 功耗与显存占用

采样方式：`nvidia-smi --query-gpu=power.draw,memory.used,utilization.gpu,temperature.gpu --format=csv -l 1`

| 配置 | 平均功耗 | 平均显存 | 平均利用率 | 平均温度 | CSV |
|---|---|---|---|---|---|
| 3machine_gpu_local_cuda_ngl0_20260714_142222 | 11.7 W | 206 MiB | 0.0 % | 41.2 °C | [`logs/3machine_gpu_local_cuda_ngl0_20260714_142222_gpu.csv`](logs/3machine_gpu_local_cuda_ngl0_20260714_142222_gpu.csv) |
| 3machine_gpu_local_cuda_ngl12_20260714_142222 | 16.3 W | 1154 MiB | 3.7 % | 42.7 °C | [`logs/3machine_gpu_local_cuda_ngl12_20260714_142222_gpu.csv`](logs/3machine_gpu_local_cuda_ngl12_20260714_142222_gpu.csv) |
| 3machine_gpu_local_cuda_ngl24_20260714_142222 | 17.8 W | 530 MiB | 0.0 % | 43.0 °C | [`logs/3machine_gpu_local_cuda_ngl24_20260714_142222_gpu.csv`](logs/3machine_gpu_local_cuda_ngl24_20260714_142222_gpu.csv) |
| 3machine_gpu_local_cuda_ngl99_20260714_142222 | 25.7 W | 2377 MiB | 0.0 % | 44.0 °C | [`logs/3machine_gpu_local_cuda_ngl99_20260714_142222_gpu.csv`](logs/3machine_gpu_local_cuda_ngl99_20260714_142222_gpu.csv) |
| 3machine_gpu_wsl_rpc_ngl0_20260714_142222 | 22.8 W | 206 MiB | 0.0 % | 45.0 °C | [`logs/3machine_gpu_wsl_rpc_ngl0_20260714_142222_gpu.csv`](logs/3machine_gpu_wsl_rpc_ngl0_20260714_142222_gpu.csv) |
| 3machine_gpu_wsl_rpc_ngl12_20260714_142222 | 16.1 W | 453 MiB | 0.3 % | 45.1 °C | [`logs/3machine_gpu_wsl_rpc_ngl12_20260714_142222_gpu.csv`](logs/3machine_gpu_wsl_rpc_ngl12_20260714_142222_gpu.csv) |
| 3machine_gpu_wsl_rpc_ngl24_20260714_142222 | 16.1 W | 603 MiB | 0.3 % | 45.9 °C | [`logs/3machine_gpu_wsl_rpc_ngl24_20260714_142222_gpu.csv`](logs/3machine_gpu_wsl_rpc_ngl24_20260714_142222_gpu.csv) |
| 3machine_gpu_wsl_rpc_ngl99_20260714_142222 | 15.1 W | 620 MiB | 0.9 % | 46.4 °C | [`logs/3machine_gpu_wsl_rpc_ngl99_20260714_142222_gpu.csv`](logs/3machine_gpu_wsl_rpc_ngl99_20260714_142222_gpu.csv) |

### 关键发现

1. **RTX 4050 6GB 可以轻松跑 Qwen3-1.7B Q4_K_M**：本地 `-ngl 99` 达到 **132.84 t/s**，显存占用约 2.4 GB。
2. **`-ngl` 在纯 CUDA 场景下单调加速**：ngl 0 → 12 → 24 → 99，速度从 39.81 提升到 132.84 t/s。
3. **RPC 混合场景的 `-ngl` 行为非单调**：
   - `ngl=0` 时速度最快（44.13 t/s），scheduler 把全部层放到 WSL CPU。
   - `ngl=12/24` 时加载时间暴增到 12–22 s，速度下降到 16–18 t/s，WSL 网络 RTT（~90 ms）成为瓶颈。
   - `ngl=99` 时速度回升到 21.60 t/s，scheduler 把计算拉回本地 GPU。
4. **RPC 初始化开销显著**：连接 WSL Worker 后，1.7B 模型加载时间从本地 365 ms 上升到 12–25 s。
5. **WSL 反向隧道稳定**：通宵运行中 RPC Server 与反向隧道保持存活，链路可复现。

### 新增产物

| 文件 | 说明 |
|---|---|
| [`config.env`](config.env) | 三机拓扑配置（本次双机使用其中 GPU PC + 当前机器部分） |
| [`scripts/overnight_gpu_benchmark.sh`](scripts/overnight_gpu_benchmark.sh) | 通宵自动基准脚本：拉模型、跑本地/RPC 多组 `-ngl`、记录 nvidia-smi、生成汇总 |
| [`logs/3machine_summary_20260714_142403.txt`](logs/3machine_summary_20260714_142403.txt) | 自动生成的文本汇总 |
| `logs/3machine_gpu_*_ngl{0,12,24,99}_20260714_142222.log` | 推理日志 |
| `logs/3machine_gpu_*_ngl*_20260714_142222_gpu.csv` | 功耗/显存/利用率/温度采样 |

---

## 合入状态

- `feat/3-machine-inference` 分支的验证结果、脚本与文档已合并到 `main` 的 `3-machine/`。
- `3-machine/scripts/` 现已包含手机端 `run_phone_rpc.sh`、`run_phone_baseline.sh` 与 PC 端 `run_pc_rpc.sh`，完整三机链路可在 main 上直接复现。
