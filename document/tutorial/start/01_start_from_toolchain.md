---
title: 从 0 开始：安装交叉编译工具链
---

# 从 0 开始：安装交叉编译工具链

> 这是 start 卷的第二篇。上一篇咱们把学习路线捋清了，这一篇解决整条构建链的第一个环节：编译器从哪来。您将亲手安装一套独立于厂商 SDK 的 ARM 交叉编译工具链(Arm GNU Toolchain 15.2)并配进 PATH，下一篇再把主机依赖补齐。工具链不就位，后面的 U-Boot、内核、根文件系统一步都动不了。

::: tip 前置知识 · 环境
- 会基本的 Linux 命令行操作(nano 编辑、tar 解压、环境变量)。交叉编译的概念背景想系统补课的话，[Linux 基础第 35 章](../linux-basics/07-devtools/ch35-crosscompile.md)有整章展开，目标三元组的逐段拆解就在那里
- 一台 Ubuntu 24.04 主机，裸机或 WSL2 皆可;WSL2 的网络与防火墙细节见[开发环境配置卷第一篇](../workflow/01_wsl2_env_config.md)
- 不想手动配工具链的话，[Docker 卷](../docker/)提供了预装同一套 15.2 的镜像路线，与本篇的手动路径二选一
- 路径上下文：本篇全部操作发生在主机的家目录与 /opt 下，不涉及 imx-forge 仓库源码树；工具链安装在 /opt/arm-gnu-toolchain,它是通用的 ARM Linux 工具链，后续所有组件的构建都靠它
:::

## 前言：今年都 2026 了，还要用 GCC 7 吗？

这套教程的目标，路线图里笔者已经交代过：不依赖厂商 SDK，不依赖魔改脚本，从最原始的 U-Boot、Linux 内核、根文件系统开始，把整套系统一步步搭起来。而很多朋友做嵌入式 Linux 时，都会撞见一个非常微妙的现实：开发板厂商给的 SDK 里，永远塞着一个不知道从哪个年代挖出来的工具链。打开目录一看：

```text
gcc-linaro-7.4.1
```

笔者第一次看到这个目录名的时候，整个人是有点懵的。今年都 2026 年了，Linux 内核主线都出到 7.x 了(本仓库主线内核就是 7.1),GCC 主线都 16.x 了，而不少 BSP 内核还停在 6.12 LTS、工具链还停在 GCC 7 / GCC 8。短期看似乎没什么问题，代码还能编；但只要咱们稍微往新一点的内核、U-Boot 或者用户态库靠一靠，过时编译器带来的警告和怪问题就会开始冒头。这种问题浪费时间的地方在于，您会本能地怀疑自己的代码，而不是怀疑编译器太老。

于是笔者这次干脆下了个决心：从工具链开始，彻底重建一套干净的交叉编译环境。不碰厂商 SDK 里那些没人维护的老版本，直接上 ARM 官方发布的 Arm GNU Toolchain 15.2。本篇就是这件事的完整记录：从零开始，装一套完全独立的 ARM Linux 交叉编译工具链。

## 环境说明

本次的环境是：

```text
Host OS      : Ubuntu 24.04(WSL2)
Host Arch    : x86_64
Target Arch  : ARMv7(Cortex-A7)
Target Board : i.MX6ULL
Toolchain    : Arm GNU Toolchain 15.2.Rel1
```

环境差异是很多教程跑不起来的根因，您后面哪条输出复现不上，先回这份清单对一遍。

目标非常明确：得到一套能直接编译 U-Boot、Linux 内核、BusyBox 和根文件系统内容的工具链。判断标准也简单，下面这条命令能正常吐出版本号，咱们整条嵌入式 Linux 构建链就算点火成功了：

```bash
# 主机 ~
arm-none-linux-gnueabihf-gcc --version
```

本篇贴出的验证输出，全部来自笔者这台机器的真实执行，不是凭记忆默写。

## 什么是 Standalone Toolchain

动手下载之前，咱们把概念说清楚。第一次接触交叉编译的朋友，看到工具链们的一堆名字时，大概会觉得像一锅字符汤：

```text
gcc-linaro
arm-linux-gnueabihf
arm-none-eabi
aarch64-linux-gnu
```

这些前缀的逐段含义(目标三元组)不在这篇展开，前面链接的第 35 章有完整拆解。这里只需要知道：咱们要装的 Arm GNU Toolchain,本质是一整套打包好的交叉编译环境，里面远不止一个 gcc。看一眼本机安装后的真实目录(/opt/arm-gnu-toolchain 下的 ls 输出)：

```text
15.2.rel1-x86_64-arm-none-linux-gnueabihf-manifest.txt
arm-none-linux-gnueabihf
bin
include
lib
lib64
libexec
license.txt
share
tmp
```

真正干活的都在 bin 里。咱们挑几个后面天天打交道的：

```text
arm-none-linux-gnueabihf-gcc
arm-none-linux-gnueabihf-g++
arm-none-linux-gnueabihf-ld
arm-none-linux-gnueabihf-objcopy
arm-none-linux-gnueabihf-objdump
arm-none-linux-gnueabihf-strip
```

翻译成人话：这是一个完整的 ARM Linux 编译工具箱。编译器 gcc、链接器 ld、格式转换 objcopy、反汇编 objdump、瘦身 strip 一应俱全，而且全部带 arm-none-linux-gnueabihf- 前缀，跟咱们主机自带的 x86 版本完全不会混淆。把这个 bin 目录加进 PATH 后，U-Boot、内核、BusyBox 的构建系统就能按前缀直接找到它们。

这也是笔者一直建议优先用 Standalone Toolchain(独立工具链)的原因：解压即用，不往系统目录塞东西，不污染主机环境；换机器或迁去 CI、Docker 时，整个目录拷走就行。厂商 SDK 的工具链往往跟一堆绑定脚本纠缠在一起，想单独升级都无从下手。

## 五步安装：从下载到验证

### 下载 Arm GNU Toolchain 15.2

Arm 官方开发者网站提供下载，咱们要的是 ARM32 Linux 版本，也就是 x86_64 主机、arm-none-linux-gnueabihf 目标的那一个包：

```bash
# 主机 ~
wget https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

官方服务器在某些网络环境下速度不太稳定，中途断了不用慌，wget 自带断点续传，咱们加个 -c 接着拉：

```bash
# 主机 ~
wget -c https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

下载完成后您可以 ls 确认一下，压缩包已经在家目录里，文件名就是上面那一长串。

::: warning 未实测标注
下载这一步在笔者当前环境没有重新执行：工具链早已装好，没必要再拉一遍一百多 MB 的包。压缩包体积笔者对官方下载链接做过一次 HTTP HEAD 实测:content-length 134,624,396 字节,约 135 MB(约 128 MiB);解压后的实际占用笔者用 du 量过，是 597 MB。具体数字以官方下载页面为准。
:::

### 解压

```bash
# 主机 ~
tar -xf arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

解压出来一个同名目录，咱们进去看一眼：

```bash
# 主机 ~
cd arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
ls
```

输出就是上一节贴过的那份清单，这里不重复。您想再踏实一点，可以单独 ls bin,确认 gcc、ld、objdump、strip 都在。

### 安装到 /opt

很多朋友喜欢把工具链直接丢在家目录，笔者不太推荐。一旦后面多个项目、多个版本的工具链共存，家目录很快会变成灾难现场，连您自己都记不清哪个目录对应哪个版本。更稳妥的做法是统一放进 /opt,Linux 放第三方软件包的惯例位置：

```bash
# 主机 ~
sudo mv arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain
```

挪完之后 ls /opt,能看到 arm-gnu-toolchain 就说明搬对了。把目录重命名成不带版本号的短名字，是笔者有意为之：后面 PATH、构建脚本、Docker 镜像与肌肉记忆里写的都是 /opt/arm-gnu-toolchain 这一个路径，将来升级到更新的版本时把新目录换进来就行，其他地方一个字都不用改。仓库里目前还有几处旧布局没跟上：开发文档 ENVIRONMENT_SETUP.md 的工具链一节(装到 /opt/arm-toolchain、重命名为 arm-15.2-rel1)，还有 Linux 基础卷脚本篇第 26、30 章的示例路径，写的都是 /opt/arm-toolchain,那个目录在本机并不存在；您对照着看时，一律以本篇的 /opt/arm-gnu-toolchain 为准，等这些文档都修订过来，这句提醒就该删了。

### 配置 PATH

工具链就位了，但此时 Linux 还不知道它在哪。咱们直接运行 arm-none-linux-gnueabihf-gcc,大概率会收获一句非常熟悉的报错：

```text
arm-none-linux-gnueabihf-gcc: command not found
```

系统只在 PATH 环境变量列出的目录里找命令，所以咱们要把工具链的 bin 目录追加进去。编辑 shell 的配置文件：

```bash
# 主机 ~
nano ~/.bashrc
```

在文件末尾加入这一行：

```bash
# 主机 ~,写入 shell 配置文件末尾的内容
export PATH=/opt/arm-gnu-toolchain/bin:$PATH
```

保存退出后刷新环境，让它立刻生效：

```bash
# 主机 ~
source ~/.bashrc
```

这里有个笔者用真实输出换来的提醒。采集素材时跑 grep -rn 'PATH' ~/.bashrc,在笔者这台机器上什么都没搜到；这行 export 其实躺在 ~/.zshrc 的第 53 行，因为默认 shell 是 zsh。您如果也在用 zsh,请把配置写进 ~/.zshrc 并 source ~/.zshrc,写错文件的话 source 到天亮也不会生效。

### 验证

到最有仪式感的一步了，咱们来确认工具链真的能工作：

```bash
# 主机 ~
arm-none-linux-gnueabihf-gcc -v
```

咱们看本机实测输出，中间一大段 configure 参数行用省略号折掉了：

```text
Using built-in specs.
Target: arm-none-linux-gnueabihf
...
gcc version 15.2.1 20251203 (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86))
```

Target 是 arm-none-linux-gnueabihf,版本 15.2.1,到这里您基本可以放心了。再看一眼更干净的 --version:

```bash
# 主机 ~
arm-none-linux-gnueabihf-gcc --version | head -2
```

```text
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
Copyright (C) 2025 Free Software Foundation, Inc.
```

只看版本号还不过瘾的话，咱们真编一个程序给它：

```bash
# 主机 ~
printf '#include <stdio.h>\nint main(void){printf("hello from arm\\n");return 0;}\n' > hello.c
arm-none-linux-gnueabihf-gcc -o hello hello.c
file hello
```

本机实测输出：

```text
hello: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, with debug_info, not stripped
```

ELF 32-bit、ARM,说明咱们这份产物确实是 ARM 机器码，交叉编译的链路全程通畅。它在 x86 主机上跑不起来——x86 内核不认 ARM 的 ELF 头，这是正常现象，不是咱们编错了。

::: warning 未实测标注
hello 放到实际的板子上运行这一步，本环境验证不了(笔者手头是 x86 主机，没有连着的 i.MX6ULL)。另外产物是动态链接的，板端根文件系统里得有 ARM 版 libc 才跑得起来；本篇以 file 命令确认产物架构为验证终点。
:::

## 一个高频翻车点:PATH 少写了 bin

装到这里，很多人会栽在一个非常隐蔽的地方：PATH 写的是工具链根目录，而不是它的 bin 子目录。根目录下确实躺着 gcc 要用的一切，但命令本体全在 bin 里；系统按 PATH 搜索的是可执行文件，不是目录树。咱们对照着看：

```bash
# 主机 ~,两种写法对照
export PATH=/opt/arm-gnu-toolchain:$PATH      # 错,少了 /bin
export PATH=/opt/arm-gnu-toolchain/bin:$PATH  # 对
```

结果就是 source 也 source 了、终端也重开了，照样 command not found。笔者当年真的踩过这个坑，排查了半天，最后 echo $PATH 一打印，路径少一截，一眼就看出来了。

::: warning
PATH 里要写的是 /opt/arm-gnu-toolchain/bin,不是 /opt/arm-gnu-toolchain。咱们遇到 command not found,第一反应是 echo $PATH 检查，别急着重装工具链。
:::

排查命令这么敲：

```bash
# 主机 ~
echo $PATH | tr ':' '\n' | grep arm
```

这条命令在全新终端里的正常输出只有一行 /opt/arm-gnu-toolchain/bin——笔者拿 env -i HOME=$HOME zsh -l -i -c 'echo $PATH' 模拟过一次干净的登录交互 zsh，看到的 PATH 里也只有这一行。您要是看到两行一模一样的 /opt/arm-gnu-toolchain/bin，多半是刚才照着上一节手动 source 过 ~/.zshrc，或者开了嵌套 shell 继承了父进程已有的 PATH，同一个 export 被又叠了一遍，同样无害。您那边如果一行都搜不到，问题就清楚了：要么 PATH 少写了 bin,要么写错了配置文件(回到上一节 zsh 的提醒)。咱们把这一节的翻车点收成一张速查表：

| 现象 | 根因 | 解法 |
|---|---|---|
| 配了 PATH 仍然 command not found | 写成了 /opt/arm-gnu-toolchain,少了 bin | 改成 /opt/arm-gnu-toolchain/bin:$PATH |
| source 后有效，新开终端又失效 | export 只敲在当前 shell,没写进配置文件 | 写进 ~/.bashrc(或 ~/.zshrc)再 source |
| 版本号是 7.x 老版本，不是 15.2 | 厂商 SDK 的工具链目录在 PATH 里排在前面 | 用 /opt/arm-gnu-toolchain/bin:$PATH 的写法，把这套工具链排到搜索顺序最前 |

## 收尾：工具链点火成功

到这里，工具链这一环就完成了。咱们现在拥有的，是一套完全独立、官方维护的 ARM 交叉编译工具链：不依赖任何厂商 SDK,不和系统环境冲突，解压即用，整体可迁移。有了它，后面的启动链条才能一段一段点起来：

```text
Toolchain  ← 本篇,已完成
   ↓
U-Boot
   ↓
Linux Kernel
   ↓
RootFS
```

不过工具链只是编译器本体。真要把 U-Boot 编起来，主机上还得有 bison、flex 这类构建依赖，所以下一篇咱们不急着碰 U-Boot,而是用仓库里的 scripts/init/env-init.sh 脚本把主机依赖一次性补齐，那就是[下一篇](02_env_init_guide.md)的主角。完整的主机环境文档(含更细的版本说明)另见仓库的开发文档，教程里笔者只带您走最常用的这条路径。

## 继续学习

- 上一篇:[00 一切的源头，学习路线怎么走](00_roadmap.md)
- 下一篇:[02 环境初始化指南](02_env_init_guide.md)，用 env-init.sh 补齐主机构建依赖
- 想系统补交叉编译的概念(目标三元组、QEMU 用户态模拟):[Linux 基础第 35 章，交叉编译与 imx-forge 衔接](../linux-basics/07-devtools/ch35-crosscompile.md)
- WSL2 主机的网络与防火墙配置:[开发环境配置卷第一篇](../workflow/01_wsl2_env_config.md)
- 不想手动配工具链，换 [Docker 路线](../docker/):镜像预装同一套 15.2
- 完整环境文档:[ENVIRONMENT_SETUP](../../development/ENVIRONMENT_SETUP.md)
