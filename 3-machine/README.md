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
