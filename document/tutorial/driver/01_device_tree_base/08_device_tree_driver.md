---
title: 从硬编码到设备树驱动
---

# 08. 从硬编码到设备树驱动

## 前言：五个写死的地址

在[字符设备驱动教程](../00_chardev_base/)里，我们点亮过一次 LED。当时的做法你已经知道了：翻芯片手册，把五个寄存器的物理地址一个个抄进 `led_reg.h`：

```c
/* led_reg.h - 硬编码方式的寄存器地址定义 */
static const u32 kCCM_CCGR1_BASE = 0X020C406C;
static const u32 kSW_MUX_GPIO1_IO03_BASE = 0X020E0068;
static const u32 kSW_PAD_GPIO1_IO03_BASE = 0X020E02F4;
static const u32 kGPIO1_DR_BASE = 0X0209C000;
static const u32 kGPIO1_GDIR_BASE = 0X0209C004;
```

`led_reg.h` 在教程里服役得很好，但代价也是实打实的。地址抄错一个数字，排查起来是灾难。LED 从 GPIO1_IO03 换到 IO04，你得重新翻手册、改宏、重新编译。真用同一颗芯片做了三款产品，你还得维护三份几乎一样、只差几个地址的驱动。这些麻烦追到底都是同一个根子：硬件信息和驱动代码长在了一起。

设备树给的解法一句话咱们也就说完了：把地址搬进一个文本文件，驱动在运行时自己来取。本章我们就拿仓库里真实的 `led_hw.c` 开刀，把硬编码版改造成设备树版，然后一路跑通编译、部署、在板子上点灯。

怎么改也有讲究。我们不会一次性把代码全换掉，而是分成六步走，每一步只动一小块，改完就能编译、能在板子上验证。哪一步出了问题，你立刻能定位到是哪一步引入的，这个习惯在改造任何老代码时都用得上。

## 改造对象，和不变的东西

这个驱动模块由 `driver/06_tutorial_device_tree_try/alpha-board/` 下的两个文件组成：`led_hw.c` 负责硬件操作，`device_tree_try_03_driver_main.c` 负责字符设备框架。六步改造全部落在 `led_hw.c` 上，main 文件一行不动。而整个改造过程中，我们守住的是 `led_hw.h` 里声明的四个接口：

```c
int  led_hw_init(void);
void led_hw_deinit(void);
void led_set_status(bool status);
bool led_get_status(void);
```

只动过一处，`led_hw_init` 在字符设备教程基线里返回 `void`，这一版改成了 `int`，好把 `-EINVAL`、`-ENOMEM` 这些失败报出去。除此之外接口原样，上层字符设备代码因此一行都不用动，硬件抽象层的价值也就在这儿：我们改的只是“地址从哪里来”这一件事，上层根本感知不到下层动过。

## 要吃进驱动的那棵设备树

来看我们要吃进去的东西。设备树文件在 `driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts`，内容如下：

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
	model = "Awesome Embedded Studio IMX6ULL Example Driver";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
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

和 `led_reg.h` 对照着看，五个地址全数搬了过来，只是从 C 常量变成了 `reg` 属性里的五组“地址、长度”对，`0X04` 是每个寄存器的长度，4 字节。DTS 语法的全貌在[卷内的语法详解一章](03_device_tree_syntax.md)有速览，我们只要认得出这个成对格式就够用。地址后面跟着注释写明寄存器名，这个习惯值得保持：设备树文件没有类型系统帮你，注释就是唯一的自解释手段。

从节点的位置说起。`imx_aes_led` 直接挂在根节点 `/` 下面，所以它的完整路径是 `/imx_aes_led`，这个路径待会儿就是驱动找它的钥匙。为什么放根下？我们拿 LED 直接操作 GPIO 寄存器，它是个简单设备，不属于任何总线。真正挂在 I2C、SPI 总线上的设备要放到对应总线节点下面，那是后面驱动章节的事。

另一件要交代的是 `compatible = "atkalpha-led"` 这个值的血统。它来自这套教程参考的正点原子 Alpha 开发板血统。我们仓库自己的板卡身份是 aes，全称 Awesome Embedded Studio。名字都对不上，能工作吗？能。本章的驱动按路径找节点，压根不做 compatible 匹配，这个值是什么都不影响运行。等我们走到平台设备驱动教程，匹配改靠 compatible 完成，那时用的是 `imxaes,led` 这样的自有命名。这里保留原值并把来历说清楚，比悄悄换掉更诚实。

## 六步改造 led_hw.c

### 第一步：两个头文件

```c
#include <linux/of.h>
#include <linux/of_address.h>
```

`of.h` 提供设备树的基础数据结构和查找、读属性的 API（`struct device_node`、`of_find_node_by_path`、`of_property_read_string` 这些），`of_address.h` 提供地址映射的 `of_iomap`。只要用到 OF API，两个头文件基本就够了，其余声明会经由它们间接包含。加完我们编译一次，确认没有拼写问题，然后往下走。

### 第二步：路径常量，斜杠不能少

```c
static const char* kIMX_AES_LED = "/imx_aes_led";
```

开头的 `/` 表示从根节点起算的绝对路径。写成 `"imx_aes_led"` 的话，`of_find_node_by_path` 会找不到节点，返回 NULL，而且报错信息只有一句 `dtsled node can not found!`，你盯着代码看它明明哪儿都对。我当初就在这个斜杠上耗了半天，所以这一步专门停下来讲它。

### 第三步：of_find_node_by_path 拿节点

```c
led.device_tree_node = of_find_node_by_path(kIMX_AES_LED);
if (led.device_tree_node == NULL) {
    pr_err("dtsled node can not found!\n");
    return -EINVAL;
}
pr_info("dtsled node has been found!\n");
```

这是设备树驱动真正的入口。找到节点返回 `struct device_node*`，找不到返回 NULL，我们据此提前退出，不再像硬编码版那样默认硬件一定在。这里返回 `-EINVAL` 其实不太精确，`-ENODEV`（设备不存在）更贴切。自己的练习驱动里两者无伤大雅，但你要知道区别在哪。

还有一件事现在就要记下：`of_find_node_by_path` 成功返回时，会把这个节点的引用计数加一。这意味着后面用完节点，必须用 `of_node_put` 把引用还回去，否则那部分内存永远不释放。第六步我们会兑现这个承诺。

### 第四步：三个属性各读一遍，但只有 reg 不能失败

改造版驱动连着读了三个属性，我们一个一个看，每一个用不同的 API，各有讲究：

```c
/* 读 compatible：拿原始属性结构 */
proper = of_find_property(led.device_tree_node, "compatible", NULL);
if (proper == NULL) {
    pr_err("compatible property find failed\n");
} else {
    pr_info("compatible = %s\n", (char*)proper->value);
}

/* 读 status：读字符串的专用接口 */
ret = of_property_read_string(led.device_tree_node, "status", &str);
if (ret < 0) {
    pr_err("status read failed!\n");
} else {
    pr_info("status = %s\n", str);
}

/* 读 reg：整数数组 */
ret = of_property_read_u32_array(led.device_tree_node, "reg", regdata, 10);
if (ret < 0) {
    pr_err("reg property read failed!\n");
    of_node_put(led.device_tree_node);
    return -EINVAL;
}
```

`of_find_property` 返回原始的 `struct property*`，`value` 字段直接指向属性值，演示“属性在内核里长什么样”最直观。`of_property_read_string` 是正经的字符串读取接口，注意第三个参数是 `const char**`，它给你的是指向设备树原始数据的指针，不是一份拷贝，所以不需要你释放。`of_property_read_u32_array` 按 u32 数组读，我们的 `reg` 有五组地址长度、共 10 个值，所以第四个参数是 10。

失败处理的松紧也不一样：compatible 和 status 读取失败只打印不返回，因为我们这个驱动不依赖它们做决定（路径才是钥匙）。reg 失败就必须返回了，下一步的 `of_iomap` 全靠它。注意返回前的 `of_node_put`：第三步借的引用，从这里提前退出时也要还，一条退出路径都不能欠。

### 第五步：of_iomap 按索引映射

```c
led.ccm_ccgr1   = of_iomap(led.device_tree_node, 0);
led.sw_mux_gpio = of_iomap(led.device_tree_node, 1);
led.sw_pad_gpio = of_iomap(led.device_tree_node, 2);
led.gpio_dr     = of_iomap(led.device_tree_node, 3);
led.gpio_gdir   = of_iomap(led.device_tree_node, 4);

if (!led.ccm_ccgr1 || !led.sw_mux_gpio || !led.sw_pad_gpio ||
    !led.gpio_dr || !led.gpio_gdir) {
    pr_err("ioremap failed!\n");
    of_node_put(led.device_tree_node);
    return -ENOMEM;
}
```

我们对照着 dts 看：第二个参数是索引，0 对应 `reg` 里第一组 `0X020C406C 0X04`，1 对应第二组，以此类推。驱动从此不需要知道地址是什么，只需要知道“我要第几组”。硬编码版里换引脚要重查手册、改宏、重编译。现在换板子改 dts 里的地址就行，`.ko` 原封不动。

`of_iomap` 内部走的就是 `ioremap`，失败同样返回 NULL，所以五个映射挨个判空，任何一个失败都回收引用、返回 `-ENOMEM`。它比裸 `ioremap` 多做的一件事是地址转换：`reg` 里写的是总线地址，某些架构上要经过转换才是 CPU 视角的物理地址，`of_iomap` 替你处理了这层。

映射拿到之后，使能时钟、配复用、配电气属性、设输出方向这一串寄存器操作，序列和语义都和硬编码版一致，只是地址变量的来源从宏换成了结构体成员。这部分与设备树无关，我们就不贴了，完整代码在仓库里。

### 第六步：deinit 收尾，把借的引用还回去

```c
void led_hw_deinit(void) {
    pr_info("Deinit LED Hardware\n");

    if (led.ccm_ccgr1) {
        iounmap(led.ccm_ccgr1);
        led.ccm_ccgr1 = NULL;
    }
    /* 其余四个 iounmap 同款，逐个判空、置 NULL */

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}
```

每个指针释放前判空、释放后置 NULL，这让 `deinit` 被调用两次也不会双重释放。好处平时看不见，出事的时候才显出来。最后的 `of_node_put` 兑现第三步的承诺：引用计数不归零，节点内存就永远挂着。你可能会想，模块卸载时内核不会自动清理吗？不会。设备树节点的生命周期就是靠引用计数管的，内核不知道你什么时候不用了，只有你自己知道。

到这里改造就完成了。我们回头看，`led_hw.h` 的接口只动过一处，`led_hw_init` 的返回值从字符设备教程里的 `void` 改成了 `int`，好把失败报出去。除此之外一行没动，上层字符设备代码也没动过，动的只有“地址从哪来”。

## 动手：编译、部署、上板点灯

代码看懂只是半件事，我们接下来把它真正跑起来，全程用仓库自带的脚本。动手前对一下环境：`third_party/linux_mainline` 已初始化检出（编 dtb 的 include 路径在它里面），你自己的电脑上装好 `dtc` 和 `arm-none-linux-gnueabihf-` 交叉工具链，部署用的 TFTP、NFS 服务能跑。缺哪样，编译或部署环节就会卡住，补齐了再往下走。

### 编驱动：一个脚本的事

```bash
# 项目根目录下
./scripts/driver_helper/build_driver.sh 06_tutorial_device_tree_try alpha-board
```

传的是 `driver/` 下的驱动目录名。产物落在 `out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/device_tree_try_03_driver.ko`，模块名里的 `03` 是早期教程编号在 Makefile 里的残留，不用管它。编完我们用 `modinfo` 看一眼 `vermagic`，它必须和板子运行的内核版本一致，不然 `insmod` 会直接拒绝：

```bash
modinfo out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/device_tree_try_03_driver.ko | grep vermagic
```

### 编设备树：这棵树要手动编

::: warning 这棵设备树目前要手动编
驱动目录编号是 `06_tutorial_device_tree_try`，设备树目录编号却是 `11_tutorial_device_tree_try`，历史遗留对不上。`build_driver.sh` 会去 `driver/device_tree/alpha-board/` 下找与驱动目录同名的子目录，落空再退回驱动目录里找 `.dts`，`06_tutorial_device_tree_try` 两处都没有，所以 `.dtb` 不会自动产出，我们用下面的命令自己编。
:::

dts 里有 `#include`，直接喂给 `dtc` 会报错，我们得让它过一遍 C 预处理器，再交给 `dtc`：

```bash
gcc -E -nostdinc -undef -x assembler-with-cpp \
    -I third_party/linux_mainline/arch/arm/boot/dts \
    -I third_party/linux_mainline/arch/arm/boot/dts/nxp/imx \
    -I driver/device_tree/alpha-board/linux \
    driver/device_tree/alpha-board/11_tutorial_device_tree_try/imx6ull-aes-11_tutorial_device_tree_try.dts \
  | dtc -I dts -O dtb \
    -o out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb -
```

命令里的三个 `-I` 我们挨个看过来。第一个是内核的 ARM 设备树公共目录。第二个是 NXP imx 子目录，`imx6ull.dtsi` 在这里。第三个到项目主板目录里找 `imx6ull-aes.dtsi`。这套“预处理一遍再交给 dtc”的两阶段流程就是内核自己编设备树的方式，细节在[编译机制一章](11_compile_mechanism.md)里拆。

编完我们可以反编译对拍，确认我们的节点真的在 dtb 里：

```bash
dtc -I dtb -O dts -o /tmp/check.dts \
    out/driver_artifacts/06_tutorial_device_tree_try/alpha-board/imx6ull-aes-11_tutorial_device_tree_try.dtb
grep -A 10 "imx_aes_led" /tmp/check.dts
```

反编译出来的格式和源文件会有出入，我们只对节点结构和属性值，这两样应当一致。

### 部署

```bash
# dtb 走 TFTP
./scripts/driver_helper/deploy_driver.sh 06_tutorial_device_tree_try alpha-board --target=tftp

# ko 走 NFS rootfs
./scripts/driver_helper/deploy_driver.sh 06_tutorial_device_tree_try alpha-board --target=nfs
```

dtb 部署时目标名是 `imx6ull-aes.dtb`，不是产物原名，U-Boot 按 `fdt_file` 环境变量里写死的名字加载。拿不准你的板子用哪个名字，你在 U-Boot 命令行 `printenv fdt_file` 查。dtb 换了要重启板子才生效。ko 不用，`insmod` 即可。

### 板上验证：把树查一遍，再加载

在板子上我们按固定的顺序走，顺序本身就是排查方法：确认内核手里的设备树里真有这个节点，然后加载驱动。树里没有的话，驱动第一步 `of_find_node_by_path` 就会失败，问题出在 dtb 部署那一侧，不在驱动。把树放在加载前面查，为的就是把这两类问题分开。

```bash
ls /proc/device-tree/imx_aes_led/
cat /proc/device-tree/imx_aes_led/compatible
# atkalpha-led
cat /proc/device-tree/imx_aes_led/status
# okay
hexdump -C /proc/device-tree/imx_aes_led/reg
```

`/proc/device-tree` 就是内核展开后的设备树本体，每个节点一个目录、每个属性一个文件，它是你在运行中的系统上检查设备树的第一入口。三个输出都对上 dts 里写的值，说明新 dtb 已经被内核吃进去了。接下来加载驱动：

```bash
insmod device_tree_try_03_driver.ko
dmesg | tail -30
```

你在 `dmesg` 里能看到 `led_hw_init` 那一串 `pr_info` 输出，下面是节选。`reg data` 和 `LED Init OK!` 之间还夹着映射地址、CCGR1 位分解、GDIR 和 DR 初值那十来行，这里省掉了，虚拟地址的值只有跑在板子上才拿得到，我们不编。

```text
dtsled node has been found!
compatible = atkalpha-led
status = okay
reg data:
0X20C406C 0X4 0X20E0068 0X4 0X20E02F4 0X4 0X209C000 0X4 0X209C004 0X4
LED Init OK!
```

`reg data` 那行是本章的高光时刻：打印出来的五个地址，和你 dts 里写的五个完全一致。数据真的从 dts 出发，经过 dtb、经过内核展开，流进了驱动变量。最后点灯：

```bash
ls -l /dev/AES_LED
# crw------- 1 root 245, 0 ... /dev/AES_LED   主设备号和 dmesg 里的一致

echo 1 > /dev/AES_LED    # 点亮（这块板的 LED 低电平点亮，写 1 是"开"）
echo 0 > /dev/AES_LED    # 熄灭

rmmod device_tree_try_03_driver
```

灯亮的那一下，从 `led_reg.h` 到设备树的迁移，我们就算走完了。

## API 拿不准时，上源码里对

教程里的 API 签名是死的，内核是活的。你以后一定会有“这个函数到底存不存在、参数是什么”的时刻，别搜教程，直接问内核源码：

```bash
cd third_party/linux_mainline
git grep -n "of_find_node_by_path" include/linux/of.h
```

你会看到它在 `include/linux/of.h` 里是个 `static inline` 包装，真正干活的是 `of_find_node_opts_by_path(path, NULL)`，内核给它留了个传选项的口子，日常用不到而已。同一个名字出现两处也别慌，一处是真实现，另一处是 `CONFIG_OF` 关闭时的空桩，看上下文就能分辨。

查的时候有两个习惯值得养成：查声明从 `include/` 查起，用 `git grep` 而不是裸 `grep -r`，内核几十万文件，后者会把你淹死。本项目的内核轨只有 mainline（7.1.0）一条，所以只对这一棵树。引用 API 时写函数名和文件就够，行号会随版本漂，别依赖它。

## 常见卡点

**路径少斜杠，节点就找不到。** 现象是 `of_find_node_by_path` 稳定返回 NULL，代码怎么看都没错。你检查 `kIMX_AES_LED` 开头的 `/`，再对照 `/proc/device-tree` 下的实际路径。路径失效还有一类：节点挪了位置（比如挂到别的节点下面），路径字符串要跟着变。

**reg 的数量对不上。** `of_property_read_u32_array` 的第四个参数写 10，是因为 reg 有五组“地址、长度”。dts 里加减了寄存器，这个数字要我们同步改。更通用的做法是用 `of_property_count_u32_elems` 问一问实际数量。

**of_iomap 索引越界返回 NULL。** reg 只写了三组，索引却用到 4，映射必然失败。判空兜底我们写了，但排查时数一遍 dts 里的组数，然后看代码里的索引。

**忘了 of_node_put。** 短时间运行看不出问题，引用泄漏是慢性病。习惯成自然：我们从 `of_find_node_by_path` 拿到的引用，每个退出路径上都还。

**改了 dts，板上还是老样子。** 挨个想过去：dtb 重新编了没有（这棵树要手动编，脚本不会替你），部署的目标文件名对不对（`imx6ull-aes.dtb`），重启了没有。`/proc/device-tree` 里看到新值，才算真的生效。

## 下一步

这一章我们手工完成了“驱动去设备树里取地址”的迁移，但驱动和设备树的结合还停在手动阶段：自己按路径找节点、自己管引用计数。下一章[板级 DTS 修改实操](09_board_dts_modification.md)把镜头转向设备树本身，走一遍在既有板级 dts 上加节点、编译、部署、验证的完整流程。再往后，平台设备驱动教程会把这些手动活交还给内核的匹配机制。

::: details 深读：这些 API 在内核里是怎么实现的
`of_find_node_by_path` 摸到的 `device_node` 是从哪来的？内核启动时怎么把一张扁平的 dtb 展开成这棵可以 `ls` 的树？`of_platform_populate` 又是怎么把节点变成设备的？这一整条链路我们将在独立的设备树原理仓库里逐章拆解（手搓 DTB 解析器、内核走读两个系列），本卷链接待该仓库篇目定稿后接入。
:::
