---
title: 内核概述
---

# 从0开始认识Linux内核：那个让无数嵌入式工程师又爱又恨的庞然大物

::: info 本节你将学到
- 作为嵌入式工程师，需要对 Linux 内核理解到什么程度
- **主线内核**与 NXP **linux-imx BSP** 的区别
- 内核源码目录的整体地图，知道每个目录大概干什么
:::

::: tip 前置知识 · 环境
- 已了解 U-Boot 的作用（见 [什么是 U-Boot](../uboot/01_what_is_uboot)）
- 工具链已安装就绪
:::

## 为什么要写这篇文章

老实说，当我第一次面对Linux内核源码的时候，我是真的懵了。

不是因为代码太难——虽然确实很难——而是因为它太大了。你`ls`一下源码目录，密密麻麻的子目录就有几十个，每个子目录下面还有一堆文件。更糟糕的是，网上的教程要么是"hello world"级别的玩具内核，要么就是上来就让你啃《Understanding the Linux Kernel》这种大部头。前者学不到东西，后者看得你怀疑人生。

我当时的问题是：我只是想在自己的i.MX6ULL板子上跑一个Linux系统，我需要理解哪些东西？主线内核和NXP的linux-imx有什么区别？为什么有些教程说用5.x版本，有些说用4.x？内核源码这堆目录都是干嘛的？

这些问题花了我很长时间才搞清楚。所以这篇文章的目标很简单：给你一个清晰的Linux内核入门地图。我不会教你写内核模块，也不会讲内核调度的实现细节——那些内容在别的地方有更好的教程。我要讲的是，作为一个嵌入式工程师，你需要对Linux内核有什么程度的理解，以及如何开始这个学习之旅。

## Linux内核的前世今生：从0.01版本到现在

Linux内核的故事已经讲了三十多年了。1991年8月，芬兰大学生Linus Torvalds在comp.os.minix新闻组发了这么一个帖子：

> "我正在做一个（免费的）操作系统（只是个爱好，不会像GNU那样大而专业），可能在386（486）AT克隆机上有点意思。这个任务从4月份开始，现在基本准备好了。"

当时的内核版本是0.01，大概有一万行代码，只能支持386硬件，基本上是个玩具。但Linus采用了一个聪明的策略：开源。他把代码放到FTP服务器上，任何人都可以下载、修改、提交补丁。这种开发模式在当时的商业软件环境下是革命性的。

1994年3月，Linux 1.0发布，支持x86和Alpha硬件，大约17万行代码。这时候的Linux已经可以用于实际工作了。之后的发展是爆炸式的：

- 1996年发布2.0版本，支持多架构
- 2003年发布2.6版本，引入了O(1)调度器、抢占式内核等重大改进
- 2011年发布3.0版本，从这时开始版本号变得简单，去掉了".stable"之类的东西
- 2015年后采用基于时间的版本号：x.y-rcN（候选版本）→ x.y（正式版）

版本命名规则也值得一提。从2.6.39之后，Linus觉得版本号太长了，直接跳到3.0。从3.0开始，版本号规律是：第一个数字是主版本号，第二个数字是次版本号，第三个数字（如果有）是修订号。现在更简单了，基本就是x.y的格式，x是主版本，y是次版本。

2026年初，主线内核已经发展到7.0rc版本了（抄，我还没体验呢哈哈）。对于嵌入式开发来说，选择哪个版本是个问题。最新版功能多、驱动新，但可能有未发现的bug；老版本稳定，但可能不支持你的硬件。i.MX6ULL这种2016年发布的芯片，官方BSP通常基于4.x或5.x的内核（我记得正点是4.1.19。。。），这是因为它需要一个相对稳定的基线。

## 主线内核 vs 厂商BSP：选择的两难

说到这里，就涉及到一个关键问题：你应该用主线内核（mainline）还是厂商的BSP内核？

主线内核就是kernel.org上发布的官方版本，由Linus和社区维护。优点是代码质量高、更新快、社区支持好。缺点是，新硬件的支持往往滞后。芯片厂商发布新芯片后，驱动代码通常先放到厂商自己的BSP里，经过一段时间才会上游到主线。

BSP（Board Support Package）内核是厂商基于主线内核修改的版本。以NXP为例，他们维护的linux-imx仓库包含了i.MX系列处理器的所有专用驱动和补丁。比如NXP的GALCORE GPU驱动、专门的电源管理代码、i.MX特有的外设驱动等等。这些东西在主线内核里要么没有，要么版本落后。

对于i.MX6ULL这样的芯片，我的建议是：学习阶段用主线内核（5.x或6.x），理解内核的工作原理；项目开发用厂商BSP，确保所有硬件功能可用。当你的理解足够深之后，可以考虑把BSP里的改动逐步迁移到主线内核。

IMX-Forge项目采用的是NXP的linux-imx，好消息是——他很潮，相较于我知道全志的SDK或者是RK的SDK基本上不是5.4就是6.1，咱们的这个内核是6.12.3（笔者发现linux-imx打了几个patch已经到6.12.49了）

## 为什么选择i.MX6ULL + linux-imx

你可能会问，现在都2026年了，为什么不选i.MX9这种更新的芯片？这个问题问得好，答案也很现实：学习成本。

i.MX6ULL是一款经典的ARM Cortex-A7处理器，2016年发布，到现在已经快十年了。但"老"不等于"过时"。它的优势在于：

- 资料丰富。网上有无数教程、论坛帖子、开源项目
- 社区成熟。遇到问题，很大概率别人已经踩过坑了
- 成本低。开发板便宜，适合个人学习和实验
- 性能适中。Cortex-A7单核或双核，最高792MHz（但愿我没记错），足够运行Linux和常见应用
- 外设齐全。UART、SPI、I2C、Ethernet、LCD、Camera，该有的都有

对比之下，i.MX9用的是Cortex-A55，性能强多了，但资料相对少，学习曲线陡峭。如果你是新手，从i.MX6ULL开始是最稳妥的选择。

## 内核源码目录结构：代码都放在哪

好了，现在假设你已经下载了linux-imx源码（IMX-Forge项目里在`third_party/linux-imx`），第一次看到这个庞大的目录树，心里发虚。别慌，我们来逐个目录看看。

### arch/：架构相关代码

`arch/`目录按CPU架构组织，每个子目录是一个架构。对于ARM平台，我们主要关心`arch/arm/`和`arch/arm64/`。

```bash
arch/arm/
├── boot/          # 启动相关代码，包含镜像打包工具
├── configs/       # 各种defconfig文件（板级默认配置）
├── kernel/        # ARM特定的内核核心代码
├── mm/            # ARM特定的内存管理
├── mach-*/        # 各厂商/系列的SoC代码（如mach-imx）
├── platsmp*       # 多平台支持相关代码
└── tools/         # ARM专用工具
```

defconfig是各板型的默认内核配置，我们在后续编译章节会详细讲解。

`mach-imx`子目录是NXP i.MX系列处理器的专用代码，里面按代数分了imx1/、imx5/、imx6/、imx7/等。i.MX6ULL相关的代码就在`mach-imx/`下面。

### drivers/：驱动代码的大本营

`drivers/`是最大的目录之一，包含了所有的设备驱动代码。

```bash
drivers/
├── clk/           # 时钟驱动
├── gpio/          # GPIO驱动
├── i2c/           # I2C总线驱动
├── mmc/           # eMMC/SD卡驱动
├── net/           # 网络驱动
├── spi/           # SPI总线驱动
├── tty/           # 串口驱动
├── usb/           # USB驱动
├── video/         # 显示驱动
├── watchdog/      # 看门狗驱动
└── ...
```

每个子目录对应一类设备。以`drivers/clk/`为例，里面按厂商/平台组织：

```bash
drivers/clk/
├── clk-imx6q.c    # i.MX6Q时钟驱动
├── clk-imx6sl.c   # i.MX6SL时钟驱动
├── clk-imx6sll.c  # i.MX6SLL时钟驱动
├── clk-imx6sx.c   # i.MX6SX时钟驱动
└── clk-imx6ul.c   # i.MX6UL/6ULL时钟驱动
```

这些文件实现了i.MX6ULL的时钟树：PLL、PFD、各种分频器、门控时钟。时钟系统是SoC的基础，几乎所有外设都依赖它。

### kernel/：内核核心代码

`kernel/`目录包含了内核的核心子系统，与架构无关：

```bash
kernel/
├── sched.c        # 调度器
├── fork.c         # 进程创建
├── exec.c         # 程序执行
├── signal.c       # 信号处理
├── sys.c          # 系统调用表
├── time.c         # 时间管理
├── timer.c        # 定时器
├── irq/           # 中断处理
├── dma/           # DMA管理
├── power/         # 电源管理
└── ...
```

这些代码实现了Linux内核的核心功能：进程调度、内存管理、中断处理、系统调用等。作为一个嵌入式工程师，你不需要完全理解这些代码，但至少知道它们在哪里，出了问题知道去哪里查。

### mm/：内存管理

`mm/`目录实现了虚拟内存系统：

```bash
mm/
├── page_alloc.c   # 物理页面分配
├── slab.c         # Slab分配器
├── mmap.c         # 内存映射
├── oom_kill.c     # OOM处理
└── ...
```

对于嵌入式系统，内存管理的重要性不言而喻。i.MX6ULL有512MB DDR，内核和用户空间共享这些内存，如何高效分配、避免碎片，都是这里处理的。

### fs/：文件系统

`fs/`目录包含了各种文件系统的实现：

```bash
fs/
├── ext4/          # EXT4文件系统
├── fat/           # FAT文件系统
├── jffs2/         # JFFS2文件系统（用于NOR Flash）
├── ubifs/         # UBIFS文件系统（用于NAND Flash）
├── proc/          # proc伪文件系统
└── sysfs/         # sysfs伪文件系统
```

嵌入式系统常用的是UBIFS（用于NAND Flash）和FAT（用于SD卡）。proc和sysfs是伪文件系统，用于向用户空间暴露内核信息。

### init/：内核初始化

`init/`目录虽然小，但非常重要：

```bash
init/
├── main.c         # 内核启动的主函数
├── do_mounts.c    # 挂载根文件系统
└── ...
```

`main.c`里的`start_kernel()`函数是内核启动的C入口点，相当于用户空间程序的`main()`函数。这里会进行各种初始化：陷阱初始化、内存初始化、调度器初始化、中断初始化、设备初始化等等。最后挂载根文件系统，启动init进程。

### net/：网络协议栈

`net/`目录实现了完整的TCP/IP协议栈：

```bash
net/
├── core/          # 核心协议栈
├── ipv4/          # IPv4
├── ipv6/          # IPv6
├── bridge/        # 网桥
└── ...
```

如果要用以太网、Wi-Fi，这部分代码就跑不掉。好在内核的网络协议栈很成熟，大部分情况下不需要修改。

### scripts/：构建脚本和工具

`scripts/`目录包含各种辅助脚本和工具：

```bash
scripts/
├── kconfig/       # Kconfig配置系统
├── mkcompile_h    # 生成compile.h
├── modpost        # 模块后处理
└── ...
```

Kconfig系统在这里，所以`make menuconfig`之类的命令要用到这里的代码。

### 其他重要目录

- `include/`：头文件，按子系统组织
- `block/`：块设备层（如eMMC、SD卡）
- `crypto/`：加密算法
- `lib/`：通用库函数
- `security/`：安全框架（如SELinux）
- `sound/`：ALSA音频子系统
- `tools/`：各种工具（如perf性能分析工具）

## 内核启动流程概述：从汇编到C的奇妙旅程

理解了目录结构，我们再来看看内核是怎么启动的。这个流程对于调试启动问题非常重要——如果你的板子卡在某个地方，知道启动流程能帮你快速定位。

### 第一阶段：汇编入口

当U-Boot把控制权交给内核时，内核的第一条指令在汇编代码里。对于ARM平台，入口点在`arch/arm/kernel/head.S`：

```assembly
ENTRY(stext)
    /* 省略各种检查和初始化 */
    bl  __calc_mmu_ext        /* 计算MMU扩展 */
    bl  __enable_mmu          /* 使能MMU */
    b   __mmap_switched       /* 跳转到C代码 */
ENDPROC(stext)
```

这个阶段做的事情包括：验证CPU ID、检查处理器类型、计算物理内存和虚拟内存的偏移、创建初始页表、使能MMU、最终跳转到C代码。全部用汇编写，因为这时候还没有C运行环境。

### 第二阶段：start_kernel()

跳转到C代码后，入口是`init/main.c`里的`start_kernel()`：

```c
asmlinkage __visible void __init __no_sanitize_addr start_kernel(void)
{
    char *command_line;
    char *after_dashes;

    set_task_stack_end_magic(&init_task);
    smp_setup_processor_id();
    debug_objects_early_init();

    cgroup_init_early();

    local_irq_disable();
    early_boot_irqs_disabled = true;

    /* ... 大量初始化调用 ... */

    trap_init();
    mm_init();
    sched_init();
    early_irq_init();
    init_IRQ();
    pidhash_init();
    rcu_init();

    /* ... 更多初始化 ... */

    rest_init();
}
```

`start_kernel()`调用了大量的初始化函数，每个函数负责一个子系统。顺序很重要，比如必须先初始化内存管理，才能初始化需要动态分配内存的子系统。

### 第三阶段：rest_init()和init进程

`start_kernel()`最后调用`rest_init()`，这里会创建kernel_init线程和kthreadd：

```c
static noinline void __ref rest_init(void)
{
    struct task_struct *tsk;
    int rc;

    rc = kernel_thread(kernel_init, NULL, CLONE_FS);
    /* ... */
    rc = kernel_thread(kthreadd, NULL, CLONE_FS | CLONE_FILES);
    /* ... */

    system_unbound_wq_alloc();
    rcu_scheduler_starting();
    /* ... */

    cpu_startup_entry(CPUHP_ONLINE);
}
```

`kernel_init`线程最终会挂载根文件系统，执行`/init`程序（或`/sbin/init`），完成用户空间的启动。

### 第四阶段：用户空间启动

内核启动init进程后，控制权就交给了用户空间。init进程会：

1. 挂载必要的文件系统（/proc、/sys、/dev等）
2. 解析/etc/inittab或配置文件
3. 启动各种系统服务（syslogd、networkd等）
4. 启动登录shell或图形界面

这个阶段已经不在内核范畴了，但它和内核密切相关——如果根文件系统有问题，init启动失败，系统就"起不来"。

## 踩坑笔记：那些常见的误解

在理解内核的过程中，我踩过不少坑，这里分享几个最常见的。

### 误区1："内核就是Linux"

不对。Linux只是内核，kernel = kernel。完整的Linux系统包括：bootloader（U-Boot）、kernel、rootfs（用户空间）。内核负责管理硬件和资源，用户空间提供应用程序和工具。你运行的`ls`、`cat`这些命令，不是内核的一部分。

### 误区2："主线内核最新版最好"

对于嵌入式开发，这往往不对。主线内核确实功能新、bug修复及时，但芯片厂商的驱动支持往往滞后。i.MX6ULL在主线内核里能跑起来，但可能GPU加速、某些外设驱动有问题。BSP内核虽然"老"一点，但厂商已经测试过了，稳定性更好。

### 误区3："内核源码都要读完才敢改"

没人读完整个内核源码，包括Linus本人。内核太大了，而且各个子系统相对独立。你只需要理解你要改的部分即可。如果要做网络驱动，专注net/和drivers/net/；如果要做文件系统，专注fs/。站在巨人肩膀上，不是从零开始。

## 下一章预告

到这里，你应该对Linux内核有了一个整体的认识：它从哪里来、主线和BSP有什么区别、源码怎么组织的、启动流程是什么样的。

但光看不练假把式。下一篇文章，我们正式进入编译环节。你会看到：

- 为什么编译前要装一堆看似无关的依赖包
- 交叉编译的原理是什么
- defconfig和.config有什么区别
- 编译出来的各种文件都是干什么用的
- 如何验证编译产物是否正确

准备好了吗？我们开始动手编译内核。

---

**延伸阅读**

- [The Linux Kernel Archives](https://www.kernel.org/) - 官方内核发布网站
- [Linux Kernel Newbies](https://kernelnewbies.org/) - 内核新手社区
- [NXP Linux Documentation](https://docs.nxp.com/) - NXP官方文档
