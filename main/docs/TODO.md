# Hetero-LLaMA 三机推理 TODO / 状态续作

> 创建时间：2026-07-10
> 说明：上下文即将超限，先记录当前状态，后续继续完成三机端到端验证。

---

## 已完成的里程碑

1. **代码/脚本**
   - `config.env`：三机拓扑配置，新增 `TUNNEL_MODE`、`PHONE_REAL_HOST`、`CURRENT_REAL_IP`
   - `setup_tunnels.sh`：当前机器一键启动 SSH 反向隧道，暴露当前机器和手机 Worker 给 GPU PC
   - `run_cpu_rpc_server.sh` / `run_gpu_host.sh` / `run_gpu_host_2node.sh`：适配隧道模式
   - `protocol.md` v0.2：补充三机拓扑与隧道模式地址约定
   - `reproduce.md`：新增 GPU PC 编译、三机/双机步骤、常见问题
   - `report.md`：新增三机实施结果章节

2. **已验证：GPU PC + 当前机器 双机推理**
   - 命令：`TUNNEL_MODE=1 ./setup_tunnels.sh` + `TUNNEL_MODE=1 ./run_gpu_host.sh 20 "你好" 5`
   - 输出：`你好！有什么可以帮助你的`
   - 性能：load 16,384 ms / prompt 12.88 t/s / eval 8.55 t/s
   - 根因：WSL2 默认 NAT 入站数据包被丢弃，使用 SSH 反向隧道解决

3. **Git**
   - commit：`6964d37 feat: 3-machine heterogeneous inference with SSH tunnels`
   - branch：`feat/3-machine-inference` 已推送到 GitHub
   - tag：`v0.2.0` 已推送到 GitHub

---

## 正在处理：完整三机验证

### 当前状态

- 手机已重新联网，SSH 可达（`192.168.1.7:8022`）
- `setup_tunnels.sh` 已能成功建立：
  - 当前机器 RPC Server 监听 `127.0.0.1:50053`
  - 手机 RPC Server 监听 `127.0.0.1:50052`
  - 当前机器 → 手机的 SSH 本地转发 `127.0.0.1:50052`
  - 当前机器 → GPU PC 的 SSH 反向隧道 `127.0.0.1:50053` 和 `127.0.0.1:50052`
- GPU PC 上两个隧道端口均验证可达：`nc -vz 127.0.0.1 50053/50052`

### 遇到的问题

GPU PC Host 连接手机 Worker（`127.0.0.1:50052`）时崩溃：

```text
/home/atituiset/projects/gpu-cpu-phone-test/llama.cpp/ggml/src/ggml-rpc/ggml-rpc.cpp:337:
Remote RPC server crashed or returned malformed response
```

当前机器 Worker（`127.0.0.1:50053`）可正常连接并推理。

### 已排查

- 三端 llama.cpp commit 一致：`152d337fa spec: support spec-draft-p-min in DFlash (#25246)`
- 手机 RPC Server 进程已启动，但向其 `127.0.0.1:50052` 发送 HELLO 无响应
- 在 proot 内部也无法连接 `127.0.0.1:50052`，说明手机 RPC Server 可能没有真正监听或 bind 异常
- 可能与 proot-distro 的网络命名空间/localhost 映射有关

### 待验证/待做

- [ ] 在手机上用 foreground 方式启动 RPC Server，观察是否有错误输出
- [ ] 尝试让手机 RPC Server 绑定 `0.0.0.0:50052` 或 WiFi IP `192.168.1.7:50052`，测试不同 bind 地址下的可达性
- [ ] 检查手机 RPC Server 是否真正在监听端口（寻找无需 root 的替代方案，如 `ss`、`netstat` 均因权限被拒绝）
- [ ] 若手机本地 bind 确实有问题，考虑在 Termux 层直接运行 RPC Server（需解决 libc 差异）
- [ ] 三机端到端跑通后，收集 log 并刷新 `report.md`
- [ ] 最终再次 commit 并更新 tag（或打 v0.2.1）

---

## 常用命令速查

```bash
# 当前机器启动隧道
cd ~/Projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./setup_tunnels.sh

# GPU PC 三机推理
cd ~/projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./run_gpu_host.sh 20 "你好" 5

# 手机端手动启动 RPC Server（proot 内）
proot-distro login ubuntu
cd /root/Projects/gpu-cpu-phone-test
TUNNEL_MODE=1 ./run_phone_rpc.sh 127.0.0.1 50052

# 测试当前机器 RPC 响应
python3 -c "import sys, struct; sys.stdout.buffer.write(b'\x0e'+struct.pack('<Q',24)+b'\x00'*24)" \
  | nc -q 2 127.0.0.1 50053 | xxd

# 测试手机 RPC 响应（需先建立本地隧道）
python3 -c "import sys, struct; sys.stdout.buffer.write(b'\x0e'+struct.pack('<Q',24)+b'\x00'*24)" \
  | nc -q 2 127.0.0.1 50052 | xxd
```

---

## 相关文件

- `/home/atituiset/Projects/gpu-cpu-phone-test/config.env`
- `/home/atituiset/Projects/gpu-cpu-phone-test/setup_tunnels.sh`
- `/home/atituiset/Projects/gpu-cpu-phone-test/run_phone_rpc.sh`
- `/home/atituiset/Projects/gpu-cpu-phone-test/run_gpu_host.sh`
- `/home/atituiset/Projects/gpu-cpu-phone-test/report.md`
- `/home/atituiset/Projects/gpu-cpu-phone-test/reproduce.md`
- `/home/atituiset/Projects/gpu-cpu-phone-test/protocol.md`
- `/home/atituiset/Projects/gpu-cpu-phone-test/logs/`
