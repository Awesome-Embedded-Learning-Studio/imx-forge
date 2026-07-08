# build-mainline-linux.sh - 主线Linux内核构建脚本

## 脚本概述

`build-mainline-linux.sh` 是 IMX-Forge 项目中用于编译主线 Linux 内核的构建脚本。它与 `build-linux.sh` 类似，但专门针对主线内核进行配置。

### 核心功能

- **依赖自动检查**：检测并提示缺失的主机构建工具
- **工具链验证**：确保交叉编译工具链正确安装且可用
- **配置管理**：基于 defconfig 模板生成内核配置
- **固件准备**：自动获取和准备无线固件数据库
- **并行编译**：自动利用多核 CPU 加速编译
- **产物验证**：验证编译产物的架构、大小等关键指标
- **快速构建模式**：支持跳过 distclean 的增量编译

### 与 build-linux.sh 的区别

| 特性 | build-linux.sh | build-mainline-linux.sh |
|------|----------------|-------------------------|
| 内核源码 | `linux-imx` | `linux_mainline` |
| 配置文件 | `imx_aes_defconfig` | `imx_aes_mainline_defconfig` |
| 输出目录 | `out/linux` | `out/mainline/linux` |
| 固件准备 | 无 | 自动获取 wireless-regdb |

### 依赖关系

```
build-mainline-linux.sh
    ├─ scripts/lib/logging.sh (日志工具库)
    ├─ scripts/lib/progress.sh (buildmeter 进度条接入)
    ├─ third_party/linux_mainline (主线内核源码子模块)
    ├─ third_party/buildmeter (进度条工具子模块,可选)
    └─ arm-none-linux-gnueabihf-gcc (交叉编译工具链)
```

## 参数说明

### 命令行参数

```bash
./scripts/build_helper/build-mainline-linux.sh [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--fast-build` | 跳过 distclean，使用现有配置快速编译 | 禁用 |

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ARCH` | 目标架构 | `arm` |
| `CROSS_COMPILE` | 交叉编译器前缀 | `arm-none-linux-gnueabihf-` |
| `DEFCONFIG` | 内核配置文件 | `imx_aes_mainline_defconfig` |
| `DEVICE_TREE` | 目标设备树名(校验 dtb 用) | `imx6ull-aes` |
| `OUTPUT_DIR` | 编译输出目录 | `out/mainline/linux` |
| `FIRMWARE_DIR` | 固件目录 | `driver/firmwares` |
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
│     - check_defconfig()                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 构建阶段                                                 │
│     - do_distclean() [可选,--fast-build 跳过]               │
│     - prepare_defconfig()                                    │
│     - do_configure()                                         │
│     - do_build()       (buildmeter 进度条)                   │
│     - do_modules_prepare()  (备好外挂驱动构建树)             │
│     - Module.symvers 软链(备好外挂模块符号表)               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 验证阶段                                                 │
│     - verify_build_artifacts()                               │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### prepare_defconfig()

**作用**：从模板生成 defconfig 并准备固件。

**执行步骤**：

1. 从模板文件复制并替换固件目录变量
2. 克隆 wireless-regdb 仓库
3. 复制 regulatory.db 文件到固件目录

**模板路径**：

```
driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
```

**目标路径**：

```
third_party/linux_mainline/arch/arm/configs/imx_aes_mainline_defconfig
```

**固件准备**：

```bash
# 克隆无线法规数据库
git clone https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git

# 复制到固件目录
cp regulatory.db driver/firmwares/
cp regulatory.db.p7s driver/firmwares/
```

#### do_build()

**作用**：编译内核,产物为 `zImage`(压缩内核) + `dtbs`(设备树)。

**基础命令**：

```bash
make -C ${LINUX_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
    O=${OUTPUT_DIR} -j${NPROC} zImage dtbs
```

**buildmeter 进度条接入**(脚本开头顶着 `set -eo pipefail`,`source` 进 `scripts/lib/progress.sh`):

```bash
if forge_progress_enabled; then
    local total=""
    # clean build 才预扫描:make -n -k 枚举全部编译单元数当 % 分母(~15s)。
    # dry-run 在 vmlinux 链接处非零退出(预期),2>/dev/null + || true 兜。
    if [[ ${FAST_BUILD} -eq 0 ]]; then
        log_info "Pre-scanning dry-run (make -n -k) for progress total (~15s)…"
        total=$(${cmd} -n -k 2>/dev/null \
            | python3 "$FORGE_PROGRESS_PY" kernel --count-only || true)
    fi
    if [[ -n "${total}" ]]; then
        ${cmd} 2>&1 | python3 "$FORGE_PROGRESS_PY" kernel --total "${total}" --tail "$FORGE_PROGRESS_TAIL"
    else
        ${cmd} 2>&1 | python3 "$FORGE_PROGRESS_PY" kernel --tail "$FORGE_PROGRESS_TAIL"
    fi
else
    ${cmd}   # buildmeter 缺失/被禁 → 回退裸 make
fi
```

要点:

- **clean build**(`FAST_BUILD=0`):预扫描出 % 分母,bar 显真实百分比(实测欠 ~6% —— vmlinux 链接断链让 dry-run 不枚举 post-link 的 CC,但 buildmeter cap 100% + finalizing 尾部兜底,不会误读 >100%)
- **fast-build**(`--fast-build`):增量跳过预扫描,走 indeterminate(count + rate + ETA,无 %),省 15s 干预扫描税
- `pipefail`:make 失败不被 buildmeter exit-0 吞掉
- 详见 [progress.sh](../lib/progress.sh.md)

#### do_modules_prepare()

**作用**：备好构建树,让外挂(驱动)模块能 `make M=... modules` 编译。

`make zImage dtbs` **不会**生成 `scripts/module.lds`,而外挂模块的链接规则(`scripts/Makefile.modfinal`)需要它 —— 缺了 `make M=... modules` 会报 `No rule to make target '<mod>.ko'`。

**执行的命令**：

```bash
make -C ${LINUX_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
    O=${OUTPUT_DIR} modules_prepare
```

紧接其后,脚本还会确保 `Module.symvers` 存在(Linux ≥ 6.4 起 `zImage` 只吐 `vmlinux.symvers`,而外挂模块仍找 `Module.symvers`),缺失则软链过去:

```bash
[[ ! -e "${OUTPUT_DIR}/Module.symvers" && -f "${OUTPUT_DIR}/vmlinux.symvers" ]] \
    && ln -sf vmlinux.symvers "${OUTPUT_DIR}/Module.symvers"
```

#### verify_build_artifacts()

**作用**：验证编译产物是否正确。

**验证项目**：

| 产物 | 验证方法 | 期望结果 |
|------|----------|----------|
| `vmlinux` | `readelf -h \| grep Machine` | `ARM` |
| `vmlinux` | `readelf -h \| grep Entry point` | 有效入口地址 |
| `zImage` | 文件存在性 + 大小 | 存在 |
| `${DEVICE_TREE}.dtb` | 文件存在性 + 大小(`arch/arm/boot/dts/nxp/imx/`) | 存在 |
| `.config` | 文件存在性检查 | 存在 |
| `System.map` | 文件存在性检查 | 存在（可选） |
| `modules/` | 目录存在性检查 | 存在（可选） |

## 配置选项

### 硬编码配置

```bash
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
DEFCONFIG=imx_aes_mainline_defconfig
FAST_BUILD=0
DEVICE_TREE="${DEFAULT_DEVICE_TREE:-imx6ull-aes}"

LINUX_SRC_DIR="${PROJECT_ROOT}/third_party/linux_mainline"
OUTPUT_DIR="${PROJECT_ROOT}/out/mainline/linux"
```

### 目录结构

```
PROJECT_ROOT/
├── third_party/
│   └── linux_mainline/       # 主线内核源码
├── out/
│   └── mainline/
│       └── linux/            # 编译产物
│           ├── vmlinux       # ELF 内核
│           ├── System.map    # 符号表
│           ├── .config       # 配置文件
│           └── arch/arm/boot/
│               ├── Image     # 未压缩镜像
│               └── zImage    # 压缩镜像
├── driver/
│   └── firmwares/            # 固件文件
│       ├── regulatory.db
│       └── regulatory.db.p7s
└── scripts/
    └── build_helper/
        └── build-mainline-linux.sh
```

## 使用示例

### 基本用法

```bash
# 完整编译（清理 + 配置 + 编译）
./scripts/build_helper/build-mainline-linux.sh
```

### 快速编译

```bash
# 跳过 distclean，保留现有配置
./scripts/build_helper/build-mainline-linux.sh --fast-build
```

### 自定义固件目录

```bash
FIRMWARE_DIR=/path/to/firmwares ./scripts/build_helper/build-mainline-linux.sh
```

## 输出示例

```
[INFO] Starting Linux kernel build for imx_aes_mainline_defconfig
[INFO] ========================================
[INFO] Checking host dependencies...
[INFO]   ✓ build-essential
[INFO]   ✓ bc
[INFO]   ✓ bison
[INFO]   ✓ flex
[INFO]   ✓ device-tree-compiler
[INFO]   ✓ python3
[INFO]   ✓ libssl-dev
[INFO]   ✓ libgnutls28-dev
[INFO]   ✓ libncurses-dev
[INFO] All host dependencies found
[INFO] Checking toolchain...
[INFO] Toolchain found: arm-none-linux-gnueabihf-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
[INFO] All required toolchain components found
[INFO] Checking defconfig...
[INFO] Defconfig found: third_party/linux_mainline/arch/arm/configs/imx_aes_mainline_defconfig
[INFO] ========================================
[INFO] All checks passed, starting build...
[INFO] ========================================
[INFO] Preparing defconfig from template...
[INFO]   Template: driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
[INFO]   Target:   third_party/linux_mainline/arch/arm/configs/imx_aes_mainline_defconfig
[INFO]   Firmware Dir: /home/user/imx-forge/driver/firmwares
[INFO] Preparing wireless regulatory database...
[INFO]   Cloning wireless-regdb repository...
[INFO]   Copied regulatory.db to driver/firmwares/
[INFO]   Copied regulatory.db.p7s to driver/firmwares/
[INFO] Configuring Linux kernel with imx_aes_mainline_defconfig...
[CMD] make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/mainline/linux imx_aes_mainline_defconfig
[INFO] Building Linux kernel...
[CMD] make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/mainline/linux -j14 zImage dtbs
[INFO] Pre-scanning dry-run (make -n -k) for progress total (~15s)…
buildmeter
:: ▓▓▓▓▓▓▓▓▓░  91% • 3750/4125 units • 7:20 elapsed • LD arch/arm/boot/compressed/vmlinux
  LD      arch/arm/boot/compressed/vmlinux
  OBJCOPY arch/arm/boot/zImage
  Kernel: arch/arm/boot/zImage is ready
[INFO] Preparing build tree for out-of-tree modules...
[CMD] make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/mainline/linux modules_prepare
[INFO]   ✓ Module.symvers -> vmlinux.symvers (ready for out-of-tree module builds)
[INFO] ========================================
[INFO] Verifying build artifacts in out/mainline/linux...
[INFO]   ✓ vmlinux: ARM
[INFO]     Entry: 0xc0008000
[INFO]   ✓ zImage: 3245152 bytes
[INFO]   ✓ imx6ull-aes.dtb: 42118 bytes
[INFO]   ✓ .config: present
[INFO]   ✓ System.map: present
[INFO] All build artifacts verified successfully
[INFO] ========================================
[INFO] Build completed successfully!
```

## 故障排除

### 常见错误

#### 错误 1：主线内核源码不存在

```
[ERROR] 内核源码目录不存在: third_party/linux_mainline
```

**解决方法**：

确保主线内核子模块已初始化：

```bash
git submodule update --init --recursive third_party/linux_mainline
```

#### 错误 2：defconfig 模板不存在

```
[ERROR] Defconfig file not found: driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
```

**解决方法**：

检查项目配置文件是否存在：

```bash
ls driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
```

#### 错误 3：无线固件下载失败

```
[WARN]  regulatory.db not found in repository
```

**解决方法**：

检查网络连接，或手动下载：

```bash
git clone https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git
cp wireless-regdb/regulatory.db driver/firmwares/
```

## 相关文档

- [build-linux.sh](./build-linux.sh.md) - NXP BSP 内核构建脚本
- 内核配置详解 - defconfig 和 .config 的关系
- [env-init.sh](../init/env-init.sh.md) - 主机依赖检查脚本
