---
title: 编译与配置
---

# 从0开始编译 U-Boot：那些教程没告诉你的交叉编译原理和踩坑记录

## 为什么又要写一篇编译教程

你可能会问，网上 U-Boot 编译教程一堆，为什么还要写？说实话，当我第一次尝试编译 U-Boot 的时候，我也这么想。照着教程敲命令不就行了吗？

结果现实给了我一记响亮的耳光。第一个报错是缺少某个依赖包，我装上这个，编译到一半又缺另一个。第二个坑是工具链问题，我一开始用系统自带的 gcc 编译，产物根本不对。第三个坑最离谱，我改了配置文件结果完全不生效，排查了半天发现是 .config 残留导致的。产物验证更是没人教，编译完了不知道怎么确认没白忙活。

大多数教程的问题是只给命令不给原理。告诉你运行 `make xxx_defconfig`，但不解释 defconfig 是什么；告诉你用 `arm-linux-gnueabihf-gcc`，但不说为什么要用交叉编译器；告诉你编译产物是 u-boot.bin，但不教你验证架构对不对。

所以这篇文章的目标很明确：我们要完整地走一遍 U-Boot 编译流程，理解每一步在做什么、为什么要这么做、可能会遇到什么坑。到了最后，你会意识到这些步骤可以自动化，我会给你一个完整的 `build.sh` 脚本——但那时候你已经理解了脚本的每一行在做什么，而不是机械地复制粘贴。

## 我们的工作环境

先说明一下本文的环境，避免踩不必要的坑：

```
平台：Ubuntu 24.04 LTS
目标板：i.MX6ULL 14x14 EVK (eMMC)
工具链：arm-none-linux-gnueabihf-gcc
U-Boot 版本：基于 NXP uboot-imx (lf_v2025.04)
```

哦对，目标的板子是啥样，后面笔者会再出一个——以正点原子开发板为例子，如何进行正确的修改。（嗯，笔者在出差，亲爱的板子还在家里睡觉呢）。当然，环境不完全一样也没关系。Ubuntu 20.04/22.04 都可以，工具链只要是 ARM 硬浮点 ABI 的就行，版本最好是 2020 年之后的。U-Boot 版本差异主要在配置选项上，编译流程基本一致。

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
    python3 \
    python3-pyelftools \
    swig
```

我来逐项解释这些包都是干什么的。`build-essential` 是基础构建工具包，包含了 gcc、make、libc-dev 这些编译必备的东西。没有它，你连最简单的 C 程序都编不过。

`bc` 是命令行计算器，你可能觉得奇怪，编译 U-Boot 要计算器干嘛？答案在于 Kconfig 配置系统。U-Boot 的配置系统来自 Linux 内核，而内核的 Kconfig 脚本会用到 bc 进行数值计算。没有 bc，make menuconfig 的时候会报错。

`bison` 和 `flex` 是语法分析器生成工具，用编译原理的话说就是"词法分析器和语法分析器生成器"。U-Boot 需要解析 Kconfig 配置文件和设备树文件，这两者都需要 bison 和 flex。你可能会在编译错误信息里看到 "missing bison" 或 "missing flex"，这就是缺这两个包的表现。

`libssl-dev` 和 `libgnutls28-dev` 是加密库开发文件。U-Boot 支持 FIT Image 格式，这是一种带签名的镜像格式，用于安全启动。还支持加密的环境变量存储。这些功能需要 OpenSSL 或 GnuTLS 库。如果你不需要这些功能，理论上可以不装，但为了避免编译到一半报错，建议还是装上。

`libncurses-dev` 是 ncurses 库的开发文件。ncurses 是一个终端图形库，make menuconfig 这种文本配置界面就是用它做的。没有它，你就没法用图形界面配置 U-Boot。

`device-tree-compiler` 也就是 dtc，是设备树编译器。U-Boot 需要把 .dts 设备树源文件编译成 .dtb 二进制文件。虽然 U-Boot 源码里自带了一个 dtc，但系统安装一个版本更稳定，而且可以用于验证编译产物。

`python3` 和 `python3-pyelftools` 是 Python 环境和 ELF 文件解析库。U-Boot 的某些构建脚本是用 Python 写的，pyelftools 用于分析 ELF 文件格式。虽然不是严格必需，但装上可以避免一些奇怪的问题。

`swig` 是 Simplified Wrapper and Interface Generator，用于把 C/C++ 代码包装成其他语言（比如 Python）的接口。U-Boot 的某些工具需要它，不装的话编译可能会失败。

## 理解交叉编译：为什么不能直接用 gcc

现在我们来到第一个核心概念：交叉编译。很多新手在这里卡住，不明白为什么不能用系统的 gcc 直接编译。

问题很简单：你的开发机是 x86_64 架构的，而 U-Boot 要跑在 ARM 架构的板子上。x86 的 CPU 跑不了 ARM 指令，反之亦然。所以我们需要一个能运行在 x86 上、但生成 ARM 代码的编译器——这就是交叉编译器。

交叉编译器的命名规则是有规律的。以 `arm-none-linux-gnueabihf-gcc` 为例：

- `arm` 是目标架构
- `none` 表示没有厂商（非嵌入式工具链）
- `linux` 是目标操作系统
- `gnueabihf` 是 GNU EABI 硬浮点 ABI

这里重点解释一下 `gnueabihf`。ARM 有两种浮点 ABI：软浮点（gnueabi）和硬浮点（gnueabihf）。软浮点模式下，浮点运算用软件模拟，函数调用时整数和浮点参数都通过通用寄存器传递。硬浮点模式下，浮点运算用硬件 FPU 执行，浮点参数通过浮点寄存器传递。i.MX6ULL 有硬件 FPU，所以我们要用硬浮点工具链，性能更好。

获取交叉编译工具有几种方式。一种是直接从 ARM 官网下载预构建的工具链，另一种是用 Ubuntu 的包管理器安装（比如 `gcc-arm-linux-gnueabihf`），还有一种是自己用 crosstool-NG 编译。对于初学者，推荐用前两种，省时省力。

安装好后，你可以用这个命令验证：

```bash
arm-none-linux-gnueabihf-gcc --version
```

如果输出了版本信息，说明工具链在 PATH 里，可以正常使用。

## 第一步：distclean——为什么要清理

现在我们终于可以开始编译了。第一步是清理旧的编译产物：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- distclean
```

这里解释一下这两个变量的作用。`ARCH=arm` 告诉 U-Boot 目标架构是 ARM，它会在 `arch/arm/` 目录下找架构相关代码。`CROSS_COMPILE=arm-none-linux-gnueabihf-` 指定交叉编译器前缀，U-Boot 会用 `arm-none-linux-gnueabihf-gcc` 编译 C 文件，用 `arm-none-linux-gnueabihf-ld` 链接，以此类推。

`distclean` 目标会删除所有编译生成的文件，包括 .config 配置文件。为什么要这么做？因为编译产物可能会"污染"后续编译。最典型的例子就是 .config 残留：你改了 defconfig，但旧的 .config 还在，make 的时候可能会优先用 .config，导致你的修改不生效。所以，如果你准备总的确认你的修改是有效的，请distclean一笔勾销之前的编译产物。

如果你确信需要保留某些配置，可以用 `make clean` 只删除编译产物，不删 .config。但对于第一次编译，建议还是用 distclean。

## 第二步：defconfig——配置的魔法

清理完成后，我们需要配置 U-Boot：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- mx6ull_14x14_evk_emmc_defconfig
```

这个命令背后的机制比很多人想象的复杂。`configs/` 目录下有 500 多个 defconfig 文件，每个文件代表一种板型或配置组合。defconfig 不是 .config 的完整复制，它只存储与默认值不同的配置选项。举个例子，如果某个配置项默认是 n，板子需要它设为 y，defconfig 里就只会记录 `CONFIG_XXX=y`。

当你运行 `make xxx_defconfig` 时，U-Boot 会做这几件事：加载指定的 defconfig，处理 Kconfig 文件（评估所有配置符号、依赖和默认值），最后生成完整的 .config 文件。所以 .config 是 defconfig + Kconfig 系统共同作用的结果，不是简单的复制粘贴。

配置文件的位置是 `configs/mx6ull_14x14_evk_emmc_defconfig`，你可以打开看看内容：

```
CONFIG_TARGET_MX6ULL_14X14_EVK=y
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-14x14-evk-emmc"
CONFIG_MX6ULL=y
...
```

每一行都是一个配置选项。如果你想修改配置，可以用 `make menuconfig` 打开图形界面，或者直接编辑 .config 文件。但要注意，直接编辑 .config 可能会被 menuconfig 覆盖，推荐还是用 menuconfig。

配置完成后，.config 文件会出现在源码根目录。这个文件是编译时实际使用的配置，包含了完整的配置信息（默认值 + 板级特定设置）。

## 第三步：make——并行编译的威力

配置完成后，终于可以编译了：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)
```

`-j$(nproc)` 这个参数很重要。`nproc` 命令会输出 CPU 核心数，`-j` 告诉 make 可以并行运行这么多任务。现代 CPU 都是多核的，不利用并行编译就太浪费了。我电脑配置好，基本上nproc一下，我手碰到桌子另一端的杯子拿回来喝一口水之后，编译就完成了。

编译过程做了这些事情：编译 C 源文件生成 .o 目标文件，链接生成 u-boot ELF 文件，用 objcopy 转换格式生成 u-boot.bin 纯二进制，编译设备树生成 u-boot.dtb，最后打包成 u-boot-dtb.imx 镜像。

编译完成后，你会在源码根目录看到这些文件：

- `u-boot`：ELF 格式的可执行文件，带调试信息，大约 6MB。这个文件可以用于调试，但不能直接烧录。
- `u-boot.bin`：纯二进制格式，去掉了 ELF 头和调试信息，大约 600KB。这个是可以直接烧录到板子上的文件。
- `u-boot-nodtb.bin`：不带设备树的二进制文件。U-Boot 支持运行时加载设备树，这个文件用于这种场景。
- `u-boot.dtb`：设备树 blob，编译后的二进制格式设备树，大约 30KB。
- `u-boot-dtb.bin`：u-boot-nodtb.bin 和 u-boot.dtb 的简单拼接。
- `u-boot-dtb.imx`：NXP i.MX 专用格式，在 u-boot-dtb.bin 的基础上加了 IVT（Image Vector Table）头。

这里重点解释一下 u-boot-dtb.imx。NXP i.MX 系列芯片的 Boot ROM 有特殊要求，它要求镜像开头有一个 IVT 头，里面包含了镜像的入口地址、DCD（Device Configuration Data）等信息。没有这个头，Boot ROM 不识别镜像，启动会失败。`tools/mkimage` 工具就是用来生成这种格式的。

## 产物验证：如何确认编译没白忙活

编译完成了，但我们还不能高兴得太早。你需要验证产物是否正确，不然烧到板子上发现起不来，排查起来更麻烦。

### 架构检查：用 readelf 看清真相

首先检查架构是否正确：

```bash
readelf -h u-boot | grep Machine
```

你应该看到类似这样的输出：

```
Machine: ARM
```

如果不是 ARM，说明你用错了工具链，白忙活了。我见过有人用 aarch64 工具链编译 armv7 代码，产物架构不对，板子上当然跑不起来。

除了架构，还可以看入口地址：

```bash
readelf -h u-boot | grep "Entry point"
```

输出类似：

```
Entry point address: 0x87800000
```

这个地址是 U-Boot 在内存中的加载位置。i.MX6ULL 的 DDR 起始地址是 0x80000000，U-Boot 加载到 0x87800000，这个值是在链接脚本里定义的。

### 设备树验证：dtc 反编译

接下来验证设备树是否正确：

```bash
dtc -I dtb -O dts u-boot.dtb | grep fsl,imx6ull
```

你应该能看到类似这样的输出：

```
compatible = "fsl,imx6ull";
```

如果看不到 imx6ull 的字样，说明设备树可能选错了。设备树选错的后果很严重：板子能启动，但外设全认不出来，串口有输出但网络、存储都不工作。这个在之后，就是我们的魔改工作。

### iMX 镜像验证：mkimage 工具

最后验证一下 u-boot-dtb.imx 的格式：

```bash
./tools/mkimage -l u-boot-dtb.imx
```

你应该能看到类似这样的输出：

```
Image Type:   ARM Linux Firmware Image (uncompressed)
Data Size:    613888 Bytes = 599.50 KiB = 0.59 MiB
Load Address: 87800000
Entry Point:  87800000
```

这个输出告诉我们镜像的类型、大小、加载地址和入口点。如果这些值不对，说明 mkimage 打包出了问题。

## 总结成脚本：方便起见，我们把它自动化

到这里，你应该已经掌握了 U-Boot 编译的完整流程。但每次都要敲这么多命令，确实有点累。而且容易出错，比如忘了 distclean 导致配置不生效，或者 ARCH 和 CROSS_COMPILE 写错了。

所以我们把这些步骤总结成一个脚本。下面是完整的 `build.sh`，我加了依赖检查和产物验证，确保每一步都不会出错：

```bash
#!/bin/bash
#
# U-Boot build script for mx6ull_14x14_evk_emmc
#

set -e

# Configuration
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
DEFCONFIG=mx6ull_14x14_evk_emmc_defconfig
DEFAULT_DEVICE_TREE="imx6ull-14x14-evk-emmc"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Get number of CPU cores for parallel build
NPROC=$(nproc)
log_info "Using ${NPROC} parallel jobs"

# Check host dependencies
check_host_dependencies() {
    log_info "Checking host dependencies..."

    MISSING_PKGS=()
    FOUND_PKGS=()

    # Helper: check if command exists
    check_cmd() {
        local cmd=$1
        local pkg=$2
        if command -v ${cmd} &> /dev/null; then
            FOUND_PKGS+=("${pkg}")
            return 0
        else
            MISSING_PKGS+=("${pkg}")
            return 1
        fi
    }

    # Check build tools
    check_cmd gcc build-essential || true
    check_cmd make build-essential || true
    check_cmd bc bc || true
    check_cmd bison bison || true
    check_cmd flex flex || true
    check_cmd dtc device-tree-compiler || true
    check_cmd python3 python3 || true
    check_cmd swig swig || true

    # Check libraries via dpkg
    if dpkg -s libssl-dev &> /dev/null; then
        FOUND_PKGS+=("libssl-dev")
    else
        MISSING_PKGS+=("libssl-dev")
    fi

    if dpkg -s libgnutls28-dev &> /dev/null || [ -f /usr/include/gnutls/gnutls.h ]; then
        FOUND_PKGS+=("libgnutls28-dev")
    else
        MISSING_PKGS+=("libgnutls28-dev")
    fi

    if dpkg -s libncurses-dev &> /dev/null || [ -f /usr/include/ncursesw/ncurses.h ] || [ -f /usr/include/ncurses/ncurses.h ]; then
        FOUND_PKGS+=("libncurses-dev")
    else
        MISSING_PKGS+=("libncurses-dev")
    fi

    # Check pyelftools Python module
    if python3 -c "import elftools" 2>/dev/null; then
        FOUND_PKGS+=("python3-pyelftools")
    else
        MISSING_PKGS+=("python3-pyelftools")
    fi

    # Remove duplicates
    FOUND_PKGS=($(echo "${FOUND_PKGS[@]}" | tr ' ' '\n' | sort -u))
    MISSING_PKGS=($(echo "${MISSING_PKGS[@]}" | tr ' ' '\n' | sort -u))

    # Display results
    for pkg in "${FOUND_PKGS[@]}"; do
        log_info "  ✓ ${pkg}"
    done

    for pkg in "${MISSING_PKGS[@]}"; do
        log_warn "  ✗ ${pkg} (not found)"
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${MISSING_PKGS[*]}"
        echo ""
        log_info "Install missing packages with:"
        echo -e "  ${YELLOW}sudo apt install ${MISSING_PKGS[*]}${NC}"
        echo ""
        exit 1
    fi

    log_info "All host dependencies found"
}

# Check if toolchain exists
check_toolchain() {
    log_info "Checking toolchain..."

    if ! command -v ${CROSS_COMPILE}gcc &> /dev/null; then
        log_error "Cross compiler '${CROSS_COMPILE}gcc' not found!"
        log_error "Please ensure the toolchain is installed and in your PATH"
        exit 1
    fi

    GCC_VERSION=$(${CROSS_COMPILE}gcc --version | head -n1)
    log_info "Toolchain found: ${GCC_VERSION}"

    for tool in objcopy objdump strip; do
        if ! command -v ${CROSS_COMPILE}${tool} &> /dev/null; then
            log_error "Tool '${CROSS_COMPILE}${tool}' not found!"
            exit 1
        fi
    done

    log_info "All required toolchain components found"
}

# Check if device tree exists
check_device_tree() {
    log_info "Checking device tree..."

    DTS_FILE="arch/arm/dts/${DEFAULT_DEVICE_TREE}.dts"

    if [ ! -f "${DTS_FILE}" ]; then
        log_error "Device tree file not found: ${DTS_FILE}"
        exit 1
    fi

    log_info "Device tree found: ${DTS_FILE}"

    BASE_DTS="arch/arm/dts/imx6ull-14x14-evk.dts"
    if [ -f "${BASE_DTS}" ]; then
        log_info "Base device tree found: ${BASE_DTS}"
    fi
}

# Check if defconfig exists
check_defconfig() {
    log_info "Checking defconfig..."

    DEFCONFIG_FILE="configs/${DEFCONFIG}"

    if [ ! -f "${DEFCONFIG_FILE}" ]; then
        log_error "Defconfig file not found: ${DEFCONFIG_FILE}"
        exit 1
    fi

    log_info "Defconfig found: ${DEFCONFIG_FILE}"
}

# Clean build
do_distclean() {
    log_info "Running distclean..."
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} distclean
}

# Configure U-Boot
do_configure() {
    log_info "Configuring U-Boot with ${DEFCONFIG}..."
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} ${DEFCONFIG}
}

# Build U-Boot
do_build() {
    log_info "Building U-Boot..."
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j${NPROC}
}

# Verify build artifacts
verify_build_artifacts() {
    log_info "Verifying build artifacts..."

    local has_error=0

    # Check ELF file
    if [ -f u-boot ]; then
        local readelf_cmd="${CROSS_COMPILE}readelf"
        if ! command -v ${readelf_cmd} &> /dev/null; then
            readelf_cmd="readelf"
        fi

        if command -v ${readelf_cmd} &> /dev/null; then
            ARCH_INFO=$(${readelf_cmd} -h u-boot 2>/dev/null | grep "Machine:" | awk '{print $2}')
            if [[ "${ARCH_INFO}" == *"ARM"* ]]; then
                log_info "  ✓ u-boot: ${ARCH_INFO}"
                ENTRY_ADDR=$(${readelf_cmd} -h u-boot 2>/dev/null | grep "Entry point" | awk '{print $4}')
                if [ -n "${ENTRY_ADDR}" ]; then
                    log_info "    Entry: 0x${ENTRY_ADDR}"
                fi
            else
                log_error "  ✗ u-boot: Wrong architecture (${ARCH_INFO})"
                has_error=1
            fi
        fi
    else
        log_error "  ✗ u-boot: not found"
        has_error=1
    fi

    # Check binary file
    if [ -f u-boot.bin ]; then
        SIZE=$(stat -c%s u-boot.bin 2>/dev/null || stat -f%z u-boot.bin 2>/dev/null)
        log_info "  ✓ u-boot.bin: ${SIZE} bytes"
    else
        log_error "  ✗ u-boot.bin: not found"
        has_error=1
    fi

    # Check device tree blob
    if [ -f u-boot.dtb ]; then
        if command -v dtc &> /dev/null; then
            DTS_INFO=$(dtc -I dtb -O dts u-boot.dtb 2>/dev/null | grep -E "compatible|fsl,imx6ull" | head -3)
            if [[ "${DTS_INFO}" == *"fsl,imx6ull"* ]] || [[ "${DTS_INFO}" == *"imx6ull-14x14-evk"* ]]; then
                log_info "  ✓ u-boot.dtb: i.MX6ULL device tree detected"
            else
                log_info "  ✓ u-boot.dtb: present"
            fi
        else
            DTB_SIZE=$(stat -c%s u-boot.dtb 2>/dev/null || stat -f%z u-boot.dtb 2>/dev/null)
            log_info "  ✓ u-boot.dtb: ${DTB_SIZE} bytes"
        fi
    else
        log_error "  ✗ u-boot.dtb: not found"
        has_error=1
    fi

    # Check iMX image
    if [ -f u-boot-dtb.imx ]; then
        if [ -f ./tools/mkimage ]; then
            IMX_INFO=$(./tools/mkimage -l u-boot-dtb.imx 2>/dev/null | grep "Image Type")
            if [ -n "${IMX_INFO}" ]; then
                log_info "  ✓ u-boot-dtb.imx: ${IMX_INFO}"
            else
                SIZE=$(stat -c%s u-boot-dtb.imx 2>/dev/null || stat -f%z u-boot-dtb.imx 2>/dev/null)
                log_info "  ✓ u-boot-dtb.imx: ${SIZE} bytes"
            fi
        fi
    fi

    if [ ${has_error} -eq 0 ]; then
        log_info "All build artifacts verified successfully"
        return 0
    else
        log_error "Build artifact verification failed"
        return 1
    fi
}

# Main build process
main() {
    log_info "Starting U-Boot build for ${DEFCONFIG}"
    log_info "========================================"

    # Pre-build checks
    check_host_dependencies
    check_toolchain
    check_device_tree
    check_defconfig

    log_info "========================================"
    log_info "All checks passed, starting build..."
    log_info "========================================"

    # Build process
    do_distclean
    do_configure
    do_build

    log_info "========================================"

    # Verify build artifacts
    verify_build_artifacts || exit 1

    log_info "========================================"
    log_info "Build completed successfully!"

    log_info "Output files summary:"
    [ -f u-boot.bin ] && log_info "  - u-boot.bin"
    [ -f u-boot-dtb.bin ] && log_info "  - u-boot-dtb.bin"
    [ -f u-boot-dtb.imx ] && log_info "  - u-boot-dtb.imx (for i.MX boot)"
    [ -f u-boot.dtb ] && log_info "  - u-boot.dtb"
    [ -f u-boot.srec ] && log_info "  - u-boot.srec"

    log_info "========================================"
}

# Run main function
main "$@"
```

这个脚本做了几件事：检查主机依赖、检查交叉编译工具链、检查设备树和 defconfig 文件是否存在、执行 distclean/configure/build 三阶段编译、最后验证编译产物。每一步都有日志输出，出错时能快速定位。

使用方法很简单：

```bash
chmod +x build.sh
./build.sh
```

## 写在最后

到这里，U-Boot 编译的完整流程你就掌握了。从手动敲命令到理解每个步骤的含义，从排查错误到自动化脚本，我们走完了整个旅程。

编译不是黑魔法，每一步都有它的原因。distclean 是为了避免缓存毒药，defconfig 是通过 Kconfig 生成配置，make -j$(nproc) 是利用多核加速，产物验证是确保没白忙活。当你理解了这些，你就不是在机械地复制命令，而是在掌控整个构建过程。

但编译只是第一步。下一篇文章，我们将进入 U-Boot 移植的核心环节——板级配置。你会看到如何创建属于自己的板型定义，如何配置 board/ 目录和 include/configs/ 目录，如何让 U-Boot 知道它运行在什么样的硬件上。那是一个从"能编译"到"能运行"的关键跨越。

