---
title: 编译、外挂模块与 QEMU 首启验收
---

# 编译、外挂模块与 QEMU 首启验收

> 板级设备树文件对已经写好并注册给构建系统，本篇咱们把它们变成能跑的东西：编出 zImage 与 dtb 两个产物，给驱动篇编出第一颗外挂模块，然后在 QEMU 里首启，闯一遍 15 项断言验收，末尾交代您在实际的板子上电要注意什么。上一篇 [设备树：从参考板改出 AES 板](./07_dts_writing.md) 造好了硬件描述，本篇做完，从零移植就此收官；下一篇 [DRM 显示系统移植](./09_display_drm.md) 钻进显示子系统。

::: tip 前置知识·环境
- 前置章：[设备树：从参考板改出 AES 板](./07_dts_writing.md)、[内核配置：动手做出自己的 defconfig](./06_defconfig_customize.md)、[从零开始搭建主线内核编译环境](./02_env_setup.md)
- 源码树 ~/experiments/linux-mainline（v7.2.9），构建目录 ~/experiments/linux-build（两目录制见 05 篇），本篇所有 make 命令都带 O= 指向构建目录
- QEMU 起机需要一份 rootfs 镜像与 qemu-system-arm：环境篇已备好 rootfs（本篇沿用），qemu-system-arm 用发行版包即可
- 交叉工具链 arm-none-linux-gnueabihf-（Arm GNU Toolchain 15.2.Rel1）
:::

## 编译：zImage 与 dtb 两个产物

编译还是 05 篇那条 O= 命令，多一个 dtb 目标。这里有个新坑先踩给您看：dtb 目标得写子目录限定的全名，直接写文件名会扑空：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx6ull-aes.dtb
```

```text
make[3]: *** No rule to make target 'arch/arm/boot/dts/imx6ull-aes.dtb'.  Stop.
```

kbuild 把裸文件名解析到了旧目录 arch/arm/boot/dts/ 下（上游重组后真身在 nxp/imx/ 子目录），所以报 No rule。咱们写上子目录限定就对了：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j16 zImage nxp/imx/imx6ull-aes.dtb
```

```text
  LD      arch/arm/boot/compressed/vmlinux
  OBJCOPY arch/arm/boot/zImage
  Kernel: arch/arm/boot/zImage is ready
```

两个产物落在构建目录里，数一下个头：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
ls -l ~/experiments/linux-build/arch/arm/boot/zImage \
      ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
```

```text
-rw-r--r-- 1 charliechen charliechen   35594 Oct 12 08:41 /home/charliechen/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
-rwxr-xr-x 1 charliechen charliechen 10369960 Oct 12 08:44 /home/charliechen/experiments/linux-build/arch/arm/boot/zImage
```

zImage 约 10.4MB（未做 06 篇第七节的裁剪），dtb 三万五字节。编出来的 dtb 值得随手反编译看一眼开头，model 和 chosen 直接告诉咱们内核将以什么身份、在哪个串口说话：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
~/experiments/linux-build/scripts/dtc/dtc -I dtb -O dts \
    ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb | sed -n '1,12p'
```

```text
/dts-v1/;

/ {
	#address-cells = <0x01>;
	#size-cells = <0x01>;
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

	chosen {
		stdout-path = "/soc/bus@2000000/spba-bus@2000000/serial@2020000";
	};
```

后面截断。咱们看得出来，源码里的 label 在产物里都换成了数字 phandle（比如触摸节点的 `pinctrl-0 = <0x0d 0x34>`），反编译产物读起来没有源码亲切，但它是内核真正吃到嘴的东西，核对死活就看它。

## 模块首编：给驱动篇铺的路

从零内核不只编镜像，驱动篇的教程模块（icm20608 六轴 IMU）也要对着这棵树编。外挂模块在 v7.2.9 上有三道前置，少一道都编不出来，咱们按真实的报错顺序走一遍。

第一道：构建目录里得有 scripts/module.lds。它是链接 .ko 时的地基，`make zImage` 不产它，咱们得显式跑一次 modules_prepare：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
```

```text
  LDS     scripts/module.lds
```

缺它长什么样？笔者在补这一步之前硬闯过，modpost 之后的最后链接阶段报：

```text
make[3]: *** No rule to make target '21_tutorial_icm20608_spi_driver.ko', needed by '__modfinal'.  Stop.
```

这条报错相当误导：它说 .ko 没有规则可编，但您明明什么都没改坏，真相是 %.ko 这条链接规则把 module.lds 列为前置件，地基缺席，整条规则作废，报错却记在 .ko 头上。看到 No rule to make target 'xxx.ko'，先查 module.lds 在不在。

第二道：符号表。模块链接时要对照内核导出的符号地址，这表在构建目录的 vmlinux.symvers 里；而外挂模块构建流程读的是老名字 Module.symvers。kbuild 在这次改版里改了名、没留兼容，咱们自己补一个软链：

```bash
# 主机 ~/experiments/linux-build(构建目录)
ln -s vmlinux.symvers Module.symvers
ls -l vmlinux.symvers Module.symvers
```

```text
lrwxrwxrwx 1 charliechen charliechen     15 Oct 12 08:44 Module.symvers -> vmlinux.symvers
-rw-r--r-- 1 charliechen charliechen 786789 Oct 12 08:43 vmlinux.symvers
```

第三道：调用姿势。外挂模块必须用 O= 指向构建目录来编，这正是 05 篇立下两目录制的回报：源码树从头到尾没被原地构建污染过，O= 通道畅通。假想一下反例：您要是前几篇一直在源码树里原地编，这里再开 O=，kbuild 会直接拒绝，报 The source tree is not clean。

三道前置齐了，咱们编模块（教程模块源码取自驱动篇 SPI 一章，放任意目录都行）：

```bash
# 主机 模块源码目录
make -C /home/charliechen/experiments/linux-mainline \
    O=/home/charliechen/experiments/linux-build \
    ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- \
    M=$PWD modules
```

```text
  LD [M]  21_tutorial_icm20608_spi_driver.o
  MODPOST Module.symvers
  CC [M]  21_tutorial_icm20608_spi_driver.mod.o
  CC [M]  .module-common.o
  LD [M]  21_tutorial_icm20608_spi_driver.ko
```

11960 字节的 .ko 出炉。两个配套的坑一并交代，都是笔者实测撞过的：其一，模块与内核必须同源同 config，拿旧树的 .ko 往新内核上 insmod，内核报 `.gnu.linkonce.this_module section size must match the kernel's built struct module size`（config 不同导致结构体尺寸对不上）或 `disagrees about version of symbol module_layout`（版本对不上），一律回炉重编；其二，模块目录里若有上次的旧 .o，kbuild 会跳过重编直接复用，坑就从这里来：换内核重编模块前，把模块目录里的 .o、.cmd、.ko 清干净。

## QEMU 首启：15 项断言验收

镜像、dtb、模块三样齐了，咱们起机。QEMU 用 mcimx6ul-evk 机型直启内核（不经过 U-Boot），一条命令：

```bash
# 主机 任意目录
qemu-system-arm \
    -machine mcimx6ul-evk -m 512M \
    -kernel ~/experiments/linux-build/arch/arm/boot/zImage \
    -dtb ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb \
    -append "console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw" \
    -drive file=<rootfs 镜像>,if=sd,index=1,format=raw \
    -nic user \
    -nographic
```

rootfs 镜像用环境篇备好的那份；模块要 insmod 的话，您先用 debugfs 把 .ko 塞进镜像的 /root/。串口就是当前终端，Ctrl-A X 退出。

起机之前有一层等价性纪律值得咱们单说。QEMU 加载的就是实际的板子那棵 dtb：唯一的例外是两颗网卡的 `local-mac-address`。为什么 MAC 必须补？咱们把内核给网口找 MAC 地址的顺序说全。内核先看设备树里的 `mac-address`/`local-mac-address` 属性；都没有，再去查 ocotp 的 MAC fuse cell。i.MX6ULL 的 MAC fuse 出厂没烧写，fuse 空着、读回的值无效，内核再落到 FEC MAC 寄存器里 bootloader 写过的值。bootloader 也没写过的话，最后才是随机 MAC，dmesg 会打印 Using random MAC address。QEMU 的卡点在第二步：`of_get_mac_address()` 查 ocotp 的 nvmem cell 落空，两颗 FEC 一起卡在 deferred probe 里起不来。实际的板子上这个缺由 U-Boot 拿环境变量里的 ethaddr 在开机 fixup 时补进 dtb；QEMU 没有 U-Boot，咱们在起机前用 fdtput 往 dtb 副本里补同样的两个属性（FEC1 写 00:11:22:33:44:01，FEC2 写 00:11:22:33:44:02），改动打在编译产物上，恰好就是 U-Boot 动手的位置，dts/dtsi 源文件零改动，所以 QEMU 里验证过的结论对实际的板子同样成立。

15 项断言的完整验收是仓库的 e2e-test.sh 采的（它认 PROJECT_ROOT 环境变量，指向您自己的产物目录即可复用；本篇表格即笔者对这棵从零树跑出的原始记录）：

| 断言 | 判定输出 | 实测 | 验证了什么 |
|---|---|---|---|
| rtc-walk | RTCDELTA | 2 | RTC 注册为 rtc0，系统时钟走时正常 |
| net-dhcp-ping | NETRC | 0 | eth1 链路 Up，DHCP 拿到地址并 ping 通 10.0.2.2 |
| can0 | CAN0 | yes | flexcan1 注册出 can0 接口 |
| pwm-backlight | PWM | yes | pwmchip0 在位 |
| pwm-backlight | BL | yes | 背光设备在位 |
| display-fb | FB | yes | fb0 帧缓冲设备在位 |
| display-fb | MXSFB | yes | dmesg 有 Initialized mxsfb |
| usb-bus | USBN | 9 | 两条 ci_hdrc USB 总线起来 |
| sd-card | MMC | yes | QEMU 把 rootfs 卡挂到 USDHC2（if=sd,index=1）注册为 mmcblk1 并作根挂载；板上 usdhc1 SD 槽在 QEMU 中无卡，cd-gpios 插拔路径未被本次断言覆盖 |
| ap3216c-als | ALS | 0x0126 | i2c1 0x1e 光照寄存器读数有效 |
| icm20608-probe | ICM | yes | 模块 insmod 成功，SPI 驱动认出 ICM20608 |
| gt911-probe | GT911 | yes | Goodix-TS 报出 ID 911 |
| wm8960-codec | WM8960 | 0x00 | i2c1 0x1a 有应答（控制面寄存器模型，裸读有应答） |
| gpio-inject | GPIOFLIP | yes | 注入电平后 GPIO1_PSR 位 18 翻转 |
| deferred-list | DEFER_EXTRA | 0 | 除已知项外无设备卡在 deferred probe |

15 项全过。这份成绩单的分量在 icm20608-probe 那一行：它是唯一一项考验"模块与内核同源"的断言，本篇模块节编出的 .ko 塞进 rootfs 后 insmod 干净落地。从零内核加自编驱动，整条链都是您树里的产物。

咱们挑三条细看。rtc-walk：日志里 `snvs_rtc 20cc000.snvs:snvs-rtc-lp: registered as rtc0`，随后脚本取时间戳、睡 2 秒、再取，差值恰好 2。它验证的是一整条链：dts 里 snvs 节点活着、驱动 probe 成功、内核拿它当了时钟源、时间真的在走。时间类断言的好处是没法造假：时钟不走，差值就是 0。

wm8960-codec：`i2cget -y 0 0x1a 0x19` 读回了 0x00，说明 i2c1 总线上 0x1a 有器件应答，总线与地址都对。另一面也得说全：日志里同时有 `wm8960 0-001a: Not wm8960, wm8960 reg can not read by i2c`，内核驱动 probe 失败（-22）。翻脸的机制值得交代：驱动探测时用一次裸 i2c 读来认芯片，真 wm8960 恰恰对这种裸读不应答，QEMU 的控制面寄存器模型却应答了，驱动据此打印 Not wm8960 并返回 -EINVAL。所以这条断言验证的是咱们 dts 里 `wm8960@1a` 的挂载位置与地址，音频链路整体要在实际的板子上验。

gt911-probe 这条咱们细看：`Goodix-TS 1-005d: ID 911, version: 0020` 加一条 input 设备注册日志。这验证的就不只是地址了：驱动绑定成功，意味着中断 GPIO（GPIO1_IO09）、复位 GPIO（GPIO1_IO05）、pinctrl 组全都配对了——还记得 07 篇战史三吗？这根中断脚差点被 SD 电源调节器的参考板写法占走，现在是触摸的。日志里 `goodix_911_cfg.bin` 加载失败（-2）是固件文件缺失，驱动带着默认配置继续跑，不致命。

## 在实际的板子上电

::: warning 未实测标注
在实际的板子上电（U-Boot 引导、tftp/netboot 拉 zImage 与 imx6ull-aes.dtb，或烧写 SD/eMMC）咱们在本环境没有硬件可跑：QEMU 的 mcimx6ul-evk 是直启内核，不经过 U-Boot 链路。操作以您所用 U-Boot 的 bootz 参数为准，串口输出以实际板子为准。
:::

在实际的板子上您要注意引导参数里的 dtb 必须是本文这份 `imx6ull-aes.dtb`，别拿成内核树里其它板子的。还有触摸地址：QEMU 侧写 0x5d，实际的板子上实测 0x14（07 篇战史二），实际的板子验证触摸按驱动篇触摸章的板级 dts 来。

## 坑速查

本篇的坑都散在正文里了，咱们收个尾，一张表备查：

| 现象 | 根因 | 解法 |
|---|---|---|
| make 报 No rule to make target 'arch/arm/boot/dts/imx6ull-aes.dtb' | dtb 目标没写子目录限定，kbuild 去旧目录找了 | 目标写成 nxp/imx/imx6ull-aes.dtb |
| dtc 报引用了不存在的节点或 label | `&xxx` 拼写与 SoC dtsi 里的 label 对不上 | 在 `imx6ul.dtsi`（必要时连同 `imx6ull.dtsi`）里 grep 该 label 核对拼写 |
| 触摸或其它 GPIO 器件 probe 报 -EBUSY | 一根 GPIO 两个主人（参考板的电源使能脚与本板中断脚撞车） | 对原理图裁决归属，删掉输家的 gpio 声明（07 篇战史三） |
| 模块编到 modpost 后报 No rule to make target 'xxx.ko', needed by '__modfinal' | 构建目录缺 scripts/module.lds，%.ko 链接规则作废 | `make O=... modules_prepare` 后重编 |
| 模块编过但链接时报符号未定义 | 构建目录缺 Module.symvers 符号表 | `ln -s vmlinux.symvers Module.symvers` |
| insmod 报 disagrees about version of symbol module_layout，或 struct module section size 不匹配 | 模块与内核不是同一次配置构建的产物 | 同一棵 O= 树、同一份 .config 重编模块，先清掉模块目录旧产物 |
| 网口 MAC 不确定，每次起机可能不同（dmesg 报 Using random MAC address，或探测早期短暂 deferred） | MAC fuse 没烧写，DT 里又没有 `local-mac-address`，内核查 ocotp 落空 | 引导固件补 MAC：U-Boot 配 ethaddr，QEMU 起机前 fdtput 补 |
| i2c 子设备 probe 报 -6 ENXIO | `reg` 地址与实际器件不符 | `i2cdetect` 扫总线确认地址再写 `reg` |
| spi 子设备乱码或不响应 | `spi-max-frequency` 超器件规格，或 `reg` 片选编号与 `cs-gpios` 对不上 | 对器件手册核频率；片选编号从 0 数 |
| 屏幕花屏或不亮但 fb0 在 | `panel-timing` 时序与屏不符 | 对屏幕手册逐项核时序，像素时钟错最常见 |

## 继续学习

- 上一篇：[设备树：从参考板改出 AES 板](./07_dts_writing.md)，板级文件对怎么写
- 下一篇：[DRM 显示系统移植](./09_display_drm.md)，显示子系统深读，把 07 篇 lcdif 那条链拆到驱动层
- 跨卷：[主线内核调试技巧](./12_debug_tricks.md) 与 [常见问题与解决方案](./13_common_issues.md)，起机不顺时按图索骥
