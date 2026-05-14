<PageHeader icon="🌐" title="Mainline 主线内核" description="IMX-Forge 已完成向上游主线内核的迁移" />

## 为什么要用主线内核？

| 特性 | linux-imx (NXP BSP) | mainline |
|------|---------------------|----------|
| 稳定性 | ✅ 高 | ✅ 高 |
| 驱动支持 | ✅ 完善 | ⚠️ 需适配 |
| 长期维护 | ⚠️ 取决于 NXP | ✅ 社区维护 |
| 上游贡献 | ❌ 困难 | ✅ 容易 |
| 版本更新 | ⚠️ 较慢 | ✅ 快速 |

::: details 构建命令
```bash
# 使用主线内核构建脚本
./scripts/build_helper/build-mainline-linux.sh

# 或手动构建
cd third_party/linux_mainline
make imx_aes_mainline_defconfig O=../../out/mainline/linux
make -j8 O=../../out/mainline/linux
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
| [02_env_setup.md](02_env_setup) | 从零开始搭建编译环境 | 依赖安装、工具链配置 |
| [03_source_fetch.md](03_source_fetch) | 获取主线内核源码 | kernel.org 克隆、补丁应用 |
| [04_bsp_vs_mainline.md](04_bsp_vs_mainline) | BSP vs 主线深度对比 | DRM 显示子系统、设备树 binding 变化 |
| [05_defconfig.md](05_defconfig) | 主线内核配置 | defconfig 配置、关键选项说明 |
| [06_dts_migration.md](06_dts_migration) | 设备树迁移 | OF graph 连接、sim2 节点补充 |
| [07_display_drm.md](07_display_drm) | DRM 显示系统移植 | LCD 驱动完整迁移指南 |
| [08_touch_gt9xx.md](08_touch_gt9xx) | 触摸屏移植 | GT9147/Goodix 驱动配置 |
| [09_network_dual_phy.md](09_network_dual_phy) | 双网口移植 | FEC + KSZ8081 以太网配置 |
| [10_debug_tricks.md](10_debug_tricks) | 调试技巧 | dmesg 分析、设备树验证、DRM 调试 |
| [11_common_issues.md](11_common_issues) | 常见问题 | 报错速查表、GPIO 冲突解决 |

## 快速开始

1. 阅读 [01_why_mainline.md](01_why_mainline) 了解主线内核的优势和代价
2. 跟随 [02_env_setup.md](02_env_setup) 搭建编译环境
3. 参考 [03_source_fetch.md](03_source_fetch) 获取主线源码并应用补丁
4. 学习 [04_bsp_vs_mainline.md](04_bsp_vs_mainline) 理解架构差异
5. 按 [05_defconfig.md](05_defconfig) 和 [06_dts_migration.md](06_dts_migration) 配置内核和设备树
6. 参考 [07_display_drm.md](07_display_drm)、[08_touch_gt9xx.md](08_touch_gt9xx)、[09_network_dual_phy.md](09_network_dual_phy) 移植具体外设
7. 使用 [10_debug_tricks.md](10_debug_tricks) 调试问题
8. 查阅 [11_common_issues.md](11_common_issues) 解决常见报错

## 技术要点

### DRM 显示系统

主线内核的 eLCDIF 驱动已迁移到 DRM 子系统，设备树写法从旧式的 `display = <&display0>` 变为 OF graph 的 `port/endpoint` 方式。

### 设备树 binding

- 旧 BSP：`&lcdif { display = <&display0>; display0: display@0 { ... }; }`
- 主线：`panel: panel-dpi { ... port { panel_in: endpoint { ... }; }; }; &lcdif { port { lcdif_out: endpoint { ... }; }; }`

### sim2 节点

主线内核的 `imx6ul.dtsi` 缺失 sim2 节点定义，移植时需要手动添加。

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
