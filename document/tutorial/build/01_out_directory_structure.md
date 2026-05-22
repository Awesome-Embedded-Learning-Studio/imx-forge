# out/ 目录结构完全指南

笔者之前有使用的朋友在私下反馈到——我不知道我的构建产物放到哪里了，随后发现自己真的没有说明过这些事情。这里特别的补充一些文档到这里。

## 前言：构建产物都去哪了

如果你已经跑过一次完整的构建（这里说的完整的构建，就是跑了一次 `./scripts/release-all.sh`，它会依次按照顺序，构建好 uboot、linux 和 rootfs 等相关产物），你会发现项目根目录下突然多了一个 `out/` 目录，里面有一些构建产物。第一次看到这个目录结构时，我承认可能真的不太好搞明白这些是啥。

---

## 环境说明

在开始之前，确保你已经至少执行过一次完整构建：

```bash
cd /home/charliechen/imx-forge
./scripts/release-all.sh
```

如果还没构建过，先去跑一遍，不然 `out/` 目录很多东西都不存在，看这一章也没什么意义。

---

## 目录结构总览

先来个全貌感受一下。执行完 `./scripts/release-all.sh` 后，`out/` 目录大致长这样：

```bash
tree -L 2 out/
```

萌新提示：如果您没有安装 tree，可能就会出这样的神秘问题

```zsh
❯ tree -L 2 out
zsh: command not found: tree
```

你会看到类似这样的输出：

```
out/
├── firmwares/              # 无线电法规数据库
├── release-latest/         # 最新版本的完整构建产物
└── third_party/            # 第三方库构建产物（如 Qt6）
```

**核心逻辑**：`out/` 目录主要存放两类内容——第三方库构建产物和 Release 构建目录。理解这个分类，目录结构就不那么混乱了。

---

## 两种构建模式

在深入目录结构之前，需要理解 IMX-Forge 有两种不同的构建模式：

### 1. 单独组件构建（Individual Build）

当你只想构建某个特定组件时，可以单独运行对应的构建脚本：

```bash
# 单独构建 U-Boot
export OUTPUT_DIR=out/uboot
./scripts/build_helper/build-uboot.sh

# 单独构建 Linux 内核
export OUTPUT_DIR=out/linux
./scripts/build_helper/build-linux.sh

# 单独构建 BusyBox
export OUTPUT_DIR=out/busybox
./scripts/build_helper/build-busybox.sh
```

这种模式下，构建产物会输出到：
- `out/uboot/`
- `out/linux/`
- `out/busybox/`

**适用场景**：开发调试阶段，只需要修改和重新编译某个组件时。

### 2. 完整 Release 构建（Release Build）

这是推荐的构建方式，会构建所有组件并打包成一个完整的发行版：

```bash
./scripts/release-all.sh
```

这种模式下，所有组件的构建产物都会整合到 `out/release-latest/` 目录下：

```
out/release-latest/
├── uboot/        # U-Boot 编译产物
├── linux/        # Linux 内核编译产物
├── busybox/      # BusyBox 编译产物
├── rootfs/       # 完整的根文件系统
└── images/       # 符号链接目录，方便找到要烧录的文件
```

**适用场景**：需要完整构建所有组件，准备烧录到目标板子时。

**注意**：本文档主要介绍 Release 构建模式（`release-all.sh`）产生的目录结构，因为这是最常用的使用方式。

---

## Release 构建目录详解

### out/release-latest/ —— 完整构建产物

`release-latest/` 目录存放的是完整 Release 构建的所有产物。每次运行 `./scripts/release-all.sh`，都会更新这个目录。

让我们看看里面都有什么：

```bash
ls -la out/release-latest/
```

你会看到：

```
drwxr-xr-x 7 user user 4096 May 22 15:50 .
drwxr-xr-x 5 user user 4096 May 22 15:43 ..
drwxr-xr-x 31 user user 4096 May 22 15:50 busybox
drwxr-xr-x  2 user user 4096 May 22 15:50 images
drwxr-xr-x 21 user user 4096 May 22 15:50 linux
drwxr-xr-x 14 user user 4096 May 22 15:50 rootfs
drwxr-xr-x 19 user user 4096 May 22 15:43 uboot
```

---

### out/release-latest/uboot/ —— U-Boot 构建输出

这个目录存放 U-Boot 的编译产物。

让我们看看里面都有什么：

```bash
ls -lh out/release-latest/uboot/ | grep -E "^-|u-boot"
```

你会看到这些关键文件：

| 文件 | 大小 | 说明 | 用途 |
|------|------|------|------|
| `u-boot` | ~6.9MB | ELF 格式可执行文件 | 调试时用，带符号表 |
| `u-boot.bin` | ~1.7MB | 纯二进制文件 | 中间产物，不含设备树 |
| `u-boot.dtb` | ~36KB | 设备树二进制文件 | 硬件配置描述 |
| `u-boot-dtb.imx` | ~1.7MB | i.MX 专用镜像格式 | **这是你要烧录的文件** |
| `System.map` | ~109KB | 符号地址映射 | 调试分析用 |
| `u-boot.sym` | ~222KB | 符号表 | 调试分析用 |

**踩坑经验**：很多新手会错误地烧录 `u-boot.bin`，结果板子起不来。记住，`u-boot-dtb.imx` 才是 NXP i.MX 平台的正确格式——它已经把设备树打包进去了。

**验证一下你的 U-Boot 镜像是否正确**：

```bash
cd out/release-latest/uboot
file u-boot-dtb.imx
```

应该看到：

```
u-boot-dtb.imx: data
```

虽然显示为 `data`，但这是正常的——i.MX 格式在文件类型识别里比较特殊。

---

### out/release-latest/linux/ —— Linux 内核构建输出

内核的编译产物比 U-Boot 复杂一些，主要文件分散在几个子目录里。

**核心文件位置**：

```bash
# 主目录下的关键文件
ls -lh out/release-latest/linux/ | grep -E "^-|vmlinux|System.map"
```

| 文件 | 位置 | 说明 | 用途 |
|------|------|------|------|
| `vmlinux` | `out/release-latest/linux/` | 未压缩内核 ELF 文件 | 调试用，带符号表 |
| `System.map` | `out/release-latest/linux/` | 内核符号表 | 地址解析调试 |
| `.config` | `out/release-latest/linux/` | 内核配置文件 | 查看编译选项 |
| `zImage` | `out/release-latest/linux/arch/arm/boot/` | **压缩内核镜像** | **这是你要烧录的文件** |
| `Image` | `out/release-latest/linux/arch/arm/boot/` | 未压缩内核镜像 | 可选的烧录文件 |
| `*.dtb` | `out/release-latest/linux/arch/arm/boot/dts/nxp/imx/` | 设备树文件 | 根据板子型号选择 |

**找到你的设备树文件**：

```bash
ls out/release-latest/linux/arch/arm/boot/dts/nxp/imx/ | grep imx6ull
```

你应该会看到类似：

```
imx6ull-14x14-evk.dtb
imx6ull-14x14-evk-emmc.dtb
imx6ull-aes.dtb
```

根据你的板子配置选择对应的 dtb 文件。IMX-Forge 项目默认使用 `imx6ull-aes.dtb`，这是适配正点原子阿尔法开发板的设备树。

**踩坑记录**：有一次我烧错了 dtb 文件，用了 gpmi（NAND Flash）版本的配置去启动 eMMC 板子，结果内核启动到一半就挂了，报错说找不到存储设备。排查了好久才发现设备树选错了。所以这里一定要仔细确认板子型号。

---

### out/release-latest/busybox/ —— BusyBox 构建输出

BusyBox 的输出相对简单，因为它本质上就是单个可执行文件：

```bash
ls -lh out/release-latest/busybox/
```

关键文件：

| 文件 | 大小 | 说明 | 用途 |
|------|------|------|------|
| `busybox` | ~748KB | 主可执行文件 | 动态链接，已剥离符号 |
| `busybox_unstripped` | ~1MB | 未剥离符号的版本 | 调试用 |
| `.config` | ~29KB | BusyBox 配置 | 查看启用的命令 |

**验证 BusyBox 是否正确编译**：

```bash
file out/release-latest/busybox/busybox
```

应该看到：

```
busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, stripped
```

关键信息：`ARM` 架构、`dynamically linked`（动态链接）、`stripped`（已剥离符号）。

**查看 BusyBox 支持的命令**：

```bash
out/release-latest/busybox/busybox --list | head -20
```

你会看到一大串命令列表：

```
[
[[
acpid
adjtimex
arp
arping
ash
...
```

这些都是 BusyBox 集成的命令。每个命令实际都是 `busybox` 的软链接，调用时通过第一个参数区分具体功能。

---

### out/release-latest/rootfs/ —— 根文件系统

这是完整的根文件系统目录，可以直接挂载使用：

```bash
ls -la out/release-latest/rootfs/
```

你会看到标准的 Linux 根文件系统结构：

```
drwxr-xr-x  2 user user 4096 May 22 15:50 bin/
drwxr-xr-x  2 user user 4096 May 22 15:50 dev/
drwxr-xr-x  3 user user 4096 May 22 15:50 etc/
drwxr-xr-x  2 user user 4096 May 22 15:50 lib/
drwxr-xr-x  2 user user 4096 May 22 15:50 proc/
drwxr-xr-x  2 user user 4096 May 22 15:50 root/
drwxr-xr-x  2 user user 4096 May 22 15:50 sbin/
drwxr-xr-x  2 user user 4096 May 22 15:50 sys/
drwxr-xr-x  2 user user 4096 May 22 15:50 tmp/
drwxr-xr-x  3 user user 4096 May 22 15:50 usr/
```

这个 rootfs 已经包含了 BusyBox 和必要的库文件，可以直接通过 NFS 导出或者复制到 SD 卡使用。

---

### out/release-latest/images/ —— 快速找到要烧录的文件

`images/` 目录存放的是所有"可以直接烧录"的文件软链接，不用翻各个子目录：

```bash
ls -la out/release-latest/images/
```

你会看到：

```
lrwxrwxrwx 1 user user 50 May 22 15:50 imx6ull-aes.dtb -> ../linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
lrwxrwxrwx 1 user user 23 May 22 15:50 u-boot-dtb.imx -> ../uboot/u-boot-dtb.imx
lrwxrwxrwx 1 user user 29 May 22 15:50 zImage -> ../linux/arch/arm/boot/zImage
```

**三个关键文件**：
- `u-boot-dtb.imx` → U-Boot 镜像
- `zImage` → 压缩内核镜像
- `imx6ull-aes.dtb` → 设备树文件

烧录时直接从这里拷贝就行，不用记复杂的路径。

**经验**：我习惯在烧录脚本里直接用 `out/release-latest/images/` 路径，这样即使代码更新了，只要路径结构不变，脚本就能一直工作。

---

## Release 构建的归档机制

### 历史版本归档

每次运行 `./scripts/release-all.sh` 时，如果 `out/release-latest/` 目录已经存在，脚本会自动将其重命名为带时间戳的归档目录：

```bash
ls -ld out/release-*/
```

你会看到类似：

```
drwxr-xr-x 7 user user 4096 May 22 15:32 out/release-20260522-153212/
drwxr-xr-x 7 user user 4096 May 22 15:43 out/release-20260522-154321/
```

**归档机制说明**：

1. 当运行 `./scripts/release-all.sh` 时
2. 脚本检测 `out/release-latest/` 是否存在
3. 如果存在，将其重命名为 `out/release-{YYYYMMDD}-{HHMMSS}/`
4. 创建新的 `out/release-latest/` 目录进行构建

**注意**：`release-latest` 是一个实际的目录，不是软链接。这与一些其他项目的做法不同。

**清理历史版本**：

如果不需要保留历史版本，可以定期清理：

```bash
# 删除所有历史版本，保留 release-latest
rm -rf out/release-[0-9]*
```

**⚠️ 注意**：这个命令很危险，执行前先确认一下会删什么：

```bash
# 预览（不实际删除）
ls -d out/release-[0-9]*
```

确认无误后再执行删除。

---

## 其他目录

### out/firmwares/ —— 固件文件

存放第三方固件文件，主要是无线电法规数据库：

```bash
ls out/firmwares/
```

你会看到：

```
wireless-regdb/
```

这是 Linux 内核 WiFi 驱动需要的无线法规数据库。

### out/third_party/ —— 第三方库构建产物

存放第三方库的构建产物，如 Qt6：

```bash
ls out/third_party/
```

如果你没有构建 Qt6，这个目录可能是空的。

---

## 实用操作指南

### 如何快速找到要烧录的镜像文件

**方法一：用 images/ 目录（推荐）**

```bash
ls out/release-latest/images/
```

这是最快的方式，所有烧录用的文件都在这里。

**方法二：按组件查找**

如果你需要找某个特定组件的产物：

```bash
# U-Boot 镜像
ls out/release-latest/uboot/u-boot-dtb.imx

# 内核镜像
ls out/release-latest/linux/arch/arm/boot/zImage

# 设备树文件
ls out/release-latest/linux/arch/arm/boot/dts/nxp/imx/*.dtb
```

**方法三：用 find 命令（当你不确定文件在哪时）**

```bash
# 查找所有 dtb 文件
find out/ -name "*.dtb" -type f

# 查找 u-boot-dtb.imx
find out/ -name "u-boot-dtb.imx" -type f
```

---

### 如何验证构建产物的完整性

构建完成后，最好验证一下关键产物是否正确生成。`release-all.sh` 脚本会自动做基本验证，但你也可以手动检查。

**验证 U-Boot**：

```bash
cd out/release-latest/uboot

# 检查文件是否存在
test -f u-boot-dtb.imx && echo "✓ u-boot-dtb.imx exists"

# 检查文件大小（应该 > 1MB）
size=$(stat -c%s u-boot-dtb.imx)
[ $size -gt 1000000 ] && echo "✓ Size OK: $size bytes"
```

**验证内核**：

```bash
cd out/release-latest/linux

# 检查 zImage 是否存在
test -f arch/arm/boot/zImage && echo "✓ zImage exists"

# 检查设备树是否存在
test -f arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb && echo "✓ Device tree exists"

# 检查内核架构
file vmlinux | grep -q "ARM" && echo "✓ Architecture OK"
```

**验证 BusyBox**：

```bash
cd out/release-latest/busybox

# 检查可执行文件是否存在
test -f busybox && echo "✓ busybox exists"

# 检查是否是 ARM 架构
file busybox | grep -q "ARM" && echo "✓ Architecture OK"

# 检查是否动态链接
file busybox | grep -q "dynamically linked" && echo "✓ Dynamic linking OK"
```

**一键验证脚本**：

如果你想偷懒，可以把上面这些检查做成一个脚本：

```bash
#!/bin/bash
# verify_build.sh - 验证构建产物完整性

echo "========================================"
echo "Build Artifacts Verification"
echo "========================================"
echo ""

ERRORS=0

# U-Boot
echo "Checking U-Boot..."
if [ -f "out/release-latest/uboot/u-boot-dtb.imx" ]; then
    echo "  ✓ u-boot-dtb.imx exists"
else
    echo "  ✗ u-boot-dtb.imx missing!"
    ERRORS=$((ERRORS + 1))
fi

# Linux Kernel
echo "Checking Linux Kernel..."
if [ -f "out/release-latest/linux/arch/arm/boot/zImage" ]; then
    echo "  ✓ zImage exists"
else
    echo "  ✗ zImage missing!"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "out/release-latest/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb" ]; then
    echo "  ✓ Device tree exists"
else
    echo "  ✗ Device tree missing!"
    ERRORS=$((ERRORS + 1))
fi

# BusyBox
echo "Checking BusyBox..."
if [ -f "out/release-latest/busybox/busybox" ]; then
    echo "  ✓ busybox exists"
else
    echo "  ✗ busybox missing!"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "========================================"
if [ $ERRORS -eq 0 ]; then
    echo "✓ All checks passed!"
else
    echo "✗ $ERRORS error(s) found!"
    exit 1
fi
echo "========================================"
```

保存为 `scripts/verify_build.sh`，每次构建完跑一下：

```bash
chmod +x scripts/verify_build.sh
./scripts/verify_build.sh
```

---

### 清理构建输出的正确姿势

开发过程中，有时候需要清理构建产物重新开始。但清理也要讲究方法，别手滑删错了东西。

**清理所有构建产物**：

最简单最暴力的办法，笔者特意把所有产物全部集中在项目目录内的一个特定文件夹就是图这个。

```bash
# 手动删除
rm -rf out/
```

**只清理特定组件**：

```bash
# 只清理 U-Boot（单独构建模式）
rm -rf out/uboot

# 只清理内核（单独构建模式）
rm -rf out/linux

# 只清理 BusyBox（单独构建模式）
rm -rf out/busybox

# 清理 Release 构建
rm -rf out/release-latest
```

**只清理历史 Release 版本，保留最新版**：

```bash
# 找出除 release-latest 外的所有 release 目录
find out/ -maxdepth 1 -type d -name "release-*" ! -name "release-latest" -exec rm -rf {} +
```

**⚠️ 注意**：这个命令很危险，执行前先确认一下会删什么：

```bash
# 预览（不实际删除）
find out/ -maxdepth 1 -type d -name "release-*" ! -name "release-latest"
```

确认无误后再执行删除。

**踩坑经验**：有一次我想清理旧的构建版本，结果命令写错了，把 `release-latest` 也删了。后来还是重新构建了一次才找回来。所以清理前最好先备份，或者用 `--dry-run` 类似的预览模式。

---

## 常见问题

### Q1: out/ 目录和 rootfs/ 目录有什么区别？

`out/` 存放编译过程中的中间产物和最终镜像，而 `rootfs/` 存放根文件系统源码（配置文件、脚本等）。`out/release-latest/rootfs/` 是从项目 `rootfs/` 目录经过处理后生成的完整 rootfs，可以直接挂载使用。

### Q2: 我可以直接用 out/release-latest/uboot/ 下的 u-boot-dtb.imx 烧录吗？

可以。`out/release-latest/uboot/` 和 `out/release-latest/images/` 下的文件内容是一样的，后者只是前者的软链接。用哪个都行，看你习惯。

### Q3: 为什么每次构建都会生成新的 release-XXX 目录？

这是为了保留历史版本，方便回溯。如果你不需要保留历史，可以定期清理旧版本。

### Q4: images/ 目录下的文件和源文件有什么区别？

没有区别，`images/` 下的都是软链接，指向对应组件的实际文件。这样做是为了方便——所有要烧录的文件集中在一个目录下，不用记复杂的路径。

### Q5: 单独构建和 Release 构建有什么区别？

**单独构建**：
- 只构建某个组件
- 输出到 `out/uboot/`、`out/linux/`、`out/busybox/`
- 适合开发调试阶段

**Release 构建**：
- 构建所有组件并整合
- 输出到 `out/release-latest/`
- 会创建完整的 rootfs 和 images/ 目录
- 适合准备烧录到目标板子

### Q6: release-latest 是软链接吗？

不是。`release-latest` 是一个实际的目录。每次构建时，如果它已存在，会被重命名为带时间戳的归档目录，然后创建新的 `release-latest` 目录。

---

## 总结：out/ 目录不再神秘

到这里，`out/` 目录的结构应该彻底搞清楚了。让我们回顾一下核心要点：

- **两种构建模式**：单独组件构建（`out/uboot/` 等）和 Release 构建（`out/release-latest/`）
- **Release 构建目录**（`release-latest/`）：包含 uboot、linux、busybox、rootfs、images
- **归档机制**：每次构建会自动归档旧版本到 `release-{datetime}/`
- **images/**：所有可烧录文件的集中地，省得满目录找文件

下次构建完成后，你可以自信地说："我知道我的文件在哪"，而不是在一堆目录里迷路。

---

## 下一步：进阶玩法

现在你已经搞懂了 `out/` 目录，接下来可以：

1. **[Patch 工作流实战指南](./02_patch_workflow_practice.md)** —— 学习如何正确管理对 U-Boot/内核的修改
2. **[RootFS Overlay 使用指南](./03_rootfs_overlay_guide.md)** —— 掌握灵活定制 Rootfs 的技巧

构建系统的进阶用法，都在这里了。继续加油！
