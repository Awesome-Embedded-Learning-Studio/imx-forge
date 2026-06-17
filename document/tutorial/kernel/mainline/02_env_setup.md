# 从零开始搭建主线内核编译环境

## 前言：为什么这篇文章这么长

说实话，编译 Linux 内核这件事本身并不复杂——不就是 `make` 一下吗？但问题在于，你第一次编译的时候会报一堆莫名其妙的错误：`flex: command not found`、`bc: command not found`、`error: openssl/bio.h: No such file or directory`...

这些报错背后的原因是：内核编译需要大量的宿主机工具和库。你把源码下载下来，直接编译大概率会失败。这篇文章的目标是帮你把环境一次性搭好，后续编译时不会再因为缺少依赖而卡住。

我们参考了项目里 `scripts/build_helper/build-mainline-linux.sh` 的依赖检查逻辑，把所有需要的依赖都列出来了。跟着做一遍，你就能得到一个可以正常编译主线内核的环境。

## 环境说明

开始之前，先明确一下我们的目标环境：

| 项目 | 说明 |
|------|------|
| 宿主机 | Ubuntu 22.04 LTS 或 Debian 12（WSL2 也可以） |
| 目标架构 | ARMv7 (i.MX6ULL) |
| 交叉编译工具链 | arm-none-linux-gnueabihf- |
| 内核版本 | Linux 7.1 |

如果你用的是其他发行版，包名可能略有不同，但依赖本质是一样的。

## 第一步——安装宿主机依赖

内核编译需要的依赖可以分为几类：基础编译工具、库文件、特定工具。我们一个个来装。

### 基础编译工具

这些是编译任何 C 项目都需要的东西：

```bash
sudo apt update
sudo apt install build-essential make
```

`build-essential` 是一个元包，会安装 gcc、g++、make 等基础工具。如果你已经做过嵌入式开发，大概率已经有了。

### 内核特定工具

内核编译需要一些特定的工具，它们的作用可能不明显，但缺一不可：

```bash
sudo apt install bc bison flex device-tree-compiler
```

让我解释一下每个工具是干什么的：

- **bc**：任意精度计算器，内核配置时会用它计算一些数值（比如内存大小）
- **bison**：语法分析器生成器，内核的 Kconfig 配置系统需要它
- **flex**：词法分析器生成器，同样用于 Kconfig 系统
- **device-tree-compiler (dtc)**：设备树编译器，把 `.dts` 文件编译成 `.dtb` 二进制格式

如果少了这些，编译会在不同阶段报错。错误信息可能不那么直观，比如 `bc: command not found` 会在配置阶段报错，而不是编译阶段。

### SSL 和加密库

内核的模块签名和某些加密功能需要 OpenSSL：

```bash
sudo apt install libssl-dev
```

如果你编译时遇到 `error: openssl/bio.h: No such file or directory`，就是缺少这个包。

### Ncurses 库

`make menuconfig` 这个图形化配置工具依赖 ncurses：

```bash
sudo apt install libncurses-dev
```

如果你不需要用 menuconfig，只准备用现成的 defconfig，这个包可以不装。但我强烈建议装上，因为调试配置问题时 menuconfig 非常有用。

### 其他可能需要的库

某些内核功能可能需要额外的库，建议一并装上：

```bash
sudo apt install libgnutls28-dev zlib1g-dev
```

- **libgnutls28-dev**：某些内核模块的签名需要
- **zlib1g-dev**：压缩相关功能需要

### Python 环境

某些内核编译步骤（如设备树验证）需要 Python：

```bash
sudo apt install python3
```

Ubuntu 22.04 默认就有 Python 3，但如果是老版本系统，可能需要手动安装。

## 第二步——安装交叉编译工具链

有了宿主机工具，接下来是交叉编译工具链。i.MX6ULL 是 ARMv7 架构，你的 x86 电脑不能直接编译出能在板子上跑的程序，需要交叉编译。

### 工具链选择

有好几种选择：

- **gcc-arm-linux-gnueabihf**：Ubuntu 官方仓库版本，方便但可能版本较老
- **arm-none-linux-gnueabihf**：ARM 官方工具链，版本新，需要手动下载
- **Linaro 工具链**：Linaro 组织维护的 ARM 工具链

这个项目用的是 `arm-none-linux-gnueabihf`，你可以从 ARM 官网下载。为了方便起见，这里用 Ubuntu 仓库版本演示：

```bash
sudo apt install gcc-arm-linux-gnueabihf
```

### 验证工具链

安装完成后，验证一下是否正常：

```bash
arm-linux-gnueabihf-gcc --version
```

你应该看到类似这样的输出：

```
arm-linux-gnueabihf-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
Copyright (C) 2021 Free Software Foundation, Inc.
```

如果输出版本号，说明安装成功。如果提示 `command not found`，检查一下是不是 PATH 环境变量的问题（如果是从 ARM 官网下载的手动解压版本，需要把 bin 目录加到 PATH 里）。

## 第三步——验证依赖完整性

项目里的构建脚本 `scripts/build_helper/build-mainline-linux.sh` 有一个 `check_host_dependencies()` 函数，它会检查所有依赖是否齐全。我们可以手动运行类似的检查：

```bash
# 检查基础命令
for cmd in gcc make bc bison flex dtc python3; do
    if command -v $cmd &> /dev/null; then
        echo "✓ $cmd"
    else
        echo "✗ $cmd (not found)"
    fi
done

# 检查库文件
for header in "openssl/openssl.h" "ncursesw/ncurses.h"; do
    if [ -f "/usr/include/$header" ] || [ -f "/usr/include/x86_64-linux-gnu/$header" ]; then
        echo "✓ $(dirname $header)"
    else
        echo "✗ $(dirname $header) (not found)"
    fi
done
```

如果所有检查都显示 ✓，恭喜你环境已经配好了。如果有 ✗，根据缺失项安装对应的包。

## 第四步——测试编译（可选）

如果你想确认环境真的没问题，可以先编译一个简单的 ARM 程序测试一下：

```bash
# 创建一个测试程序
echo '#include <stdio.h>
int main() {
    printf("Hello from ARM!\n");
    return 0;
}' > hello.c

# 交叉编译
arm-linux-gnueabihf-gcc hello.c -o hello_arm

# 检查文件类型
file hello_arm
```

你应该看到类似 `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV)` 的输出，说明这是一个 ARM 程序。如果看到 `x86-64`，说明你用的是宿主机的 gcc，不是交叉编译器。

## 常见问题排查

### 问题一：dtc 版本太老

某些设备树语法需要较新的 dtc 版本。如果你编译设备树时报错，可能是 dtc 版本太老：

```bash
dtc --version
```

如果版本低于 1.4.x，建议安装 `device-tree-compiler` 包而不是用系统自带的。

### 问题二：Python 模块缺失

某些内核构建步骤需要特定的 Python 模块，如果报错 `ModuleNotFoundError: No module named 'xxx'`，用 pip 安装：

```bash
sudo apt install python3-pip
pip3 install <缺失的模块名>
```

### 问题三：工具链路径问题

如果你下载的是 ARM 官方工具链，需要手动添加到 PATH：

```bash
# 添加到 ~/.bashrc
echo 'export PATH=$PATH:/opt/arm-none-linux-gnueabihf/bin' >> ~/.bashrc
source ~/.bashrc
```

### 问题四：WSL2 的特殊问题

如果你在 WSL2 下编译，可能会遇到文件系统大小写敏感的问题。Linux 内核源码里有同名不同大小写的文件（比如 `Makefile` 和 `makefile`），在 WSL2 的默认配置下可能出问题。

建议把内核源码放在 WSL2 的文件系统内（比如 `~/linux_mainline`），而不是挂载的 Windows 驱动（比如 `/mnt/c/...`）。WSL2 的 Linux 文件系统是大小写敏感的，Windows 文件系统则不是。

## 下一章预告

到这里，你的编译环境应该已经准备好了。下一篇文章，我们会讲如何获取主线内核源码：

- 从 kernel.org 克隆特定版本
- 使用 git worktree 管理多个内核版本
- 如何应用移植补丁
- 源码目录结构快速导读

有了源码，下一步就是配置和编译。我们一步步来。

---

**参考命令速查**

```bash
# 一键安装所有依赖（Ubuntu/Debian）
sudo apt install build-essential make bc bison flex device-tree-compiler \
    libssl-dev libncurses-dev libgnutls28-dev zlib1g-dev python3

# 安装交叉编译工具链
sudo apt install gcc-arm-linux-gnueabihf

# 验证工具链
arm-linux-gnueabihf-gcc --version
```

**延伸阅读**

- [Linux Kernel Build Documentation](https://www.kernel.org/doc/html/latest/kbuild/index.html) - 内核构建系统文档
- [ARM GNU Toolchain Download](https://developer.arm.com/downloads/-/gnu-rm) - ARM 官方工具链下载
