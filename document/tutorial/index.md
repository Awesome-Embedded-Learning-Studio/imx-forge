---
title: 教程
---

<PageHeader icon="📚" title="教程系列" description="系统学习嵌入式 Linux 开发的完整路径" />

## 学习路线图

<RoadMap>
  <RoadMapPhase icon="🐧" title="Linux 基础预备营" subtitle="Pre-Camp · 可选" time="按需" :difficulty="1" :num="0">
    <ChapterLink num="01" href="linux-basics/" variant="sub">零基础？先补 Linux 基本功（35 章）</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🌱" title="环境搭建" subtitle="Foundation" time="~2 天" :difficulty="1" :num="1">
    <ChapterLink num="01" href="docker/" variant="sub">Docker 环境搭建</ChapterLink>
    <ChapterLink num="02" href="start/01_start_from_toolchain" variant="sub">工具链安装</ChapterLink>
    <ChapterLink num="03" href="start/02_env_init_guide" variant="sub">环境初始化</ChapterLink>
    <ChapterLink num="04" href="workflow/" variant="sub">开发工作流（WSL2/clangd/tasks）</ChapterLink>
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
    <ChapterLink num="05" href="buildroot/" variant="sub">Buildroot 现代构建（12 章）</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🔗" title="系统启动" subtitle="System Boot" time="~2 天" :difficulty="2" :num="5">
    <ChapterLink num="01" href="practical/01_practical_overview" variant="sub">实战概述</ChapterLink>
    <ChapterLink num="02" href="practical/02_build_system" variant="sub">构建系统</ChapterLink>
    <ChapterLink num="03" href="practical/03_boot_and_debug" variant="sub">启动与调试</ChapterLink>
    <ChapterLink num="04" href="flash/" variant="sub">镜像构建</ChapterLink>
    <ChapterLink num="05" href="emu/" variant="sub">没有板子？QEMU 板级模拟直启</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="⚙️" title="驱动开发" subtitle="Driver Dev" time="~15 天" :difficulty="4" :num="6">
    <ChapterLink num="01" href="driver/00_chardev_base/" variant="sub">字符设备基础</ChapterLink>
    <ChapterLink num="02" href="driver/01_device_tree_base/" variant="sub">设备树基础</ChapterLink>
    <ChapterLink num="03" href="driver/02_pinctrl_gpio/01_introduction" variant="sub">Pin Control & GPIO</ChapterLink>
    <ChapterLink num="04" href="driver/modules/" variant="sub">模块开发</ChapterLink>
    <ChapterLink num="05" href="driver/firmware_apply/" variant="sub">固件应用</ChapterLink>
  </RoadMapPhase>

  <RoadMapPhase icon="🏔️" title="进阶探索" subtitle="Advanced" time="持续" :difficulty="5" :num="7">
    <ChapterLink num="01" href="kernel/mainline/" variant="sub">主线内核移植</ChapterLink>
    <ChapterLink num="02" href="kernel/core-functional/" variant="sub">内核并发机制</ChapterLink>
    <ChapterLink num="03" href="uboot/bonus_qa" variant="sub">U-Boot Q&A</ChapterLink>
    <ChapterLink num="04" href="project/light-meter/" variant="sub">工程实战：light-meter 照度摆件</ChapterLink>
  </RoadMapPhase>
</RoadMap>

## 教程目录

### Linux 基础（零基础预备营）

<ChapterNav>
  <ChapterLink num="★" href="linux-basics/">Ubuntu Linux 实用教程（35 章）</ChapterLink>
</ChapterNav>

### 入门准备

<ChapterNav>
  <ChapterLink num="01" href="start/01_start_from_toolchain">工具链安装</ChapterLink>
  <ChapterLink num="02" href="start/02_env_init_guide">环境初始化指南</ChapterLink>
</ChapterNav>

### 开发工作流

<ChapterNav>
  <ChapterLink num="01" href="workflow/01_wsl2_notes">WSL2 开发注意事项</ChapterLink>
  <ChapterLink num="02" href="workflow/02_clangd_cross_compile">clangd 交叉编译配置</ChapterLink>
  <ChapterLink num="03" href="workflow/03_tasks_json_templates">VSCode tasks.json 模板</ChapterLink>
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
  <ChapterLink num="07" href="rootfs/07_module_autoload">模块自动加载</ChapterLink>
</ChapterNav>

### Buildroot 构建（现行 rootfs 方案）

<ChapterNav>
  <ChapterLink num="★" href="buildroot/">Buildroot 专栏总览（12 章）</ChapterLink>
  <ChapterLink num="01" href="buildroot/01_how_buildroot_works">Buildroot 工作原理</ChapterLink>
  <ChapterLink num="02" href="buildroot/02_first_build">第一次构建</ChapterLink>
  <ChapterLink num="03" href="buildroot/03_external_toolchain">外部工具链</ChapterLink>
  <ChapterLink num="04" href="buildroot/04_kconfig_fragments">Kconfig fragment</ChapterLink>
  <ChapterLink num="05" href="buildroot/05_br2_external_tree">br2-external 树</ChapterLink>
  <ChapterLink num="06" href="buildroot/06_rootfs_customization">rootfs 定制</ChapterLink>
  <ChapterLink num="07" href="buildroot/07_custom_package">自定义软件包</ChapterLink>
  <ChapterLink num="08" href="buildroot/08_init_system">init 系统</ChapterLink>
  <ChapterLink num="09" href="buildroot/09_ccache_rebuild">ccache 与重建</ChapterLink>
  <ChapterLink num="10" href="buildroot/10_debugging">调试</ChapterLink>
  <ChapterLink num="11" href="buildroot/11_qt6_integration">Qt6 集成</ChapterLink>
  <ChapterLink num="12" href="buildroot/12_migration_guide">从手搓 rootfs 迁移</ChapterLink>
</ChapterNav>

### 驱动开发

<ChapterNav>
  <ChapterLink num="01" href="driver/00_chardev_base/">字符设备基础</ChapterLink>
  <ChapterLink num="02" href="driver/01_device_tree_base/">设备树驱动基础</ChapterLink>
  <ChapterLink num="03" href="driver/02_pinctrl_gpio/01_introduction">Pin Control & GPIO</ChapterLink>
  <ChapterLink num="04" href="driver/03_platform_led_driver/">Platform LED 驱动</ChapterLink>
  <ChapterLink num="05" href="driver/04_beep_driver/">蜂鸣器驱动</ChapterLink>
  <ChapterLink num="06" href="driver/05_gpio_key_driver/">GPIO 按键驱动</ChapterLink>
  <ChapterLink num="07" href="driver/06_debounced_key_driver/">按键消抖驱动</ChapterLink>
  <ChapterLink num="08" href="driver/07_input_subsystem_key/">Input 子系统按键</ChapterLink>
  <ChapterLink num="09" href="driver/08_i2c_ap3216c_driver/">AP3216C I2C 驱动</ChapterLink>
  <ChapterLink num="10" href="driver/09_spi_icm20608_driver/">ICM-20608 SPI 驱动</ChapterLink>
  <ChapterLink num="11" href="driver/10_rtc_snvs_driver/">RTC 驱动（SNVS 分析型）</ChapterLink>
  <ChapterLink num="12" href="driver/11_goodix_touchscreen_driver/">电容触摸驱动（goodix 分析型）</ChapterLink>
  <ChapterLink num="13" href="driver/12_wm8960_audio_driver/">WM8960 音频驱动（ASoC 分析型）</ChapterLink>
  <ChapterLink num="14" href="driver/modules/">模块开发</ChapterLink>
  <ChapterLink num="15" href="driver/firmware_apply/">固件应用</ChapterLink>
</ChapterNav>

### QEMU 板级模拟（无板可学）

<ChapterNav>
  <ChapterLink num="★" href="emu/">模拟器卷总览（8 章）</ChapterLink>
  <ChapterLink num="01" href="emu/01_why_emulation">为什么做板级模拟</ChapterLink>
  <ChapterLink num="02" href="emu/02_machine_model">机器模型</ChapterLink>
  <ChapterLink num="03" href="emu/03_rootfs_image">rootfs 镜像</ChapterLink>
  <ChapterLink num="04" href="emu/04_whack_a_mole">打地鼠：日志链验证</ChapterLink>
  <ChapterLink num="05" href="emu/05_toolchain">工具链</ChapterLink>
  <ChapterLink num="06" href="emu/06_peripheral_models">外设模型</ChapterLink>
  <ChapterLink num="07" href="emu/07_gt911_debug">gt911 排查实录</ChapterLink>
  <ChapterLink num="08" href="emu/08_equivalence">真机等价性原则</ChapterLink>
</ChapterNav>

### 实战演练

<ChapterNav>
  <ChapterLink num="01" href="practical/01_practical_overview">实战概述</ChapterLink>
  <ChapterLink num="02" href="practical/02_build_system">构建系统</ChapterLink>
  <ChapterLink num="03" href="practical/03_boot_and_debug">启动与调试</ChapterLink>
  <ChapterLink num="04" href="practical/04-nfs-experience">NFS 体验</ChapterLink>
</ChapterNav>

### 工程实战项目（工程终点）

<ChapterNav>
  <ChapterLink num="★" href="project/">项目卷总览</ChapterLink>
  <ChapterLink num="01" href="project/light-meter/">light-meter 照度护眼摆件（11 章）</ChapterLink>
</ChapterNav>

### 镜像构建与烧录准备

<ChapterNav>
  <ChapterLink num="01" href="flash/01_storage_media_basics">存储介质基础</ChapterLink>
  <ChapterLink num="02" href="flash/02_image_partition_filesystem_basics">镜像、分区和文件系统</ChapterLink>
  <ChapterLink num="03" href="flash/03_common_image_and_archive_formats">常见打包与镜像格式</ChapterLink>
  <ChapterLink num="04" href="flash/04_imx6ull_boot_flow_and_offsets">i.MX6ULL 启动链路与偏移</ChapterLink>
  <ChapterLink num="05" href="flash/05_why_full_image">为什么需要完整镜像</ChapterLink>
  <ChapterLink num="06" href="flash/06_image_layout_design">镜像布局设计</ChapterLink>
  <ChapterLink num="07" href="flash/07_build_imx6ull_image_script">脚本设计拆解</ChapterLink>
  <ChapterLink num="08" href="flash/08_image_size_and_usage">镜像大小与使用</ChapterLink>
  <ChapterLink num="09" href="flash/09_sd_card_flashing">SD 卡烧录实战</ChapterLink>
  <ChapterLink num="10" href="flash/10_uuu_ums_emmc_flashing">UUU + UMS eMMC 烧录</ChapterLink>
</ChapterNav>

### 命令速查

<ChapterNav>
  <ChapterLink num="01" href="commands/01_image_builder_commands">镜像构建命令</ChapterLink>
  <ChapterLink num="02" href="commands/02_image_inspection_commands">镜像检查命令</ChapterLink>
  <ChapterLink num="03" href="commands/03_storage_tool_commands">存储工具命令</ChapterLink>
  <ChapterLink num="04" href="commands/04_flashing_commands">烧录命令</ChapterLink>
</ChapterNav>

### 构建进阶

<ChapterNav>
  <ChapterLink num="01" href="build/01_out_directory_structure">out/ 目录结构</ChapterLink>
  <ChapterLink num="02" href="build/02_patch_workflow_practice">Patch 工作流</ChapterLink>
  <ChapterLink num="03" href="build/03_rootfs_overlay_guide">RootFS Overlay</ChapterLink>
</ChapterNav>

::: tip 遇到问题？
提交 [GitHub Issue](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues) 或查阅项目 [快速开始](../QUICK_START)。
:::
