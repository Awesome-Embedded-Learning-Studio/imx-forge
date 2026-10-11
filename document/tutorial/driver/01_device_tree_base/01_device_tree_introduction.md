---
title: 设备树与本仓的学习地图
---

# 01. 设备树与本仓的学习地图

## 前言：从抄地址说起

如果您跟着[字符设备教程](../00_chardev_base/)点亮过 LED，您对手里的 `led_reg.h` 应该还有印象：五个寄存器的物理地址，是一个个从芯片手册里抄进 C 代码的。那套代码在教程里工作得很好，代价也实打实，抄错一个数字，排查起来就是灾难。

麻烦追到底是同一个根子：硬件信息和驱动代码长在了一起。LED 从 IO03 换到 IO04，您要重新翻手册、改宏、重新编译。真拿同一颗芯片做了三款产品，您还得维护三份几乎一样的驱动。

设备树给的解法，咱们一句话就能说完：把硬件描述搬进一份文本文件，驱动在运行时自己来取。地址换了改文件，驱动不动，内核也不用重编。

这事在自家教程里只是别扭，咱们把视野放宽到内核社区，就是另一个量级。同一颗芯片会被做成成百上千块板子，旧办法的麻烦跟着翻成百上千倍。这段历史里最有名的一幕，发生在 2011 年的内核邮件列表上。

## Linus 的愤怒：ARM 内核源码为什么那么大

那时候 ARM Linux 的发展遇到了一个尴尬的问题，咱们今天看来会觉得难以置信：内核源码变得越来越大，大到让 Linus Torvalds 都忍不住爆了粗口。

> "This whole ARM thing is a f*cking pain in the ass."
> （这该死的 ARM 事儿真是一团糟。笔者照原话直译。）

不是开玩笑，而是 Linus 在邮件列表里真的说出来的（您可以搜一下，太出名了）。那么问题来了，为什么 ARM 会让他这么头疼？

答案在于一个叫做"板级信息硬编码"的历史遗留问题，咱们拆开看。

在 3.x 版本之前的 Linux 内核里，ARM 架构处理硬件描述的方式非常直接——直接写在 C 代码里。您在那个年代的内核源码里能看到大量的 `arch/arm/mach-xxx` 和 `arch/arm/plat-xxx` 文件夹，里面全是描述板级信息的 `.c` 和 `.h` 文件。

我们来想象一个具体的场景。假设您手里有一块开发板，板子上有 CPU，有内存，有挂在 I2C 总线上的触摸屏和 EEPROM，还有 SPI 接口上的 Flash 芯片。作为开发者，您需要告诉 Linux 内核这些硬件都存在、它们接在哪条总线上、地址是多少。

在旧的做法里，您得写一个 C 文件来描述这块板子。比如针对 SMDK2440 开发板，内核里就有这样一个文件：

```c
/* arch/arm/mach-smdk2440.c (片段) */
static struct s3c2410fb_display smdk2440_lcd_cfg __initdata = {
    .lcdcon5 = S3C2410_LCDCON5_FRM565 |
              S3C2410_LCDCON5_INVVLINE |
              S3C2410_LCDCON5_INVVFRAME |
              S3C2410_LCDCON5_PWREN |
              S3C2410_LCDCON5_HWSWP,
    /* ... 其他配置 ... */
};

static struct s3c2410fb_mach_info smdk2440_fb_info __initdata = {
    .displays        = &smdk2440_lcd_cfg,
    .num_displays    = 1,
    .default_display = 0,
    /* ... 其他配置 ... */
};

static struct platform_device *smdk2440_devices[] __initdata = {
    &s3c_device_ohci,
    &s3c_device_lcd,
    &s3c_device_wdt,
    &s3c_device_i2c0,
    &s3c_device_iis,
};
```

您看，上面这段代码只是在描述一块板子上的 LCD 配置和设备列表。这看起来很合理，直到您意识到：这仅仅是使用 2440 芯片的 **SMDK2440** 这 **一种** 板子。

使用 2440 芯片的板子有成百上千种，每换一块板子，哪怕只是改了一个电阻的连接，理论上您就需要修改内核源码，重新编译。随着 ARM 芯片爆发式增长，Linux 内核源码库里迅速塞满了这种"一次性"的板级代码。

这种做法让内核变得极其臃肿。就像您花大价钱去吃海鲜自助，结果进去发现全是炒面和凉菜，您肯定想骂人。Linus 看到 ARM 社区向主线内核提交了海量的、重复的板级描述文件时，他的反应和您差不多。

这次"震怒"改变了 ARM Linux 的历史。ARM 社区被迫引入了 PowerPC 等架构早已采用的技术，也就是咱们本卷的主角：**设备树**。

文本源文件叫 dts，内容是一棵描述硬件的树。它不直接进内核，要编译成二进制的 dtb，内核启动时把 dtb 展开成自己能查的树，驱动再从树上取地址。换板子的时候，您改的是描述文件，驱动一行不动。

那次变革更细的沿革考据（邮件列表里一步步怎么吵出方案来的）咱们不在本卷展开，想深挖的话，文末的深读路线留给您。本卷只管一件事：在这个仓库里把设备树真正用起来。

## 本仓的设备树长在哪

道理说完了，咱们直接进仓库认文件。全仓自己维护的设备树都住在 `driver/device_tree/alpha-board/` 下面，把目录列出来看：

```bash
ls -1 driver/device_tree/alpha-board/
```

```text
05_tutorial_pinctrl_gpio
11_tutorial_device_tree_try
15_tutorial_beep
16_tutorial_platform_led
17_tutorial_key_gpio
18_tutorial_key_debounce
19_tutorial_key_input
20_tutorial_ap3216c_iic
21_tutorial_icm20608_spi
22_tutorial_goodix_touchscreen
23_tutorial_rtc_snvs
24_tutorial_wm8960_audio
example-driver
linux
uboot
```

头一回面对这串目录容易发怵，其实您抓住一层规律就够了：编号目录配教程，剩下三个各管一摊。

编号目录是给各篇驱动教程配的树，编号跟着 `driver/` 下的教程目录走，您对着两边的目录名就能互认。05 配引脚复用，15 配蜂鸣器，20 往后是 I2C、SPI、触摸、RTC、音频这些外设。目录里各有一份 `.dts`，名字大多形如 `imx6ull-aes-20_tutorial_ap3216c_iic.dts`。按键教程那三章不带编号，都叫 `imx6ull-aes-key.dts`，三个目录里各是配自己教程的一份，model 与 compatible 都不一样，您拿串了目录，实验就对不上号。11 里的那棵树，就是[驱动改造一章](03_device_tree_driver.md)要吃进驱动的主角，个别编号和 `driver/` 对不上属于历史遗留，到那章会专门交代。

不带编号的三个目录，咱们挨个认一遍。`linux/` 收着 Linux 侧的主设备树：`imx6ull-aes.dts` 是主文件，`imx6ull-aes.dtsi` 是它 include 进来的板级配置，旁边还有内核配置模板 `imx6ull_mainline_defconfig.template`。`uboot/` 放的是 U-Boot 轨用的同类文件，两边的 `imx6ull-aes.dts` 一模一样，差别都在 `imx6ull-aes.dtsi` 上，Linux 侧和 U-Boot 侧的板级配置各是各的，取用时看准目录。`example-driver/` 是一份不对应真实硬件的示例树，拿来验证编译链路正合适。

主设备树长什么样，咱们看个节选：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dts（节选）
/dts-v1/;

#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"
#include "imx6ull-14x14-evk-u-boot.dtsi"

/ {
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};
```

三行 include 就是设备树的分层。`imx6ull.dtsi` 住在内核源码里，描述 i.MX6ULL 这颗芯片本身，几个 UART、GPIO 控制器在哪，由它说了算。`imx6ull-aes.dtsi` 是咱们自己维护的板级文件，板上装了哪些外设、引脚怎么复用，写在它里面。第三行的 `imx6ull-14x14-evk-u-boot.dtsi` 来历不一样，它是 U-Boot 侧给 EVK 参考板补的片段，本仓源码里找不到，要从 `third_party/uboot-imx` 子模块里取，各教程的树也都没带它，这算是主设备树和它们的一处差别。分工有点像 C 里的头文件与源文件，芯片级的不动，板级的往上叠。

文件名里的 aes 是咱们仓库自己的板卡身份，全称 Awesome Embedded Studio，`model` 里写的正是它，板子启动后内核日志的 Machine model 一行报的也是它。硬件参考的是正点原子的 IMX6ULL Alpha 开发板，目录名 alpha-board 就从这来：板子是那块 Alpha，软件身份归 aes。

`compatible` 的两个值就是拿来做驱动和设备配对的，内核怎么靠它认设备，等咱们走到后面的平台设备驱动教程再细看，现在您混个脸熟就行。

## 从 dts 到板子

dts 里有 `#include`，直接喂给编译器 `dtc` 会报错，所以编译分两阶段：用 C 预处理器把 include 展平，再交给 `dtc` 编出 dtb。内核源码树自己编设备树走的也是同一套流程。要走通它，咱们手头得有那几个 include 的来源。

`imx6ull.dtsi` 住在内核源码里，U-Boot 的片段住在 U-Boot 源码里，动手之前您得把 `third_party/linux_mainline` 和 `third_party/uboot-imx` 两个 submodule 都初始化检出。本仓的内核轨只有 mainline 7.1.0 一条，没有第二棵内核树，本卷所有命令对着的都是它。

日常编译部署不用手敲长命令，仓库备好了脚本。`./scripts/driver_helper/build_driver.sh` 把驱动和设备树一起编出来，`./scripts/driver_helper/deploy_driver.sh` 负责部署。dtb 通过 TFTP 部署，U-Boot 启动时按 `fdt_file` 环境变量里写的名字加载，本板认的是 `imx6ull-aes.dtb`。编译、部署的具体命令咱们一起留到动手环节，到时候一步一步走。

## 本卷的学习地图

产物链有了全貌，学习路线就好画了。本卷五章，这一章是地图，后面四章一条线：读懂别人的树，改自己的驱动，独立走一次板级修改，最后把整条链路亲手走通。咱们一章一章看过去。

[语法速览一章](02_device_tree_syntax.md)教您看懂本仓的 dts，节点、属性、phandle、单元格计数、引用覆盖，讲到能独立读懂 `imx6ull-aes.dtsi` 为止。语法全貌是个深水区，本卷只取读懂所需的那段深度，更深的留给深读路线。

[驱动改造一章](03_device_tree_driver.md)是本卷主干。咱们拿仓库里真实的 `led_hw.c` 开刀，分六步从抄地址改造成去设备树取地址，然后编译、部署、在板子上点灯。

[板级修改一章](04_board_dts_modification.md)把镜头转向设备树本身，咱们在既有板级 dts 上加一个节点，编译、部署、验证走完整流程，仓库的构建、部署、查看三个脚本全程陪着。

[毕业项目一章](05_complete_practice.md)负责收尾。从一份接近空白的 dts 起步，您自己加节点、自己写驱动，一路走到板子上亮灯，整条链路走通了才算毕业。

四章的依赖是单向的：语法不熟就动驱动，等于您闭着眼睛改代码，所以顺序建议照排。手上已经有经验的您，直接跳去动手也行，卡住了再回头补对应的前章。

动手之外还备着一本工具书：[设备树配置指南](../../../modules/DEVICE_TREE_GUIDE.md)。LCD、网络、存储这些外设怎么配，换一块板子怎么移植，它按条目整理好了。本卷不重复那些内容，需要查配方时咱们再去翻它。

## 下一步

设备树此刻在您眼里还是棵陌生的树，也不要紧，下一章咱们就从最近的距离开始：把本仓的 dts 一行行读明白。

::: details 深读：设备树的历史与原理
上面那段 Linus 的故事只是引子，当年邮件列表里设备树方案一步步怎么吵出来的完整考据，dtb 的二进制格式里装了什么，内核启动时怎么把一张扁平的 dtb 展开成 `/proc/device-tree` 里那棵能逐节点查看的树，这些原理内容本卷不展开，咱们留给后续的深读专题慢慢补。
:::
