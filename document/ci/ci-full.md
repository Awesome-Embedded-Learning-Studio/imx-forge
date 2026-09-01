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
- QEMU 开机冒烟（mainline 内核 + rootfs 真的启动到登录提示符）
- 创建构建摘要

## 预计时间

| 场景 | 时间 |
|------|------|
| Stage 1 | ~8 分钟 |
| Stage 2（并行） | ~12 分钟 |
| Stage 3 | ~5 分钟 |
| Stage 4 | ~3 分钟 |
| QEMU Boot Smoke | 首次 ~15-25 分钟（编自建 QEMU），缓存命中后 ~5 分钟（TCG，无 KVM） |
| **总计** | **~25-35 分钟**（缓存命中）/ **~40-50 分钟**（首次） |

## 产物

| Artifact | 内容 | 保留期 |
|----------|------|--------|
| qemu-boot-log | QEMU 开机冒烟的完整串口日志（`uart.log`，运行时验证证据） | 30 天 |
| qemu-kernel / qemu-rootfs | 冒烟用的 mainline zImage + 真板同源 dtb + rootfs ext4 镜像（供复现/调试） | 7 天 |

::: info 说明
CI 不产出烧录镜像（Stage 5 仅本地 `release-all.sh` 执行）——曾经的 `release-images` artifact 因 final job 在独立 runner 上无产物可传而长期为空，已删除，由 QEMU 开机冒烟的 `qemu-boot-log` 提供真实运行时证据。
:::

::: info 双轨说明
Full Build 同时验证 Linux NXP BSP 和 Linux Mainline。QEMU 开机冒烟跑的是 Mainline 轨产物（`out/release-latest/linux` 的 zImage + 真板同源 dtb）；BSP 轨仍以构建验证为主。
:::

::: warning 为什么冒烟必须用自建 QEMU
真板单源设备树在发行版自带的 QEMU（8.2.x）上**启动不了**——eLCDIF/MMDC/OCOTP 在那边是未映射的地址空洞，内核死在串口驱动初始化之前（0 字节串口输出，CI 2026-08-31 实测）。因此冒烟 job 用 `build-qemu.sh` 自建的 v11.1（16 个板级补丁），二进制按补丁内容做缓存（`actions/cache`，键含 `patches/qemu/*.patch` 哈希），补丁不变不重编。
:::

## 使用场景

1. **PR 完整验证**：添加 `full-build` 标签
2. **Main 分支保护**：合并到 main 后自动运行
3. **发布前验证**：确保构建完整可用
