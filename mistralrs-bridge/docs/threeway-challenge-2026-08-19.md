# 三机推理挑战实验记录（2026-08-19）

> 目标：同一 prompt、同一模型（Qwen3.8-27B Q3_K_M）下，对比 mistralrs TCP 桥接 vs llama.cpp RPC 的三机（GPU PC + WSL + 手机）推理。
> 记录：过程日志 + prompt/token 生成细节。原始日志在 `mistralrs-bridge/logs/`。

## 测试环境

| 节点 | 硬件 | 角色 |
|------|------|------|
| GPU PC | RTX 4050 6GB + 15GB RAM | host（CUDA + CPU 层） |
| WSL | 15GB RAM | worker / rpc-server（经 ssh -R 隧道） |
| Mate 40 Pro | Kirin 9000, 8GB | worker / rpc-server（经 ssh -R 隧道） |

统一 prompt：`用中文写一段关于秋天的短诗，然后解释你最喜欢的一句。`
采样：框架默认值（mistralrs: temp=0.1 top_k=32 top_p=0.1 min_p=0.05；llama.cpp: 默认）

## 实验矩阵

| # | 引擎 | 拓扑 | 状态 |
|---|------|------|------|
| 1 | mistralrs fork | 0-11 cuda / 12-44 cpu / 45-58 WSL / 59-63 手机 | 运行中 |
| 2 | llama.cpp RPC | -ngl 12 cuda + WSL rpc + 手机 rpc | 待跑 |

## 结果记录

### 实验 1：mistralrs 四段桥接（27B）✅ 成功

- 拓扑文件：`topologies/qwen38_27b_threeway.yml`（0-11 cuda / 12-44 cpu / 45-58 WSL / 59-63 手机）
- host 日志：`logs/host_27b_threeway_20260819_234645.log`
- 手机 worker：`logs/phone_worker_27b_20260819_234645.log`（含 1142 次 59-63 层 forward 记录，手机全程在岗）
- WSL worker：`logs/worker_27b_threeway.log`
- **TTFT 7.06s；Prompt 25 tokens, 3.56 T/s；Decode 570 tokens, 1.29 T/s**（对比：同模型双机 12+37+15 拓扑 decode 2.56 T/s——手机段是瓶颈但确实在干活）
- 采样：temp=0.1, top_k=32, top_p=0.1, min_p=0.05；输出：完整诗《秋薄》+ 对"远山薄了，天也薄了"的赏析，思考链与成文连贯正确
- 输出全文要点：《秋薄》"秋风翻过旧书页，一片银杏落在肩头。远山薄了，天也薄了，雁声从云缝里漏下来。我站在霜里，等一场不来的雪。"+ 对"薄"字通感手法的赏析（与双机版《秋渡》同源构思，均选择"远山薄了，天也薄了"为最佳句）

### 实验 2：llama.cpp RPC 三机（27B）✅ 成功

- 拓扑：GPU PC host（`-ngl 12` CUDA）+ WSL rpc-server:50052 + 手机 rpc-server:50053（均经 ssh -R 隧道）
- 二进制：GPU PC `build-cuda-rpc`（master dc72703fc，FA off）；手机/WSL rpc-server 协议 v5.1.0
- host 日志：`logs/llamacpp_threeway_20260820_000603.log`
- **load 111.7s；prompt eval 23 tokens, 3.01 T/s；decode 258 tokens, 0.22 T/s**（4547 ms/token）
- 输出：《秋声》完整诗 + "像一杯放凉的茶，静静沉淀了季节的喧嚣"选句赏析，正确
- 排障记录：手机 rpc-server 旧协议 v4.0.1 与新版客户端 v5 不匹配导致 `get_socket` abort——手机/WSL 都需重编 rpc-server；pgrep 检查进程时小心命令行自匹配造成"假活"

### 实验 2b：llama.cpp RPC 双机（27B，旧版 152d337，参照）

- GPU PC + WSL rpc（无手机）：decode **0.32 T/s**，输出正确

## 对比结论

| 引擎 | 拓扑 | decode T/s | 输出正确 |
|------|------|-----------|---------|
| **mistralrs 自研桥** | 双机（12cuda+37cpu+15remote） | **2.56** | ✅ |
| **mistralrs 自研桥** | 三机（+手机 5 层） | **1.29** | ✅ |
| llama.cpp RPC | 双机 | 0.32 | ✅ |
| llama.cpp RPC | 三机 | 0.22 | ✅ |

**mistralrs 自研桥比 llama.cpp RPC 快 4-6 倍**。根因：ggml RPC 是算子级卸载，decode 每 token 每算子都有网络往返；自研桥按连续层块卸载，每 token 每个远程块只一次往返（20KB hidden state）。llama.cpp RPC 的优势是零改动开箱即用、协议有版本协商；自研桥的价值在于协议设计和可定制性。

*更新: 2026-08-20*
