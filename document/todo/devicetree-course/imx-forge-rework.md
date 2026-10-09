# 设备树课程改造方案（imx-forge 侧）

> **状态**：草案，待确认
> **日期**：2026-10-09
> **配套文档**：[standalone-repo.md](standalone-repo.md)（设备树原理独立仓库规划）
> **依据**：2026-10-09 设备树教学深度调研。核心结论：`document/tutorial/driver/01_device_tree_base/` 现有 12 章（5711 行）结构性冗余严重（01/04 重复、05/07/08 三章一套内容、09/10 流程互拷、同一 DTS 节点贴 6 遍），多处事实错误与失效前提，11/12 章文风断裂；外围文档另有三份基础知识重复拷贝（DEVICE_TREE_GUIDE 第一部分、uboot/05、kernel/05 部分）。
> **总方针**：深度原理内容迁往独立仓库，imx-forge 收缩为"本仓实践卷 + 各卷引用 + 脚本文档"，动手环节全部锚定本仓真实文件与脚本。

---

## 一、内容边界

| 内容 | 去处 |
|---|---|
| 历史与动机（原始邮件考据） | 独立仓库 · 甲篇 |
| DTB 二进制格式、手搓解析器项目 | 独立仓库 · 乙篇 |
| DTS 语法全解、dtc 用法与内部 | 独立仓库 · 丙篇 |
| 内核消费链（r2 传递、unflatten、device_node、of API、匹配、of_platform_populate） | 独立仓库 · 丁篇 |
| bindings 与 YAML schema、overlay | 独立仓库 · 戊篇 |
| 内核两阶段编译机制（cpp + dtc、Makefile.dtbs） | 独立仓库 · 丙篇 |
| OF API 落到 LED 驱动的改造实操、上板点亮 | imx-forge 实践卷 |
| 板级 dts 修改、build/deploy 脚本、毕业项目 | imx-forge 实践卷 |
| pinctrl 五元组、i.MX 引脚电气配置 | imx-forge（02_pinctrl_gpio，不动） |
| 各驱动章节的 05 设备树小节 | imx-forge（不动，分层范本） |
| U-Boot 修整 DTB 的通用机制（bootm fixup、fdt_support） | 独立仓库 · 丁篇第 1 章 |
| 本板 imx6ull-aes 的 dts 走析、QEMU dtb、脚本文档 | imx-forge |

三条接缝的既定判断（2026-10-09 讨论）：

1. **pinctrl**：i.MX 五元组与位分解留在本仓 02 章；独立仓库只讲 pinctrl binding 的通用结构（状态、消费者与提供者），不讲具体芯片。
2. **两阶段编译**：机制进独立仓库丙篇；本仓只留 `driver_buildlib.sh` 的迁移记（脚本文档）。
3. **U-Boot**：bootm 修整 DTB 的通用逻辑进独立仓库丁篇；本板 dts 走析留在 uboot 卷。

---

## 二、01_device_tree_base 收缩映射（12 章 → 5 章）

| 旧章 | 去向 |
|---|---|
| 01 简介 | 动机速览并入新实践卷第 1 章；Linus 史实部分移交独立仓库甲篇（考据后重写） |
| 02 DTC 深入 | 主体（编译器原理、DTB 格式、make dtbs）移交独立仓库丙篇；本仓保留"用 dtc 干活"的最小用法，并入实践卷第 2 章 |
| 03 语法详解 | 全解移交独立仓库丙篇；本仓保留"语法速览"（以能读懂本仓 dts 为界），并入实践卷第 2 章 |
| 04 历史演进 | 整体移交独立仓库甲篇（与 01 的动机部分合并）；本仓只留一段导言 |
| 05 OF API 基础 | API 机理移交独立仓库丁篇；"在 LED 驱动里用 OF API"并入实践卷第 3 章 |
| 06 OF API 验证 | "主线 vs IMX 内核对比"前提已失效（项目 mainline 单轨），整节废弃；验证方法改写后并入实践卷第 3 章动手环节 |
| 07 驱动代码对比 | 并入实践卷第 3 章开头，作为改造的引子 |
| 08 设备树驱动改造 | 实践卷第 3 章主干 |
| 09 板级 DTS 修改实操 | 实践卷第 4 章主干 |
| 10 完整实战演练 | 实践卷第 5 章（毕业项目），砍掉与 09 重复的流程段，附录代码与仓库同步 |
| 11 编译机制深度解析 | 通用机制移交独立仓库丙篇；本仓收缩为 `driver_buildlib.sh` 脚本文档 |
| 12 编译机制迁移实践 | 同上，收缩为脚本文档并修复死链 |

新实践卷各章规格（目录名暂保留 `01_device_tree_base`，编号不动，减少外部链接 churn）：

| 章 | 标题（草案） | 目标 | 底子 | 动手锚点 |
|---|---|---|---|---|
| 1 | 设备树与本仓的学习地图 | 一页说清为什么有设备树、本仓 dts→dtb→板子的产物链、深读路线 | 旧 01 压缩 | 站在 `driver/device_tree/alpha-board/` 认文件 |
| 2 | 语法速览：读懂本仓的 dts | 节点、属性、phandle、cells、引用覆盖，讲到能读懂 imx6ull-aes.dtsi 为止（实测 dts 为 45 行薄壳、dtsi 为 886 行板级正文，验收线取 dtsi，2026-10-09 主控裁决） | 旧 03 压缩 | 用 dtc 反编译本仓真实 dtb，对照 dts 读 |
| 3 | 从硬编码到设备树驱动 | 07 的对比引出，08 的渐进改造做主干，06 的验证法落到动手 | 旧 07+08+06 | `build_driver.sh` 编译、`/proc/device-tree` 验证、上板点亮 |
| 4 | 板级 dts 修改与部署 | 加节点→编译→部署→验证全流程 | 旧 09 | build/deploy/show_device_tree 三脚本全流程 |
| 5 | 毕业项目：完整闭环 | 从空白 dts 到上板亮灯六步闭环 | 旧 10 | 全流程独立完成；附录与仓库代码逐字同步 |

每章末尾放"深读链接"块（`::: details` 或固定小节），指向独立仓库对应章。独立仓库章名定稿前，此块先留占位不写死链接（VitePress `ignoreDeadLinks: false`，死链会断构建）。

---

## 三、外围文档改造清单

| 文件 | 动作 |
|---|---|
| `tutorial/uboot/05_device_tree_basics.md` | 删历史、.dts/.dtsi、四大属性等基础重讲（约六成篇幅），换成指向独立仓库与本仓实践卷的链接；保留 U-Boot 特有内容（`*-u-boot.dtsi`、devicetree-rebasing、`CONFIG_OF_LIBFDT`）、本板 dts/dtsi 逐段走析、正点原子对比、时钟 assigned-clocks |
| `tutorial/kernel/05_kernel_device_tree.md` | 内核数据结构、unflatten、匹配机制等深度内容移交独立仓库丁篇；本卷收缩为"本仓内核怎么拿到 dtb（make dtbs、defconfig、部署）+ 本板调试法"，深度换链接 |
| `tutorial/kernel/mainline/06_dts_migration.md` | 保留独有增量（OF graph、delete-property、phandle_references 排查案例）；开头的基础重讲删成链接 |
| `modules/DEVICE_TREE_GUIDE.md` | 第一部分（基础回顾）换成导引链接；保留本板 dts/dtsi 详解、外设配方、移植步骤、调试速查，定位仍是本仓参考手册 |
| `tutorial/driver/02_pinctrl_gpio/04、06` 与 `03_platform_led_driver/05` | LED 案例三连讲收敛为一次完整讲解（留在 02 章），03 章回指不重复；三处 compatible 拼写统一（见事实清单） |
| `scripts/driver_helper/show_device_tree.sh.md` 与 `show_device_tree.md` | 两份合并为一份：用户手册为主体，脚本内部机制折叠进 `details` 块 |
| `scripts/qemu_helper/make-qemu-dtb.sh.md` | 按脚本当前行为整体重写：真机 dts 直编 + fdtput 补 MAC，无 QEMU 变体、无 12 节点表 |
| `driver/06_tutorial_device_tree_try/` 源码头注释 | 清理指向已不存在路径的注释（`document/tutorial/driver/device_tree_compile/...` 等） |
| `01_device_tree_base/index.md` | 修 `gnueabhif`→`gnueabihf`；章节列表随收缩重写；"内核 7.1.0 唯一轨"口径全文贯彻 |

---

## 四、事实修正清单（内容无论落在哪，逐项打勾）

1. 兼容串拼写三处不一（调研见到 `atkalpha-led`、`imxaes_led`、`imxaes,led` 三种）：以真实 dts 文件为准统一，动手前逐文件核对真实值，不凭调研转述定案。
2. 旧 03 章"空属性后面没有分号"与相邻代码块（带分号）自相矛盾：修正，并顺带纠正把 `#gpio-cells = <2>` 归入空属性的分类错误。
3. 旧 04 章 Linus 引文查无出处、峰会地点错误：史实叙述迁独立仓库甲篇时全部换成 lore.kernel.org 可查证原文，查不到的删。
4. 旧 10 章附录"完整代码清单"与仓库 `led_hw.c` 不一致：重写时附录直接从仓库文件生成或逐字核对。
5. 旧 06 章"IMX 内核验证"整节（同目录自比自）废弃，随第 3 章重写。
6. 旧 12 章两个死链（`scripts/examples/example_driver.md`、`scripts/driver_helper/workflow.md`）：随脚本文档化修复。
7. 旧 02/06/11/12 章依赖 `third_party/linux_mainline` 的命令：显式标注"需先初始化 submodule"，并在章首交代前提。
8. 全套"上一章/下一章"指代（已知至少一处错乱）：收缩后逐章重排时全文检查。
9. atk/ALIENTEK 语境残留（`imx6ull-atk.dts` 示例、`Machine: ALIENTEK` 输出示例）：替换为本仓 aes/alpha-board 语境，或在出现处一句话交代命名来历。

---

## 五、执行顺序与验收

| 阶段 | 内容 | 依赖 |
|---|---|---|
| 0 | 独立仓库骨架 + 试点章（见配套文档），声音校准 | 无 |
| 1 | 实践卷第 3 章试写（全套最难：去重 + 动手落地 + API 不字典化三合一） | 阶段 0 声音认可 |
| 2 | 实践卷第 1、2、4、5 章 | 阶段 1 通过 |
| 3 | 外围瘦身（第三节清单逐项） | 独立仓库篇名定稿（部分链接才有的放矢） |
| 4 | 脚本文档合并重写、死链清理、index 重写、全站链接检查 | 前三阶段 |

验收标准（每阶段通用）：

- 每条 shell 命令在仓库当前状态可复现；依赖 submodule 的显式标注前提。
- 每个引用的路径、脚本名、脚本参数逐一与仓库实际核对。
- 文风按 `.claude/content_forge/writing_style.md`，每章走 content_forge 写手 + 声音/保真走查闭环，范文锚 `buildroot/11_qt6_integration.md`。
- 站点构建通过：`ignoreDeadLinks: false`，任何站内链接改动后必须全站过 build。
- 事实修正清单在本侧涉及的项逐项销号。

---

## 六、代价与风险（已知，接受才开工）

1. **跨仓断点**：读者在实践卷学到一半需跳独立仓库深读，靠每章"深读链接"缝接；反向同理。
2. **双仓同步**：独立仓库改版（章名、口径）时，本仓实践卷与外围引用要回头检查。
3. **目录收缩的入链检查**：12 章 → 5 章会删文件、改文件名，动手前 grep 全站对 `01_device_tree_base/` 的入链并逐一改指向。

---

## 七、待确认

1. 实践卷是否留在 `01_device_tree_base` 原目录名下收缩（我的建议：是，少动入链）。
2. 阶段 1 的试点章选第 3 章还是第 1 章（我的建议：第 3 章，理由见第五节）。
3. 外围瘦身阶段，uboot/05 与 kernel/05 收缩后是否保留原章号（建议保留，侧栏编号稳定）。
