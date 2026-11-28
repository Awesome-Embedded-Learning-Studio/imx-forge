# IMX-Forge 项目路线图（愿景）

> **最后更新**：2026-11-28
> 本文件只讲定位与方向，不登记具体条目；执行追踪见 [todo.md](todo.md)。

## 定位判词

**imx-forge 是稳定、入门友好的 Embedded Linux 工坊，AELS 嵌入式工程开发的大入口。**

- **负责**：把正点原子阿尔法（i.MX6ULL）从源码带到可用系统——启动链、mainline 内核、设备树、板级驱动、烧录镜像、真板交付、QEMU 等价验证。
- **不负责**：通用 Linux 命令、通用内核模块 API、通用 Qt 通识（路由给 EmbedBox / PenguinLab / Tutorial_AwesomeQt，迁移按「先声明、后迁移」原则推进）。

## 四个共同方向

1. **可验证**（第一优先级）：「网站能部署」升级为「知识、代码、工程被 CI 证明」——模拟器先行，最后落到真板。
2. **精细化**：LLM 产线只做初稿，每个模块是否保留、技术是否可信，最终由人判断和签收。
3. **清晰化**：四问页（前置/负责/不负责/学完去哪）+ 路由声明，让学习者不迷路。
4. **工程交接**：教程必须有工程终点——从 light-meter 孤本走向项目梯队，应用打进镜像、开机自启。

外加 **Windows 复现** 扩展方向：WSL2 为一等公民，QEMU 出画面不依赖真板与串口。

## 里程碑

| 版本 | 时间 | 内容 |
|---|---|---|
| v0.5 | 2026-03 | Mainline 内核迁移 + QT6 支持 |
| v1.0.0 | 2026-06 | SD/eMMC 完整构建→烧录→启动闭环 |
| 下一站 v1.1.0 | 待发 | U-Boot 上游化 + 内核 7.2.9 拷贝机制 + 七分区导航 + 调试卷（清单见 todo.md 治理线） |

## 想参与

按 todo.md 的「当前重点」挑一条，在 issue 里声明后开工。贡献流程见 [CONTRIBUTING.md](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/CONTRIBUTING.md)。
