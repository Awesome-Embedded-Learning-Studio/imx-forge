<div align="center">

```
██╗███╗   ███╗██╗  ██╗      ███████╗ ██████╗ ██████╗  ██████╗ ███████╗
██║████╗ ████║╚██╗██╔╝      ██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
██║██╔████╔██║ ╚███╔╝ █████╗█████╗  ██║   ██║██████╔╝██║  ███╗█████╗
██║██║╚██╔╝██║ ██╔██╗ ╚════╝██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
██║██║ ╚═╝ ██║██╔╝ ██╗      ██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
╚═╝╚═╝     ╚═╝╚═╝  ╚═╝      ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

**面向 NXP i.MX6ULL 的嵌入式 Linux 开发工坊 —— 从工具链到 QT 应用的完整学习路径**

[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)
[![WSL2](https://img.shields.io/badge/WSL2-Tested%20%26%20OK-brightgreen?style=flat-square)](#-wsl2-深度友好)
[![Kernel](https://img.shields.io/badge/Kernel-dual%20track%20(6.12.3%20%2B%20mainline%207.0rc)-blue?style=flat-square)](#-双轨内核策略)
[![Mainline](https://img.shields.io/badge/Mainline-migrated%20%EF%83%A0-brightgreen?style=flat-square)](#-双轨内核策略)
[![Bootloader](https://img.shields.io/badge/Bootloader-uboot--imx%202025--04-yellow?style=flat-square)](#-双轨内核策略)
[![Board](https://img.shields.io/badge/Board-alpha%20%E2%9C%85-blueviolet?style=flat-square)](#-支持的开发板)
[![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](#-贡献指南)

</div>

---

## ✨ 为什么选择 IMX-Forge？

### 📚 完整的教程链条

我们的嵌入式学习和开发链条一步不落（虽然后面几个仍然再火热WIP）

```
工具链安装 → U-Boot 移植 → 内核配置 → Rootfs 构建 → 驱动开发 → QT 应用
```

每一步都有详细的文档和实战示例，不再是"这里略去一万字"的坑人教程。

是的，甚至可以在网页上阅读！[点击🖱获得更好体验!](https://awesome-embedded-learning-studio.github.io/imx-forge/)


### 💻 WSL2 深度友好

> **Windows 用户首选！** 项目在 WSL2 环境下完整测试通过

- ✅ Mirrored 网络模式 —— 直接访问开发板，无需复杂转发
- ✅ USB 设备直通指南 —— 串口、烧录一步到位
- ✅ TFTP/NFS 开发调试方案 —— 网络启动提高开发效率

不再需要双系统或虚拟机，Windows 下也能愉快地搞嵌入式开发！

### 🎨 QT / 图形界面支持

集成 `qt-compile-pipeline`，快速搭建嵌入式 GUI 开发环境：

- 🖥️ QT6 交叉编译支持
- 📦 触摸屏驱动（GT911 等）
- 🎯 完整的 QT 示例工程

### 🔄 双轨内核策略

```
patches/
├── [linux-imx]   NXP BSP 6.12.3 ← 当前推荐
└── [mainline]    上游内核      ← ✅ 已完成
```

稳定优先，长期向上游靠拢。

### 🛠️ 完整的开发环境

```
IMX-Forge/
├── scripts/          # 一键构建脚本
│   ├── release-all.sh      # 全量构建
│   └── build_helper/       # 分组件构建
├── third_party/      # 5 个子模块
│   ├── uboot-imx          # U-Boot NXP fork
│   ├── linux-imx          # NXP BSP 6.12.3
│   ├── linux_mainline     # 上游主线内核
│   ├── busybox            # BusyBox
│   └── qt-compile-pipeline # QT 交叉编译
├── patches/          # 双轨补丁管理
├── driver/           # 设备树和驱动示例
├── examples/         # 项目示例（QT/驱动/系统）
├── document/         # 完整教程文档
└── rootfs/           # NFS Rootfs
```

---

## 🚀 5分钟快速体验

```bash
# 1. 克隆项目（含子模块）
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge

# 2. 安装依赖（Ubuntu/WSL2）
sudo apt install -y build-essential gcc make bison flex device-tree-compiler \
    libssl-dev libncurses-dev python3-pyelftools swig picocom imagemagick

# 3. 安装 ARM 工具链（ARM GNU Toolchain 15.2）
wget https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
tar -xf arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
sudo mv arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain
export PATH=/opt/arm-gnu-toolchain/bin:$PATH

# 4. 一键构建（推荐）或分步构建
./scripts/release-all.sh                      # 一键构建所有组件（NXP BSP 内核）
# 或分步构建：
# ./scripts/build_helper/build-uboot.sh
# ./scripts/build_helper/build-linux.sh       # NXP BSP 内核
# ./scripts/build_helper/build-mainline-linux.sh  # 主线内核
# ./scripts/build_helper/build-busybox.sh

# 5. 烧录到 SD 卡，启动！
```

> 📖 **详细指南**: [QUICK_START.md](QUICK_START.md)

---

## 📖 完整学习路径

| 阶段 | 教程 | 内容 |
|------|------|------|
| 1️⃣ | [工具链教程](document/tutorial/start/01_start_from_toolchain.md) | ARM GNU Toolchain 15.2 安装与配置 |
| 2️⃣ | [U-Boot 教程](document/tutorial/uboot/01_what_is_uboot.md) | U-Boot 原理、编译、移植、Logo 定制 |
| 3️⃣ | [内核教程](document/tutorial/kernel) | 设备树、内核配置、驱动开发 |
| 4️⃣ | [Rootfs 教程](document/tutorial/rootfs/01_rootfs_overview.md) | BusyBox、inittab、NFS 挂载 |
| 5️⃣ | [实战教程](document/tutorial/practical/01_practical_overview.md) | 完整系统构建与调试 |
| 6️⃣ | [QT 示例](examples/qt) | QT6 交叉编译与触摸屏应用 |

---

## 🎯 支持的开发板

| 板卡 | 芯片 | 存储 | 状态 | 备注 |
|------|------|------|------|------|
| 正点原子阿尔法 | i.MX6ULL | eMMC / SD | ✅ 完整支持 | 首要支持目标，设备树完整 |
| 自制板 v1 | i.MX6ULL | eMMC / SD | 📋 规划中 | 通过 DTB Overlay 接入 |

---

## 🛠️ 技术架构

### 开发环境支持

| 环境 | 状态 | 备注 |
|------|------|------|
| **WSL2 (Ubuntu 22.04/24.04)** | ✅ 推荐 | Windows 用户首选，需 Mirrored 网络模式 |
| Ubuntu 24.04+ | ✅ 推荐 | 原生 Linux 环境 |

### 双轨内核演进路线

```
                    ┌─────────────────────────────┐
                    │        v0.5  [当前]          │
                    │  linux-imx (NXP BSP 6.12.3)   │
                    │  + mainline kernel 支持       │
                    │  U-Boot NXP fork             │
                    └──────────────┬──────────────┘
                                   │ mainline 适配完善
                    ┌──────────────▼──────────────┐
                    │        v1.x  [下一阶段]       │
                    │  mainline 成为推荐轨道        │
                    │  linux-imx 作为兼容备选       │
                    └──────────────┬──────────────┘
                                   │ 长期维护
                    ┌──────────────▼──────────────┐
                    │        v2.x  [未来]          │
                    │  完全迁移到上游              │
                    │  简化维护流程                │
                    └─────────────────────────────┘
```

---

## 📁 项目结构

```
imx-forge/
├── scripts/                # 构建脚本
│   ├── build_helper/      # 组件构建脚本
│   │   ├── build-uboot.sh
│   │   ├── build-linux.sh         # NXP BSP 内核
│   │   ├── build-mainline-linux.sh  # 主线内核
│   │   └── build-busybox.sh
│   ├── release-all.sh      # 一键构建所有组件
│   ├── patch_maker.sh      # 补丁生成工具
│   └── ...
├── third_party/            # 第三方源码（Git Submodule）
│   ├── uboot-imx/          # U-Boot NXP fork
│   ├── linux-imx/          # Linux Kernel NXP BSP
│   ├── linux_mainline/     # Linux Kernel 上游主线
│   ├── busybox/            # BusyBox
│   └── qt-compile-pipeline/  # QT 交叉编译流水线
├── patches/                # 补丁文件（format-patch + series）
│   ├── linux-imx/          # [linux-imx] 标签
│   ├── linux-mainline/     # [mainline] 标签
│   └── uboot/              # U-Boot 补丁
├── driver/                 # 设备树和驱动
│   ├── device_tree/        # 设备树文件
│   │   └── alpha-board/    # 正点原子阿尔法板
│   ├── led/                # LED 驱动示例
│   ├── base_driver/        # 基础驱动框架
│   └── firmwares/          # 固件
├── examples/               # 示例工程
│   ├── qt/                 # QT 应用示例
│   ├── driver/             # 驱动示例
│   ├── system/             # 系统示例
│   └── project/            # 完整项目示例
├── rootfs/                 # 根文件系统
│   ├── nfs/                # NFS 挂载用 rootfs
│   ├── overlay/            # Overlay 叠加目录
│   └── src/                # Rootfs 源文件
├── document/               # 完整教程文档
│   ├── tutorial/           # 教程（工具链/U-Boot/内核/Rootfs）
│   ├── practical/          # 实战教程
│   └── todo/               # 项目规划
├── out/                    # 编译输出目录
├── develop/                # 开发工具
└── tools/                  # 辅助工具
```

---

## 🚧 当前重点方向

- [x] 正点原子阿尔法板卡支持完善（eMMC / SD 双存储路径）
- [x] Mainline 内核迁移
- [ ] QT6 + GT911 触摸屏完整示例
- [ ] 自制板 v1 支持
- [ ] 教程文档持续完善

完整规划见 [document/todo/todo.md](document/todo/todo.md)。

---

## 🤝 贡献指南

欢迎提交 PR 与 Issue！

**补丁命名规范**：
- `[linux-imx]` 前缀 —— NXP BSP 轨道补丁
- `[mainline]` 前缀 —— 上游内核轨道补丁
- `[uboot]` 前缀 —— U-Boot 补丁

**文档贡献**：
- 教程改进建议
- 错误修复
- 新示例代码

---

## 📄 开源协议

MIT LICENSE —— 详见 [LICENSE](LICENSE)

若补丁源自 GPL 授权的 linux-imx 或 NXP U-Boot，则保留其原始 GPL-2.0 许可证。

---

## 🔗 相关链接

- **快速入门**: [QUICK_START.md](QUICK_START.md)
- **教程目录**: [document/tutorial/](document/tutorial/)
- **问题反馈**: [GitHub Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
- **项目规划**: [document/todo/todo.md](document/todo/todo.md)

---

<div align="center">

**用 🔥 和无数串口终端堆出来的工程。希望我们可以更方便地自定义自己的 i.MX6ULL 系统。**

[⭐ Star](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge) · [🍴 Fork](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/fork) · [📢 Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)

</div>
