# 镜像布局设计 - 这块“假想的盘”里面有什么

## 前言：别把 `.img` 当成一个普通文件系统

第一次看到 `imx6ull-aes-emmc.img` 的时候，很容易下意识把它理解成“一个 rootfs 镜像”。但它其实不是。

它更像是一整块 SD 卡或 eMMC 的拷贝。你从第 0 字节开始读，会先遇到分区表；继续往后，会遇到 raw U-Boot；再往后才是 boot 分区和 rootfs 分区。

这点很重要。因为一旦你把 `.img` 当成单个 ext4 文件系统来理解，后面很多事情都会觉得奇怪：

- 为什么 U-Boot 不在分区里？
- 为什么 boot 分区从 16 MiB 开始？
- 为什么脚本要用 `dd` 写三次？
- 为什么 `sfdisk -d` 能看到分区表？

这一章我们就把这块“假想的盘”拆开来看。

## 先看整体长相

当前脚本生成的镜像布局大概是这样：

```text
offset 0
├── MBR 分区表
├── 1 KiB: u-boot-dtb.imx
├── 16 MiB: boot 分区开始
│   ├── zImage
│   ├── imx6ull-aes.dtb
│   └── boot.cmd
└── boot 分区之后: rootfs 分区开始
    └── 完整 rootfs
```

把它翻译成默认参数，就是：

| 项目 | 默认值 | 作用 |
| --- | --- | --- |
| U-Boot 偏移 | `1 KiB` | 给 i.MX6ULL ROM 启动读取 |
| boot 分区起点 | `16 MiB` | 避开启动区，顺便做清晰对齐 |
| boot 分区大小 | `64 MiB` | 放内核、设备树和启动命令 |
| rootfs 分区大小 | 自动计算 | 放完整根文件系统并预留余量 |
| 分区文件系统 | ext4 | boot 和 rootfs 都使用 ext4 |

你可以把前 16 MiB 理解成启动前置区域。U-Boot 住在这里，分区从它后面开始。

## 为什么 U-Boot 要写在 1 KiB

U-Boot 在这里不是一个普通文件。它不会被 Linux 挂载，也不属于 boot 分区。

i.MX6ULL 上电后，ROM Code 会按照启动介质去找符合格式的启动镜像。项目里生成的 `u-boot-dtb.imx` 已经是 i.MX 平台需要的格式，脚本要做的就是把它放到正确的位置。

脚本里的动作很直接：

```bash
dd if="${UBOOT_IMAGE}" of="${image}" bs=1K seek=1 conv=notrunc
```

这句的意思是：从镜像文件开头跳过 1 KiB，然后把 `u-boot-dtb.imx` 写进去。

这里最容易误会的是 `conv=notrunc`。如果不加它，`dd` 有可能把目标文件截断。我们前面已经创建了一整个磁盘镜像，后面还要继续写分区文件系统，所以绝对不能让一次 `dd` 把整盘镜像截掉。

## 为什么 boot 分区从 16 MiB 开始

按理说，U-Boot 只有一两 MiB 左右，那为什么 boot 分区不紧贴着它开始？

这里是工程上的保守设计。我们给前面留出 16 MiB，有几个好处。

首先，它能避开 raw U-Boot 区域。以后如果 U-Boot 变大，或者环境区、扩展数据有变化，不至于马上撞到第一个分区。

其次，16 MiB 是一个很清楚的边界。换算成 512 字节扇区，就是：

```text
16 * 1024 * 1024 / 512 = 32768
```

所以你用 `sfdisk -d` 看镜像时，会看到第一个分区从 `32768` 扇区开始：

```text
...img1 : start=32768, size=131072, type=83, bootable
```

这个数字一眼就能对上 16 MiB，不需要在脑子里猜“这是哪里来的”。

## 为什么 boot 分区也做成 ext4

很多教程会把 boot 分区做成 FAT32。这没错，FAT 对很多 U-Boot 配置都很友好，主机上也容易挂载。

但在 IMX-Forge 这个脚本里，我们选择了 ext4。不是因为 FAT 不好，而是因为 ext4 更适合当前构建方式。

当前 U-Boot 已经支持：

```text
ext4load
```

rootfs 本身也是 ext4。更关键的是，`mke2fs` 有一个很好用的 `-d` 参数，可以直接把一个目录打进 ext4 文件系统镜像里：

```bash
mke2fs -q -t ext4 -d "${boot_dir}" -L "BOOT" -m 0 -F "${boot_fs}"
```

这就绕开了一个很讨厌的问题：我们不需要 `sudo mount` 一个 loop 设备，也不需要在构建脚本里维护挂载和卸载状态。

构建镜像时，越少碰主机挂载状态越好。否则脚本跑失败后留下一个没卸载的 loop 设备，后面排查起来会很烦。

## boot 分区里为什么放两份内核和 DTB

脚本会先构造一个临时目录：

```text
boot-tree/
├── zImage
├── imx6ull-aes.dtb
├── boot.cmd
└── boot/
    ├── zImage
    └── imx6ull-aes.dtb
```

严格来说，当前自动生成的启动命令用的是根目录下的文件：

```text
ext4load mmc 1:1 ${loadaddr} /zImage
ext4load mmc 1:1 ${fdt_addr_r} /imx6ull-aes.dtb
```

那为什么还要在 `/boot/` 下面再放一份？

这是为了兼容人的习惯。很多 Linux 系统会把内核文件放在 `/boot/` 下，很多人手动调试时也会自然去 `ext4ls mmc 1:1 /boot` 看东西。多放一份成本不高，但能减少“文件到底在哪里”的疑惑。

`boot.cmd` 则更像是一份启动命令备忘录。它不是现在这套流程里必须自动执行的脚本，但你可以打开它看脚本为这个镜像生成了什么启动参数。

## rootfs 分区怎么决定大小

rootfs 的大小不能拍脑袋。太小，文件系统装不下；太大，每次生成和复制镜像都浪费时间。

脚本采用一个比较朴素的策略：

```text
rootfs 分区 = rootfs 实际占用 + 25% + 64 MiB
```

同时保证最低不小于 128 MiB。

这个策略适合默认情况：镜像不会大得离谱，又给 rootfs 留出一点上板后写文件的空间。

如果你明确希望镜像固定大小，比如固定成 1 GiB，可以用：

```bash
scripts/image_builder/build_imx6ull_image.sh --image-size-mb=1024
```

这时脚本会先固定总镜像大小，再把扣掉前置空间和 boot 分区后的剩余空间分给 rootfs。也就是说，多出来的空间不是空洞，而是 rootfs 分区里的可用空间。

## SD 和 eMMC 的布局一样吗

分区布局基本一样，但启动命令不一样。

SD 镜像里，U-Boot 从 `mmc 0:1` 读取内核，Linux 挂载 `/dev/mmcblk0p2`：

```text
ext4load mmc 0:1 ${loadaddr} /zImage
root=/dev/mmcblk0p2
```

eMMC 镜像里，U-Boot 从 `mmc 1:1` 读取内核，Linux 挂载 `/dev/mmcblk1p2`：

```text
ext4load mmc 1:1 ${loadaddr} /zImage
root=/dev/mmcblk1p2
```

所以脚本默认用文件名提醒你：

```text
imx6ull-aes-sd.img
imx6ull-aes-emmc.img
```

这不是为了好看，而是为了避免你后面把 SD/eMMC 参数混了。

## 怎么验证布局没跑偏

生成镜像后，不用挂载，先看分区表就行：

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-emmc.img
```

你应该看到类似这样的内容：

```text
label: dos
unit: sectors

...img1 : start=32768, size=131072, type=83, bootable
...img2 : start=163840, size=..., type=83
```

这里几个数字能对上：

- `32768` 扇区是 16 MiB
- `131072` 扇区是 64 MiB
- `163840` 扇区是 boot 分区结束后的 rootfs 起点

如果这些数字明显不对，就先别急着烧录。镜像布局都没确认，后面的问题只会更绕。

## 接下来我们看脚本怎么做

现在你已经知道镜像内部长什么样了。下一章我们回到 `build_imx6ull_image.sh`，看看它是怎么一步一步把这个布局做出来的。

**下一步：** 阅读 [06_build_imx6ull_image_script.md](06_build_imx6ull_image_script.md)，拆解脚本的设计思路。
