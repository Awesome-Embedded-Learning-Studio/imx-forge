---
title: 内核编译
---

# 从0开始编译Linux内核：当你发现make时少了一个包，第17次

## 为什么要写这篇编译教程

你可能会想，Linux内核编译不是有现成的教程吗？随便一搜就是一堆。但我敢打赌，你第一次尝试的时候，至少会遇到以下问题之一：

1. 编译到一半报错，提示缺少某个头文件或工具（我当时就是我头文件呢？？？）
2. 编译完成了，但产物是x86的，板子上跑不起来（孩子们记得ARCH=arm，少一下就完蛋）
3. 想改配置，结果发现.config和defconfig的关系搞不清楚
4. 编译完了一堆文件，不知道哪个是真正要用的

我当年踩的坑比这还多。第一次编译内核，我直接用系统的gcc，结果编出来个x86_64的vmlinux，还奇怪怎么i.MX6ULL板子认不出来（一想到芯片对着X64的Instructions发懵我就想笑）。第二次好不容易用对了工具链，结果少了bc，make menuconfig直接报错。第三次装齐了依赖，编完了不知道怎么验证，直接把vmlinux往板子上拷，当然不行。

所以这篇文章的目标很明确：带你走一遍完整的内核编译流程，理解每一步在做什么、为什么这么做、可能会遇到什么坑。到了最后，你会明白这些步骤可以自动化，我会给你一个完整的build脚本——但那时候你已经理解了脚本的每一行在做什么。

## 我们的工作环境

先说明一下本文的环境，避免踩不必要的坑：

```
平台：Ubuntu 24.04 LTS
目标板：i.MX6ULL 14x14 EVK (512MB DDR)
工具链：arm-none-linux-gnueabihf-gcc
内核版本：NXP linux-imx (lf-6.12.3)（哦对了，我上机测试是6.12.49，看来打了一些patch）
```

环境不完全一样也没关系。Ubuntu 20.04/22.04 都可以，工具链只要是ARM硬浮点ABI的就行。内核版本主要影响配置选项，编译流程基本一致。

## 准备工作：那些看似无关的包为什么必须装

在我们开始编译之前，先要把依赖装齐。这一步看起来简单，但缺了任何一个包，你都会在不同阶段遇到莫名其妙的报错。

```bash
sudo apt install \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libgnutls28-dev \
    libncurses-dev \
    device-tree-compiler \
    python3
```

我来逐项解释这些包都是干什么的。

`build-essential`是基础构建工具包，包含了gcc、make、libc-dev这些编译必备的东西。没有它，你连最简单的C程序都编不过。

`bc`是命令行计算器。你可能觉得奇怪，编译内核要计算器干嘛？答案在于Kconfig配置系统。内核的配置脚本会用到bc进行数值计算，比如计算内存大小、时钟分频比。没有bc，某些配置选项计算会报错。

`bison`和`flex`是语法分析器生成工具。内核需要解析Kconfig配置文件，还需要生成某些驱动代码。这两者由flex（词法分析）和bison（语法分析）处理。你可能会在编译错误信息看到"missing bison"或"missing flex"，这就是缺这两个包的表现。

`libssl-dev`和`libgnutls28-dev`是加密库开发文件。内核支持签名验证、加密的模块加载、安全启动等功能。这些功能需要OpenSSL或GnuTLS库。虽然不是严格必需，但为了完整性，建议装上。

`libncurses-dev`是ncurses库的开发文件。ncurses是一个终端图形库，make menuconfig这种文本配置界面就是用它做的。没有它，你就没法用图形界面配置内核。

`device-tree-compiler`也就是dtc，是设备树编译器。内核需要把.dts设备树源文件编译成.dtb二进制文件。虽然内核源码里自带了一个dtc，但系统安装一个版本更稳定，而且可以用于验证编译产物。

`python3`是Python解释器。内核的某些构建脚本和工具是用Python写的，没有Python，编译可能会失败。

IMX-Forge项目的构建脚本`scripts/build_helper/build-linux.sh`会自动检查这些依赖。你运行脚本时，它会告诉你哪些包缺失，并给出安装命令。

## 理解交叉编译：为什么不能直接用gcc

现在我们来到第一个核心概念：交叉编译。很多新手在这里卡住，不明白为什么不能用系统的gcc直接编译。

问题很简单：你的开发机是x86_64架构的，而内核要跑在ARM架构的板子上。x86的CPU跑不了ARM指令，反之亦然。所以我们需要一个能运行在x86上、但生成ARM代码的编译器——这就是交叉编译器。

交叉编译器的命名规则是有规律的。以`arm-none-linux-gnueabihf-gcc`为例：

- `arm`是目标架构
- `none`表示没有厂商（非嵌入式工具链）
- `linux`是目标操作系统
- `gnueabihf`是GNU EABI硬浮点ABI

这里重点解释一下`gnueabihf`。ARM有两种浮点ABI：软浮点（gnueabi）和硬浮点（gnueabihf）。软浮点模式下，浮点运算用软件模拟，函数调用时整数和浮点参数都通过通用寄存器传递。硬浮点模式下，浮点运算用硬件FPU执行，浮点参数通过浮点寄存器传递。i.MX6ULL有硬件FPU，所以我们要用硬浮点工具链，性能更好。

获取交叉编译工具有几种方式。一种是直接从ARM官网下载预构建的工具链，另一种是用Ubuntu的包管理器安装（比如`gcc-arm-linux-gnueabihf`），还有一种是自己用crosstool-NG编译。对于初学者，推荐用前两种，省时省力。

安装好后，你可以用这个命令验证：

```bash
arm-none-linux-gnueabihf-gcc --version
```

如果输出了版本信息，说明工具链在PATH里，可以正常使用。

## 第一步：设置输出目录——为什么要分离源码和产物

开始编译前，建议先设置一个独立的输出目录。这样可以保持源码目录干净，也方便清理。

```bash
export O=/path/to/output/dir
```

然后在make时使用`O=输出目录`参数：

```bash
make O=/path/to/output/dir ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- xxx_defconfig
make O=/path/to/output/dir ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)
```

IMX-Forge项目的构建脚本使用固定的输出目录：`PROJECT_ROOT/out/linux`。这样所有的编译产物都在一个地方，管理起来很方便。

## 第二步：defconfig——配置的魔法

清理完成后，我们需要配置内核：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux imx_aes_defconfig
```

这里解释一下这三个变量的作用。`ARCH=arm`告诉内核目标架构是ARM，它会在`arch/arm/`目录下找架构相关代码。`CROSS_COMPILE=arm-none-linux-gnueabihf-`指定交叉编译器前缀。`O=out/linux`指定输出目录。

`imx_aes_defconfig`是IMX-Forge项目为i.MX6ULL定制的默认配置。

> **⚠️ 重要提示**
>
> `imx_aes_defconfig` **不是NXP官方提供的配置文件**，而是IMX-Forge项目自定义的配置。
> 这个配置文件需要通过应用项目补丁后才会生成到linux-imx仓库中。
>
> **使用方式：**
>
> 1. **使用IMX-Forge构建系统（推荐）**
>    ```bash
>    ./scripts/build_helper/build-linux.sh  # 自动应用补丁并构建
>    ```
>
> 2. **手动操作：需要先应用补丁**
>    ```bash
>    cd third_party/linux-imx
>    git apply ../../patches/linux-imx/linux-imx-latest.patch
>    make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=../../out/linux imx_aes_defconfig
>    ```
>
> 3. **NXP官方仓库：使用官方配置**
>    ```bash
>    make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux imx_v7_defconfig
>    ```

IMX-Forge项目应用补丁后，defconfig文件位于`arch/arm/configs/`目录下：

```bash
arch/arm/configs/
├── imx_aes_defconfig          # IMX-Forge 自定义配置（应用补丁后）
├── imx_v6_v7_defconfig        # NXP 官方：i.MX 6/7系列通用配置
├── imx_v7_defconfig           # NXP 官方：i.MX 7系列配置（推荐用于i.MX6ULL）
└── ...
```

defconfig不是.config的完整复制，它只存储与默认值不同的配置选项。举个例子，如果某个配置项默认是n，板子需要它设为y，defconfig里就只会记录`CONFIG_XXX=y`。

当你运行`make xxx_defconfig`时，内核会做这几件事：

1. 加载指定的defconfig
2. 处理Kconfig文件（评估所有配置符号、依赖和默认值）
3. 生成完整的.config文件

所以.config是defconfig + Kconfig系统共同作用的结果，不是简单的复制粘贴。

配置完成后，.config文件会出现在输出目录（`out/linux/.config`）。这个文件是编译时实际使用的配置，包含了完整的配置信息（默认值 + 板级特定设置）。

## 第三步：make——并行编译的威力

配置完成后，终于可以编译了：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux -j$(nproc)
```

`-j$(nproc)`这个参数很重要。`nproc`命令会输出CPU核心数，`-j`告诉make可以并行运行这么多任务。现代CPU都是多核的，不利用并行编译就太浪费了。我电脑是8核，`make -j8`基本上几分钟就编完了。

编译过程做了这些事情：

1. 编译C源文件生成.o目标文件
2. 链接生成vmlinux ELF文件
3. 解析vmlinux生成System.map符号表
4. 用objcopy转换格式生成Image（纯二进制）
5. 压缩Image生成zImage
6. 打包zImage+设备树生成最终镜像

编译过程可能需要几分钟到十几分钟，取决于你的CPU性能和配置。

## 编译产物说明：一堆文件都是干什么用的

编译完成后，你会在输出目录看到这些文件：

```
out/linux/
├── vmlinux                     # ELF格式的内核镜像
├── System.map                  # 符号地址表
├── .config                     # 内核配置
├── arch/arm/boot/
│   ├── Image                   # 未压缩的内核镜像
│   └── zImage                  # 压缩的内核镜像
└── modules/                    # 内核模块（如果编译了模块）
```

### vmlinux：ELF格式的完整内核

`vmlinux`是ELF格式的可执行文件，带调试信息，通常有几十MB。这个文件包含了完整的内核代码和数据，但太大且是ELF格式，不能直接烧录到板子上。它主要用于调试。

vmlinux的名字有点意思：vm = virtual memory（虚拟内存），linux = Linux内核。早期的Linux内核需要虚拟内存支持，所以叫vmlinux，这个名字一直沿用到现在。

### Image：纯二进制格式

`arch/arm/boot/Image`是vmlinux去掉ELF头和调试信息后的纯二进制格式，大约5-10MB。这个可以直接加载到内存运行，但因为没有压缩，占用空间较大。

### zImage：自解压的压缩镜像

`arch/arm/boot/zImage`是Image经过gzip压缩后，加上自解压代码的镜像，大约2-5MB。这是最常用的格式——体积小，加载到内存后会自动解压。

zImage的名字：z = gzip压缩。类似的还有bzImage（big zImage，用于x86的大内核）。

对于嵌入式系统，zImage通常是最终烧录的文件。

### System.map：符号地址表

`System.map`是内核符号及其地址的映射表。它的格式是：

```
c0008000 T _text
c0008000 A stext
c0008000 t _head
...
```

每一行表示一个符号的地址、类型、名称。当内核出现Oops（崩溃）时，会打印出错的地址，你可以用System.map找到对应的函数名，帮助定位问题。

### .config：配置文件

`.config`是编译时使用的完整配置。它非常重要，因为不同的配置会产生不同的内核。建议把.config保存好，下次编译时直接用，这样可以保证配置一致。

### .dtb：设备树Blob

如果你编译了设备树，还会看到.dtb文件。设备树编译后的二进制格式，包含了硬件描述。U-Boot加载内核时，会把dtb地址传给内核，内核根据dtb初始化硬件。

## 产物验证：如何确认编译没白忙活

编译完成了，但我们还不能高兴得太早。你需要验证产物是否正确，不然烧到板子上发现起不来，排查起来更麻烦。

### 架构检查：用readelf看清真相

首先检查架构是否正确：

```bash
arm-none-linux-gnueabihf-readelf -h out/linux/vmlinux | grep Machine
```

你应该看到类似这样的输出：

```
Machine: ARM
```

如果不是ARM，说明你用错了工具链，白忙活了。我见过有人用aarch64工具链编译armv7代码，产物架构不对，板子上当然跑不起来。

除了架构，还可以看入口地址：

```bash
arm-none-linux-gnueabihf-readelf -h out/linux/vmlinux | grep "Entry point"
```

输出类似：

```
Entry point address: 0xc0008000
```

这个地址是内核在虚拟内存中的入口点。对于ARM，0xc0008000是经典的内核加载地址（物理地址0x80000000的虚拟映射）。

### 大小检查：合理范围的验证

检查zImage的大小：

```bash
ls -lh out/linux/arch/arm/boot/zImage
```

输出类似：

```
-rwxr-xr-x 1 user user 3.2M Mar 15 12:34 out/linux/arch/arm/boot/zImage
```

i.MX6ULL的内核zImage一般在2-5MB之间。如果小于1MB，可能编译不完整；如果大于10MB，可能配置了太多调试选项或不必要的驱动。

### 符号检查：System.map是否正确

检查System.map是否包含预期的符号：

```bash
head -20 out/linux/System.map
```

你应该看到类似这样的输出：

```
c0008000 T _text
c0008000 A stext
c0008000 t _head
c0008000 t _start
...
```

如果System.map是空的或只有几行，说明编译出了问题。

### 设备树验证：dtc反编译

如果你编译了设备树，可以验证一下：

```bash
dtc -I dtb -O dts arch/arm/boot/dts/imx6ull-14x14-evk.dtb | grep fsl,imx6ull
```

你应该能看到类似这样的输出：

```
compatible = "fsl,imx6ull";
```

如果看不到imx6ull的字样，说明设备树可能选错了。

## 常见编译错误及解决

编译内核时，常见错误有这几类。我整理了一下，方便你快速排查。

### 错误1：缺少依赖包

```bash
scripts/kconfig/conf  --syncconfig .config
/bin/sh: 1: bc: not found
make: *** [Makefile:xxx: syncconfig] Error 127
```

这是缺少bc包。安装方法：

```bash
sudo apt install bc
```

类似的错误还可能出现在bison、flex、openssl等包上。

### 错误2：架构错误

如果你看到类似的警告：

```
WARNING: vmlinux.o (.text+0x...): unexpected relocation
```

可能是ARCH设错了，或者工具链不匹配。检查一下：

```bash
echo $ARCH
arm-none-linux-gnueabihf-gcc --version
```

确保ARCH=arm，工具链是ARM的。

### 错误3：配置冲突

```makefile
error: attempt to assign twice to 'CONFIG_XXX'
```

这通常是.config里有冲突的配置。解决方法：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux distclean
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux xxx_defconfig
```

先清理，再重新配置。

### 错误4：空间不足

```bash
No space left on device
```

内核编译需要不少临时文件空间，确保你的磁盘有足够空间（至少2GB）。可以用`df -h`检查。

## 总结成脚本：方便起见，我们把它自动化

到这里，你应该已经掌握了内核编译的完整流程。但每次都要敲这么多命令，确实有点累。而且容易出错，比如忘了distclean导致配置不生效，或者ARCH和CROSS_COMPILE写错了。

所以我们把这些步骤总结成一个脚本。IMX-Forge项目的`scripts/build_helper/build-linux.sh`就是这么一个脚本，它做了几件事：

1. 检查主机依赖（build-essential、bc、bison等）
2. 检查交叉编译工具链
3. 检查defconfig文件是否存在
4. 执行distclean/configure/build三阶段编译
5. 验证编译产物

使用方法很简单：

```bash
cd /path/to/imx-forge
./scripts/build_helper/build-linux.sh
```

脚本会自动处理所有细节，你只需要坐等编译完成。

## 快速编译技巧：节省时间的实用方法

当你频繁修改和编译时，全量编译太浪费时间。这里有几个加速技巧。

### 只编译修改的部分

如果你只修改了某个驱动，可以只编译这个驱动：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux drivers/gpio/gpio-mxc.o
```

### 跳过模块编译

如果你不需要内核模块，可以禁用它：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux -j$(nproc) CONFIG_MODULES=n
```

### 使用ccache

ccache是编译器缓存，第二次编译相同代码时直接用缓存，大幅提速：

```bash
sudo apt install ccache
export CROSS_COMPILE="ccache arm-none-linux-gnueabihf-"
```

IMX-Forge的构建脚本支持`--fast-build`参数，跳过distclean，节省时间。

## 写在最后

到这里，Linux内核编译的完整流程你就掌握了。从手动敲命令到理解每个步骤的含义，从排查错误到自动化脚本，我们走完了整个旅程。

编译不是黑魔法，每一步都有它的原因。distclean是为了避免缓存毒药，defconfig是通过Kconfig生成配置，make -j$(nproc)是利用多核加速，产物验证是确保没白忙活。当你理解了这些，你就不是在机械地复制命令，而是在掌控整个构建过程。

但编译只是第一步。下一篇文章，我们将深入内核配置的世界。你会看到：

- defconfig和.config到底有什么区别
- menuconfig怎么用
- 哪些配置项是必须了解的
- 如何创建自己的defconfig

准备好了吗？我们来配置内核。

---

**延伸阅读**

- [Linux Kernel Build Documentation](https://www.kernel.org/doc/html/latest/kbuild/index.html) - 内核构建系统文档
- [Cross-Compilation with gcc](https://www.kernel.org/doc/html/latest/kbuild/llvm.html) - 交叉编译指南
