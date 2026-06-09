# 镜像构建命令速查

本页只汇总 `scripts/image_builder/build_imx6ull_image.sh` 的常用命令。原理解释见 [脚本设计拆解](../flash/06_build_imx6ull_image_script)。

## 查看帮助

```bash
scripts/image_builder/build_imx6ull_image.sh --help
```

## 默认生成 eMMC 镜像

```bash
scripts/image_builder/build_imx6ull_image.sh
```

默认输入：

```text
out/release-latest
```

默认输出：

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

## 生成 SD 镜像

```bash
scripts/image_builder/build_imx6ull_image.sh --boot-media=sd
```

输出：

```text
out/release-latest/images/imx6ull-aes-sd.img
```

## 生成 eMMC 镜像

```bash
scripts/image_builder/build_imx6ull_image.sh --boot-media=emmc
```

输出：

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

## 指定 release 目录

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-20260608-121544 \
  --boot-media=sd
```

## 指定设备树名称

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --device-tree=imx6ull-aes
```

脚本会查找：

```text
out/release-latest/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
```

## 指定 DTB 文件路径

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --device-tree=/tmp/imx6ull-custom.dtb
```

## 指定输出文件名

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --image-name=imx6ull-test.img
```

如果没有 `.img` 后缀，脚本会自动补上。

## 固定总镜像大小

```bash
scripts/image_builder/build_imx6ull_image.sh --image-size-mb=1024
```

多出来的空间会分给 rootfs 分区。

## 固定 rootfs 分区大小

```bash
scripts/image_builder/build_imx6ull_image.sh --rootfs-size-mb=1024
```

不要和 `--image-size-mb` 同时使用。

## 调整 boot 分区大小

```bash
scripts/image_builder/build_imx6ull_image.sh --boot-size-mb=128
```

通常不需要调整，默认 64 MiB 足够存放 `zImage`、DTB 和 `boot.cmd`。

## 保留临时目录

```bash
scripts/image_builder/build_imx6ull_image.sh --keep-workdir
```

用于调试 `boot.ext4`、`rootfs.ext4` 或中间镜像。正常使用不建议保留。

## 使用环境变量设置默认值

```bash
DEFAULT_DEVICE_TREE=imx6ull-aes \
DEFAULT_BOOT_MEDIA=sd \
DEFAULT_IMAGE_SIZE_MB=1024 \
scripts/image_builder/build_imx6ull_image.sh
```

## 通过 release-all 生成镜像

只运行镜像阶段：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media emmc
scripts/release-all.sh --continue --stage 5 --boot-media sd
```

如果构建脚本启用了 `both`：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media both
```

## 输出文件说明

| 文件 | 说明 |
| --- | --- |
| `*.img` | 完整 raw disk image |
| `*.img.manifest` | 输入产物、分区布局、启动命令记录 |
| `*.img.sha256` | 镜像校验和 |

## 介质映射速查

| 参数 | U-Boot mmc dev | Linux root | 默认文件名 |
| --- | --- | --- | --- |
| `--boot-media=sd` | `0` | `/dev/mmcblk0p2` | `imx6ull-aes-sd.img` |
| `--boot-media=emmc` | `1` | `/dev/mmcblk1p2` | `imx6ull-aes-emmc.img` |
