---
title: 参考资源索引
---

<PageHeader icon="📚" title="参考资源索引" description="i.MX6ULL 嵌入式开发相关的官方文档、手册、源码仓库与社区入口" />

::: tip 专栏定位
这里集中了 IMX-Forge 开发过程中最常查阅的**外部权威资源**入口：NXP 官方文档、上游项目（U-Boot/Linux/设备树/Buildroot/Yocto/Qt）、ARM 工具链，以及社区论坛。按需查阅，不必通读。
:::

## 一、NXP 官方

| 资源 | 链接 | 说明 |
|------|------|------|
| i.MX6ULL 产品页 | https://www.nxp.com/products/i.MX6ULL | 所有文档（datasheet/RM/应用笔记/勘误）的入口 |
| Datasheet（消费级） | https://www.nxp.com/docs/en/data-sheet/IMX6ULLCEC.pdf | IMX6ULLCEC |
| Datasheet（工业级） | https://www.nxp.com/docs/en/data-sheet/IMX6ULLIEC.pdf | IMX6ULLIEC |
| i.MX Reference Manual (Linux) | https://www.nxp.com/docs/en/reference-manual/i.MX_Reference_Manual_Linux.pdf | Linux BSP 层面参考手册 |
| 芯片级 Reference Manual | 产品页 "Documentation" 标签 | IMX6ULLRM，寄存器级文档，**需 NXP 账号** |
| NXP 文档中心 | https://www.nxp.com/design/design-center/documentation:DOCUMENTATION | 全部公开/受限技术文档 |

## 二、i.MX6ULL 手册速查

::: info datasheet vs reference manual
- **Datasheet**：电气特性、引脚定义、封装、机械参数——硬件设计看这个；
- **Reference Manual (RM)**：寄存器、外设控制器工作原理、时序——驱动/固件开发看这个。

两者都要，NXP 账号免费注册即可下载。
:::

| 文档 | 文档号 | 用途 |
|------|--------|------|
| i.MX 6ULL Datasheet | IMX6ULLCEC / IMX6ULLIEC | 电气/引脚/封装 |
| i.MX 6ULL Reference Manual | IMX6ULLRM | 寄存器/外设原理 |
| 硬件开发指南 | 产品页下载 | PCB 设计检查清单、电源/时钟/复位要求 |

## 三、NXP Linux BSP

| 资源 | 链接 | 说明 |
|------|------|------|
| i.MX Linux BSP 官方页 | https://www.nxp.com/design/design-center/software/embedded-software/i-mx-software/embedded-linux-for-i-mx-applications-processors:IMXLINUX | BSP 发布包、Release Notes、用户指南 |
| linux-imx 内核仓库 | https://github.com/nxp-imx/linux-imx | NXP 维护的 i.MX 内核（本项目 NXP 轨用此） |
| meta-imx (Yocto BSP) | https://github.com/nxp-imx/meta-imx | Yocto Project i.MX BSP 层 |
| mfgtools | https://github.com/nxp-imx/mfgtools/releases | NXP 官方量产烧录工具（UUU 上游） |
| nxp-imx 组织 | https://github.com/nxp-imx | 全部 i.MX 相关仓库 |

::: tip IMX-Forge 的双轨策略
本项目同时用 NXP BSP（`third_party/linux-imx`，6.12.3，稳定）和 Mainline（`third_party/linux_mainline`，7.1，紧跟上游）。见 [kernel/ 教程](../tutorial/kernel/)。
:::

## 四、U-Boot

| 资源 | 链接 | 说明 |
|------|------|------|
| U-Boot 官方文档 | https://u-boot.readthedocs.io/ | |
| 官方仓库 | https://source.denx.de/u-boot/u-boot | |
| GitHub 镜像 | https://github.com/u-boot/u-boot | |
| DENX wiki | https://docs.denx.de/ | |

## 五、Linux Kernel

| 资源 | 链接 | 说明 |
|------|------|------|
| Kernel 文档 | https://www.kernel.org/doc/html/latest/ | 内核自带文档（含驱动子系统、设备树绑定） |
| Kernel.org | https://www.kernel.org/ | 源码发布 |
| man pages | https://www.kernel.org/doc/man-pages/ | 用户态接口手册 |
| Kernel Newbies | https://kernelnewbies.org/ | 内核开发入门 |
| Bootlin 培训材料 | https://bootlin.com/docs/ | 免费 Linux/嵌入式培训 |

## 六、设备树

| 资源 | 链接 | 说明 |
|------|------|------|
| Device Tree 规范 | https://www.devicetree.org/ | Device Tree Specification（本项目 third_party 收录 v0.4 PDF） |
| elinux Device Tree | https://elinux.org/Device_Tree | 嵌入式 Linux wiki 综述 |
| 内核 DT 绑定文档 | https://www.kernel.org/doc/html/latest/devicetree/bindings/ | bindings/ 源码即文档 |
| dtc 工具 | https://git.kernel.org/pub/scm/utils/dtc/dtc.git | 设备树编译器 |

## 七、Buildroot

| 资源 | 链接 | 说明 |
|------|------|------|
| Buildroot 官网 | https://buildroot.org/ | |
| Buildroot Manual | https://buildroot.org/downloads/manual/manual.html | 官方手册（本项目 rootfs 主方案） |
| Buildroot wiki | https://github.com/buildroot/buildroot/wiki | |
| 仓库 | https://git.buildroot.net/buildroot/ | |

## 八、Yocto Project

| 资源 | 链接 | 说明 |
|------|------|------|
| Yocto 官网 | https://www.yoctoproject.org/ | |
| Yocto 文档 | https://docs.yoctoproject.org/ | Mega-Manual、BitBake、开发指南 |
| meta-imx | https://github.com/nxp-imx/meta-imx | i.MX 的 Yocto BSP 层 |

::: tip Buildroot vs Yocto
IMX-Forge 选用 **Buildroot** 作为 rootfs 方案（轻量、构建快、易理解），见 [buildroot 教程](../tutorial/buildroot/)。Yocto 适合需要包管理与长期维护的产品级发行版。
:::

## 九、Qt

| 资源 | 链接 | 说明 |
|------|------|------|
| Qt 文档 | https://doc.qt.io/ | 各模块 API |
| Qt Wiki | https://wiki.qt.io/ | 社区知识库 |
| Qt 嵌入式/Linux | https://doc.qt.io/qt-6/embedded-linux.html | Qt on 嵌入式 Linux（eglfs/linuxfb） |

## 十、ARM GCC 工具链

| 资源 | 链接 | 说明 |
|------|------|------|
| ARM GNU Toolchain 下载 | https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads | 官方预编译工具链 |
| ARM 开发者工具页 | https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain | |
| 工具链文档 | https://developer.arm.com/documentation | GCC/LD/GDB 文档 |

::: tip IMX-Forge 用的工具链
本项目用 **ARM GNU Toolchain 15.2.rel1**（`arm-none-linux-gnueabihf-`），由 Docker 镜像预装。见 [Docker 教程](../tutorial/docker/)。
:::

## 十一、社区与论坛

| 资源 | 链接 | 说明 |
|------|------|------|
| NXP 社区 | https://community.nxp.com/ | 官方论坛，i.MX 板块活跃 |
| Stack Overflow | https://stackoverflow.com/ | 通用编程/嵌入式问答 |
| Linux 内核邮件列表 | https://lkml.org/ | 内核开发讨论 |
| elinux.org | https://elinux.org/ | 嵌入式 Linux wiki |
| 正点原子论坛 | http://www.openedv.com/ | 本项目所用开发板厂商社区 |

## 本项目内部资源

- 教程目录：[tutorial/](../tutorial/)
- 脚本说明：[scripts/](../scripts/)
- 项目规划：[todo/](../todo/)
- 第三方资料 PDF：[third_party/](../tutorial/third_party/)
