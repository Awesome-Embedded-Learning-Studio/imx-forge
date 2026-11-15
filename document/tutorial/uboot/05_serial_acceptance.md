---
title: 串口验收：亲眼看见咱们编的 U-Boot 活着
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 串口验收：亲眼看见咱们编的 U-Boot 活着

> 上一篇把串口线接好、终端开好、上电的次序摆正了，本篇接着讲上电之后的事：串口里冒出来的头几行怎么认，哪些值要跟主机侧抄下来的预期逐项对，对到哪一步才敢说咱们编的这份 U-Boot 活着。板子不在手边，板端现象一条都没实证，本篇能实量的全部在主机侧，每个预期值都从产物里现抄现贴，出处随行标注。

## 一、验收验的是什么：时间戳当指纹

串口里有输出，离活着还差一步。咱们把处境摆出来：板子上有好几块能存东西的介质，出厂可能预烧过一份 U-Boot，上一轮实验可能在别的介质里留过一份，BootROM 按拨码选中哪块，就从哪块读镜像。读出来的那份照样在串口里打 banner，字都认识，行都工整，可它未必是咱们编的这份。验收要回答的其实只有一句话，现在出声的这份，是不是从 `/tmp/uboot-batch2-evk` 出炉的那份。

区分的把柄在 banner 自己身上。头一行带着编译时间戳，同一棵源码树每编一轮换一个数，咱们拿两轮产物各抄了一份（真实输出）：

```bash
# 主机 ~/imx-forge
strings /tmp/uboot-batch2-evk/u-boot-dtb.imx /tmp/uboot-ref-evk/u-boot-dtb.imx | grep '^U-Boot 2'
```

```text
U-Boot 2026.10-dirty (Nov 14 2026 - 17:02:31 +0800)
U-Boot 2026.10-dirty (Nov 14 2026 - 14:00:57 +0800)
```

两轮产物、两个时间戳，咱们分别对应着 03 章那一轮（17:02:31）与 04 章验过的参考轮（14:00:57）。版本号里的 dirty 是源码树带本地改动的标记，03 章讲过它的来历。时间戳这东西补不了，它生成于编译那一刻，跟着镜像一起写进文件，所以它当得起指纹两个字。板子一出声，对一下这个数，跑的是哪一轮当场见分晓。

上电之前，咱们先在主机侧把预期值抄下来。烧进卡的就是这个文件，banner 原文就嵌在它身上，单独贴一遍：

```bash
# 主机 ~/imx-forge
strings /tmp/uboot-batch2-evk/u-boot-dtb.imx | grep '^U-Boot 2'
```

```text
U-Boot 2026.10-dirty (Nov 14 2026 - 17:02:31 +0800)
```

banner 不是玄学，它是镜像里实打实的一段字符串。U-Boot 起来后头一件事就是把自己这段版本文本打到串口，文件里嵌着它，板子起来后串口里打出的还是它，同一句话的两次露面，中间隔着一次启动。咱们拿 strings 在产物目录的另一份文件 `u-boot-nodtb.bin`（拼接产物的前身，03 章的产物表里有它）里也能抓到同一行，出处同源。

## 二、上电前的对照表：每个预期值都给出处

光有时间戳还不够，banner 底下那一片行各有各的来历。咱们把要核的值全部整理成一张表，每个预期都在主机侧现抄过：

| 串口里该出现的 | 咱们的预期值 | 出处（主机侧已验） |
|---|---|---|
| 头一行 banner | U-Boot 2026.10-dirty (Nov 14 2026 - 17:02:31 +0800) | strings 抄自 u-boot-dtb.imx，第一节现贴 |
| 波特率 | 115200 | `.config` 第 1447 行 CONFIG_BAUDRATE=115200 |
| 倒计时 | Hit any key to stop autoboot: 2 | `.config` 里 CONFIG_BOOTDELAY=2，这句格式文本嵌在 u-boot-nodtb.bin 里 |
| 提示符 | => | `.config` 里 `CONFIG_SYS_PROMPT="=> "` |
| Model 行 | Freescale i.MX6 UltraLiteLite 14x14 EVK Board | dtb 根节点 model 属性，往下现抄 |
| DRAM 行 | 512 MiB | dtb memory 节点 reg = <0x80000000 0x20000000>，0x20000000 折合 512 MiB |
| 从哪个串口出声 | UART1（serial@2020000） | dtb chosen 节点的 stdout-path |

表格下半段的值全部来自 dtb。咱们拿 dtc 把设备树 blob 还原成文本，抓出四个关键字段（真实截取）：

```bash
# 主机 ~/imx-forge
dtc -I dtb -O dts /tmp/uboot-batch2-evk/u-boot.dtb | grep -E '^\s+(model =|device_type = "memory"|reg = <0x80000000|stdout-path =)'
```

```text
	model = "Freescale i.MX6 UltraLiteLite 14x14 EVK Board";
		stdout-path = "/soc/bus@2000000/spba-bus@2000000/serial@2020000";
		device_type = "memory";
		reg = <0x80000000 0x20000000>;
```

model 那行有个要交代的细节，UltraLiteLite 两个 Lite 叠在一起，不是咱们抄错，上游 EVK 设备树的原文就这样，板子打出来就该这么拼。memory 节点声明了 512 MiB 的内存，起点 0x80000000，0x20000000 折成十进制正好是 512 MiB。DRAM 行那个数是运行时探测出来的，探测结果与声明对得上，两道证据才算闭合。

U-Boot 打 Model 行时念的是自己随身带的 dtb，不是卡上另有的一份。03 章的拼接流水线交代过，`u-boot-dtb.imx` 的本体是 `u-boot.bin`，而它由 `u-boot-nodtb.bin` 与 `u-boot.dtb` 拼成，dtb 就在镜像里跟着一起烧。所以 Model 一旦念得出来，顺带证明的就是这份镜像自带的家谱读对了。板子身份那行的字符串咱们也验过，Board: MX6ULL 14x14 EVK 与格式文本 Model: %s 都住在镜像里，strings 一把就能抓到。

## 三、上电读串口：核三样，核到 => 为止

次序接上一篇，线接好、终端开好、再按复位。上电后的动静咱们分三步核。

头一步认时间戳。banner 一出来，咱们先对照第一节抄下的那行，17:02:31 一字不差，板上跑的才是 03 章出炉的这份。对不上时先别怀疑编译，两种更常见的情形排在前面。卡写偏了或者没写进去，上一篇教过读回核对，卡上第 1024 字节起应当是 d1 00 20 40，对不上直接重烧。拨码把 BootROM 指到了另一块介质，它从那边读了份旧货，旧货 banner 里的时间戳会告诉咱们那是哪一轮编的。两种都排除后时间戳还认识不出，再把怀疑还给镜像本身。

第二步认硬件两行。咱们把 DRAM 与 Model 当硬件自检来读，对上了含义比看起来多一层。Model 念得出来，说明随身 dtb 读对了。DRAM 探测出数，说明 DCD 把内存唤醒了（03 章讲过，DCD 是 BootROM 跳转前照单执行的寄存器清单，大头就是配内存），预期值 512 MiB 对着第二节表里的声明。banner 有了、DRAM 没了的板子，多半是内存这一关的活，去处记在下面的速查表里。

第三步落到提示符上。倒计时按 CONFIG_BOOTDELAY=2 走两秒，Hit any key to stop autoboot: 2 这句格式文本嵌在镜像里，咱们已经验证过它的存在。两秒走完，=> 出现，这是 CONFIG_SYS_PROMPT 的字面值。到这一步固件活没活不用再猜，咱们敲一个命令把交互层也验掉，version。它回显的头一行应当与 banner 相同，version 命令的说明文本 print monitor, compiler and linker version 就嵌在镜像里，命令是编进固件的。敲得进、回得出，串口收发双向都通，验收就算过了。想再核内存的，bdinfo 也开着（`.config` 里 CONFIG_CMD_BDI=y），把它的 DRAM start 与 size 跟 dtb memory 节点的 0x80000000、0x20000000 对一遍。

验收记录咱们顺手就能留档，把头一段输出存进文件，凭据就有了。minicom 里按 Ctrl+A 再按 L 开抓取，再按一次停，picocom 直接接个 tee：

```bash
# 主机 ~/imx-forge
picocom -b 115200 /dev/ttyUSB0 | tee uboot_boot_171.log
```

存下来的日志跟第二节的对照表放在一起，验收过了没过、哪一项对上哪一项没对，咱们翻记录就清楚，不用凭记忆。

还有一类行咱们提前打个招呼，免得虚惊。这张卡上只有 U-Boot，没有内核，倒计时结束后 U-Boot 会照 BOOTCOMMAND 找内核，找不到就一层层退：

```text
CONFIG_BOOTCOMMAND="run findfdt;mmc dev ${mmcdev}; if mmc rescan; then if run loadbootscript; then run bootscript; else if run loadimage; then run mmcboot; else run netboot; fi; fi; else run netboot; fi"
```

它先在 mmc 上找脚本与内核镜像，找不到就转 netboot 走网络，走不通超时停下，落回 => 提示符。这些报错行是预期内的，咱们验收时别被它们吓住，它们讲的是存储里没装内核，不是固件死了。验收认三样，banner、提示符、version 回显，报错行一步步怎么读，debug 卷的串口日志阅读那篇接着讲。

咱们顺手把可能见到的现象归拢成一张速查表，对号入座：

| 现象 | 最可能的根因 | 去处 |
|---|---|---|
| 串口一点动静没有 | 流控没关、TX/RX 接反、拨码不对、dd 偏移错 | minicom 篇、04 章 |
| 满屏乱码 | 波特率不对，或者地线没共 | minicom 篇、04 章 |
| banner 出了、时间戳对不上 | 板从别的介质读了旧 U-Boot | 本篇第一节、04 章拨码 |
| banner 出了、DRAM 行没跟上来 | DCD 配内存的活没干成 | debug 卷串口日志阅读 |
| banner、=>、version 回显齐全 | 验收通过 | 往下走移植篇 |

## 四、打不进命令行的排查

三列表过一遍，先对现象再动手：

| 现象 | 根因 | 解法 |
|---|---|---|
| 串口零输出 | 供电没到位、TX/RX 接反、波特率不匹配 | 核对接线（板卡 TXD 接适配器 RXD）、终端改回 115200、换一根 USB 转 TTL 再试 |
| 输出全是乱码 | 波特率或晶振偏差 | 终端逐档试 115200 附近的常用值，乱码有规律说明只差波特率，完全无规律查晶振与供电 |
| 倒计时跑完直接往下走 | bootdelay 时窗太短，按键时机错过 | 复位后立刻连敲回车，或提前按住任意键再上电；本篇验收的参考板走默认 2 秒，足够反应 |

这三行的根因都指向串口链路本身，还轮不到怀疑固件：第三节已经证明镜像里嵌着完整的提示符与命令文本，链路通了它们就会说话。

## 继续学习

- [净源码里没有咱们的板卡](./06_aes_vs_evk_diff.md)：EVK 与仓库里 AES 板的差别从这一篇铺开，验收过的产物该往移植走了。
- [七步造出咱们的板卡](./07_board_porting.md)：defconfig 与 Kconfig 的正题，改完配置回来把第二节的对照表重抄一遍再上电。
- [第一次上电与串口检查](../start/05_first_boot_check.md)：整条链路上电的视角（U-Boot 到内核到 rootfs），本篇只验到 U-Boot 为止。
- [串口日志阅读路线](../debug/03_serial_log_reading.md)：倒计时之后的报错行一步步怎么读的专门篇。
