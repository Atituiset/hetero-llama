# 3-Machine 异构推理模式

GPU PC（CUDA Host）+ 当前机器（WSL CPU RPC Worker）+ 华为 Mate 40 Pro（手机 CPU RPC Worker）三机 RPC 异构推理。

---

## 状态

- `3-machine/` 已在 `main` 分支可用。
- 支持完整三机拓扑、双机拓扑（GPU PC + WSL / GPU PC + 手机）、以及 GPU PC 本地 CUDA 基线。
- 包含配置驱动的通宵基准脚本与 watchdog，支持断点续跑。

---

## 目录结构

```text
3-machine/
├── README.md                          # 本文件
├── config.env                         # 三机地址与构建路径
├── config/
│   └── benchmark-matrix.env           # 通宵基准矩阵配置
├── scripts/
│   ├── overnight_gpu_benchmark.sh     # 通宵自动基准
│   ├── overnight_watchdog.sh          # 通宵 watchdog
│   ├── setup_tunnels.sh               # SSH 隧道启动
│   ├── run_cpu_rpc_server.sh          # 当前机器 RPC Server
│   ├── run_gpu_host.sh                # GPU PC 三机 Host
│   ├── run_gpu_host_2node.sh          # GPU PC 双机 Host（仅手机）
│   ├── run_phone_rpc.sh               # 手机 RPC Server
│   ├── run_phone_baseline.sh          # 手机本地 CPU 推理
│   └── run_pc_rpc.sh                  # PC 端 RPC 推理
├── docs/
│   ├── protocol.md                    # 通信协议 v0.3
│   ├── reproduce.md                   # 三机复现手册
│   ├── report.md                      # 最新报告
│   └── historical/                    # 归档的旧文档
└── logs/                              # 运行日志
```

---

## 快速开始

```bash
cd 3-machine

# 1. 确保 config.env 中的地址与构建路径正确
# 2. 在当前机器启动 SSH 隧道（会同时拉起 WSL RPC Server 和手机 RPC Server）
./scripts/setup_tunnels.sh

# 3. 在 GPU PC 启动通宵基准
ssh atituiset@192.168.1.10
cd ~/projects/gpu-cpu-phone-test/3-machine
tmux new -d -s gpu_bench './scripts/overnight_gpu_benchmark.sh'

# 4. 回到当前机器启动 watchdog
./scripts/overnight_watchdog.sh --loop
```

---

## 日志说明

### 早期调试（2026-07-09/10，Qwen2-0.5B）

| 日志文件 | 拓扑 | 说明 |
|---|---|---|
| `cpu_rpc_20260710_*.log` | 当前机器 RPC Server | 启动日志 |
| `pc_ngl20_20260709_*.log` | GPU PC + 当前机器/手机直连 | 连接失败或 NAT 问题 |
| `pc_current_tun_ngl20_20260709_*.log` | GPU PC + 当前机器（隧道） | 成功，约 8.5 t/s |
| `pc_3node_tun_ngl20_20260709_*.log` | GPU PC + 当前机器 + 手机（隧道） | 手机离线，降级双机 |
| `pc_local_ngl999_20260709_*.log` | GPU PC 本地 CUDA | 基线 282 t/s |

详见 `docs/historical/report-20260710-qwen2-0.5b.md`。

### Qwen3-1.7B 双机通宵基准（2026-07-14）

| 配置 | 最快 generation | 日志 |
|---|---|---|
| GPU PC 本地 CUDA `-ngl 99` | 132.84 t/s | `3machine_gpu_local_cuda_ngl99_20260714_142222.log` |
| GPU PC + WSL RPC `-ngl 0` | 44.13 t/s | `3machine_gpu_wsl_rpc_ngl0_20260714_142222.log` |

详见 `docs/report.md`。

### 最新通宵基准（2026-07-15 起）

运行后生成命名统一的日志：

```text
<model_alias>_<topology>_ngl<ngl>_<timestamp>.log
```

例如：`qwen3_1_7b_phone_ngl24_20260715_020000.log`。

---

## 通宵 watchdog 用法

```bash
# 单次健康检查（手动）
./scripts/overnight_watchdog.sh

# 后台循环守护（推荐）
nohup ./scripts/overnight_watchdog.sh --loop > logs/overnight_watchdog.log 2>&1 &
```

功能：
1. 检查并恢复本地 tmux 会话 `rpc_server` 和 `reverse_tunnel`。
2. 若矩阵声明 `phone`，检查并恢复手机 SSH 链路、`phone_tunnel` 本地转发、手机 RPC Server。
3. 通过 SSH 检查 GPU PC 上的 `gpu_bench` 会话，掉线则重启。
4. 状态追加到 `~/.claude/hetero_overnight_status.md`。
5. 检测到 GPU PC 上生成 `summary_*.txt` 后自动退出 `--loop`。

---

## 关键设计

- **配置驱动**：模型、拓扑、ngl 列表全部在 `config/benchmark-matrix.env` 中声明。
- **断点续跑**：`overnight_gpu_benchmark.sh` 会跳过已有非空日志的组合，可通过 `FORCE_RERUN=1` 强制重跑。
- **拓扑按需启用**：矩阵里不写 `phone` 时，watchdog 不会尝试监控手机链路。

---

## 相关文档

- 复现手册：`docs/reproduce.md`
- 协议：`docs/protocol.md`
- 报告：`docs/report.md`
- 旧文档：`docs/historical/`
