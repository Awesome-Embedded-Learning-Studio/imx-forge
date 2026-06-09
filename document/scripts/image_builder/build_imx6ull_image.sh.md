# build_imx6ull_image.sh 说明文档

> **文件路径**: `scripts/image_builder/build_imx6ull_image.sh`
> **脚本类型**: image_builder
> **状态**: 已完成

## 概述

构建 i.MX6ULL 可启动 SD/eMMC 镜像的脚本。该脚本从发布目录读取 U-Boot、Linux 内核、设备树和 rootfs 组件，生成完整的可启动系统镜像。

**主要功能：**
- 从发布目录组装完整的启动镜像
- 支持 SD 卡和 eMMC 两种启动介质
- 自动计算分区布局和镜像大小
- 生成 U-Boot 启动脚本和 boot.cmd
- 输出镜像清单和 SHA256 校验和

## 使用方法

```bash
# 基本用法 - 使用默认配置
./scripts/image_builder/build_imx6ull_image.sh

# 指定发布目录
./scripts/image_builder/build_imx6ull_image.sh --release-dir=out/release-latest

# 指定设备树和启动介质
./scripts/image_builder/build_imx6ull_image.sh --device-tree=imx6ull-aes --boot-media=emmc

# 指定固定镜像大小
./scripts/image_builder/build_imx6ull_image.sh --image-size-mb=1024

# 使用环境变量设置默认值
DEFAULT_BOOT_MEDIA=sd DEFAULT_DEVICE_TREE=imx6ull-aes ./scripts/image_builder/build_imx6ull_image.sh
```

## 参数说明

| 参数 | 说明 | 必需/可选 |
|------|------|-----------|
| `--release-dir=PATH` | 发布目录路径，包含 uboot/linux/rootfs | 可选 (默认: `out/release-latest`) |
| `--device-tree=NAME` | 设备树名称（不含.dtb）或完整.dtb路径 | 可选 (默认: `imx6ull-aes`) |
| `--boot-media=sd\|emmc` | 目标启动介质，控制 U-Boot mmc 设备和 root 设备 | 可选 (默认: `emmc`) |
| `--image-name=NAME` | 输出镜像文件名 | 可选 (默认: `<dtb>-<boot-media>.img`) |
| `--boot-size-mb=N` | Boot 分区大小（MiB） | 可选 (默认: 64) |
| `--rootfs-size-mb=N` | Rootfs 分区大小（MiB） | 可选 (默认: 自动计算) |
| `--image-size-mb=N` | 最终镜像大小（MiB），剩余空间分配给 rootfs | 可选 (默认: 自动计算) |
| `--keep-workdir` | 保留临时文件系统镜像用于调试 | 可选 |
| `--help, -h` | 显示帮助信息 | 可选 |

**注意:** `--rootfs-size-mb` 和 `--image-size-mb` 不能同时使用，只能指定其中一个。

## 执行流程

1. **参数解析与验证**
   - 解析命令行参数
   - 验证数值参数的有效性

2. **启动介质解析**
   - 根据 `--boot-media` 确定 U-Boot mmc 设备号和 Linux root 设备
   - `sd` → mmc 0, `/dev/mmcblk0p2`
   - `emmc` → mmc 1, `/dev/mmcblk1p2`

3. **组件定位与验证**
   - 定位 U-Boot 镜像 (`u-boot-dtb.imx`)
   - 定位内核镜像 (`zImage`)
   - 定位设备树文件 (`.dtb`)
   - 验证 rootfs 目录存在性

4. **布局计算**
   - 自动计算最小 boot 分区大小
   - 根据 rootfs 使用情况计算 rootfs 分区大小
   - 计算最终镜像大小

5. **创建启动文件树**
   - 创建 boot 目录结构
   - 复制 zImage 和 DTB 文件
   - 生成 U-Boot 启动脚本 (`boot.cmd`)

6. **创建分区文件系统**
   - 创建 ext4 格式的 boot 分区镜像
   - 创建 ext4 格式的 rootfs 分区镜像

7. **写入最终镜像**
   - 创建分区表
   - 在 1KB 偏移处写入 U-Boot
   - 写入 boot 分区和 rootfs 分区
   - 生成清单文件和 SHA256 校验和

## 镜像布局

```
+------------------------+----------------------+--------------------------+
|       偏移             |        大小          |         内容             |
+------------------------+----------------------+--------------------------+
| 1 KiB                  | ~512 KiB             | U-Boot (u-boot-dtb.imx) |
| 16 MiB                 | BOOT_SIZE_MB MiB     | Boot 分区 (ext4)         |
| (16 + BOOT_SIZE) MiB   | ROOTFS_SIZE_MB MiB   | Rootfs 分区 (ext4)       |
+------------------------+----------------------+--------------------------+
```

**分区详情：**

| 分区 | 起始扇区 | 内容 |
|------|----------|------|
| - | 1KB offset | U-Boot (原始写入) |
| 1 (可启动) | 16 MiB | zImage, DTB, boot.cmd |
| 2 | 紧接 boot 分区 | 完整 rootfs |

## 依赖关系

### 依赖的脚本
- `scripts/lib/logging.sh` - 日志输出函数（可选）

### 依赖的工具
| 工具 | 用途 |
|------|------|
| `realpath` | 解析绝对路径 |
| `sfdisk` | 创建分区表 |
| `mke2fs` | 创建 ext4 文件系统 |
| `truncate` | 创建稀疏文件 |
| `dd` | 写入镜像数据 |
| `du` | 计算目录大小 |
| `stat` | 获取文件大小 |
| `awk` | 文本处理 |
| `sha256sum` | 生成校验和（可选） |

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DEFAULT_DEVICE_TREE` | 默认设备树名称 | `imx6ull-aes` |
| `DEFAULT_BOOT_MEDIA` | 默认启动介质 | `emmc` |
| `DEFAULT_IMAGE_SIZE_MB` | 默认固定镜像大小 | 空 (自动计算) |

## 输入目录结构

```
out/release-latest/
├── uboot/
│   └── u-boot-dtb.imx              # U-Boot 镜像
├── linux/arch/arm/boot/
│   ├── zImage                      # 内核镜像
│   └── dts/nxp/imx/
│       └── imx6ull-aes.dtb         # 设备树
├── rootfs/                         # Rootfs 目录
│   ├── bin/busybox
│   └── ...
└── images/                         # 输出目录（自动创建）
    ├── imx6ull-aes-emmc.img
    ├── imx6ull-aes-emmc.img.manifest
    └── imx6ull-aes-emmc.img.sha256
```

## 输出产物

1. **系统镜像**: `<release-dir>/images/<dtb>-<boot-media>.img`
   - 完整的可启动 SD/eMMC 镜像
   - 包含 U-Boot、分区表、boot 分区、rootfs 分区

2. **清单文件**: `<image>.manifest`
   - 镜像构建信息
   - 分区布局详情
   - 手动启动命令

3. **SHA256 校验和**: `<image>.sha256`
   - 用于验证镜像完整性

## 故障排除

### 常见错误

**错误**: `Required tool not found: <tool>`
**原因**: 缺少必要的系统工具
**解决**: 安装对应的工具，如 `sudo apt-get install util-linux e2fsprogs`

**错误**: `Release directory not found`
**原因**: 指定的发布目录不存在
**解决**: 先运行完整的构建流程生成发布目录

**错误**: `--image-size-mb is too small`
**原因**: 指定的镜像大小不足以容纳所有内容
**解决**: 增大 `--image-size-mb` 值，或让脚本自动计算

**错误**: `Use either --rootfs-size-mb or --image-size-mb, not both`
**原因**: 同时指定了两个互斥的参数
**解决**: 只使用其中一个参数

## 更新日志

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-06-09 | 1.0 | 初始版本 |

---

> **文档生成时间**: 2026-06-09
> **最后更新**: 2026-06-09
