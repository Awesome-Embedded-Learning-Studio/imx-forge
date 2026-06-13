---
title: 模块编译与加载
---

# 内核模块编译与加载详解：从 Makefile 到 insmod 的完整旅程

## 为什么要写这一章

上一章我们已经写了最简单的内核模块，那为什么还要专门写一章来讲编译和加载呢？

老实说，我在刚开始学驱动开发的时候，在这里踩过不少坑。比如：为什么 `insmod` 的时候提示 "Invalid module format"？为什么 `modprobe` 能用但 `insmod` 不行？Makefile 里的 `obj-m` 到底是什么意思？`-C $(KDIR) M=$(PWD)` 这一长串是在干啥？

更糟糕的是，很多教程只告诉你"照着这样做就行了"，却不解释为什么。这样确实能跑起来，但一旦遇到问题就傻眼了。交叉编译环境、内核版本不匹配、模块依赖……这些都是绕不开的坎儿。

所以这一章，我们来把内核模块的编译和加载机制讲透。我们会从内核源码的角度，看看模块是如何被加载进内核的，各个命令背后的系统调用是什么，以及出了问题该怎么排查。

## 一、编译流程详解：从源码到 .ko 文件

### 1.1 内核构建系统（kbuild）简介

Linux 内核使用自己的一套构建系统，叫 kbuild。它和普通项目的 Makefile 不太一样，原因很简单：内核代码的编译规则太复杂了。

kbuild 的核心思想是：**你告诉它要编译哪些文件，它自己决定怎么编译**。这意味着你不需要手写复杂的编译规则，只需要声明模块名称和源文件列表。

内核文档对 kbuild 的说明在：
- `Documentation/kbuild/modules.rst` —— 外部模块构建指南
- `Documentation/kbuild/makefiles.rst` —— Makefile 语法

### 1.2 Makefile 核变量解析

让我们来看一个典型的模块 Makefile：

```makefile
# 模块对象文件声明
obj-m += hello.o

# 内核源码目录
KDIR := /home/charliechen/linux-imx

# 内核输出目录（如果使用 O= 输出）
MODDIR := /home/charliechen/linux-imx-build

# 交叉编译工具链前缀
CROSS_COMPILE := arm-none-linux-gnueabihf-
ARCH := arm

# 当前目录
PWD := $(shell pwd)

# 默认目标
all:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(MODDIR) M=$(PWD) modules

# 清理目标
clean:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(MODDIR) M=$(PWD) clean
```

#### obj-m 是什么？

`obj-m` 中的 `m` 表示 **module**（模块）。这是一个 kbuild 特有的变量，告诉构建系统："把这个目标文件编译成可加载模块"。

kbuild 支持类似的其他变量：
- `obj-y`：编入内核（built-in），静态链接到 vmlinux
- `obj-m`：编译成模块（.ko 文件）
- `obj-`：不编译

#### $(MAKE) -C $(KDIR) M=$(PWD) 是什么意思？

这条命令分解如下：

| 部分 | 含义 |
|------|------|
| `$(MAKE)` | 调用 make 程序 |
| `-C $(KDIR)` | 先切换到内核源码目录 |
| `M=$(PWD)` | 然后回到当前目录编译模块 |
| `modules` | kbuild 的目标，表示编译模块 |

这里的逻辑是：kbuild 的核心规则定义在内核源码目录里，所以需要先 `-C` 切换过去。然后通过 `M=` 参数告诉它："嘿，我要编译外部模块，源文件在这个目录"。

> **内核源码参考**：这个逻辑在内核源码的 `scripts/Makefile.modpost` 和顶层 Makefile 中实现。

#### ARCH 和 CROSS_COMPILE

交叉编译时必须指定这两个变量：

- `ARCH=arm`：告诉 kbuild 目标架构是 ARM
- `CROSS_COMPILE=arm-none-linux-gnueabihf-`：指定交叉编译工具链前缀

kbuild 会自动拼接这些前缀，比如调用 `$(CROSS_COMPILE)gcc` 而不是 `gcc`。

#### O=$(MODDIR) 是什么？

这是内核的**输出目录**。内核源码和编译产物可以分离，`O=` 指定编译产物存放位置。

如果你编译内核时用了 `make O=/path/to/build`，那么编译模块时也必须用相同的 `O=` 参数。原因很简单：模块编译需要访问内核的配置信息（.config）和生成的头文件。

### 1.3 多源文件模块

如果模块由多个源文件组成，需要这样写：

```makefile
# 模块名称是 mydriver，由三个源文件组成
obj-m += mydriver.o
mydriver-y := main.o ioctl.o hw.o

# 或者用 +=
mydriver-y := main.o
mydriver-y += ioctl.o
mydriver-y += hw.o
```

这里有个容易混淆的地方：
- `mydriver.o` 是最终要生成的目标文件，会链接成 `mydriver.ko`
- `mydriver-y` 列出的是组成 `mydriver.o` 的各个源文件对应的目标文件

kbuild 会：
1. 编译 `main.c` → `main.o`
2. 编译 `ioctl.c` → `ioctl.o`
3. 编译 `hw.c` → `hw.o`
4. 链接 `main.o + ioctl.o + hw.o` → `mydriver.o`
5. 生成 `mydriver.ko` 模块文件

### 1.4 完整编译流程

当你运行 `make` 后，kbuild 会执行以下步骤：

```
1. 读取模块目录的 Makefile/Kbuild
2. 进入内核源码目录，加载 kbuild 规则
3. 根据 M= 回到模块目录
4. 编译 .c 文件为 .o 文件
5. 生成 .mod.o 文件（包含模块元数据）
6. 运行 modpost 工具：
   - 解析模块的符号依赖
   - 生成 Module.symvers
   - 检查版本魔术（vermagic）
7. 链接生成 .ko 文件
8. （可选）生成 BTF 信息用于调试
```

> **内核源码参考**：modpost 工具的源码在 `scripts/mod/modpost.c`。

## 二、模块加载机制：insmod 做了什么

### 2.1 系统调用链分析

当我们执行 `insmod hello.ko` 时，实际上是调用了 `init_module` 系统调用。这个系统调用的定义在内核源码中：

```c
// 文件：kernel/module/main.c
SYSCALL_DEFINE3(init_module, void __user *, umod,
		unsigned long, len, const char __user *, uargs)
{
	int err;
	struct load_info info = { };

	err = may_init_module();
	if (err)
		return err;

	pr_debug("init_module: umod=%p, len=%lu, uargs=%p\n",
	       umod, len, uargs);

	err = copy_module_from_user(umod, len, &info);
	if (err) {
		mod_stat_inc(&failed_kreads);
		mod_stat_add_long(len, &invalid_kread_bytes);
		return err;
	}

	return load_module(&info, uargs, 0);
}
```

系统调用号定义在 `arch/arm/include/asm/unistd.h`（ARM 架构）或 `arch/arm64/include/asm/unistd.h`（ARM64）。

> **内核文档**：`Documentation/userspace-api/ioctl/ioctl-number.rst` 提供了系统调用号的参考。

### 2.2 load_module 流程

`load_module()` 函数是模块加载的核心，它执行以下步骤：

```c
// 简化后的流程（位于 kernel/module/main.c）
static int load_module(struct load_info *info, const char __user *uargs,
		       int flags)
{
	// 1. 检查模块签名（如果启用）
	err = module_sig_check(info, flags);
	if (err)
		return err;

	// 2. 解析 ELF 格式
	err = elf_validity_check(info);
	if (err)
		return err;

	// 3. 检查版本魔术（vermagic）
	err = check_modinfo(info, flags);
	if (err)
		return err;

	// 4. 分配内存并复制模块代码
	err = layout_and_allocate(info, flags);
	if (err)
		return err;

	// 5. 解析符号依赖
	err = resolve_symbol_wait(mod, info);
	if (err)
		goto free_mod;

	// 6. 完成模块初始化
	err = complete_formation(mod, info);
	if (err)
		goto free_mod;

	// 7. 调用模块的 init 函数
	err = do_init_module(mod);
	if (err)
		goto free_mod;

	return 0;
}
```

每个步骤都有可能失败，对应的错误信息会通过 `dmesg` 输出。

## 三、版本魔术（Version Magic）详解

### 3.1 什么是版本魔术

版本魔术是一个字符串，用于确保模块和内核的兼容性。它包含：
- 内核版本号
- SMP 配置
- 抢占配置
- 模块卸载支持
- 其他内核配置选项

版本魔术的定义在 `include/linux/vermagic.h`：

```c
// 文件：include/linux/vermagic.h
#define VERMAGIC_STRING 						\
	UTS_RELEASE " "							\
	MODULE_VERMAGIC_SMP MODULE_VERMAGIC_PREEMPT 			\
	MODULE_VERMAGIC_MODULE_UNLOAD MODULE_VERMAGIC_MODVERSIONS	\
	MODULE_ARCH_VERMAGIC						\
	MODULE_RANDSTRUCT
```

展开后类似这样：
```
6.12.49 SMP PREEMPT mod_unload modversions ARMv7
```

### 3.2 版本魔术检查

内核加载模块时会检查版本魔术是否匹配。相关代码在 `kernel/module/version.c`：

```c
// 文件：kernel/module/version.c
int same_magic(const char *amagic, const char *bmagic,
	       bool has_crcs)
{
	if (has_crcs) {
		amagic += strcspn(amagic, " ");
		bmagic += strcspn(bmagic, " ");
	}
	return strcmp(amagic, bmagic) == 0;
}
```

如果启用了 `CONFIG_MODVERSIONS`，内核版本号不匹配也可以通过 CRC 校验来弥补。

### 3.3 常见版本不匹配错误

如果你看到这样的错误：

```
hello: version magic '6.8.0-48-generic SMP mod_unload ' should be '6.12.49 SMP preempt mod_unload modversions ARMv7'
```

这意味着：
1. 模块是用 6.8.0 内核编译的
2. 但运行中的内核是 6.12.49
3. 而且配置差异（preempt、modversions）

**解决方法**：使用目标板对应的内核源码重新编译模块。

### 3.4 查看模块的版本魔术

使用 `modinfo` 命令：

```bash
modinfo hello.ko
```

输出中的 `vermagic` 字段显示版本魔术：

```
vermagic:       6.12.49 SMP preempt mod_unload modversions ARMv7
```

## 四、模块命令详解

### 4.1 insmod：简单直接

`insmod` 是最基础的加载命令，它直接调用 `init_module` 系统调用：

```bash
insmod hello.ko
insmod hello.ko count=5 name="World"
```

特点：
- 不处理依赖，需要手动加载依赖模块
- 需要指定完整的模块文件名
- 传递参数时直接加在命令行

> **内核源码参考**：`insmod` 命令的实现通常在 kmod 工具包中，不属于内核源码。

### 4.2 rmmod：卸载模块

```bash
rmmod hello
```

`rmmod` 调用 `delete_module` 系统调用：

```c
// 文件：kernel/module/main.c
SYSCALL_DEFINE2(delete_module, const char __user *, name_user,
		unsigned int, flags)
{
	struct module *mod;
	char name[MODULE_NAME_LEN];
	// ... 检查权限、查找模块、调用模块的 exit 函数 ...
	if (mod->exit != NULL)
		mod->exit();
	// ... 释放资源 ...
}
```

### 4.3 lsmod：列出已加载模块

```bash
lsmod
```

输出示例：

```
Module                  Size  Used by
hello                   16384  0
provider                20480  1 consumer
```

数据来源：`/proc/modules`，这是内核模块子系统提供的虚拟文件。

### 4.4 modinfo：查看模块信息

```bash
modinfo hello.ko          # 未加载的模块
modinfo hello             # 已加载的模块
```

输出包括：
- `filename`：模块文件路径
- `version`：模块版本
- `description`：模块描述
- `author`：作者
- `license`：许可证
- `srcversion`：源代码版本（CRC）
- `depends`：依赖的模块
- `vermagic`：版本魔术
- `parm`：模块参数

### 4.5 modprobe：智能加载/卸载

`modprobe` 是更智能的工具，它会：
- 自动处理依赖关系
- 从 `/lib/modules/$(uname -r)/` 查找模块
- 支持 `/etc/modprobe.d/` 配置

```bash
modprobe hello                    # 自动加载依赖
modprobe -r hello                 # 卸载（包括不需要的依赖）
modprobe hello count=5            # 传递参数
```

#### modprobe.d 配置

`/etc/modprobe.d/` 目录下的配置文件可以控制模块行为：

```bash
# /etc/modprobe.d/blacklist.conf
# 禁用某个模块
blacklist unwanted_module

# /etc/modprobe.d/options.conf
# 设置模块参数
options hello count=10 verbose=1

# /etc/modprobe.d/alias.conf
# 创建模块别名
alias my-hello hello
```

> **内核文档**：`Documentation/admin-guide/kernel-parameters.rst` 和 `man modprobe.d`

### 4.6 depmod：生成模块依赖

```bash
depmod -a    # 生成所有模块的依赖信息
depmod -n    # 只显示，不实际写入
```

`depmod` 会读取 `/lib/modules/$(uname -r)/` 下的所有模块，分析它们的符号依赖，生成：
- `modules.dep`：依赖关系
- `modules.dep.bin`：二进制格式的依赖
- `modules.alias`：别名映射
- `modules.symbols`：符号映射

## 五、模块签名

### 5.1 为什么需要签名

在生产环境中，你可能希望只加载经过验证的模块，防止恶意代码进入内核空间。模块签名提供了这种安全保障。

### 5.2 签名检查流程

内核源码中的签名检查在 `kernel/module/signing.c`：

```c
// 文件：kernel/module/signing.c
int module_sig_check(struct load_info *info, int flags)
{
	int err = -ENODATA;
	const unsigned long markerlen = sizeof(MODULE_SIG_STRING) - 1;
	const void *mod = info->hdr;

	// ... 检查签名标记 ...
	if (memcmp(mod + info->len - markerlen, MODULE_SIG_STRING, markerlen) == 0) {
		info->len -= markerlen;
		err = mod_verify_sig(mod, info);
		if (!err) {
			info->sig_ok = true;
			return 0;
		}
	}
	// ...
}
```

### 5.3 配置模块签名

内核配置选项：
- `CONFIG_MODULE_SIG`：启用模块签名
- `CONFIG_MODULE_SIG_FORCE`：强制要求签名
- `CONFIG_MODULE_SIG_ALL`：自动签名编译的模块

> **内核文档**：`Documentation/admin-guide/module-signing.rst`

## 六、交叉编译实战：i.MX6ULL 模块编译

### 6.1 准备工作

确保你有：
1. ARM 交叉编译工具链
2. 已配置的内核源码（至少运行过 `make modules_prepare`）

```bash
# 检查工具链
arm-none-linux-gnueabihf-gcc --version

# 准备内核源码（如果还没做）
cd ~/linux-imx
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx_v6ull_defconfig
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
```

### 6.2 完整示例代码

创建 `hello_imx.c`：

```c
// SPDX-License-Identifier: GPL-2.0
/*
 * hello_imx.c - 面向 i.MX6ULL 的内核模块示例
 *
 * 这个模块演示了：
 * 1. 基本的模块加载/卸载
 * 2. 使用 pr_info 打印日志
 * 3. 模块参数
 * 4. 与 ARM Cortex-A7 相关的信息
 */

#include <linux/init.h>       // __init, __exit 宏
#include <linux/module.h>     // module_init, module_exit
#include <linux/printk.h>     // pr_info, pr_err
#include <linux/moduleparam.h> // module_param

/*
 * 模块参数定义
 * 这些参数可以在加载时通过命令行传递
 */
static int count = 1;
module_param(count, int, 0644);
MODULE_PARM_DESC(count, "Number of times to print hello");

static bool verbose = false;
module_param(verbose, bool, 0644);
MODULE_PARM_DESC(verbose, "Enable verbose output");

/*
 * hello_init - 模块初始化函数
 *
 * 这个函数在模块加载时执行，相当于用户空间程序的 main()
 * __init 宏告诉内核这段代码可以丢弃（初始化后不再需要）
 *
 * 返回值：
 *   0 - 成功
 *   负值 - 失败（标准 errno 值）
 */
static int __init hello_init(void)
{
	int i;

	pr_info("=== Hello i.MX6ULL! ===\n");
	pr_info("Module: %s\n", KBUILD_MODNAME);
	pr_info("Kernel: " UTS_RELEASE "\n");
	pr_info("Architecture: ARM\n");
	pr_info("Processor: Cortex-A7\n");

	if (verbose) {
		pr_info("Parameters: count=%d, verbose=%d\n", count, verbose);
	}

	/* 打印指定次数的欢迎信息 */
	for (i = 0; i < count; i++) {
		pr_info("[%d] Hello from i.MX6ULL kernel module!\n", i + 1);
	}

	pr_info("Module loaded successfully\n");

	return 0;  // 返回 0 表示成功
}

/*
 * hello_exit - 模块清理函数
 *
 * 这个函数在模块卸载时执行
 * __exit 宏告诉内核这段代码只在模块卸载时使用
 */
static void __exit hello_exit(void)
{
	pr_info("=== Goodbye i.MX6ULL! ===\n");
	pr_info("Module unloaded successfully\n");
}

/*
 * 注册模块的入口和出口点
 *
 * module_init() 注册初始化函数
 * module_exit() 注册清理函数
 *
 * 对于静态编译的代码：
 *   - module_init() 注册的函数在内核启动时调用
 *   - module_exit() 不起作用
 *
 * 对于模块化编译的代码：
 *   - module_init() 注册的函数在 insmod/modprobe 时调用
 *   - module_exit() 注册的函数在 rmmod 时调用
 */
module_init(hello_init);
module_exit(hello_exit);

/*
 * 模块元数据
 * 这些信息可以通过 modinfo 命令查看
 */

MODULE_LICENSE("GPL");
/*
 * 许可证说明：
 * "GPL" 表示代码使用 GPL 许可证
 * 使用非 GPL 许可证会导致：
 *   1. 内核被标记为 "tainted"（污染）
 *   2. 无法访问 GPL-only 导出的符号
 *   3. 社区可能不支持 bug 报告
 *
 * 支持的许可证：
 *   "GPL", "GPL v2", "Dual BSD/GPL", "Dual MIT/GPL", "Dual MPL/GPL"
 * 不支持的许可证：
 *   "Proprietary" 会标记内核为污染状态
 */

MODULE_AUTHOR("IMX-Forge <contact@imx-forge.example>");
MODULE_DESCRIPTION("A simple kernel module for i.MX6ULL (ARM Cortex-A7)");
MODULE_VERSION("1.0");

/*
 * 可选的模块信息
 */
MODULE_SOFTDEP("pre: some_other_module");  // 软依赖
```

### 6.3 对应的 Makefile

```makefile
# SPDX-License-Identifier: GPL-2.0
# Makefile for hello_imx kernel module

# 模块名称
obj-m := hello_imx.o

# 交叉编译设置
ARCH ?= arm
CROSS_COMPILE ?= arm-none-linux-gnueabihf-

# 内核源码目录（根据你的实际路径修改）
KDIR ?= $(HOME)/linux-imx

# 内核输出目录（如果使用了 O= 分离编译）
# 如果没有分离编译，可以留空或注释掉
MODDIR ?= $(HOME)/linux-imx-build

# 当前目录
PWD := $(shell pwd)

# 默认目标：编译模块
all:
	$(MAKE) -C $(KDIR) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(MODDIR) \
		M=$(PWD) \
		modules

# 清理编译产物
clean:
	$(MAKE) -C $(KDIR) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(MODDIR) \
		M=$(PWD) \
		clean

# 安装模块到目标目录（可选）
install:
	$(MAKE) -C $(KDIR) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(MODDIR) \
		M=$(PWD) \
		modules_install

# 帮助信息
help:
	@echo "Makefile for hello_imx kernel module"
	@echo ""
	@echo "Usage:"
	@echo "  make           - 编译模块"
	@echo "  make clean     - 清理编译产物"
	@echo "  make install   - 安装模块"
	@echo ""
	@echo "Variables:"
	@echo "  ARCH           - 目标架构 (default: $(ARCH))"
	@echo "  CROSS_COMPILE  - 交叉编译工具链前缀 (default: $(CROSS_COMPILE))"
	@echo "  KDIR           - 内核源码目录 (default: $(KDIR))"
	@echo "  MODDIR         - 内核输出目录 (default: $(MODDIR))"

.PHONY: all clean install help
```

### 6.4 编译和验证

```bash
# 编译
make

# 检查生成的文件架构
file hello_imx.ko

# 查看模块信息
modinfo hello_imx.ko
```

预期输出（file 命令）：
```
hello_imx.ko: ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV)
```

## 七、常见错误与调试

### 7.1 "Invalid module format"

**错误现象**：
```
insmod: ERROR: could not insert module hello_imx.ko: Invalid module format
```

**原因**：
1. 模块和内核版本不匹配
2. 架构不匹配（比如在 x86 上编译 ARM 模块）
3. 编译配置不一致

**调试方法**：
```bash
# 查看模块版本
modinfo hello_imx.ko | grep vermagic

# 查看运行中的内核版本
uname -r

# 查看内核日志
dmesg | tail -20
```

### 7.2 "Unknown symbol"

**错误现象**：
```
hello_imx: Unknown symbol some_function (err 0)
```

**原因**：
模块依赖的符号不存在，可能是：
1. 依赖的模块没有加载
2. 内核配置问题，该符号没编入内核

**调试方法**：
```bash
# 查看缺失的符号
cat /proc/kallsyms | grep some_function

# 查看模块依赖
modinfo hello_imx.ko | grep depends
```

### 7.3 "Operation not permitted"

**原因**：
权限不足，需要 root 权限。

**解决**：
```bash
sudo insmod hello_imx.ko
```

### 7.4 "Device or resource busy"

**错误现象**：
```
rmmod: ERROR: Module hello_imx is in use
```

**原因**：
模块正在被使用（引用计数 > 0）。

**调试方法**：
```bash
# 查看引用计数
lsmod | grep hello_imx

# 查看谁在使用
cat /sys/module/hello_imx/refcnt
```

## 八、练习题

### 练习题 1：多文件模块

创建一个由 3 个源文件组成的模块：
- `core.c`：核心功能
- `utils.c`：工具函数
- `data.c`：数据管理

要求：
1. 编写正确的 Makefile
2. 在 `utils.c` 中导出一个函数供 `core.c` 使用
3. 在 `data.c` 中导出一个变量供 `core.c` 使用

**参考答案**：

```makefile
# Makefile
obj-m := multimod.o
multimod-y := core.o utils.o data.o

KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

```c
/* utils.c */
#include <linux/module.h>
#include <linux/printk.h>

int utils_add(int a, int b)
{
    pr_info("utils_add: %d + %d = %d\n", a, b, a + b);
    return a + b;
}
EXPORT_SYMBOL(utils_add);

static int __init utils_init(void)
{
    pr_info("utils initialized\n");
    return 0;
}

static void __exit utils_exit(void)
{
    pr_info("utils exited\n");
}

module_init(utils_init);
module_exit(utils_exit);

MODULE_LICENSE("GPL");
```

```c
/* data.c */
#include <linux/module.h>
#include <linux/printk.h>

int data_counter = 0;
EXPORT_SYMBOL(data_counter);

static int __init data_init(void)
{
    pr_info("data initialized\n");
    return 0;
}

static void __exit data_exit(void)
{
    pr_info("data exited\n");
}

module_init(data_init);
module_exit(data_exit);

MODULE_LICENSE("GPL");
```

```c
/* core.c */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/printk.h>

extern int utils_add(int a, int b);
extern int data_counter;

static int __init core_init(void)
{
    pr_info("core: data_counter = %d\n", data_counter);
    pr_info("core: utils_add(10, 20) = %d\n", utils_add(10, 20));
    return 0;
}

static void __exit core_exit(void)
{
    pr_info("core exited\n");
}

module_init(core_init);
module_exit(core_exit);

MODULE_LICENSE("GPL");
```

### 练习题 2：模块依赖

创建两个模块：
- `provider.ko`：提供一个函数 `provider_get_value()`
- `consumer.ko`：调用 `provider_get_value()`

要求：
1. 正确使用 `EXPORT_SYMBOL`
2. 先加载 `provider`，再加载 `consumer`
3. 尝试反向加载，观察错误

### 练习题 3：modprobe.d 配置

1. 创建一个模块，接受参数 `debug_level`
2. 在 `/etc/modprobe.d/` 创建配置文件，设置默认 `debug_level=3`
3. 创建别名 `mymod` 指向你的模块
4. 验证 `modprobe mymod` 是否正确应用配置

### 练习题 4：错误处理

修改示例代码，让 `init` 函数可能失败：
1. 当 `count > 10` 时返回错误
2. 观察错误时模块的状态
3. 查看 `dmesg` 输出

```c
static int __init hello_init(void)
{
    if (count > 10) {
        pr_err("count too large (max 10)\n");
        return -EINVAL;
    }
    // ...
}
```

### 练习题 5：实战代码查看

1. 查看内核源码中 `struct module` 的定义（`include/linux/module.h`），列出至少 5 个字段
2. 查看 `kernel/module/main.c` 中的 `SYSCALL_DEFINE3(init_module, ...)`
3. 查看 `include/linux/vermagic.h` 中的 `VERMAGIC_STRING` 定义
4. 查看 `scripts/mod/modpost.c`，了解 modpost 工具的作用

## 九、内核源码实战查看

### 查看 module 结构体

```bash
# 查看完整定义
grep -n "struct module" third_party/linux-imx/include/linux/module.h

# 查看模块状态枚举
grep -A 10 "enum module_state" third_party/linux-imx/include/linux/module.h
```

### 查看模块加载系统调用

```bash
# 查看 init_module 系统调用
grep -A 20 "SYSCALL_DEFINE3(init_module" third_party/linux-imx/kernel/module/main.c

# 查看 delete_module 系统调用
grep -A 30 "SYSCALL_DEFINE2(delete_module" third_party/linux-imx/kernel/module/main.c
```

### 查看版本魔术相关代码

```bash
# 查看版本魔术定义
cat third_party/linux-imx/include/linux/vermagic.h

# 查看版本检查函数
cat third_party/linux-imx/kernel/module/version.c
```

### 查看模块签名代码

```bash
# 查看签名检查
cat third_party/linux-imx/kernel/module/signing.c
```

## 十、总结

这一章我们深入了解了内核模块的编译和加载机制：

1. **编译流程**：kbuild 系统如何将源码编译成 .ko 文件
2. **Makefile 语法**：obj-m、$(MAKE) -C、M= 等关键变量
3. **加载机制**：insmod 调用 init_module 系统调用的完整流程
4. **版本魔术**：如何确保模块与内核的兼容性
5. **模块命令**：insmod、rmmod、lsmod、modinfo、modprobe、depmod 的区别和用法
6. **交叉编译**：为 i.MX6ULL 编译模块的完整步骤
7. **常见错误**：如何调试和解决模块加载问题

理解这些内容后，你就能自信地编写、编译、加载和调试内核模块了。下一章，我们将深入设备驱动的基础知识，看看如何编写真正的设备驱动程序。

---

**参考资料**

- Linux 内核文档：`Documentation/kbuild/modules.rst`
- Linux 内核文档：`Documentation/admin-guide/module-signing.rst`
- man 手册：`man modules`、`man modprobe`、`man modprobe.d`
- 内核源码：`kernel/module/main.c`、`include/linux/module.h`、`include/linux/vermagic.h`
