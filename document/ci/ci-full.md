# Full Build

完整构建工作流，执行完整的 4 阶段构建流程。

## 文件

`.github/workflows/ci-full.yml`

## 触发条件

| 事件 | 条件 |
|------|------|
| `push` | 推送到 main 分支 |
| `pull_request` | PR 添加 `full-build` 标签 |
| `workflow_dispatch` | 手动触发（可指定阶段） |

## 手动触发参数

| 参数 | 选项 | 说明 |
|------|------|------|
| stage | all / 1 / 2 / 3 / 4 | 指定构建阶段 |

## 构建阶段

### Stage 1 - U-Boot

- 超时：12 分钟
- 命令：`./scripts/release-all.sh --stage 1`
- 产物：`out/release-latest/uboot/u-boot-dtb.imx`

### Stage 2 - Linux Kernel（并行）

| Job | 内核 | 超时 |
|-----|------|------|
| stage2-imx | NXP BSP | 20 分钟 |
| stage2-mainline | Mainline | 20 分钟 |

两个内核**并行构建**，节省约 10 分钟。

### Stage 3 - BusyBox

- 超时：10 分钟
- 依赖：Stage 2 完成
- 命令：`./scripts/release-all.sh --stage 3`
- 产物：`out/release-latest/busybox/`, `out/release-latest/rootfs/bin/busybox`

### Stage 4 - RootFS

- 超时：8 分钟
- 依赖：Stage 3 完成
- 命令：`./scripts/release-all.sh --stage 4`
- 验证：`./scripts/varified_rootfs_ok.sh`

### Final - 最终验证

- 验证所有产物存在
- 创建构建摘要
- 上传 artifacts（保留 30 天）

## 预计时间

| 场景 | 时间 |
|------|------|
| Stage 1 | ~8 分钟 |
| Stage 2（并行） | ~12 分钟 |
| Stage 3 | ~5 分钟 |
| Stage 4 | ~3 分钟 |
| **总计** | **~25-30 分钟** |

## 产物

| Artifact | 内容 | 保留期 |
|----------|------|--------|
| release-images | `out/release-latest/images/` | 30 天 |

::: info 双轨说明
Full Build 同时验证 Linux NXP BSP 和 Linux Mainline。当前 `release-images` artifact 主要来自 `release-all.sh` 的 BSP 默认链路；Mainline 在同一次工作流中作为兼顾轨道进行构建验证。
:::

## 使用场景

1. **PR 完整验证**：添加 `full-build` 标签
2. **Main 分支保护**：合并到 main 后自动运行
3. **发布前验证**：确保构建完整可用
