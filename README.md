<div align="center">

```
██╗███╗   ███╗██╗  ██╗      ███████╗ ██████╗ ██████╗  ██████╗ ███████╗
██║████╗ ████║╚██╗██╔╝      ██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
██║██╔████╔██║ ╚███╔╝ █████╗█████╗  ██║   ██║██████╔╝██║  ███╗█████╗
██║██║╚██╔╝██║ ██╔██╗ ╚════╝██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
██║██║ ╚═╝ ██║██╔╝ ██╗      ██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
╚═╝╚═╝     ╚═╝╚═╝  ╚═╝      ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

**面向 NXP i.MX6ULL 的嵌入式 Linux 开发工坊 —— 从工具链到驱动的完整学习路径**

[![CI](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions/workflows/ci-build.yml/badge.svg)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions/workflows/ci-build.yml)
[![Tag](https://img.shields.io/github/v/tag/Awesome-Embedded-Learning-Studio/imx-forge?sort=semver&style=flat-square&label=Tag&color=blue)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/tags)
[![Latest Stable](https://img.shields.io/github/v/release/Awesome-Embedded-Learning-Studio/imx-forge?style=flat-square&label=latest%20stable&color=blue)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/releases/latest)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)
[![Contributors](https://img.shields.io/github/contributors/Awesome-Embedded-Learning-Studio/imx-forge?style=flat-square)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/graphs/contributors)
[![Docker](https://img.shields.io/badge/Docker-supported%20%EF%83%8B-blue?style=flat-square)](docker/README.md)
[![WSL2](https://img.shields.io/badge/WSL2-Tested%20%26%20OK-brightgreen?style=flat-square)](document/QUICK_START.md)

</div>

---

## ✨ 为什么选择 IMX-Forge？

- 🐳 **开箱即用的开发环境** — 预装 ARM GNU Toolchain 15.2.rel1 的 Docker 镜像，5 分钟就绪，无需配置工具链 PATH；WSL2 深度友好（Mirrored 网络 + USB 直通）。
- 🔧 **双轨内核策略** — NXP BSP `6.12.3`（稳定）+ Mainline `7.1`（紧跟上游），附完整迁移对比。
- 📚 **完整的 0→1 学习路径** — 工具链 → U-Boot → 内核 → Rootfs → 驱动 → 实战，每步都有文档与示例，不再是"略去一万字"的坑人教程。
- ✅ **CI/CD 全覆盖** — 每次提交自动验证 U-Boot、双轨 Linux 内核与 rootfs 构建，ccache 加速。

🌐 **在线阅读**：https://awesome-embedded-learning-studio.github.io/imx-forge/

---

## 🚀 快速开始

```bash
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge

# 拉取预构建镜像（Ubuntu 24.04 + 工具链 + 全部依赖，约 2GB）
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
docker run -it --rm -v $(pwd):/workspace ghcr.io/awesome-embedded-learning-studio/imx-forge:latest

# 一键构建完整系统（默认 eMMC 镜像）
./scripts/release-all.sh
```

<details>
<summary><b>更多选项</b></summary>

- **锁定版本**：`docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:v1.0.0`（首个轻量可用版；历史 `v0.5` 仅作路线图里程碑）。
- **SD/eMMC 双介质**：`./scripts/release-all.sh --boot-media both`。
- **Qt6 rootfs**（默认不含，增量补不浪费前面的编译）：
  ```bash
  ./scripts/build_helper/build-buildroot.sh --with-qt6    # 增量补 Qt6 到 out/release-latest/rootfs
  ./scripts/release-all.sh --continue --stage 5           # 用带 Qt6 的 rootfs 重打包镜像
  ```
  详见 [release-all.sh 文档](document/scripts/release-all.sh.md)。
- **本地构建镜像 / 国内加速**：`cd docker && docker build -t imx-forge:latest .`（国内可用 `Dockerfile.cn`）；ghcr.io 拉取慢见 [Docker 镜像加速](docker/README.md#国内用户加速)。

</details>

> v1.0.0 的 SD 卡启动与 UUU + UMS eMMC 启动流程，已由仓库主作者 CharlieChen114514 在正点原子阿尔法 i.MX6ULL 开发板上完成实验验证。

📖 **详细配置**：[QUICK_START.md](document/QUICK_START.md) · [Docker 指南](docker/README.md) · [WSL2 教程](document/tutorial/docker/01_docker_basics.md#wsl2-安装)

---

## 📖 学习路径

| 阶段 | 主题 | 内容 | 状态 |
|------|------|------|------|
| 🌱 | [Linux 基础预备营](document/tutorial/linux-basics) | 35 章 Ubuntu 实用教程，补齐嵌入式必备功课 | ✅ 新增 |
| 0️⃣ | [Docker 基础](document/tutorial/docker) | Docker 基础知识与 IMX-Forge 开发指南 | ✅ |
| 🛠️ | [开发工作流](document/tutorial/workflow) | WSL2、clangd 交叉索引、VSCode tasks 模板 | ✅ |
| 1️⃣ | [工具链](document/tutorial/start) | ARM GNU Toolchain 15.2 安装与配置 | ✅ |
| 2️⃣ | [U-Boot](document/tutorial/uboot) | U-Boot 原理、编译、移植、Logo 定制 | ✅ |
| 3️⃣ | [内核开发](document/tutorial/kernel) | 设备树、内核配置、驱动开发、网络启动 | ✅ |
| 4️⃣ | [Rootfs](document/tutorial/rootfs) | BusyBox、inittab、NFS 挂载、应用集成 | ✅ |
| 🏗️ | [Buildroot 构建](document/tutorial/buildroot) | 现行 rootfs 方案：br2-external、自定义包、Qt6 集成 | ✅ |
| 5️⃣ | [驱动开发](document/tutorial/driver) | 字符设备、设备树、pinctrl/gpio、platform、input 子系统 | ✅ 持续扩展 |
| 🖥️ | [QEMU 板级模拟](document/tutorial/emu) | 没有板子也能跑：外设模型 + e2e 断言体检 | ✅ 新增 |
| 6️⃣ | [实战演练](document/tutorial/practical) | 完整系统构建与调试 | ✅ |
| 🏁 | [工程实战](document/tutorial/project) | light-meter：从空 CMakeLists 到真板产品 | ✅ 新增 |

当前完整支持 **正点原子阿尔法 i.MX6ULL**；其它板卡（野火等）欢迎提交 PR。项目规划见 [todo](document/todo/todo.md)。

---

## 🤝 贡献

欢迎 [报告 Bug](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues) · [提出功能](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues) · [提交代码](CONTRIBUTING.md)。完整指南与补丁命名规范（`[linux-imx]` / `[mainline]` / `[uboot]`）见 [CONTRIBUTING.md](CONTRIBUTING.md)。感谢 [所有贡献者](CONTRIBUTORS.md)。

---

## 📄 开源协议

MIT —— 详见 [LICENSE](LICENSE)。若补丁源自 GPL 授权的 linux-imx 或 NXP U-Boot，则保留其原始 GPL-2.0 许可证。

---

<div align="center">

**用 🔥 和无数串口终端堆出来的工程。希望我们可以更方便地自定义自己的 i.MX6ULL 系统。**

[⭐ Star](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge) · [🍴 Fork](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/fork) · [📢 Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)

</div>
