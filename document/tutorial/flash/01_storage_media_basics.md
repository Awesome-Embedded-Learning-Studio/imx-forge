---
title: 存储介质基础
---

# 存储介质基础 - 先分清 SD、eMMC 和块设备

## 前言：别急着烧，先认清“盘”

很多人第一次看到镜像烧录教程时，卡住的地方不是命令本身。

命令其实就那么几条：`lsblk`、`dd`、`sync`，或者 U-Boot 里的 `mmc list`、`mmc part`。但是我们有时候还是会难以理解烧录过程重出现的问题。

随意一些例子：

- SD 卡是什么？你很清楚这是一个存储设备
- eMMC 又是什么？你很清楚这是一个存储设备，但是怎么正点原子或者一些厂商告诉你，你要用mfgtools了？怎么跟SD卡的不太一样？
- /dev/sdb 和 /dev/sdb1 有什么区别？
- U-Boot 里的 mmc 0 为什么到了 Linux 里又变成 /dev/mmcblk0？

如果这些概念没分清楚，后面看到“把完整镜像写入整盘设备”这句话，就很容易只记住 `dd`，却不知道为什么 `of=` 不能写成分区。

所以这一章先不烧录。我们只做一件事：把板子上的存储介质和主机看到的块设备认清楚。

## SD 卡和 eMMC：一个能拔，一个焊死

在 IMX6ULL 这类板子上，最常见的两种启动存储是 SD 卡和 eMMC。

SD 卡大家比较熟。它是一张可以拔下来的卡。你可以把它插到读卡器里，主机就能像看到一个 U 盘一样看到它。烧录 SD 镜像时，主机直接对这张卡写数据。

eMMC 则不一样。它是一颗焊在板子上的存储芯片，外形上更像板子的一部分。你不能把 eMMC 拔下来插进电脑。想往 eMMC 里写镜像，通常要借助板子自己：让板子通过 USB 暂时把 eMMC 暴露给主机。这也就是我们说的UMS传递烧录。

后面讲 UUU + UMS 的时候，本质上就是在解决“eMMC 不能拔下来”这个问题。

## 块设备是什么

Linux 里把磁盘、U 盘、SD 卡、通过 UMS 暴露出来的 eMMC 这类东西，都看成块设备。

所谓块设备，可以简单理解成：一块可以按扇区读写的存储空间。它不像普通文件那样以“文件名”为第一视角，而是以“第几个字节、第几个扇区”为第一视角。

在主机上看块设备，最常用的是：

```bash
lsblk
```

你可能会看到这样的输出：

```text
sdb      8:16   1  29.7G  0 disk
├─sdb1   8:17   1    64M  0 part
└─sdb2   8:18   1   512M  0 part
```

这里先解释一下“分区”。一整块盘可以被切成几段相对独立的区域，每一段就叫一个分区。你可以把它想成一本厚笔记本：整本笔记本是 `sdb`，前面几十页专门放启动文件，后面几百页专门放根文件系统。每一段页码范围，就是一个分区。

Linux 不会只给整本笔记本起名字，它也会给每个分区起名字。所以 `lsblk` 里 `TYPE` 为 `disk` 的是整盘，`TYPE` 为 `part` 的就是分区。

这里 `sdb` 是整盘设备，`sdb1` 和 `sdb2` 是这块盘上的两个分区。

换成路径就是：

```text
/dev/sdb   -> 整张盘
/dev/sdb1  -> 第 1 个分区
/dev/sdb2  -> 第 2 个分区
```

这不是名字长短的问题，而是层级不同。

## 整盘设备和分区设备

完整镜像必须写到整盘设备。这句话很重要，值得单独放一遍：完整镜像写整盘，不写分区。

为什么？

因为我们生成的 `.img` 不是一个“boot 分区文件系统”，也不是一个“rootfs 文件系统”。它是一整块盘的字节布局，里面已经包含：

```text
raw U-Boot 区域
MBR 分区表
boot 分区
rootfs 分区
```

如果你把它写到 `/dev/sdb`，意思是“从整张 SD 卡的第 0 字节开始，把整盘布局写进去”。这是对的。

如果你把它写到 `/dev/sdb1`，意思就变成“把整盘布局塞进第 1 个分区里面”。这样分区表会跑到分区内部，raw U-Boot 也不在 ROM Code 期待的位置，板子自然很难启动。

所以后面看到类似命令时：

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-sd.img of=/dev/sdX bs=4M
```

`/dev/sdX` 代表的是例子里的整盘设备，不是 `/dev/sdX1`。

## 为什么有时是 /dev/sdX，有时是 /dev/mmcblk0

主机上不同设备会有不同命名。

USB 读卡器、U 盘、通过 UMS 暴露出来的设备，常见名字是：

```text
/dev/sdb
/dev/sdc
/dev/sdd
```

它们的分区通常是：

```text
/dev/sdb1
/dev/sdb2
```

而板子自己运行 Linux 后，SD/eMMC 通常会叫：

```text
/dev/mmcblk0
/dev/mmcblk1
```

对应分区会多一个 `p`：

```text
/dev/mmcblk0p1
/dev/mmcblk0p2
/dev/mmcblk1p1
/dev/mmcblk1p2
```

这里的 `p` 只是命名格式的一部分。它表示这是 `mmcblk0` 这个整盘设备上的第几个分区。

所以不要把 `/dev/sdb1` 和 `/dev/mmcblk0p1` 理解成两套不同规则。它们都在表达：

```text
整盘设备 + 分区编号
```

只是设备类型不一样，名字长得不一样。

## U-Boot 的 mmc 0/1 和 Linux 的 /dev/mmcblk0/1

还有一个容易绕的地方：U-Boot 里的 `mmc 0`、`mmc 1`，和 Linux 里的 `/dev/mmcblk0`、`/dev/mmcblk1`，不是同一个命名系统。

U-Boot 在自己的驱动模型里给 MMC 设备编号。Linux 启动后，又由 Linux 内核按自己的枚举顺序创建设备名。

在当前 IMX-Forge 板卡约定里，我们使用这套映射：

| 目标介质 | U-Boot 里 | Linux 里 |
| --- | --- | --- |
| SD | `mmc 0` | `/dev/mmcblk0p2` |
| eMMC | `mmc 1` | `/dev/mmcblk1p2` |

这里的 `/dev/mmcblk0p2` 和 `/dev/mmcblk1p2` 指的是 rootfs 分区，也就是第 2 个分区。

不过这件事不要盲信。不同板子、不同 U-Boot 配置、不同接线，枚举顺序都可能变。教程后面会反复提醒：如果你不确定，先在 U-Boot 里看：

```text
mmc list
mmc dev 0
mmc part
mmc dev 1
mmc part
```

这些命令不会写存储，只是观察设备。

## 在主机上怎么观察

主机侧最实用的办法是“前后对比”。

插入 SD 卡前看一次：

```bash
lsblk
```

插入 SD 卡后再看一次：

```bash
lsblk
```

新增出来的那块 `disk`，才是你的 SD 卡。

如果进入 UMS 前后对比，也一样：

```bash
lsblk
```

让板子进入 UMS 后再执行：

```bash
lsblk
```

新增出来的整盘设备，就是板子借给主机的 eMMC。

这里最怕的是凭记忆猜 `/dev/sdb`。今天它可能是 SD 卡，明天插了另一个 U 盘，它就可能变成 `/dev/sdc`。`dd` 不会替你判断对错，所以人要先判断。

## 在 U-Boot 里怎么观察

U-Boot 里常用这几条：

```text
mmc list
mmc dev 0
mmc part
mmc dev 1
mmc part
```

`mmc list` 看 U-Boot 当前识别到了哪些 MMC 设备。

`mmc dev 0` 是选择第 0 个 MMC 设备。选择之后再 `mmc part`，就能看这个设备上有没有分区表。

如果你已经烧了镜像，还可以继续看文件：

```text
ext4ls mmc 0:1 /
ext4ls mmc 0:2 /
```

这里 `mmc 0:1` 的意思是：

```text
U-Boot 的第 0 个 MMC 设备上的第 1 个分区
```

这和 Linux 里的 `/dev/mmcblk0p1` 很像，但仍然要记住：它们是两个阶段里的两套名字。

## UMS 是什么先有个印象

UMS 全称可以理解成 USB Mass Storage。这里不用先背术语，只要知道它做了什么：

```text
板子把自己的 eMMC 暂时伪装成一个 USB 存储设备，让主机来写。
```

也就是说，eMMC 本来焊在板子上，主机摸不到。进入 UMS 后，主机的 `lsblk` 会突然多出一块盘。你对这块新增的整盘设备写镜像，数据最终会落到板子的 eMMC 里。

后面的 eMMC 烧录章节会详细讲 UUU 怎么把 U-Boot 跑进 RAM，U-Boot 又怎么执行 `ums 0 mmc 1`。现在先知道这个目的就够了：

```text
UUU/UMS 不是另一种镜像格式，它只是让主机能够访问板上的 eMMC。
```

## 小结

这一章只讲了一个基础问题：镜像到底要写到哪里。

先把几个关键词收一下：

- SD 卡可以拔下来，用读卡器写。
- eMMC 焊在板子上，通常通过 UUU/UMS 暴露给主机写。
- `/dev/sdX` 或 `/dev/mmcblk0` 是整盘设备。
- `/dev/sdX1` 或 `/dev/mmcblk0p1` 是分区设备。
- 完整 `.img` 要写整盘，不写分区。
- U-Boot 的 `mmc 0/1` 和 Linux 的 `/dev/mmcblk0/1` 是两套命名，需要现场确认。

下一章我们继续往下拆：既然 `.img` 是一整块盘，那它里面的分区表、boot 分区、rootfs 分区和普通文件到底是什么关系。

**下一步：** 阅读 [02_image_partition_filesystem_basics.md](02_image_partition_filesystem_basics.md)，先把 `.img`、分区和文件系统这几个概念拆开。
