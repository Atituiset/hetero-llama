# 3-Machine 异构推理报告（模板）

> **本报告为模板：完整三机（GPU PC + WSL + 手机）数据待通宵基准完成后填充。**

> 生成时间：2026-07-15  
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
| 0 | 1920 ms | 39.81 t/s | `3machine_gpu_local_cuda_ngl0_20260714_142222.log` |
| 12 | 1350 ms | 65.82 t/s | `3machine_gpu_local_cuda_ngl12_20260714_142222.log` |
| 24 | 633 ms | 98.31 t/s | `3machine_gpu_local_cuda_ngl24_20260714_142222.log` |
| 99 | 365 ms | 132.84 t/s | `3machine_gpu_local_cuda_ngl99_20260714_142222.log` |

### 2.2 GPU PC + WSL RPC

| ngl | load time | generation | 日志 |
|---|---|---|---|
| 0 | 1930 ms | 44.13 t/s | `3machine_gpu_wsl_rpc_ngl0_20260714_142222.log` |
| 12 | 12147 ms | 18.80 t/s | `3machine_gpu_wsl_rpc_ngl12_20260714_142222.log` |
| 24 | 21987 ms | 16.46 t/s | `3machine_gpu_wsl_rpc_ngl24_20260714_142222.log` |
| 99 | 25360 ms | 21.60 t/s | `3machine_gpu_wsl_rpc_ngl99_20260714_142222.log` |

### 2.3 GPU PC + WSL + 手机 RPC（待跑）

新通宵基准完成后填充。

---

## 3. Qwen2-0.5B 性能结果（待跑）

新通宵基准完成后填充。

---

## 4. 关键发现

1. RTX 4050 6GB 可以轻松跑 Qwen3-1.7B Q4_K_M；本地 `-ngl 99` 达到 132.84 t/s。
2. RPC 初始化开销显著：连接 WSL Worker 后，Qwen3-1.7B 加载时间从本地 365 ms 上升到 12–25 s。
3. `-ngl` 在纯 CUDA 场景下单调加速，在 RPC 混合场景下非单调。
4. 手机参与后的完整三机数据待补充。

---

## 5. 下一步

- 填充完整三机（GPU PC + WSL + 手机）的 Qwen3-1.7B 与 Qwen2-0.5B 数据。
- 测试 Qwen2.5-3B / 7B。
- 评估 Qwen3.6-35B-A3B-FP8 在 24GB+ 显存设备上的可行性。
