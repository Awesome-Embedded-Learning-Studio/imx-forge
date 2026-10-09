# 设备树原理独立仓库规划

> **状态**：草案，待确认
> **日期**：2026-10-09
> **配套文档**：[imx-forge-rework.md](imx-forge-rework.md)（imx-forge 侧改造方案）
> **一句话**：一套不依赖任何开发板的设备树原理课，主线是"按规范手搓一个 DTB 解析器 + 走读 Linux 内核怎么消费设备树"，前四分之三内容在宿主机上完成。

---

## 一、定位与受众

- **受众**：会 C 和 Makefile 的工程师。读过任意字符设备驱动教程更好，不强制；**全程不需要开发板**。手搓解析、语法实验、dtc 对拍都在宿主机；内核走读章节只需要一份内核源码。
- **与 imx-forge 的关系**：imx-forge 保留"本仓实践卷"（改本仓 dts、跑本仓脚本、上板点亮），本仓库承载原理、格式、工具链、内核消费的深度内容。双向互链，不重复讲述。
- **语言**：正文中文，代码、命令、标识符英文。
- **不做什么**：不做完整的 DTS→DTB 编译器（那是 dtc 的工程量，不服务教学）；不做 overlay 应用器（戊篇只讲机制与使用现成工具）；不绑定任何具体 SoC。

## 二、仓库基建

- **命名候选**（待拍板）：`devicetree-from-scratch`（首选，呼应手搓主线）、`dt-internals`、`devicetree-lab`。
- **形态**：起步纯 Markdown，GitHub 直读，不建站。结构稳定后可选：submodule 挂进 imx-forge 站点，或独立建站。起步阶段不背基建。
- **目录布局草案**：

```
README.md            课程地图、学习路径、环境前提
chapters/            甲乙丙丁戊五篇正文
parser/              手搓解析器 dtbwalk 源码（C11 + Makefile）
materials/           考据材料：原始邮件链接、规范引用位置、实验真实输出
tools/               配套小脚本（对拍、生成测试用 dtb）
```

- **许可证**：默认 MIT，待拍板。
- **实验输入**：自写最小 dts 编译产物 + mainline 树内简单板卡 dts 编译产物，两组都不依赖私有材料。

## 三、篇章结构（15-16 章）

### 甲篇 · 历史与动机（2 章）

| 章 | 内容 | 素材 |
|---|---|---|
| 甲1 板级代码的困境 | ARM mach-xxx 膨胀的真实代价；Linus 2011 年 3 月邮件原文考据（lore.kernel.org 链接，引文逐句可查证，查不到的不写） | lore 存档、内核 git 史 |
| 甲2 从 OF 到规范 | PowerPC 血统、IEEE 1275、ePAPR、Devicetree Specification v0.4 的演进关系；"规范现在到哪、内核支持到哪"写明版本口径 | devicetree.org 存档 |

### 乙篇 · 格式与手搓解析（4 章，本仓库主打）

| 章 | 内容 | 交付物 |
|---|---|---|
| 乙1 DTB 二进制格式走读 | 按 devicetree-specification v0.4 第 2 章逐字段讲 FDT header、内存保留区、结构块、字符串块 | 动手：hexdump 真实 dtb，人工认出 magic、版本、各块偏移 |
| 乙2 手写 walker（上） | 结构块 token 协议（FDT_BEGIN_NODE / END_NODE / PROP / NOP / END），遍历算法 | dtbwalk M2：列出任意 dtb 的全部节点路径 |
| 乙3 手写 walker（下） | 属性值解码（cells、string、bytes、phandle 引用），内存中的树表示 | dtbwalk M3-M4：树状 dump + phandle 引用解析 |
| 乙4 对拍与边界 | 与 `dtc -I dtb -O dts` 输出对拍验证；边界情况（空属性、别名、异常长度、未对齐访问）；并排对照 libfdt 同职责函数 | dtbwalk M5：对拍通过；一章"自己写的和 Linux 用的对上了" |

### 丙篇 · 语言与工具链（3 章）

| 章 | 内容 | 底子 |
|---|---|---|
| 丙1 DTS 语法全解 | 节点、标签、属性类型、标准属性（compatible/status/reg/cells/ranges），示例全部中性化（spec 示例 + 自写示例），不绑 i.MX | 旧 03 章骨架 |
| 丙2 组织与覆盖 | dtsi、`/include/` 与 cpp、标签引用、`&节点` 覆盖、`/delete-node/`、`/delete-property/`、phandle 的自动生成 | 新写 |
| 丙3 dtc 与两阶段编译 | dtc 用法（`-@`、`-I/-O`、告警分级）；dts→cpp 预处理→dtc 的内核构建机制（`Makefile.dtbs`、`-D__DTS__`） | 旧 02、11 章骨架 |

### 丁篇 · 内核消费（4 章，需要内核源码）

| 章 | 内容 |
|---|---|
| 丁1 DTB 怎么到内核手里 | bootloader 的角色、r2（ARM32）/x0（ARM64）约定、U-Boot `bootm` 对 DTB 的修整（`fdt_support` 通用逻辑：chosen、memory、MAC 传递）、`fdt chosen` 与 bootargs |
| 丁2 从扁平到树 | `early_init_dt_scan` 选板与提前扫描、`unflatten_device_tree` 怎么把 FDT 变成 `device_node` 链、早期内存分配的限制；与乙篇"我们自己建树"对照 |
| 丁3 内核里的设备树 API | `device_node`/`property` 结构、`of_find_node_*` 家族、`of_property_read_*`、`of_iomap`、引用计数（`of_node_put`）；用 modprobe 一个小模块在 `/proc/device-tree` 上做实验 |
| 丁4 设备怎么被创造 | compatible 与 `of_match_table`（含 `MODULE_DEVICE_TABLE`）、`of_platform_populate` 生成 platform device、reg/ranges/中断解析入口、`/sys/firmware/devicetree` 与 `/proc/device-tree` 的来历 |

### 戊篇 · 进阶（2-3 章）

| 章 | 内容 |
|---|---|
| 戊1 bindings 契约与 schema | binding 是什么、YAML schema 与 `dt-validate`、写一个最小 binding 并让它拒绝一个坏 dts |
| 戊2 overlay | `/plugin/` 语法、`dtc -@` 符号、configfs 应用流程、U-Boot `fdtoverlay`；适用与不适用的场景判断 |
| 戊3（可选）排查方法论 | 常见故障与定位路径；也可拆散并入各章，写时定 |

## 四、手搓解析器 dtbwalk 规格

- **范围**：解析 DTB（FDT 二进制）→ 输出可读树。非目标：DTS 编译、overlay 应用、dtb 修改。
- **形态**：C11、单 Makefile、零第三方依赖，宿主机 gcc 直接编。读者按章节渐进实现；仓库里每个里程碑对应一个可编译快照（tag 或 `parser/snapshots/M<n>/`），跟丢的读者可以直接对代码。
- **里程碑**：M1 header 解析与 magic/版本校验 → M2 结构块遍历 → M3 属性解码与树构建 → M4 phandle 引用解析 → M5 对拍通过（输入：自写 dts 编译产物 + mainline 树内板卡 dtb 两组）。
- **教学设计**：关键步骤与内核 `lib/fdt`、`drivers/of/fdt.c` 的同职责函数并排对照（乙3、乙4、丁2），手搓不是为了替代 libfdt，是为了让读者再看 libfdt 时每一行都有着落。

## 五、证据与版本纪律（全仓硬规矩）

1. 每章标注"验证于 mainline vX.Y / dtc vX.Y"；内核引用优先级：函数名 > 文件路径 > 行号。
2. 历史叙述的每句引文给出处链接（lore.kernel.org / lwn.net / 规范原文）；给不出处的删。
3. 所有贴出的实验输出必须来自真实运行；不允许"示意输出"。
4. 规范锚定 v0.4（与 imx-forge 内 PDF 同版），升版时逐章复查。

## 六、执行阶段

| 阶段 | 内容 | 备注 |
|---|---|---|
| 一 | 仓库骨架 + 乙1 试写 | 声音校准试点，主打内容先行；用户认可后铺开 |
| 二 | 乙2-乙4 + dtbwalk M1-M5 | 代码与章节同步推进，每章可编译 |
| 三 | 甲篇（考据自行完成）、丙篇（旧 02/03 骨架改造） | |
| 四 | 丁篇 | 依赖内核 submodule 检出（见资料清单） |
| 五 | 戊篇 + 全仓链接检查 + 对拍回归 | imx-forge 侧"深读链接"在此阶段接入 |

## 七、开工资料清单

**需要用户给的：**

1. submodule 初始化（丁篇、丙篇走读的前提）：`git submodule update --init third_party/linux_mainline third_party/uboot-imx`。可以你跑，也可以授权我在 imx-forge 里跑，下载量大。
2. 仓库命名与放置：个人账号还是 Awesome-Embedded-Learning-Studio 组织下。
3. 许可证（默认 MIT）。

**我自行取用的：**

- Linus 2011 年 3 月 arm 内核邮件列表原文（lore.kernel.org）。
- ePAPR v1.1 / IEEE 1275 历史材料（devicetree.org 存档）。
- mainline 内核 `Documentation/devicetree/`（submodule 起来后本地就有）。
- Devicetree Specification v0.4（imx-forge 仓库已有 PDF）。
- 同类优秀材料（free-electrons 设备树讲座、LWN 设备树系列文章、内核 usage-model 文档）：只做核对与参考，不做逐句搬运；具体篇目在甲篇考据时定，引用处逐一给链接。

---

## 附：与 imx-forge 的同步义务

- 本仓库篇名/章名/口径变更时，通知检查 imx-forge 实践卷"深读链接"与外围引用。
- imx-forge 的脚本或板级文件变化不影响本仓库（无硬依赖，实验输入自备）。
- 两仓各自独立发版，不共享 CI。
