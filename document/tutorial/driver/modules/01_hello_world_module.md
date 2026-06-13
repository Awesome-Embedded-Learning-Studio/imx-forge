# Hello World内核模块：内核编程的第一步

## 为什么要写这一章

老实说，当你第一次决定写内核模块的时候，心里是既兴奋又紧张的。

兴奋是因为你要开始探索内核这个神秘的世界了——你的代码将直接运行在内核空间，拥有最高的权限，能直接访问硬件。紧张是因为……说实话，内核编程和用户空间编程完全不是一回事，一个bug就可能让整个系统崩溃。

我当年刚开始学的时候，网上那些教程要么太简单（hello world完事），要么太复杂（上来就讲字符设备驱动）。而且很多教程是基于x86的，跑在PC上，和咱们正点原子的i.MX6ULL开发板环境差异挺大的。

这一章的目标很简单：给你一个扎实的内核模块入门基础。我会把原理讲清楚，代码写明白，让你能够真正理解内核模块是怎么一回事，而不仅仅是复制粘贴代码。

## 什么是内核模块

先来说说内核模块到底是个什么东西。

在Linux系统中，内核镜像（zImage/Image）是一个单一的二进制文件，在系统启动时加载到内存。传统的做法是把所有需要的驱动都编译进内核镜像里，但这样做有几个问题：

1. **镜像太大**：每个驱动都加进去，内核文件会变得很大
2. **内存浪费**：不用的驱动代码也占用内存
3. **更新麻烦**：添加新功能需要重新编译整个内核

内核模块（Kernel Module）就是为了解决这些问题而诞生的。它是一种**动态加载**的目标文件（.ko文件），可以在系统运行时加载进内核，也可以在不需要时卸载。

参考内核文档中对模块系统的描述：

> **modules.rst** - "kbuild" is the build system used by the Linux kernel. Modules must use kbuild to stay compatible with changes in the build infrastructure...
>
> 文件位置：`third_party/linux-imx/Documentation/kbuild/modules.rst`

### 模块 vs 静态编译

让我们从内核源码的角度理解模块和静态编译的区别。

当驱动**静态编译进内核**时（`y`配置），它的初始化函数会被放入一个特殊的**initcall段**，在内核启动时按顺序调用。

当驱动编译成**模块**时（`m`配置），它的初始化函数只有在使用`insmod`加载时才会被调用。

看看`module.h`中的定义（`third_party/linux-imx/include/linux/module.h`）：

```c
#ifndef MODULE
/* 静态编译进内核的情况 */
#define module_init(x)	__initcall(x);
#define module_exit(x)	__exitcall(x);
#else /* MODULE */
/* 编译成模块的情况 */
#define module_init(initfn)					\
	static inline initcall_t __maybe_unused __inittest(void)		\
	{ return initfn; }					\
	int init_module(void) __copy(initfn)			\
		__attribute__((alias(#initfn)));		\
	___ADDRESSABLE(init_module, __initdata);

#define module_exit(exitfn)					\
	static inline exitcall_t __maybe_unused __exittest(void)		\
		{ return exitfn; }					\
	void cleanup_module(void) __copy(exitfn)		\
		__attribute__((alias(#exitfn)));		\
	___ADDRESSABLE(cleanup_module, __exitdata);
#endif
```

这段代码展示了`module_init`和`module_exit`宏的本质：

- **静态编译时**：它们把你的函数放到initcall段，内核启动时自动调用
- **编译成模块时**：它们创建一个`init_module`符号别名，加载器通过这个名字找到你的初始化函数

## 你的第一个Hello World模块

好了，理论差不多够了，让我们动手写第一个模块。

### 完整代码

```c
// SPDX-License-Identifier: GPL-2.0
/*
 * hello_world.c - 第一个内核模块
 *
 * 这是一个最简单的内核模块示例，展示了：
 * 1. module_init 和 module_exit 的使用
 * 2. MODULE_LICENSE 等模块信息宏的使用
 * 3. printk 的使用方法和日志级别
 *
 * 适用于：i.MX6ULL (ARM Cortex-A7) + Linux 6.12.49
 */

#include <linux/init.h>     /* module_init, module_exit */
#include <linux/module.h>   /* MODULE_LICENSE, MODULE_AUTHOR等 */
#include <linux/printk.h>   /* printk, pr_info等 */

/*
 * 模块初始化函数
 *
 * 当模块加载时（insmod）或内核启动时（静态编译）被调用
 * __init标记告诉链接器把这个函数放到.init.text段
 * 内核启动完成后，这个段的内存会被释放
 *
 * 返回值：0表示成功，负值表示错误码
 */
static int __init hello_init(void)
{
	/* printk是内核的printf，但需要指定日志级别 */
	/* KERN_INFO是日志级别宏，定义在 include/linux/kern_levels.h */
	printk(KERN_INFO "Hello World: 模块初始化中...\n");

	/* pr_*系列宏更方便，自动添加模块名前缀 */
	pr_info("Hello World: 这是我的第一个内核模块!\n");
	pr_info("Hello World: 运行在i.MX6ULL平台\n");

	/* 返回0表示初始化成功 */
	return 0;
}

/*
 * 模块退出函数
 *
 * 当模块卸载时（rmmod）被调用
 * __exit标记把这个函数放到.exit.text段
 * 注意：静态编译进内核时，exit函数不会被调用（内核不会退出）
 */
static void __exit hello_exit(void)
{
	pr_info("Hello World: 模块即将卸载，再见!\n");
}

/*
 * module_init 和 module_exit 宏
 *
 * 这两个宏是内核模块的入口和出口点
 * module_init(hello_init) -> 注册初始化函数
 * module_exit(hello_exit) -> 注册退出函数
 *
 * 展开后的效果：
 * - 编译成模块时：创建 init_module 和 cleanup_module 符号
 * - 静态编译时：放入 initcall 段，内核启动时调用
 */
module_init(hello_init);
module_exit(hello_exit);

/*
 * MODULE_LICENSE - 模块许可证声明
 *
 * 这个宏非常重要！它告诉内核你的模块使用什么许可证
 * 内核只允许GPL兼容的模块使用某些内核符号
 *
 * 常见的许可证字符串（定义在 include/linux/module.h）：
 * - "GPL"               - GNU General Public License v2
 * - "GPL v2"            - 同上
 * - "Dual BSD/GPL"      - BSD或GPL双重许可
 * - "Dual MIT/GPL"      - MIT或GPL双重许可
 * - "Proprietary"       - 专有许可（会污染内核）
 *
 * 如果你没有声明GPL兼容的许可证：
 * 1. 无法使用EXPORT_SYMBOL_GPL导出的符号
 * 2. 内核会被标记为"tainted"（被污染）
 * 3. 社区可能拒绝提供支持
 */
MODULE_LICENSE("GPL v2");

/*
 * MODULE_AUTHOR - 作者信息
 * 可以多次调用来列出多个作者
 * 格式："Name <email>" 或 "Name"
 */
MODULE_AUTHOR("你的名字 <your.email@example.com>");

/*
 * MODULE_DESCRIPTION - 模块描述
 * 简短描述这个模块的功能
 * 可以通过 modinfo 命令查看
 */
MODULE_DESCRIPTION("一个简单的Hello World内核模块示例");

/*
 * MODULE_VERSION - 模块版本
 * 可选的版本字符串
 */
MODULE_VERSION("1.0");
```

### 对应的Makefile

内核模块的Makefile和用户空间程序的Makefile完全不同，需要使用kbuild系统：

```makefile
# SPDX-License-Identifier: GPL-2.0
#
# Makefile for hello_world kernel module
#

# 如果要从这里编译（用于开发测试），取消下面的注释
# KERNELDIR := /path/to/your/kernel/source
# PWD := $(shell pwd)

# obj-m 表示要把这些文件编译成模块
# obj-y 表示要静态编译进内核
obj-m := hello_world.o

# 构建模块
# make           - 编译模块
# make clean     - 清理编译产物
# make install   - 安装模块到系统模块目录
# make modpost   - 生成Module.symvers（用于模块版本控制）

# 默认目标：构建内核模块
default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

# 或者使用更通用的方式（通过环境变量或自动检测）
ifeq ($(KERNELRELEASE),)
# 第一次调用：从命令行调用
KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

%:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) $@
else
# 第二次调用：从内核构建系统调用
# 这里不需要做任何事，kbuild会处理obj-m
endif

clean:
	rm -f *.o *.ko *.mod *.mod.c .*.cmd
	rm -rf Module.symvers modules.order .tmp_versions
```

**简化版Makefile（推荐新手使用）**：

```makefile
# SPDX-License-Identifier: GPL-2.0
# 最简单的Makefile，适合IMX-Forge项目使用

# 模块名称（会自动编译 hello_world.c -> hello_world.ko）
obj-m := hello_world.o

# 内核源码目录（IMX-Forge项目中）
KERNELDIR := ../../../../third_party/linux-imx

# 编译模块
all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

# 清理编译产物
clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
```

### 详细代码讲解

现在让我逐行解释代码中那些"看起来很奇怪"的地方。

#### __init 和 __exit 标记

```c
static int __init hello_init(void)
static void __exit hello_exit(void)
```

这两个标记在`include/linux/init.h`中定义：

```c
#define __init      __section(".init.text") __cold __latent_entropy __noinitretpoline
#define __exit      __section(".exit.text") __exitused __cold notrace
```

它们的作用是把函数放到特殊的ELF段：

- **`.init.text`段**：初始化代码，系统启动完成后可以释放
- **`.exit.text`段**：模块退出代码

为什么要有这个标记？因为内核启动时有很多初始化代码，这些代码执行一次后就再也不会用了。通过把它们放到单独的段，内核可以在启动完成后**释放这部分内存**，节省宝贵的RAM资源。

#### printk 日志级别

printk和用户空间的printf最大的区别是：printk需要指定**日志级别**。

日志级别定义在`include/linux/kern_levels.h`：

```c
#define KERN_EMERG   KERN_SOH "0"   /* 系统不可用 */
#define KERN_ALERT   KERN_SOH "1"   /* 需要立即采取行动 */
#define KERN_CRIT    KERN_SOH "2"   /* 严重情况 */
#define KERN_ERR     KERN_SOH "3"   /* 错误情况 */
#define KERN_WARNING KERN_SOH "4"   /* 警告情况 */
#define KERN_NOTICE  KERN_SOH "5"   /* 正常但重要的情况 */
#define KERN_INFO    KERN_SOH "6"   /* 信息性消息 */
#define KERN_DEBUG   KERN_SOH "7"   /* 调试消息 */
```

数字越小，优先级越高。内核有一个**控制台日志级别**（console_loglevel），只有优先级**高于或等于**这个级别的消息才会显示到控制台。

更推荐使用`pr_*`系列宏：

```c
pr_emerg("紧急消息\n");    /* KERN_EMERG */
pr_alert("警报消息\n");    /* KERN_ALERT */
pr_crit("严重消息\n");     /* KERN_CRIT */
pr_err("错误消息\n");      /* KERN_ERR */
pr_warn("警告消息\n");     /* KERN_WARNING */
pr_notice("通知消息\n");   /* KERN_NOTICE */
pr_info("信息消息\n");     /* KERN_INFO */
pr_debug("调试消息\n");    /* KERN_DEBUG，只在DEBUG定义时生效 */
```

这些宏的好处：
1. 自动添加`pr_fmt`前缀（通常是模块名）
2. 代码更简洁
3. 支持动态调试

## 模块加载和卸载的内部流程

让我们深入理解内核是如何加载和卸载模块的。

### 模块加载流程

当你执行`insmod hello_world.ko`时，内核会执行以下操作：

1. **系统调用**：用户空间调用`finit_module`系统调用
2. **ELF解析**：内核解析.ko文件的ELF格式（.ko是可重定位的ELF文件）
3. **内存分配**：为模块代码和数据分配内核内存
4. **符号解析**：解析模块引用的外部符号，检查版本
5. **重定位**：处理所有重定位项，修正地址
6. **依赖检查**：检查模块依赖的其他模块是否已加载
7. **初始化调用**：调用模块的`init`函数（即我们用`module_init`注册的函数）

相关代码位于`kernel/module/main.c`：

```c
/* 模块加载的主函数 */
static int load_module(struct load_info *info, const char __user *uargs,
		       int flags)
{
	/* ... 繁杂的初始化工作 ... */

	/* 调用模块的初始化函数 */
	err = mod->init(mod);

	if (err < 0) {
		/* 初始化失败，清理资源 */
		return err;
	}

	/* 成功！模块现在处于LIVE状态 */
	mod->state = MODULE_STATE_LIVE;
	return 0;
}
```

### 模块卸载流程

执行`rmmod hello_world`时：

1. **系统调用**：用户空间调用`delete_module`系统调用
2. **引用计数检查**：检查模块的引用计数是否为0
3. **退出调用**：调用模块的`exit`函数
4. **资源清理**：释放模块占用的内存和资源
5. **符号移除**：从内核符号表中移除模块的符号

## 在IMX6ULL上编译和运行

### 准备工作

假设你按照IMX-Forge项目的指引已经完成了交叉编译环境的搭建。

1. **确保内核已编译**：模块编译需要内核的头文件和配置
2. **确认交叉编译工具链**：arm-linux-gnueabihf-gcc

### 编译步骤

```bash
# 1. 创建工作目录
mkdir -p ~/driver_modules/hello_world
cd ~/driver_modules/hello_world

# 2. 将上面的代码保存为 hello_world.c
# 3. 将简化版Makefile保存为 Makefile

# 4. 修改Makefile中的路径
# KERNELDIR 指向你的linux-imx源码目录

# 5. 编译
make
```

如果一切顺利，你应该能看到：
```
make -C ../../../../third_party/linux-imx M=/home/xxx/driver_modules/hello_world modules
make[1]: Entering directory '.../linux-imx'
  CC [M]  /home/xxx/driver_modules/hello_world/hello_world.o
  MODPOST /home/xxx/driver_modules/hello_world/Module.symvers
  CC [M]  /home/xxx/driver_modules/hello_world/hello_world.mod.o
  LD [M]  /home/xxx/driver_modules/hello_world/hello_world.ko
make[1]: Leaving directory '.../linux-imx'
```

编译产物说明：
- `hello_world.o`：目标文件
- `hello_world.mod.o`：包含模块信息的特殊目标文件
- `hello_world.ko`：**内核模块文件**，这是我们要的最终产物
- `Module.symvers`：符号版本信息
- `modules.order`：模块链接顺序

### 部署和运行

```bash
# 1. 将.ko文件传输到开发板
scp hello_world.ko root@192.168.xxx.xxx:/root/

# 2. 在开发板上加载模块
ssh root@192.168.xxx.xxx
insmod hello_world.ko

# 3. 查看内核日志（应该能看到我们的printk输出）
dmesg | tail

# 输出示例：
# [ 1234.567890] Hello World: 模块初始化中...
# [ 1234.567912] Hello World: 这是我的第一个内核模块!
# [ 1234.567925] Hello World: 运行在i.MX6ULL平台

# 4. 检查模块是否已加载
lsmod | grep hello_world
# 或者
cat /proc/modules | grep hello_world

# 5. 查看模块信息
modinfo hello_world.ko

# 6. 卸载模块
rmmod hello_world

# 7. 再次查看日志（应该能看到退出消息）
dmesg | tail
# 输出示例：
# [ 1245.678901] Hello World: 模块即将卸载，再见!
```

### 通过NFS运行（推荐开发时使用）

如果你已经配置好了NFS根文件系统，可以直接在NFS目录中开发：

```bash
# 在开发机上
cd ~/nfs_root/root/driver_modules/
mkdir hello_world
cd hello_world
# 把 hello_world.c 和 Makefile 放在这里
make

# 在开发板上（NFS挂载的目录）
cd /root/driver_modules/hello_world
insmod hello_world.ko
```

这样每次修改代码后重新编译，开发板上直接就能运行新的.ko文件。

## 常见错误与调试方法

### 错误1：Unknown symbol

```
insmod: ERROR: could not insert module hello_world.ko: Unknown symbol
```

**原因**：模块引用了不存在的内核符号，可能是：
1. 内核配置不同，某些功能没启用
2. 版本不匹配

**调试方法**：
```bash
# 查看模块需要的符号
modinfo hello_world.ko

# 查看内核导出的符号
cat /proc/kallsyms | grep symbol_name
```

### 错误2：Invalid module format

```
insmod: ERROR: could not insert module hello_world.ko: Invalid module format
```

**原因**：模块与运行的内核版本不匹配

**调试方法**：
```bash
# 查看模块的版本信息
modinfo hello_world.ko | grep vermagic

# 查看当前内核版本
uname -r
```

确保编译模块时使用的内核源码与开发板运行的内核版本一致。

### 错误3：Permission denied

```
insmod: ERROR: could not insert module hello_world.ko: Permission denied
```

**原因**：需要root权限

**解决方法**：
```bash
sudo insmod hello_world.ko
# 或
su root
insmod hello_world.ko
```

### 错误4：Module license unset

```
hello_world: module license 'unspecified' taints kernel.
```

**原因**：缺少`MODULE_LICENSE()`声明，或使用了不兼容的许可证

**影响**：
- 内核被标记为"tainted"（污染）
- 社区可能拒绝提供bug报告支持
- 无法使用某些GPL-only的内核符号

**解决方法**：
```c
MODULE_LICENSE("GPL v2");  // 添加这一行
```

### 调试技巧

1. **使用dmesg查看内核日志**
```bash
dmesg | tail -20          # 查看最近20条
dmesg -c                  # 清空日志后重新测试
dmesg -w                  # 实时监控日志
```

2. **使用dynamic_debug动态调试**
```bash
# 启用模块的所有动态调试
echo 'module hello_world +p' > /sys/kernel/debug/dynamic_debug/control

# 查看可用的调试点
cat /sys/kernel/debug/dynamic_debug/control | grep hello_world
```

3. **使用ftrace跟踪函数调用**
```bash
# 跟踪特定函数
echo function > /sys/kernel/debug/tracing/current_tracer
echo hello_init > /sys/kernel/debug/tracing/set_ftrace_filter
cat /sys/kernel/debug/tracing/trace
```

## 模块信息查看工具

### modinfo - 查看模块信息

```bash
modinfo hello_world.ko
```

输出示例：
```
filename:       hello_world.ko
version:        1.0
description:    一个简单的Hello World内核模块示例
author:         你的名字 <your.email@example.com>
license:        GPL v2
srcversion:     XXXXXXXXXXXXXXXXXXXXXXXX
depends:
retpoline:      Y
name:           hello_world
vermagic:       6.12.49 SMP mod_unload modversions ARMv8
```

### lsmod - 列出已加载的模块

```bash
lsmod
```

输出格式：
```
Module                  Size  Used by
hello_world            16384  0
```

- `Size`：模块占用的内存大小（字节）
- `Used by`：引用计数，0表示可以安全卸载

### /proc和/sysfs下的模块信息

```bash
# 查看已加载模块的详细信息
cat /proc/modules

# 查看模块参数
ls /sys/module/hello_world/
cat /sys/module/hello_world/refcnt       # 引用计数
```

## 实战代码查看：看看内核里的模块是怎么写的

最好的学习方式是看内核源码中的实际驱动。让我们找一个简单的例子：

### 示例1：kobject示例

内核官方提供了一个很好的示例模块：

文件：`third_party/linux-imx/samples/kobject/kobject-example.c`

```c
static int __init example_init(void)
{
    int retval;

    example_kobj = kobject_create_and_add("kobject_example", kernel_kobj);
    if (!example_kobj)
        return -ENOMEM;

    retval = sysfs_create_group(example_kobj, &attr_group);
    if (retval)
        kobject_put(example_kobj);

    return retval;
}

static void __exit example_exit(void)
{
    kobject_put(example_kobj);
}

module_init(example_init);
module_exit(example_exit);
MODULE_DESCRIPTION("Sample kobject implementation");
MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Greg Kroah-Hartman <greg@kroah.com>");
```

### 示例2：看一个简单的字符设备驱动

找一个更接近实际驱动的例子：

文件：`third_party/linux-imx/drivers/char/misc.c`

```c
static int __init misc_init(void)
{
    int err;

    pr_info("misc device class registered\n");
#ifdef CONFIG_PROC_FS
    proc_create("misc", 0, NULL, &misc_proc_fops);
#endif
    err = class_register(&misc_class);
    if (err)
        goto fail_register;

    err = -EIO;
    if (register_chrdev(MISC_MAJOR, "misc", &misc_fops))
        goto fail_printk;
    misc_class->devnode = misc_devnode;
    return 0;

fail_printk:
    pr_err("misc: couldn't get major %d\n", MISC_MAJOR);
    class_unregister(&misc_class);
fail_register:
    remove_proc_entry("misc", NULL);
    return err;
}

static void __exit misc_exit(void)
{
    unregister_chrdev(MISC_MAJOR, "misc");
    class_unregister(&misc_class);
    remove_proc_entry("misc", NULL);
}
```

## 练习题

好了，理论讲完了，来做几道练习巩固一下。

### 练习1：添加模块参数

**题目**：修改hello_world模块，添加一个整数参数`count`和一个字符串参数`name`，在加载时可以指定这些参数的值。

**提示**：使用`module_param()`宏

**参考答案**：

```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>

/* 模块参数
 * module_param(name, type, perm)
 * - name: 参数名
 * - type: 参数类型 (int, bool, charp等)
 * - perm: sysfs权限 (0表示不在sysfs中可见)
 */
static int count = 1;
module_param(count, int, 0644);
MODULE_PARM_DESC(count, "打印次数");

static char *name = "world";
module_param(name, charp, 0644);
MODULE_PARM_DESC(name, "要问候的名字");

static int __init hello_init(void)
{
	int i;

	for (i = 0; i < count; i++) {
		pr_info("Hello %s! (第%d次)\n", name, i + 1);
	}

	return 0;
}

static void __exit hello_exit(void)
{
	pr_info("Goodbye %s!\n", name);
}

module_init(hello_init);
module_exit(hello_exit);
MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("你的名字");
MODULE_DESCRIPTION("带参数的Hello World模块");
```

**测试**：
```bash
insmod hello_world.ko count=3 name="i.MX6ULL"
# 查看参数
cat /sys/module/hello_world/parameters/count
cat /sys/module/hello_world/parameters/name
```

### 练习2：实现模块引用计数

**题目**：编写一个模块A，导出一个函数。编写另一个模块B，调用模块A的函数。测试加载顺序和引用计数。

**提示**：使用`EXPORT_SYMBOL()`或`EXPORT_SYMBOL_GPL()`

**参考答案**：

**模块A (module_a.c)**：
```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>

static void module_a_function(void)
{
	pr_info("模块A的函数被调用了\n");
}

/* 导出符号，让其他模块可以使用 */
EXPORT_SYMBOL_GPL(module_a_function);

static int __init module_a_init(void)
{
	pr_info("模块A已加载\n");
	return 0;
}

static void __exit module_a_exit(void)
{
	pr_info("模块A已卸载\n");
}

module_init(module_a_init);
module_exit(module_a_exit);
MODULE_LICENSE("GPL v2");
```

**模块B (module_b.c)**：
```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>

/* 声明外部符号 */
extern void module_a_function(void);

static int __init module_b_init(void)
{
	pr_info("模块B已加载，准备调用模块A的函数\n");
	module_a_function();
	return 0;
}

static void __exit module_b_exit(void)
{
	pr_info("模块B已卸载\n");
}

module_init(module_b_init);
module_exit(module_b_exit);
MODULE_LICENSE("GPL v2");
```

**Makefile**：
```makefile
obj-m := module_a.o module_b.o
KERNELDIR := ../../../../third_party/linux-imx

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules
```

**测试**：
```bash
# 1. 先加载A
insmod module_a.ko
cat /sys/module/module_a/refcnt    # 应该是0

# 2. 再加载B
insmod module_b.ko
cat /sys/module/module_a/refcnt    # 应该是1

# 3. 尝试卸载A（应该失败，因为B在使用）
rmmod module_a
# rmmod: ERROR: could not remove 'module_a': Device or resource busy

# 4. 先卸载B，再卸载A
rmmod module_b
rmmod module_a
```

### 练习3：实现模块自动加载

**题目**：使用`MODULE_ALIAS()`让模块在特定硬件存在时自动加载。

**提示**：结合设备树和`MODULE_DEVICE_TABLE()`

这个练习比较复杂，涉及到设备驱动的基础知识，我们在后面的章节会详细讲解。

### 练习4：分析一个真实驱动

**题目**：阅读`third_party/linux-imx/drivers/char/random.c`的前200行，理解：
1. 这个模块如何初始化
2. 使用了哪些模块宏
3. 注册了哪些设备接口

**提示**：使用grep搜索关键函数和宏

### 练习5：调试一个有bug的模块

**题目**：下面的模块有一个bug，加载后会导致问题。找出bug并修复。

```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/delay.h>

static int __init buggy_init(void)
{
	int i;

	pr_info("开始有bug的测试...\n");

	/* Bug: 在原子上下文中睡眠 */
	for (i = 0; i < 10; i++) {
		pr_info("计数: %d\n", i);
		msleep(1000);  /* 这里可能有问题 */
	}

	return 0;
}

static void __exit buggy_exit(void)
{
	pr_info("有bug的模块卸载\n");
}

module_init(buggy_init);
module_exit(buggy_exit);
MODULE_LICENSE("GPL v2");
```

**提示**：考虑模块初始化函数的执行上下文。

**参考答案**：
这个模块其实没有明显的bug（`module_init`可以睡眠），但可以引发讨论：
1. 初始化时间太长会影响启动速度
2. 应该使用`async_*` API异步初始化

更好的做法：
```c
static void async_init(void *data, async_cookie_t cookie)
{
	/* 耗时操作放在这里 */
}
...
async_schedule(async_init, NULL);
return 0;
```

## 本章小结

恭喜你完成了第一个内核模块！让我们回顾一下学到的东西：

1. **内核模块的本质**：动态加载的内核代码，可以通过insmod/rmmod管理
2. **module_init/module_exit**：模块的入口和出口，宏展开后创建init_module/cleanup_module符号
3. **MODULE_LICENSE**：许可证声明很重要，GPL-only符号需要GPL许可证
4. **printk**：内核的printf，需要日志级别，推荐使用pr_*系列
5. **Makefile**：使用kbuild系统，obj-m指定要编译的模块
6. **编译和运行**：make编译，insmod加载，rmmod卸载，dmesg看日志

下一章，我们将学习字符设备驱动，那时你就能创建/dev下的设备节点，和用户空间程序真正交互了。

---

**延伸阅读**

- [Linux Kernel Module Programming Guide](https://sysprog21.github.io/lkmpg/) - 经典的内核模块编程指南
- Documentation/kbuild/modules.rst - kbuild模块构建文档
- include/linux/module.h - 模块相关定义
- include/linux/init.h - 初始化相关宏
