---
title: 常见打包与镜像格式
---

# 常见打包与镜像格式 - `.img` / `.iso` / `.tar.gz` 到底谁是谁

## 前言：先把"关心什么"分清楚

上一章我们把 `.img` 拆成了整盘、分区表、分区、文件系统、文件几层。但很多读者真正卡住的，是手上这一堆后缀：

```text
imx6ull-aes-sd.img
rootfs.tar.gz
rootfs.ext4
u-boot-dtb.imx
zImage
imx6ull-aes.dtb
```

再加上平时见到的 `.iso`、`.zip`，很容易混成一锅。这一章不教命令（命令见命令速查），只做一件事：把这些常见格式按"它关心什么、在哪一层"分清楚。

判断一个格式，先问一个问题：

```text
它关心的是"文件"，还是"盘的字节布局"？
```

关心文件的，是归档（tar、zip）。关心盘布局的，是镜像（img、iso）。这是后面所有区别的根。

## 一张表先立住

| 格式 | 关心什么 | 怎么看里面的内容 | 能不能 `dd` 直接烧整盘 | 项目里的角色 |
| --- | --- | --- | --- | --- |
| `.img` | 整盘字节布局 | `sfdisk -d`、`fdisk -l`、loop 挂载 | 能，烧整盘 | 完整 SD/eMMC 镜像 |
| `.iso` | 整卷（ISO 9660） | `file`、`isoinfo`、loop 挂载 | 能，烧 U 盘 | 不用（PC 安装盘才用） |
| `rootfs.ext4` | 单个文件系统 | `dumpe2fs`、`debugfs`、`mount` | 不能，只灌进某个分区 | rootfs 分区内容 |
| `.squashfs` | 只读压缩文件系统 | `unsquashfs -l`、`mount` | 不能 | 不用（了解即可） |
| `.tar` / `.tar.gz` | 文件集合 | `tar tf`、`tar xf` | 不能 | rootfs 产物分发 |
| `.zip` | 文件集合（带压缩） | `unzip -l` | 不能 | 偶尔用 |
| `zImage` | 压缩的内核 | `file` | 不能，放 boot 分区当文件 | boot 分区内核文件 |
| `.dtb` | 设备树二进制 | `fdtdump`、`dtc -I dtb -O dts` | 不能，放 boot 分区当文件 | boot 分区设备树 |
| `u-boot-dtb.imx` | i.MX 启动镜像（带 IVT） | `file` | 不能，写到 1 KiB raw 区 | 整盘 raw 区启动镜像 |

记住一条分界线：能不能直接 `dd` 烧整盘，取决于它是不是"整盘布局"。`.img`、`.iso` 是；其余都不是。

## 整盘镜像：`.img` 和 `.iso`

### `.img`：一张盘的字节拷贝

项目里的 `imx6ull-aes-sd.img` 就是这一类。它从第 0 字节开始，按真实 SD 卡的布局写好了 raw U-Boot、MBR 分区表、两个 ext4 分区。所以它能被 `sfdisk` 读分区表，能被 `dd` 直接写回整盘。

`.img` 本身不是一个固定格式，它只是约定俗成的后缀，意思是"这里头是一份盘的镜像"。里面到底装什么文件系统，是脚本决定的——项目用的是 MBR + ext4。

### `.iso`：光盘那一套

`.iso` 也属于整盘/整卷镜像，所以它也能 `dd` 烧到 U 盘做成启动盘。你下载 Ubuntu、各种 LiveUSB，拿到的就是 `.iso`。

但它内部用的是 ISO 9660 文件系统，这是为光盘设计的那一套：

```text
.img：自定义的 MBR + ext4 布局（项目说了算）
.iso：固定的 ISO 9660 文件系统（为光盘/安装盘设计，通常只读）
```

i.MX6ULL 项目不用 `.iso`。提它，是因为它和 `.img` 长得像、都能整盘烧，但内部文件系统完全不是一回事。别看到一个能 `dd` 的镜像就以为是同一种东西。

## 文件系统镜像：`rootfs.ext4` 和 `.squashfs`

文件系统镜像比整盘镜像"小一层"。它不是整张盘，只是某一个分区的文件系统，被单独灌成了一个文件。

```text
整盘 .img
├── 分区表
├── boot 分区（里面是一个 ext4 文件系统）
└── rootfs 分区（里面也是一个 ext4 文件系统）  ← 这个 ext4 单独拎出来，就是 rootfs.ext4
```

所以 `rootfs.ext4` 没有 MBR 分区表，也不能直接 `dd` 烧整盘。它要么被脚本写进镜像的某个分区位置，要么挂载起来看：

```bash
sudo mount -o loop rootfs.ext4 /mnt
```

`.squashfs` 是另一种文件系统镜像，只读、压缩。Live 系统、嵌入式只读根常用它。看内容用 `unsquashfs -l`，不用解包。项目目前不用，知道它和 `.ext4` 同属"文件系统镜像"这一层即可。

## 文件归档：`.tar` / `.tar.gz` / `.zip`

归档关心的是"文件"，跟盘的字节布局无关。解开它得到的是一个普通目录。

最容易和镜像混的一对：

```text
rootfs.tar.gz：把 rootfs 目录打包压缩，解开是目录、是一堆文件
rootfs.ext4 ：把 rootfs 做成 ext4 文件系统，是带 inode/块结构的镜像
```

一个能 `tar xf` 直接看到目录树，一个必须 `mount` 才看得到内容。这就是上一章开头那句"`.tar.gz` 关心文件，`.img` 关心盘布局"的延伸版。

顺带理一下压缩和归档的关系：

```text
tar              ：归档（把一堆文件打成一个包）
gz / bz2 / xz / zstd：压缩（把包变小）
.tar.gz = 先 tar 归档，再 gz 压缩
```

`.zip` 自己同时做归档和压缩，所以单后缀就够。它们都不能 `dd` 烧盘。

## 启动专用二进制：`zImage` / `.dtb` / `u-boot-dtb.imx`

严格说这几个不是"打包格式"，是特定用途的二进制。但读者常把它们和 `.img` 搞混——尤其 `u-boot-dtb.imx`，名字里带 `.imx`，很容易被当成 `.img` 那种整盘镜像。其实不是。

```text
zImage            ：压缩的 Linux 内核镜像
imx6ull-aes.dtb   ：编译后的设备树二进制
u-boot-dtb.imx    ：i.MX 专用 U-Boot 镜像，带 IVT/DCD 头，给 ROM 识别
```

前两个是 boot 分区里的普通文件，U-Boot 用 `ext4load` 读它们。

`u-boot-dtb.imx` 比较特殊：它不进 boot 分区，而是写到整盘 1 KiB 的 raw 区域。注意 `.imx` 是 i.MX 的启动镜像格式（IVT 头），不是通用 `.img`。别看后缀像就以为是同一种东西。

这三个都"不能 `dd` 烧整盘"——它们要么是 boot 分区里的文件，要么是 raw 区的一小段，不是整盘布局。

## 回到那张表

把这些格式按层摆回去：

```text
整盘镜像      ：.img  /  .iso
文件系统镜像  ：rootfs.ext4  /  .squashfs
文件归档      ：.tar  .tar.gz  .zip
启动专用二进制：zImage  .dtb  u-boot-dtb.imx
```

下次看到一个后缀，先定位它在哪一层，再决定用什么工具：归档用 `tar`/`unzip`，文件系统镜像用 `mount`/`debugfs`，整盘镜像才轮到 `dd` 和 `sfdisk`。

## 小结

这一章把常见的打包和镜像格式横向梳理了一遍，核心就一句话：

```text
能直接 dd 烧整盘的，只有整盘镜像（.img / .iso）。
其余要么是文件系统镜像（要 mount / 灌分区），要么是文件归档（要解包），要么是启动二进制（写特定位置）。
```

格式分清后，下一章我们进入 i.MX6ULL 的启动链路，看 `u-boot-dtb.imx` 为什么偏偏要写在 1 KiB，而 boot 分区又从 16 MiB 开始。

**下一步：** 阅读 [04_imx6ull_boot_flow_and_offsets.md](04_imx6ull_boot_flow_and_offsets.md)，理解 1 KiB 和 16 MiB 这两个偏移的意义。
