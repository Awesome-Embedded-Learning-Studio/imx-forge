# IMX-Forge 待办与执行追踪

> **最后更新**：2026-11-28（M0 三轨合一：本文件取代原 roadmap/todo/directions 三轨，成为唯一待办登记处）
> **任务来源**：2026-08-31 全面优化计划（2026-11-28 清账后）+ 旧方向清单收编
> **维护约定**：任何待办只在本文件登记一次。开工前把状态改为进行中，完成后勾选并附证据链接，不再另开记录。

## 使用规则

- 状态标记：`[ ]` 排队，`[~]` 进行中（有分支/PR 的附链接），`[x]` 完成（完成后移入文末归档节）。
- 明确不做的写进「冻结与放弃」节，附一句原因，不留空挂。
- GitHub Issues 是薄指针：新需求先在本文件登记，再开 issue 指向这里的条目；issue 完成后关闭，不在 issue 里维护勾选框。
- 每条尽量带证据链接（issue 号、commit、文档路径），让「做没做」可以一眼核实。

## 当前重点（2026-11-28）

1. 可验证线：e2e 全量进 CI（smoke 已接，全量断言未接）。
2. 精细化线：风格四裁定——三期源码章重写与存量修复的共同前置。
3. 治理线：本文件即 M0 落地；后续按「issue 薄指针」约定运行。

---

## 一、可验证（组织第一优先级）

### CI 接线（剩余三档，smoke 档已于 #106/#135 合拢）

- [ ] **P1** e2e 全量 job：ci-full 加 `qemu-e2e`，跑 `e2e-test.sh` 全部断言，报告上传 artifact（出处：op_plan/02 §二第 2 档）
- [ ] **P1-P2** 驱动 .ko 真跑：drivers job 产物拷进 rootfs，e2e 里 insmod + 断言行为，先拿 icm20608 做示范（op_plan/02 §二第 3 档）
- [ ] **P2** 站点与文档防线：deploy 加外链检查 job；ChapterLink 组件 href 构建期对账（op_plan/02 §二第 4 档）

### 教程挂钩

- [ ] **P1** emu 第 9 章「CI 冒烟教程章」：教读者看 e2e 报告、加断言（emu/index.md 自述待补）
- [ ] **P2** 驱动章 Verified 段挂 e2e 断言名（PWM 章最便宜：patch 0003 + `BL=yes` 断言已备）
- [ ] **P2** 每章最小验证命令试点（先 emu/driver 新章，不做全库运动）

### QEMU 工程后续

- [ ] **P2** icm20608 数据面修复（spi FIFO 字打包 quirk，修通后 A2/B2/C3 解卡）
- [ ] **P2** gt911 双 Begin/release 丢失修复（根因已定位：poll 间隙 INT idle 电平）
- [ ] **P2** QEMU 升版 11.2 rebase（16 连发 patch）+ U-Boot 启动链，2026-12 里程碑统一做
- [ ] **P2 卫生** apply_patches.sh 对 qemu 组件加豁免声明或警告

### 诚实性防线

- [ ] **P2** linux-basics 伪输出修复：ch15/ch16 的编造时间戳已改为示意值并加注（2026-11-28），真跑重采仍待做；其余章节抽查
- [ ] **P2** e2e 报告进 release assets，让「验证过」对外可追溯

### Windows 复现

- [ ] **P2** emu 卷加「Windows/WSL2 路线」章：WSL2 构建 QEMU → WSLg 出画面，全程实测
- [ ] **P2** QUICK_START 环境矩阵补「Docker Desktop on Windows」行（需与 CI 镜像含 qemu 联动）
- [ ] **P3** 最小 clone 路径文档（浅克隆 + 按需 submodule；kernel/03 与 uboot/02 已有零散指引）

---

## 二、清晰化与路由

### 四问页与路由声明（先声明、后迁移）

- [ ] **P1** 仓库级四问页：前置 / 负责 / 不负责 / 学完去哪，落点 start/00_roadmap.md 升格或 tutorial 顶部定位节（op_plan/03 §二）
- [ ] **P1** linux-basics 卷头冻结声明：通用 Linux 基础归属 EmbedBox，对应卷成文前不迁移
- [ ] **P1** Qt/C++ 分工声明：本仓只写板端部署，语言与桌面开发外链（写 app 相关章之前必须先立）
- [ ] **P2** modules / core-functional 与 PenguinLab 对表声明（对表前加「通用面重叠」标注）
- [ ] **P2** 多板支持政策页：alpha-board 为 Tier-1，异板给指路不承诺；#79 排查知识沉淀 qa_79（op_plan/03 §六）
- [ ] **P2** reference 增「AELS 学习树」节：EmbedBox → … → imx-forge → rk-forge/h618_forge → CFBox 等

### 导航单源收尾

- [ ] **P1** scripts/build_pdf.py 的 LEARNING_ORDER 改为读 project.config.ts 同源数据（现存最后一份手写副本，仍是老 12 卷清单）
- [ ] **P2** 编号体系统一：linux-basics 全局章号 vs 各卷重启、rootfs/08_nfs_bindmount 命名、driver 尾部子卷无编号（op_plan/03 §四）
- [ ] **P2** 「继续学习」链理顺：buildroot 下一站改指 project；emu 卷 DocNavCards 越界跳 driver 的 bug
- [ ] **P2** 卷 index 组织风格统一到 ChapterNav 组件
- [ ] **P2** linux-basics 7 个子目录补 index.md（#71 根因）

### 杂项

- [ ] **P1** buildroot/index.md 外链改组织仓库（现指个人 fork Charliechen114514/imx-forge）
- [ ] **P2** document/engineering/ci/index.md 触发矩阵按实测修（现称「不设 Release workflow」，实际 release.yml/docker-publish.yml 已存在）
- [ ] **P3** debug 卷补两篇排查专题：常见构建失败排查（kernel/13 部分覆盖）、rootfs 挂载失败排查（rootfs/05 部分覆盖；原 D1 待办收编）

---

## 三、工程交接

### 项目梯队（依赖就绪度排序，取代 #94 原顺序）

- [ ] **P1** B1 nightlight 自感应小夜灯（依赖全就绪；含 headless 变体回应 #95 开放问题）
- [ ] **P1** C1 touch-paint 触摸画板（host-mouse 桥已验证 evdev→Qt 全链）
- [ ] **P2** C3 sensor-dashboard 仪表盘（旗舰前置）
- [ ] **P2** A2 level-tool / B2 knock-detector（卡 icm20608 数据面）
- [ ] **P3** C2 voice-recorder（卡 wm8960 无音频模型，排最后）

### 打包与部署

- [ ] **P1** 应用打包通道：把 B1 或 C1 做成第一个真实 buildroot package（Config.in + .mk），开机自启进镜像；产出《一个应用从源码到进产品镜像》教程
- [ ] **P2** 无 GUI system demo 决策（建议 B1 拆 headless 变体）

### 工作流专栏收尾

- [ ] **P1** 「我是如何开发的」总纲篇（#101 标题承诺，串 Remote-SSH + clangd + 板端同步）
- [ ] **P2** perf/top/日志收集基础篇（RFC §6 尾巴）

### 驱动章分析型改造（板级实例保留、通用 API 百科不写，详见 #54 重构）

- [ ] **P2** 网络 fec/PHY/MDIO 分析章（吸收 #79 排查知识）
- [ ] **P2** PWM/背光分析短章（QEMU 断言已备，最便宜）
- [ ] **P2** UART 分析章；USB 短章；IIO/ADC 收敛一章；DMA 与音频合并叙事；Regmap 并入用例章
- [ ] **P2** 「换内核后驱动怎么办」单篇（vermagic/符号 CRC 机制 + BSP .ko 在 mainline 上 insmod 应失败的正反例）

### 结课资产

- [ ] **P2** CFBox PID-1 结课章（community/notes/2026-06-23 真实实验升格，与 CFBox 仓互链）
- [ ] **P2** BOM 页：alpha-board 板载外设清单 + 可扩展接口（start/03 扩展或 document/hardware/ 新页）
- [ ] **P2** #54 重构：勾已完成三项（RTC/触摸/音频），其余标三态
- [ ] **P2** #94 修订：勾 A1、顺序按就绪度重排、验收栏断言化、B1/C1/C3 开 sub-issue

---

## 四、精细化（写作产线）

### 先裁定后修复

- [ ] **P0** 风格四裁定成文（「」引号口径 / 行号锚点密度 / persona 适用范围 / 结构模板），同步 content_forge writing_style.md（op_plan/05 §二）
- [ ] **P1** 废弃 .claude/wrting_style.md（旧人格模板，与现档案互斥）

### lint 与门禁

- [ ] **P1** humanizer_lint.py 四缺陷修复（全角逗号逃逸 / 漏「我们」/ VitePress 容器误报 / enum_command 死占位）
- [ ] **P1** 双 profile 机制：--profile site（站内宽）/ --profile publish（发文包严）
- [ ] **P1** ci-pr 加 tutorial-lint job：只管增量（基线快照豁免存量），首月 warn-only

### 存量修复（L0 裁定 → 门禁止增量 → 机械 → 结构 → 核心列）

- [ ] **P2** L1 机械修复：非 persona 类 ERROR 约 889 处
- [ ] **P2** L2 结构统一：模板一套 + 编号体系 + 导航链
- [ ] **P2** L3' 核心列人称化：emu + driver 分析型 + buildroot（约 144 文件，分批）
- [ ] **P2** workflow 卷六篇人工技术签收（#108 重写后未签收）

### 草稿库处置

- [ ] **P2** 正点草稿库三态定案：采纳清单（走管线，禁止洗稿）/ 放弃（ch06-29 裸机 24 章）/ 悬案（触摸 I2C 地址、HDMI 桥片）
- [ ] **P2** 草稿库整目录 tar 备份到仓库外（巴士因子，4.1MB 仅本机）

---

## 五、治理与卫生

### 追踪（M0 已落地）

- [x] **P0** todo 三轨合一重写（2026-11-28 完成，即本文件；roadmap.md 缩编为愿景页，directions/ 收编删除）
- [ ] **P1** PR 模板加 checklist：若新增/完成 todo 条目，同步本文件
- [ ] **P2** #54、#94 修订后关闭；此后新需求走 issue → 本文件登记 → 关 issue

### Release 卫生

- [ ] **P1** 处理 tag 幽灵：v1.0.1-4 补 release 或删 tag（二选一）
- [ ] **P1** 发 v1.1.0：内容含 U-Boot 上游化 + 内核 7.2.9 拷贝机制 + 七分区导航 + debug 卷
- [ ] **P2** PDF 产物联动 release + 触发器修漂移（pdf-export.yml 仅手动触发，产物停在 06-23）

### QA 与知识沉淀

- [ ] **P1** qa_79：#79 异板 PHY 排查 + 放弃原因诚实记录
- [ ] **P1** qa_76+91 合并一篇《假成功的三种面孔》
- [ ] **P1** gt911 地址定案记进 qa/（裁定现仅记录在 driver/device_tree/alpha-board/linux/README.md）
- [ ] **P2** 立约定：issue 关闭前排查知识入 qa（写进 CONTRIBUTING 与 PR 模板）

### 贡献流程

- [ ] **P1** CONTRIBUTING.md 重写：stage3=BusyBox 过时表述、good-first-issue 空货架、三道贡献门禁预警（submodule 约定 / 单 patch 约定 / 脚本配 md）
- [ ] **P1** .github 模板：ISSUE_TEMPLATE（bug/doc 两类）、PULL_REQUEST_TEMPLATE（lint/配md/todo 同步 checklist）、CODEOWNERS

### 仓库卫生（一次 PR 扫掉）

- [ ] **P2** examples 预编译 ARM 二进制出库（hello_app/icm_app 各 2.7MB）
- [ ] **P2** third_party/busybox 子模块退役（退模 + 教程指向 buildroot 卷）
- [ ] **P2** ci-build.yml 死路径清理（patches/uboot/** 空目录触发规则）；release-all.sh 头部注释改
- [ ] **P3** imxdownload 纳入版权/溯源清单；host/qt6-host 加去留说明；shellcheck 分批清或显式豁免

---

## 六、教程大改版（2026-10-10 立项，剩余施工）

### 一期尾巴

- [ ] **P1** v7.1 文字引用批量刷：core-functional 11 文件「基于 Linux 7.1」声明 + 全教程约 45 处残留（历史叙事合法保留）
- [ ] **P1** 行号重核工具 scripts/check_lineno.py（规格见 op_plan/07 §四；升版流水线的自动化核心）

### 三期 · 管线批量重写（每批 ≤3 章，前置 = 风格四裁定）

- [ ] **P2** modules 8 章对 7.2.9 树重写（现挂失效行号横幅且文案停在 v7.1），3 批
- [ ] **P2** kernel 拍平章复核（18 章重写质量 + 7.1 声明残留）
- [ ] **P2** emu 8 章扩写（结合 e2e 断言与排查实录，脱离最薄卷），3 批

### 四期 · 缺口篇 5 章

- [ ] **P2** UART / USB / 块设备 / MISC / Regmap 五章，每章验收栏写 QEMU 注入式断言

---

## 七、冻结与放弃（明确不做，防重复讨论）

- **PROJ-003~010 点子池冻结**：不入承诺范围（projects/ 目录仅存 PROJ-001/002 愿景稿，待重写为 C3 之上的扩展阶段）
- **Debian rootfs 冻结**：rootfs 主线为 Buildroot
- **C2 voice-recorder 排最后**：wm8960 无音频模型（永久桩），真板 capture 未测
- **看门狗/WIFI 驱动章冻结**：无板无模型无真实需求实证
- **Regmap/USB 通用 API 百科式清单不写**：只做分析型章节（见三、驱动章改造）
- **CHANGELOG 增量门禁暂缓**：release.yml 现状只查文件存在性（release.yml:164），暂不加增量校验——之后会进行比较大的文档章节梳理重构，CHANGELOG 结构可能随之调整，门禁等重构后一并定（2026-11-28 用户裁定）
- **通用 Linux 命令/内核 API/Qt 通识不新增**：按路由声明归属 EmbedBox/PenguinLab/Tutorial_AwesomeQt

---

## 八、已完成归档（证据可查）

### 里程碑

- v0.5（2026-03）：Mainline 内核迁移 + QT6 支持
- v1.0.0（2026-06）：SD/eMMC 完整构建→烧录→启动闭环

### 2026-08-31 计划立项以来完成（抽样，详见 git log）

- [x] QEMU smoke 接进 CI（#106，2026-09-01；#135 修绿，2026-11-04）
- [x] release-images 空 artifact 假绿修复（声明删除，2026-09）
- [x] debug 卷三篇 + workflow 卷六篇重写（#108，2026-09-03；#101 同日关闭）
- [x] light-meter commit 引用断链修复（教程明写分支位置）
- [x] core-functional 双核幻觉改单核（2026-09）
- [x] 内核基线切 v7.2.9 + 补丁退役改拷贝机制（#126，2026-10-13）
- [x] 设备树独立仓（#125，2026-10-11）
- [x] kernel 卷拍平 18 章（2026-10-13）
- [x] U-Boot 迁移上游主线 v2026.10（#129，2026-10-20）+ uboot 卷重写 14 章（#139，2026-11-15）
- [x] 教程七分区导航落地（#131，2026-10-30）：hub/homeRoadmap/侧栏单源到 project.config.ts
- [x] gt911 0x5d/0x14 定案（dts 押 0x5d，真板 0x14 记录在案，修复等 QEMU 11.2）
- [x] org description 改实际定位（2026-09）
- [x] 文档-脚本漂移清理：e2e 口径统一、run-qemu usage、overlay 退役横幅、debug/04 vexpress 纠正
- [x] 教程层级化简（2026-11-28）：7 个分区壳并入 tutorial/index.md 总览页；docker 两章并入 start；practical 拆并入 build/debug/rootfs（01 概述删除）；core-functional 与 driver 卷的版本声明刷到 7.2.9
- [x] 全站过时文档审查与统一更新（2026-11-28）：两路子代理扫 360 篇（uboot 除外），修 74 条高置信过时——版本号刷 7.2.9、退役补丁机制改 U-Boot 示例、CI 文档对齐实际 workflow、23 条死链、8 处脚本文档漂移、goodix dtsi 事实错误；历史实录加版本说明。登记与修复记录在 /tmp/audit-a.md、/tmp/audit-b.md、/tmp/fix-log.md。同日清理脚本源码陈旧注释：release-all.sh 旧名 build-all、build-buildroot.sh 双轨表述、env-init.sh 的 Stage 3 依赖表（BusyBox 两包 → Buildroot 完整清单）、build-uboot.sh 头部板名

## 相关链接

- **愿景与定位**：[roadmap.md](roadmap.md)
- **GitHub Issues**：https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues （薄指针，状态以本文件为准）
- **快速开始**：[../QUICK_START.md](../QUICK_START.md)
