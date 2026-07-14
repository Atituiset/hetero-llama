# main 模式：PC + 手机 RPC 异构推理

本目录是 Hetero-LLaMA 的基础 RPC 模式：PC（x86_64 CPU）作为 Host，华为 Mate 40 Pro（ARM64 CPU，Termux + proot Ubuntu）作为 RPC Worker，通过 llama.cpp 的 RPC 后端完成跨设备分层推理。

- 状态：✅ 可用
- 模型：`Qwen2-0.5B-Instruct-Q4_0.gguf`（336 MB，24 层）
- llama.cpp commit：`152d337fadb93c2a099653c4072d5512c92c5bfd`

## 目录

- `config.env` — 节点地址、模型路径、默认推理参数
- `scripts/` — 一键运行脚本
- `docs/` — 报告、复现手册、协议
- `logs/` — 运行日志

## 快速开始

1. 在两端准备同 commit 的 llama.cpp，并编译 RPC 后端：

   ```bash
   # PC
   cmake -B build-rpc -DGGML_RPC=ON && cmake --build build-rpc

   # 手机（proot Ubuntu 内）
   cmake -B build-rpc -DGGML_RPC=ON && cmake --build build-rpc
   ```

2. 将模型放到 `~/models/qwen2-0.5b-instruct-q4_0.gguf`（或修改 `config.env` 的 `MODEL_PATH`）。

3. 编辑 `config.env` 中的 `PHONE_HOST` / `PHONE_PORT`，确保 PC 能访问手机端口。

4. 手机端启动 RPC Server：

   ```bash
   ./scripts/run_phone_rpc.sh
   ```

5. PC 端发起推理：

   ```bash
   ./scripts/run_pc_rpc.sh 99 "你好" 5
   ```

   - `99`：offload 层数（`-ngl`），`99` 表示尽量多放手机。
   - `"你好"`：prompt。
   - `5`：生成 token 数。

   如果 `config.env` 里的地址与脚本默认值不同，可显式传 host/port：

   ```bash
   source config.env
   ./scripts/run_pc_rpc.sh 99 "你好" 5 "${PHONE_HOST}" "${PHONE_PORT}"
   ```

6. 需要 DEBUG 调度细节时：

   ```bash
   DEBUG=1 ./scripts/run_pc_rpc.sh 99 "你好" 5 2>&1 | ../common/scripts/ts-log.sh > logs/pc_ngl99_$(date +%Y%m%d_%H%M%S).log
   DEBUG=1 ./scripts/run_phone_rpc.sh
   ```

## 脚本说明

| 脚本 | 用途 | 运行位置 |
|---|---|---|
| `run_phone_rpc.sh` | 启动手机 RPC Server（带 `-c` 缓存） | 手机 |
| `run_pc_rpc.sh` | PC Host，通过 `--rpc` 调用手机 Worker | PC |
| `run_phone_baseline.sh` | 手机本地 CPU 推理基线 | 手机 |
| `../common/scripts/check-phone-status.sh` | 检查手机 Agent/inbox/outbox/进程状态 | PC |
| `../common/scripts/ts-log.sh` | 给日志加 `YYYY-MM-DD HH:MM:SS` 时间戳 | 任意 |

## 关键结论

1. **`-ngl` 真实控制手机参与比例**
   - `-ngl 4`：手机端 graph 约 108 个节点
   - `-ngl 99`：手机端 graph 约 821 个节点（完整 forward）

2. **手机 RPC Server 必须带缓存**  
   启动时 `./run_phone_rpc.sh` 已默认使用 `-c`，336 MB 权重首次传输后会缓存在 `~/.cache/llama.cpp/rpc/`。

3. **性能（关闭 DEBUG）**

   | 模式 | prompt eval | generation |
   |---|---|---|
   | PC 本地 CPU | 380.78 t/s | 99.75 t/s |
   | PC + 手机 RPC（`-ngl 4`） | 37.64 t/s | 7.59 t/s |
   | PC + 手机 RPC（`-ngl 99`） | 9.73 t/s | 3.36 t/s |

   > 开启 DEBUG 后日志写入会显著拖慢速度，DEBUG 数据仅用于验证 scheduler 行为。

## 日志说明

`logs/` 下的所有日志都通过 `ts-log.sh` 加了 `YYYY-MM-DD HH:MM:SS` 的 wall-clock 时间戳。它们按“PC 端 / 手机端 + 配置 + 是否 DEBUG”命名，对应关系如下：

| 日志文件 | 产生命令 | 运行位置 | 关键结果 |
|---|---|---|---|
| `pc_cpu_20260708_210444.log` | `llama-completion -m <model> -p "你好" -n 5` + `../common/scripts/ts-log.sh` | PC | DEBUG 本地 CPU 基线：prompt 386.17 t/s，gen 95.11 t/s |
| `pc_cpu_nodebug_20260708_213312.log` | 同上，关闭 DEBUG | PC | 真实本地 CPU：prompt 380.78 t/s，gen 99.75 t/s |
| `pc_ngl4_20260708_210444.log` | `DEBUG=1 ./run_pc_rpc.sh 4 "你好" 5` + `../common/scripts/ts-log.sh` | PC | 4 层 offload 到手机：prompt 34.34 t/s，gen 8.46 t/s |
| `pc_ngl4_nodebug_20260708_212253.log` | `./run_pc_rpc.sh 4 "你好" 5` + `../common/scripts/ts-log.sh` | PC | 同上非 DEBUG：prompt 37.64 t/s，gen 7.59 t/s |
| `pc_ngl99_20260708_210444.log` | `DEBUG=1 ./run_pc_rpc.sh 99 "你好" 5` + `../common/scripts/ts-log.sh` | PC | 全部层 offload 到手机：prompt 8.96 t/s，gen 3.16 t/s |
| `pc_ngl99_nodebug_20260708_212345.log` | `./run_pc_rpc.sh 99 "你好" 5` + `../common/scripts/ts-log.sh` | PC | 同上非 DEBUG：prompt 9.73 t/s，gen 3.36 t/s |
| `phone_cpu_20260708_210444.log` | `./run_phone_baseline.sh` + `../common/scripts/ts-log.sh` | 手机 | 本地 CPU 基线：约 7.1 t/s |
| `phone_cpu_nodebug_20260708_213312.log` | 同上 | 手机 | 同上 |
| `phone_ngl4_20260708_210444.log` | `DEBUG=1 ./run_phone_rpc.sh` + `../common/scripts/ts-log.sh` | 手机 | RPC Server 侧，对应 `pc_ngl4`：graph 108 节点 |
| `phone_ngl4_nodebug_20260708_212253.log` | 同上 | 手机 | 同上 |
| `phone_ngl99_20260708_210444.log` | `DEBUG=1 ./run_phone_rpc.sh` + `../common/scripts/ts-log.sh` | 手机 | RPC Server 侧，对应 `pc_ngl99`：graph 821 节点 |
| `phone_ngl99_nodebug_20260708_212345.log` | 同上 | 手机 | 同上 |

> `*_nodebug_*.log` 是关闭 `DEBUG=1` 后的真实性能数据；`DEBUG=1` 日志用于验证 scheduler split 和手机端 graph 节点数。

## 文档

| 文档 | 内容 |
|---|---|
| `docs/report.md` | 完整实验报告与性能数据 |
| `docs/reproduce.md` | 逐行复现手册 |
| `docs/protocol.md` | 双/三机通信协议 v0.2 |
| `docs/plan.md` | 原始规划 |
| `docs/inbox.md` / `outbox.md` | 双 Agent 任务信箱 |

## 注意

- 本模式默认假设 PC 与手机在同一局域网且端口可达。如果需要经过 SSH 反向隧道连接 WSL2 / 手机，请参考 [`../3-machine/`](../3-machine/README.md) 模式。
- 三端 llama.cpp commit 必须一致，否则会出现 `Remote RPC server crashed or returned malformed response`。
