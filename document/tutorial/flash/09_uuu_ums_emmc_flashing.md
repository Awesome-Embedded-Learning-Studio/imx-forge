# UUU + UMS eMMC 烧录实战 - 让板子把 eMMC 借给主机

## 前言：eMMC 不能像 SD 卡那样拔下来

SD 卡烧录很直接：拿读卡器，找到 `/dev/sdX`，把整盘镜像写进去。

eMMC 就麻烦一点。它焊在板子上，不能拔下来插到主机。我们需要让板子自己帮忙：先通过 USB SDP 把 U-Boot 临时下载到 RAM 里运行，再让 U-Boot 执行 `ums 0 mmc 1`，把板上的 eMMC 伪装成一个 USB Mass Storage 设备暴露给主机。

这就是 UUU + UMS 流程。

这里有个边界一定要分清楚：UUU 这一步只是把 U-Boot 跑进内存。真正写入 eMMC 的动作，是主机对 UMS 暴露出来的块设备写 raw image。

## 当前流程长什么样

整个链路可以拆成四步：

```text
主机 uuu
  -> USB SDP 下载 u-boot-dtb.imx 到 RAM
  -> U-Boot 运行 bootcmd_mfg
  -> U-Boot 执行 ums 0 mmc 1 暴露 eMMC
  -> 主机把 imx6ull-aes-emmc.img 写进新增块设备
```

项目里的 UUU 脚本是：

```text
tools/uuu/imx6ull-aes-ums.lst
```

内容很短：

```text
uuu_version 1.4.72
SDP: boot -f ../../out/release-latest/uboot/u-boot-dtb.imx
```

这个相对路径是按 `tools/uuu/` 目录来算的。之前 bring-up 里踩过一次坑：如果 lst 里直接写 `out/release-latest/...`，UUU 从 lst 所在目录解析路径时就会找不到文件。现在用 `../../out/...`，从 `tools/uuu/` 回到项目根目录，再进入 `out/`。

## 先生成 eMMC 镜像

从项目根目录执行：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media emmc
```

或者直接调用镜像脚本：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-latest \
  --boot-media=emmc
```

输出应该是：

```text
out/release-latest/images/imx6ull-aes-emmc.img
out/release-latest/images/imx6ull-aes-emmc.img.manifest
out/release-latest/images/imx6ull-aes-emmc.img.sha256
```

烧录前先看 manifest：

```bash
sed -n '1,80p' out/release-latest/images/imx6ull-aes-emmc.img.manifest
```

重点确认：

```text
boot_media=emmc
uboot_mmc_dev=1
linux_root_dev=/dev/mmcblk1p2
```

eMMC 镜像和 SD 镜像的分区布局很像，但启动参数不是一回事。这里必须是 `mmc 1` 和 `/dev/mmcblk1p2`。

## 确认临时 U-Boot 是新的

UUU 加载的是：

```text
out/release-latest/uboot/u-boot-dtb.imx
```

如果你刚改过 U-Boot 的 `bootcmd_mfg`，要先重新构建 U-Boot。否则 UUU 跑起来的还是旧环境，可能会掉进旧的 `fastboot 0` 流程。

当然，现场已经是旧环境也不是完全没救。只要还能进 U-Boot 命令行，或者旧 U-Boot 里还有 `ums` 命令，就可以先把 eMMC 暴露出来，手动热更新 boot 分区里的内核/设备树，再把新的 `u-boot-dtb.imx` 写回 raw U-Boot 区域。

这里一定要分清楚两件事：

```text
zImage / imx6ull-aes.dtb  -> boot 分区里的普通文件
u-boot-dtb.imx            -> eMMC 起始区域的 raw bootloader，偏移 1 KiB
```

也就是说，把 `u-boot-dtb.imx` 拷进 boot 分区只是“放了一个文件”，板子下次上电不会自动从这个文件启动。真正热更新 U-Boot，还要执行后面的 raw 写入步骤。

可以用 `strings` 粗看一下镜像里有没有 UMS 命令：

```bash
strings out/release-latest/uboot/u-boot-dtb.imx | grep -E 'bootcmd_mfg|ums 0 mmc'
```

期望能看到类似：

```text
bootcmd_mfg=... mmc dev ${emmc_dev}; ums 0 mmc ${emmc_dev};
```

这一步不是严格校验，只是一个很实用的现场检查。至少能避免“我以为烧的是新 U-Boot，其实 UUU 还在跑旧镜像”。

## 旧 U-Boot 下的热更新方法

这节适合这种情况：板子里现在跑的是旧 U-Boot，`bootcmd_mfg` 还不对，没法优雅地自动进入 UMS，但你还能进 U-Boot 命令行。

先在 U-Boot 里手动暴露 eMMC：

```text
mmc dev 1
ums 0 mmc 1
```

回到主机，先确认新增的整盘设备。还是老规矩，进入 UMS 前后各看一次：

```bash
lsblk
```

假设新增设备是 `/dev/sdX`。如果系统自动挂载了 boot 分区，可以直接用文件管理器替换文件；如果没有自动挂载，就手动挂载：

```bash
sudo mkdir -p /mnt/imx6ull-emmc-boot
sudo mount /dev/sdX1 /mnt/imx6ull-emmc-boot
```

替换 boot 分区里的内核、设备树，并顺手放一份新的 U-Boot 文件进去：

```bash
sudo cp out/release-latest/linux/arch/arm/boot/zImage \
  /mnt/imx6ull-emmc-boot/zImage

sudo cp out/release-latest/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb \
  /mnt/imx6ull-emmc-boot/imx6ull-aes.dtb

sudo cp out/release-latest/uboot/u-boot-dtb.imx \
  /mnt/imx6ull-emmc-boot/u-boot-dtb.imx

sync
```

如果这个 boot 分区里还有 `/boot/` 目录，也可以同步放一份，方便兼容不同启动命令：

```bash
sudo mkdir -p /mnt/imx6ull-emmc-boot/boot
sudo cp out/release-latest/linux/arch/arm/boot/zImage \
  /mnt/imx6ull-emmc-boot/boot/zImage

sudo cp out/release-latest/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb \
  /mnt/imx6ull-emmc-boot/boot/imx6ull-aes.dtb

sync
```

卸载分区：

```bash
sudo umount /mnt/imx6ull-emmc-boot
```

到这里，内核和设备树已经更新了，但 U-Boot 还没有真正更新。接下来有两种写 raw U-Boot 的办法。

第一种是在主机侧直接对 UMS 暴露出来的整盘设备写 raw 区域：

```bash
sudo dd if=out/release-latest/uboot/u-boot-dtb.imx \
  of=/dev/sdX \
  bs=1K \
  seek=1 \
  conv=notrunc,fsync

sync
```

这条命令对应镜像构建脚本里的动作：从整盘偏移 `1 KiB` 处写入 `u-boot-dtb.imx`。`of=` 必须是整盘设备 `/dev/sdX`，不是 `/dev/sdX1`。

第二种是先把 `u-boot-dtb.imx` 放进 boot 分区，再回到 U-Boot 里从 boot 分区加载它，然后写到 eMMC raw 区域。先在主机算一下需要写多少个 512 字节块：

```bash
size=$(stat -c%s out/release-latest/uboot/u-boot-dtb.imx)
printf 'filesize=%d bytes, block_count=0x%x\n' \
  "${size}" \
  "$(( (size + 511) / 512 ))"
```

它会输出类似：

```text
filesize=786432 bytes, block_count=0x600
```

回到 U-Boot，执行下面这组命令。最后一个参数要换成你刚才算出来的 `block_count`：

```text
mmc dev 1
ext4load mmc 1:1 ${loadaddr} /u-boot-dtb.imx
mmc write ${loadaddr} 0x2 0x600
```

这里的 `0x2` 是写入起始块号。因为 raw U-Boot 偏移是 `1 KiB`，而 eMMC 块大小按 `512` 字节算：

```text
1 KiB / 512 = 2
```

最后断电重启，重新进 U-Boot 看环境：

```text
printenv bootcmd_mfg
```

如果能看到 `ums 0 mmc 1`，说明新的 U-Boot 默认环境已经生效。

## 通过 UUU 进入 UMS

让板子进入 USB SDP / mfgtools 启动模式，接好 USB 线，然后在项目根目录执行：

```bash
sudo uuu tools/uuu/imx6ull-aes-ums.lst
```

如果主机权限已经配置好，也可以不加 `sudo`。

正常流程里，UUU 把 U-Boot 下载到 RAM，U-Boot 检测到制造模式启动后会执行：

```text
mmc dev 1
ums 0 mmc 1
```

这时主机上再看块设备：

```bash
lsblk
```

你应该能看到一个新增的整盘设备。它可能是 `/dev/sdb`、`/dev/sdc`，也可能在 WSL/USB 转发环境里表现得更绕一点。判断方法还是一样：运行 UUU 前看一次 `lsblk`，进入 UMS 后再看一次，新增的整盘设备才是目标。

## 把 eMMC 镜像写进 UMS 设备

假设新增设备是 `/dev/sdX`，先卸载它可能被自动挂载的分区：

```bash
sudo umount /dev/sdX1
sudo umount /dev/sdX2
```

然后写入整盘镜像：

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-emmc.img \
  of=/dev/sdX \
  bs=4M \
  status=progress \
  conv=fsync
```

写完同步：

```bash
sync
```

这里还是那句话：`of=` 必须是整盘设备。不要只往弹出来的盘符里复制 `zImage`、DTB，也不要写到 `/dev/sdX1`。完整镜像里包含 raw U-Boot、MBR 分区表、boot 分区和 rootfs 分区；文件复制只会更新分区里的普通文件，补不上 raw 区域。

如果用 Rufus，也选择 UMS 暴露出来的 eMMC 设备，并使用 DD/raw image 模式写：

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

## 切回 eMMC 启动

写入完成后，安全弹出或确保 `sync` 完成。然后断电，把启动模式切回 eMMC，再上电。

进入 U-Boot 后可以先检查：

```text
mmc list
mmc dev 1
mmc part
ext4ls mmc 1:1 /
ext4ls mmc 1:2 /
```

如果环境里有 `emmcbootaes`：

```text
run emmcbootaes
```

手动启动兜底：

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk1p2 rootfstype=ext4 rootwait rw
ext4load mmc 1:1 ${loadaddr} /zImage
ext4load mmc 1:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

这里最关键的是：

```text
mmc 1:1
root=/dev/mmcblk1p2
```

如果串口里显示内核加载成功，但挂 rootfs 失败，第一眼就看这个 root 参数。

## UMS 流程里最容易混的两块 U-Boot

这个地方很容易绕，我们单独说清楚。

UUU 下载到 RAM 的 U-Boot，只负责临时把 eMMC 暴露出来。它不会自动写进 eMMC。

真正被烧进 eMMC 的 U-Boot，是 `imx6ull-aes-emmc.img` 里 1 KiB 偏移处的那份 `u-boot-dtb.imx`。

所以如果你改了 U-Boot，至少要确认两件事：

第一，`out/release-latest/uboot/u-boot-dtb.imx` 已经重新生成。否则 UUU 临时启动的 U-Boot 可能还是旧的。

第二，`out/release-latest/images/imx6ull-aes-emmc.img` 已经重新生成。否则写进 eMMC 的 raw U-Boot 仍然是旧的。

这也是 bring-up 里专门记下来的 caveat：临时 UUU U-Boot 只在 RAM 里跑，不能代表 eMMC 已经更新。

## 常见现象

### UUU 找不到 u-boot-dtb.imx

看 `tools/uuu/imx6ull-aes-ums.lst` 里的路径。当前应为：

```text
SDP: boot -f ../../out/release-latest/uboot/u-boot-dtb.imx
```

同时确认文件存在：

```bash
ls -lh out/release-latest/uboot/u-boot-dtb.imx
```

### U-Boot 没有进入 UMS，而是进了 fastboot

这通常说明 `bootcmd_mfg` 还是旧的。进入 U-Boot 后可以看：

```text
printenv bootcmd_mfg
```

期望里面有：

```text
ums 0 mmc 1
```

如果还是 `fastboot 0`，就需要更新板级默认环境，重新构建 U-Boot，并重新生成 eMMC 镜像。

### 主机看不到新增块设备

先确认 U-Boot 里 `ums 0 mmc 1` 已经跑起来。如果 U-Boot 卡在命令行，可以手动执行：

```text
mmc dev 1
ums 0 mmc 1
```

主机侧再看：

```bash
lsblk
dmesg | tail -40
```

如果仍然没有新增设备，就回到 USB 线、板卡 USB 口、虚拟机或 WSL USB 转发这些外部因素上排查。

### eMMC 启动时 VFS 找不到 root

eMMC 流程应该是：

```text
root=/dev/mmcblk1p2
```

如果实际板卡枚举和项目约定不一致，可以临时试一下：

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw
run emmcbootaes
```

但这只能作为现场判断，不建议长期靠猜设备号。最终还是要把项目里的镜像生成参数、U-Boot 环境和板卡实际枚举统一起来。

## 下一步

到这里，SD 和 eMMC 两条烧录路径都走通了。后面再遇到启动问题，就可以按层次拆：镜像 manifest、主机写盘设备、U-Boot 能不能读 boot 分区、Linux root 参数是否匹配。

后续现场操作时，命令速查可以看：[烧录命令速查](../commands/04_flashing_commands.md)。
