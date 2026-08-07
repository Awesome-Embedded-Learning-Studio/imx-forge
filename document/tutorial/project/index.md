---
title: 应用项目
---

<PageHeader icon="🚀" title="应用项目" description="把工具链、内核、驱动、应用代码缝成一个能在板子上跑起来的真实产品" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="light-meter/">照度护眼摆件 light-meter —— 从桌面 Mock 到板子真机的造工程全流程</ChapterLink>
</ChapterNav>

::: tip 这个卷在做什么
这里放的是「复合项目」——不再是某一个单点知识(怎么编 U-Boot、怎么写字符设备),而是带你把已经学过的零件缝成一个**完整产品**:从一份空的 `CMakeLists.txt`,到一个在板子上会呼吸、会告警、会息屏、能导出数据的常驻应用。

light-meter 是第一个项目。后续 [PROJ-001 便携式环境监测站](../../todo/projects/proj-001-env-monitor.md) 等旗舰会陆续加入这个卷。
:::

::: info 和其他卷的关系
本卷的每一个项目都是**自包含的工程教学**:除了一处例外——项目依赖的具体硬件驱动会指给你本仓库对应的驱动章节(例如 light-meter 的 AP3216C 指向 [driver/08](../driver/08_i2c_ap3216c_driver/))——其余的工程本事(C++、Qt、CMake、Mock、部署、标定)都在项目教程里讲够,不需要你先读完 buildroot、practical 再来。
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../practical/" variant="sub">← 实战演练</ChapterLink>
  <ChapterLink href="light-meter/" variant="sub">light-meter →</ChapterLink>
</ChapterNav>
