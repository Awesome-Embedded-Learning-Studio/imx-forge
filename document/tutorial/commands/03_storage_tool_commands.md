# 存储工具命令速查

本页只做速查和安全提示，不展开完整烧录教程。真实烧录请结合 [SD 卡烧录实战](../flash/09_sd_card_flashing.md) 和 [UUU + UMS eMMC 烧录实战](../flash/10_uuu_ums_emmc_flashing.md) 操作。

## 查看块设备

插入 SD 卡或暴露 UMS 之前：

```bash
lsblk
```

插入之后再看一次：

```bash
lsblk
```

新增的整盘设备可能类似：

```text
/dev/sdX
```

写完整 raw image 时使用整盘设备，不使用分区路径：

```text
正确：/dev/sdX
错误：/dev/sdX1
```

## 查看设备详情

```bash
sudo fdisk -l /dev/sdX
```

或者：

```bash
lsblk -f /dev/sdX
```

## 卸载已挂载分区

```bash
sudo umount /dev/sdX1
sudo umount /dev/sdX2
```

如果分区数量不确定，先用 `lsblk` 确认。

## dd 写入 raw image

::: danger
`dd` 会覆盖目标设备内容。确认 `/dev/sdX` 是目标 SD 卡或 UMS 暴露出来的 eMMC，不要写到主机硬盘。
:::

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-sd.img \
  of=/dev/sdX \
  bs=4M \
  status=progress \
  conv=fsync
```

写完后同步：

```bash
sync
```

## dd 读取备份

从设备读出 raw image：

```bash
sudo dd if=/dev/sdX \
  of=backup.img \
  bs=4M \
  status=progress \
  conv=fsync
```

## 查看镜像分区表

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-sd.img
```

查看真实设备分区表：

```bash
sudo sfdisk -d /dev/sdX
```

## UUU 启动 U-Boot

UUU/UMS 常用于 eMMC 流程：先通过 USB SDP 把 U-Boot 跑进内存，再让 U-Boot 暴露 eMMC 为 USB Mass Storage。

查看 UUU 版本：

```bash
uuu -V
```

执行 lst：

```bash
sudo uuu tools/uuu/imx6ull-aes-ums.lst
```

如果权限已配置好，也可以不加 `sudo`。

## U-Boot UMS 命令

在 U-Boot 里暴露 eMMC：

```text
mmc dev 1
ums 0 mmc 1
```

暴露 SD：

```text
mmc dev 0
ums 0 mmc 0
```

回到主机后用 `lsblk` 确认新增设备。

## U-Boot 检查分区

```text
mmc list
mmc dev 0
mmc part
ext4ls mmc 0:1 /
ext4ls mmc 0:2 /
```

eMMC 通常使用：

```text
mmc dev 1
mmc part
ext4ls mmc 1:1 /
ext4ls mmc 1:2 /
```

## 手动启动 SD 镜像

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw
ext4load mmc 0:1 ${loadaddr} /zImage
ext4load mmc 0:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

## 手动启动 eMMC 镜像

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw
ext4load mmc 1:1 ${loadaddr} /zImage
ext4load mmc 1:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

## 相关资料

- [烧录命令速查](04_flashing_commands.md)
- [SD 卡烧录实战](../flash/09_sd_card_flashing.md)
- [UUU + UMS eMMC 烧录实战](../flash/10_uuu_ums_emmc_flashing.md)
- [SD 卡烧录 Bring-up 笔记](../../notes/2026-06-08-sd-card-flashing-bringup.md)
- [UUU + UMS + eMMC Bring-up 笔记](../../notes/2026-06-08-uuu-ums-emmc-bringup.md)
