---
title: 内核模块
---

# 内核模块详解：从 Hello World 到设备驱动

## 为什么要写这一章

前面我们花了三章的篇幅，把 Linux 内核从哪里来、怎么编译、设备树是什么都讲清楚了。你可能觉得好了，现在我对内核有认识了，可以开始写驱动了吧？

但这里有一个坎儿：你写的代码怎么放进内核里？

传统的做法是把代码直接编进内核镜像。这种方式有几个问题：一是每次修改都要重新编译整个内核，耗时漫长；二是代码会一直占用内存，即使用不到；三是调试不方便，出错可能导致整个系统起不来。

有没有一种方式，可以让代码在需要的时候加载，不用的时候卸载，修改后也不需要重编内核？答案就是——内核模块。

说实话，我刚接触内核模块的时候也有点懵。明明就是 C 代码，为什么不能直接编译成普通程序运行？为什么必须用特殊的宏？为什么 insmod 的时候提示 "unknown symbol"？这些坑我都踩过，而且不止一次。

所以这一章，我们手把手地从零开始写一个内核模块，搞清楚它是什么、怎么编译、怎么加载卸载、怎么传参数、怎么处理依赖关系。当你把这些都弄明白了，后面的设备驱动开发就是顺水推舟的事情。

## 内核模块是什么，为什么需要它

### 模块 vs 静态编译

Linux 内核有两种代码组织方式：静态编译和模块化编译。

**静态编译**就是把代码直接编进内核镜像（vmlinux/zImage）。系统启动时，这些代码就驻留在内存里了。比如你查看一下 `/proc/kallsyms`，里面列出的就是内核里所有符号（函数和变量）的地址。

```bash
cat /proc/kallsyms | head -20
```

输出类似这样：

```
00000000 T startup_64
00000000 T _text
ffffffff81000000 T _stext
...
```

这些符号大部分是静态编入内核的代码。

**模块化编译**则是把代码编译成独立的 .ko（Kernel Object）文件，运行时通过 `insmod` 或 `modprobe` 加载到内核空间。模块加载后，它的符号会被注册到内核的符号表里，就像它本来就在内核里一样。

### 模块的好处

模块化设计有几个明显的好处：

**动态加载**。用不到的功能可以不加载，节省内存。比如你开发板上可能没有 SCSI 设备，那 SCSI 驱动模块就不需要加载。这在资源受限的嵌入式系统上很重要。

**快速迭代**。开发驱动时，每次修改代码只需要重新编译模块，然后 `rmmod` 旧模块、`insmod` 新模块。这比每次都重编内核快太多了。我记得我第一次碰驱动，大概就几秒钟吧，LED的驱动更简单，我还没反应过来编完了。内核可就不好说了（笑）

**安全隔离**。模块有 BUG 导致内核崩溃的概率比静态代码低，因为模块可以选择性加载，出问题时更容易定位。

**闭源兼容**。有些厂商的驱动是闭源的，必须以模块形式提供（虽然这不是内核社区鼓励的做法，嗯）。

### 模块的局限性

当然，模块也不是万能的：

**启动前依赖**。如果某个设备是系统启动必需的（比如根文件系统所在的存储设备），它的驱动就不能是模块，必须静态编入内核。

**性能开销**。模块加载/卸载有开销，虽然不大，但对性能敏感的场景可能需要注意。

**符号依赖**。模块只能调用内核导出的符号，不能直接访问内核内部的静态函数。

## 手写一个 Hello World 模块

好了，理论讲够了。我们来写一个最简单的内核模块。

### 创建工作目录

首先，在合适的地方创建一个目录来存放模块代码：

```bash
mkdir -p ~/kernel-module-tutorial
cd ~/kernel-module-tutorial
```

### 编写模块源码

创建 `hello.c` 文件：

```c
#include <linux/init.h>   // __init __exit 宏定义
#include <linux/module.h> // module_init module_exit 等核心宏
#include <linux/printk.h> // pr_info printk

// 模块加载时执行的函数
static int __init hello_init(void)
{
    // 使用 pr_info 而不是 printk，更简洁
    pr_info("Hello, kernel module!\n");
    return 0;
}

// 模块卸载时执行的函数
static void __exit hello_exit(void)
{
    pr_info("Goodbye, kernel module!\n");
}

// 注册初始化和清理函数
module_init(hello_init);
module_exit(hello_exit);

// 模块元信息
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name <your.email@example.com>");
MODULE_DESCRIPTION("A simple hello world kernel module");
MODULE_VERSION("1.0");
```

> **踩坑提醒**：一定要包含 `MODULE_LICENSE("GPL")`！否则内核会认为你的模块是"被污染的"（tainted），某些功能会受限。而且使用 GPL 以外的许可证，你不能访问某些只有 GPL 模块才能用的内核符号。

### 编写 Makefile

内核模块的编译和普通程序不同，它需要使用内核的构建系统。创建一个 `Makefile`：

```makefile
# 模块名称
obj-m += hello.o

# 获取当前运行的内核构建目录
KDIR := /lib/modules/$(shell uname -r)/build

# 当前目录
PWD := $(shell pwd)

# 默认目标：构建模块
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

# 清理编译产物
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

> **注意**：Makefile 里的缩进必须是 **Tab**，不能是空格！这是 Makefile 的语法要求，用空格会报错 "missing separator"。

### 编译模块

现在可以编译了：

```bash
make
```

你应该能看到类似这样的输出：

```
make -C /lib/modules/6.8.0-48-generic/build M=/home/charliechen/kernel-module-tutorial modules
make[1]: Entering directory '/usr/src/linux-headers-6.8.0-48-generic'
  CC [M]  /home/charliechen/kernel-module-tutorial/hello.o
  MODPOST /home/charliechen/kernel-module-tutorial/Module.symvers
  CC [M]  /home/charliechen/kernel-module-tutorial/hello.mod.o
  LD [M]  /home/charliechen/kernel-module-tutorial/hello.ko
  BTF [M] /home/charliechen/kernel-module-tutorial/hello.ko
make[1]: Leaving directory '/usr/src/linux-headers-6.8.0-48-generic'
```

编译成功后，当前目录下会出现几个文件：

- `hello.o`：目标文件
- `hello.ko`：内核模块文件（这就是我们需要的）
- `hello.mod.o`、`hello.mod.c`：模块版本信息相关
- `Module.symvers`：符号导出文件
- `.hello.ko.cmd` 等隐藏文件：编译过程记录

### 加载和卸载模块

现在来加载模块：

```bash
sudo insmod hello.ko
```

如果一切正常，命令没有任何输出。那怎么知道模块加载成功了？查看内核日志：

```bash
sudo dmesg | tail -5
```

你应该能看到：

```
[ 1234.567890] Hello, kernel module!
```

你也可以用 `lsmod` 命令查看已加载的模块：

```bash
lsmod | grep hello
```

输出：

```
hello                  16384  0
```

这表示 `hello` 模块已加载，大小是 16384 字节（16KB），被引用次数是 0。

现在来卸载模块：

```bash
sudo rmmod hello
```

再查看日志：

```bash
sudo dmesg | tail -5
```

你应该能看到：

```
[ 1235.678901] Goodbye, kernel module!
```

恭喜！你已经成功完成了第一个内核模块的编写、编译、加载和卸载。

## 交叉编译：为目标板编译模块

刚才的编译是针对你当前运行的开发机的。但我们的目标是 i.MX6ULL 开发板，它用的是 ARM 架构，需要交叉编译。

### 准备交叉编译环境

首先确保你有 ARM 交叉编译工具链：

```bash
arm-none-linux-gnueabihf-gcc --version
```

应该能输出版本信息。

### 准备内核源码

交叉编译模块时，需要访问目标架构的内核源码或头文件。你不需要完整编译一遍内核，但至少要有内核源码树和配置好的 `.config`。

假设你内核源码在 `~/linux-imx`，输出目录在 `~/linux-imx-build`：

```bash
# 确保内核已经配置过
cd ~/linux-imx
make O=~/linux-imx-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx_aes_defconfig
```

### 修改 Makefile 用于交叉编译

回到模块目录，修改 `Makefile`：

```makefile
obj-m += hello.o

# 交叉编译相关变量
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码目录（根据你的实际路径修改）
KDIR := ~/linux-imx

# 输出目录
MODDIR := ~/linux-imx-build

# 当前目录
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) O=$(MODDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) O=$(MODDIR) M=$(PWD) clean
```

重新编译：

```bash
make clean && make
```

这次生成的 `hello.ko` 就是 ARM 架构的模块了。你可以验证一下：

```bash
file hello.ko
```

输出应该显示：

```
hello.ko: ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV) ...
```

### 在开发板上测试

把模块传到开发板（通过 TFTP、NFS 或 SD 卡），然后在开发板上加载：

```bash
insmod hello.ko
```

查看日志：

```bash
dmesg | tail
```

你应该能看到熟悉的 "Hello, kernel module!" 输出。

## 模块参数传递

硬编码的模块不太实用。更多时候，我们希望能在加载模块时传递参数，让模块行为更灵活。

### 添加模块参数

修改 `hello.c`，添加参数支持：

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/moduleparam.h> // module_param 宏

// 定义一个整型参数，默认值 0
static int count = 0;
// 参数名、类型、权限（S_IRUGO 表示所有用户可读）
module_param(count, int, S_IRUGO);
MODULE_PARM_DESC(count, "Number of times to print hello");

// 定义一个字符串参数，默认值 "world"
static char *name = "world";
module_param(name, charp, S_IRUGO);
MODULE_PARM_DESC(name, "Who to say hello to");

// 定义一个布尔型参数，默认值 false
static bool verbose = false;
module_param(verbose, bool, S_IRUGO);
MODULE_PARM_DESC(verbose, "Enable verbose output");

static int __init hello_init(void)
{
    int i;

    if (verbose) {
        pr_info("Module parameters: count=%d, name=%s, verbose=%d\n",
                count, name, verbose);
    }

    for (i = 0; i < count; i++) {
        pr_info("Hello, %s! (#%d)\n", name, i + 1);
    }

    if (count == 0) {
        pr_info("Hello, %s!\n", name);
    }

    return 0;
}

static void __exit hello_exit(void)
{
    pr_info("Goodbye, %s!\n", name);
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name <your.email@example.com>");
MODULE_DESCRIPTION("A hello world module with parameters");
MODULE_VERSION("1.0");
```

### 参数类型说明

`module_param` 宏支持这些类型：

| 类型 | C 类型 | 说明 |
|------|--------|------|
| `int` | int | 整型 |
| `short` | short | 短整型 |
| `uint` | unsigned int | 无符号整型 |
| `ushort` | unsigned short | 无符号短整型 |
| `long` | long | 长整型 |
| `ulong` | unsigned long | 无符号长整型 |
| `charp` | char * | 字符串指针 |
| `bool` | bool / int | 布尔型 |

### 权限标志

权限标志定义了谁可以通过 `/sys/module` 访问这个参数：

```c
// S_IRUGO：所有用户可读
module_param(count, int, S_IRUGO);

// S_IWUSR：只有 root 可写
module_param(count, int, S_IWUSR);

// S_IRUGO | S_IWUSR：所有用户可读，root 可写
module_param(count, int, S_IRUGO | S_IWUSR);
```

常用权限常量：

| 常量 | 值 | 含义 |
|------|-----|------|
| S_IRUSR | 0400 | 所有者可读 |
| S_IWUSR | 0200 | 所有者可写 |
| S_IRGRP | 0040 | 组用户可读 |
| S_IWGRP | 0020 | 组用户可写 |
| S_IROTH | 0004 | 其他用户可读 |
| S_IWOTH | 0002 | 其他用户可写 |
| S_IRUGO | 0444 | 所有用户可读 |
| S_IWUGO | 0222 | 所有用户可写 |

### 加载时传递参数

重新编译模块，然后加载时传递参数：

```bash
# 使用默认参数
sudo insmod hello.ko

# 指定 count
sudo insmod hello.ko count=3

# 指定 name
sudo insmod hello.ko name="Kernel"

# 同时指定多个参数
sudo insmod hello.ko count=5 name="World" verbose=1
```

查看日志：

```bash
sudo dmesg | tail -10
```

### 运行时查看和修改参数

模块加载后，可以通过 `/sys/module` 查看和修改参数：

```bash
# 查看模块参数目录
ls -la /sys/module/hello/parameters/

# 查看参数值
cat /sys/module/hello/parameters/count
cat /sys/module/hello/parameters/name
cat /sys/module/hello/parameters/verbose

# 修改参数（如果权限允许）
sudo sh -c "echo 10 > /sys/module/hello/parameters/count"
```

> **注意**：修改参数是否生效取决于模块代码如何使用参数。有些参数只在初始化时读取，后续修改不会影响行为。

## 模块依赖管理

实际开发中，模块之间往往有依赖关系。比如一个网络设备驱动模块可能依赖于通用 PHY 层模块。这时候加载顺序就很重要。

### 查看模块依赖

用 `modinfo` 命令查看模块信息：

```bash
modinfo hello.ko
```

输出类似：

```
filename:       /home/charliechen/kernel-module-tutorial/hello.ko
version:        1.0
description:    A hello world module with parameters
author:         Your Name <your.email@example.com>
license:        GPL
srcversion:     XXXXXXXXXXXXXXXXXXXX
depends:
retpoline:      Y
name:           hello
vermagic:       6.8.0-48-generic SMP mod_unload modversions aarch64
```

`depends` 字段显示了这个模块依赖的其他模块。我们的 hello 模块没有依赖，所以是空的。

### 导出符号：让模块提供 API

如果一个模块想提供函数给其他模块使用，需要导出符号。

**模块 A：导出符号**

创建 `provider.c`：

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>

// 导出一个函数
int provider_add(int a, int b)
{
    pr_info("provider_add: %d + %d = %d\n", a, b, a + b);
    return a + b;
}
EXPORT_SYMBOL(provider_add);

// 导出一个变量
int provider_counter = 0;
EXPORT_SYMBOL(provider_counter);

static int __init provider_init(void)
{
    pr_info("Provider module loaded\n");
    return 0;
}

static void __exit provider_exit(void)
{
    pr_info("Provider module unloaded\n");
}

module_init(provider_init);
module_exit(provider_exit);

MODULE_LICENSE("GPL");
```

**模块 B：使用导出的符号**

创建 `consumer.c`：

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>

// 声明外部符号
extern int provider_add(int a, int b);
extern int provider_counter;

static int __init consumer_init(void)
{
    int result;

    pr_info("Consumer module loaded\n");

    result = provider_add(10, 20);
    pr_info("Result from provider: %d\n", result);

    pr_info("Provider counter: %d\n", provider_counter);

    return 0;
}

static void __exit consumer_exit(void)
{
    pr_info("Consumer module unloaded\n");
}

module_init(consumer_init);
module_exit(consumer_exit);

MODULE_LICENSE("GPL");
```

**更新 Makefile**

```makefile
obj-m += provider.o
obj-m += consumer.o

KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

**编译和测试**

```bash
make
sudo insmod provider.ko
sudo insmod consumer.ko
sudo dmesg | tail -10
```

**加载顺序错误会怎样？**

如果你先加载 `consumer`，会报错：

```bash
sudo rmmod provider consumer  # 先卸载
sudo insmod consumer.ko
```

输出：

```
insmod: ERROR: could not insert module consumer.ko: Unknown symbol
```

查看详细错误：

```bash
sudo dmesg | tail
```

你会看到：

```
consumer: Unknown symbol provider_add (err 0)
consumer: Unknown symbol provider_counter (err 0)
```

这就是符号依赖：`consumer` 需要 `provider` 导出的符号，但 `provider` 还没加载。

### modprobe：自动处理依赖

`insmod` 不会自动处理依赖，但 `modprobe` 会。

```bash
sudo rmmod consumer provider
sudo modprobe consumer
```

`modprobe` 会自动分析依赖，先加载 `provider`，再加载 `consumer`。

卸载时也类似：

```bash
sudo modprobe -r consumer
```

`modprobe -r` 会自动卸载不再被依赖的模块（比如 `provider`）。

### 依赖信息存储

模块的依赖信息存储在 `/lib/modules/$(uname -r)/modules.dep` 文件中：

```bash
cat /lib/modules/$(uname -r)/modules.dep | grep provider
```

这个文件是在安装内核模块时由 `depmod -a` 命令生成的。你自己编译的模块不在系统目录里，所以 `modprobe` 可能找不到。解决方法是把模块 `.ko` 文件复制到 `/lib/modules/$(uname -r)/extra/`，然后运行 `sudo depmod -a`。

## 模块信息查看命令

我们总结一下常用的模块管理命令：

### lsmod：列出已加载模块

```bash
lsmod
```

输出格式：

```
Module                  Size  Used by
hello                   16384  0
provider                20480  1 consumer
consumer                16384  0
...
```

- `Module`：模块名
- `Size`：模块占用内存大小（字节）
- `Used by`：被引用次数，以及被哪些模块引用

### modinfo：查看模块信息

```bash
modinfo hello.ko          # 查看未加载的模块
modinfo hello             # 查看已加载的模块
```

### depmod：生成模块依赖

```bash
sudo depmod -a            # 重新生成所有模块的依赖信息
sudo depmod -n            # 只显示，不实际写入文件
```

### modprobe：智能加载/卸载模块

```bash
sudo modprobe hello               # 加载模块（自动处理依赖）
sudo modprobe -r hello            # 卸载模块（自动卸载不再需要的依赖）
sudo modprobe hello count=5       # 加载并传递参数
```

### insmod/rmmod：手动加载/卸载

```bash
sudo insmod hello.ko              # 加载模块（不处理依赖）
sudo insmod hello.ko count=5      # 加载并传递参数
sudo rmmod hello                  # 卸载模块
```

## 模块调试技巧

### 查看内核日志

```bash
sudo dmesg                        # 查看所有日志
sudo dmesg | tail -20             # 查看最近 20 行
sudo dmesg | grep -i hello        # 过滤包含 hello 的日志
sudo dmesg -c                     # 清空日志
```

### 实时监控日志

```bash
sudo dmesg -w                     # 持续监控新日志
# 或
sudo journalctl -kf               # 使用 systemd journal
```

### 查看模块符号

```bash
cat /proc/kallsyms | grep hello
```

### 查看模块参数

```bash
ls /sys/module/hello/parameters/
cat /sys/module/hello/parameters/count
```

### 动态调试（dynamic debug）

如果你的模块使用 `pr_debug()` 或 `dev_dbg()` 打印调试信息，可以通过 dynamic debug 动态控制：

```bash
# 启用某个模块的所有调试信息
sudo echo 'module hello +p' > /sys/kernel/debug/dynamic_debug/control

# 启用某个文件的所有调试信息
sudo echo 'file hello.c +p' > /sys/kernel/debug/dynamic_debug/control

# 启用某个函数的所有调试信息
sudo echo 'func hello_init +p' > /sys/kernel/debug/dynamic_debug/control

# 查看当前调试设置
sudo cat /sys/kernel/debug/dynamic_debug/control | grep hello
```

## 常见错误排查

### "Invalid module format"

这个错误通常表示模块和内核版本不匹配。可能是：
- 编译模块时用的内核源码和运行中的内核版本不一致
- 交叉编译时架构不匹配

解决方法：
```bash
uname -r                    # 查看当前内核版本
modinfo hello.ko            # 查看模块编译的内核版本（vermagic 字段）
```

### "Unknown symbol"

表示模块依赖的符号不存在。可能是：
- 依赖的模块没有加载
- 依赖的符号没有被导出
- 内核配置问题，该符号没有编入内核

解决方法：
```bash
# 查看缺失的符号名称
sudo dmesg | tail

# 搜索符号在哪个模块
grep -r "missing_symbol_name" /lib/modules/$(uname -r)/
```

### "Operation not permitted"

表示权限不足。确保使用 `sudo` 加载/卸载模块。

### "Device or resource busy"

表示模块正被使用（Used by > 0），无法卸载。

先查看谁在使用：
```bash
lsmod | grep module_name
```

先卸载依赖它的模块，再卸载它。

## 写在最后

到这里，你应该对内核模块有了全面的认识。从简单的 Hello World 到参数传递，从符号导出到依赖管理，这些知识是后续驱动开发的基础。

内核模块是 Linux 内核"可扩展性"设计的体现。它让内核既能保持稳定性，又能灵活地支持新硬件和新功能。对于嵌入式开发者来说，模块更是必不可少的工具——它让我们能够快速迭代代码，而不需要每次都重新编译和烧录整个内核。

下一章，我们将深入探讨设备树在内核中的使用。你会看到内核如何解析设备树、如何根据设备树信息匹配设备和驱动、如何调试设备树相关的问题。那是从"写代码"到"写驱动"的关键一步。

准备好了吗？让我们继续。
