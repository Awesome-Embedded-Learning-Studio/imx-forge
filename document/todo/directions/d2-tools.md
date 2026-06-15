# 方向 D2：工具完备

> **最后更新**：2026-06-14（对齐实际进度）
> **任务数量**：66项 (9工具 + 57文档)，文档已完成约 8 项

---

## 📋 为什么重要

**方向 D2** 的核心目标是提供完整的辅助工具链，提升开发效率和用户体验。当环境配置完成后，良好的工具可以让开发过程更加顺畅。

**核心价值**：
- 提供完整的开发工具集
- 建立 CI/CD 基础
- 完善文档体系
- 支持多板卡扩展

---

## 📊 优先级概览

| 优先级 | 工具任务 | 文档任务 | 总计 |
|--------|----------|----------|------|
| P1 | 6项（待办）| 49项（✅约8 / 待办约41）| 55 |
| P2 | 3项（待办）| 8项（待办）| 11 |
| **总计** | **9** | **57** | **66** |

> 注：原概览表 P2 文档记为 `-` 且总数 50 有误，本次重计为 9 工具 + 57 文档 = 66。

---

## 📋 P1: 重要功能 (6工具 + 49文档)

> 提升开发效率和调试能力的关键功能
>
> **2026-06-14 对齐**：P1-1 系统调试手册、P1-2 交叉调试所引用的 `tutorial/debug/`、`tutorial/workflow/`、`tutorial/tools/` 目录均尚未建立，整体待办；现有部分覆盖见 [kernel/mainline/11 常见问题](../../tutorial/kernel/mainline/11_common_issues.md)、[practical/03 启动调试](../../tutorial/practical/03_boot_and_debug.md)、[kernel/08 内核启动调试](../../tutorial/kernel/08_kernel_boot_debug.md)。

### 工具任务 (6项)

| 任务 | 推荐基础 | 说明 |
|------|----------|------|
| D2-003: select-board.sh | D1-006 | 板卡切换脚本 |
| D2-004: 板卡接入文档 | D1-006 | 多板卡接入规范 |
| D2-005: CI - Patch 校验 | - | 自动补丁格式检查 |
| D2-007: build-buildroot.sh | D1-004 | Buildroot 根文件系统构建脚本 |
| D2-008: buildroot_menuconfig.sh | D2-007 | Buildroot 配置管理工具 |
| D2-009: clean_buildroot.sh | D2-007 | Buildroot 清理工具 |

### 文档任务 (23项)

#### P1-1: 系统调试手册 (10项)

| 任务 | 相关文件 |
|------|----------|
| [ ] U-Boot common issues / U-Boot 常见问题排查 | `document/tutorial/debug/` |
| [ ] Serial console no-output troubleshooting / 串口无输出排查 | `document/tutorial/debug/` |
| [ ] Network boot troubleshooting / 网络启动问题排查 | `document/tutorial/debug/` |
| [ ] Kernel panic common issues / Kernel panic 常见问题排查 | `document/tutorial/debug/` |
| [ ] DTB mismatch troubleshooting / DTB 不匹配问题排查 | `document/tutorial/debug/` |
| [ ] Rootfs and init failure troubleshooting / Rootfs 与 init 失败排查 | `document/tutorial/debug/` |
| [ ] NFS / TFTP troubleshooting / NFS / TFTP 常见问题排查 | `document/tutorial/debug/` |
| [ ] Kernel module loading failure troubleshooting / 模块加载失败排查 | `document/tutorial/debug/` |
| [ ] Serial log reading guide / 串口日志阅读指南 | `document/tutorial/debug/` |
| [ ] How to submit useful debug logs / 如何提交有效的问题日志 | `document/tutorial/debug/` |

#### P1-2: 交叉调试与诊断 (7项)

| 任务 | 相关文件 |
|------|----------|
| [ ] gdbserver deployment guide / gdbserver 板端部署说明 | `document/tutorial/debug/` |
| [ ] VSCode + GDB cross-debugging setup / VSCode + GDB 交叉调试配置 | `document/tutorial/workflow/` |
| [ ] Debugging shared libraries / 共享库调试说明 | `document/tutorial/debug/` |
| [ ] `strace` basic usage / `strace` 基础使用 | `document/tutorial/tools/` |
| [ ] Core dump debugging workflow / core dump 调试流程 | `document/tutorial/debug/` |
| [ ] Basic logging workflow / 基础日志收集流程 | `document/tutorial/debug/` |
| [ ] Basic performance inspection tools / 基础性能分析工具说明 | `document/tutorial/tools/` |

#### P1-3: 构建工具 (17项 — 已完成 9，基于旧教程 Ch 3, 34, 40)

> VIM/GCC/二进制工具基础已由 [linux-basics/](../../tutorial/linux-basics/) 覆盖（原路径 `tutorial/tools/`、`tutorial/ubuntu/` 已废弃）。

| 任务 | 状态 | 实际文件 |
|------|------|----------|
| Makefile basics and advanced / Makefile 基础 | [x] | [ch31 gcc 与 make](../../tutorial/linux-basics/07-devtools/ch31-gcc-make.md) |
| Makefile syntax 实战 / Makefile 语法进阶 | [ ] ⚠️ | ch31 覆盖基础，进阶待补 |
| Cross-compilation Makefile practice / 交叉编译 Makefile | [ ] ⚠️ | 见 [ch35 交叉编译](../../tutorial/linux-basics/07-devtools/ch35-crosscompile.md)，Makefile 实践待补 |
| CMake cross-compilation / CMake 交叉编译 | [ ] | 缺 |
| CMakeLists.txt writing / CMakeLists.txt 编写 | [ ] | 缺 |
| CMake with Qt cross-compilation / CMake 与 Qt 交叉编译 | [ ] | 缺 |
| menuconfig principles and usage / menuconfig 原理与使用 | [x] | [kernel/03 内核配置](../../tutorial/kernel/03_kernel_config.md) |
| Kconfig syntax / Kconfig 语法 | [ ] ⚠️ | 缺专篇 |
| Kernel/U-Boot configuration practice / 内核/uboot 配置实战 | [x] | [kernel/03](../../tutorial/kernel/03_kernel_config.md) + [uboot/02](../../tutorial/uboot/02_uboot_compile.md) |
| VIM quick start / VIM 快速入门 | [x] | [ch12 vim](../../tutorial/linux-basics/03-text/ch12-vim.md) |
| VIM modes and operations / VIM 模式与操作 | [x] | [ch12 vim](../../tutorial/linux-basics/03-text/ch12-vim.md) |
| VIM configuration and plugins / VIM 配置与插件 | [ ] ⚠️ | ch12 覆盖基础，插件待补 |
| GCC compilation options / GCC 编译选项 | [x] | [ch31 gcc 与 make](../../tutorial/linux-basics/07-devtools/ch31-gcc-make.md) |
| Static and dynamic library compilation / 静态库与动态库 | [x] | [ch31 gcc 与 make](../../tutorial/linux-basics/07-devtools/ch31-gcc-make.md) |
| objdump, nm, readelf usage / objdump, nm, readelf | [x] | [ch33 binutils](../../tutorial/linux-basics/07-devtools/ch33-binutils.md) |
| ldd library dependency checking / ldd 查看库依赖 | [x] | [ch33 binutils](../../tutorial/linux-basics/07-devtools/ch33-binutils.md) |
| Time measurement and performance analysis / 时间测量与性能 | [ ] ⚠️ | 缺 |

##### P1-3a: Buildroot 根文件系统构建（新增）

| 任务 | 相关文件 |
|------|----------|
| [ ] Buildroot 概述与对比分析 / Buildroot overview and comparison | `document/tutorial/build/04_buildroot_introduction.md` |
| [ ] Buildroot 快速开始指南 / Buildroot quickstart guide | `document/tutorial/build/05_buildroot_quickstart.md` |
| [ ] Buildroot 配置系统详解 / Buildroot config system explained | `document/tutorial/build/06_buildroot_config.md` |
| [ ] Buildroot 定制化与包管理 / Buildroot customization and packages | `document/tutorial/build/07_buildroot_customization.md` |
| [ ] Buildroot 故障排查手册 / Buildroot troubleshooting guide | `document/tutorial/build/08_buildroot_troubleshooting.md` |
| [ ] Buildroot 与 QT6 集成实战 / Buildroot with QT6 integration | `document/tutorial/practical/03_buildroot_qt6.md` |

#### P1-4: 驱动开发工具 (9项 — 已完成 2，基于旧教程 Ch 52-76)

> 阻塞/非阻塞 I/O、异步通知已由 [kernel/core-functional/](../../tutorial/kernel/core-functional/) 覆盖；I2C/SPI/UART 等子系统驱动见 [Issue #54 驱动开发待做清单](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/54)。

| 任务 | 状态 | 实际文件 |
|------|------|----------|
| I2C driver framework complete tutorial / I2C 驱动框架 | [ ] | 缺，见 #54 |
| SPI driver framework complete tutorial / SPI 驱动框架 | [ ] | 缺，见 #54 |
| UART driver development / UART 驱动开发 | [ ] | 缺，见 #54 |
| Blocking/non-blocking I/O complete tutorial / 阻塞/非阻塞 I/O | [x] | [core-functional/09 阻塞 IO](../../tutorial/kernel/core-functional/09_blocking_io.md) + [10 非阻塞 IO](../../tutorial/kernel/core-functional/10_nonblocking_io.md) |
| Async notification (fasync) / 异步通知 | [x] | [core-functional/11 异步通知](../../tutorial/kernel/core-functional/11_async_notification.md) |
| Linux device model detailed / 设备模型详解 | [ ] | 缺，见 #54 |
| Regmap API detailed guide / Regmap API | [ ] | 缺，见 #54 |
| IIO subsystem framework / IIO 子系统 | [ ] | 缺，见 #54 |
| ADC driver development / ADC 驱动 | [ ] | 缺，见 #54 |

---

## 📋 P2: 优化体验 (3项)

> 提升开发效率的高级功能

### 工具任务 (3项)

| 任务 | 推荐基础 | 说明 |
|------|----------|------|
| D2-001: menuconfig.sh | D1-004 | 统一配置入口 |
| D2-002: clean.sh | - | 智能清理工具 |
| D2-006: CI - Docker 构建 | D1-001 | 自动镜像构建 |

### 文档任务 (P2-0: 开发工作流与工具链) - 8项

| 任务 | 相关文件 |
|------|----------|
| [ ] VSCode development workflow / VSCode 开发工作流说明 | `document/tutorial/workflow/` |
| [ ] WSL2 development notes / WSL2 开发注意事项 | `document/tutorial/workflow/` |
| [ ] Docker development workflow / Docker 开发环境说明 | `document/tutorial/workflow/` |
| [ ] Remote-SSH workflow / Remote-SSH 工作流说明 | `document/tutorial/workflow/` |
| [ ] clangd cross-compilation configuration / clangd 交叉编译配置说明 | `document/tutorial/workflow/` |
| [ ] tasks.json command templates / tasks.json 常用任务模板 | `document/tutorial/workflow/` |
| [ ] Host and board file synchronization workflow / 主机与板端文件同步流程 | `document/tutorial/workflow/` |
| [ ] Git workflow for third-party source patches / 第三方源码 patch 的 Git 工作流 | `document/tutorial/workflow/` |

---

## 🔗 相关方向

- **D1：环境完善** - 完成环境配置后，再开发辅助工具
- **D3：示例展示** - 工具完备后，可以更高效地开发示例项目

---

## 🔗 相关资源

- **主路线图**：[roadmap.md](../roadmap.md)
- **D1 详情**：[d1-environment.md](./d1-environment.md)
- **GitHub Issue #47**: [路线任务追踪](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/47)

---

**完善的工具链是高效开发的基础！** 🛠️
