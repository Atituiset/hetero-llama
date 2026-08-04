# 异构推理实验深度分析与探索方向

> 生成时间：2026-08-04
> 范围：本仓库从 2026-07-07 至今的异构推理实验全貌（llama.cpp RPC 双机/三机、手机 GPU 尝试、mistral.rs TCP 桥接）
> 依据：仓库全部文档 + mistral.rs / llama.cpp 源码交叉核对 + 原始日志逐条回查

---

## 0. TL;DR

这个实验的起点是"异构推理是否等价于搬运 tensor、TPU 算出的 KV cache 能否直接喂给 GPU decode"（见 [`docs/notes/`](./notes/异构的推理服务是在玩tensor的矩阵转换的游戏吗-比如我在tpu上计算出来的kv-cache可以给-de7f8e62.md)）。近一个月的所有工作，把这个问题从**想象层**拉到了**工程层**，最终验证出的答案是：

- 跨设备/跨机协同推理传输的是**层间隐状态（hidden state）**，不是 KV cache；KV cache 留在算它的节点本地。
- 分层推理的价值在**容量与形态**（模型放不下、弱端参与），不在速度——decode 的同步关键路径决定了 RPC 一定比单机慢。
- 手机 Mali-G78 的 LLM GPU 路径（llama.cpp / MNN / ncnn）目前全部不可实用化，手机唯一可用路径是 CPU。
- 自己 fork 的 mistral.rs 桥接实现了任意层区间 + 每节点分片加载，但 35B 端到端尚未跑通，SSM 层未做数值验证。

---

## 1. 实验演进路线

| 阶段 | 时间 | 内容 | 结论 |
|------|------|------|------|
| 1. 双机 RPC | 07-07 ~ 07-08 | PC CPU + Mate 40 Pro，llama.cpp RPC 分层 | ✅ 链路跑通；`-ngl` 确实控制手机参与层数；性能被 RPC 大幅拖慢 |
| 2. 三机 RPC | 07-09 ~ 07-16 | GPU PC(CUDA) + WSL + 手机，SSH 隧道组网 + 通宵基准 | ✅ GPU+WSL 数据完整；手机链路因 Android 网络问题反复失败，最终隧道架构已修复但未重跑 |
| 3. 手机 GPU | 07-10 ~ 07-13 | llama.cpp Vulkan/OpenCL、MNN、ncnn / ncnn_llm | ❌ 全部失败或显著慢于 CPU（详见第 5 节） |
| 4. mistral.rs 桥接 | 07-24 ~ 07-28 | fork mistral.rs 实现 TCP 层卸载 + Qwen3.6 SSM（Gated DeltaNet） | ⚠️ Qwen2-0.5B 跨机验证通过；Qwen3.6-35B-A3B 端到端未完成 |

阶段 4 是技术上最有分量的部分：不再使用 llama.cpp 现成 RPC，而是自己动手在 mistral.rs 里实现了跨机分层推理（16 个 commit + 一批未提交改动）。

---

## 2. 两条技术主线的机制拆解

### 2.1 llama.cpp RPC：层级卸载，KV 从不跨设备

依据 [`llama.cpp/ggml/src/ggml-rpc/ggml-rpc.cpp`](../../llama.cpp/ggml/src/ggml-rpc/ggml-rpc.cpp) 与 [`llama.cpp/src/llama-model.cpp`](../../llama.cpp/src/llama-model.cpp) 源码核对：

1. **`-ngl` 的语义是"最后 N 层 offload"**（`llama-model.cpp` 中 `i_gpu_start = n_layer+1-ngl`）：embedding 输入层永远留在 CPU；`-ngl 4` 是远端跑最后 4 层，`-ngl 99` 是除 embedding 外全部上远端。与日志中手机端 graph 节点数 108（`-ngl 4`）vs 821（`-ngl 99`）完全吻合。
2. **每 token 的线上流量已压到最小**：
   - 权重 >10MB 时用 FNV-1a hash 一次性传输并落盘缓存到服务器端（对应手机上的 `/root/.cache/llama.cpp/rpc/`）；
   - decode 阶段 graph 结构通过 `cgraph->uid` 复用，只发一条几字节的 `GRAPH_RECOMPUTE`；
   - 真正每次过网的只有**边界隐状态**（batch×hidden 的小张量）+ 激活 + 取回的 logits。
3. **KV cache 留在算它的节点上**：RPC 张量通过 `remote_ptr` 引用服务器端已分配的 buffer，服务器在自己的内存里续写 KV。这就是 [`main/docs/protocol.md`](../main/docs/protocol.md) 中"KV Cache 不跨设备传输"约定的实现。

### 2.2 mistral.rs 桥接：任意层区间 + 每节点只持有一片层

依据 [`mistral.rs/mistralrs-core/src/device_map/remote.rs`](../../mistral.rs/mistralrs-core/src/device_map/remote.rs) 与 [`mistral.rs/mistralrs-cli/src/remote_worker.rs`](../../mistral.rs/mistralrs-cli/src/remote_worker.rs)：

- **连续远端块合并**：同一地址的连续层合并成一个块，只在该块第一层触发一次 TCP 往返，块内靠 forward loop 语义透传（`last_remote_block` 原子变量跟踪），避免逐层 roundtrip。
- **past_kv 传播**：`DeviceMapper::set_past_kv()` 把 KV 位置传给远端 worker，保证 RoPE 位置正确——跨进程/跨机协议必须显式处理，而 llama.cpp RPC 不需要。
- **协议**：`[1B cmd][4B start][4B end][4B past_kv][4B reserved][8B len][payload]`，张量序列化为 `[8B n_elem][8B ndims][dims][f32 data]`，强制 CPU F32 以保证跨设备兼容。
- **未提交的 `RangeLimitedMapper`**（`mistral.rs` 工作区 diff）：让 worker 通过 `--layers start-end` **只加载自己的那一段层**，host 也不再需要全模型。这是"6GB GPU + 15GB CPU 合起来跑 16GB 模型"的关键机制——前 16 个 commit 中 worker 仍加载全量模型，内存放不下 35B。

---

## 3. 验证数据汇总（已回查原始日志）

### 3.1 双机 RPC（Qwen2-0.5B，PC CPU + 手机 CPU，07-08 非 DEBUG）

来源：`main/logs/pc_*_nodebug_*.log`

| 配置 | prompt eval | generation | 手机参与 |
|------|------------|-----------|---------|
| PC 本地 CPU | 380.78 t/s | 99.75 t/s | 0 层 |
| `-ngl 4` | 37.64 t/s | 7.59 t/s | 4 层（108 节点） |
| `-ngl 99` | 9.73 t/s | 3.36 t/s | 24 层（821 节点） |

手机本地基线约 7.1 t/s；`-ngl 99` 时线上开销叠加在手机算力之上，反而比手机本地还慢。

### 3.2 三机（GPU PC CUDA + WSL RPC，07-15 通宵基准）

来源：`3-machine/logs/qwen3_1_7b_*_20260715_122356.log` 与 `qwen2_0_5b_*_20260715_122356.log`

Qwen3-1.7B generation（t/s）：

| ngl | GPU 本地 | + WSL RPC |
|-----|---------|-----------|
| 0 | 44.17 | 44.45 |
| 12 | 65.33 | 19.59 |
| 24 | 95.19 | 16.08 |
| 99 | 132.90 | 12.64 |

Qwen2-0.5B generation（t/s）：

| ngl | GPU 本地 | + WSL RPC |
|-----|---------|-----------|
| 0 | 118.38 | 103.87 |
| 12 | 193.13 | 34.04 |
| 24 | 312.45 | 33.10 |
| 99 | 364.83 | 15.22（16 runs 提前触发 end-of-text） |

手机拓扑（`+WSL+手机`）全部为"待重跑"：手机 RPC Server 曾崩溃，根因是 Android/Termux 无法连接自身 LAN IP；修复方案（proot 内 `127.0.0.1` + socat Unix socket 桥接 + SSH 双隧道）已落地但未重跑。

### 3.3 手机 GPU 尝试

来源：[`docs/gpu-acceleration-summary.md`](./gpu-acceleration-summary.md)（数据与各模式日志一致）

| 框架/后端 | 结果 | 备注 |
|----------|------|------|
| llama.cpp Vulkan | ❌ 无法用 GPU | WSL 只有 llvmpipe；Mali 驱动仅 Vulkan 1.1，要求 1.2 |
| llama.cpp OpenCL | ❌ 手机被丢弃 | `unsupported GPU 'Mali-G78 r0p1'`（白名单只支持 Adreno/Intel）；WSL Intel 可用 56.3 t/s |
| MNN OpenCL | ❌ 慢 10~13 倍 | 0.5B 23s vs CPU 1.7s；1.5B 45.5s vs 4.7s；3B normal 直接 OOM，low 配置 85.6s |
| MNN Vulkan | ❌ 极慢 | 0.5B 跑 6m37s |
| ncnn_llm Vulkan | ❌ 首次推理卡住 | CPU 40.7s 可跑通 Qwen3-0.6B |
| ncnn Vulkan | ⚠️ 选择性加速 | vgg16 快 2.1 倍，但 vision_transformer 慢 25 倍 |

### 3.4 mistral.rs 桥接

| 测试项 | 状态 | 性能/说明 |
|--------|------|----------|
| Qwen2-0.5B 跨机桥接 | ✅ | 197 t/s prompt、46 t/s decode（仅记录于 session 报告，仓库无日志佐证） |
| TCP 协议 + RemoteConnectionPool | ✅ | — |
| Qwen3.6-35B-A3B GGUF 解析 | ✅ | 41 层、248320 vocab、16GB Q3_K_M |
| SSM 层加载（blk.0-2） | ✅ | — |
| SSM 层 forward | ⚠️ | 编译通过，未数值验证 |
| 35B 端到端 / 跨机桥接 / GPU 二进制重建 | 🚧 | 未完成（GPU PC OOM 崩溃中断；07-28 日志停在 "DType selected is F32"） |

---

## 4. 核心洞察

### 4.1 传输的是隐状态，不是 KV cache

实验完整验证了"层间 offload 传隐状态、KV 本地化"这条工业界主线：每次 decode 跨设备传输的数据量是 `batch × hidden_dim` 量级，而非与序列长度线性增长的 KV cache。这与最初"搬运 KV tensor"的想象有本质区别，也与 Gemini 笔记中"工业界做法是在通信边界上做文章"的判断一致。

### 4.2 RPC 慢的本质是"关键路径延迟"，不是带宽

decode 逐 token 串行，每个 token 必须等远端节点算完 + 一次 RTT：

```
T_token ≈ Σ(各设备计算时间) + (#边界穿越) × RTT
```

双机数据：本地 99.75 t/s → `-ngl 4` 7.59 t/s → `-ngl 99` 3.36 t/s。三机数据：本地 CUDA 随 ngl 单调升到 132.9 t/s，接 RPC 后 ngl 越高越慢（44.45 → 12.64）。即使远端算力为无穷大，RTT 依然是硬下限——所以 RPC 的价值在**容量**（跑不下的大模型、弱端参与），不在速度。

### 4.3 lm_head 的落点影响巨大

07-14 通宵日志（`3-machine/logs/3machine_summary_20260714_142403.txt`）中 Qwen3-1.7B + WSL RPC：`-ngl 24` 只有 16.46 t/s，`-ngl 99` 反而 21.60 t/s。原因：`-ngl 24` 时 lm_head 留在 host CPU，而 Qwen3 词表 15 万+，host 每 token 要算一遍巨大的输出投影；`-ngl 99` 把 lm_head 也 offload 给了 worker。对词表大的模型，输出层放哪比想象中更影响性能。

### 4.4 桥接协议的性能债

`serialize_tensor()` 强制 F32 CPU：8-bit 量化模型的权重在线上反而传 4 字节/元素的高精度激活。加上 `roundtrip`/`map` 中残留的 `eprintln!` debug 输出，35B 跑起来前应清掉。

### 4.5 什么时候跨机值得

- 模型单机放不下（6GB VRAM + 15GB RAM 跑 16GB 模型）→ 值得。
- 远端节点算得比本地快（GPU server 卸载 CPU 层）→ 值得，但仍受 RTT 限制。
- 远端节点更慢（手机 CPU 承接层）→ 只用于容量/形态验证，不要期待速度。

---

## 5. 手机 GPU 结论

Mali-G78 上所有 LLM GPU 路径都不可用，原因分三层：

| 层次 | 问题 | 涉及框架 |
|------|------|---------|
| 框架门槛 | OpenCL 白名单只认 Adreno/Intel；Vulkan 要求 1.2（Mali 只有 1.1） | llama.cpp |
| 算子层 | 能调用 GPU 但 LLM kernel 对 Mali 不友好；3B 直接 OOM | MNN |
| 架构退化 | Transformer 类算子极慢（vision_transformer 慢 25 倍） | ncnn |

手机当前唯一可用 LLM 路径：**CPU（MNN ARM82 / ncnn_llm CPU）**。

---

## 6. 工程与协作问题（跨 session 复盘）

| 类别 | 问题 | 解法/教训 |
|------|------|----------|
| 网络 | WSL2 默认 NAT 入站数据包被丢弃 | SSH 反向隧道；更优方案为 WSL `networkingMode=mirrored` |
| 网络 | Android/Termux 无法连接自身 LAN IP | 手机 RPC 绑定 proot 内 `127.0.0.1` + socat Unix socket 桥接 + SSH 双隧道 |
| 资源 | GPU PC 15GB RAM 编译 OOM 导致系统重启 | `CARGO_BUILD_JOBS=1` 单线程编译 |
| 会话 | 上下文窗口反复溢出（每 90 分钟 compaction） | 文档化状态续作（inbox/outbox/TODO）是有效的；避免单 session 堆 20 万 token |
| 协作 | 21 次自动模式拦截、38+ 次 SSH 失败、210+ 工具错误 | 通宵实验前应预检环境（SSH 免密、模型就位、编译完成） |

---

## 7. 当前状态盘点

### 未提交的代码改动（`mistral.rs` 工作区，07-28 之后）

11 个文件未 commit，核心是：

- `RangeLimitedMapper`（按层区间限制本地加载）+ `GGUFSpecificConfig.layer_range` 透传；
- `remote_worker` 支持 `--layers start-end` 分片加载；
- 所有 `GGUFSpecificConfig` 构造点补 `..Default::default()`。

这是 35B 跨机跑通的关键，但尚未提交。

### 未跟踪的运行日志（`mistralrs-bridge/logs/`，07-28）

| 日志 | 内容 | 结论 |
|------|------|------|
| `worker_qwen36_35b_*` | 加载到 "DType selected is F32" 处停止 | 模型加载/量化阶段中断，35B 端到端未完成 |
| `cpu_only_*IQ2_M*` | `unknown dtype for tensor 21` | candle 版本不支持 IQ2_M，需 Q3_K_M（bug #11 已记录但日志显示仍试了 IQ2_M） |
| `loopback_qwen2_0.5b_*` | `./target/release/mistralrs: No such file or directory` | 脚本 cwd 错误 |

### 文档卫生问题

- `docs/GPU_CPU_SPLIT_INFERENCE_REPORT.md` 与 `mistralrs-bridge/docs/report.md` 内容重复。
- `3-machine/docs/report.md` 中手机拓扑 4 个"待重跑"空位未回填。
- "Qwen2-0.5B 跨机 197/46 t/s" 只有 session 记录，仓库无日志佐证。

---

## 8. 未来探索点

### P0 — 收尾闭环（当前最该做的事）

1. **提交 `RangeLimitedMapper` 分片加载改动**，锁定"每节点只持有自己那一片层"的设计。
2. **SSM 数值验证**：WSL 纯 CPU 跑 Qwen3.6-35B 一段 prompt，再让 host+worker 分片跑同样 prompt，对比输出 logits 一致性（用逐 token 的 logprobs 或贪婪输出）。这是 35B 桥接的前置门槛——SSM 的 conv1d / gated delta 循环 / 状态矩阵跨机传递都未验证。
3. **桥接收尾**：清掉 `remote.rs` 中 `eprintln!` debug；线上 dtype 从 F32 降到模型精度（FP16/BF16）；`CARGO_BUILD_JOBS=1` 在 GPU PC 重建 CUDA 二进制。
4. **回填 3-machine 手机拓扑**：手机恢复在线后重跑完整三机通宵基准（隧道架构已就绪）。

### P1 — 性能工程

5. **每 token 时间分解剖析**：对 Qwen2-0.5B 桥接，分别测 RTT、远端计算、序列化/反序列化、host 侧等待，定位瓶颈占比。可加 `tc netem` 注入延迟，画出"速度 vs RTT"拐点曲线。
6. **流水线重叠（关键优化方向）**：decode 时 host 层与远端层串行等待，可以尝试异步双缓冲/分块流水——host 计算本层的同时，远端已在算上一批 token 的层（牺牲一点首 token 延迟换取稳定吞吐）。llama.cpp 与当前桥接都是同步阻塞，这是两者共同的优化空间。
7. **摊薄 RTT：批量采样 / speculative decoding**：一次往返产出多个 token（parallel sampling、speculative 草稿+验证），把固定 RTT 成本摊到多个 token 上。对高 RTT 的跨机场景收益最大。
8. **线上协议优化**：隐状态 FP16/BF16/INT8 传输（与模型量化对齐）；大 payload 分段/压缩；合并多个小张量为单次往返。

### P2 — 系统能力

9. **多机内存池 + 自动分层调度**：基于 `RangeLimitedMapper` 扩展到 3 节点（6GB GPU + 15GB CPU + 8GB 手机）跑 35B；写一个按"设备算力 + 网络带宽/延迟 + 层大小"估算最优切分点的脚本（mistral.rs 已有 `auto_device_map` 按内存贪心，可扩展为含网络代价的版本）。
10. **异构层感知调度**：Qwen3.6 的 30 个 SSM 层与 11 个 Attention 层计算特性差异大（SSM 纯 CPU 逐 token 串行是瓶颈），可以按层类型分配设备（如 SSM 层给 GPU、Attention 层给 CPU），而不是简单按层号切。
11. **前缀缓存 / PD 分离实验**：回到最初想象——prefill 节点产出 KV、decode 节点消费。llama.cpp RPC 的 KV 本地化与"KV 传输"是两种极端，可以实验中间态：prefix caching 跨机复用（如 SGLang radix attention 思路）或短 KV 传输的可行性。
12. **llama.cpp GPU RPC server**：llama.cpp 的 RPC server 本身可透传后端，尝试让 GPU PC 跑 CUDA RPC server、WSL/手机连它，与 mistral.rs 桥接做对比基准。

### P3 — 手机 GPU 重评估

13. 换 Adreno 手机测试（llama.cpp OpenCL 白名单内）；或等 Vulkan 1.2+ 驱动。
14. 接受 CPU 方案：手机作为纯 CPU 分片 worker 参与三机（容量场景），不再追求 Mali GPU。

### P4 — 工程质量

15. **协议版本化**：桥接线协议目前无版本字段，两端需同步改动；建议在 header 加 magic + version（参考 llama.cpp RPC 的 HELLO 机制）。
16. **worker 健康检查/断线重连**：`RemoteConnectionPool` 已有重连逻辑，但 worker 侧无心跳；加入负载状态上报，便于 watchdog 监控。
17. **benchmark harness 规范化**：统一 runs 次数、控制手机温度/网络波动、重复实验取中位数（当前部分结论基于单次 run）；补上 mistral.rs 桥接的性能日志留存。
18. **文档归一**：合并重复报告、回填"待重跑"、把"无日志佐证"的数据标注来源（session 记录 vs 日志）。

---

## 9. 相关文档索引

| 文档 | 内容 |
|------|------|
| [`docs/gpu-acceleration-summary.md`](./gpu-acceleration-summary.md) | 手机 GPU 加速尝试总览 |
| [`docs/GPU_CPU_SPLIT_INFERENCE_REPORT.md`](./GPU_CPU_SPLIT_INFERENCE_REPORT.md) | mistral.rs GPU/CPU 分层推理源码变更报告 |
| [`docs/OVERNIGHT_SESSION_REPORT.md`](./OVERNIGHT_SESSION_REPORT.md) | 跨机异构推理全历史总结（07-07 ~ 07-25） |
| [`3-machine/docs/report.md`](../3-machine/docs/report.md) | 三机通宵基准报告 |
| [`mistralrs-bridge/docs/overnight-session.md`](../mistralrs-bridge/docs/overnight-session.md) | mistral.rs 桥接通宵 session 复盘 |
| [`mistralrs-bridge/docs/report.md`](../mistralrs-bridge/docs/report.md) | mistral.rs 桥接源码报告（与顶层报告重复） |
| [`main/docs/protocol.md`](../main/docs/protocol.md) / [`3-machine/docs/protocol.md`](../3-machine/docs/protocol.md) | RPC 通信协议 v0.2 / v0.3 |

