# 脚本设计拆解 - Bash 怎么把零件拼成一块盘

## 前言：脚本不是魔法，只是把手工步骤固定下来

如果你第一次打开 `scripts/image_builder/build_imx6ull_image.sh`，可能会觉得它做的事情有点多：解析参数、找文件、算大小、做 ext4、写分区表、写 U-Boot、生成 manifest。

但别被这些函数名吓住。这个脚本的核心思路其实很简单：

**把我们原本手工烧录前要做的准备工作，变成一套稳定的、可重复执行的流程。**

我们不计划发明新的启动方式（没有任何收益，咱们是工程师，先把问题搞定了，再把问题解决优雅，是一种很常见的处理问题的方式，尽管往往我们不会做第二步（笑）），也不是在改变 U-Boot 或 Linux 的规则。它只是按照上一章的布局，把 U-Boot、内核、设备树和 rootfs 放到该放的位置。

我们这一章就顺着脚本的执行顺序走一遍，看它每一步为什么这么写。

## 先看脚本的输入和输出

脚本默认从这里取材料：

```text
out/release-latest/
├── uboot/u-boot-dtb.imx
├── linux/arch/arm/boot/zImage
├── linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
└── rootfs/
```

然后把成品放到：

```text
out/release-latest/images/
```

默认情况下，目标介质是 eMMC，所以输出文件名是：

```text
imx6ull-aes-emmc.img
imx6ull-aes-emmc.img.manifest
imx6ull-aes-emmc.img.sha256
```

如果你指定 SD：

```bash
scripts/image_builder/build_imx6ull_image.sh --boot-media=sd
```

输出就变成：

```text
imx6ull-aes-sd.img
```

这一步看起来只是换名字，但背后会影响启动命令里的 `mmc` 设备号和 Linux 的 `root=` 参数。

## 第一步：先把用户意图问清楚

脚本一开始做的是参数解析。它支持两种写法：

```bash
--release-dir=out/release-latest
--release-dir out/release-latest
```

这些参数里，最常用的是：

| 参数 | 你在告诉脚本什么 |
| --- | --- |
| `--release-dir` | 从哪个 release 目录拿材料 |
| `--device-tree` | 使用哪个 DTB |
| `--boot-media` | 生成 SD 还是 eMMC 镜像 |
| `--image-name` | 输出文件要叫什么 |
| `--boot-size-mb` | boot 分区要多大 |
| `--rootfs-size-mb` | rootfs 分区要多大 |
| `--image-size-mb` | 整个镜像要多大 |

还有几个环境变量可以当默认值：

```bash
DEFAULT_DEVICE_TREE=imx6ull-aes
DEFAULT_BOOT_MEDIA=emmc
DEFAULT_IMAGE_SIZE_MB=1024
```

这几个环境变量适合放在 CI 或你自己的构建习惯里。比如你一直做 SD 卡镜像，就不用每次都敲 `--boot-media=sd`。

## 第二步：SD 和 eMMC 先分清楚

脚本里有一个函数叫 `resolve_boot_media`。它做的事情非常朴素：把 `sd` 和 `emmc` 翻译成启动时真正需要的设备号。

当前项目约定是：

| 参数 | U-Boot 设备 | Linux root |
| --- | --- | --- |
| `--boot-media=sd` | `mmc 0` | `/dev/mmcblk0p2` |
| `--boot-media=emmc` | `mmc 1` | `/dev/mmcblk1p2` |

这一步必须放得很早。因为后面生成 `boot.cmd`、manifest、手动启动命令，都要用这两个值。

如果用户传了一个脚本不认识的介质，比如：

```bash
--boot-media=nand
```

脚本会直接退出。这里不要“猜”。启动介质猜错了，生成出来的镜像反而更危险。

## 第三步：把材料找齐

接下来脚本进入 `resolve_artifacts`，开始检查材料。

它会找这些文件：

```text
<release>/uboot/u-boot-dtb.imx
<release>/linux/arch/arm/boot/zImage
<release>/linux/arch/arm/boot/dts/nxp/imx/<dtb>.dtb
<release>/rootfs/
```

这里有两个小设计值得注意。

第一个是路径会转成绝对路径。这样 manifest 里记录出来的内容更明确，不会因为你从不同目录运行脚本而变得含糊。

第二个是 `--device-tree` 既可以是名字，也可以是路径。

如果你写：

```bash
--device-tree=imx6ull-aes
```

脚本会去 release 的 Linux 输出目录里找：

```text
imx6ull-aes.dtb
```

如果你写：

```bash
--device-tree=/tmp/custom.dtb
```

脚本就直接使用这个文件。

这个设计对驱动教程很有用。比如你为某一章驱动实验单独编了一个 DTB，就可以直接把路径传给镜像脚本，不一定非要覆盖 release 里的默认 DTB。

## 第四步：算大小，别让文件系统装不下

镜像大小是脚本里最容易让人误会的部分。

脚本先看内核和 DTB 有多大，确保 boot 分区至少能装下它们。默认 boot 分区是 64 MiB，一般够用。如果用户把 `--boot-size-mb` 设得太小，脚本会自动往上调。

然后脚本计算 rootfs。

默认情况下，它会用：

```text
rootfs 实际占用 + 25% + 64 MiB
```

这个算法不复杂，但很实用。rootfs 不能刚刚好，刚刚好就意味着上板后很快写满；但默认也不应该动不动生成几个 GiB 的镜像。

如果你明确想要固定总镜像大小，比如 1 GiB：

```bash
scripts/image_builder/build_imx6ull_image.sh --image-size-mb=1024
```

脚本会把镜像总大小固定成 1024 MiB，然后把剩余空间分给 rootfs 分区。

这里要注意：`--rootfs-size-mb` 和 `--image-size-mb` 不能同时使用。

为什么？因为它们都在控制容量，只是角度不同。一个说“rootfs 分区要这么大”，另一个说“整块盘要这么大”。如果同时写，脚本就要替你做取舍，这种取舍不应该偷偷发生。

## 第五步：先做一个 boot-tree

在真正生成 ext4 之前，脚本会先准备一个临时目录：

```text
boot-tree/
├── zImage
├── imx6ull-aes.dtb
├── boot.cmd
└── boot/
    ├── zImage
    └── imx6ull-aes.dtb
```

`zImage` 和 DTB 都来自 release 目录。`boot.cmd` 是脚本根据介质生成的启动命令。

eMMC 镜像里的 `boot.cmd` 大概是：

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw
ext4load mmc 1:1 ${loadaddr} /zImage
ext4load mmc 1:1 ${fdt_addr_r} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr_r}
```

SD 镜像则会变成 `mmc 0:1` 和 `/dev/mmcblk0p2`。

这份 `boot.cmd` 不一定会被 U-Boot 自动执行，但它是很好的调试记录。你忘了这个镜像到底为哪个介质生成时，看它就知道。

## 第六步：用 `mke2fs -d` 做文件系统

传统做镜像时，很多人会走这条路：

```text
创建空文件 → losetup → 分区 → mount → cp → umount
```

这条路能走，但脚本化起来麻烦。尤其是 mount/umount，一旦中间失败，就容易留下脏状态。

这里脚本用了更干净的方式：先分别生成两个 ext4 文件系统镜像。

```text
boot.ext4
rootfs.ext4
```

核心命令是：

```bash
mke2fs -q -t ext4 -d "${src_dir}" -L "${label}" -m 0 -F "${fs_image}"
```

`-d "${src_dir}"` 是关键。它告诉 `mke2fs`：创建文件系统时，顺便把这个目录里的内容填进去。

这样脚本就不需要挂载文件系统，也不需要 root 权限。对构建系统来说，这是一个很舒服的选择。

## 第七步：整盘镜像登场

现在 boot.ext4 和 rootfs.ext4 都准备好了，脚本开始创建真正的 `.img`。

先用 `truncate` 做出一个指定大小的空文件：

```bash
truncate -s "${IMAGE_SIZE_MB}M" "${image}"
```

然后用 `sfdisk` 写入 MBR 分区表：

```text
start=<boot_start>, size=<boot_size>, type=83, bootable
start=<rootfs_start>, size=<rootfs_size>, type=83
```

最后用 `dd` 把三个 payload 写进去：

```bash
dd if=u-boot-dtb.imx of=image bs=1K seek=1 conv=notrunc
dd if=boot.ext4      of=image bs=512 seek=<boot_start> conv=notrunc
dd if=rootfs.ext4    of=image bs=512 seek=<rootfs_start> conv=notrunc
```

这三次写入分别对应：

```text
raw U-Boot 区域
boot 分区内容
rootfs 分区内容
```

做到这里，一个完整 raw image 就出来了。

## 第八步：manifest 是镜像说明书

脚本最后会写一个 `.manifest`。这个文件非常值得看，因为它记录了镜像到底是怎么来的。

里面会有这些信息：

```text
image=...
release_dir=...
uboot=...
kernel=...
dtb=...
rootfs=...
boot_media=emmc
uboot_mmc_dev=1
linux_root_dev=/dev/mmcblk1p2
```

还会记录分区布局：

```text
layout:
  uboot_offset_kib=1
  boot_partition_start_sector=32768
  boot_partition_size_mib=64
  rootfs_partition_start_sector=163840
```

以及手动启动命令。

这份 manifest 的价值在排错时会非常明显。比如你看到 Linux 起不来，怀疑 root 设备不对，第一件事不是重新烧录，而是先打开 manifest 看：

```text
linux_root_dev=
boot_media=
```

很多问题到这里就能对上。

`.sha256` 则是用来确认镜像复制或传输过程中没有损坏。

## 和 `release-all.sh` 的关系

你可以直接运行 image builder：

```bash
scripts/image_builder/build_imx6ull_image.sh --release-dir=out/release-latest
```

也可以让 `release-all.sh` 的 Stage 5 调它：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media emmc
scripts/release-all.sh --continue --stage 5 --boot-media sd
```

如果你正在调镜像参数，直接跑 image builder 更快；如果你想放进完整 release 流程，就走 `release-all.sh`。

## 小结

到这里，这个脚本的主线就清楚了：

```text
解析参数
→ 确认 SD/eMMC
→ 找齐 U-Boot、zImage、DTB、rootfs
→ 计算分区大小
→ 生成 boot.ext4 和 rootfs.ext4
→ 写分区表和 raw payload
→ 输出 manifest 和 sha256
```

它不是一个神秘工具，而是一份可复现的装配流程。理解这一点之后，你就可以放心地改参数、看 manifest、查分区表，而不是把镜像当成黑盒。

**下一步：** 阅读 [07_image_size_and_usage.md](07_image_size_and_usage.md)，专门处理镜像大小、SD/eMMC 参数和常见错误。
