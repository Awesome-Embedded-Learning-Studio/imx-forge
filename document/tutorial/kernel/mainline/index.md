<PageHeader icon="🌐" title="Mainline 主线内核" description="IMX-Forge 已完成向上游主线内核的迁移" />

## 为什么要用主线内核？

| 特性 | NXP BSP（项目已退役） | mainline |
|------|---------------------|----------|
| 稳定性 | ✅ 高 | ✅ 高 |
| 驱动支持 | ✅ 完善 | ⚠️ 需适配 |
| 长期维护 | ⚠️ 取决于 NXP | ✅ 社区维护 |
| 上游贡献 | ❌ 困难 | ✅ 容易 |
| 版本更新 | ⚠️ 较慢 | ✅ 快速 |

## 🖥️ 实测效果

主线 Linux 7.2.9 咱们已在正点原子阿尔法 i.MX6ULL 上跑通——这不是 PPT，是真实启动画面：

![主线内核 Linux 7 启动实拍：咱们这块板子的真实启动画面](/linux7.png)

::: details 构建命令
```bash
# 教程从零流程：源码树 ~/experiments/linux-mainline，构建产物进 ~/experiments/linux-build
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx6ull_aes_defconfig
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j16 zImage nxp/imx/imx6ull-aes.dtb

# 仓库工程化：一条命令完成拷贝、配置、构建（见工程化章节）
./scripts/build_helper/build-linux.sh
```
:::

::: details 延伸阅读
- [Linux 内核邮件列表](https://lkml.org/)
- [内核开发流程](https://www.kernel.org/doc/html/latest/process/)
:::

## 教程目录

| 文件 | 标题 | 说明 |
|------|------|------|
| [01_why_mainline.md](01_why_mainline) | 为什么要折腾主线内核 | NXP BSP vs 主线内核的根本差异 |
| [02_env_setup.md](02_env_setup) | 从零开始搭建主线内核编译环境 | 依赖安装、工具链配置 |
| [03_source_fetch.md](03_source_fetch) | 取源码：从 stable 树拉下 v7.2.9 | stable 树与主树的分工、浅克隆、子模块、版本验证 |
| [04_bsp_vs_mainline.md](04_bsp_vs_mainline) | BSP vs 主线对比 | DRM 显示子系统、设备树 binding 变化 |
| [05_defconfig.md](05_defconfig) | 内核配置：读懂一份 defconfig | 配置机制、基线铺建、原生基线差距盘点 |
| [06_defconfig_customize.md](06_defconfig_customize) | 内核配置：动手做出自己的 defconfig | menuconfig、savedefconfig、内置与模块取舍 |
| [07_dts_writing.md](07_dts_writing) | 设备树：从参考板改出 AES 板 | 参考板方法、节点精读、板级文件对写作 |
| [08_dts_build_boot.md](08_dts_build_boot) | 编译、外挂模块与 QEMU 首启验收 | 编译 zImage/dtb、模块首编、QEMU 15 项断言验收 |
| [09_display_drm.md](09_display_drm) | DRM 显示系统移植 | LCD 驱动完整迁移指南 |
| [10_touch_gt9xx.md](10_touch_gt9xx) | 触摸屏移植 | GT9147/Goodix 驱动配置 |
| [11_network_dual_phy.md](11_network_dual_phy) | 双网口移植 | FEC + KSZ8081 以太网配置 |
| [12_debug_tricks.md](12_debug_tricks) | 调试技巧 | dmesg 分析、设备树验证、DRM 调试 |
| [13_common_issues.md](13_common_issues) | 常见问题 | 报错速查表、GPIO 冲突解决 |

## 快速开始

1. 阅读 [01_why_mainline.md](01_why_mainline) 了解主线内核的优势和代价
2. 跟随 [02_env_setup.md](02_env_setup) 搭建咱们自己的编译环境
3. 参考 [03_source_fetch.md](03_source_fetch) 在自己的目录里克隆 v7.2.9（内核侧没有补丁）
4. 学习 [04_bsp_vs_mainline.md](04_bsp_vs_mainline) 理解架构差异
5. 按 [05_defconfig.md](05_defconfig) 读懂配置机制，按 [06_defconfig_customize.md](06_defconfig_customize) 做出自己板子的 defconfig，再按 [07_dts_writing.md](07_dts_writing) 从参考板改出 AES 板、按 [08_dts_build_boot.md](08_dts_build_boot) 编译并首启
6. 参考 [09_display_drm.md](09_display_drm)、[10_touch_gt9xx.md](10_touch_gt9xx)、[11_network_dual_phy.md](11_network_dual_phy) 移植具体外设
7. 使用 [12_debug_tricks.md](12_debug_tricks) 调试问题
8. 查阅 [13_common_issues.md](13_common_issues) 解决常见报错

## 技术要点

### DRM 显示系统

主线内核的 eLCDIF 驱动已迁移到 DRM 子系统，设备树写法也随之变了：旧式的 `display = <&display0>` 咱们不再使用，换成 OF graph 的 `port/endpoint` 方式。

### 设备树 binding

- 旧 BSP：`&lcdif { display = <&display0>; display0: display@0 { ... }; }`
- 主线：`panel: panel-dpi { ... port { panel_in: endpoint { ... }; }; }; &lcdif { port { lcdif_out: endpoint { ... }; }; }`

### 板级设备树

内核侧没有补丁。教程从零流程在您自己的内核树里创建 `imx6ull-aes.dts`/`imx6ull-aes.dtsi`；仓库工程化则把它们收敛为 `driver/device_tree/alpha-board/linux/` 下的唯一原件，构建时拷入内核树并注册 dtb。上游 `imx6ul.dtsi` 没有也不需要 sim2 节点，旧补丁里的 sim2 是死代码，v7.2.9 重写时已清理。

## 硬件平台

- **芯片**：NXP i.MX6ULL (ARM Cortex-A7, 528MHz)
- **开发板**：正点原子 i.MX6ULL
- **显示**：7 寸 LCD (1024×600)
- **触摸**：Goodix GT9147
- **网络**：双 KSZ8081 PHY (RMII)

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="01_why_mainline" variant="sub">为什么要用主线内核</ChapterLink>
  <ChapterLink href="../" variant="sub">← 返回内核教程</ChapterLink>
</ChapterNav>
