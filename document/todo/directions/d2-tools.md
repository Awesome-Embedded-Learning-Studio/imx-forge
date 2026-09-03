# 方向 D2：工具完备

> **最后更新**：2026-09-02（回填 debug/workflow 两卷落地项：调试与排错卷 3 章新建、开发环境配置卷扩至 6 篇并全卷重写）
> **任务数量**：66项 (9工具 + 57文档)，文档已完成约 16 项（buildroot 12 章、I2C/SPI 驱动，以各表勾选为准）

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
| P1 | 6项（✅3 / 待办3）| 49项（✅约16 / 待办约33）| 55 |
| P2 | 3项（待办）| 8项（待办）| 11 |
| **总计** | **9** | **57** | **66** |

> 注：原概览表 P2 文档记为 `-` 且总数 50 有误，本次重计为 9 工具 + 57 文档 = 66。

---

## 📋 P1: 重要功能 (6工具 + 49文档)

> 提升开发效率和调试能力的关键功能
>
> **2026-09-02 对齐**：`tutorial/debug/` 已建立（3 章 + index，含症状排障路标表）；`tutorial/workflow/` 已扩至 6 篇（卷名改「开发环境配置」）；`tutorial/tools/` 不建——工具内容并入 linux-basics（见 P1-3 注）。按 op_plan/04 §四「错误模式不立独立卷」，P1-1 排查类条目收敛进 debug 卷与 qa/ 机制，不逐条立篇。

### 工具任务 (6项)

| 任务 | 推荐基础 | 说明 |
|------|----------|------|
| D2-003: select-board.sh | D1-006 | 板卡切换脚本 |
| D2-004: 板卡接入文档 | D1-006 | 多板卡接入规范 |
| D2-005: CI - Patch 校验 | - | 自动补丁格式检查 |
| D2-007: build-buildroot.sh | D1-004 | ✅ [build-buildroot.sh](../../scripts/build_helper/build-buildroot.sh.md) |
| D2-008: buildroot_menuconfig.sh | D2-007 | ✅ [buildroot_menuconfig.sh](../../scripts/build_helper/buildroot_menuconfig.sh.md) |
| D2-009: clean_buildroot.sh | D2-007 | ✅ [clean_buildroot.sh](../../scripts/build_helper/clean_buildroot.sh.md) |

### 文档任务 (23项)

#### P1-1: 系统调试手册 (10项)

| 任务 | 相关文件 |
|------|----------|
| [ ] U-Boot common issues / U-Boot 常见问题排查 | `document/tutorial/debug/` |
| [ ] Serial console no-output troubleshooting / 串口无输出排查 | [start/04](../../tutorial/start/04_serial_tools_minicom.md) 排障节部分覆盖；其余按上方对齐注收敛，不逐条立篇 |
| [ ] Network boot troubleshooting / 网络启动问题排查 | `document/tutorial/debug/` |
| [ ] Kernel panic common issues / Kernel panic 常见问题排查 | 机制在 [kernel/08](../../tutorial/kernel/08_kernel_boot_debug.md)，读法在 [debug/03 §三](../../tutorial/debug/03_serial_log_reading.md)，不另立篇 |
| [ ] DTB mismatch troubleshooting / DTB 不匹配问题排查 | `document/tutorial/debug/` |
| [ ] Rootfs and init failure troubleshooting / Rootfs 与 init 失败排查 | `document/tutorial/debug/` |
| [ ] NFS / TFTP troubleshooting / NFS / TFTP 常见问题排查 | 已由 [workflow/01](../../tutorial/workflow/01_wsl2_env_config.md) + [rootfs/05](../../tutorial/rootfs/05_nfs_wsl_troubleshoot.md) 覆盖，不另立篇 |
| [ ] Kernel module loading failure troubleshooting / 模块加载失败排查 | `document/tutorial/debug/` |
| [x] Serial log reading guide / 串口日志阅读指南 | [debug/03](../../tutorial/debug/03_serial_log_reading.md) |
| [x] How to submit useful debug logs / 如何提交有效的问题日志 | [debug/03 §五](../../tutorial/debug/03_serial_log_reading.md)（四要素日志截法） |

#### P1-2: 交叉调试与诊断 (7项)

| 任务 | 相关文件 |
|------|----------|
| [x] gdbserver deployment guide / gdbserver 板端部署说明 | [debug/01 §二](../../tutorial/debug/01_gdbserver_remote_debug.md) |
| [x] VSCode + GDB cross-debugging setup / VSCode + GDB 交叉调试配置 | [debug/01 §四](../../tutorial/debug/01_gdbserver_remote_debug.md)（全仓首个 launch.json） |
| [x] Debugging shared libraries / 共享库调试说明 | [debug/01 §五](../../tutorial/debug/01_gdbserver_remote_debug.md) |
| [x] `strace` basic usage / `strace` 基础使用 | [debug/02 §三](../../tutorial/debug/02_strace_log_coredump.md)（tools/ 不建） |
| [x] Core dump debugging workflow / core dump 调试流程 | [debug/02 §四](../../tutorial/debug/02_strace_log_coredump.md) |
| [x] Basic logging workflow / 基础日志收集流程 | [debug/02 §二](../../tutorial/debug/02_strace_log_coredump.md)（dmesg/syslogd/logread） |
| [ ] Basic performance inspection tools / 基础性能分析工具说明 | perf/top 归 workflow 卷 P2 补篇（op_plan/04 §五④），本批不做 |

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

> ✅ 已完成：实际扩展为 12 章，见 [tutorial/buildroot/](../../tutorial/buildroot/)。下表为原 6 项任务与实际章节的对应关系。

| 任务 | 状态 | 实际文件 |
|------|------|----------|
| Buildroot 概述与对比分析 / Buildroot overview and comparison | [x] | [buildroot/01_how_buildroot_works](../../tutorial/buildroot/01_how_buildroot_works.md) |
| Buildroot 快速开始指南 / Buildroot quickstart guide | [x] | [buildroot/02_first_build](../../tutorial/buildroot/02_first_build.md) |
| Buildroot 配置系统详解 / Buildroot config system explained | [x] | [buildroot/04_kconfig_fragments](../../tutorial/buildroot/04_kconfig_fragments.md) |
| Buildroot 定制化与包管理 / Buildroot customization and packages | [x] | [buildroot/06_rootfs_customization](../../tutorial/buildroot/06_rootfs_customization.md) + [07_custom_package](../../tutorial/buildroot/07_custom_package.md) |
| Buildroot 故障排查手册 / Buildroot troubleshooting guide | [x] | [buildroot/10_debugging](../../tutorial/buildroot/10_debugging.md) |
| Buildroot 与 QT6 集成实战 / Buildroot with QT6 integration | [x] | [buildroot/11_qt6_integration](../../tutorial/buildroot/11_qt6_integration.md) |

#### P1-4: 驱动开发工具 (9项 — 已完成 2，基于旧教程 Ch 52-76)

> 阻塞/非阻塞 I/O、异步通知已由 [kernel/core-functional/](../../tutorial/kernel/core-functional/) 覆盖；I2C/SPI/UART 等子系统驱动见 [Issue #54 驱动开发待做清单](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/54)。

| 任务 | 状态 | 实际文件 |
|------|------|----------|
| I2C driver framework complete tutorial / I2C 驱动框架 | [x] | [driver/08_i2c_ap3216c](../../tutorial/driver/08_i2c_ap3216c_driver/) |
| SPI driver framework complete tutorial / SPI 驱动框架 | [x] | [driver/09_spi_icm20608](../../tutorial/driver/09_spi_icm20608_driver/) |
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
| [x] VSCode development workflow / VSCode 开发工作流说明 | [workflow 卷](../../tutorial/workflow/) 整卷重写为六篇制 |
| [x] WSL2 development notes / WSL2 开发注意事项 | [workflow/01](../../tutorial/workflow/01_wsl2_env_config.md) |
| [x] Docker development workflow / Docker 开发环境说明 | [docker 卷](../../tutorial/docker/) 已覆盖，不另立 |
| [x] Remote-SSH workflow / Remote-SSH 工作流说明 | [workflow/02](../../tutorial/workflow/02_vscode_remote_ssh.md) |
| [x] clangd cross-compilation configuration / clangd 交叉编译配置说明 | [workflow/04](../../tutorial/workflow/04_clangd_cross_compile.md) |
| [x] tasks.json command templates / tasks.json 常用任务模板 | [workflow/05](../../tutorial/workflow/05_tasks_json.md) |
| [x] Host and board file synchronization workflow / 主机与板端文件同步流程 | [workflow/06](../../tutorial/workflow/06_host_board_transfer.md) |
| [x] Git workflow for third-party source patches / 第三方源码 patch 的 Git 工作流 | [build/02](../../tutorial/build/02_patch_workflow_practice.md) 已覆盖 |

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
