# Vulkan 本地/双机实验设计

> 日期：2026-07-11  
> 背景：GPU PC 暂时不可用，需要在当前 WSL 机器和 Mate 40 Pro 上验证 llama.cpp 的 Vulkan backend。  
> 目标：不破坏 `feat/3-machine-inference` 分支的 CUDA 三机配置，独立开展 Vulkan 实验。

---

## 1. 总体思路

采用 **git worktree + 独立分支** 的方式做隔离实验：

- 原目录 `/home/atituiset/Projects/gpu-cpu-phone-test` 保持 `feat/3-machine-inference` 不变，继续保留 CUDA 三机配置（`config.env`、`setup_tunnels.sh`、`run_gpu_host.sh` 等）。
- 新建 worktree `/home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan`，切出分支 `feat/vulkan-local`，所有 Vulkan 相关脚本、配置、文档只在该目录下修改。
- 手机端在同一分支下独立 checkout（已用 `git init` + `git remote add` + `git checkout` 补全仓库），目录为 `/root/Projects/gpu-cpu-phone-test`。

实验顺序：先各自跑通本地 Vulkan baseline，再尝试 WSL ↔ 手机 RPC 联动。

---

## 2. 分支与目录约定

### WSL 端

```text
/home/atituiset/Projects/gpu-cpu-phone-test                    # feat/3-machine-inference（CUDA 三机，不动）
/home/atituiset/Projects/gpu-cpu-phone-test/.claude/worktrees/vulkan   # feat/vulkan-local（Vulkan 实验）
```

### 手机端

```text
/root/Projects/gpu-cpu-phone-test                              # feat/vulkan-local（Vulkan 实验）
```

> 手机端原 CPU/RPC 配置以手动备份或分支切换方式保留；本次实验中不再维护手机端的 CUDA 三机配置。

---

## 3. 网络配置变更

`feat/vulkan-local` 分支下的 `config.env` 需要更新手机 IP：

```bash
PHONE_REAL_HOST="192.168.31.177"
PHONE_HOST="${PHONE_REAL_HOST}"
```

同时移除或注释掉 `GPU_PC_IP` 相关配置，因为 GPU PC 不参与本次实验。

---

## 4. 新增/修改文件

在 `feat/vulkan-local` 分支下新增以下文件：

| 文件 | 用途 |
|------|------|
| `run_wsl_vulkan_baseline.sh` | WSL 端使用 Vulkan backend 本地运行 `llama-completion` |
| `run_phone_vulkan_baseline.sh` | 手机端使用 Vulkan backend 本地运行 `llama-cli` |
| `check-vulkan-env.sh` | 检查 `vulkaninfo`、ICD、build 目录、模型路径 |
| `docs/vulkan-setup.md` | Vulkan 环境准备与复现步骤文档 |
| `reproduce.md`（追加章节） | 把 Vulkan 实验路线纳入复现手册 |

`config.env` 在 `feat/vulkan-local` 内修改：

- 更新 `PHONE_REAL_HOST`。
- 把 build 目录从 `build-rpc` / `build-cuda-rpc` 改为 `build-vulkan` / `build-vulkan-rpc`。
- 移除 GPU PC 相关路径。

---

## 5. 实验阶段

### Phase A：WSL 本地 Vulkan baseline

1. 在 WSL worktree 中检查 Vulkan 环境：

   ```bash
   ./check-vulkan-env.sh
   ```

2. 编译 llama.cpp Vulkan backend：

   ```bash
   cd llama.cpp
   cmake -B build-vulkan -DGGML_VULKAN=ON
   cmake --build build-vulkan -j
   ```

3. 运行 baseline：

   ```bash
   ./run_wsl_vulkan_baseline.sh 99 "你好" 5
   ```

### Phase B：手机本地 Vulkan baseline

1. 在手机仓库中检查 Vulkan 环境：

   ```bash
   ./check-vulkan-env.sh
   ```

2. 在 Termux / proot 中编译：

   ```bash
   cd llama.cpp
   cmake -B build-vulkan -DGGML_VULKAN=ON
   cmake --build build-vulkan -j
   ```

3. 运行 baseline：

   ```bash
   ./run_phone_vulkan_baseline.sh 99 "你好" 5
   ```

### Phase C：RPC 联动（后续可选）

在两台机器本地 Vulkan baseline 都跑通后，再编译 RPC 版本：

```bash
cmake -B build-vulkan-rpc -DGGML_VULKAN=ON -DGGML_RPC=ON
cmake --build build-vulkan-rpc -j
```

新增：

- `run_wsl_vulkan_host.sh`：WSL 作为 Host，调用手机 Worker。
- `run_phone_vulkan_worker.sh`：手机作为 RPC Worker。
- `run_wsl_vulkan_worker.sh` / `run_phone_vulkan_host.sh`：互为 Host/Worker 的另一方向。

---

## 6. 错误处理与回退

- 所有运行脚本使用 `set -e`，构建或运行失败立即退出。
- `check-vulkan-env.sh` 在运行前检查：
  - `vulkaninfo` 是否可用且能列出物理设备；
  - Vulkan build 目录和关键二进制是否存在；
  - 模型路径是否存在。
- 任一阶段失败可在 WSL 端直接删除 worktree：

  ```bash
  git worktree remove .claude/worktrees/vulkan
  ```

  原 `feat/3-machine-inference` 目录不受影响。

---

## 7. 与现有 CUDA 三机配置的隔离保证

- `feat/3-machine-inference` 的 `config.env`、`setup_tunnels.sh`、`run_gpu_host.sh`、`run_cpu_rpc_server.sh`、`run_phone_rpc.sh` 均不在本次实验中修改。
- Vulkan 相关改动集中在新增文件和 `feat/vulkan-local` 分支的 `config.env` 中。
- 需要合并回主线时，通过 cherry-pick 或手动迁移新增脚本，避免直接覆盖 CUDA 配置。

---

## 8. 验收标准

- [ ] WSL 端 `vulkaninfo` 能识别 GPU，且 `run_wsl_vulkan_baseline.sh` 成功输出文本。
- [ ] 手机端 `vulkaninfo` 能识别 Mali-G78，且 `run_phone_vulkan_baseline.sh` 成功输出文本。
- [ ] Phase C（可选）：WSL Host + 手机 Worker 的 RPC 联动能完整跑完一次推理。
- [ ] 整个过程中 `feat/3-machine-inference` 的 CUDA 脚本未被破坏。

---

## 9. 参考

- `README.md` 中“下一步计划”已列出 Vulkan 方向。
- `config.env` 当前定义见 `feat/3-machine-inference`。
