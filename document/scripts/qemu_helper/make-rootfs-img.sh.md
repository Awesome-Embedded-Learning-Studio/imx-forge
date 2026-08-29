# make-rootfs-img.sh - QEMU rootfs 镜像制作脚本详解

## 脚本概述

`make-rootfs-img.sh` 把 `out/release-latest/rootfs/` 目录树打包成 QEMU 可直接
挂载的 ext4 裸镜像（无分区表），供 `run-qemu.sh` 作为 SD 卡使用。它解决两个
具体问题：一是 QEMU 的 SD 模型把容量编码进 CSD 寄存器、只支持 2 的幂大小，
非 2 的幂镜像在 guest 里会被识别成 0 字节卡；二是我们的 SD/eMMC 整盘镜像
（216M/369M）不符合这个约束，需要单独制作 rootfs-only 镜像。

### 核心功能

- **目录树直灌 ext4**：`mke2fs -t ext4 -d`（与 `scripts/image_builder/`
  的分区文件系统做法一致），不需要 root 权限、不需要 loop 挂载
- **2 的幂容量校验**：默认 256M，可用 `--size-mb` 调整（512/1024…），
  非法值直接报错
- **增量 resize**：`--append-size-mb` 对已存在镜像原地扩容，rootfs 树长大后
  CI 里不用重建

### 在开发工作流中的位置

QEMU 模拟链路三件套的第一步：

```text
make-rootfs-img.sh   →  out/qemu/rootfs.ext4      （本脚本）
make-qemu-dtb.sh     →  out/qemu/imx6ull-aes-qemu.dtb
run-qemu.sh          →  交互 / --smoke 冒烟
```

## 用法示例

```bash
# 默认：out/release-latest/rootfs → out/qemu/rootfs.ext4 (256M)
scripts/qemu_helper/make-rootfs-img.sh

# rootfs 树超过 256M 时扩到 512M
scripts/qemu_helper/make-rootfs-img.sh --size-mb=512

# 树长大了，只扩容不重建
scripts/qemu_helper/make-rootfs-img.sh --append-size-mb=512
```

## 关键实现细节

- **`mke2fs -d` 的含义**：直接以目录树为内容源创建文件系统镜像（`-F` 强制
  对普通文件操作，`-m 0` 不预留 root 块，`-L rootfs` 打卷标），guest 里
  `root=/dev/mmcblk1` 整卡即文件系统
- **为什么无分区表**：QEMU `-drive if=sd,index=1` 挂 USDHC2 → guest
  `/dev/mmcblk1`；没有 MBR 时 ext4 直接从 0 扇区开始，`root=/dev/mmcblk1`
  即可，省掉分区偏移换算

## 常见问题

- **mke2fs 报 "too small"**：目录树实际占用超过 `--size-mb`，调大（保持
  2 的幂）
- **QEMU 里 mmcblk1 容量为 0 / 无法挂载**：镜像不是 2 的幂大小（见脚本头
  注释里 CSD 的说明）
