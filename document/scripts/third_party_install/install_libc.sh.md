# install_libc.sh - libc 库安装脚本详解

## 脚本概述

`install_libc.sh` 是 IMX-Forge 项目中用于将交叉编译工具链的 libc 库文件复制到根文件系统的脚本。它是构建可运行 rootfs 的关键步骤之一，确保目标系统能够正确运行动态链接的程序。

### 核心功能

- **自动检测工具链路径**：智能定位交叉编译工具链的库目录
- **多路径搜索**：支持多种常见的工具链安装位置
- **sysroot 自动发现**：通过 gcc 查询 sysroot 路径
- **批量库文件复制**：复制 `.a` 静态库和 `.so` 动态库文件
- **目录结构创建**：自动创建 `/lib` 和 `/usr/lib` 目录
- **文件统计报告**：显示复制的库文件数量和目录大小

### 为什么需要这个脚本

在交叉编译场景下，构建主机（通常是 x86_64 Linux）为目标架构（如 ARM）编译程序。这些程序在运行时需要依赖目标架构的 C 标准库（libc）。

```
┌─────────────────────────────────────────────────────────────────┐
│  问题场景                                                         │
├─────────────────────────────────────────────────────────────────┤
│  1. 在 x86_64 主机上使用 arm-none-linux-gnueabihf-gcc 编译程序   │
│  2. 编译生成的 ARM 二进制文件动态链接到 libc.so                   │
│  3. 将二进制文件放到 ARM 板子上运行                               │
│  4. 如果板子的 rootfs 中没有对应的 libc.so，程序无法启动！         │
└─────────────────────────────────────────────────────────────────┘
```

这个脚本解决了上述问题：它将工具链中的库文件复制到 rootfs，确保目标系统有运行程序所需的完整依赖。

### 设计理念

脚本遵循"自动化但灵活"的原则：

1. **自动优先**：首先尝试自动定位工具链库目录
2. **多路径回退**：如果自动检测失败，尝试多个常见位置
3. **优雅降级**：如果全部失败，给出详细提示并跳过（不强制中断）
4. **最小侵入**：使用 `cp -d` 保留符号链接，不修改文件内容

### 依赖关系

```
install_libc.sh
    ├─ arm-none-linux-gnueabihf-gcc (交叉编译器，用于查询 sysroot)
    └─ ROOTFS_DIR (根文件系统目录)
```

调用关系：

```
varified_rootfs_ok.sh
    └─ install_libc.sh (被调用)
```

## 技术背景

### 什么是 libc

libc（C Standard Library）是 C 语言标准库的实现，提供了 POSIX 标准定义的核心函数：

| 分类 | 主要函数 |
|------|----------|
| 字符串操作 | `strcpy`, `strlen`, `strcmp`, `memcpy` |
| 内存管理 | `malloc`, `free`, `calloc`, `realloc` |
| I/O 操作 | `printf`, `scanf`, `fopen`, `fread` |
| 数学函数 | `sin`, `cos`, `sqrt`, `abs` |
| 系统调用 | `open`, `read`, `write`, `fork`, `exec` |
| 线程操作 | `pthread_create`, `pthread_join` |

### 常见的 libc 实现

| 实现 | 说明 | 使用场景 |
|------|------|----------|
| glibc | GNU C Library，功能最全 | 大多数 Linux 发行版 |
| uClibc | 轻量级，面向嵌入式 | 嵌入式 Linux |
| musl libc | 轻量、安全、快速 | Alpine Linux, 嵌入式 |
| newlib | 面向裸机和嵌入式系统 | bare-metal, RTOS |

IMX-Forge 使用的是基于 glibc 的工具链（`arm-none-linux-gnueabihf`）。

### 动态链接与静态链接

**动态链接**：
- 程序不包含库代码，只包含引用
- 运行时需要 `.so` 文件在 rootfs 中
- 优点：体积小，多个程序可共享同一库

**静态链接**：
- 库代码被编译进程序
- 运行时不需要外部 `.so` 文件
- 优点：独立运行，但体积大

大多数嵌入式系统使用动态链接以节省空间，因此需要正确的 libc 文件。

### sysroot 概念

sysroot（system root）是指包含目标系统库和头文件的目录，它的结构模拟目标系统的根目录：

```
sysroot/
├── lib/
│   ├── libc.so.6
│   ├── libm.so.6
│   ├── ld-linux-armhf.so.3
│   └── ...
├── usr/
│   └── lib/
│       ├── libpthread.so.0
│       └── ...
└── usr/include/
    └── (头文件)
```

当使用交叉编译器时，`--sysroot` 选项告诉编译器去哪里找目标系统的库和头文件：

```bash
arm-none-linux-gnueabihf-gcc --sysroot=/path/to/sysroot hello.c
```

这个脚本利用 `gcc -print-sysroot` 命令来查找工具链的 sysroot。

## 使用方法

### 基本用法

脚本通常由 `varified_rootfs_ok.sh` 自动调用，但也可以独立运行：

```bash
# 使用默认 rootfs 路径 (../rootfs/nfs)
./scripts/third_party_install/install_libc.sh

# 指定 rootfs 路径
ROOTFS_DIR=out/rootfs ./scripts/third_party_install/install_libc.sh

# 同时指定工具链库目录
TOOLCHAIN_LIB_DIR=/usr/arm-linux-gnueabihf/lib \
  ROOTFS_DIR=out/rootfs \
  ./scripts/third_party_install/install_libc.sh
```

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ROOTFS_DIR` | 根文件系统目录路径 | `../rootfs/nfs` |
| `TOOLCHAIN_LIB_DIR` | 工具链库目录（自动检测） | 自动检测 |
| `CROSS_COMPILE` | 交叉编译器前缀 | `arm-none-linux-gnueabihf-` |

### 输出格式

脚本使用带颜色和前缀的输出格式：

```
[install_libc] Installing libc libraries to: rootfs/nfs
[install_libc] Found toolchain library directory: /usr/arm-linux-gnueabihf/lib
[install_libc] Copying library files...
[install_libc]   Copying to lib/...
[install_libc]     Copied 127 library files to lib/
[install_libc]   Copying to usr/lib/...
[install_libc]     Copied 89 library files to usr/lib/
[install_libc] Library installation complete!
[install_libc]   /lib size:  45M
[install_libc]   /usr/lib size: 32M
```

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  1. 初始化阶段                                               │
│     - 设置颜色变量                                           │
│     - 定义日志函数                                           │
│     - 设置默认参数                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 预检查阶段                                               │
│     - 检查 ROOTFS_DIR 是否存在                               │
│     - 如果不存在，报错退出                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 工具链定位阶段                                           │
│     - 尝试预设路径列表                                        │
│     - 尝试 gcc -print-sysroot                                │
│     - 如果失败，显示提示并跳过                                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 目录准备阶段                                             │
│     - 创建 ${ROOTFS_DIR}/lib                                 │
│     - 创建 ${ROOTFS_DIR}/usr/lib                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. 库文件复制阶段                                           │
│     - 复制 .a 和 .so 文件到 lib/                             │
│     - 复制 usr/lib 中的库文件                                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  6. 统计报告阶段                                             │
│     - 计算复制的文件数量                                      │
│     - 计算目录大小                                           │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### 日志函数

脚本定义了三个内嵌的日志函数：

```bash
log_info()  { echo -e "${GREEN}[install_libc]${NC} $1"; }
log_error() { echo -e "${RED}[install_libc]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[install_libc]${NC} $1"; }
```

**设计说明**：

- 使用 `[install_libc]` 前缀区分其他脚本的输出
- 颜色编码：绿色（信息）、红色（错误）、黄色（警告）
- `log_error` 输出到 stderr（`>&2`）

#### 工具链路径检测

脚本使用多阶段检测策略：

**阶段 1：预设路径列表**

```bash
TOOLCHAIN_LIB_DIRS=(
    "/usr/lib/${CROSS_COMPILE}gcc"
    "/usr/${CROSS_COMPILE}/lib"
    "/usr/arm-linux-gnueabihf/lib"
    "/usr/arm-none-linux-gnueabihf/lib"
    "/opt/${CROSS_COMPILE}/lib"
    "/usr/local/lib/${CROSS_COMPILE}"
)
```

这些路径覆盖了常见的工具链安装位置：

| 路径 | 说明 | 发行版 |
|------|------|--------|
| `/usr/lib/${CROSS_COMPILE}gcc` | Ubuntu/Debian 新版本 | Ubuntu 20.04+ |
| `/usr/${CROSS_COMPILE}/lib` | Ubuntu/Debian 旧版本 | Ubuntu 18.04 |
| `/usr/arm-linux-gnueabihf/lib` | Arch Linux | Arch |
| `/opt/${CROSS_COMPILE}/lib` | 手动安装 | 通用 |

**阶段 2：gcc 查询**

```bash
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot 2>/dev/null || echo "")
```

`gcc -print-sysroot` 返回编译器的 sysroot 路径，这是最可靠的方式。

**阶段 3：用户干预**

如果自动检测失败，脚本显示友好提示：

```
[install_libc] Could not automatically locate toolchain library directory
[install_libc] Please specify the path to your cross-compiler's library directory
[install_libc] Common locations:
[install_libc]   - /usr/lib/arm-none-linux-gnueabihfgcc
[install_libc]   - /usr/arm-none-linux-gnueabihf/lib
...
[install_libc] For now, skipping libc installation (you can copy libraries manually)
```

注意：脚本以 `exit 0` 退出，不是 `exit 1`，允许后续构建继续。

#### 目录创建

```bash
mkdir -p "${ROOTFS_DIR}/lib"
mkdir -p "${ROOTFS_DIR}/usr/lib"
```

使用 `-p` 参数确保：
- 父目录不存在时自动创建
- 目录已存在时不报错

#### 库文件复制

**复制到 lib/**：

```bash
find "${TOOLCHAIN_LIB_DIR}" -maxdepth 1 \
    \( -name "*.a" -o -name "*.a.*" -o -name "*.so" -o -name "*.so.*" \) \
    -print0 2>/dev/null | \
xargs -0 -I {} cp -d {} "${ROOTFS_DIR}/lib/" 2>/dev/null
```

**命令详解**：

| 部分 | 作用 |
|------|------|
| `find ... -maxdepth 1` | 只搜索当前目录，不递归 |
| `-name "*.a"` | 静态库文件 |
| `-name "*.a.*"` | 版本化的静态库（罕见） |
| `-name "*.so"` | 动态库链接文件 |
| `-name "*.so.*"` | 版本化的动态库（如 libc.so.6） |
| `-print0` | 用 null 字符分隔（处理带空格的文件名） |
| `xargs -0 -I {}` | 读取 null 分隔的输入 |
| `cp -d` | 复制时不解引用符号链接 |

**为什么使用 `cp -d`**：

`-d` 参数等价于 `--no-dereference`，保留符号链接：

```bash
# 没有 -d：复制链接指向的文件
$ cp libfoo.so rootfs/lib/
# 结果：复制了实际的 libfoo.so.1.0 文件

# 使用 -d：复制链接本身
$ cp -d libfoo.so rootfs/lib/
# 结果：复制了符号链接 libfoo.so -> libfoo.so.1
```

这对于动态链接很重要，因为 `.so` 文件通常是符号链接。

**复制到 usr/lib/**：

```bash
if [[ -d "${TOOLCHAIN_LIB_DIR}/../usr/lib" ]]; then
    USR_LIB_DIR="$(cd "${TOOLCHAIN_LIB_DIR}/../usr/lib" && pwd)"
    # 复制逻辑相同...
fi
```

注意 `$(cd ... && pwd)` 的用法：先进入目录获取绝对路径，避免相对路径问题。

#### 统计报告

```bash
LIB_COUNT=$(find "${ROOTFS_DIR}/lib" -maxdepth 1 -type f \
    \( -name "*.a" -o -name "*.so*" \) 2>/dev/null | wc -l)

LIB_SIZE=$(du -sh "${ROOTFS_DIR}/lib" 2>/dev/null | cut -f1)
```

- `wc -l`：统计行数（即文件数量）
- `du -sh`：计算目录大小（人类可读格式）
- `cut -f1`：提取大小字段

## 配置选项

### 硬编码配置

脚本开头定义了以下配置：

```bash
CROSS_COMPILE=arm-none-linux-gnueabihf-
: "${ROOTFS_DIR:=../rootfs/nfs}"
```

### 工具链前缀

默认使用 `arm-none-linux-gnueabihf-`，这是 NXP i.MX 系列常用的工具链。

如果要支持其他架构，可以修改这个变量或通过环境变量覆盖：

```bash
# 使用不同的工具链
CROSS_COMPILE=aarch64-linux-gnu- ./install_libc.sh
```

## 目录结构

### 工具链库目录结构

典型的工具链库目录结构：

```
/usr/arm-linux-gnueabihf/
├── lib/
│   ├── libc.so.6              -> libc-2.31.so
│   ├── libc-2.31.so           # 实际文件
│   ├── libm.so.6              -> libm-2.31.so
│   ├── libpthread.so.0        -> libpthread-2.31.so
│   ├── ld-linux-armhf.so.3    -> ld-2.31.so
│   ├── libgcc_s.so.1
│   ├── libstdc++.so.6         -> libstdc++.so.6.0.28
│   └── ...
└── usr/lib/
    ├── libgfortran.so.5
    ├── libssp.so.0
    └── ...
```

### rootfs 目标结构

执行后，rootfs 目录结构：

```
rootfs/nfs/
├── lib/
│   ├── libc.so.6
│   ├── libc-2.31.so
│   ├── libm.so.6
│   ├── libpthread.so.0
│   ├── ld-linux-armhf.so.3
│   └── ...
└── usr/lib/
    ├── libstdc++.so.6
    ├── libgcc_s.so.1
    └── ...
```

## 使用示例

### 场景 1：正常执行

```bash
$ ./scripts/third_party_install/install_libc.sh
[install_libc] Installing libc libraries to: ../rootfs/nfs
[install_libc] Found toolchain library directory: /usr/arm-linux-gnueabihf/lib
[install_libc] Copying library files...
[install_libc]   Copying to lib/...
[install_libc]     Copied 127 library files to lib/
[install_libc]   Copying to usr/lib/...
[install_libc]     Copied 89 library files to usr/lib/
[install_libc] Library installation complete!
[install_libc]   /lib size:  45M
[install_libc]   /usr/lib size: 32M
```

### 场景 2：工具链未找到

```bash
$ ./scripts/third_party_install/install_libc.sh
[install_libc] Installing libc libraries to: ../rootfs/nfs
[install_libc] Could not automatically locate toolchain library directory
[install_libc] Please specify the path to your cross-compiler's library directory
[install_libc]
[install_libc] Common locations:
[install_libc]   - /usr/lib/arm-none-linux-gnueabihfgcc
[install_libc]   - /usr/arm-none-linux-gnueabihf/lib
[install_libc]   - /usr/arm-linux-gnueabihf/lib
[install_libc]   - /usr/arm-none-linux-gnueabihf/lib
[install_libc]   - /opt/arm-none-linux-gnueabihf-/lib
[install_libc]   - /usr/local/lib/arm-none-linux-gnueabihf-
[install_libc]
[install_libc] You can set TOOLCHAIN_LIB_DIR environment variable and run again
[install_libc]
[install_libc] For now, skipping libc installation (you can copy libraries manually)
```

解决方法：

```bash
# 检查工具链是否安装
which arm-none-linux-gnueabihf-gcc

# 手动指定路径
TOOLCHAIN_LIB_DIR=/custom/path/to/lib ./install_libc.sh
```

### 场景 3：rootfs 目录不存在

```bash
$ ROOTFS_DIR=/nonexistent ./install_libc.sh
[install_libc] Installing libc libraries to: /nonexistent
[install_libc] Rootfs directory not found: /nonexistent
```

解决方法：

```bash
# 先创建 rootfs 目录
mkdir -p out/rootfs
ROOTFS_DIR=out/rootfs ./install_libc.sh
```

## 故障排除

### 常见错误

#### 错误 1：rootfs 目录不存在

```
[install_libc] Rootfs directory not found: /path/to/rootfs
```

**原因**：指定的 `ROOTFS_DIR` 不存在

**解决方法**：

```bash
# 创建目录
mkdir -p out/rootfs

# 重新运行
ROOTFS_DIR=out/rootfs ./install_libc.sh
```

#### 错误 2：工具链库目录未找到

```
[install_libc] Could not automatically locate toolchain library directory
```

**原因**：

1. 交叉编译工具链未安装
2. 工具链安装在非标准位置

**解决方法**：

```bash
# 检查工具链是否安装
which arm-none-linux-gnueabihf-gcc

# 查询 sysroot
arm-none-linux-gnueabihf-gcc -print-sysroot

# 手动指定并运行
TOOLCHAIN_LIB_DIR=/usr/arm-linux-gnueabihf/lib \
  ROOTFS_DIR=out/rootfs \
  ./install_libc.sh
```

#### 错误 3：复制了 0 个文件

```
[install_libc]     No library files found or copy failed
```

**原因**：

1. 工具链库目录为空
2. 权限不足
3. 路径不正确

**解决方法**：

```bash
# 检查源目录
ls -la /usr/arm-linux-gnueabihf/lib/

# 检查权限
ls -ld out/rootfs/lib

# 手动复制测试
sudo cp -d /usr/arm-linux-gnueabihf/lib/*.so* out/rootfs/lib/
```

#### 错误 4：程序在目标板上运行失败

```
# 在板子上运行
./hello
./hello: No such file or directory
```

**原因**：缺少动态链接器或库文件

**解决方法**：

```bash
# 检查程序依赖
arm-none-linux-gnueabihf-readelf -d hello | grep NEEDED

# 确保以下文件存在于 rootfs：
# - ld-linux-armhf.so.3 (动态链接器)
# - libc.so.6 (C 库)
# - 其他依赖库

# 重新运行 install_libc.sh
./install_libc.sh
```

### 调试技巧

#### 查看复制的库文件

```bash
# 列出所有 .so 文件
find rootfs/nfs/lib -name "*.so*"

# 检查动态链接器
ls -l rootfs/nfs/lib/ld-linux*

# 检查 libc
ls -l rootfs/nfs/lib/libc.so*
```

#### 验证库文件架构

```bash
# 检查库文件架构
file rootfs/nfs/lib/libc.so.6
# 应显示：ELF 32-bit LSB shared object, ARM, EABI5 version 1

# 如果显示 x86-64，说明复制了错误的库
```

#### 检查符号链接

```bash
# 查看符号链接目标
ls -l rootfs/nfs/lib/libc.so.6
# 应显示：libm.so.6 -> libc-2.31.so

# 检查目标文件是否存在
ls -l rootfs/nfs/lib/libc-2.31.so
```

## 设计决策说明

### 为什么使用 find + xargs 而不是 cp -r

脚本使用：

```bash
find ... -print0 | xargs -0 -I {} cp -d {} "${ROOTFS_DIR}/lib/"
```

而不是简单的：

```bash
cp -r "${TOOLCHAIN_LIB_DIR}"/*.so* "${ROOTFS_DIR}/lib/"
```

**原因**：

1. **更精确的文件选择**：`find` 可以精确匹配文件类型和名称模式
2. **处理特殊文件名**：`-print0` 和 `xargs -0` 正确处理带空格的文件名
3. **符号链接处理**：`cp -d` 保留符号链接
4. **错误容忍**：`2>/dev/null` 让命令在部分失败时继续

### 为什么复制 .a 静态库

`.a` 文件是静态库，通常只在编译时需要，运行时不需要。但脚本仍然复制它们，原因：

1. **完整性**：提供完整的开发环境
2. **板载编译**：某些场景需要在目标板上编译程序
3. **大小考虑**：rootfs 大小通常不是主要限制

如果需要节省空间，可以修改脚本只复制 `.so*` 文件：

```bash
find ... -name "*.so*" -print0 | xargs -0 -I {} cp -d {} "${ROOTFS_DIR}/lib/"
```

### 为什么既复制 lib/ 又复制 usr/lib/

这是 FHS（Filesystem Hierarchy Standard）的要求：

- `/lib`：核心库，系统启动必需
- `/usr/lib`：其他库，应用程序使用

某些工具链将库放在这两个位置，脚本都处理以确保完整性。

### 为什么找不到库时继续执行而不是失败

脚本在找不到工具链库时执行 `exit 0` 而不是 `exit 1`：

```bash
if [[ -z "$TOOLCHAIN_LIB_DIR" ]]; then
    log_warn "..."
    exit 0  # 不是 exit 1
fi
```

**原因**：

1. **允许手动干预**：用户可以手动复制库文件
2. **不阻塞构建**：libc 安装失败不应阻止其他步骤
3. **灵活性**：某些场景可能不需要这个步骤

这是一个"尽力而为"的设计。

## 扩展和定制

### 支持新的工具链

如果使用不同的交叉编译器：

```bash
# 方法1：修改脚本
CROSS_COMPILE=aarch64-linux-gnu-

# 方法2：环境变量
CROSS_COMPILE=aarch64-linux-gnu- ./install_libc.sh
```

同时需要修改搜索路径列表：

```bash
TOOLCHAIN_LIB_DIRS=(
    "/usr/lib/${CROSS_COMPILE}gcc"
    "/usr/${CROSS_COMPILE}/lib"
    "/usr/aarch64-linux-gnu/lib"  # 添加新架构
    ...
)
```

### 添加文件过滤

如果只想复制特定库：

```bash
# 只复制 C 库和数学库
find "${TOOLCHAIN_LIB_DIR}" -maxdepth 1 \
    \( -name "libc*" -o -name "libm*" \) \
    -print0 | xargs -0 -I {} cp -d {} "${ROOTFS_DIR}/lib/"
```

### 排除调试文件

如果需要排除调试符号文件：

```bash
find "${TOOLCHAIN_LIB_DIR}" -maxdepth 1 \
    -name "*.so*" \
    ! -name "*.debug" \
    -print0 | xargs -0 -I {} cp -d {} "${ROOTFS_DIR}/lib/"
```

### 添加验证步骤

添加库文件完整性检查：

```bash
# 在复制后添加
log_info "Verifying copied libraries..."

if [[ ! -L "${ROOTFS_DIR}/lib/ld-linux-armhf.so.3" ]]; then
    log_error "Dynamic linker not found!"
    exit 1
fi

if [[ ! -f "${ROOTFS_DIR}/lib/libc.so.6" ]]; then
    log_error "libc not found!"
    exit 1
fi

log_info "All critical libraries present"
```

## 相关概念

### 动态链接过程

当运行动态链接的程序时：

```
1. 内核加载程序，读取 ELF �头部
2. 读取 INTERP 字段，找到动态链接器 (ld-linux.so)
3. 加载动态链接器
4. 动态链接器读取 NEEDED 条目
5. 依次加载所需的共享库 (libc.so, libm.so, ...)
6. 解析符号引用
7. 将控制权交给程序入口点
```

如果任何一步失败（如找不到库），程序无法运行。

### 动态链接器

动态链接器本身也是一个共享库：

```
/lib/ld-linux-armhf.so.3  # ARM 硬浮点
/lib/ld-linux.so.3        # ARM 软浮点
/lib64/ld-linux-x86-64.so.2  # x86_64
```

它负责：
- 加载程序依赖的共享库
- 解析符号引用
- 执行初始化代码
- 传递控制权给程序

**为什么动态链接器也在 rootfs 中**：

它是程序运行的第一步，必须在 rootfs 中可用。

### 符号版本化

glibc 使用符号版本化来保持 ABI 兼容性：

```
libc.so.6 -> libc-2.31.so
```

程序可以链接到特定版本的符号，即使 glibc 更新也能继续工作。

这就是为什么 `install_libc.sh` 使用 `cp -d` 保留符号链接——符号链接是版本化机制的关键部分。

## 相关文档

- 构建根文件系统 - rootfs 构建概述
- 动态链接详解 - 动态链接原理
- 交叉编译工具链 - 工具链使用
- [varified_rootfs_ok.sh](../varified_rootfs_ok.sh) - 调用此脚本的上级脚本
