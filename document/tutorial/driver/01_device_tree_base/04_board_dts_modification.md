---
title: 板级 dts 修改与部署
---

# 04. 板级 dts 修改与部署

> 08 章里设备树是现成的，咱们只动手改了驱动；这一章镜头转回树本身：在既有板级 dts 上加一个 LED 节点，走完加节点、编译、部署、验证的完整闭环。三个仓库脚本全程陪同，build_driver.sh 管编译，deploy_driver.sh 管部署，show_device_tree.sh 管查看。读完这一篇，您面对一块新板子时该动哪个文件、产物怎么进板子、怎么确认改动真的生效，心里就有了一条完整的链路。

::: tip 前置知识 · 环境
- [语法速览一章](02_device_tree_syntax.md)讲过的节点、属性、cells、引用覆盖，本章直接拿来用，不再重讲
- [驱动改造一章](03_device_tree_driver.md)里驱动按 `/imx_aes_led` 路径找节点、读五组 reg 地址，本章动手的这棵树就是喂给那个驱动的树
- 动手前提：`third_party/linux_mainline` 和 `third_party/uboot-imx` 两个 submodule 先初始化检出，再往内核树打上本仓补丁（`./scripts/apply_patches.sh linux_mainline`）。本篇全部实测命令跑在这套环境就位的仓库上
- 路径上下文：本篇命令都在仓库根目录 `~/imx-forge` 下执行，动手对象是 `driver/device_tree/alpha-board/` 下的板级 dts 和 `driver/06_tutorial_device_tree_try/` 下的驱动，内核源码对的是 `third_party/linux_mainline`（mainline 7.1.0，本仓唯一内核轨），交叉工具链前缀 `arm-none-linux-gnueabihf-`，设备树编译走 gcc 预处理加 dtc 两段
:::

## 前言：树是现成的，直到轮到咱们改它

08 章咱们把 `led_hw.c` 从抄死地址改造成运行时去树里取地址，但那棵树从头到尾是现成的，咱们一行都没动过它。真实开发里的节奏常常反过来：拿到一块板子，头一件事是改树，加一个节点、开一个外设、让一组引脚复用，然后才轮到写驱动。改树本身不难，语法咱们在 03 章练过了；真正容易把人卡住的是它周围那一圈：编出来的 dtb 怎么变成板子手里那一份、部署完了怎么确认内核吃到的确实是新树、改了没生效时该沿哪条链路排查。

这一章咱们就把这一圈走通。动手对象是仓库里现成的一份教程树，咱们在它身上加节点；编译环节您会亲眼看到脚本编出了 `.ko` 却没有 `.dtb`，然后把手动编译补上；部署环节讲清楚 dtb 走 TFTP、ko 走 NFS 这套分工；验证环节的判据有两个，`/proc/device-tree` 里查节点，`dmesg` 里的 Machine model 一行对 model 字符串。判据先放在这儿，走到时咱们逐一对上一遍。

## 动手对象：六百字节的薄壳

咱们的动手对象在树的目录里。把目录列出来看：

```bash
# 主机 ~/imx-forge
ls -la driver/device_tree/alpha-board/11_tutorial_device_tree_try/
```

```text
total 12
drwxr-xr-x 2 charliechen charliechen 4096 Jun  9 19:18 .
drwxr-xr-x 17 charliechen charliechen 4096 Jul  4 10:29 ..
-rw-r--r-- 1 charliechen charliechen  616 Jun  9 19:18 imx6ull-aes-11_tutorial_device_tree_try.dts
```

整个目录就一份 616 字节的 dts。这里得交代一处历史遗留：树目录编号是 11，吃这棵树的驱动目录却是 `driver/06_tutorial_device_tree_try/`，两边对不上。来历 08 章专门讲过，咱们记住结论就行：驱动是 06，树是 11，后文所有命令里的目录名都以这两个真实编号为准。

文件全文贴出来，一共二十来行：

```dts
// driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts（全文）
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
	model = "Awesome Embedded Studio IMX6ULL Example Driver";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
	/**
	 * PS 下，可以看到我们在/下追加了一个新的LED等节点
	 */
	imx_aes_led {
		#address-cells = <1>;
		#size-cells = <1>;
		compatible = "atkalpha-led";
		status = "okay";
		reg = < 0X020C406C 0X04 /* CCM_CCGR1_BASE */
				0X020E0068 0X04 /* SW_MUX_GPIO1_IO03_BASE */
				0X020E02F4 0X04 /* SW_PAD_GPIO1_IO03_BASE */
				0X0209C000 0X04 /* GPIO1_DR_BASE */
				0X0209C004 0X04 >; /* GPIO1_GDIR_BASE */
	};
};
```

咱们从头往下读。两行 include 的来历 03 章讲过：`imx6ull.dtsi` 住在内核源码里，描述 i.MX6ULL 这颗芯片；`imx6ull-aes.dtsi` 是本仓自己维护的板级文件，板上外设、引脚复用都写它在里面。这份教程树没有 include 主树带的那份 U-Boot 侧片段，所以编译时不需要 U-Boot 的 include 目录，这点后面跑命令时会再对上一次。

根节点上两个属性值得多看一眼。`compatible` 和主树一模一样；`model` 却不同，主树写的是 `Awesome Embedded Studio IMX6ULL (i.mx NXP)`，这里写的是 `Awesome Embedded Studio IMX6ULL Example Driver`。这个差异有专门的用处，是咱们验证环节的锚点：内核启动日志里的 Machine model 一行报的就是 dtb 里的 model 值，各章的 dtb 互斥地占用 `imx6ull-aes.dtb` 这一个名字，板子到底加载了哪份树，看 model 字符串一眼就能分辨。这个用处留到验证一节，到时候拿它认树。

### 五组地址，一组都不能少

`reg` 是这个节点的核心。五组“地址、长度”对，每组长 4 字节，五个地址正是 08 章里 `led_reg.h` 从芯片手册抄出来的那五个宏：CCM 时钟门控、引脚复用、引脚电气属性、GPIO 数据寄存器、GPIO 方向寄存器。08 章把它们从 C 常量搬进了树，驱动用 `of_iomap` 按索引一组组映射回来，索引 0 到 4 对应这里的五组。咱们在树里加减一组，驱动里 `of_property_read_u32_array` 的长度参数就得跟着动，两边是绑死的。

地址后面的注释写着寄存器名，这个习惯值得您保持。设备树没有类型系统帮咱们兜底，注释就是它唯一的自解释手段，半年后回看这份文件，救咱们的是注释而不是记忆。

### compatible 的血统

`compatible = "atkalpha-led"` 这个值的来历 08 章交代过：它跟着正点原子 Alpha 开发板的血统来的，和本仓的 aes 身份对不上，但那个驱动按路径找节点、不做 compatible 匹配，所以值是什么不影响运行。咱们在这里保持原值，不去悄悄换掉它，把来历说清楚比涂改更诚实。

### 节点里那两行 cells，其实没有活干

`#address-cells` 和 `#size-cells` 写在节点里，管的是这个节点的孩子怎么切 reg。`imx_aes_led` 底下一个孩子都没有，这两行实际上不起作用。真正管它自己 reg 切分的是根节点上那对度量衡，1 加 1，写在内核 `imx6ul.dtsi` 的根上，03 章读过它。这两行留着无害，删掉也一样，咱们知道谁在干活就行，别被教程里的冗余行带偏了认识。

## 把节点亲手加一遍

这份 dts 出厂就带着 `imx_aes_led` 节点，加节点的动作咱们这样练：把 `imx_aes_led { ... };` 整段删掉，保存，然后凭对结构的理解亲手加回来，值照着上一节的全文抄，不凭记忆编。加完拿 `git diff` 看一眼，改动应该只有这一个节点。

动手时有三处标点最容易出问题，咱们提前点名。属性行末的分号一个不能少，包括没有值的属性；`reg` 的五组数装在尖括号里，组与组之间用空白分隔；`0X020C406C` 这种大写 0X 前缀和 `0x` 小写前缀在 dtc 眼里等价，照抄原文即可。漏分号的报错有个脾气，03 章拿玩具实验验证过：dtc 把错误标在漏分号那行的下一行，看到 syntax error 又找不到错处，您就往上一行查分号。

节点挂在根下还是挂在总线节点下，判断标准 03 章讲过：看设备属于谁。这个 LED 直接操作 GPIO 寄存器，不挂在任何总线上，所以咱们把它放在根 `/` 下面，完整路径是 `/imx_aes_led`，这个路径就是驱动里 `kIMX_AES_LED` 常量的值。

## 编译：脚本编出了 ko，dtb 得咱们自己补

### 脚本跑一遍，看到什么

编译的统一入口是 build_driver.sh，咱们传驱动目录名和板名：

```bash
# 主机 ~/imx-forge
./scripts/driver_helper/build_driver.sh 06_tutorial_device_tree_try alpha-board
```

笔者在本环境真跑了一遍，输出节选如下（它结尾会问是否部署，答 n 跳过）：

```text
[INFO] 构建驱动： 06_tutorial_device_tree_try/alpha-board
[INFO] 内核： mainline
[INFO] 编译驱动模块...
[INFO] ✓ 编译完成 (1 个模块)
[INFO] ✓ 构建完成： /home/charliechen/imx-forge/out/driver_artifacts/06_tutorial_device_tree_try/alpha-board
构建成功！
是否部署驱动? [Y/n]:
```

模块编出来了。咱们顺手验一下身份，vermagic 必须和板子运行的内核一致，不然 insmod 直接拒绝：

```bash
# 主机 ~/imx-forge
modinfo out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/device_tree_try_03_driver.ko | grep vermagic
```

```text
vermagic:       7.1.0-dirty mod_unload modversions ARMv6 p2v8
```

7.1.0，对得上本仓唯一的 mainline 内核轨。产物目录里现在有什么，咱们列出来看：

```bash
# 主机 ~/imx-forge
ls out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/
```

```text
build_info.txt  device_tree_try_03_driver.ko
```

只有 `.ko` 和构建信息，没有 `.dtb`。回头看上面的构建日志，从头到尾没有出现过“编译设备树”一行。原因 08 章讲过：脚本拿着驱动目录名 `06_tutorial_device_tree_try` 去 `driver/device_tree/alpha-board/` 下找同名子目录，落空；退回驱动目录里找 `.dts`，也落空；于是树这一步静默跳过，不报错也不留 dtb。这就是编号错位的实际代价，咱们的树在 11 号目录里躺着呢。dtb 得自己补，接着往下走。

### 两阶段：预处理展平，dtc 出 dtb

dts 里有 `#include`，直接喂 dtc 会报错，所以编译分两段：C 预处理器把 include 展平成一份长文件，dtc 再把展平结果编成 dtb。内核自己编设备树走的也是同一套流程。咱们先看一条会失败的跑法，报错很有教学价值：

```bash
# 主机 ~/imx-forge
cpp -nostdinc -undef -x assembler-with-cpp \
    -I third_party/linux_mainline/arch/arm/boot/dts \
    -I third_party/linux_mainline/arch/arm/boot/dts/nxp/imx \
    -I driver/device_tree/alpha-board/linux \
    driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts
```

```text
third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ul.dtsi:5:10: fatal error: dt-bindings/clock/imx6ul-clock.h: No such file or directory
    5 | #include <dt-bindings/clock/imx6ul-clock.h>
```

三条 `-I` 里没有内核的 `include/`，芯片级 dtsi 里那些尖括号包含的 dt-bindings 头文件就没了着落，预处理停在 `imx6ul.dtsi` 第 5 行。咱们补上第四条，完整命令如下，三条老 `-I` 的来历 08 章逐条讲过（内核 ARM 设备树公共目录、NXP imx 子目录、项目主板目录），第四条内核 `include/` 就是给这报错补的：

```bash
# 主机 ~/imx-forge
cpp -nostdinc -undef -x assembler-with-cpp \
    -I third_party/linux_mainline/arch/arm/boot/dts \
    -I third_party/linux_mainline/arch/arm/boot/dts/nxp/imx \
    -I third_party/linux_mainline/include \
    -I driver/device_tree/alpha-board/linux \
    driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts \
    > /tmp/imx6ull-aes-11.pp.dts \
 && dtc -I dts -O dtb -o out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb /tmp/imx6ull-aes-11.pp.dts
```

```text
third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi:176.14-182.4: Warning (unit_address_vs_reg): /imx_aes_led: node has a reg or ranges property, but no unit name
  also defined at driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts:11.14-21.4
third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ul.dtsi:995.23-1002.6: Warning (simple_bus_reg): /soc/bus@2100000/sim@021b4000: simple-bus unit address format error, expected "21b4000"
  also defined at third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi:432.7-446.3
```

预处理通过，展平结果 2185 行；dtb 编出来了，落在 `out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb`，共 36185 字节。落点不选 `/tmp` 而选产物目录，是因为部署一节的 tftp 目标只拷产物目录里的 `*.dtb`。两条警告咱们挨个看，它们都不是错误，dtc 照常出了产物。

头一条冲着咱们的节点来：`imx_aes_led` 带着 reg 却没在名字里写 `@地址`，规范写法应该形如 `imx_aes_led@20c406c`。地址不唯一的简单设备挂根下时，教程圈惯用的写法就是不带 `@`，这条警告可以容忍，知道它在说什么就行。第二条说 `sim@021b4000` 的单元名前头多了俩零，这是本仓补丁把 sim 节点补回内核树时带进来的老式写法，同样无害。

两条警告后面都跟着一行 `also defined at`，这个提示信息量很大，咱们单独说。它说 `imx_aes_led` 在两处被定义过：一处在共享的 `imx6ull-aes.dtsi` 里，一处在咱们这份教程 dts 里。dtc 对同名节点的处理是合并：同一属性后写的赢，一边独有的属性保留。再多看一眼警告里的路径：命中的 `imx6ull-aes.dtsi` 是内核树里那份副本（补丁放进去的），它和 `driver/device_tree/alpha-board/linux/` 下那份逐字节一致，笔者 diff 过；真要动这个共享文件时三处都得同步，这个坑咱们收进常见卡点。

### 查产物：show_device_tree.sh 三种用法

仓库备了一个查看脚本，咱们先看它的 `--help`，真实输出摘一段：

```text
用法: show_device_tree.sh <设备树文件> [选项]

选项:
  --all, -a     显示完整DTS内容
  --search, -s  搜索节点或属性
  --detailed, -d 显示详细信息
```

三种用法咱们各跑一遍。不带选项时它把 dtb 反编译成树形结构，高亮 compatible 和 status；`--all` 在树形之外追加完整反编译文本；`--search` 按关键词找。拿刚编出的 dtb 搜一把：

```bash
# 主机 ~/imx-forge
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb --search led
```

这一搜有个现成的坑等咱们。头二十条匹配里十七条是 `status = "disabled"`，另外三条是 `micrel,led-mode`、`led_grp` 这类同样含 led 字样的行，`imx_aes_led` 本尊在第 1601 行，压根没挤进前二十。原因不神秘：脚本的搜索就是 grep，disabled 这个词里正好含着 led 三个字母，满树的 disabled 把名额吃掉了大半。咱们把关键词换具体一点：

```bash
# 主机 ~/imx-forge
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb --search imx_aes_led
```

```text
🔍 搜索: imx_aes_led
══════════════════════════════════════════════════════

行 1601: 	imx_aes_led {
```

命中了。反编译文本的第 1601 行，咱们把那个节点前后取出来直接看：

```dts
// imx6ull-aes-11_tutorial_device_tree_try.dtb 反编译产物（节选）
imx_aes_led {
	compatible = "atkalpha-led";
	pinctrl-names = "default";
	pinctrl-0 = <0x4a>;
	status = "okay";
	led-gpio = <0x09 0x03 0x01>;
	#address-cells = <0x01>;
	#size-cells = <0x01>;
	reg = <0x20c406c 0x04 0x20e0068 0x04 0x20e02f4 0x04 0x209c000 0x04 0x209c004 0x04>;
};
```

这一段是编译环节的高光。咱们 dts 里只写了五个属性，产物里却多出 `pinctrl-names`、`pinctrl-0`、`led-gpio` 三个，它们从共享 dtsi 里的同名节点合并进来；`compatible` 两边都写了，dts 在 include 链的最后，`atkalpha-led` 赢了 dtsi 里的 `imxaes,led`。咱们亲手加的 reg 一组不少地躺在最后一行，五个地址和源文件一字不差。同名节点合并、后写的赢，03 章讲属性覆盖时立过的规矩，在节点这个层级原样成立。

## 部署：dtb 走 TFTP，ko 走 NFS

部署模型 01 章画过链路，咱们把链路落到动作上。U-Boot 启动时按 `fdt_file` 环境变量里写的固定名字从 TFTP 服务器拉 dtb，本板认的是 `imx6ull-aes.dtb`；内核起来后 rootfs 挂在 NFS 上，`.ko` 放进 rootfs 的 `lib/modules/` 里，板子上 insmod 即可。所以两类产物的去向不同，dtb 部署到 TFTP 目录，ko 部署到 NFS 目录，deploy_driver.sh 用 `--target` 区分：

```bash
# 主机 ~/imx-forge
# dtb 走 TFTP
./scripts/driver_helper/deploy_driver.sh 06_tutorial_device_tree_try alpha-board --target=tftp

# ko 走 NFS rootfs
./scripts/driver_helper/deploy_driver.sh 06_tutorial_device_tree_try alpha-board --target=nfs
```

部署目录不在命令里，在配置文件 `scripts/driver_helper/driver_helper.conf` 里，当前真值是 `TFTP_DIR="/home/charliechen/tftp"`、`NFS_DIR="rootfs/nfs"`，您机器上不一样就改这份 conf。

tftp 目标有两个行为值得点名。目标文件名会被改写成固定的 `imx6ull-aes.dtb`，不管产物原名带多长的教程后缀，落进 TFTP 目录就叫这个名字，U-Boot 只认它；覆盖之前脚本会先把旧文件改名留档，名字带 14 位时间戳。咱们看本机 TFTP 目录的真实现状：

```text
imx6ull-aes-20260621090534.dtb
imx6ull-aes-before-can2-fix.dtb
imx6ull-aes-before-dma-fix.dtb
imx6ull-aes-before-goodix-fix.dtb
imx6ull-aes-before-tutorial-full.dtb
imx6ull-aes.dtb
```

这份列表的来历得分开说：时间戳名的 `imx6ull-aes-20260621090534.dtb` 是 deploy_driver.sh 备份机制真跑留下的，脚本只会起这一种名字；四份 `before-*` 是历次修复时手动改名留的档，改个名留快照，是同一目录下的既有人工惯例。五份历史留档加一份现役，每次换树旧版都在，咱们真要回退时改个名就行。nfs 目标的行为也交代一句：`.ko` 拷进 `lib/modules/`，`.dtb` 顺手拷进 `boot/` 留档，但那份 dtb 不会被 U-Boot 加载，启动走的还是 TFTP 这条线，别指望它生效。

还有一条时间上的规矩，咱们记牢：dtb 是 U-Boot 在内核启动前就交给内核的，部署完必须重启板子才生效；ko 不用重启，insmod 即可。

::: warning 未实测标注
部署两条命令笔者本轮没有真跑：它们会直接覆盖 `/home/charliechen/tftp/imx6ull-aes.dtb`，决定这块板下次重启加载哪份树，写作时不宜动它。命令参数与脚本行为以 `deploy_driver.sh` 源码和 `driver_helper.conf` 为准；上面 TFTP 目录里的留档，时间戳名那份是脚本备份机制真跑所留，四份 before-* 是历次修复时的手动留档。
:::

## 板上验证：先查树，再点灯

板上的验证咱们按固定顺序走，顺序本身就是排查方法，08 章立过这条规矩：先确认内核手里的树里真有这个节点，再加载驱动。树里没有的话，驱动第一步找节点就会失败，问题出在 dtb 那一侧；树里有而驱动失败，问题才在驱动。把查树放在前面，为的就是把这两类问题分开。

第一步，咱们在板子上看内核展开出来的那棵树。`/proc/device-tree` 里每个节点一个目录、每个属性一个文件：

```bash
# 板端 /
ls /proc/device-tree/imx_aes_led/
cat /proc/device-tree/imx_aes_led/compatible
# atkalpha-led
cat /proc/device-tree/imx_aes_led/status
# okay
hexdump -C /proc/device-tree/imx_aes_led/reg
```

compatible 和 status 的输出咱们标在注释里了，reg 的十六进制转储里应该能看到五组地址。第二步，确认加载的确实是这份树而不是别的章的树：

```bash
# 板端 /
dmesg | grep "Machine model"
```

这一行报的正是 dtb 里的 model 值。咱们这份树的 model 是 `Awesome Embedded Studio IMX6ULL Example Driver`，和主树的 `(i.mx NXP)` 后缀不同；各章 dtb 共用 `imx6ull-aes.dtb` 一个名字、彼此互斥，model 字符串就是分辨它们的最快判据。第三步，加载驱动、点灯：

```bash
# 板端 /
insmod device_tree_try_03_driver.ko
dmesg | tail -30
ls -l /dev/AES_LED
echo 1 > /dev/AES_LED
echo 0 > /dev/AES_LED
rmmod device_tree_try_03_driver
```

咱们在 dmesg 里应该看到 08 章记录过的那一串输出，从 `dtsled node has been found!` 到 `reg data` 那行五个地址，再到 `LED Init OK!`。`echo 1` 写开、`echo 0` 写关，这块板的 LED 低电平点亮，写 1 是开。灯亮的那一下，从改树到点灯的闭环就算走完了。

::: warning 未实测标注
板端这一节的命令和输出，笔者本轮没有接板子，无法实测。命令序列与 08 章当时在板子上跑通的序列一致，dmesg 预期输出以 08 章的板端记录为准；model 字符串对照法依据的是 dts 源文件里的真值，不依赖本轮运行。
:::

## 常见卡点

| 现象 | 根因 | 解法 |
|---|---|---|
| build_driver.sh 跑完，产物目录只有 .ko 没有 .dtb | 驱动目录编号 06 与树目录编号 11 错位，脚本两处都找不到 .dts，树这步静默跳过 | 用本章的两阶段命令手动编 dtb |
| 预处理报 dt-bindings 头文件 No such file or directory | `-I` 少了内核 `include/`，尖括号包含没了搜索路径 | 补第四条 `-I third_party/linux_mainline/include` |
| dtc 警告 unit_address_vs_reg | 节点带 reg 但名字没写 `@地址` | 简单设备挂根下可容忍；介意规范就改成带 `@` 的名字并同步驱动路径 |
| `--search led` 搜出一堆 disabled | disabled 一词含 led 子串，grep 不分词，前二十条被吃光 | 关键词换具体的 `imx_aes_led` |
| 改了 dts，重启后板上还是老样子 | dtb 没重编、没部署成 `imx6ull-aes.dtb`、或者压根没重启 | 沿链路逐环查：产物目录、TFTP 目录、重启 |
| 改了共享的 imx6ull-aes.dtsi，编译结果没变 | 编译命中的是内核树里补丁放的那份副本，改项目副本不生效 | 补丁源和两处副本三处同步；教程内的改动只动教程自己的 dts |

表格之外有两个坑值得展开说。头一个是共享 dtsi 的三处同步：`imx6ull-aes.dtsi` 在仓库里存在不止一份，补丁源 `patches/linux_mainline/linux_mainline-feat-imx6ull_patches-20260828.patch` 是源头，应用补丁后内核树里有一份，`driver/device_tree/alpha-board/linux/` 下还有一份副本。咱们编译时 `-I` 的搜索顺序让内核树那份优先命中，警告里的路径就是证据；今天这两份内容一致（笔者 diff 过），但只改副本不改补丁，下次编出来还是老样子，这种“改了不生效”最磨人的地方在于它不报任何错。本章的动手范围只在教程自己的 dts 里加节点，天然避开这个坑。

另一个是工具链前缀的拼写。本仓的交叉前缀是 `arm-none-linux-gnueabihf-`，中间那截 gnueabihf 是 e-a-b-i-h-f，hardware float 的 ABI 缩写；拼成 gnueabhif，字母对、顺序错，工具链照样找不到，报错还只会说 command not found。写脚本配环境时这两个拼写值得您多看一眼。

## 下一步

- 上一篇：[03. 从硬编码到设备树驱动](03_device_tree_driver.md)，驱动怎么按路径找到咱们这章加的节点、把 reg 一组组映射成虚拟地址
- 下一篇：[05. 毕业项目](05_complete_practice.md)，从接近空白的 dts 起步，加节点、写驱动、部署点灯整条链路独立走一遍，走通才算毕业
- 跨卷参考：外设怎么配、换板子怎么移植，查[设备树配置指南](../../../modules/DEVICE_TREE_GUIDE.md)；本章构建库的内部实现，见 [driver_buildlib.sh 脚本文档](../../../scripts/lib/driver_buildlib.sh.md)

::: details 深读：编译与加载链路的深处
两阶段编译里内核 Makefile 是怎么组织 dtbs 目标的，dtc 内部还有哪些检查与告警，U-Boot 的 bootm 在把 dtb 交给内核前做了哪些修整，内核又怎么把一张扁平的 dtb 展开成 `/proc/device-tree` 里能逐节点查看的树，这些机制内容本卷不展开，咱们留给后续的深读专题。
:::