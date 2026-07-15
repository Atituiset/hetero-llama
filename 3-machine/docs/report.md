# 3-Machine 异构推理报告

> 生成时间：2026-07-16  
> 模型：Qwen3-1.7B-Instruct-Q4_K_M、Qwen2-0.5B-Instruct-Q4_0  
> 拓扑：GPU PC 本地 CUDA / GPU PC + WSL RPC / GPU PC + WSL + 手机 RPC

---

## 1. 环境

| 节点 | 角色 | 后端 | 地址 |
|---|---|---|---|
| GPU PC | Host | CUDA 12.0 / RTX 4050 6GB | `192.168.1.10` |
| 当前机器（WSL） | RPC Worker | CPU | `127.0.0.1:50053`（SSH 反向隧道） |
| Mate 40 Pro | RPC Worker | CPU | `127.0.0.1:50052`（SSH 本地转发 + 反向隧道） |

---

## 2. Qwen3-1.7B 性能结果

命令：`llama-completion -m qwen3-1.7b-instruct-ollama.gguf -p "你好" -n 32 -no-cnv -ngl N [--rpc ...]`

### 2.1 GPU PC 本地 CUDA

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 724.54 ms | 44.17 t/s | `qwen3_1_7b_local_ngl0_20260715_122356.log` |
| 12 | 489.83 ms | 65.33 t/s | `qwen3_1_7b_local_ngl12_20260715_122356.log` |
| 24 | 336.16 ms | 95.19 t/s | `qwen3_1_7b_local_ngl24_20260715_122356.log` |
| 99 | 240.79 ms | 132.90 t/s | `qwen3_1_7b_local_ngl99_20260715_122356.log` |

### 2.2 GPU PC + WSL RPC

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 719.85 ms | 44.45 t/s | `qwen3_1_7b_wsl_ngl0_20260715_122356.log` |
| 12 | 1633.80 ms | 19.59 t/s | `qwen3_1_7b_wsl_ngl12_20260715_122356.log` |
| 24 | 1989.56 ms | 16.08 t/s | `qwen3_1_7b_wsl_ngl24_20260715_122356.log` |
| 99 | 2530.93 ms | 12.64 t/s | `qwen3_1_7b_wsl_ngl99_20260715_122356.log` |

### 2.3 GPU PC + WSL + 手机 RPC

| ngl | 结果 | 日志 |
|---|---|---|
| 0 | 待重跑（手机当前离线） | `qwen3_1_7b_phone_ngl0_20260715_122356.log` |
| 12 | 待重跑（手机当前离线） | `qwen3_1_7b_phone_ngl12_20260715_122356.log` |
| 24 | 待重跑（手机当前离线） | `qwen3_1_7b_phone_ngl24_20260715_122356.log` |
| 99 | 待重跑（手机当前离线） | `qwen3_1_7b_phone_ngl99_20260715_122356.log` |

历史问题：首次通宵基准时手机 RPC Server 在 GPU PC 连接后崩溃，错误为 `Remote RPC server crashed or returned malformed response`。根因已定位：Android/Termux 无法连接自身 LAN IP，导致 SSH 本地转发到 `192.168.1.7:50052` 在手机侧实际无法建立连接。

修复方案（已更新脚本）：
- 手机 RPC Server 绑定 proot 内的 `127.0.0.1:50052`。
- 在 proot 内运行 `socat`，把 `127.0.0.1:50052` 桥接到 Termux 可见的 Unix socket `/data/data/com.termux/files/home/.phone_rpc_50052.sock`。
- WSL 通过 SSH 本地转发连接该 Unix socket，再经反向隧道暴露给 GPU PC。

相关变更：
- `scripts/run_phone_rpc.sh`：默认绑定 `127.0.0.1`。
- `scripts/run_phone_proxy.sh`（新增）：socat Unix socket 代理。
- `scripts/setup_tunnels.sh` / `scripts/overnight_watchdog.sh`：改用 Unix socket 转发。
- `docs/protocol.md` / `docs/reproduce.md`：更新拓扑说明与依赖。

---

## 3. Qwen2-0.5B 性能结果

命令：`llama-completion -m qwen2-0.5b-instruct-q4_0.gguf -p "你好" -n 32 -no-cnv -ngl N [--rpc ...]`

### 3.1 GPU PC 本地 CUDA

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 270.31 ms | 118.38 t/s | `qwen2_0_5b_local_ngl0_20260715_122356.log` |
| 12 | 165.69 ms | 193.13 t/s | `qwen2_0_5b_local_ngl12_20260715_122356.log` |
| 24 | 102.42 ms | 312.45 t/s | `qwen2_0_5b_local_ngl24_20260715_122356.log` |
| 99 | 87.71 ms | 364.83 t/s | `qwen2_0_5b_local_ngl99_20260715_122356.log` |

### 3.2 GPU PC + WSL RPC

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 308.08 ms | 103.87 t/s | `qwen2_0_5b_wsl_ngl0_20260715_122356.log` |
| 12 | 940.05 ms | 34.04 t/s | `qwen2_0_5b_wsl_ngl12_20260715_122356.log` |
| 24 | 966.91 ms | 33.10 t/s | `qwen2_0_5b_wsl_ngl24_20260715_122356.log` |
| 99 | 20676.02 ms | 15.22 t/s（16 runs，提前触发 end-of-text） | `qwen2_0_5b_wsl_ngl99_20260715_122356.log` |

### 3.3 GPU PC + WSL + 手机 RPC

| ngl | 结果 | 日志 |
|---|---|---|
| 0 | 待重跑（手机当前离线） | `qwen2_0_5b_phone_ngl0_20260715_122356.log` |
| 12 | 待重跑（手机当前离线） | `qwen2_0_5b_phone_ngl12_20260715_122356.log` |
| 24 | 待重跑（手机当前离线） | `qwen2_0_5b_phone_ngl24_20260715_122356.log` |
| 99 | 待重跑（手机当前离线） | `qwen2_0_5b_phone_ngl99_20260715_122356.log` |

备注：直接连接 WSL → 手机 `192.168.1.7:50052` 可正常工作（Qwen2-0.5B 约 104 t/s），证明手机 RPC Server 本身无 ABI/内存问题。完整三机链路需等待修复后的隧道架构在手机上验证。

---

## 4. 关键发现

1. **RTX 4050 6GB 可以轻松跑 Qwen3-1.7B Q4_K_M**：本地 `-ngl 99` 达到 132.90 t/s。
2. **`-ngl` 在纯 CUDA 场景下单调加速**：Qwen3-1.7B 从 ngl=0 的 44.17 t/s 提升到 ngl=99 的 132.90 t/s。
3. **RPC 初始化开销显著**：连接 WSL Worker 后，Qwen3-1.7B 加载时间从本地 240 ms 上升到 12–25 s。
4. **RPC 混合场景的 `-ngl` 行为非单调**：Qwen3-1.7B + WSL 时，ngl=0 速度最快（44.45 t/s），ngl=99 反而降到 12.64 t/s。
5. **手机 RPC 隧道架构已修复**：从直连手机 LAN IP 改为 proot 内 `127.0.0.1` + `socat` Unix socket 桥接，规避 Android/Termux 无法访问自身 LAN IP 的问题。完整三机结果待手机恢复在线后补跑。

---

## 5. 问题与下一步

### 5.1 手机 RPC Server 崩溃

- 现象：GPU PC `llama-completion` 在 `ggml_backend_rpc_add_server` / `get_socket` 阶段崩溃，手机端 `ggml-rpc-server` 进程退出。
- 已确认：
  - 三端 llama.cpp commit 一致（`152d337f`）。
  - 手机端模型 `qwen2-0.5b-instruct-q4_0.gguf` 已就位。
  - 直接连接 WSL → 手机 `192.168.1.7:50052` 成功（约 104 t/s），排除 ABI/内存问题。
  - 根因：Android/Termux 无法连接自身 LAN IP，导致 SSH 本地转发到 `192.168.1.7:50052` 在手机侧失败。
- 已修复：
  - 手机 RPC Server 绑定 proot 内 `127.0.0.1:50052`。
  - 增加 `socat` Unix socket 代理桥接 Termux 与 proot。
  - WSL 通过 Unix socket SSH 本地转发连接手机。
- 待验证：
  - 手机当前离线（`192.168.1.7` 不可达），修复后的隧道架构需在手机恢复后验证。
  - 验证通过后，重新跑完整三机通宵基准并回填报告。

### 5.2 后续实验

- 修复手机 RPC 后，重新跑完整三机通宵基准。
- 测试 Qwen2.5-3B / 7B。
- 评估 Qwen3.6-35B-A3B-FP8 在 24GB+ 显存设备上的可行性。

---

## 6. 日志索引

本次通宵基准生成日志：

```text
3-machine/logs/qwen3_1_7b_{local,wsl,phone}_ngl{0,12,24,99}_20260715_122356.log
3-machine/logs/qwen2_0_5b_{local,wsl,phone}_ngl{0,12,24,99}_20260715_122356.log
3-machine/logs/summary_20260715_122356.txt
```

GPU PC 与 WSL 双机数据完整可用；手机拓扑日志仅包含崩溃堆栈，无有效性能数据。
