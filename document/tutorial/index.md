<PageHeader icon="📚" title="教程系列" description="系统学习嵌入式 Linux 开发的完整路径" />

## 学习路线图

<RoadMap>
  <RoadMapPhase icon="🌱" title="环境搭建" subtitle="Foundation" time="~2 天" :difficulty="1" :num="1">
    <ChapterLink num="01" href="docker/" variant="sub">Docker 环境搭建</ChapterLink>
    <ChapterLink num="02" href="start/01_start_from_toolchain" variant="sub">工具链安装</ChapterLink>
    <ChapterLink num="03" href="start/02_env_init_guide" variant="sub">环境初始化</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🚀" title="引导加载" subtitle="Bootloader" time="~3 天" :difficulty="2" :num="2">
    <ChapterLink num="01" href="uboot/01_what_is_uboot" variant="sub">什么是 U-Boot</ChapterLink>
    <ChapterLink num="02" href="uboot/02_uboot_compile" variant="sub">编译与配置</ChapterLink>
    <ChapterLink num="03" href="uboot/03_uboot_porting_overview" variant="sub">移植概述</ChapterLink>
    <ChapterLink num="04" href="uboot/06_lcd_porting" variant="sub">LCD 移植</ChapterLink>
    <ChapterLink num="05" href="uboot/07_network_porting" variant="sub">网络移植</ChapterLink>
    <ChapterLink num="06" href="uboot/08_logo_splash" variant="sub">Logo 定制</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🔍" title="内核探索" subtitle="Kernel" time="~5 天" :difficulty="3" :num="3">
    <ChapterLink num="01" href="kernel/01_kernel_overview" variant="sub">内核概述</ChapterLink>
    <ChapterLink num="02" href="kernel/02_kernel_compile" variant="sub">内核编译</ChapterLink>
    <ChapterLink num="03" href="kernel/03_kernel_config" variant="sub">内核配置</ChapterLink>
    <ChapterLink num="04" href="kernel/04_kernel_modules" variant="sub">内核模块</ChapterLink>
    <ChapterLink num="05" href="kernel/05_kernel_device_tree" variant="sub">设备树详解</ChapterLink>
    <ChapterLink num="06" href="kernel/08_kernel_boot_debug" variant="sub">启动调试</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="📦" title="根文件系统" subtitle="RootFS" time="~3 天" :difficulty="2" :num="4">
    <ChapterLink num="01" href="rootfs/01_rootfs_overview" variant="sub">Rootfs 概述</ChapterLink>
    <ChapterLink num="02" href="rootfs/02_busybox_compile" variant="sub">BusyBox 编译</ChapterLink>
    <ChapterLink num="03" href="rootfs/03_inittab_init" variant="sub">inittab 与 init</ChapterLink>
    <ChapterLink num="04" href="rootfs/05_nfs_wsl_troubleshoot" variant="sub">NFS 挂载</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🔗" title="系统启动" subtitle="System Boot" time="~2 天" :difficulty="2" :num="5">
    <ChapterLink num="01" href="practical/01_practical_overview" variant="sub">实战概述</ChapterLink>
    <ChapterLink num="02" href="practical/02_build_system" variant="sub">构建系统</ChapterLink>
    <ChapterLink num="03" href="practical/03_boot_and_debug" variant="sub">启动与调试</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="⚙️" title="驱动开发" subtitle="Driver Dev" time="~15 天" :difficulty="4" :num="6">
    <ChapterLink num="01" href="driver/char_device/" variant="sub">字符设备基础</ChapterLink>
    <ChapterLink num="02" href="driver/device_tree/" variant="sub">设备树实践</ChapterLink>
    <ChapterLink num="03" href="driver/pinctrl_gpio/" variant="sub">Pin Control & GPIO</ChapterLink>
    <ChapterLink num="04" href="driver/modules/" variant="sub">模块开发</ChapterLink>
    <ChapterLink num="05" href="driver/firmware_apply/" variant="sub">固件应用</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🏔️" title="进阶探索" subtitle="Advanced" time="持续" :difficulty="5" :num="7">
    <ChapterLink num="01" href="kernel/mainline/" variant="sub">主线内核移植</ChapterLink>
    <ChapterLink num="02" href="kernel/core_features/" variant="sub">内核并发机制</ChapterLink>
    <ChapterLink num="03" href="uboot/bonus_qa" variant="sub">U-Boot Q&A</ChapterLink>
  </RoadMapPhase>
</RoadMap>

## 教程目录

### 入门准备

<ChapterNav>
  <ChapterLink num="01" href="start/01_start_from_toolchain">工具链安装</ChapterLink>
  <ChapterLink num="02" href="start/02_env_init_guide">环境初始化指南</ChapterLink>
</ChapterNav>

### U-Boot 教程

<ChapterNav>
  <ChapterLink num="01" href="uboot/01_what_is_uboot">什么是 U-Boot</ChapterLink>
  <ChapterLink num="02" href="uboot/02_uboot_compile">编译与配置</ChapterLink>
  <ChapterLink num="03" href="uboot/03_uboot_porting_overview">移植概述</ChapterLink>
  <ChapterLink num="04" href="uboot/04_board_config_basic">板级配置</ChapterLink>
  <ChapterLink num="05" href="uboot/05_device_tree_basics">设备树基础</ChapterLink>
  <ChapterLink num="06" href="uboot/06_lcd_porting">LCD 移植</ChapterLink>
  <ChapterLink num="07" href="uboot/07_network_porting">网络移植</ChapterLink>
  <ChapterLink num="08" href="uboot/08_logo_splash">Logo 定制</ChapterLink>
  <ChapterLink num="09" href="uboot/09_debugging_commands">调试命令</ChapterLink>
  <ChapterLink num="★" href="uboot/bonus_qa">Q&A 常见问题</ChapterLink>
</ChapterNav>

### 内核教程

<ChapterNav>
  <ChapterLink num="01" href="kernel/01_kernel_overview">内核概述</ChapterLink>
  <ChapterLink num="02" href="kernel/02_kernel_compile">内核编译</ChapterLink>
  <ChapterLink num="03" href="kernel/03_kernel_config">内核配置</ChapterLink>
  <ChapterLink num="04" href="kernel/04_kernel_modules">内核模块</ChapterLink>
  <ChapterLink num="05" href="kernel/05_kernel_device_tree">设备树详解</ChapterLink>
  <ChapterLink num="06" href="kernel/06_wsl_network_boot">网络启动</ChapterLink>
  <ChapterLink num="07" href="kernel/07_driver_basic">驱动基础</ChapterLink>
  <ChapterLink num="08" href="kernel/08_kernel_boot_debug">启动调试</ChapterLink>
</ChapterNav>

### 根文件系统

<ChapterNav>
  <ChapterLink num="01" href="rootfs/01_rootfs_overview">Rootfs 概述</ChapterLink>
  <ChapterLink num="02" href="rootfs/02_busybox_compile">BusyBox 编译</ChapterLink>
  <ChapterLink num="03" href="rootfs/03_inittab_init">inittab 与 init</ChapterLink>
  <ChapterLink num="04" href="rootfs/04_rootfs_structure">目录结构</ChapterLink>
  <ChapterLink num="05" href="rootfs/05_nfs_wsl_troubleshoot">NFS 挂载</ChapterLink>
  <ChapterLink num="06" href="rootfs/06_apps_integration">应用集成</ChapterLink>
</ChapterNav>

### 驱动开发

<ChapterNav>
  <ChapterLink num="01" href="driver/modules/">模块开发</ChapterLink>
  <ChapterLink num="02" href="driver/firmware_apply/">固件应用</ChapterLink>
</ChapterNav>

### 实战演练

<ChapterNav>
  <ChapterLink num="01" href="practical/01_practical_overview">实战概述</ChapterLink>
  <ChapterLink num="02" href="practical/02_build_system">构建系统</ChapterLink>
  <ChapterLink num="03" href="practical/03_boot_and_debug">启动与调试</ChapterLink>
  <ChapterLink num="04" href="practical/04-nfs-experience">NFS 体验</ChapterLink>
</ChapterNav>

::: tip 遇到问题？
提交 [GitHub Issue](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues) 或查阅项目 [快速开始](../QUICK_START)。
:::
