# build-uboot.sh - U-Boot构建脚本详解

## 脚本概述

`build-uboot.sh` 是 IMX-Forge 项目中用于编译 U-Boot 引导加载程序的核心构建脚本。它自动化了从依赖检查、工具链验证、设备树检查到 U-Boot 配置、编译和产物验证的完整流程。

### 核心功能

- **依赖自动检查**：检测并提示缺失的主机构建工具（包括 U-Boot 特有的 swig、pyelftools）
- **工具链验证**：确保交叉编译工具链正确安装且可用
- **设备树验证**：检查目标设备树源文件是否存在
- **Logo 准备**：自动调用 logo_helper 生成启动 Logo
- **配置管理**：基于 defconfig 生成 U-Boot 配置
- **并行编译**：自动利用多核 CPU 加速编译
- **产物验证**：验证 U-Boot 镜像的架构、格式等关键指标

### 设计理念

U-Boot 的构建比 Linux 内核更复杂，因为它需要生成多种格式的镜像文件，每种格式有不同的用途。这个脚本的设计重点是：

1. **全面的检查**：除了常规的构建工具，还检查设备树文件
2. **产物多样性验证**：验证 u-boot、u-boot.bin、u-boot.dtb、u-boot-dtb.imx 等多种产物
3. **Logo 集成**：自动准备启动 Logo
4. **i.MX 特定格式**：特别验证 u-boot-dtb.imx（NXP i.MX 系列要求的格式）

### 依赖关系

```
build-uboot.sh
    ├─ scripts/lib/logging.sh (日志工具库)
    ├─ scripts/init/env-init.sh (依赖检查库) ← 新增
    ├─ scripts/logo_helper/logo_helper.sh (Logo 生成工具)
    ├─ third_party/uboot-imx (U-Boot 源码子模块)
    └─ arm-none-linux-gnueabihf-gcc (交叉编译工具链)
```

如果 `logging.sh` 不可用，脚本会使用内嵌的备用日志函数。

## 参数说明

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ARCH` | 目标架构 | `arm` |
| `CROSS_COMPILE` | 交叉编译器前缀 | `arm-none-linux-gnueabihf-` |
| `DEFCONFIG` | U-Boot 配置文件 | `mx6ull_aes_emmc_defconfig` |
| `DEFAULT_DEVICE_TREE` | 默认设备树名称 | `imx6ull-14x14-evk-emmc` |
| `DEBUG` | 启用调试输出 | `0` |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  1. 初始化阶段                                               │
│     - 获取脚本路径                                           │
│     - 设置项目根目录                                         │
│     - 加载日志库                                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 预检查阶段                                               │
│     - check_host_dependencies()                              │
│     - check_toolchain()                                      │
│     - check_device_tree()                                    │
│     - check_defconfig()                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. Logo 准备阶段                                            │
│     - 调用 logo_helper.sh                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 构建阶段                                                 │
│     - do_distclean()                                        │
│     - do_configure()                                        │
│     - do_build()                                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. 验证阶段                                                 │
│     - verify_build_artifacts()                               │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### check_host_dependencies()

**作用**：检查主机系统是否安装了所有必需的构建工具。

**实现方式**：

通过导入 `scripts/init/env-init.sh`，调用 `check_uboot_dependencies()` 函数实现依赖检查：

```bash
source "${SCRIPT_DIR}/../init/env-init.sh"
check_uboot_dependencies || exit 1
```

**U-Boot 特有依赖**：

与 Linux 内核构建脚本相比，U-Boot 构建需要额外的工具：

| 工具/库 | 用途 | U-Boot 特有 |
|---------|------|-------------|
| `swig` | C/C++ 到其他语言的接口生成器 | 是 |
| `python3-pyelftools` | ELF 文件解析库 | 是 |
| `libssl-dev` | 加密库（FIT Image 签名） | 是 |
| `libgnutls28-dev` | 加密库 | 是 |
| `imagemagick` | Logo 图片转换 | 是 |

**检查项目**：

```bash
# 基础工具
gcc, make, bc, bison, flex, dtc, python3

# U-Boot 特有工具
swig, imagemagick

# Python 模块检查
python3-pyelftools (通过 python3 -c "import elftools" 检查)

# 库文件
libssl-dev, libgnutls28-dev, libncurses-dev
```

**输出示例**：

```
[INFO] 检查 U-Boot 依赖包...
[INFO]   ✓ build-essential
[INFO]   ✓ bc
[INFO]   ✓ bison
[INFO]   ✓ flex
[INFO]   ✓ device-tree-compiler
[INFO]   ✓ python3
[INFO]   ✓ swig
[INFO]   ✓ libssl-dev
[INFO]   ✓ libgnutls28-dev
[INFO]   ✓ libncurses-dev
[INFO]   ✓ python3-pyelftools
[INFO]   ✓ imagemagick
[INFO] All U-Boot dependencies found
```

**详细的依赖检查逻辑**：

请参考以下文档：
- env-init.sh 源码
- 环境初始化指南

#### check_toolchain()

**作用**：验证交叉编译工具链是否正确安装。

**检查流程**：

1. 检查 `${CROSS_COMPILE}gcc` 是否存在
2. 显示工具链版本信息
3. 检查 `objcopy`、`objdump`、`strip` 等配套工具

**输出示例**：

```
[INFO] Checking toolchain...
[INFO] Toolchain found: arm-none-linux-gnueabihf-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
[INFO] All required toolchain components found
```

#### check_device_tree()

**作用**：验证目标设备树源文件是否存在。

**检查路径**：

```
${UBOOT_SRC_DIR}/arch/arm/dts/${DEFAULT_DEVICE_TREE}.dts
```

对于默认配置，完整路径是：

```
third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk-emmc.dts
```

**同时检查基础设备树**：

脚本还会检查基础设备树文件 `imx6ull-14x14-evk.dts` 是否存在，因为 eMMC 版本通常继承自基础版本。

**输出示例**：

```
[INFO] Checking device tree...
[INFO] Device tree found: third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk-emmc.dts
[INFO] Base device tree found: third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk.dts
```

#### check_defconfig()

**作用**：验证指定的 defconfig 文件是否存在。

**检查路径**：

```
${UBOOT_SRC_DIR}/configs/${DEFCONFIG}
```

对于默认配置，完整路径是：

```
third_party/uboot-imx/configs/mx6ull_aes_emmc_defconfig
```

#### do_distclean()

**作用**：清理旧的编译产物，确保干净的构建环境。

**实现方式**：

```bash
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
```

与 Linux 内核脚本相同，直接删除输出目录而不是运行 `make distclean`。

#### do_configure()

**作用**：使用 defconfig 配置 U-Boot。

**执行的命令**：

```bash
make -C ${UBOOT_SRC_DIR} \
    ARCH=${ARCH} \
    CROSS_COMPILE=${CROSS_COMPILE} \
    O=${OUTPUT_DIR} \
    ${DEFCONFIG}
```

**输出结果**：

在 `${OUTPUT_DIR}` 目录生成 `.config` 文件。

#### do_build()

**作用**：编译 U-Boot。

**执行的命令**：

```bash
make -C ${UBOOT_SRC_DIR} \
    ARCH=${ARCH} \
    CROSS_COMPILE=${CROSS_COMPILE} \
    O=${OUTPUT_DIR} \
    -j${NPROC}
```

**编译过程**：

1. 编译 U-Boot 源文件 → 生成 `.o` 目标文件
2. 链接生成 `u-boot` ELF 文件
3. 用 objcopy 转换格式生成 `u-boot.bin`
4. 编译设备树生成 `u-boot.dtb`
5. 使用 mkimage 打包生成 `u-boot-dtb.imx`

#### verify_build_artifacts()

**作用**：验证编译产物是否正确。

**验证项目**：

| 产物 | 验证方法 | 期望结果 |
|------|----------|----------|
| `u-boot` | `readelf -h \| grep Machine` | `ARM` |
| `u-boot` | `readelf -h \| grep Entry point` | `0x87800000` |
| `u-boot.bin` | 文件存在性 + 大小检查 | 存在 |
| `u-boot.dtb` | `dtc -I dtb -O dts` + 内容检查 | 包含 `fsl,imx6ull` |
| `u-boot-dtb.imx` | `mkimage -l` 格式检查 | i.MX Image |

**输出示例**：

```
[INFO] Verifying build artifacts in out/uboot...
[INFO]   ✓ u-boot: ARM
[INFO]     Entry: 0x87800000
[INFO]   ✓ u-boot.bin: 613888 bytes
[INFO]   ✓ u-boot.dtb: i.MX6ULL device tree detected
[INFO]   ✓ u-boot-dtb.imx: Image Type: ARM Linux Firmware Image (uncompressed)
[INFO] All build artifacts verified successfully
```

### U-Boot 产物说明

#### u-boot

ELF 格式的可执行文件，带调试信息，大约 6MB。主要用于调试，不能直接烧录。

#### u-boot.bin

纯二进制格式，去掉了 ELF 头和调试信息，大约 600KB。可以直接烧录到板子上。

#### u-boot-nodtb.bin

不带设备树的二进制文件。U-Boot 支持运行时加载设备树。

#### u-boot.dtb

设备树 blob，编译后的二进制格式设备树，大约 30KB。

#### u-boot-dtb.bin

`u-boot-nodtb.bin` 和 `u-boot.dtb` 的简单拼接。

#### u-boot-dtb.imx

**NXP i.MX 专用格式**，在 `u-boot-dtb.bin` 的基础上加了 IVT（Image Vector Table）头。

NXP i.MX 系列芯片的 Boot ROM 有特殊要求，它要求镜像开头有一个 IVT 头，里面包含：

- 镜像的入口地址
- DCD（Device Configuration Data）
- Boot 参数

没有这个头，Boot ROM 不识别镜像，启动会失败。

`tools/mkimage` 工具用于生成这种格式。

## 配置选项

### 硬编码配置

```bash
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
DEFCONFIG=mx6ull_aes_emmc_defconfig
DEFAULT_DEVICE_TREE="imx6ull-14x14-evk-emmc"

UBOOT_SRC_DIR="${PROJECT_ROOT}/third_party/uboot-imx"
OUTPUT_DIR="${PROJECT_ROOT}/out/uboot"
```

### 目录结构

```
PROJECT_ROOT/
├── third_party/
│   └── uboot-imx/                    # U-Boot 源码（子模块）
│       ├── arch/arm/dts/
│       │   └── imx6ull-14x14-evk-emmc.dts
│       └── configs/
│           └── mx6ull_aes_emmc_defconfig
├── out/
│   └── uboot/                        # 编译产物
│       ├── u-boot                    # ELF 文件
│       ├── u-boot.bin                # 纯二进制
│       ├── u-boot.dtb                # 设备树
│       └── u-boot-dtb.imx            # i.MX 格式镜像
├── document/
│   └── logo/
│       └── logo.png                  # 启动 Logo 源文件
└── scripts/
    ├── build_helper/
    │   └── build-uboot.sh            # 本脚本
    └── logo_helper/
        └── logo_helper.sh            # Logo 生成工具
```

## 使用示例

### 基本用法

```bash
# 完整编译
./scripts/build_helper/build-uboot.sh
```

### 调试模式

```bash
# 启用调试输出
DEBUG=1 ./scripts/build_helper/build-uboot.sh
```

### 输出示例

```
[INFO] Starting U-Boot build for mx6ull_aes_emmc_defconfig
[INFO] ========================================
[INFO] Checking host dependencies...
[INFO]   ✓ build-essential
[INFO]   ✓ bc
[INFO]   ✓ bison
[INFO]   ✓ flex
[INFO]   ✓ device-tree-compiler
[INFO]   ✓ python3
[INFO]   ✓ swig
[INFO]   ✓ libssl-dev
[INFO]   ✓ libgnutls28-dev
[INFO]   ✓ libncurses-dev
[INFO]   ✓ python3-pyelftools
[INFO] All host dependencies found
[INFO] Checking toolchain...
[INFO] Toolchain found: arm-none-linux-gnueabihf-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
[INFO] All required toolchain components found
[INFO] Checking device tree...
[INFO] Device tree found: third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk-emmc.dts
[INFO] Base device tree found: third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk.dts
[INFO] Checking defconfig...
[INFO] Defconfig found: third_party/uboot-imx/configs/mx6ull_aes_emmc_defconfig
[INFO] ========================================
[INFO] All checks passed, starting build...
[INFO] ========================================
[INFO] Preparing logo...
[INFO] Running distclean... Using Remove All as to make all clear!
[INFO]   Removing out/uboot
[INFO] Configuring U-Boot with mx6ull_aes_emmc_defconfig...
[CMD] make -C third_party/uboot-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/uboot mx6ull_aes_emmc_defconfig
#
# configuration written to out/uboot/.config
#
[INFO] Building U-Boot...
[CMD] make -C third_party/uboot-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/uboot -j8
  CC      arch/arm/lib/asm.o
  CC      arch/arm/lib/cache.o
  ...
  LD      u-boot
  OBJCOPY u-boot.bin
  SHIPPED u-boot.dtb
  MKIMAGE u-boot-dtb.imx
[INFO] ========================================
[INFO] Verifying build artifacts in out/uboot...
[INFO]   ✓ u-boot: ARM
[INFO]     Entry: 0x87800000
[INFO]   ✓ u-boot.bin: 613888 bytes
[INFO]   ✓ u-boot.dtb: i.MX6ULL device tree detected
[INFO]   ✓ u-boot-dtb.imx: Image Type: ARM Linux Firmware Image (uncompressed)
[INFO] All build artifacts verified successfully
[INFO] ========================================
[INFO] Build completed successfully!
[INFO] ========================================
[INFO] Flashable artifacts in out/uboot:
[INFO]   ✓ u-boot-dtb.imx (for i.MX boot)
[INFO]   ✓ u-boot-dtb.bin
[INFO]   ✓ u-boot.dtb
[INFO] ========================================
```

## 故障排除

### 常见错误

#### 错误 1：缺少 swig

```
[ERROR] Missing dependencies: swig
```

**解决方法**：

```bash
sudo apt install swig
```

**说明**：swig 是 U-Boot 构建所需的工具，用于生成某些语言绑定。

#### 错误 2：缺少 pyelftools

```
[ERROR] Missing dependencies: python3-pyelftools
```

**解决方法**：

```bash
sudo apt install python3-pyelftools
```

**说明**：pyelftools 用于解析 ELF 文件，U-Boot 的某些构建脚本需要它。

#### 错误 3：设备树文件不存在

```
[ERROR] Device tree file not found: third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk-emmc.dts
```

**可能原因**：

1. U-Boot 子模块未初始化
2. 设备树名称不正确

**解决方法**：

```bash
# 初始化子模块
git submodule update --init --recursive

# 检查可用的设备树
ls third_party/uboot-imx/arch/arm/dts/imx6ull*.dts
```

#### 错误 4：mkimage 格式检查失败

```
[ERROR] Build artifact verification failed
```

**可能原因**：

1. u-boot-dtb.imx 生成失败
2. mkimage 工具问题

**解决方法**：

```bash
# 手动检查 mkimage
./third_party/uboot-imx/tools/mkimage -l out/uboot/u-boot-dtb.imx

# 手动重新生成
./third_party/uboot-imx/tools/mkimage -A arm -O linux -T firmware \
    -C none -a 0x87800000 -e 0x87800000 -n "U-Boot" \
    -d out/uboot/u-boot.bin out/uboot/u-boot.imx
```

#### 错误 5：Logo 生成失败

```
[ERROR] Failed to generate logo
```

**解决方法**：

确保 Logo 文件存在：

```bash
ls -la document/logo/logo.png
```

如果不存在，准备一个 800x480 的 PNG 文件。

## 设计决策说明

### 为什么需要设备树验证

U-Boot 的设备树配置非常关键。如果设备树选错了，可能导致：

1. 无法启动
2. 外设无法识别
3. 内存配置错误

脚本在编译前检查设备树文件是否存在，可以避免编译后发现选错了。

### 为什么特别验证 u-boot-dtb.imx

NXP i.MX 系列芯片的 Boot ROM 要求特定的镜像格式。普通的 u-boot.bin 无法直接启动，必须经过 mkimage 处理添加 IVT 头。

脚本特别验证这个文件，确保最终产物可以直接烧录到板子上。

### Logo 准备的时机

Logo 准备在 distclean 之后、configure 之前进行。这样做的理由：

1. Logo 文件需要被编译进 U-Boot
2. distclean 会删除旧的产物
3. 在 configure 之前准备好，确保编译时能找到

### 与 Linux 内核构建脚本的区别

| 特性 | build-linux.sh | build-uboot.sh |
|------|----------------|----------------|
| 设备树验证 | 无 | 有 |
| Logo 准备 | 无 | 有 |
| 验证产物数量 | 3 个 | 4+ 个 |
| 特殊格式验证 | 无 | u-boot-dtb.imx |
| 快速构建模式 | 支持 | 不支持 |

## 扩展和定制

### 添加新的板型支持

要支持新的板型：

1. 在 U-Boot 源码中创建新的 defconfig 和设备树
2. 修改脚本中的配置变量

```bash
# 编辑脚本
vim scripts/build_helper/build-uboot.sh

# 修改这些行
DEFCONFIG=my_board_defconfig
DEFAULT_DEVICE_TREE="imx6ull-my-board"
```

### 修改 Logo 尺寸

如果需要不同的 Logo 尺寸：

```bash
# 编辑脚本，找到这一行
"${SCRIPT_DIR}/../logo_helper/logo_helper.sh" 800x480 document/logo/logo.png third_party/uboot-imx/tools/logos/denx.bmp

# 修改尺寸参数
"${SCRIPT_DIR}/../logo_helper/logo_helper.sh" 1024x600 document/logo/logo.png third_party/uboot-imx/tools/logos/denx.bmp
```

### 禁用 Logo

如果不需要 Logo，可以注释掉 Logo 准备部分：

```bash
# 准备 logo before build
# log_info "Preparing logo..."
# "${SCRIPT_DIR}/../logo_helper/logo_helper.sh" 800x480 document/logo/logo.png third_party/uboot-imx/tools/logos/denx.bmp
```

## 相关文档

- U-Boot编译教程 - U-Boot 编译的详细原理
- 板级配置基础 - U-Boot 板级配置
- [Linux内核构建脚本](./build-linux.sh) - 对比的 Linux 内核构建脚本
- [Logo 处理](../logo_helper/logo_helper.sh.md) - Logo 生成工具文档
