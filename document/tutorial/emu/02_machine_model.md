# 02 — QEMU 眼里的 i.MX6ULL:真模型、纸糊的桩与纯粹的空气

::: info 本节你将学到
- 拿到陌生 QEMU 机器的第一件事:`info mtree` 五分钟打印整机地址地图
- 怎么从地图上认出三种外设:真模型、unimplemented 桩、地址空洞——两个辨认特征
- 桩和空洞在内核眼里的区别:一个软失败,一个 external abort 杀内核
- `-d guest_errors` 这个仪器怎么和 mtree 互相印证
:::

## 一条命令看见整台机器

很多人用 QEMU 的方式是「参数对了就跑,跑不起来换参数」。对咱们要做的事——往一台虚拟机里塞一块真机板子的内核——这个方式不够,得先知道这台机器肚子里装了什么。QEMU 自己就带着这个问答命令,叫 `info mtree`,藏在 monitor 里。

交互式的玩法:启动之后按 `Ctrl-A C` 切进 monitor,敲 `info mtree`。脚本化的玩法一条管道就够,连内核都不用挂:

```bash
printf 'info mtree\nquit\n' | qemu-system-arm -M mcimx6ul-evk -S \
    -display none -serial none -monitor stdio
```

`-S` 让 CPU 停在复位态,咱们只看静态地图。输出的每一行是一个内存 region,咱们抽几行真实的出来看:

```text
0000000002020000-0000000002020fff (prio 0, i/o): imx.serial
0000000002190000-00000000021900ff (prio 0, i/o): sdhci
0000000002188000-000000000218bfff (prio 0, i/o): imx.fec
0000000002080000-000000000208001f (prio -1000, i/o): pwm0
0000000002090000-0000000002090fff (prio -1000, i/o): can0
00000000021c8000-00000000021c80ff (prio -1000, i/o): lcdif
```

前三个和后三个长得像,差在两处:`prio 0` 对 `prio -1000`;region 大小一个像样(0x1000 上下)对一个寒酸(pwm0 只有 32 字节)。这两个特征就是分界线。`prio 0`、尺寸正常的是真模型——`imx.serial` 是 8 个 UART、`sdhci` 是两个 USDHC、`imx.fec` 是两块网卡,寄存器行为、中断逻辑都是实现了的,内核驱动跟它们打交道,和跟真芯片打交道一个待遇。`prio -1000` 的那些,来自 QEMU 源码里一个叫 `create_unimplemented_device()` 的函数:名字、地址、大小,三样信息,划一块内存区域,读永远返回 0,写扔掉只打一行日志。这就是桩。咱们这份 8.2.2 的输出里,数出来 24 行桩 region、68 行真 region(含子 region),PWM×8、CAN×2、SAI×3、ASRC、ADC×2、LCDIF、IOMUXC、SDMA 全在桩那一侧。

桩的体感,拿 CAN 做标本最清楚。地图上 `can0` 是桩,再看启动日志:

```text
[   12.039464] flexcan 2090000.can: registering netdev failed
[   12.039793] flexcan 2090000.can: probe with driver flexcan failed with error -110
```

地址对上了(`2090000` 就是地图上 can0 那行),驱动 probe 读寄存器拿一串零,等到超时,`-110` 也就是 `-ETIMEDOUT`,然后退出。内核整体照常跑,串口吵两声完事。所有桩上的驱动都是这个待遇:软失败,吵,不致命。

## 空洞:地图上根本没有这个地址

现在把咱们设备树里天经地义的几个地址拿去地图上找:`0x21b0000`(MMDC,DDR 控制器)、`0x21bc000`(OCOTP,熔丝盒)、`0x21e0000`(QSPI)、`0x21cc000`(PXP)。grep 那份 mtree 输出,一个都搜不到。

地址上没有 region,访问它会怎样?CPU 发出总线事务,QEMU 的系统总线找不到任何 region 接这一单,直接给 CPU 回一个总线错误,ARM 上表现为 external abort 异常。如果这时跑在内核态——比如驱动的 probe 函数里一句 `readl`——异常没人兜底,内核死。桩读出零,空洞炸内核,同一个「QEMU 没实现」在地图上差一个 region,落到内核头上就是两种命运。这是第四章连环惨案的完整伏笔,咱们板子的 dtsi 里,mmdc、ocotp、qspi、pxp、dcp、rngb、csi、tsc、usbmisc 全部落在空洞这一侧。

空洞还有一个更阴的变种:地址外面套着一个真模型的容器,但访问的位置落在容器内部的缝里。咱们机器的 USB 控制器就是这副地形,0x2184000 一带有完整的 chipidea/ehci 模型,可模型只覆盖了控制器自己的寄存器;NXP 在控制器旁边加的那块「usbmisc」杂项寄存器(基址 +0x800)没人管。地图上看容器存在,踩进去那一步才是空气。这个坑第四章拿实物讲。

## 两个仪器互相印证

mtree 是静态地图,QEMU 还有一个动态仪器:`-d guest_errors`,把客户机的非法访客操作打到 stderr。拿真机 dtb(还没裁剪过的那份)启动,加上这个参数:

```console
$ qemu-system-arm -M mcimx6ul-evk ... -dtb imx6ull-aes.dtb -d guest_errors
Invalid read at addr 0x21B0018, size 4, region '(null)', reason: rejected
[    0.133220] PC is at imx_mmdc_probe+0x80/0x31c
```

第一行是 QEMU 的视角:`region '(null)'` 说这个地址上什么都没挂,`reason: rejected` 说这单总线事务被拒了。第二行是内核的视角:MMDC 驱动的 probe 死在读寄存器上。两个仪器报告了同一个地址、同一个事件——0x21B0018,读 4 字节,被拒,炸。排查的时候两边对账,比单看一边踏实得多。

顺带一提对咱们有利的一个地形:FEC 网卡是真模型,而且 EVK 机器的 PHY 拓扑(fec2 的 MDIO 下挂 1 号 PHY)和咱们板子的 ksz8081 接法对得上,网络这条路的地基是好的。眼下 FEC 还有个 probe deferred 的遗留(第五章末尾交代),那属于设备树供应链的毛病,模拟硬件本身没缺。

## 版本会挪动地皮

三档的归属跟着 QEMU 版本走,方向通常是把空洞填成桩、把桩换成真模型。咱们这份 8.2.2 的地图上 lcdif 还是桩,11.1 里它已经是能出画面的真模型(2026 年 4 月合入);mmdc 空洞在 2026 年 8 月的十补丁系列里补了桩;flexcan 的桩后面换成了 CTU Prague 写的真模型,只是还没接线到 6UL 这个 SoC。所以设备树变体(第四章)按所用版本的地图来裁:8.2 的空洞关掉,升到 11.1 再放行——空洞只会变少,升级只松不紧。反过来要小心:拿 11.1 的经验写的教程,落到 8.2 上就可能炸。

::: tip 下一章
家底摸清了,下一章开始动手:把 `out/release-latest/rootfs/` 那棵 174MB 的目录树变成 QEMU 能当 SD 卡挂的 ext4 镜像。中间有个容量限制等着——一张 200MB 的正常镜像,QEMU 会当场拒收。
:::
