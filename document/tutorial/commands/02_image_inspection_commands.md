# 镜像检查命令速查

本页命令以只读检查为主，用来确认 `.img` 是否按预期生成。

## 查看镜像文件

```bash
ls -lh out/release-latest/images/*.img
```

查看某个镜像和附属文件：

```bash
ls -lh out/release-latest/images/imx6ull-aes-emmc.img*
```

## 查看 manifest

```bash
sed -n '1,80p' out/release-latest/images/imx6ull-aes-emmc.img.manifest
```

重点看：

```text
boot_media=
uboot_mmc_dev=
linux_root_dev=
boot_partition_start_sector=
rootfs_partition_start_sector=
rootfs_partition_size_mib=
image_size_mib=
```

## 查看分区表

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-emmc.img
```

典型输出：

```text
label: dos
unit: sectors

...img1 : start=32768, size=131072, type=83, bootable
...img2 : start=163840, size=..., type=83
```

换算：

```text
32768 sectors * 512 bytes = 16 MiB
131072 sectors * 512 bytes = 64 MiB
```

## 验证 sha256

进入 images 目录：

```bash
cd out/release-latest/images
sha256sum -c imx6ull-aes-emmc.img.sha256
```

回到项目根目录：

```bash
cd -
```

## 手动计算 sha256

```bash
sha256sum out/release-latest/images/imx6ull-aes-emmc.img
```

## 查看 ext4 超级块

如果你保留了临时目录：

```bash
scripts/image_builder/build_imx6ull_image.sh --keep-workdir
```

可以检查中间文件系统：

```bash
dumpe2fs -h out/imx6ull-image.XXXXXX/boot.ext4
dumpe2fs -h out/imx6ull-image.XXXXXX/rootfs.ext4
```

只看卷标：

```bash
dumpe2fs -h out/imx6ull-image.XXXXXX/boot.ext4 | grep 'Filesystem volume name'
dumpe2fs -h out/imx6ull-image.XXXXXX/rootfs.ext4 | grep 'Filesystem volume name'
```

## 用 debugfs 查看文件

检查 boot 分区中间镜像：

```bash
debugfs -R 'ls -l /' out/imx6ull-image.XXXXXX/boot.ext4
debugfs -R 'ls -l /boot' out/imx6ull-image.XXXXXX/boot.ext4
debugfs -R 'cat /boot.cmd' out/imx6ull-image.XXXXXX/boot.ext4
```

检查 rootfs 中间镜像：

```bash
debugfs -R 'ls -l /' out/imx6ull-image.XXXXXX/rootfs.ext4
debugfs -R 'ls -l /bin' out/imx6ull-image.XXXXXX/rootfs.ext4
```

## 检查 release 输入产物

```bash
ls -lh out/release-latest/uboot/u-boot-dtb.imx
ls -lh out/release-latest/linux/arch/arm/boot/zImage
ls -lh out/release-latest/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
ls -ld out/release-latest/rootfs
```

检查 rootfs 大小：

```bash
du -sh out/release-latest/rootfs
du -sm out/release-latest/rootfs
```

## 查找可用 DTB

```bash
find out/release-latest/linux/arch/arm/boot/dts -name 'imx6ull*.dtb' | sort
```

## 只检查脚本语法

```bash
bash -n scripts/image_builder/build_imx6ull_image.sh
```

## 对照启动命令

查看 manifest 里的手动启动命令：

```bash
sed -n '/manual_uboot_boot:/,$p' out/release-latest/images/imx6ull-aes-emmc.img.manifest
```

如果是 SD 镜像，应出现：

```text
ext4load mmc 0:1
root=/dev/mmcblk0p2
```

如果是 eMMC 镜像，应出现：

```text
ext4load mmc 1:1
root=/dev/mmcblk1p2
```
