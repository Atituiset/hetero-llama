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
