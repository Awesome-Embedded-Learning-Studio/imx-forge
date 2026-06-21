# 烧录命令速查

本页专门放 SD 卡直写和 UUU + UMS eMMC 烧录命令。原理和排查过程见 [SD 卡烧录实战](../flash/09_sd_card_flashing.md) 和 [UUU + UMS eMMC 烧录实战](../flash/10_uuu_ums_emmc_flashing.md)。

## 生成 SD 镜像

```bash
scripts/release-all.sh --continue --stage 5 --boot-media sd
```

或者：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-latest \
  --boot-media=sd
```

## 生成 eMMC 镜像

```bash
scripts/release-all.sh --continue --stage 5 --boot-media emmc
```

或者：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-latest \
  --boot-media=emmc
```

## 检查 SD manifest

```bash
sed -n '1,80p' out/release-latest/images/imx6ull-aes-sd.img.manifest
```

应重点确认：

```text
boot_media=sd
uboot_mmc_dev=0
linux_root_dev=/dev/mmcblk0p2
```

## 检查 eMMC manifest

```bash
sed -n '1,80p' out/release-latest/images/imx6ull-aes-emmc.img.manifest
```

应重点确认：

```text
boot_media=emmc
uboot_mmc_dev=1
linux_root_dev=/dev/mmcblk1p2
```

## 找目标块设备

插入 SD 卡或进入 UMS 前：

```bash
lsblk
```

插入 SD 卡或进入 UMS 后：

```bash
lsblk
```

写完整镜像时使用整盘设备：

```text
正确：/dev/sdX
错误：/dev/sdX1
```

## 卸载自动挂载分区

```bash
sudo umount /dev/sdX1
sudo umount /dev/sdX2
```

分区号以 `lsblk` 实际显示为准。

## 写 SD 卡

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-sd.img \
  of=/dev/sdX \
  bs=4M \
  status=progress \
  conv=fsync
sync
```

## 启动 UUU + UMS

查看 UUU 版本：

```bash
uuu -V
```

执行 UMS lst：

```bash
sudo uuu tools/uuu/imx6ull-aes-ums.lst
```

## 写 UMS 暴露的 eMMC

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-emmc.img \
  of=/dev/sdX \
  bs=4M \
  status=progress \
  conv=fsync
sync
```

## 检查 UUU lst 路径

```bash
sed -n '1,40p' tools/uuu/imx6ull-aes-ums.lst
```

当前应包含：

```text
SDP: boot -f ../../out/release-latest/uboot/u-boot-dtb.imx
```

## 检查 U-Boot 是否包含 UMS 环境

```bash
strings out/release-latest/uboot/u-boot-dtb.imx | grep -E 'bootcmd_mfg|ums 0 mmc'
```

## U-Boot 手动暴露 eMMC

```text
mmc dev 1
ums 0 mmc 1
```

## U-Boot 手动暴露 SD

```text
mmc dev 0
ums 0 mmc 0
```

## U-Boot 检查 SD 分区

```text
mmc list
mmc dev 0
mmc part
ext4ls mmc 0:1 /
ext4ls mmc 0:2 /
```

## U-Boot 检查 eMMC 分区

```text
mmc list
mmc dev 1
mmc part
ext4ls mmc 1:1 /
ext4ls mmc 1:2 /
```

## 手动启动 SD

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw
ext4load mmc 0:1 ${loadaddr} /zImage
ext4load mmc 0:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

## 手动启动 eMMC

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk1p2 rootfstype=ext4 rootwait rw
ext4load mmc 1:1 ${loadaddr} /zImage
ext4load mmc 1:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

## Linux 启动后检查

```bash
cat /proc/cmdline
mount | grep ' / '
lsblk
```

SD 启动应看到：

```text
/dev/mmcblk0p2
```

eMMC 启动应看到：

```text
/dev/mmcblk1p2
```
