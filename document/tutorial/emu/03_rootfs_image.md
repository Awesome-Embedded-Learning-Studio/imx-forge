# 03 — rootfs 变 SD 卡:一张会被当场拒收的镜像

::: info 本节你将学到
- `mke2fs -d` 直灌目录树做 ext4 镜像:全程无 root、无挂载,以及用 `debugfs` 不挂载验证镜像内容
- QEMU SD 卡模型的容量限制:亲手做一张会被拒收的镜像,看它死在哪个环节
- `if=sd,index=1` 背后的连线逻辑,和 `/dev/mmcblk1` 这个名字的由来(设备树 aliases)
- 整卡文件系统与分区表的取舍,`root=/dev/mmcblk1` 和真机 `mmcblk1p2` 的差别
:::

## 手上有什么,要变成什么

上一章把机器的家底摸清了,这一章喂东西。手上现成的是 `out/release-latest/rootfs/`——Buildroot 吐出来的一棵完整目录树,174MB,BusyBox、eudev、ALSA 一家、Qt6 运行时都在里面,登录密码配好,getty 挂在 ttymxc0 上。QEMU 要的则是一个文件:`-drive file=xxx,if=sd` 把它当 SD 卡插给客户机。中间这道工序,本章走通。

第一反应也许是「loop 挂载 + `mkfs.ext4` + `cp`」。能干,但要 root 权限,要挂载点清理,CI 里跑这种脚本浑身难受。`mke2fs` 的 `-d` 选项省掉这整套:以目录树为内容源,直接在普通文件上建 ext4,全程无特权、无挂载。仓库里 `build_imx6ull_image.sh` 做整盘镜像用的同一招,`make-rootfs-img.sh` 照搬:

```bash
truncate -s 256M out/qemu/rootfs.ext4
mke2fs -q -t ext4 -d out/release-latest/rootfs -L rootfs -m 0 -F out/qemu/rootfs.ext4
```

`-t ext4` 定文件系统类型,`-d` 给目录树,`-L rootfs` 打卷标,`-m 0` 不给 root 预留块(仿真盘不需要这套),`-F` 允许在普通文件上操作。

做完了怎么验?又不用挂载——`debugfs` 直接读镜像里的文件系统:

```console
$ debugfs -R 'ls -l /' out/qemu/rootfs.ext4
      2  40755 (2)      0      0    4096 25-Aug-2026 23:54 .
     11  40700 (2)      0      0   16384 25-Aug-2026 23:54 lost+found
     12  100644 (1)   1000   1000     585  8-Jul-2026 19:38 README.md
     14  40755 (1)   1000   1000    4096  2-Aug-2026 19:03 bin
    116  40755 (2)   1000   1000    4096  1-Jan-1970 08:00 etc
```

内容都在,而且注意时间戳:`README.md` 保留着 8-Jul、`bin` 是 2-Aug——文件自己的 mtime 原样搬进来了,只有镜像层的目录(那两个 `.`)是今天。这是 `-d` 直灌的痕迹,也是排障时的一个指纹:哪天怀疑镜像内容陈旧,`debugfs` 一眼能看到每个文件的真实日期,连挂载都不用。

## 256 不是随便选的

现在做那个实验:镜像做到 200MB,挂上去。

```bash
truncate -s 200M /tmp/t200.img
qemu-system-arm -M mcimx6ul-evk -m 128M \
    -drive file=/tmp/t200.img,if=sd,index=1,format=raw ...
```

QEMU 当场拒收:

```text
qemu-system-arm: Invalid SD card size: 200 MiB
SD card size has to be a power of 2, e.g. 256 MiB.
You can resize disk images with 'qemu-img resize <imagefile> <new-size>'
```

报错发生在 QEMU 初始化 SD 卡模型的时候,内核都还没上场。原因是 SD 卡协议里的 CSD 寄存器:客户机枚举 SD 卡要读这张卡的自描述寄存器,容量编码在 `C_SIZE` 字段里,QEMU 的实现要求容量是 2 的幂,编码才能严丝合缝。所以官方 Buildroot 靶机生成的 84MB 镜像,文档专门嘱咐 resize 到 128MB;咱们 `out/release-latest/images/` 里那些 216M、369M 的整盘镜像同样挂不得,模拟用的一律单独做——174MB 的树灌进 256MB,余量健康,树再长胖就 `--size-mb=512`。

校验写死在脚本参数解析里:

```bash
is_power_of_two() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" != 0 && ("$1" & ("$1" - 1)) == 0 ))
}
is_power_of_two "${SIZE_MB}" || die "size must be a power of two (got ${SIZE_MB})"
```

位运算的原理一句话:`n & (n-1)` 把 n 最低位的 1 抹掉,2 的幂抹完剩 0。

## index=1 的连线和 mmcblk1 的名字

挂载参数逐字拆开:`-drive file=...,if=sd,index=1,format=raw`。`if=sd` 说这是一张 SD 卡,QEMU 把它接到机器的 SD 总线上;`index` 挑控制器——机器模型里有两个 USDHC,index 0 接 USDHC1,index 1 接 USDHC2。

为什么选 1?咱们真机上 usdhc2 接的是 eMMC,设备树里它是 8-bit、non-removable 的配置;usdhc1 是 SD 卡槽,带 `cd-gpios`(插拔检测)。虚拟 SD 卡插第二槽,「第二控制器上有张卡」和设备树自洽;插第一槽的话,设备树声称的插拔检测 GPIO 在 QEMU 里没人驱动,行为不可预测,没必要赌。

客户机里这张卡叫 `/dev/mmcblk1`,这个名字的来历查得到——设备树的 aliases:

```console
$ fdtget imx6ull-aes.dtb /aliases mmc0
/soc/bus@2100000/mmc@2190000
$ fdtget imx6ull-aes.dtb /aliases mmc1
/soc/bus@2100000/mmc@2194000
```

`mmc0` 指向 2190000(USDHC1),`mmc1` 指向 2194000(USDHC2)。内核按 alias 给 mmc 控制器定编号,块设备名跟着控制器走,所以 USDHC2 上的卡稳稳当当叫 mmcblk1。alias 的意义就在这个「稳」:没有 alias 时编号按 probe 顺序分配,`root=` 写谁全凭运气,有了 alias,设备名和 `root=/dev/mmcblk1` 锁死。

启动日志里这张卡现身的时刻:

```text
[    0.880534] mmc1: new high speed SD card at address 4567
[    0.884844] mmcblk1: mmc1:4567 QEMU! 256 MiB
[    1.745474] EXT4-fs (mmcblk1): mounted filesystem ad538f68-... r/w with ordered data mode
```

## 分区表呢

这张盘没有 MBR,ext4 从 0 扇区铺到尾,内核参数是 `root=/dev/mmcblk1`,真机上写的是 `mmcblk1p2`。差别在启动链:真机里 U-Boot 要从分区 1 读内核、内核从分区 2 挂 root,分区表是刚需;QEMU 直启链里 `-kernel`/`-dtb` 由 QEMU 自己装进内存,盘的使命只剩给内核当根文件系统,整卡一块 ext4 就够了。等哪天要复刻 U-Boot 引导链、让虚拟板也从分区里 `ext4load`,再回头上 genimage 切分区,`mmcblk1p2` 自然会回来。

::: tip 下一章
料齐了:zImage、dtb、256MB 的镜像。下一章把它们一起塞进 QEMU——然后经历那场打地鼠:八次启动、八种死法,以及让串口从死寂里开口的那个关键词。
:::
