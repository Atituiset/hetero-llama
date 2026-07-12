# 3-Machine 异构推理模式

本目录为 `feat/3-machine-inference` 分支预留位置。

## 状态

- **当前 main 分支尚未包含完整 3-machine 实现**。
- 完整脚本、配置和日志仍在独立分支：`feat/3-machine-inference`。

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
