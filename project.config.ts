import { defineProject } from './site/.vitepress/config/schema'

export default defineProject({
  name: 'imx-forge',
  title: { 'zh-CN': 'IMX-Forge的教程文档' },
  description: { 'zh-CN': 'IMX-Forge，专注于IMX6ULL的教程文档网站' },
  base: '/imx-forge/',
  copyright: 'Copyright © 2026 Charliechen - 保留所有权利',

  documentsDir: 'document',
  siteDir: 'site',

  locales: [
    { code: 'zh-CN', label: '中文', default: true },
  ],

  // 顶层导航 = 7 个学习分区 + 速查 + 更多，与侧栏分区（见 sidebar.sections）一一对应。
  // 读者向（教程）与维护者向（架构/CI/脚本/发布）分开，后者统一收进「更多」。
  // 顶层导航 = 7 个学习分区 + 更多。每个分区项「文字」是链接(点击直达分区总览),
  // 「右侧箭头」展开二级菜单(列出该分区包含的章节)。这是主题覆盖后的复合行为
  // (见 site/.vitepress/theme/components/NavSplitItem.vue):VitePress 内置版
  // 只要项里有 link 就会丢掉 items,所以必须覆盖。
  nav: {
    'zh-CN': [
      { text: '首页', link: '/' },
      {
        text: '快速上手',
        link: '/tutorial/getting-started/',
        activeMatch: '^/tutorial/(getting-started)/',
        items: [
          { text: '学习路线图', link: '/tutorial/start/00_roadmap' },
          { text: 'Docker 一键环境', link: '/tutorial/docker/' },
          { text: '没有板子？QEMU 直启', link: '/tutorial/emu/01_why_emulation' },
          { text: '硬件清单与接线', link: '/tutorial/start/03_hardware_quick_reference' },
          { text: '首次上电验收', link: '/tutorial/start/05_first_boot_check' },
          { text: '全部教程总览', link: '/tutorial/' },
        ],
      },
      {
        text: '环境与基础',
        link: '/tutorial/foundations/',
        activeMatch: '^/tutorial/(foundations|linux-basics|docker|workflow)/',
        items: [
          { text: 'Linux 基础预备营', link: '/tutorial/linux-basics/' },
          { text: 'Docker 教程', link: '/tutorial/docker/' },
          { text: '开发环境配置', link: '/tutorial/workflow/' },
        ],
      },
      {
        text: '系统构建',
        link: '/tutorial/system-build/',
        activeMatch: '^/tutorial/(system-build|start|uboot|kernel|rootfs|buildroot|practical)/',
        items: [
          { text: '入门准备', link: '/tutorial/start/' },
          { text: 'U-Boot 移植', link: '/tutorial/uboot/' },
          { text: '内核移植', link: '/tutorial/kernel/' },
          { text: '根文件系统', link: '/tutorial/rootfs/' },
          { text: 'Buildroot 构建', link: '/tutorial/buildroot/' },
          { text: '实战演练', link: '/tutorial/practical/' },
        ],
      },
      {
        text: '驱动与实战',
        link: '/tutorial/driver-dev/',
        activeMatch: '^/tutorial/(driver-dev|driver|project)/',
        items: [
          { text: '驱动开发', link: '/tutorial/driver/' },
          { text: '应用项目 light-meter', link: '/tutorial/project/' },
        ],
      },
      {
        text: '模拟与调试',
        link: '/tutorial/emulation/',
        activeMatch: '^/tutorial/(emulation|emu|debug)/',
        items: [
          { text: 'QEMU 板级模拟', link: '/tutorial/emu/' },
          { text: '调试与排错', link: '/tutorial/debug/' },
        ],
      },
      {
        text: '烧录与进阶',
        link: '/tutorial/flashing/',
        activeMatch: '^/tutorial/(flashing|flash|build)/',
        items: [
          { text: '镜像与烧录', link: '/tutorial/flash/' },
          { text: '构建进阶', link: '/tutorial/build/' },
        ],
      },
      {
        text: '速查',
        link: '/tutorial/cheatsheet/',
        activeMatch: '^/tutorial/(cheatsheet|commands|third_party)/',
        items: [
          { text: '命令速查', link: '/tutorial/commands/' },
          { text: '第三方支持', link: '/tutorial/third_party/' },
        ],
      },
      {
        text: '更多',
        items: [
          { text: '项目架构', link: '/architecture/' },
          { text: 'CI/CD', link: '/ci/' },
          { text: '脚本手册', link: '/scripts/' },
          { text: '发布流程', link: '/release/' },
          { text: '参考手册', link: '/reference/' },
          { text: '技术笔记', link: '/notes/' },
          { text: '来稿', link: '/tutorial/contrib/' },
          { text: '贡献者', link: '/team/' },
        ],
      },
      { text: 'GitHub', link: 'https://github.com/Awesome-Embedded-Learning-Studio/imx-forge' },
    ],
  },

  sidebar: {
    // tutorial 卷已移除:整个教程区改由 sections 按学习分区注册（见下）。
    // 其余顶端目录仍是「一目录一卷」的自动扫描。
    volumes: [
      { name: 'architecture', srcDir: 'architecture', urlPrefix: '/architecture' },
      { name: 'ci', srcDir: 'ci', urlPrefix: '/ci' },
      { name: 'scripts', srcDir: 'scripts', urlPrefix: '/scripts' },
      { name: 'development', srcDir: 'development', urlPrefix: '/development' },
      { name: 'modules', srcDir: 'modules', urlPrefix: '/modules' },
      { name: 'release', srcDir: 'release', urlPrefix: '/release' },
      { name: 'team', srcDir: 'team', urlPrefix: '/team' },
      { name: 'notes', srcDir: 'notes', urlPrefix: '/notes' },
      { name: 'qa', srcDir: 'qa', urlPrefix: '/qa' },
      { name: 'todo', srcDir: 'todo', urlPrefix: '/todo' },
      { name: 'reference', srcDir: 'reference', urlPrefix: '/reference' },
    ],

    // /tutorial/ 总览页的侧栏:只列 7 个分区与来稿,不再展开 18 个目录 288 篇。
    extra: {
      '/tutorial/': [
        { text: '教程总览', link: '/tutorial/' },
        { text: '快速上手', link: '/tutorial/getting-started/' },
        { text: '环境与基础', link: '/tutorial/foundations/' },
        { text: '系统构建', link: '/tutorial/system-build/' },
        { text: '驱动与实战', link: '/tutorial/driver-dev/' },
        { text: '模拟与调试', link: '/tutorial/emulation/' },
        { text: '烧录与进阶', link: '/tutorial/flashing/' },
        { text: '速查与参考', link: '/tutorial/cheatsheet/' },
        { text: '来稿', link: '/tutorial/contrib/' },
      ],
    },

    // 学习分区:每个分区横跨若干物理目录,同一份侧栏数组挂到各目录前缀上。
    // VitePress 按路径段数降序匹配前缀，故 4 段的 /tutorial/<dir>/ 恒优先于 3 段的 /tutorial/。
    sections: [
      {
        slug: 'getting-started',
        title: '快速上手',
        // 不拥有物理目录:总览页是跨目录精选,侧栏入口手工列出。
        dirs: [],
        links: [
          { text: '学习路线图', link: '/tutorial/start/00_roadmap' },
          { text: 'Docker 一键环境', link: '/tutorial/docker/' },
          { text: '没有板子？QEMU 直启', link: '/tutorial/emu/01_why_emulation' },
          { text: '硬件清单与接线', link: '/tutorial/start/03_hardware_quick_reference' },
          { text: '首次上电验收', link: '/tutorial/start/05_first_boot_check' },
          { text: '全部教程总览', link: '/tutorial/' },
        ],
      },
      { slug: 'foundations', title: '环境与基础', dirs: ['linux-basics', 'docker', 'workflow'] },
      {
        slug: 'system-build',
        title: '系统构建',
        dirs: ['start', 'uboot', 'kernel', 'rootfs', 'buildroot', 'practical'],
      },
      { slug: 'driver-dev', title: '驱动与实战', dirs: ['driver', 'project'] },
      { slug: 'emulation', title: '模拟与调试', dirs: ['emu', 'debug'] },
      { slug: 'flashing', title: '烧录与进阶', dirs: ['flash', 'build'] },
      { slug: 'cheatsheet', title: '速查与参考', dirs: ['commands', 'third_party'] },
    ],
  },

  github: {
    owner: 'Awesome-Embedded-Learning-Studio',
    repo: 'imx-forge',
    branch: 'main',
    documentsPath: 'document',
  },

  build: {
    concurrency: 4,
    rootPages: ['index.md'],
    rootAssets: [],
  },

  plugins: {
    cppTemplateEscape: true,
    kbd: true,
    math: true,
    // 阅读体验三件套(字号切换 / 侧栏拖拽 / 阅读进度条)+ 长代码折叠:默认开启。
    // readingUX / codeFold 不写也默认 true(defineProject 兜底),这里显式写明意图。
    readingUX: true,
    codeFold: true,
    // Mermaid 图表:开启 —— ```mermaid 块渲染为 SVG(客户端 npm mermaid 按需加载,打进
    // 独立懒加载 chunk,离线可用;当前页真有图才下载)。需关闭时改 false。
    mermaid: true,
  },

  // 阅读体验默认值(可选;首次访问、未拖拽过时使用)。
  readingDefaults: {
    fontTier: 'normal',
    sidebarWidth: 272,
    asideWidth: 256,
    codeFoldLines: 20,
  },

  // 首页截图轮播:复用现有 public/ 图片,立即可用。
  // 想换真实 UI 截图:把 png 丢进 site/.vitepress/public/,改下面的 src 即可。
  homeScreenshots: [
    {
      src: '/lcd-on.jpg',
      href: '/tutorial/uboot/',
      title: 'U-Boot 点亮 LCD',
      desc: '上电即见 —— Bootloader 阶段就把 7 寸屏幕点亮',
    },
    {
      src: '/tutorial/project/light-meter/mock-light.png',
      href: '/tutorial/project/light-meter/',
      title: 'light-meter 照度摆件',
      desc: '从桌面 Mock 到板子真机 —— 一个嵌入式 Qt 工程的完整造法',
    },
    {
      src: '/linux7.png',
      href: '/tutorial/kernel/',
      title: '主线 Linux 7 运行',
      desc: '上游主线内核在 i.MX6ULL 上稳定运行',
    },
    {
      src: '/build_linux.png',
      href: '/tutorial/kernel/',
      title: '内核编译实时进度',
      desc: 'buildmeter 解析 kbuild —— 数千个编译单元逐个点亮,长构建不再黑盒',
    },
    {
      src: '/build_buildroot.png',
      href: '/tutorial/rootfs/',
      title: 'rootfs 编译进度',
      desc: 'buildroot 全包序 + ninja 子进度 + All Packages 计数,漫长构建一目了然',
    },
    {
      src: '/Awesome-Embedded.png',
      href: '/',
      title: 'IMX-Forge 文档站',
      desc: '从工具链到 QT 应用的完整学习路径',
    },
  ],

  // 首页学习路线图:阶段卡 + 状态徽标 + 章数。
  homeRoadmap: {
    title: '学习路线图',
    next:
      '推荐顺序:快速上手 → 环境与基础 → 系统构建 → 驱动与实战。模拟与调试、烧录与进阶可按需穿插;没有板子的朋友从「快速上手」里的 QEMU 直启进入即可。速查与参考随时翻。',
    stages: [
      {
        no: '阶段 1',
        name: '快速上手',
        dir: 'getting-started',
        desc: '三条最短路径:有板走硬件速查与首启验收,无板走 Docker + QEMU 直启,已配环境直接进系统构建。',
        status: 'done',
        link: '/tutorial/getting-started/',
      },
      {
        no: '阶段 2',
        name: '环境与基础',
        dir: 'foundations',
        desc: 'Ubuntu 命令行、Shell、文件系统、进程、网络打底;Docker 一键部署 ARM GNU Toolchain 15.2;WSL2/远程/串口/传文件把开发台配齐。',
        status: 'done',
        link: '/tutorial/foundations/',
      },
      {
        no: '阶段 3',
        name: '系统构建',
        dir: 'system-build',
        desc: '工具链与入门准备 → U-Boot 移植 → 主线内核 → BusyBox 手搓 rootfs → Buildroot 工程化 → 完整系统实战启动。',
        status: 'done',
        link: '/tutorial/system-build/',
      },
      {
        no: '阶段 4',
        name: '驱动与实战',
        dir: 'driver-dev',
        desc: '字符设备 → 设备树 → pinctrl/GPIO → I2C/SPI/RTC/触摸/音频,再到 light-meter 完整产品级项目 —— 本教程的核心重头戏。',
        status: 'reviewing',
        link: '/tutorial/driver-dev/',
      },
      {
        no: '阶段 5',
        name: '模拟与调试',
        dir: 'emulation',
        desc: '没板子也能跑:mcimx6ul-evk + 16 个外设模型补丁;gdbserver 远程调试、strace/core dump、串口日志读法。',
        status: 'done',
        link: '/tutorial/emulation/',
      },
      {
        no: '阶段 6',
        name: '烧录与进阶',
        dir: 'flashing',
        desc: '存储介质与分区、i.MX6ULL 启动流程与偏移、整包镜像设计、SD/UUU+eMMC 烧录;构建目录、patch 工作流与 rootfs overlay。',
        status: 'done',
        link: '/tutorial/flashing/',
      },
      {
        no: '阶段 7',
        name: '速查与参考',
        dir: 'cheatsheet',
        desc: '镜像构建/检查/存储/烧录命令速查,第三方组件说明,以及脚本手册与参考手册索引。',
        status: 'done',
        link: '/tutorial/cheatsheet/',
      },
    ],
  },

  // 首页社区区块:QQ 交流群。留空/不设则首页不渲染(与 homeScreenshots/homeRoadmap 同开关约定)。
  // qrCode 走 public/ 相对路径,组件内 withBase 补 base。
  community: {
    title: '技术交流',
    qq: {
      group: '645248275',
      link: 'https://qm.qq.com/q/tEsFhL8eB2',
      qrCode: '/qq-group.svg',
      desc: '搭建环境卡住、内核跑不起来、驱动写了没反应 —— 欢迎进群与作者和同学们一起踩坑。',
    },
  },

  favicon: '/imx-forge/Awesome-Embedded.ico',

  homeBanner: {
    'zh-CN': '新手必读：不知道从哪里开始？请先查看 <a href="/imx-forge/tutorial/start/00_roadmap">学习路线图</a>，了解嵌入式Linux的学习路径和项目结构。',
  },
})
