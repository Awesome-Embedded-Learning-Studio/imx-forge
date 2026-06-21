---
title: 镜像、分区与文件系统
---

# 镜像、分区和文件系统 - `.img` 到底是什么

## 前言：它不是一个文件夹压缩包

很多人第一次接触 `.img` 时，会下意识把它当成压缩包。这也很正常。因为我们平时看到 `.zip`、`.tar.gz`，里面都是一堆文件；看到 `rootfs.tar.gz`，也确实可以解开得到一个根文件系统目录。

但这里的 `imx6ull-aes-sd.img` 或 `imx6ull-aes-emmc.img` 不是这种东西。

它不是“把 boot 目录和 rootfs 目录压成一个包”。它更像是把一整张 SD 卡从第 0 字节开始复制成了一个普通文件。

换句话说：

```text
.tar.gz 关心的是文件。
.img 关心的是整块盘的字节布局。
```

理解了这一点，后面很多命令就不奇怪了。`sfdisk -d xxx.img` 能看分区表，是因为这个 `.img` 里面真的有分区表。`dd` 能把它写进 SD 卡，是因为它本来就是按整盘布局生成的。

如果你还不确定 `.img`、`.iso`、`.tar.gz`、`rootfs.ext4` 这些常见后缀彼此什么关系，可以配合 [常见打包与镜像格式](03_common_image_and_archive_formats.md) 横向对比着看。

## 从整盘到文件：中间有几层

我们先用一个层级把概念摆正：

```text
整盘设备
└── 分区表
    ├── 分区 1
    │   └── 文件系统
    │       ├── zImage
    │       └── imx6ull-aes.dtb
    └── 分区 2
        └── 文件系统
            ├── /bin
            ├── /etc
            └── /lib
```

这几层不要混：

整盘设备是一块完整存储，例如一张 SD 卡，或者一颗 eMMC。分区表记录这块盘上有哪些分区，每个分区从哪里开始，到哪里结束。

分区是一段连续的存储范围。文件系统是在分区里面组织文件的一套格式，比如 ext4。文件才是我们平时能 `ls`、`cp`、`cat` 的东西，比如 `zImage`、`.dtb`、`/etc/inittab`。

如果把这几层混了，就会出现很典型的误会：以为把 `u-boot-dtb.imx` 拷进 boot 分区，板子下次上电就会从它启动。实际上不会，因为项目里的 U-Boot 不属于 boot 分区里的普通文件。

## MBR 是做什么的

MBR 可以先简单理解成一种老派但够用的分区表格式。

它放在整盘的开头，告诉系统：

```text
第 1 个分区从哪个扇区开始，有多大
第 2 个分区从哪个扇区开始，有多大
每个分区是什么类型
哪个分区带 bootable 标记
```

当前镜像脚本会写一个 DOS/MBR 风格的分区表。你用下面命令看镜像：

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-emmc.img
```

能看到类似：

```text
label: dos
unit: sectors

...img1 : start=32768, size=131072, type=83, bootable
...img2 : start=163840, size=..., type=83
```

这里 `start=32768` 的意思是第 1 个分区从第 32768 个扇区开始。一个扇区按 512 字节算，正好是 16 MiB。

这就是为什么 `.img` 可以被 `sfdisk` 读懂。它虽然是一个普通文件，但文件开头的内容按整盘格式写好了。

## boot 分区和 rootfs 分区

当前镜像里有两个分区。

第 1 个是 boot 分区。它放启动 Linux 需要的普通文件：

```text
zImage
imx6ull-aes.dtb
boot.cmd
```

`zImage` 是 Linux 内核镜像。`.dtb` 是设备树，告诉内核这块板子的硬件长什么样。`boot.cmd` 记录脚本为这个镜像生成的启动命令。

第 2 个是 rootfs 分区。Linux 内核启动后，会把它挂载成 `/`：

```text
/
├── bin
├── etc
├── lib
└── ...
```

这就是用户空间。BusyBox、init 脚本、配置文件、你后续放进去的应用，都会在 rootfs 里。

所以启动链路里有一个很自然的顺序：

```text
U-Boot 读取 boot 分区里的 zImage 和 DTB
Linux 内核启动
Linux 挂载 rootfs 分区作为根目录
进入用户空间
```

## 文件系统是什么

分区只是“一段空间”。要在这段空间里放文件，还需要文件系统。

当前脚本把 boot 分区和 rootfs 分区都做成 ext4。这样 U-Boot 可以用 `ext4load` 读取内核和设备树，Linux 也能直接挂载 rootfs。

ext4 文件系统负责回答这些问题：

```text
这个目录里有哪些文件？
这个文件的数据块在哪里？
这个文件权限是什么？
软链接指向哪里？
```

也就是说，`zImage` 能以文件形式存在，是因为 boot 分区里面有 ext4 文件系统。`/etc/inittab` 能被 `cat`，也是因为 rootfs 分区里面有 ext4 文件系统。

脚本用 `mke2fs -d` 生成 ext4 文件系统镜像，这样可以把一个目录直接灌进文件系统里，不需要 `sudo mount`。后面脚本拆解章节会细讲这件事。

## U-Boot raw 区域不是普通文件

现在回到最容易混的地方：U-Boot。

项目里的 `u-boot-dtb.imx` 不放在 boot 分区里作为普通文件启动。镜像脚本会把它写到整盘偏移 1 KiB 的位置：

```text
offset 1 KiB -> u-boot-dtb.imx
```

这段区域在分区前面，属于 raw disk 区域。

raw 的意思可以先理解成：不经过文件系统，直接按字节或扇区写。这里没有文件名，也没有目录。你不能在 Linux 挂载 boot 分区后 `ls` 出“1 KiB 偏移处的 U-Boot”。它不在文件系统里。

这就是为什么我们要区分：

```text
zImage / DTB：boot 分区里的普通文件
u-boot-dtb.imx：整盘 raw 区域里的启动镜像
```

把 `zImage` 拷到 boot 分区，是文件操作。

把 `u-boot-dtb.imx` 写到 1 KiB，是 raw 写盘操作。

这两件事不在同一层。

## 为什么 sfdisk 能看 .img

`sfdisk` 不是只能看真实磁盘。只要一个文件的内容按“整盘布局”组织，它也能读。

所以这条命令：

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-sd.img
```

本质上是在问：

```text
这个文件开头有没有我认识的分区表？
如果有，每个分区从哪里开始，有多大？
```

它不会挂载分区，也不会读 ext4 里的文件。它只是读分区表。

如果你想看文件系统层面的信息，可以用更偏文件系统的工具，比如：

```bash
dumpe2fs -h boot.ext4
debugfs -R 'ls -l /' boot.ext4
```

这些命令的层次就不一样了。`sfdisk` 看整盘分区表，`dumpe2fs` 和 `debugfs` 看 ext4 文件系统。

## 为什么完整镜像要写整盘

现在就能解释上一章那句话了。

完整 `.img` 里面同时包含：

```text
整盘前面的 raw U-Boot
整盘前面的 MBR 分区表
第 1 分区的 ext4 文件系统
第 2 分区的 ext4 文件系统
```

所以它必须从目标设备的第 0 字节开始写。

写到整盘设备：

```text
of=/dev/sdb
```

意思是把这些层级完整放回一张真实 SD 卡。

写到分区设备：

```text
of=/dev/sdb1
```

意思是把整盘布局塞进第 1 个分区内部。这样外层分区表、raw U-Boot 位置都不对。

这也是为什么很多教程会反复强调：看清楚 `lsblk`，确认目标是 `disk`，不是 `part`。

## 小结

这一章把 `.img` 拆成了几层：

```text
整盘
→ 分区表
→ 分区
→ 文件系统
→ 文件
```

`zImage`、DTB、rootfs 里的内容，都是文件系统里的普通文件。U-Boot 则写在整盘前面的 raw 区域，不属于 boot 分区。

下一章我们先把常见的打包和镜像格式横向梳理一遍，把 `.img`、`.iso`、`.tar.gz`、`rootfs.ext4` 这些后缀的关系理顺。之后再进入 i.MX6ULL 的启动链路。

**下一步：** 阅读 [03_common_image_and_archive_formats.md](03_common_image_and_archive_formats.md)，把常见格式分门别类。
