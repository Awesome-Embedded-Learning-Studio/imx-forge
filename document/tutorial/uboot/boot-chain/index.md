---
title: boot-chain · 启动深读
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

<PageHeader icon="🧭" title="boot-chain · 启动深读" description="U-Boot 自己是怎样启动的：从 BootROM 挑介质到交棒内核那一刻，四段十六篇逐字节拆完" />

主线 [U-Boot 教程](../) 教你把启动链走通，这一卷回答走通之后悬在心里的问题：镜像为什么写到 1KB 偏移就活了、DDR 是谁带活的、U-Boot 进 C 之前活得有多小心、它怎么把自己搬进 DDR 高处、交棒那一刻到底发生了什么。建议读完主线第 04 站（产物验证与烧录）后再来，手里的镜像正好当标本。

## 阶段一 · Boot ROM 与镜像格式

<ChapterNav>
  <ChapterLink num="01" href="01_boot_rom_boot_media">上电之后：挑介质、认镜像</ChapterLink>
  <ChapterLink num="02" href="02_ivt_fields">IVT 逐字段：BootROM 的说明书</ChapterLink>
  <ChapterLink num="03" href="03_dcd_walkthrough">DCD 逐条读：寄存器写入清单</ChapterLink>
  <ChapterLink num="04" href="04_flash_offset_layout">1KB 偏移：镜像布局与烧录位置</ChapterLink>
</ChapterNav>

## 阶段二 · 早期初始化

<ChapterNav>
  <ChapterLink num="05" href="05_entry_and_vectors">从 _start 开始：第一条指令</ChapterLink>
  <ChapterLink num="06" href="06_gd_and_stack">栈和 gd：U-Boot 的小本本</ChapterLink>
  <ChapterLink num="07" href="07_relocation_limits">重定位前：处处受限的日子</ChapterLink>
  <ChapterLink num="08" href="08_spl_sidebar">SPL 旁栏：别的平台为什么多一层</ChapterLink>
</ChapterNav>

## 阶段三 · 搬家：重定位与后期初始化

<ChapterNav>
  <ChapterLink num="09" href="09_console_ready">console 什么时候就绪</ChapterLink>
  <ChapterLink num="10" href="10_relocate_code">搬家：重定位算法与地址计算</ChapterLink>
  <ChapterLink num="11" href="11_board_init_r_dm">board_init_r 与驱动模型扫描</ChapterLink>
  <ChapterLink num="12" href="12_env_and_autoboot">env 加载与倒计时</ChapterLink>
</ChapterNav>

## 阶段四 · 交棒内核

<ChapterNav>
  <ChapterLink num="13" href="13_bootz_parsing">bootz 解析 zImage</ChapterLink>
  <ChapterLink num="14" href="14_fdt_handoff">FDT 传递与启动参数修补</ChapterLink>
  <ChapterLink num="15" href="15_cleanup_before_linux">cleanup_before_linux：清场</ChapterLink>
  <ChapterLink num="16" href="16_handoff_moment">控制权交接那一刻</ChapterLink>
</ChapterNav>

::: tip 读法建议
每篇开头都接着主线某个具体时刻（烧完镜像、看见横幅、敲进命令行），手里有按主线做出来的镜像与串口记录，对照着读收获最大；全部取证命令都能对着自己编的产物复跑。
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← U-Boot 主线</ChapterLink>
  <ChapterLink href="../kernel/" variant="sub">内核教程 →</ChapterLink>
</ChapterNav>
