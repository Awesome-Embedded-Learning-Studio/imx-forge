---
title: 启动链路与偏移
---

# i.MX6ULL 启动链路与偏移 - 为什么 U-Boot 写在 1 KiB

## 前言：1 KiB 和 16 MiB 不是一回事

前面两章我们先分清了存储设备、整盘、分区和文件系统。

现在可以看镜像布局里最容易让新手疑惑的两个数字了：

```text
U-Boot 写在 1 KiB 偏移
boot 分区从 16 MiB 开始
```

这两个数字经常被放在同一张布局图里，于是很容易被误会成同一件事。其实它们解决的是两个不同问题。

`1 KiB` 是 i.MX6ULL 启动 ROM 找 U-Boot 的位置问题。

`16 MiB` 是我们给第一个分区安排起点时做的工程布局选择。

一个是“芯片上电后先去哪里找启动镜像”，另一个是“分区从哪里开始比较清楚、保守、好维护”。不要把它们混在一起。

## 上电后谁先运行

板子上电后，不是 U-Boot 第一个运行。

最先运行的是芯片内部固化好的 ROM Code。它在芯片里，不能像 U-Boot 那样随便重新编译。ROM Code 会根据启动拨码、熔丝配置或制造模式，决定从哪里找启动介质。

大概可以理解成：我们的板子一上电，i.MX6ULL就要跑它的ROM Code 运行。ROM代码按启动配置找 SD/eMMC/USB，在对应的存储设备中找到符合格式的启动镜像。然后大喊一声哈哈U-Boot小子我抓到你了。最后就是大伙熟悉的引导。所以 U-Boot 不是凭空出现的。它必须被放在 ROM Code 能找到的位置，并且格式要让 ROM Code 看得懂。

## u-boot-dtb.imx 和 u-boot.bin 有什么区别

构建 U-Boot 时，你可能见过不同文件名：

```text
u-boot.bin
u-boot-dtb.bin
u-boot-dtb.imx
```

对当前 i.MX6ULL 镜像脚本来说，真正拿来写盘的是：

```text
u-boot-dtb.imx
```

这个 `.imx` 后缀很关键。它不是随便改的文件名，而是已经按 i.MX 平台启动要求处理过的镜像。里面带了 ROM Code 需要识别的启动头信息，也包含 U-Boot 自身以及设备树相关内容。

如果你只拿普通 `u-boot.bin` 往 1 KiB 偏移写，ROM Code 不一定能按 i.MX 的启动格式识别它。这里我们不展开 IVT、DCD 这些细节。刚入门时先抓住项目使用层面的结论：i.MX6ULL 从 SD/eMMC 启动时，项目写盘使用 u-boot-dtb.imx。

## 为什么脚本用 dd bs=1K seek=1

镜像脚本里写 U-Boot 的动作是：

```bash
dd if="${UBOOT_IMAGE}" of="${image}" bs=1K seek=1 conv=notrunc
```

拆开看：

```text
bs=1K   -> 每个块按 1 KiB 算
seek=1  -> 写入前跳过 1 个块
```

所以实际写入位置就是：

```text
1 KiB * 1 = 1 KiB
```

也就是从整盘镜像的 1 KiB 偏移处开始写 `u-boot-dtb.imx`。

这不是写进某个分区。此时 boot 分区还没有开始。它写的是整盘前面的 raw 区域。

`conv=notrunc` 也很重要。脚本前面已经创建好一个完整大小的 `.img` 文件，后面还要写分区文件系统。写 U-Boot 时不能把这个文件截断，所以要告诉 `dd`：只覆盖对应位置，不要截掉后面的内容。

## 1 KiB 偏移解决什么问题

从使用者角度看，1 KiB 偏移解决的是 ROM Code 找启动镜像的问题。

i.MX6ULL 从 SD/eMMC 启动时，会按平台约定在介质前面特定位置寻找启动数据。项目脚本把 `u-boot-dtb.imx` 放到 1 KiB 偏移，就是为了让 ROM Code 能在上电早期找到它。

这件事发生在 Linux 还没启动之前，也发生在 U-Boot 解析文件系统之前。

所以它和下面这些概念都不是一层：

```text
boot 分区
rootfs 分区
ext4 文件系统
zImage 文件
```

它更靠前。先有 ROM Code 找 U-Boot，才有 U-Boot 去读 boot 分区里的 `zImage` 和 DTB。

## 16 MiB boot 分区起点解决什么问题

boot 分区从 16 MiB 开始，是另一个问题。

脚本把第一个分区安排在 16 MiB，是为了给整盘前面留出一个清晰的启动前置区域：

```text
offset 0
├── MBR 分区表
├── 1 KiB: u-boot-dtb.imx
└── 16 MiB: boot 分区开始
```

这样做有几个好处。

第一，boot 分区不会贴着 U-Boot。以后 U-Boot 变大，或者前面需要放别的启动相关数据，不会马上撞到第一个分区。

第二，16 MiB 对齐起来很好认。按 512 字节扇区算：

```text
16 * 1024 * 1024 / 512 = 32768
```

所以你看分区表时会看到：

```text
start=32768
```

这个数字一眼就能对上 16 MiB。

第三，它让布局解释起来更清楚。前 16 MiB 是启动前置区域，后面才进入普通分区世界。

## U-Boot 起来后做什么

ROM Code 把 U-Boot 拉起来之后，事情就进入 U-Boot 的世界。

U-Boot 会根据环境变量或手动命令，从 boot 分区读取内核和设备树。以 eMMC 镜像为例，命令大概是：

```text
ext4load mmc 1:1 ${loadaddr} /zImage
ext4load mmc 1:1 ${fdt_addr_r} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr_r}
```

这里的 `mmc 1:1` 表示：

```text
U-Boot 的第 1 个 MMC 设备，第 1 个分区
```

这时才会用到 boot 分区里的 ext4 文件系统。`zImage` 和 `.dtb` 是普通文件，U-Boot 通过 `ext4load` 把它们读到内存里。

然后 U-Boot 把控制权交给 Linux 内核。

## Linux 再挂 rootfs

Linux 启动后，会根据 `bootargs` 里的 `root=` 参数挂载根文件系统。

SD 镜像里通常是：

```text
root=/dev/mmcblk0p2
```

eMMC 镜像里通常是：

```text
root=/dev/mmcblk1p2
```

这里的 `p2` 指第 2 个分区，也就是 rootfs 分区。

所以整个启动链路可以串起来：

```text
ROM Code
  -> 1 KiB raw 区域里的 u-boot-dtb.imx
U-Boot
  -> boot 分区里的 zImage 和 DTB
Linux
  -> rootfs 分区作为 /
```

这样看，U-Boot、boot 分区、rootfs 分区各自职责就很清楚了。

## UUU 和 UMS 在这条链路里的位置

eMMC 烧录时还会出现 UUU 和 UMS。先放一个简单位置，不展开细节。

UUU 走的是 USB 制造模式相关流程。它可以让主机把一个 U-Boot 镜像下载到板子的 RAM 里运行。

注意，是 RAM 里运行。

这一步不是把 U-Boot 永久写进 eMMC。它只是临时让板子先跑起来。

U-Boot 跑起来后，可以执行：

```text
ums 0 mmc 1
```

这条命令让板子把 eMMC 暴露成主机上的 USB 存储设备。主机随后对这个新增块设备写完整 eMMC 镜像，才是真正把数据写进 eMMC。

所以 UUU/UMS 可以简单理解成：

```text
UUU：临时把 U-Boot 跑进 RAM。
UMS：让主机能看到板上的 eMMC。
dd/Rufus：把完整镜像写进 eMMC。
```

后面的 eMMC 烧录实战会详细讲这条链路。这里先把它和正常启动链路分开，不然很容易误以为 UUU 下载的 U-Boot 已经自动烧进了 eMMC。

## 小结

这一章重点不是背细节，而是把几个位置分清楚：

- ROM Code 最先运行。
- `u-boot-dtb.imx` 是给 i.MX6ULL 启动用的 U-Boot 镜像格式。
- 脚本用 `dd bs=1K seek=1` 把它写到整盘 1 KiB 偏移。
- 1 KiB 偏移服务于 ROM Code 找 U-Boot。
- 16 MiB boot 分区起点服务于分区布局和工程预留。
- U-Boot raw 区域不是 boot 分区。
- U-Boot 起来后，才从 boot 分区读取 `zImage` 和 DTB。
- Linux 起来后，才挂载 rootfs 分区。

到这里，基础概念就铺得差不多了。下一章再回到一个工程问题：既然零件都知道了，为什么我们还要把它们打成一个完整 `.img`。

**下一步：** 继续阅读 [05_why_full_image.md](05_why_full_image.md)，看为什么要从散落产物升级为完整镜像。
