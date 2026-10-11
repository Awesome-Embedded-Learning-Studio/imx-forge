---
title: 毕业项目：完整闭环
---

# 05. 毕业项目：完整闭环

> 本篇是实践卷的末章，也是验收章。前四章攒下的语法、驱动改造、板级修改，到这里要拧成一条由您独立走通的链路：自己裁起步树、自己写节点、自己备驱动，一路编到板子上亮灯才算毕业。它解决的是“学到哪一步算真会了”这个问题；上一篇[板级 DTS 修改](04_board_dts_modification.md)把每一步操作掰开教完，这一篇撤掉手把手，只留目标、验收线和卡点提示。

::: tip 前置知识 · 环境
- [02 语法速览：读懂本仓的 dts](02_device_tree_syntax.md)：节点、属性、cells、同名属性的覆盖合流，本章写节点时按“已掌握”对待
- [03 从硬编码到设备树驱动](03_device_tree_driver.md)：六步改造在 08 章完整教过，本章只做验收，不从头再教一遍
- [04 板级 DTS 修改实操](04_board_dts_modification.md)：build、deploy、show 三个脚本的用法在那里拆细了，流程卡住回那边查
- 起步材料在仓库两处：`driver/device_tree/alpha-board/11_tutorial_device_tree_try/`（树）与 `driver/06_tutorial_device_tree_try/alpha-board/`（驱动）
- 路径上下文：本篇命令都在仓库根目录 `~/imx-forge` 下执行，对着 `third_party/linux_mainline` 这棵内核源码操作，交叉工具链前缀 `arm-none-linux-gnueabihf-`；本仓内核轨只有 mainline 7.1.0 一条
:::

## 毕业标准：一颗树、一个驱动、一盏灯

怎么判断设备树学到家了？能把改造代码讲得头头是道不算数，知识过不过关，得让一块通着电的板子说了算。所以本卷把末章定成毕业项目：您独立完成一次完整闭环，验收标准就三样东西——一颗自己写的设备树、一个从这颗树上取地址的驱动、板子上那颗真亮起来的 LED。三样齐了，本卷毕业；缺哪样，卡住的那一步就是您该回头补的那一章。

拿 LED 当考题不是偷懒：五个寄存器撑死，您不会淹在硬件调试里，而节点、OF API、脚本、部署、板上验证一个环节不少。换 I2C、SPI 外设当考题，链条一模一样，毕了业自然举一反三。

本章的角色是教练。脚本怎么传参、两阶段编译为什么那样编、部署为什么是 TFTP 加 NFS，前面两章细讲过，这里当您已经会了，每步只给目标、验收线和卡住时回看哪一章。照附录对答案不算作弊，但“做没做对”的判断，得您自己下。

## 起步材料：一张薄壳树，三件套驱动

### 树：22 行薄壳，和一次同名合流

仓库给这章配的树在 `driver/device_tree/alpha-board/11_tutorial_device_tree_try/`，整个目录只有一份 `imx6ull-aes-11_tutorial_device_tree_try.dts`，22 行。把中间的 `imx_aes_led` 块拿掉，剩下的就是咱们的起步形态：

```dts
// 起步形态：仓库 dts 去掉 LED 节点后的薄壳（笔者裁剪，两行 include 原样）
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
	model = "Awesome Embedded Studio IMX6ULL Example Driver";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};
```

薄壳虽薄，两行 include 一行都少不得：`imx6ull.dtsi` 描述芯片，`imx6ull-aes.dtsi` 描述咱们这块板，展平之后背后还站着整份板级正文。更要紧的是旧稿没写的一件事，咱们用一次真跑挖出来：板级 dtsi 里已经躺着一颗同名节点 `imx_aes_led`，血统是平台驱动教程那一代，`compatible` 写的是 `imxaes,led`：

```dts
// third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi（节选）
/* 教程外设（自写 platform 驱动，从 16/15/17 章提到默认启用）*/
imx_aes_led {
	compatible = "imxaes,led";
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_aes_led>;
	status = "okay";
	led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;
};
```

也就是说，您在薄壳里再写一个 `imx_aes_led`，真正发生的事情是同名合流。规则语法一章讲过：同一属性，后写的赢；您没写的属性，从前一颗节点原样继承。笔者把仓库这份 dts 真编了一遍（命令和输出见后面编译一步），反编译出来的合流节点长这样：

```dts
// dtb 反编译产物（节选）
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

咱们挨个数过去：`compatible`、`reg` 和两个 cells 是咱们写的，赢了；`pinctrl-0`、`led-gpio` 是从 dtsi 那颗继承来的。对本章驱动这无伤，它按路径找节点、地址只从 `reg` 里拿，compatible 和 status 只是照着打印，继承来的 pinctrl-0、led-gpio 躺在树上没人动。您想要一颗绝对干净的节点，起个新名字（比如 `imx_grad_led`）就行，记得驱动里的路径常量跟着改，备驱动一步还会对这条。

### 驱动：三件套加一份 Makefile

驱动侧的起步材料是仓库现成的一组文件，咱们把目录真列出来看：

```bash
# 主机 ~/imx-forge
ls driver/06_tutorial_device_tree_try/alpha-board/
```

```text
Makefile
Module.symvers
README.md
device_tree_try_03_driver.ko
device_tree_try_03_driver.mod
device_tree_try_03_driver.mod.c
device_tree_try_03_driver.mod.o
device_tree_try_03_driver.o
device_tree_try_03_driver_main.c
device_tree_try_03_driver_main.o
led_hw.c
led_hw.h
led_hw.o
modules.order
```

十四个条目里近三分之二是上次编译留下的产物，要看的就四份：`led_hw.c`、`led_hw.h`、`device_tree_try_03_driver_main.c`、`Makefile`。三份源码的体量，笔者量过：

```bash
# 主机 ~/imx-forge
wc -c /home/charliechen/imx-forge/driver/06_tutorial_device_tree_try/alpha-board/led_hw.c \
      /home/charliechen/imx-forge/driver/06_tutorial_device_tree_try/alpha-board/led_hw.h \
      /home/charliechen/imx-forge/driver/06_tutorial_device_tree_try/alpha-board/device_tree_try_03_driver_main.c
```

```text
 5200 /home/charliechen/imx-forge/driver/06_tutorial_device_tree_try/alpha-board/led_hw.c
  590 /home/charliechen/imx-forge/driver/06_tutorial_device_tree_try/alpha-board/led_hw.h
 6004 /home/charliechen/imx-forge/driver/06_tutorial_device_tree_try/alpha-board/device_tree_try_03_driver_main.c
11794 total
```

一万一千多字节，一晚上读得完。分工驱动改造一章交代过：`led_hw.c` 管硬件、从设备树取地址，`device_tree_try_03_driver_main.c` 管字符设备框架、整个项目里一行不用动。您可以照这组范例改，也可以从字符设备教程的基线自己重写 `led_hw.c`；附录五份清单与仓库逐字同步，就是给您逐字比对的标准答案。

树上认完了，再认驱动这边的名字。`device_tree_try_03_driver.ko` 里那个 `03` 是早期教程编号在 Makefile 里的残留，与目录编号 `06` 对不上，历史遗留。它的 vermagic 笔者真查过：

```bash
# 主机 ~/imx-forge
modinfo driver/06_tutorial_device_tree_try/alpha-board/device_tree_try_03_driver.ko | grep vermagic
```

```text
vermagic:       7.1.0-dirty mod_unload modversions ARMv6 p2v8
```

`7.1.0` 就是本仓唯一的内核轨 mainline，`-dirty` 来自内核树上打着的本仓补丁；板子内核与模块 vermagic 对不上，`insmod` 当场拒绝，这条您编完模块就该查。核对从 compatible 开始，一条命令问出真实值：

```bash
# 主机 ~/imx-forge
grep -n compatible driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts
```

```text
7:	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
14:		compatible = "atkalpha-led"; 
```

预期就这两行：第 7 行板级身份，第 14 行 LED 节点的匹配串。`atkalpha-led` 的血统驱动改造一章交代过，本章驱动按路径找节点、它不参与匹配，但您抄错了 dmesg 里立刻现形，卡点一节细说。

## 六步闭环：每步给目标，也给验收线

闭环拆成六步：复制起步树、写节点、备驱动、编译、部署、板上验证。顺序单向，前一步没过验收线就别进下一步，哪一环是糊的，最后灯不亮都得全量排查。每步咱们只对目标和验收线，完整教程在前面两章，卡住就回去翻。

### 复制起步树

给自己起个新目录（名字您定，比如 `30_grad_led`），把起步 dts 放进去；`11_tutorial_device_tree_try` 里的原件别动，那是驱动改造一章的教具，也是您的对照答案。验收线：您的目录里只有一份 `.dts`，两行 include 齐全，`/dts-v1/;` 在头一行。这步没什么命令可教，难的从来是舍得给实验留一份干净的对照。

### 写 LED 节点

在您的 dts 根节点下写 `imx_aes_led`（或您自起的名字）：`compatible`、`status`、两个 cells，五组“地址、长度”进 `reg`。地址的出处是芯片手册，驱动改造一章 `led_reg.h` 里的五个常量就是标准答案。验收线两条：`grep -n compatible` 的匹配串与您笔下的一致；属性逐行过一遍分号，语法一章的玩具实验演示过，漏分号时 dtc 把报错指到下一行。

### 备吃树的驱动

`led_hw.c` 按六步改造的路线来：路径常量、找节点、读三个属性、五个 `of_iomap`、`of_node_put` 收尾；`device_tree_try_03_driver_main.c` 不动；`Makefile` 里 `obj-m` 那两行照附录抄。验收线：路径常量与您的节点路径一字不差，自起了节点名的话这里必须同步；五个 `of_iomap` 的索引 0 到 4 与 `reg` 五组一一对应；读 reg 的数组长度 10 与五组“地址、长度”对得上。改动只许落在“地址从哪来”上，要是动进了字符设备框架，说明您改的不是地方。

### 编译

ko 用 `build_driver.sh` 编，传驱动目录名 `06_tutorial_device_tree_try` 和板卡名 `alpha-board`，用法板级修改一章拆过，您直接抄来用。dtb 要手动编，缘由卡点一节交代；命令驱动改造一章给过，但笔者这次重编踩了个现成的坑，值得把修正后的版本原样放这儿：

```bash
# 主机 ~/imx-forge（编的是 11 目录的仓库原件，您把自己的副本路径换进去；输出落进产物目录，部署那步才取得到）
gcc -E -nostdinc -undef -x assembler-with-cpp \
    -I third_party/linux_mainline/arch/arm/boot/dts \
    -I third_party/linux_mainline/arch/arm/boot/dts/nxp/imx \
    -I third_party/linux_mainline/include \
    -I driver/device_tree/alpha-board/linux \
    driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts \
  | dtc -I dts -O dtb \
    -o out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb -
```

笔者头一遍照那条三 `-I` 的版本抄，在这台机器上当场挂掉，报错关键行照录：

```text
third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ul.dtsi:5:10: fatal error: dt-bindings/clock/imx6ul-clock.h: No such file or directory
compilation terminated.
```

缺的正是语法一章讲过的那条内核 `include/` 的 `-I`：dt-bindings 头文件全在里面；那条三 `-I` 的命令漏了它，您编译时以上面四条的版本为准。补上就通，笔者的实况是两条 Warning、一个 36185 字节的 dtb：

```text
third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi:176.14-182.4: Warning (unit_address_vs_reg): /imx_aes_led: node has a reg or ranges property, but no unit name
  also defined at driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts:11.14-21.4
third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ul.dtsi:995.23-1002.6: Warning (simple_bus_reg): /soc/bus@2100000/sim@021b4000: simple-bus unit address format error, expected "21b4000"
  also defined at third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi:432.7-446.3
```

两条都是老面孔，不挡编译。前一条就是起步材料里那次同名合流，dtc 顺带嫌 `imx_aes_led` 带着 `reg` 却没有 `@单元名`，教学树咱们不必理会；后一条来自本仓补丁补回的 sim 节点，旧式单元地址格式，与您无关。Warning 里报的 `third_party/` 前缀也交代一下：`-I` 顺序先命中了补丁放进内核树的那份 `imx6ull-aes.dtsi`，它与咱们目录里的副本逐字相同（笔者 diff 过），合流结果不受影响。dtb 的验收线：文件生成，大小三万多字节量级；再拿 `fdtget` 问一句 reg，五组值与 dts 一一对应，笔者跑的真实输出：

```bash
# 主机 ~/imx-forge
fdtget -t x out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb /imx_aes_led reg
```

```text
20c406c 4 20e0068 4 20e02f4 4 209c000 4 209c004 4
```

十个数全对上，这一步您就算过了。ko 那边验收两条：`out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/` 里 `device_tree_try_03_driver.ko` 在，笔者这台机器刚跑完 `build_driver.sh` 的目录里是一份 13K 的 ko 加 build_info.txt——脚本构建那一刻不产 dtb，您手动编的那份要落进同一目录，部署命令才取得到；`modinfo` 查 vermagic，7.1.0 开头。想肉眼看整棵树，`show_device_tree.sh` 能把 dtb 拆开着色，用法板级修改一章教过。

### 部署

dtb 走 TFTP，ko 走 NFS，两条 `deploy_driver.sh` 命令板级修改一章有现成的；两条命令扫的都是产物目录，dtb 取的正是您上一步手动编进去的那份。验收线抓两处：TFTP 根目录里落地的文件名是 `imx6ull-aes.dtb`，不是产物原名，U-Boot 按 `fdt_file` 环境变量里这个名字加载；部署完的文件大小与您刚编的产物一致。还有一条没有商量余地：dtb 部署后必须重启板子才生效，各章的 dtb 顶同一个名字、彼此互斥，后部署的覆盖前面的。ko 不用重启，insmod 即时生效。

### 板上验证

顺序本身就是排查法：先查树，再加载，再点灯。树里没有节点，问题在部署那侧；树里有、驱动找不到，问题在路径字符串。查树放在加载前面，为的就是把两类问题切开；完整清单在下一节，您一项项打勾。

## 关键卡点：真正容易翻车的地方

咱们把容易翻车的坑收在这儿，都与前面章节对过口径，只留现象、根因和动作。

compatible 抄错，这一版驱动不会罢工，匹配靠路径不靠它；现形位置在 dmesg，`compatible = ` 后面打出来的值跟您想写的不一样，就是抄错了。别因为它现在不咬人就放过：到了平台设备驱动教程，compatible 就是配对钥匙，错一个字母设备就没人认领。

reg 里的地址抄错一位，是最隐蔽的一档。错在高位，`of_iomap` 给您映射到一块没人管的地址，写轻了灯没反应，写重了踩到别的外设头上；错在低位，可能撞进同一外设的另一个寄存器，灯的行为莫名其妙。排查靠三处比对：您的 dts、`led_reg.h` 的五个常量、板上 `hexdump -C /proc/device-tree/imx_aes_led/reg` 的字节；主机侧更快的办法是那条 `fdtget`，不通电就能问。

改了树、板上还是老样子，您先问自己一句：重启了没有。dtb 是 U-Boot 开机拉给内核的，不重启，内核手里永远是旧树；ko 才是 insmod 即时生效的那一类。确认重启过还老样子，再查 TFTP 目录里 `imx6ull-aes.dtb` 的时间戳和大小。

模块名的 `03`、驱动目录的 `06`、树目录的 `11`，三处编号对不上，都是早期教程编号的历史遗留，实际影响就一条：`build_driver.sh` 按驱动目录名找树，找不到，dtb 得手动编。insmod、rmmod 时模块名以 `modinfo` 的 name 字段为准，就是 `device_tree_try_03_driver`，您别按目录名猜。

速查表收个尾：

| 现象 | 根因 | 解法 |
|---|---|---|
| dmesg 里 compatible 打印值不对 | dts 里 compatible 抄错 | grep -n compatible 对两行预期 |
| dmesg 一切正常，灯不亮或行为诡异 | reg 地址抄错一位 | dts、led_reg.h、板上 hexdump 三处比对；主机侧 fdtget 直问 dtb |
| 板上查不到节点，还是旧树 | dtb 部署后没重启，或 TFTP 目录里还是旧文件 | 重启板子；核对 imx6ull-aes.dtb 的时间戳与大小 |
| 产物目录里只有 ko 没有 dtb | 驱动目录 06 与树目录 11 编号错位，脚本不产树 | 手动两阶段编译，命令见本章编译一步 |
| insmod 报 Invalid module format | 模块 vermagic 与板端内核不一致 | 两边都用 mainline 7.1.0，重编模块 |

## 验收清单：板子上逐项打勾

::: warning 未实测标注
本节命令与预期输出都要您在实际的 Alpha 开发板上执行才能拿到，本篇成稿环境只有主机侧仓库，通不了电；各项预期值以仓库 dts 与本章主机侧真编出的 dtb 为准，dmesg 各行文案取自 led_hw.c 源码里的原样字符串，虚拟地址这类每次启动都不同的量不列具体数。
:::

清单从树到灯一条线，您按序打勾，哪项不过就停在那项排查：

**树在。** 您在板上把节点目录列出来，属性一个个都是文件：

```bash
# 板端 /
ls /proc/device-tree/imx_aes_led/
cat /proc/device-tree/imx_aes_led/compatible
# 预期：atkalpha-led
cat /proc/device-tree/imx_aes_led/status
# 预期：okay
```

这一项过不了，您先别碰驱动，回部署那一步查。`reg` 用 `hexdump -C` 看：四十个字节、五组“地址、长度”，头四个字节 `02 0c 40 6c` 正是 `0X020C406C` 的大端字节序，咱们拿它跟 dts 第一组对上，后面照此类推。

**匹配成功。** 您加载模块后看 dmesg 的关键行：

```bash
# 板端 /lib/modules
insmod device_tree_try_03_driver.ko
dmesg | tail -30
```

```text
dtsled node has been found!
compatible = atkalpha-led
status = okay
reg data:
0X20C406C 0X4 0X20E0068 0X4 0X20E02F4 0X4 0X209C000 0X4 0X209C004 0X4
LED Init OK!
```

`reg data` 那行是全场高光：五个地址与您 dts 里写的逐个一致，数据才算真从树流进了驱动。中间夹着的映射地址、CCGR1 位分解那些行，值每次启动都不同，对不上具体数不算问题。

**设备节点在。** 您拿 `ls -l /dev/AES_LED` 看主次设备号，与 dmesg 打印的 major、minor 一致才算过。

**灯听指挥。** `echo 1 > /dev/AES_LED` 点亮，`echo 0 > /dev/AES_LED` 熄灭，这块板的 LED 低电平点亮，写 1 是开；`cat /dev/AES_LED` 读回状态。您眼睛盯着板子上的灯，别只看终端回显。

**卸载干净。** `rmmod device_tree_try_03_driver` 后 dmesg 出现 `Deinit LED Hardware`，`/dev/AES_LED` 消失。加试一条：紧接着再 insmod 一轮还能原样跑通，说明您的闭环可重复，不是碰巧。

毕业加试，给有余力的您备了一道：换个节点名（比如 `imx_grad_led`）重走六步，dts、路径常量、编译、部署全跟着改。不翻对照答案也能走通，这一卷才算真毕业。

## 附录：完整代码清单

五份清单与仓库文件逐字同步，笔者成稿前用 diff 逐份核对过，唯一差异是 dts 原件末行没有换行符，代码块表达不出来。仓库文件永远为准：树在 `driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts`，其余四份在 `driver/06_tutorial_device_tree_try/alpha-board/` 下。`device_tree_try_03_driver_main.c` 开头的注释曾指向改版前已不存在的 `device_tree_compile/` 教程路径，本次改版顺手把它更新成了本章的真实指向。

### A. 设备树 imx6ull-aes-11_tutorial_device_tree_try.dts

```dts
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

### B. 硬件接口 led_hw.h

```c
/**
 * @file led_hw.h
 * @brief LED hardware control interface
 */

#pragma once

#include <linux/types.h>

/**
 * @brief Initialize LED hardware (clock, GPIO mux/pad, direction)
 * @return 0 on success, negative errno on failure
 */
int led_hw_init(void);

/**
 * @brief Deinit the usage
 * 
 */
void led_hw_deinit(void);

/**
 * @brief Set LED on/off status
 * @param status true = LED on, false = LED off
 */
void led_set_status(bool status);

/**
 * @brief Get LED status
 * 
 * @return true: led is currently on
 * @return false: led is currently false
 */
bool led_get_status(void);

```

### C. 硬件实现 led_hw.c

```c
/**
 * @file led_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED hardware control using Device Tree (mainline Linux API style)
 * @version 0.2
 * @date 2026-04-27
 */

#include "led_hw.h"
#include <asm/io.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/printk.h>

/* LED hardware register mapping structure */
struct led_handle {
    void __iomem* ccm_ccgr1;
    void __iomem* sw_mux_gpio;
    void __iomem* sw_pad_gpio;
    void __iomem* gpio_dr;
    void __iomem* gpio_gdir;
    struct device_node* device_tree_node;
};

static struct led_handle led;

static const char* kIMX_AES_LED = "/imx_aes_led";

static void pr_bin_u32(u32 val) {
    char buf[33];
    for (int i = 0; i < 32; i++) {
        buf[i] = (val & (1u << (31 - i))) ? '1' : '0';
    }
    buf[32] = '\0';
    pr_cont("%s", buf);
}

int led_hw_init(void) {
    u32 regdata[10];
    int ret;
    const char* str;
    struct property* proper;
    u32 val;

    /* Get the struct of in the device tree */
    led.device_tree_node = of_find_node_by_path(kIMX_AES_LED);
    if (led.device_tree_node == NULL) {
        pr_err("dtsled node can not found!\n");
        return -EINVAL;
    }
    pr_info("dtsled node has been found!\n");

    /* 2. 获取 compatible 属性 */
    proper = of_find_property(led.device_tree_node, "compatible", NULL);
    if (proper == NULL) {
        pr_err("compatible property find failed\n");
    } else {
        pr_info("compatible = %s\n", (char*)proper->value);
    }

    /* 3. 获取 status 属性 */
    ret = of_property_read_string(led.device_tree_node, "status", &str);
    if (ret < 0) {
        pr_err("status read failed!\n");
    } else {
        pr_info("status = %s\n", str);
    }

    /* 4. 获取 reg 属性内容 */
    ret = of_property_read_u32_array(led.device_tree_node, "reg", regdata, 10);
    if (ret < 0) {
        pr_err("reg property read failed!\n");
        of_node_put(led.device_tree_node);
        return -EINVAL;
    }

    pr_info("reg data:\n");
    for (int i = 0; i < 10; i++) {
        pr_cont("%#X ", regdata[i]);
    }
    pr_cont("\n");

    /* 5. 使用 of_iomap 进行寄存器地址映射 */
    led.ccm_ccgr1 = of_iomap(led.device_tree_node, 0);
    led.sw_mux_gpio = of_iomap(led.device_tree_node, 1);
    led.sw_pad_gpio = of_iomap(led.device_tree_node, 2);
    led.gpio_dr = of_iomap(led.device_tree_node, 3);
    led.gpio_gdir = of_iomap(led.device_tree_node, 4);

    if (!led.ccm_ccgr1 || !led.sw_mux_gpio || !led.sw_pad_gpio || !led.gpio_dr || !led.gpio_gdir) {
        pr_err("ioremap failed!\n");
        of_node_put(led.device_tree_node);
        return -ENOMEM;
    }

    pr_info("IMX6U_CCM_CCGR1    = 0x%p\n", led.ccm_ccgr1);
    pr_info("SW_MUX_GPIO1_IO03  = 0x%p\n", led.sw_mux_gpio);
    pr_info("SW_PAD_GPIO1_IO03  = 0x%p\n", led.sw_pad_gpio);
    pr_info("GPIO1_DR           = 0x%p\n", led.gpio_dr);
    pr_info("GPIO1_GDIR         = 0x%p\n", led.gpio_gdir);

    /* 6. 使能GPIO1时钟 */
    val = readl(led.ccm_ccgr1);
    pr_info("CCGR1 raw value: 0x%08x\n Bits: ", val);
    pr_bin_u32(val);
    pr_cont("\n");

    val &= ~(3 << 26); /* 清除以前的设置 */
    val |= (3 << 26);  /* 设置新值 */
    writel(val, led.ccm_ccgr1);

    pr_info("CCGR1 new value: 0x%08x\n Bits: ", val);
    pr_bin_u32(val);
    pr_cont("\n");

    /* 7. 设置GPIO1_IO03复用功能为GPIO */
    writel(5, led.sw_mux_gpio);

    /* 8. 设置GPIO1_IO03电气属性 */
    writel(0x10B0, led.sw_pad_gpio);

    /* 9. 设置GPIO1_IO03为输出功能 */
    val = readl(led.gpio_gdir);
    val &= ~(3 << 3); /* 清除以前的设置 */
    val |= (1 << 3);  /* 设置为输出 */
    writel(val, led.gpio_gdir);
    pr_info("GPIO1_GDIR = 0x%08x\n", val);

    /* 10. 默认关闭LED (高电平) */
    val = readl(led.gpio_dr);
    val |= (1 << 3);
    writel(val, led.gpio_dr);
    pr_info("GPIO1_DR init = 0x%08x (LED OFF)\n", val);

    pr_info("LED Init OK!\n");
    return 0;
}

void led_hw_deinit(void) {
    pr_info("Deinit LED Hardware\n");

    if (led.ccm_ccgr1) {
        iounmap(led.ccm_ccgr1);
        led.ccm_ccgr1 = NULL;
    }
    if (led.sw_mux_gpio) {
        iounmap(led.sw_mux_gpio);
        led.sw_mux_gpio = NULL;
    }
    if (led.sw_pad_gpio) {
        iounmap(led.sw_pad_gpio);
        led.sw_pad_gpio = NULL;
    }
    if (led.gpio_dr) {
        iounmap(led.gpio_dr);
        led.gpio_dr = NULL;
    }
    if (led.gpio_gdir) {
        iounmap(led.gpio_gdir);
        led.gpio_gdir = NULL;
    }

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}

void led_set_status(bool status) {
    u32 val = readl(led.gpio_dr);
    pr_info("led_set_status: status=%d, GPIO1_DR before=0x%08x\n", status, val);

    if (status) {
        val &= ~(1 << 3); /* 低电平点亮 */
    } else {
        val |= (1 << 3); /* 高电平熄灭 */
    }
    writel(val, led.gpio_dr);

    pr_info("led_set_status: GPIO1_DR after=0x%08x\n", val);
}

bool led_get_status(void) {
    u32 val = readl(led.gpio_dr);
    return (val & (1 << 3)) == 0;
}
```

### D. 字符设备框架 device_tree_try_03_driver_main.c

```c
// 本章配套的设备树文件在
// driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts
// 改造思路的完整讲解见仓库
// https://github.com/Awesome-Embedded-Learning-Studio/imx-forge
// 的 document/tutorial/driver/01_device_tree_base/03_device_tree_driver.md

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

/**
 * @file chardev_led_v2_02_driver_main.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED Driver using new API
 * @version 0.1
 * @date 2026-04-18
 *
 * @copyright Copyright (c) 2026
 *
 */

#include "led_hw.h"
#include "linux/printk.h"
#include <linux/cdev.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/uaccess.h>

static const char* CHARDEV_NAME = "AES_LED";
static const int LED_CNT = 1;

struct IMXAesLED {
    dev_t devid;
    struct cdev char_device_handle;
    struct class* char_device_class;
    struct device* char_device_device;
} led_handle;

static int aes_chardev_open(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called open!\n", CHARDEV_NAME);
    // Assigned the private data
    filp->private_data = &led_handle;
    return 0;
}

static ssize_t aes_chardev_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    // Upper Level App request to read the application

    if (*offt > 0) {
        // `cat` program will request for next session,
        // to avoid always read, break it
        // down.
        return 0;
    }

    if (cnt > 1) {
        cnt = 1;
    }

    *offt += cnt;

    // let make these simple
    // '1' for on, '0' for close
    const bool led_status = led_get_status();
    const char user_indication = led_status ? '1' : '0';

    const auto kResult = copy_to_user(buf, &user_indication, cnt);
    if (kResult != 0) {
        pr_warn("Failed to pass the led status to user! code: %ld\n", kResult);
        return -EFAULT;
    }

    return cnt;
}

static ssize_t aes_chardev_write(struct file* filp, const char __user* buf, size_t cnt,
                                 loff_t* offt) {
    pr_info("aes_chardev_write: cnt=%zu\n", cnt);

    if (cnt > 2) {
        pr_warn("Get the unexpected data, thats to more!\n");
        return -EINVAL;
    }

    char user_led_new_status = 0;
    const auto kResult = copy_from_user(&user_led_new_status, buf, 1);
    if (kResult != 0) {
        pr_warn("Failed to set the led status from user! code: %ld\n", kResult);
        return -EFAULT;
    }

    const bool led_new_status = (user_led_new_status == '1') ? true : false;
    pr_info("LED status: %d (user_led_new_status='%c')\n", led_new_status, user_led_new_status);
    led_set_status(led_new_status);
    return 1;
}

/* 关闭/释放设备 */
static int aes_chardev_release(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called close!\n", CHARDEV_NAME);
    filp->private_data = NULL; // Release the private datas
    return 0;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = aes_chardev_open,
    .read = aes_chardev_read,
    .write = aes_chardev_write,
    .release = aes_chardev_release,
};

static int init_led_handle(struct IMXAesLED* led_handle) {
    // filled the led handle, by using new API
    pr_info("Init the User Interfaces and driver handles\n");

    // Calling for a major dev number
    alloc_chrdev_region(&led_handle->devid, 0, LED_CNT, CHARDEV_NAME);

    // I do not like the var leak, so, just do this as I like :)
    {
        const auto led_major_number = MAJOR(led_handle->devid);
        const auto led_minor_number = MINOR(led_handle->devid);

        pr_info("LED handle get the device number: major: %u, minor: %u\n", led_major_number,
                led_minor_number);
    }

    led_handle->char_device_handle.owner = THIS_MODULE;
    cdev_init(&led_handle->char_device_handle, &fops);
    const auto kResult = cdev_add(&led_handle->char_device_handle, led_handle->devid, LED_CNT);
    if (kResult < 0) {
        pr_warn("Error when trying to make a cdev in kernel: %d\n", kResult);
        return kResult;
    }

    pr_info("cdev series api called success!\n");

    // Mark: New kernel has abolished the owner module
    led_handle->char_device_class = class_create(CHARDEV_NAME);
    if (IS_ERR(led_handle->char_device_class)) {
        const auto error_code = PTR_ERR(led_handle->char_device_class);
        pr_warn("Failed to create a class, code: %ld", error_code);
        return error_code;
    }

    pr_info("class create success!\n");

    led_handle->char_device_device =
        device_create(led_handle->char_device_class, NULL, led_handle->devid, NULL, CHARDEV_NAME);
    if (IS_ERR(led_handle->char_device_device)) {
        const auto error_code = PTR_ERR(led_handle->char_device_device);
        pr_warn("Failed to create a class, code: %ld", error_code);
        return error_code;
    }

    pr_info("device create success!\n");
    return 0;
}

static void release_led_handle(struct IMXAesLED* led_handle) {
    device_destroy(led_handle->char_device_class, led_handle->devid);
    class_destroy(led_handle->char_device_class);
    cdev_del(&led_handle->char_device_handle);
    unregister_chrdev_region(led_handle->devid, LED_CNT);
}

static int __init device_tree_try_03_init(void) {
    pr_info("=== Device Tree try ===\n");
    led_hw_init();
    // init the handle
    init_led_handle(&led_handle);
    pr_info("========================\n");
    return 0;
}

static void __exit device_tree_try_03_exit(void) {
    pr_info("=== device_tree_try_03驱动卸载成功 ===\n");
    release_led_handle(&led_handle);
    led_hw_deinit();
    pr_info("========================\n");
}

module_init(device_tree_try_03_init);
module_exit(device_tree_try_03_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Device Tree try");
MODULE_VERSION("1.0");
```

### E. 构建文件 Makefile

```makefile
# Device Tree try Makefile
#
# 由 template_creator.sh 自动生成

# Kernel module definition
obj-m := device_tree_try_03_driver.o
device_tree_try_03_driver-y := device_tree_try_03_driver_main.o led_hw.o
# ── 项目配置 ────────────────────────────────────────
PROJECT_ROOT := $(shell realpath $(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := $(PROJECT_ROOT)/third_party/linux-${KERNEL_TYPE}
KOBJ := $(PROJECT_ROOT)/out/${KERNEL_TYPE}

# 输出目录
OUTPUT_DIR := $(PROJECT_ROOT)/out/driver_artifacts/device_tree_try_03/alpha-board

.PHONY: all modules clean install help

all: modules

modules:
	@echo "🔨 编译device_tree_try_03驱动..."
	@mkdir -p $(OUTPUT_DIR)
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@cp *.ko $(OUTPUT_DIR)/ 2>/dev/null || true
	@echo "✓ 驱动编译完成: $(OUTPUT_DIR)/device_tree_try_03_driver.ko"

clean:
	@echo "🧹 清理构建产物..."
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)

install: modules
	@echo "📦 驱动位置: $(OUTPUT_DIR)"
	@ls -lh $(OUTPUT_DIR)/*.ko 2>/dev/null || echo "无.ko文件"
	@echo ""
	@echo "使用方法："
	@echo "  1. 构建驱动: scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board"
	@echo "  2. 部署驱动: scripts/driver_helper/deploy_driver.sh device_tree_try_03 alpha-board"
	@echo "  3. 测试驱动: insmod device_tree_try_03_driver.ko"
	@echo "  4. 查看日志: dmesg | tail"

help:
	@echo "Device Tree try"
	@echo ""
	@echo "用法："
	@echo "  make           - 编译驱动"
	@echo "  make clean     - 清理构建产物"
	@echo "  make install   - 显示使用说明"
	@echo ""
	@echo "产物位置: $(OUTPUT_DIR)"
```

## 收束：这一卷给了您什么

五章走完，咱们收个尾。学习地图一章认文件、看产物链；语法速览一章把您练到能独立读懂板级 dtsi；驱动改造一章把硬编码驱动改成吃树的驱动；板级修改一章走通从加节点到验证的全流程；本篇把这些拧成一次独立闭环。贯穿五篇的就一件事：描述硬件，而不是在代码里编码硬件。好处毕业项目里已经摸过，LED 换个引脚，您改的是 dts 里几个数字，`.ko` 原封不动。

往后再出发有两条路。工具书那条，[设备树配置指南](../../../modules/DEVICE_TREE_GUIDE.md)按外设整理了 LCD、网络、存储的配方和换板移植步骤，您给自己的板子添外设时去翻它。深读那条，设备树的历史考据、dtb 的二进制格式、内核展开链路，本卷先把清单列在下面，后续的深读专题会逐章补全。

## 继续学习

- 上一篇：[04. 板级 DTS 修改实操](04_board_dts_modification.md)
- 卷内回看：[01. 设备树与本仓的学习地图](01_device_tree_introduction.md) · [02. 语法速览：读懂本仓的 dts](02_device_tree_syntax.md) · [03. 从硬编码到设备树驱动](03_device_tree_driver.md)
- 跨卷深读：[设备树配置指南](../../../modules/DEVICE_TREE_GUIDE.md)，外设配方与移植步骤
- 本卷到这里收官。下一站是平台设备驱动教程：内核的匹配机制接管咱们手动找节点的活，compatible 在那里真正上岗。

::: details 深读：设备树原理的完整拆解
本卷反复借力的底层机制，dtb 的二进制格式、内核启动时怎么把一张扁平的 dtb 展开成 /proc/device-tree 里那棵树、节点又怎么变成设备，连同设备树的历史考据与 bindings 体系，咱们先把这些记作深读清单，后续的深读专题逐章补全。
:::