# 第 17 章  软件安装全解

> **Part 4 · 系统管理**

---

## 引子

Windows 装软件：下载 `.exe`，双击，下一步，完成。
macOS 装软件：拖进 Applications，完事。
Linux 装软件：`apt install`？`snap install`？还是下载源码自己 `./configure && make`？

三条路，三种哲学。

`apt` 是 Linux 世界最主流的包管理器——一个命令解决下载、安装、依赖、更新所有问题。`snap` 想做「跨发行版的通用包」，把应用和它所有的依赖打包成一个自包含的沙盒。源码编译是嵌入式开发的标配——因为你经常需要交叉编译，预编译的二进制包根本没法用。

它们不冲突，但你得知道什么时候用哪个。而做出正确选择的前提，是理解它们各自的工作原理和边界。

---

## 背景与动机

在 Windows 的世界里，「安装软件」就是下载一个安装包、运行它、点几下「下一步」。安装包里已经帮你打包好了所有东西——可执行文件、动态链接库（DLL）、注册表项、桌面快捷方式。如果缺了什么依赖，安装程序通常会自动帮你装上。

Linux 的包管理器把这个过程做得更彻底——它不只是帮你装一个软件，而是帮你管理整个系统的软件生态。依赖关系由包管理器自动解析和安装，不需要你手动下载一个个 DLL。升级时，包管理器会统一处理所有已安装软件的版本更新。

但嵌入式开发者会频繁遇到一种场景：你要用的工具或者库没有预编译的 `.deb` 包——也许它太新了，也许它只以源码形式发布，也许你需要针对 ARM 架构重新编译。这时候就需要从源码编译。

三种方式不是互相替代的关系，而是互补的。日常工具用 `apt`，图形应用用 `snap`（或者不用），嵌入式工具链和定制库用源码编译。

---

## 概念层

### 包管理器——软件的「中央配送系统」

你可以把 `apt` 理解为一个**中央配送系统**——它有一个全球的「仓库网络」（软件源），你的系统本地有一份「库存清单」（软件索引），每次安装之前它先从仓库拉最新的清单，然后自动计算这个软件需要哪些依赖，按顺序一起配送、安装。

但「中央配送系统」这个比喻有一个地方是错的：真正的配送系统送的是成品，你拿到就能用。而 `apt` 的软件包（`.deb` 文件）不仅仅是成品——它在安装前会执行预安装脚本（比如创建系统用户、设置目录权限），安装后会执行后安装脚本（比如更新缓存、重启服务）。软件包是一个「自带安装说明的压缩包」，不是单纯的文件集合。

这也是为什么你不应该只用 `dpkg -i` 安装 `.deb` 文件——`dpkg` 只负责解压和放置文件，不处理依赖。而 `apt` 会帮你解决依赖问题。

#### apt vs apt-get

Ubuntu 22.04+ 上，`apt` 是推荐的命令行接口。它是 `apt-get` 的现代替代，做了几件事：

- 合并了 `apt-get` 和 `apt-cache` 的常用功能（安装用 `apt install`，搜索用 `apt search`）
- 默认启用了进度条和颜色输出
- 在 `apt upgrade` 时会自动移除不再需要的依赖

在脚本中，`apt-get` 仍然更常用——因为它的输出格式更稳定，更适合被脚本解析。`apt` 的输出格式可能会在不同版本间变化。

两者操作的是同一套底层的 APT 系统和 `.deb` 包数据库，所以你可以混用，不会冲突。

---

### snap——自包含的沙盒包

`snap` 是 Canonical（Ubuntu 的母公司）推出的包格式。它的核心设计理念是：**把应用和它所有的依赖打包成一个自包含的 SquashFS 镜像**，运行在沙盒环境中。

这意味着同一个 snap 包可以在 Ubuntu、Fedora、Arch 等不同发行版上运行——因为所有依赖都打包在内部，不依赖系统库的版本。

这种设计的代价是：snap 包的体积通常比 `.deb` 包大很多（因为包含了所有依赖）；首次启动时需要挂载 SquashFS 镜像，会有几秒钟的冷启动延迟；snap 应用运行在受限的沙盒中，访问系统资源需要显式授权。

对于国内用户来说，snap 还有一个实际问题：snap 的软件源托管在 Canonical 的全球 CDN 上，没有国内镜像。下载速度可能很慢，有时甚至超时。

---

### 源码编译——从源到二进制的完整旅程

源码编译是嵌入式开发中最重要的安装方式。它通常遵循一套经典流程：

```
./configure → make → make install
```

`./configure` 是一个 Shell 脚本，它检测你的系统环境（编译器是否存在、需要的库是否安装、内核头文件是否可用），然后生成一个 `Makefile`。`make` 根据 `Makefile` 中的规则调用编译器，把源代码编译成二进制文件。`make install` 把编译产物复制到系统目录（通常是 `/usr/local/bin`、`/usr/local/lib`）。

你可以把源码编译理解为「从原材料开始自己造零件」——`./configure` 是检查你有没有工具和原材料，`make` 是加工制造，`make install` 是把成品放到工具箱里。

但「自己造零件」这个比喻有一个地方是错的：你并不是真的从零开始。`./configure` 检测的那些系统库和工具就是你的「机床」和「原材料供应」——如果机床没通电（编译器没装）或者原材料不够（缺少依赖库），制造过程在 `./configure` 阶段就会报错停下来。

这也是源码编译最容易让人崩溃的地方：缺一个依赖，装上之后发现它还依赖另一个，再装，还缺……这种「依赖地狱」在嵌入式交叉编译中尤其严重，因为目标架构（ARM）的依赖库和主机架构（x86）的依赖库不能混用。

---

## 实践层

### 4.1  apt——日常安装的主力

#### 更新软件索引

```bash
$ sudo apt update
Hit:1 http://cn.archive.ubuntu.com/ubuntu noble InRelease
Hit:2 http://cn.archive.ubuntu.com/ubuntu noble-updates InRelease
...
Reading package lists... Done
Building dependency tree... Done
All packages are up to date.
```

`apt update` 不安装任何东西——它只从软件源拉取最新的软件包列表。在安装任何软件之前，先跑一遍 `apt update` 是好习惯，因为本地的索引可能已经过时了。

#### 搜索软件包

```bash
$ apt search cmake
Sorting... Done
Full Text Search... Done
cmake/noble 3.28.3-1build1 amd64
  cross-platform, open-source make system
```

#### 安装软件

```bash
$ sudo apt install cmake
Reading package lists... Done
Building dependency tree... Done
The following NEW packages will be installed:
  cmake cmake-data
...
Do you want to continue? [Y/n] y
...
Setting up cmake (3.28.3-1build1) ...
```

APT 会列出所有即将安装的包（包括自动解析出的依赖），等你确认后才开始下载和安装。

#### 查看已安装的包

```bash
$ apt list --installed | grep vim
vim/noble,now 9.1.0016-1ubuntu2 amd64 [installed]
vim-common/noble,now 9.1.0016-1ubuntu2 all [installed]
vim-runtime/noble,now 9.1.0016-1ubuntu2 all [installed]
```

#### 升级软件

```bash
# 升级单个包
$ sudo apt upgrade cmake

# 升级所有可升级的包
$ sudo apt upgrade
```

`apt upgrade` 不会移除任何已安装的包。如果某个包的升级需要移除其他包，`apt upgrade` 会跳过它——这时需要用 `apt full-upgrade`。

#### 卸载软件

```bash
# 卸载软件但保留配置文件
$ sudo apt remove cmake

# 卸载软件并删除配置文件
$ sudo apt purge cmake

# 清理不再需要的依赖
$ sudo apt autoremove
```

`remove` 和 `purge` 的区别在于是否删除配置文件（通常在 `/etc` 下）。`autoremove` 会清理那些因为依赖关系自动安装、但现在不再被任何包需要的「孤儿包」。

---

### 4.2  snap——另一个选项

#### 查看已安装的 snap

```bash
$ snap list
Name    Version   Rev    Tracking       Publisher   Notes
core20  20240111  2182   latest/stable  canonical✓  base
snapd   2.61.1    19361  latest/stable  canonical✓  snapd
```

#### 安装 snap 应用

```bash
$ sudo snap install hello-world
hello-world 6.4 from Canonical✓ installed
```

snap 包安装在 `/snap/` 目录下。每个应用是一个独立的 SquashFS 镜像，挂载在 `/snap/<name>/current/`。

#### 更新和卸载

```bash
# 更新所有 snap 应用
$ sudo snap refresh

# 卸载
$ sudo snap remove hello-world
```

#### snap 的实际使用建议

坦率地说，在国内的网络环境下，snap 的体验不算好。下载速度慢是一个真实的问题——snap 没有像 apt 那样的国内镜像源。如果你在安装 snap 应用时遇到超时，可以尝试指定使用候选通道：

```bash
$ sudo snap install --candidate <name>
```

但对于日常的命令行工具和开发库，`apt` 几乎总是更好的选择。snap 更适合那些需要最新版本的图形应用（比如 VS Code、Chromium），或者需要沙盒隔离的场景。

---

### 4.3  源码编译——嵌入式开发必备技能

以编译 `htop`（一个比 `top` 更好看的进程查看器）为例，演示源码编译的完整流程。`htop` 本身用 `apt` 就能装，这里只是用它做演示——后面你在编译嵌入式工具链时会遇到完全一样的流程。

#### 第一步：安装编译依赖

```bash
$ sudo apt update
$ sudo apt install build-essential libncurses5-dev
```

`build-essential` 是一个元包（meta package），它会安装 `gcc`、`g++`、`make` 等基础编译工具。`libncurses5-dev` 是 `htop` 依赖的终端图形库的开发头文件和静态库。

如果 `./configure` 阶段报错说缺某个库，通常会提示你包名——但你需要注意，开发包的名字通常以 `-dev` 或 `-devel` 结尾。运行时库（`libncurses5`）和开发库（`libncurses5-dev`）是两个不同的包，你需要的是后者。

#### 第二步：下载源码

```bash
$ cd ~/Downloads
$ wget https://github.com/htop-dev/htop/releases/download/3.3.0/htop-3.3.0.tar.gz
$ tar xzf htop-3.3.0.tar.gz
$ cd htop-3.3.0
```

#### 第三步：配置和编译

```bash
$ ./configure
checking build system type... x86_64-pc-linux-gnu
checking for gcc... gcc
checking whether the C compiler works... yes
...
config.status: creating Makefile

$ make
gcc -c -O2 -Wall htop.c -o htop.o
gcc -c -O2 -Wall ScreenManager.c -o ScreenManager.o
...
gcc -o htop htop.o ScreenManager.o ...  -lncurses -ltinfo
```

`./configure` 输出的最后一行 `creating Makefile` 表示配置成功。如果这一步失败，它会明确告诉你缺什么——按提示安装对应的 `-dev` 包即可。

`make` 会编译所有源文件并链接成最终的可执行文件。编译完成后，当前目录下会生成一个名为 `htop` 的可执行文件。

验证一下编译结果：

```bash
$ ./htop --version
htop 3.3.0
```

#### 第四步：安装到系统路径

```bash
$ sudo make install
```

默认安装路径是 `/usr/local/bin`。这个路径已经在系统的 `PATH` 中了，安装完成后你可以在任何位置直接运行 `htop`。

```bash
$ which htop
/usr/local/bin/htop
```

#### 卸载源码编译的软件

如果你保留了编译目录，可以执行：

```bash
$ sudo make uninstall
```

但不是所有项目都提供 `uninstall` 目标。如果源码目录已经删了，你需要手动找到并删除 `/usr/local/bin/htop`、`/usr/local/share/man/man1/htop.1` 等文件。这也是源码编译的一个缺点——没有统一的卸载机制。

---

### 4.4  AppImage——下载即用

还有一种格式值得一提：**AppImage**。它不需要安装——下载一个文件，加上执行权限，直接运行。

```bash
$ wget https://github.com/neovim/neovim/releases/download/v0.9.5/nvim-linux64.appimage
$ chmod +x nvim-linux64.appimage
$ ./nvim-linux64.appimage
```

AppImage 的特点是「便携」——它不往系统目录写东西，不需要 root 权限，删掉文件就是卸载。适合那些不需要系统集成的独立工具。

---

## 练习题

走到这里，三种安装方式的机制应该清楚了。下面几道题帮你巩固认知，第三题是一道真实的嵌入式场景题。

**练习 17.1** ⭐（理解）

请解释以下命令的区别：

1. `apt update` 和 `apt upgrade`
2. `apt remove` 和 `apt purge`
3. `apt install` 和 `dpkg -i`

> **提示**：关注依赖处理能力的差异。

**练习 17.2** ⭐⭐（应用）

你需要在一台全新的 Ubuntu 22.04 上从源码编译安装一个名为 `libserial` 的串口通信库。执行 `./configure` 时报错：`checking for C++ compiler... no`。请问：

1. 需要安装哪个包来解决这个问题？
2. 写出完整的安装和编译命令序列。
3. 如果编译成功后想卸载，应该怎么做？

> **提示**：`build-essential` 元包包含 C 和 C++ 编译器。

**练习 17.3** ⭐⭐⭐（思考）

你正在为 ARM 架构的嵌入式开发板编译一个应用程序。你的主机是 x86_64 的 Ubuntu，你下载了源码并直接运行 `./configure && make`。

1. 编译出来的二进制文件能在 ARM 开发板上运行吗？为什么？
2. 如果不能，你需要做哪些改变才能让它交叉编译出 ARM 版本的二进制？
3. 在交叉编译场景中，`apt install` 还能用吗？为什么？

> **提示**：想想 `gcc` 默认编译出的是什么架构的代码。交叉编译工具链（如 `arm-linux-gnueabihf-gcc`）是如何解决架构不匹配问题的。

---

## 本章回响

本章的核心在于理解 Linux 软件安装不是「一条路走到底」，而是三条并行通道，各有各的适用场景。`apt` 是日常使用的主力——它自动解析依赖、统一管理升级、卸载干净，覆盖了绝大多数需求。`snap` 提供了跨发行版的通用包和沙盒隔离，但它的体积和国内网络问题限制了它的使用场景。源码编译是最底层的方式，也是嵌入式开发绕不开的路径——它给了你完全的控制权，但也把依赖管理和卸载的责任交给了你自己。

回到那个「中央配送系统」的类比：`apt` 是大型物流——标准化、自动化、覆盖面广，但你只能订它目录里的东西。源码编译是自己买原材料回家做——自由度最高，但费时费力，而且你得自己保证原材料齐全。

还记得开头的问题吗——`apt install`、`snap install`、源码编译，什么时候用哪个？现在你应该能回答了：日常工具用 `apt`，它最省心；需要最新版或沙盒隔离的图形应用考虑 `snap`；嵌入式工具链和定制库只能源码编译，没有别的路。

下一章我们要从软件层面跳到硬件层面——磁盘管理。当你在开发板上插入一张 SD 卡，或者给服务器加一块硬盘，Linux 怎么认出它、怎么分区、怎么格式化、怎么挂载——这些都是你在嵌入式开发中每天都会面对的操作。

---

[← 上一章](ch16-permission.md)
[下一章 →](ch18-disk.md)
