# 镜像大小与使用 - 留多少空间才合适

## 前言：镜像不是越小越好，也不是越大越好

做完完整镜像之后，马上会遇到一个很现实的问题：这个 `.img` 到底应该多大？

一开始我也倾向于让它越小越好。镜像小，生成快，复制快，看起来也干净。可是上板之后你很快会发现，如果 rootfs 分区几乎没有剩余空间，系统虽然能启动，但你连临时改个配置、写个日志、拷个测试程序都不舒服。

反过来，如果每次都生成一个很大的镜像，开发阶段又会浪费很多时间。你只是改了一个 DTB，却要复制几个 GiB 的文件，这也不划算。

所以脚本提供了三种思路：

- 默认动态大小：够用就好
- 固定总镜像大小：交付和上板写文件更方便
- 固定 rootfs 分区大小：只关心根分区容量

这章我们把这几种用法讲清楚。

## 默认模式：脚本自己算

最简单的命令就是：

```bash
scripts/image_builder/build_imx6ull_image.sh
```

它默认等价于：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-latest \
  --device-tree=imx6ull-aes \
  --boot-media=emmc
```

默认输出是：

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

在这个模式下，rootfs 分区大小由脚本自动计算：

```text
rootfs 分区 = rootfs 实际占用 + 25% + 64 MiB
```

然后总镜像大小再加上：

```text
16 MiB 前置空间 + boot 分区 + 8 MiB 尾部余量
```

这个模式适合日常构建。它不会生成特别夸张的大文件，同时也不会让 rootfs 卡得太紧。

## 固定总镜像大小：上板后想直接写文件

如果你希望烧录进去以后，根文件系统里有比较明确的空余空间，可以指定总镜像大小：

```bash
scripts/image_builder/build_imx6ull_image.sh --image-size-mb=1024
```

这表示生成一个 1024 MiB 的镜像。脚本会把 boot 分区和前置空间扣掉，剩下的都给 rootfs。

这点很重要：多出来的空间不是镜像末尾的“空白地带”，而是 rootfs 分区里的可用空间。Linux 启动后，你在 `/` 下面写文件，能直接用到这些空间。

如果你每次都想生成固定大小，可以用环境变量：

```bash
DEFAULT_IMAGE_SIZE_MB=2048 scripts/image_builder/build_imx6ull_image.sh
```

这个模式适合：

- 做相对稳定的交付镜像
- 希望多次构建出来的镜像大小一致
- 上板后要写日志、配置或测试程序
- 不想每次都因为 rootfs 内容变化导致镜像大小波动

## 固定 rootfs 分区大小：只管根分区

有时候你不关心整盘镜像多大，只想说 rootfs 分区就给 1024 MiB。

这时用：

```bash
scripts/image_builder/build_imx6ull_image.sh --rootfs-size-mb=1024
```

最终镜像会在这个基础上，再加上前置空间、boot 分区和尾部余量。

注意，`--rootfs-size-mb` 和 `--image-size-mb` 不能同时用。一个控制 rootfs，一个控制整盘，两个一起写只会让意图变乱。

## SD 镜像和 eMMC 镜像怎么生成

生成 eMMC 镜像：

```bash
scripts/image_builder/build_imx6ull_image.sh --boot-media=emmc
```

输出：

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

生成 SD 镜像：

```bash
scripts/image_builder/build_imx6ull_image.sh --boot-media=sd
```

输出：

```text
out/release-latest/images/imx6ull-aes-sd.img
```

这两个镜像的布局很像，但启动命令不一样：

| 镜像 | U-Boot 加载 | Linux root |
| --- | --- | --- |
| SD | `ext4load mmc 0:1` | `/dev/mmcblk0p2` |
| eMMC | `ext4load mmc 1:1` | `/dev/mmcblk1p2` |

所以生成之后先别急着烧录，先看一眼 manifest，确认自己拿的是对的镜像。

::: tip v1.0.0 验证基线
`imx6ull-aes-sd.img` 和 `imx6ull-aes-emmc.img` 两条启动路径，已由仓库主作者 CharlieChen114514 在正点原子阿尔法 i.MX6ULL 开发板上实验通过。后续回归测试以 manifest 中的 `boot_media`、`uboot_mmc_dev` 和 `linux_root_dev` 为第一检查点。
:::

## 用 `release-all.sh` 只跑镜像阶段

如果前面的 U-Boot、Linux、BusyBox 和 rootfs 都已经构建好了，可以只跑 Stage 5：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media emmc
scripts/release-all.sh --continue --stage 5 --boot-media sd
```

也可以一次生成两个：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media both
```

如果你只是调镜像大小，直接跑 `build_imx6ull_image.sh` 更快；如果你希望走完整 release 脚本，就用 Stage 5。

## 给历史 release 生成镜像

默认 release 目录是：

```text
out/release-latest
```

如果你想给历史目录补一个镜像：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-20260608-121544 \
  --boot-media=sd
```

镜像会生成到对应 release 目录下：

```text
out/release-20260608-121544/images/
```

这对回归测试很有用。你不必重新构建整套系统，只要那个 release 目录里的 U-Boot、内核、DTB 和 rootfs 都还在，就可以重新打包镜像。

## 使用其他设备树

默认设备树是：

```bash
--device-tree=imx6ull-aes
```

这时脚本会去 release 目录里找：

```text
linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
```

如果你手里有一个单独编出来的 DTB，也可以直接传路径：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --device-tree=out/driver_artifacts/example/alpha-board/imx6ull-aes-example.dtb
```

这对于驱动实验很方便。比如你为某一节教程改了设备树，不想覆盖默认 release 产物，就直接把实验 DTB 打进镜像。

## 生成后先检查什么

第一步，看文件大小和附属文件：

```bash
ls -lh out/release-latest/images/imx6ull-aes-emmc.img*
```

第二步，看 manifest：

```bash
sed -n '1,40p' out/release-latest/images/imx6ull-aes-emmc.img.manifest
```

重点看这几个字段：

```text
boot_media=emmc
uboot_mmc_dev=1
linux_root_dev=/dev/mmcblk1p2
boot_partition_start_sector=32768
rootfs_partition_start_sector=163840
```

第三步，看分区表：

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-emmc.img
```

这些检查都不会修改镜像。养成这个习惯很有用，因为很多启动问题在烧录之前就能发现。

## 常见错误怎么处理

### 找不到 U-Boot

如果看到：

```text
U-Boot image not found: .../uboot/u-boot-dtb.imx
```

先别怀疑脚本。它只是告诉你 release 目录里的 U-Boot 产物不存在。

检查一下：

```bash
ls out/release-latest/uboot/u-boot-dtb.imx
```

如果没有，就先构建 U-Boot，或者确认 `--release-dir` 是否指错。

### 找不到 DTB

如果看到：

```text
DTB not found: .../imx6ull-aes.dtb
```

先查当前 release 里到底有哪些 DTB：

```bash
find out/release-latest/linux/arch/arm/boot/dts -name 'imx6ull*.dtb'
```

有时候问题只是名字不一致，比如你传的是 `imx6ull-aes`，但实际生成的是某个实验用 DTB。

### 固定镜像太小

如果看到：

```text
--image-size-mb (...) is too small
```

说明你给的总镜像大小连当前 rootfs 都装不下。要么增大 `--image-size-mb`，要么检查 rootfs 里是不是混进了不该打包的大文件。

可以先看 rootfs 大小：

```bash
du -sh out/release-latest/rootfs
```

### root 设备不对

如果内核启动时报：

```text
VFS: Cannot open root device
```

优先检查 manifest：

```bash
sed -n '1,40p' out/release-latest/images/imx6ull-aes-emmc.img.manifest
```

确认：

```text
boot_media=
linux_root_dev=
```

SD 应该是 `/dev/mmcblk0p2`，eMMC 应该是 `/dev/mmcblk1p2`。这两个混了，启动失败很正常。

## 后续烧录资料

镜像确认没问题以后，就可以进入真实烧录流程：

- [SD 卡烧录实战](08_sd_card_flashing.md)
- [UUU + UMS eMMC 烧录实战](09_uuu_ums_emmc_flashing.md)

如果要看当时 bring-up 的原始记录，可以继续翻这两篇笔记：

- [SD 卡烧录 Bring-up 笔记](../../notes/2026-06-08-sd-card-flashing-bringup.md)
- [UUU + UMS + eMMC Bring-up 笔记](../../notes/2026-06-08-uuu-ums-emmc-bringup.md)

命令速查见：[镜像构建命令速查](../commands/01_image_builder_commands) 和 [烧录命令速查](../commands/04_flashing_commands.md)。

**下一步：** 如果你已经理解镜像大小和介质参数，可以去 [命令速查](../commands/) 里复制常用命令。
