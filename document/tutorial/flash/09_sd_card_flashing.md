# SD 卡烧录实战 - 先把一张卡写明白

## 前言：SD 卡流程为什么要单独讲

前面几章我们已经把完整镜像做出来了。现在问题变成另一个很实际的事情：怎么把这个 `.img` 写进一张真正的 SD 卡，然后让板子从它启动。

这一步看起来简单，命令也就一条 `dd`。但说实话，很多烧录事故都不是脚本写错，而是写错了主机设备。比如把 `/dev/sdX1` 当成整盘写，或者把主机硬盘误认成 SD 卡。`dd` 不会问你“真的要覆盖吗”，它会很认真地把你给它的目标抹掉。

所以这一章不会上来就让你敲命令。我们先确认镜像，再确认设备，最后再写卡。

## 先生成 SD 镜像

从项目根目录执行：

```bash
scripts/release-all.sh --continue --stage 5 --boot-media sd
```

如果前面的 release 产物都已经在 `out/release-latest/` 里，也可以直接调用镜像脚本：

```bash
scripts/image_builder/build_imx6ull_image.sh \
  --release-dir=out/release-latest \
  --boot-media=sd
```

生成结果应该在这里：

```text
out/release-latest/images/imx6ull-aes-sd.img
out/release-latest/images/imx6ull-aes-sd.img.manifest
out/release-latest/images/imx6ull-aes-sd.img.sha256
```

这里一定要注意文件名里的 `sd`。当前项目约定是：

| 介质 | U-Boot 设备 | Linux root |
| --- | --- | --- |
| SD | `mmc 0` | `/dev/mmcblk0p2` |
| eMMC | `mmc 1` | `/dev/mmcblk1p2` |

SD 镜像里面的启动参数就是按这个约定生成的。拿 eMMC 镜像去烧 SD 卡，有时候也能看到 U-Boot，有时候甚至能加载到内核，但内核挂 rootfs 的时候很容易掉进 `VFS: Cannot open root device`。

::: tip v1.0.0 验证基线
SD 卡镜像 `imx6ull-aes-sd.img` 已由仓库主作者 CharlieChen114514 在正点原子阿尔法 i.MX6ULL 开发板上实验启动通过。本章后续排查默认以 `mmc 0` 和 `root=/dev/mmcblk0p2` 为基线。
:::

## 烧录前先看 manifest

先别急着插卡。先确认这个镜像确实是 SD 版本：

```bash
sed -n '1,80p' out/release-latest/images/imx6ull-aes-sd.img.manifest
```

重点看这几行：

```text
boot_media=sd
uboot_mmc_dev=0
linux_root_dev=/dev/mmcblk0p2
```

再看一下分区表：

```bash
sfdisk -d out/release-latest/images/imx6ull-aes-sd.img
```

正常情况下，第一个分区从 16 MiB 开始：

```text
...img1 : start=32768, size=131072, type=83, bootable
...img2 : start=163840, size=..., type=83
```

这些检查都不会修改镜像。把这一步养成习惯，后面排查能省很多时间。

## Windows

孩子们我偷懒了直接，Rufus是一个好用的工具，直接选择镜像咱们构建的镜像烧录进去就完事了。关键点只有一个：选择 DD/raw image 模式，把整个 `.img` 写进整张 SD 卡。

Linux的用户看下边

## Linux/WSL用户 找到主机上的 SD 卡设备

插入 SD 卡之前，先看一次块设备：

```bash
lsblk
```

插入 SD 卡，再看一次：

```bash
lsblk
```

新增出来的那个整盘设备，就是目标设备。它可能长这样：

```text
sdb      8:16   1  29.7G  0 disk
├─sdb1   8:17   1    64M  0 part
└─sdb2   8:18   1   512M  0 part
```
（我反复强调下，你的不一定是sdb哈，看你多出来了哪一个！）。这时整盘路径是：

```text
/dev/sdb
```

不是：

```text
/dev/sdb1
```

写完整 raw image 必须写整盘。因为镜像里本来就包含 MBR、raw U-Boot 区域、boot 分区和 rootfs 分区。你写到分区上，相当于把整盘结构塞进了一个分区内部，板子当然很难启动。

如果桌面环境自动挂载了 SD 卡分区，先卸载：

```bash
sudo umount /dev/sdb1
sudo umount /dev/sdb2
```

这里的 `/dev/sdb` 只是例子。实际操作一定换成你机器上 `lsblk` 看到的新增设备。

## 用 dd 写入

确认目标是整盘设备后，执行：

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-sd.img \
  of=/dev/sdX \
  bs=4M \
  status=progress \
  conv=fsync
```

写完再同步一次：

```bash
sync
```

`conv=fsync` 会让 `dd` 在结束前尽量把数据刷到设备上。后面的 `sync` 是再稳一手，尤其是用 USB 读卡器时，不要看到命令返回就马上拔卡。你知道的，硬盘操作远慢于内存读写，有时候操作系统小小的缓存机制可能会坑人。。。

## 上板启动

把 SD 卡插到板子上，启动模式拨到 SD。上电后进入 U-Boot，可以先做几条手动检查：

```text
mmc list
mmc dev 0
mmc part
ext4ls mmc 0:1 /
ext4ls mmc 0:2 /
```

`mmc dev 0` 能选中 SD，`ext4ls mmc 0:1 /` 能看到 `zImage` 和 `imx6ull-aes.dtb`，说明 boot 分区至少是能读的。

如果当前 U-Boot 环境里有 `sdbootaes`，直接跑：

```text
run sdbootaes
```

如果环境里没有，可以快速设置一套：

```text
# SD 快速启动环境设置
setenv sd_dev 0
setenv fdt_addr 0x83000000
setenv sdargs 'setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw'
setenv loadsdimage 'ext4load mmc ${sd_dev}:1 ${loadaddr} /zImage'
setenv loadsdfdt 'ext4load mmc ${sd_dev}:1 ${fdt_addr} /imx6ull-aes.dtb'
setenv sdbootaes 'echo Booting AES from SD ...; run sdargs; mmc dev ${sd_dev}; run loadsdimage; run loadsdfdt; bootz ${loadaddr} - ${fdt_addr}'
saveenv
run sdbootaes
```

手动启动兜底（不依赖预设环境变量）：

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw
ext4load mmc 0:1 ${loadaddr} /zImage
ext4load mmc 0:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

这里最关键的是两个 `0`：

```text
mmc 0:1
root=/dev/mmcblk0p2
```

前者是 U-Boot 从 SD 的第一个分区加载内核和 DTB，后者是 Linux 挂 SD 的第二个分区作为根文件系统。

## Linux 起来后看什么

系统启动后，先看内核实际拿到的参数：

```bash
cat /proc/cmdline
```

再看根目录挂载在哪：

```bash
mount | grep ' / '
```

如果系统里有 `lsblk`，也可以看：

```bash
lsblk
```

SD 启动时，根分区应该是：

```text
/dev/mmcblk0p2
```

如果你看到 `/dev/mmcblk1p2`，那就说明启动参数还是 eMMC 口径。回去检查镜像 manifest，或者检查 U-Boot 环境变量是不是覆盖了镜像里的默认命令。

## 常见现象

### 写卡后主机还能看到旧分区

这种情况常见于写完后桌面缓存没刷新，或者你写错了设备。

先拔插 SD 卡，再看：

```bash
lsblk -f
```

如果分区大小、卷标、数量完全没变，优先怀疑 `of=` 写错了。正确目标应该是整盘设备，例如 `/dev/sdb`，不是 `/dev/sdb1`。

### U-Boot 里 ext4ls 失败

先确认选的是 SD：

```text
mmc dev 0
mmc part
```

如果 `mmc part` 看不到两个分区，说明卡里整盘布局可能没写进去。回主机用：

```bash
sudo sfdisk -d /dev/sdX
```

确认真实 SD 卡上是否有从 `32768` 扇区开始的第一个分区。

### 内核提示 VFS 无法打开 root

这个问题通常不是 `zImage` 坏了，而是 root 参数和真实设备对不上。SD 流程应该是：

```text
root=/dev/mmcblk0p2
```

如果串口里看到的是 `/dev/mmcblk1p2`，那就是把 eMMC 启动参数带过来了。

## 下一步

SD 卡流程适合第一次验证镜像，也适合快速换卡测试。下一章我们看 eMMC：它不能直接插到主机上，所以要先用 UUU 把 U-Boot 跑进 RAM，再让 U-Boot 把 eMMC 暴露成 UMS。

**下一步：** 阅读 [10_uuu_ums_emmc_flashing.md](10_uuu_ums_emmc_flashing.md)。
