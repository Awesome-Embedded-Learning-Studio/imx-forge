---
title: 启动与调试
---

# Linux内核启动与调试：从bootargs到init进程的那几百万行代码

## 为什么要写这一章

如果你跟着前面的教程一路走过来，这时候你应该已经成功让内核在板子上跑起来了。恭喜你！这真是一个不小的成就。

但——内核启动的那一瞬间到底发生了什么？

你可能会在串口日志里看到一堆类似这样的东西：

```
Uncompressing Linux... done, booting the kernel.
Boot Linux on physical CPU 0x0
Linux version 5.15.72-gxxxxxxxx (builduser@buildhost) (arm-none-linux-gnueabihf-gcc 11.3.0) #1 PREEMPT
CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=10c5387d
CPU: div instructions available: patching division code
CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
...
```

你大概能猜出这是内核在自我介绍，但后面那一大坨到底是什么意思？出错了怎么找原因？bootargs里的那些参数都是干什么用的？

这一章的目标就是带你完整地走一遍内核启动流程。你会看到：

1. 内核是如何解压自己的
2. bootargs里的每个参数有什么作用
3. 内核初始化的各个阶段都做了什么
4. init进程是怎么启动的
5. 根文件系统是如何挂载的
6. 常见启动问题的排查方法

到了最后，你会对着串口日志发出"原来如此"的感叹，而不是一脸懵逼地关掉终端。

## 回顾：完整的启动链路

在深入内核启动之前，我们先回顾一下完整的启动链路：

```
ROM Code → U-Boot → Linux Kernel → Rootfs → Init Process
```

1. **ROM Code**：芯片上电后最先运行的代码，厂商写死的
2. **U-Boot**：引导加载程序，初始化硬件，加载内核
3. **Linux Kernel**：内核，完成系统初始化
4. **Rootfs**：根文件系统，提供用户空间环境
5. **Init Process**：第一个用户空间进程（PID=1），启动其他所有服务

我们这一章关注的是内核接管控制权之后发生的事情。U-Boot把内核镜像加载到内存，跳转到入口地址，剩下的就交给内核了。

## 内核启动参数：bootargs详解

bootargs是U-Boot传递给内核的启动参数，是一个字符串，包含了内核启动所需的各种配置信息。它在U-Boot的环境变量中定义：

```
setenv bootargs 'console=ttymxc0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait'
```

让我们逐个解析常见参数的含义。

### console参数

```
console=ttymxc0,115200n8
```

这指定内核的控制台输出设备：
- `ttymxc0`：控制台设备名（i.MX6ULL的串口0）
- `115200`：波特率
- `n8`：（可选）无校验，8位数据位

**多个console**：可以指定多个控制台，内核会依次尝试：

```
console=ttymxc0,115200 console=tty0
```

这样早期输出走串口，后面可以切换到显示器。

### root参数

```
root=/dev/mmcblk0p2
```

指定根文件系统位置：
- `/dev/mmcblk0p2`：eMMC的第二个分区
- `/dev/nfs`：NFS根文件系统（网络启动）
- `/dev/ram0`：内存文件系统（initramfs）

**其他常见写法**：

```
# UUID方式
root=UUID=12345678-1234-1234-1234-123456789abc

# PARTUUID方式
root=PARTUUID=12345678-02

# NFS网络启动
root=/dev/nfs nfsroot=192.168.1.100:/path/to/rootfs,v3,tcp

# UBIFS
root=ubi0:rootfs ubi.mtd=2 rootfstype=ubifs
```

### rootfstype参数

```
rootfstype=ext4
```

指定根文件系统的类型。常见类型：
- `ext4`：最常用的Linux文件系统
- `ubifs`：用于Flash存储的文件系统
- `jffs2`：另一种Flash文件系统
- `nfs`：网络文件系统

### rootwait参数

```
rootwait
```

告诉内核等待根设备就绪。对于eMMC/SD卡这种需要时间初始化的设备很重要。没有这个参数，内核可能在存储设备准备好之前就尝试挂载，导致启动失败。

### 其他常见参数

```
# 初始化程序
init=/linuxrc
init=/sbin/init

# 内存大小（通常自动检测）
mem=512M

# IP配置（用于NFS启动）
ip=192.168.1.50:192.168.1.100:192.168.1.1:255.255.255.0::eth0:off

# 关闭某些功能
quiet          # 减少内核输出
loglevel=4     # 设置日志级别
rdinit=/init   # 指定initramfs的init程序

# 调试参数
earlyprintk    # 尽早输出到串口
ignore_loglevel # 忽略日志级别，全部输出
debug          # 开启调试信息
```

## 内核启动流程全景图

内核启动是一个复杂的过程，我们按时间顺序来看。

### 阶段1：解压内核（如果使用压缩镜像）

U-Boot跳转到的是解压代码的入口。内核首先解压自己到正确的位置。

串口输出：
```
Uncompressing Linux... done, booting the kernel.
```

如果这里卡住，可能是：
1. 内核镜像损坏（重新编译）
2. 内存地址不对（检查CONFIG_SYS_TEXT_BASE）

### 阶段2：早期初始化（汇编代码）

解压后的代码跳转到`start_kernel`函数，开始C语言执行。但在此之前，有一段汇编代码做最基本的初始化：

- 检测CPU类型
- 验证处理器ID
- 创建临时页表
- 开启MMU
- 跳转到C语言入口

### 阶段3：start_kernel——主初始化函数

这是内核初始化的核心函数，位于`init/main.c`。它按顺序调用各种初始化函数：

```c
asmlinkage __visible void __init start_kernel(void)
{
    char *command_line;
    char *after_dashes;

    set_task_stack_end_magic(&init_task);
    smp_setup_processor_id();
    debug_objects_early_init();

    cgroup_init_early();

    local_irq_disable();
    early_boot_irqs_disabled = true;

    boot_cpu_init();
    page_address_init();
    pr_notice("%s", linux_banner);
    setup_arch(&command_line);
    ...
}
```

串口开始大量输出：
```
Linux version 5.15.72-gxxxxxxxx (builduser@buildhost) (arm-none-linux-gnueabihf-gcc 11.3.0) #1 PREEMPT
CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=10c5387d
CPU: div instructions available: patching division code
CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
OF: fdt: Machine model: NXP i.MX6ULL 14x14 EVK
Memory policy: Data cache: writeback
...
```

### 阶段4：设备树解析

内核解析U-Boot传递的设备树，了解硬件配置：

```
OF: fdt: Machine model: NXP i.MX6ULL 14x14 EVK
printk: console [tty1] enabled
printk: console [ttymxc0] enabled
```

设备树告诉内核：
- 有哪些CPU
- 内存大小和地址
- 有哪些串口（以及哪个用作控制台）
- 有哪些存储设备
- 外设的配置信息

### 阶段5：内存初始化

内核设置内存管理系统：

```
Zone ranges:
  DMA      [mem 0x0000000080000000-0x000000008fffffff]
  Normal   empty
  Movable zone start for each node
Early memory node ranges
  node   0: [mem 0x0000000080000000-0x000000008fffffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000008fffffff]
```

i.MX6ULL有512MB内存，地址从0x80000000开始。

### 阶段6：中断控制器初始化

```
irq: irq_domain added at CPU0, irq_hwirq=0x0, nr_irqs=240
GIC: Using split EOI/Deactivate mode
```

中断控制器是硬件和内核之间的桥梁，必须尽早初始化。

### 阶段7：时钟初始化

```
clocksource: arm_global_timer: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785 ns
sched_clock: 32 bits at 24MHz, resolution 41ns, wraps every 89478484971ns
```

内核需要一个高精度时钟源来调度进程。

### 阶段8：早期控制台

```
printk: console [ttymxc0] enabled
printk: console [tty1] enabled
bootconsole [ttymxc0] enabled
```

控制台初始化完成后，内核的printk输出就能看到啦。

### 阶段9：驱动初始化

内核开始初始化各个子系统：

```
NET: Registered protocol family 16
DMA: preallocated 256 KiB pool for atomic coherent allocations
cpuidle: using governor ladder
cpuidle: using governor menu
```

然后是平台设备和驱动的探测：

```
imx6ul-pinctrl 20e0000.iomuxc: failed to request pin 135 for GPIO
imx6ul-pinctrl 20e0000.iomuxc: pin 135 already requested by 20e0000.iomuxc;
   failed to request pin 135 for GPIO
```

**踩坑提醒**：这里的警告不一定是错误。很多驱动会尝试多个配置，失败就换下一个。只有最后失败才需要担心。

### 阶段10：块设备初始化

```
mmc0: new SD card at address 1234
mmcblk0: mmc0:1234 SA32G 29.7 GiB
 mmcblk0: p1 p2
```

存储设备（eMMC/SD卡）被识别并注册。

### 阶段11：网络初始化

```
libphy: 20b0000.ethernet-1:00: mdio_register_fixed
Fixed MDIO Bus: probed
libphy: 20b0000.ethernet-1:00: phy_connect: attached PHY driver [Generic PHY]
```

网络驱动加载，PHY被探测。

### 阶段12：文件系统初始化

```
VFS: Mounted root (ext4 filesystem) readonly on device 179:2.
devtmpfs: mounted
```

根文件系统被挂载！这是关键的一步。

`179:2`的含义：
- `179`：主设备号（块设备）
- `2`：次设备号（分区2）

可以用`ls -l /dev/block/179:2`查看对应哪个设备。

### 阶段13：启动init进程

```
Run /linuxrc as init process
  with arguments:
    /linuxrc
  with environment:
    HOME=/
    TERM=linux
...
```

内核跳转到用户空间的第一个进程！PID=1诞生了。

### 阶段14：系统就绪

```
 Welcome to IMX-Forge Linux

imx6ullpilot login:
```

看到登录提示符，内核启动完成！

## 常见启动问题排查

### 问题1：内核解压后卡住

症状：
```
Uncompressing Linux... done, booting the kernel.
```
然后什么都没有了。

可能原因：
1. **入口地址不对**：检查U-Boot的`bootm`地址是否正确
2. **机器ID不匹配**：设备树里的`compatible`和内核不匹配
3. **内存配置错误**：DDR初始化有问题

排查方法：
- 确认U-Boot加载内核的地址
- 检查设备树是否被正确加载
- 用`bdinfo`命令查看U-Boot识别的内存信息

### 问题2：设备树解析失败

症状：
```
OF: fdt: Error -21 scanning interrupt-controller node
```

可能原因：
- 设备树文件损坏
- 设备树版本不匹配
- 中断控制器配置错误

排查方法：
```bash
# 检查设备树编译是否成功
dtc -I dtb -O dts imx6ull-14x14-evk.dtb

# 对比设备树源码和生成的dtb
# 在U-Boot中打印设备树
fdt addr $fdtaddr
fdt print /
```

### 问题3：控制台无输出

症状：内核启动，但串口什么都没有。

可能原因：
1. **console参数错误**：
   ```
   # 错误：设备名不对
   console=ttymcx0,115200

   # 正确
   console=ttymxc0,115200
   ```

2. **串口驱动没加载**：设备树里串口节点被禁用了

3. **波特率不匹配**：内核和U-Boot的波特率要一致

排查方法：
- 加上`earlyprintk`参数
- 检查设备树中串口节点状态
- 用`loglevel=8`强制输出所有日志

### 问题4：根文件系统挂载失败

症状：
```
VFS: Cannot open root device "mmcblk0p2" or unknown-block(179,2): error -11
Please append a correct "root=" boot option
```

可能原因：
1. **设备名不对**：
   ```
   # eMMC可能是
   root=/dev/mmcblk0p2

   # SD卡可能是
   root=/dev/mmcblk1p2
   ```

2. **分区不存在**：烧录时分区表不对

3. **文件系统类型不对**：
   ```
   # 忘记指定文件系统类型
   root=/dev/mmcblk0p2 rootfstype=ext4
   ```

4. **驱动没加载**：eMMC/SD卡驱动没有编译进内核

排查方法：
```bash
# 在U-Boot中列出存储设备
mmc list
mmc dev 0
mmc part

# 内核启动后检查
cat /proc/partitions
ls -l /dev/block/
```

### 问题5：init进程启动失败

症状：
```
Kernel panic - not syncing: No init found.  Try passing init= option to kernel.
```

可能原因：
1. **init程序不存在**：根文件系统里没有`/sbin/init`或`/linuxrc`
2. **文件系统损坏**：烧录不完整
3. **动态链接器问题**：init程序依赖的库找不到

排查方法：
```bash
# 检查文件系统内容
ls -l /rootfs/sbin/init
ls -l /rootfs/lib/ld-*.so*

# 检查init程序依赖
arm-none-linux-gnueabihf-readelf -d /rootfs/sbin/init

# 用busybox作为init
init=/bin/busybox
```

## 内核日志级别配置

内核日志级别决定了哪些消息会输出到控制台。

### 级别定义

```c
#define KERN_EMERG   "0"    // 紧急情况，系统可能崩溃
#define KERN_ALERT   "1"    // 必须立即处理
#define KERN_CRIT    "2"    // 严重情况
#define KERN_ERR     "3"    // 错误
#define KERN_WARNING "4"    // 警告
#define KERN_NOTICE  "5"    // 正常但重要
#define KERN_INFO    "6"    // 信息
#define KERN_DEBUG   "7"    // 调试
```

### 配置方法

**方法1：bootargs参数**
```
loglevel=8           # 启动时日志级别
quiet                # 安静模式，只输出错误
ignore_loglevel      # 忽略日志级别限制
debug                # 等同于loglevel=8
```

**方法2：运行时修改**
```bash
# 查看当前配置
cat /proc/sys/kernel/printk
# 4    4    1    7
# |    |    |    |
# |    |    |    +-- 默认控制台日志级别
# |    |    +------- 最小控制台日志级别
# |    +------------ 当前控制台日志级别
# +----------------- 默认日志级别

# 修改
echo 8 > /proc/sys/kernel/printk
```

**方法3：dmesg控制**
```bash
# 只看最后N行
dmesg | tail -20

# 过滤关键字
dmesg | grep -i error

# 清空日志
sudo dmesg -c

# 实时监控
dmesg -w
```

## 串口调试配置

串口是最重要的调试工具，正确配置很关键。

### U-Boot串口配置

在U-Boot源码的`include/configs/mx6ull_14x14_evk.h`中：

```c
#define CONFIG_MXC_UART_BASE        UART1_BASE
#define CONFIG_BAUDRATE             115200
#define CONFIG_CONS_INDEX           1
```

### 内核串口配置

在设备树中：

```dts
&uart1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart1>;
    status = "okay";
};
```

确保：
1. status是"okay"
2. pinctrl配置正确
3. 时钟使能

### 串口工具选择

**Windows**：
- PuTTY（推荐）
- Tera Term
- SecureCRT

**Linux**：
```bash
# screen
screen /dev/ttyUSB0 115200

# minicom
minicom -D /dev/ttyUSB0 -b 115200

# picocom（轻量级）
picocom -b 115200 /dev/ttyUSB0
```

## 启动优化技巧

### 减少启动时间

1. **剪裁内核**：禁用不需要的功能
   ```
   # 不需要调试信息
   # CONFIG_DEBUG_KERNEL is not set

   # 不需要内核模块签名验证
   # CONFIG_MODULE_SIG is not set
   ```

2. **使用initramfs**：小内存系统可用
   ```
   CONFIG_INITRAMFS_SOURCE="rootfs.cpio.gz"
   ```

3. **延迟加载驱动**：
   ```
   # 把驱动编译成模块，按需加载
   ```

4. **并行初始化**：
   ```
   CONFIG_PREEMPT=y
   CONFIG_SMP=y  # 如果有多核
   ```

### 启动时间分析

内核内置了启动时间分析功能：

```
initcall_debug     # 打印每个initcall的耗时
```

输出示例：
```
initcall bootparam_early_init+0x0/0x40 returned 0 after 0 usecs
initcall random_init+0x0/0x1ac returned 0 after 1234 usecs
initcall init_jiffies_clocksource+0x0/0x2c returned 0 after 56 usecs
...
```

可以找出哪些初始化函数耗时最长。

## 完整启动链路回顾

让我们用一张完整的时序图来回顾整个启动过程：

```
时间轴    ROM Code        U-Boot          内核              用户空间
  |           |               |               |                  |
  | 上电       |               |               |                  |
  |----------->|               |               |                  |
  |           | 从存储加载      |               |                  |
  |           |--------------->|               |                  |
  |           | 初始化硬件      |               |                  |
  |           | 加载设备树      |               |                  |
  |           | 加载内核        |               |                  |
  |           |--------------->|               |                  |
  |           |               | 解压内核       |                  |
  |           |               |-------------->|                  |
  |           |               | 早期初始化     |                  |
  |           |               | 解析设备树     |                  |
  |           |               | 内存初始化     |                  |
  |           |               | 驱动探测       |                  |
  |           |               | 挂载根文件系统  |                  |
  |           |               |-------------->|                  |
  |           |               |               | 启动init进程      |
  |           |               |               |----------------->|
  |           |               |               | 启动系统服务      |
  |           |               |               | 显示登录提示      |
  v           v               v               v                  v
```

每个阶段都有它的工作：

1. **ROM Code**：最基础的硬件初始化，加载U-Boot
2. **U-Boot**：更复杂的硬件设置，为内核准备环境
3. **内核**：建立系统基础设施，让用户空间能运行
4. **init进程**：启动系统服务，最终达到可用状态

## 总结：Linux教程的收官

到这里，我们的Linux内核教程就告一段落了。回顾一下我们走过的路：

1. **什么是内核**：内核是操作系统的核心，管理硬件和资源
2. **交叉编译**：为什么需要交叉编译，如何搭建工具链
3. **内核配置**：defconfig、menuconfig、.config的关系
4. **设备树**：硬件描述的标准化方式
5. **编译内核**：完整的构建流程和产物验证
6. **驱动入门**：字符驱动的基本框架和调试方法
7. **启动调试**：内核如何启动，问题如何排查

但学习没有终点。内核开发是一门深奥的学问，我们只是打开了大门。后续你可以继续探索：

- **深入设备树**：复杂的设备绑定和覆盖机制
- **驱动框架**：platform、I2C、SPI、网络、块设备驱动
- **并发控制**：互斥锁、自旋锁、RCU、原子操作
- **内存管理**：页表、 slab分配器、CMA
- **电源管理**：休眠、唤醒、设备电源状态
- **实时性**：PREEMPT_RT、中断线程化
- **安全**：SELinux、AppArmor、安全启动
- **性能优化**：追踪、分析、热点定位

嵌入式Linux开发是一条漫长的路，但也是一条充满乐趣的路。当你看着自己移植的系统在板子上跑起来，那种成就感是无可替代的。

希望这些教程能帮助你入门，减少一些摸索的痛苦。记住，遇到问题先看日志，日志会告诉你真相。保持好奇心，保持耐心，你一定能成为嵌入式Linux的高手。

祝你开发顺利！
