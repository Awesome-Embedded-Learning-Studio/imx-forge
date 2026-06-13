# 从 0 开始构建嵌入式 Linux 开发环境

> 如何配置自己的想要使用的编译器？

::: info 本节你将学到
- 为什么嵌入式 Linux 必须用**交叉编译工具链**，而不能直接用主机 gcc
- 如何安装并验证 ARM GNU Toolchain 15.2
- 工具链的目录结构与 PATH 配置方法
:::

::: tip 前置知识 · 环境
- 会基本的 Linux 命令行操作（零基础请先看 [Linux 基础预备营](../linux-basics/)）
- 一台 Ubuntu / WSL2 主机，或直接使用项目 Docker 镜像
:::

### 前言：今年都 2026 了，我们真的还要用 gcc 7 吗？

最近在重新整理一套 **完全干净的嵌入式 Linux 构建环境**，目标其实很简单：
不依赖厂商 SDK，不依赖魔改脚本，从 **最原始的 U-Boot + Linux Kernel + RootFS** 开始，一步一步把整套系统搭起来。这是我一直想做的

很多朋友在做嵌入式 Linux 时其实都会遇到一个非常微妙的问题：
开发板厂商给的 SDK 里永远塞着一个 **不知道从哪个年代挖出来的工具链**。

你打开目录一看：

```
gcc-linaro-7.4.1
```

说实话第一次看到的时候我整个人是有点懵的。

今年都 **2026** 了，Linux Kernel 已经跑到 **6.x LTS**，GCC 主线版本都 **15.x** 了，而我们很多 BSP 还在用 **GCC 7 / GCC 8**。
短期看似乎没什么问题，代码还能编，但只要你稍微往新一点的 Kernel、U-Boot 或者用户态库靠一靠，警告和奇怪的问题就会开始出现。

于是这次我干脆决定一件事情：

**从工具链开始，彻底重建一套干净的交叉编译环境。**

我们不用厂商 SDK 里的东西，不碰那些已经没人维护的老版本工具链，而是直接上 **ARM 官方发布的最新 Arm GNU Toolchain 15.2**。

这一篇文章就是整个系列的第一步：

> **从 0 开始，安装一套完全独立的 ARM Linux 交叉编译工具链。**

---

# 环境说明（实验记录）

先把这次实验环境交代清楚，这一点我一直很在意，因为很多“教程跑不起来”的根本原因其实就是环境差异。

本次实验环境如下：

```
Host OS      : Ubuntu 24.04
Host Arch    : x86_64
Target Arch  : ARMv7 (Cortex-A7)
Target Board : i.MX6ULL
Toolchain    : Arm GNU Toolchain 15.2.rel1
```

目标非常明确：
我们要得到一套可以直接用于编译以下组件的交叉工具链：

```
U-Boot
Linux Kernel
BusyBox
RootFS
```

也就是说，最终我们的命令应该长这样：

```
arm-none-linux-gnueabihf-gcc
```

只要这个命令能正常工作，我们整个嵌入式 Linux 的构建链条就算点火成功了。

---

### 我们的起点：什么是 Standalone Toolchain？

先别急着下载，我们先把概念说清楚。

很多朋友第一次接触交叉编译时都会看到一堆名字：

```
gcc-linaro
arm-linux-gnueabihf
arm-none-eabi
aarch64-linux-gnu
```

看起来像一锅字符汤。

其实我们现在要用的 **Arm GNU Toolchain** 本质上就是一整套已经打包好的交叉编译环境，它里面不仅仅只有 gcc，还包含了一整套完整的工具链组件。

如果我们解压之后看一下目录结构，你会发现大概是这样：

```
arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
│
├── bin
│   ├── arm-none-linux-gnueabihf-gcc
│   ├── arm-none-linux-gnueabihf-ld
│   ├── arm-none-linux-gnueabihf-objdump
│   ├── arm-none-linux-gnueabihf-objcopy
│
├── lib
├── include
├── share
└── arm-none-linux-gnueabihf
```

你可以把它理解成：

> 一个 **完整的 ARM Linux 编译工具箱**

只要我们把这个工具箱加入 PATH，Linux 内核、U-Boot、BusyBox 等项目就能直接调用它完成交叉编译。

这也是为什么我一直建议大家 **优先使用 Standalone Toolchain**。
它干净、独立、不会污染系统环境，而且非常容易迁移到 CI 或 Docker。

---

### 第一步——下载 Arm GNU Toolchain 15.2

好，现在开始真正动手。

Arm 官方目前发布的最新版本是：

```
Arm GNU Toolchain 15.2.rel1
```

下载地址在 ARM 官方开发者网站，不过这里有一个小现实问题——官方服务器在某些网络环境下速度不太稳定，所以建议直接使用 `wget` 断点续传。

我们现在要做的是下载 **ARM32 Linux 版本**：

```bash
wget https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

下载体积大概是：

```
~350 MB
```

如果你发现速度慢，可以加上断点续传参数：

```bash
wget -c https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

下载完成之后我们先确认文件存在：

```
$ ls

arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

很好，现在我们的工具链包已经到手。

---

### 第二步——解压工具链

接下来事情就简单很多了。

直接解压：

```bash
tar -xf arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

解压完成之后你会得到一个完整目录：

```
arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
```

先别急着装，我们先进去看一眼。

```
cd arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
ls
```

你会看到：

```
bin
lib
include
share
arm-none-linux-gnueabihf
```

这里面最重要的其实就是 `bin` 目录。

我们验证一下：

```
ls bin
```

输出类似：

```
arm-none-linux-gnueabihf-gcc
arm-none-linux-gnueabihf-g++
arm-none-linux-gnueabihf-ld
arm-none-linux-gnueabihf-objdump
arm-none-linux-gnueabihf-strip
```

看到这里其实就已经非常清楚了：

> 这就是我们之后编译整个 ARM Linux 系统要用的核心工具。

---

### 第三步——安装到 /opt

很多朋友喜欢把工具链放在 home 目录，其实我不太推荐。

原因很简单：
如果未来你有多个项目、多个版本工具链，home 目录很快就会变成一个灾难现场。

更好的做法是把所有工具链统一放到：

```
/opt
```

所以现在我们做一件很简单的事情：

```bash
sudo mv arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain
```

然后确认一下：

```
ls /opt
```

应该能看到：

```
arm-gnu-toolchain
```

很好，现在工具链已经安装完成。

---

### 第四步——配置 PATH

接下来问题来了。

我们现在虽然已经有工具链了，但 Linux 还不知道它在哪。

如果你现在直接运行：

```
arm-none-linux-gnueabihf-gcc
```

大概率会得到一个非常熟悉的报错：

```
command not found
```

所以我们需要把工具链的 `bin` 目录加入 PATH。

编辑 `.bashrc`：

```bash
nano ~/.bashrc
```

在文件最后加一行：

```bash
export PATH=/opt/arm-gnu-toolchain/bin:$PATH
```

保存退出之后刷新环境：

```bash
source ~/.bashrc
```

---

### 第五步——验证工具链

现在到了最有仪式感的一步。

我们来确认工具链是否真的工作。

直接运行：

```
arm-none-linux-gnueabihf-gcc -v
```

如果一切正常，你会看到类似输出：

```
Using built-in specs.
COLLECT_GCC=arm-none-linux-gnueabihf-gcc
Target: arm-none-linux-gnueabihf
gcc version 15.2.1
```

看到这一行：

```
gcc version 15.2
```

基本就可以放心了。

这说明：

> 我们已经拥有一套可以编译 ARM Linux 程序的完整工具链。

---

# 这里千万别手滑的一个坑

很多人到这里其实会犯一个非常隐蔽的错误。

他们会把 PATH 写成：

```
/opt/arm-gnu-toolchain
```

而不是：

```
/opt/arm-gnu-toolchain/bin
```

结果就是系统找不到 gcc。

如果你遇到：

```
arm-none-linux-gnueabihf-gcc: command not found
```

第一件事先检查：

```
echo $PATH
```

看看 `bin` 目录是否存在。

这个坑我当年真的踩过。

---

### 到这里，我们的工具链已经点火成功

很好，到这里其实第一阶段已经完成了。

我们现在已经拥有了一套 **完全独立、官方维护、最新版本的 ARM 交叉编译工具链**，而且它没有依赖任何厂商 SDK，也不会和系统环境产生冲突。

接下来事情就开始变得有意思了。

因为有了工具链之后，我们就可以开始真正搭建嵌入式 Linux 的启动链条：

```
Toolchain
   ↓
U-Boot
   ↓
Linux Kernel
   ↓
RootFS
```

下一篇我们要做的事情就是：

> **从 0 编译 U-Boot。**

到时候我们会真的把板子点起来。

到这里，工具链环境就算搭建完成了，可以给工具链拍张照纪念一下。不过更重要的是——下一篇开始，我们就要真正和 Bootloader 正面交锋了。
