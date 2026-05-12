<PageHeader icon="🐧" title="内核教程" description="Linux 内核是嵌入式系统的核心，理解内核是成为高级嵌入式开发者的必经之路" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_kernel_overview">内核概述</ChapterLink>
  <ChapterLink num="02" href="02_kernel_compile">内核编译</ChapterLink>
  <ChapterLink num="03" href="03_kernel_config">内核配置</ChapterLink>
  <ChapterLink num="04" href="04_kernel_modules">内核模块</ChapterLink>
  <ChapterLink num="05" href="05_kernel_device_tree">设备树详解</ChapterLink>
  <ChapterLink num="06" href="06_wsl_network_boot">网络启动</ChapterLink>
  <ChapterLink num="07" href="07_driver_basic">驱动基础</ChapterLink>
  <ChapterLink num="08" href="08_kernel_boot_debug">启动调试</ChapterLink>
</ChapterNav>

## 双轨内核策略

IMX-Forge 支持两种内核：

| 轨道 | 版本 | 特点 | 适用场景 |
|------|------|------|----------|
| **linux-imx** | NXP BSP 6.12.3 <Badge type="tip" text="推荐" /> | 稳定，驱动完善 | 生产环境、新手 |
| **mainline** | 上游主线 <Badge type="info" text="进阶" /> | 长期维护，可贡献 | 追求最新特性 |

<ChapterNav variant="sub">
  <ChapterLink href="mainline/" variant="sub">Mainline 主线内核 —— 迁移指南</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解 Linux 内核的组成和启动流程，独立编译配置内核，掌握设备树编写和简单字符设备驱动开发。
:::

::: info 前置知识
C 语言高级特性 · 计算机组成原理 · U-Boot 基础
:::

::: details 延伸阅读
- [Linux 内核官方文档](https://www.kernel.org/doc/html/latest/)
- [Linux 设备树规范](https://www.devicetree.org/)
- [内核驱动开发指南](https://www.kernel.org/doc/html/latest/driver-api/)
- [i.MX6ULL 参考手册](https://www.nxp.com/docs/en/reference-manual/IMX6ULLRM.pdf)
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../uboot/" variant="sub">← U-Boot 教程</ChapterLink>
  <ChapterLink href="../rootfs/" variant="sub">根文件系统 →</ChapterLink>
</ChapterNav>
