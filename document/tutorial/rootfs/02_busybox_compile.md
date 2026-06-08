# BusyBox 编译安装：一把瑞士军刀的自制指南

## 为什么要写这篇文章

上一章我们介绍了 Rootfs 的概念和各种方案。这一章，我们要真正动手把 BusyBox 编译出来。

你可能会说：编译软件有什么难的？不就是 `./configure && make && make install` 三板斧吗？

问题是，BusyBox 的编译有几个"坑"让我当初踩了好久：

第一，BusyBox 没有标准的 autotools（./configure），它用的是类似 Linux 内核的 Kconfig 系统。你得先了解 defconfig、menuconfig 这些概念。

第二，这是交叉编译！你得指定架构（ARCH）和交叉编译工具链（CROSS_COMPILE），而且 BusyBox 的 defconfig 默认开启的一些选项在 ARM 上不兼容，需要手动修复。

第三，编译产物在哪里？安装到哪里去？每次我都要去翻半天文档才搞清楚 `CONFIG_PREFIX` 是什么意思。

第四，验证！你怎么知道自己编译出来的 busybox 是对的？是 ARM 架构的吗？大小正常吗？

所以这篇文章，我会带你完整走一遍 BusyBox 的编译流程，解释每一步在做什么，为什么这么做。当你读完这篇文章，你不仅能够编译出可用的 BusyBox，更重要的是，你会理解嵌入式交叉编译的基本流程。

## BusyBox 是什么：瑞士军刀的传说

BusyBox 的官方定义是："The Swiss Army Knife of Embedded Linux"（嵌入式 Linux 的瑞士军刀）。这个比喻非常形象。

想象一把瑞士军刀：它只有把手那么大，但折叠着刀片、剪刀、锯子、开瓶器、螺丝刀等几十种工具。你需要什么功能，就展开哪个工具。

BusyBox 也是这样：它只有一个可执行文件 `busybox`，但这个文件里编译进了几百个常用命令的实现——ls、cat、cp、mv、grep、awk、sh、vi 等等。运行时，你可以通过两种方式调用：

```bash
# 方式一：通过符号链接
ls -l          # 符号链接 ls 指向 busybox，busybox 检测 argv[0] 知道要运行 ls

# 方式二：通过 applet 参数
busybox ls -l  # 直接告诉 busybox 要运行 ls
```

这种设计带来了巨大的优势：
- **体积小**：一个 1-2 MB 的文件就包含了数百个命令
- **资源共享**：所有命令共享代码库，比独立编译节省大量空间
- **部署简单**：只需要复制一个文件，创建一堆符号链接

### BusyBox 的历史

BusyBox 最早是 Bruce Perens 在 1996 年创建的，当时叫 "BusyBox" 因为它把很多工具"塞进一个盒子"。1998 年由 Erik Andersen 接手维护，2006 年后由 Denys Vlasenko 接手成为当前维护者。

当前（2026 年）的最新稳定版本是 1.37.0，IMX-Forge 项目使用的是 1.37.0 版本。

## 环境准备：工欲善其事，必先利其器

在开始编译之前，我们需要确保环境准备好了。这包括：

### 1. 主机依赖检查

BusyBox 的编译需要一些主机工具。在 Ubuntu/Debian 上，你可以这样检查：

```bash
# 检查 gcc
$ gcc --version
# 检查 make
$ make --version

# 检查 ncurses 库（menuconfig 需要）
$ dpkg -l | grep libncurses
```

> [!经验] 为什么需要 ncurses？
> menuconfig 使用 ncurses 库来绘制终端上的图形配置界面。如果你只打算用 defconfig，理论上可以不装，但强烈建议装上——因为迟早你会用到 menuconfig 来修改配置。

### 2. 交叉编译工具链检查

我们要为 ARM 编译 BusyBox，所以需要 ARM 交叉编译工具链。在 IMX-Forge 项目中，我们使用 `arm-none-linux-gnueabihf` 工具链。

### 3. BusyBox 源码准备

IMX-Forge 项目将 BusyBox 作为子模块管理，位于 `third_party/busybox/`：

```bash
# 检查源码是否存在
$ ls third_party/busybox/Makefile
third_party/busybox/Makefile

# 查看版本
$ head -5 third_party/busybox/Makefile
VERSION = 1
PATCHLEVEL = 37
SUBLEVEL = 0
```

如果源码目录不存在，记得初始化子模块：

```bash
git submodule update --init third_party/busybox
```

## BusyBox 配置系统：Kconfig 的世界

BusyBox 使用与 Linux 内核相同的 Kconfig 配置系统。这意味着它的配置方式和内核几乎一模一样。

### 配置文件层级

1. **Config.in**：源码中的配置定义，描述各个选项
2. **.config**：实际的配置文件，由配置工具生成
3. **defconfig**：默认配置模板

### 常用配置目标

| 目标 | 作用 |
|------|------|
| `defconfig` | 使用默认配置（推荐新手） |
| `menuconfig` | 图形化配置界面（推荐修改配置） |
| `config` | 基于文本的配置界面 |
| `allnoconfig` | 全部禁用（最小配置） |
| `allyesconfig` | 全部启用（最大配置） |

## 第一步：使用 defconfig 生成初始配置

我们从一个简单的配置开始——使用 defconfig 生成默认配置。

```bash
# 进入项目根目录
cd /path/to/imx-forge

# 使用项目提供的构建脚本
./scripts/build_helper/build-busybox.sh defconfig
```

这个命令实际上执行的是：

```bash
make -C third_party/busybox \
    ARCH=arm \
    CROSS_COMPILE=arm-none-linux-gnueabihf- \
    O=$(pwd)/out/busybox \
    defconfig
```

让我们分解一下这些参数：

| 参数 | 含义 |
|------|------|
| `-C third_party/busybox` | 切换到 BusyBox 源码目录执行 make |
| `ARCH=arm` | 目标架构是 ARM |
| `CROSS_COMPILE=arm-none-linux-gnueabihf-` | 交叉编译工具链前缀 |
| `O=$(pwd)/out/busybox` | 输出目录（构建产物放在这里） |
| `defconfig` | 使用默认配置 |

执行成功后，你会看到：

```
[INFO] Starting BusyBox build for arm
[INFO] Target: defconfig
========================================
[INFO] Checking host dependencies...
[INFO]   ✓ build-essential
[INFO]   ✓ libncurses-dev
[INFO] All host dependencies found
[INFO] Checking toolchain...
[INFO] Toolchain found: arm-none-linux-gnueabihf-gcc (GNU Toolchain ...) xx.x.x
[INFO] Toolchain verified
[INFO] Checking BusyBox source...
[INFO] BusyBox source: 1.37.0
[INFO] BusyBox source verified
========================================
[INFO] All checks passed
========================================
#
# configuration written to out/busybox/.config
#
```

> [!经验] 为什么使用 O= 指定输出目录？
> 将构建产物与源码分离是一个好习惯：
> 1. 源码目录保持干净，便于 git 管理
> 2. 可以维护多个不同的构建配置（O=out1, O=out2）
> 3. 清理构建产物更简单（rm -rf out/busybox）

## 第二步：ARM 兼容性修复（重要！）

这是新手最容易忽略的一步。BusyBox 的 defconfig 默认启用了某些 x86 特定的优化选项，在 ARM 上会导致编译错误。（好奇有没有大手子提个Issue的。。。我当时看到了都惊呆了，我都ARCH=arm了为啥还开着hhh）

具体来说，是这两个选项：
- `CONFIG_SHA1_HWACCEL=y`：SHA1 硬件加速（x86 特定）
- `CONFIG_SHA256_HWACCEL=y`：SHA256 硬件加速（x86 特定）

IMX-Forge 的构建脚本会自动检测并修复：

```bash
[INFO] Checking ARM-incompatible config items...
[WARN]   Disabled CONFIG_SHA1_HWACCEL (x86-only, not supported on ARM)
[WARN]   Disabled CONFIG_SHA256_HWACCEL (x86-only, not supported on ARM)
[INFO] Running oldconfig to sync patched dependencies...
```

如果你是手动编译，需要这样修复：

```bash
# 编辑 .config，禁用这两个选项
sed -i 's/^CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' out/busybox/.config
sed -i 's/^CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' out/busybox/.config

# 运行 oldconfig 同步依赖
make -C third_party/busybox ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/busybox oldconfig
```

> [!踩坑] 忘记修复会怎样？
> 编译会报类似这样的错误：
> ```
> coreutils/libcoreutils.a(libcoreutils_a-sha1.o): In function 'sha1_hash':
> sha1.c:(.text+0x38): undefined reference to 'sha1_begin_arch'
> ```
> 这个错误非常困惑，因为它只告诉你链接失败，但没说为什么。记住：遇到 undefined reference 且与 sha 相关，首先检查是否禁用了 HWACCEL。

## 第三步：编译 BusyBox

配置好之后，就可以编译了：

```bash
./scripts/build_helper/build-busybox.sh
```

或者手动执行：

```bash
make -C third_party/busybox \
    ARCH=arm \
    CROSS_COMPILE=arm-none-linux-gnueabihf- \
    O=$(pwd)/out/busybox \
    -j$(nproc)
```

`-j$(nproc)` 表示使用所有 CPU 核心并行编译，可以显著加快速度。

编译过程中你会看到大量输出：

```
[INFO] Building BusyBox (8 parallel jobs)...
[CMD] make -C third_party/busybox ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/busybox -j8
  CC      applets/applet_tables.o
  LD      applets/applet_tables
  HOSTCC  applets/usage
  GEN     include/usage_compressed.h
  CC      applets/applets.o
  LD      applets/built-in.o
  CC      archival/built-in.o
  CC      archival/libarchive/built-in.o
  CC      console-tools/built-in.o
  CC      coreutils/built-in.o
  ...
  LD      busybox_unstripped
  GEN     busybox.links
  STRIP   busybox
  COPY    busybox_unstripped
  COPY    busybox
```

关键文件的含义：
- `busybox_unstripped`：未剥离符号的版本（用于调试）
- `busybox`：剥离符号后的最终版本
- `busybox.links`：符号链接列表

编译完成后，输出的 busybox 二进制文件在 `out/busybox/busybox`。

## 第四步：验证编译产物

编译完成后，我们要验证产物是否正确：

```bash
# 使用构建脚本的验证功能
./scripts/build_helper/build-busybox.sh --install-only  # 如果已编译
# 或完整流程会自动验证
```

你会看到：

```
[INFO] Verifying build artifacts...
[INFO]   ✓ out/busybox/busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, no section header info
[INFO]     Size: 1045656 bytes
[INFO]   ✓ out/busybox/.config: present
[INFO]   ✓ rootfs/nfs/bin/busybox: installed
[INFO]     Symlinks in bin/: 315
[INFO] Build artifacts verified successfully
```

### 手动验证

你也可以手动验证, 如果使用release-all.sh编译的朋友，请检查如下路径：
```bash
# 检查文件类型
$ file out/release-latest/busybox/busybox
out/release-latest/busybox/busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, no section header info

# 检查大小
$ ls -lh out/release-latest/busybox/busybox
-rwxr-xr-x 1 user user 1.0M Mar 15 10:30 out/release-latest/busybox/busybox

# 检查架构
$ readelf -h out/release-latest/busybox/busybox | grep Machine
  Machine:   ARM
```

当然，如果是自己独立调用单独组件构建的朋友，可以自行查看打印的日志的输出位置，使用file或者是readelf指令进行查看。

> [!经验] 1MB 算大吗？
> BusyBox 的典型大小在 1-2MB 之间（静态链接）。如果你启用更多功能，可能达到 2-3MB。如果超过 5MB，可能需要检查是否不小心启用了某些大型功能（如 full vi）。

## 第五步：安装到 Rootfs

最后一步，将 BusyBox 安装到 Rootfs 目录：

```bash
# 使用项目构建脚本
./scripts/build_helper/build-busybox.sh --install-only
```

或者手动执行：

```bash
make -C third_party/busybox \
    ARCH=arm \
    CROSS_COMPILE=arm-none-linux-gnueabihf- \
    O=$(pwd)/out/busybox \
    install CONFIG_PREFIX=$(pwd)/rootfs/nfs
```

`CONFIG_PREFIX` 参数指定安装目标目录。执行后：

```
[INFO] Installing BusyBox to /path/to/imx-forge/rootfs/nfs...
[CMD] make -C third_party/busybox ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/busybox install CONFIG_PREFIX=/path/to/imx-forge/rootfs/nfs
./_install/usr/bin/ -> /path/to/imx-forge/rootfs/nfs/usr/bin/
./_install/usr/sbin/ -> /path/to/imx-forge/rootfs/nfs/usr/sbin/
./_install/bin/ -> /path/to/imx-forge/rootfs/nfs/bin/
./_install/sbin/ -> /path/to/imx-forge/rootfs/nfs/sbin/
./_install/bin/busybox -> /path/to/imx-forge/rootfs/nfs/bin/busybox
...
```

安装完成后，检查 Rootfs 目录：

```bash
$ ls rootfs/nfs/bin/
[
[[
acpid
add-shell
addgroup
adduser
...
busybox    # 主二进制文件
cat        # 符号链接 -> busybox
chmod      # 符号链接 -> busybox
...
```

```bash
# 验证符号链接
$ ls -l rootfs/nfs/bin/ls
lrwxrwxrwx 1 root root 7 Mar 15 10:30 rootfs/nfs/bin/ls -> busybox

$ file rootfs/nfs/bin/busybox
rootfs/nfs/bin/busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, no section header info
```

## 使用 menuconfig 自定义配置

当你需要添加或删除某些功能时，menuconfig 是最有用的工具。

```bash
# 启动 menuconfig
./scripts/build_helper/build-busybox.sh menuconfig
```

你会看到一个图形化的配置界面：

```
BusyBox Configuration
────────────────────────────────────────────────────────────────────────
Arrow keys navigate the menu.  <Enter> selects submenus --->.
                  Highlighted letters are hotkeys.  <Esc><Esc> exits.
                    <*> means built in.
                    <M> means module.
                    < > means excluded (not built).
────────────────────────────────────────────────────────────────────────
        Busybox Settings  --->
        Coreutils          --->
        Console Utilities  --->
        Debian Utilities   --->
        Editors            --->
        Finding Utilities  --->
        Init Utilities     --->
        Login/Password Management Utilities  --->
        Linux Ext2 FS Progs  --->
        Linux Module Utilities  --->
        Linux System Utilities  --->
        Miscellaneous Utilities  --->
        Networking Utilities  --->
        Print utilities  --->
        Mail utilities  --->
        ...
────────────────────────────────────────────────────────────────────────
      <Select>    < Exit >    < Help >    < Save >    < Load >
────────────────────────────────────────────────────────────────────────
```

### 常用配置项

1. **Settings → Build Options**
   - `Build BusyBox as a static binary`：静态链接（推荐用于 Rootfs）
   - `Cross compiler prefix`：设置交叉编译器前缀

2. **Init Utilities**
   - `init`：必须启用，系统启动需要
   - `Support for running an init from within an shell`：调试时有用

3. **Shells**
   - `ash`：推荐，功能比 sh 强，比 bash 小
   - `Feature: Editing mode`：命令行编辑功能

4. **Networking Utilities**
   - `ifconfig`：网络配置
   - `ping`：网络测试
   - `wget`：下载文件
   - `telnetd`：远程登录（调试有用）

> [!经验] 配置修改后记得重新编译
> menuconfig 退出后会自动保存 .config，但你需要重新运行编译命令：
> ```bash
> ./scripts/build_helper/build-busybox.sh --build-only
> ./scripts/build_helper/build-busybox.sh --install-only
> ```

## 常见编译问题排查

### 问题 1：工具链找不到

```
error: arm-none-linux-gnueabihf-gcc: command not found
```

**解决**：检查工具链是否在 PATH 中，或显式设置 PATH：

```bash
export PATH=/path/to/toolchain/bin:$PATH
```

### 问题 2：ncurses 头文件找不到

```
scripts/kconfig/lxdialog/dialog.h:32:10: fatal error: ncurses.h: No such file or directory
```

**解决**：安装 libncurses-dev：

```bash
sudo apt install libncurses-dev
```

### 问题 3：undefined reference 错误

```
undefined reference to 'sha1_begin_arch'
```

**解决**：检查是否禁用了 x86 特定的 HWACCEL 选项（见第二步）。

### 问题 4：配置修改不生效

**原因**：旧的 .config 残留

**解决**：使用 `--clean` 选项清理后重新编译：

```bash
./scripts/build_helper/build-busybox.sh --clean
```

## 构建脚本完整选项说明

IMX-Forge 提供的 `build-busybox.sh` 脚本支持以下选项：

```bash
Usage: ./scripts/build_helper/build-busybox.sh [TARGET] [OPTIONS]

Targets (BusyBox make targets):
  defconfig      - Default configuration (default)
  menuconfig     - Interactive curses-based configurator (exits after config, no build)
  config         - Text-based configurator (exits after config, no build)
  allnoconfig    - Disable all symbols (exits after config, no build)
  allyesconfig   - Enable all symbols (exits after config, no build)

Options:
  --clean        - Clean build directory before building
  --static       - Build static binary
  --build-only   - Build only, using existing .config
  --install-only - Install only, using existing build

Examples:
  ./scripts/build_helper/build-busybox.sh                          # Full flow: config + build + install
  ./scripts/build_helper/build-busybox.sh menuconfig               # Interactive configuration only
  ./scripts/build_helper/build-busybox.sh --build-only             # Build only using existing .config
  ./scripts/build_helper/build-busybox.sh --install-only           # Install only using existing build
  ./scripts/build_helper/build-busybox.sh --clean                  # Clean and rebuild from scratch
  ./scripts/build_helper/build-busybox.sh defconfig --clean --static  # Clean build with static binary
```

## 写在最后

通过这一章，你应该已经能够：
- 理解 BusyBox 的"瑞士军刀"设计
- 配置和交叉编译 BusyBox
- 处理 ARM 架构的兼容性问题
- 验证和安装编译产物

现在你的 Rootfs 目录中已经有了 BusyBox 及其数百个命令的符号链接。但系统还不能启动——我们还缺少关键的配置文件，特别是 inittab。

下一章，我们将深入 Linux 系统的"第一进程"——init，理解它是如何工作的，以及如何配置 inittab 让系统顺利启动。

**下一章：[inittab 与 init 系统](./03_inittab_init)**
