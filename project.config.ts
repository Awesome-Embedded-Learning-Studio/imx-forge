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

  nav: {
    'zh-CN': [
      { text: '首页', link: '/' },
      { text: '教程', link: '/tutorial/' },
      { text: 'CI/CD', link: '/ci/' },
      { text: '架构', link: '/architecture/' },
      { text: '脚本', link: '/scripts/' },
      { text: '发布', link: '/release/' },
      { text: '参考', link: '/reference/' },
      { text: '贡献者', link: '/team/' },
      { text: 'GitHub', link: 'https://github.com/Awesome-Embedded-Learning-Studio/imx-forge' },
    ],
  },

  sidebar: {
    volumes: [
      { name: 'tutorial', srcDir: 'tutorial', urlPrefix: '/tutorial' },
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
    // Mermaid 图表:开启 —— ```mermaid 块渲染为 SVG(客户端按需从 jsdelivr CDN 加载)。
    // 离线/内网环境图渲染失败(不影响其它内容);需关闭时改 false。
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
    title: '📍 学习路线图',
    next:
      '推荐顺序:Linux 基础 → 开发环境(Docker)→ U-Boot → 内核 → 根文件系统 → 驱动开发(重头戏)→ 实战 → 构建系统。各阶段可按需跳读,但驱动开发依赖前面所有基础。',
    stages: [
      {
        no: '阶段 0',
        name: 'Linux 基础预备营',
        dir: 'linux-basics',
        chapters: 36,
        desc: 'Ubuntu 命令行、Shell、文件系统、进程、网络与交叉编译入门,为零基础读者打底,无缝衔接嵌入式开发。',
        status: 'done',
        link: '/tutorial/linux-basics/',
      },
      {
        no: '阶段 1',
        name: '开发环境',
        dir: 'docker',
        chapters: 3,
        desc: 'Docker 一键部署 ARM GNU Toolchain 15.2,WSL2 深度友好,告别环境配置地狱。',
        status: 'done',
        link: '/tutorial/docker/',
      },
      {
        no: '阶段 2',
        name: 'U-Boot 移植',
        dir: 'uboot',
        chapters: 11,
        desc: 'Bootloader 原理、Makefile 结构、板级配置、驱动 LCD 与网卡,把 i.MX6ULL 引导起来。',
        status: 'done',
        link: '/tutorial/uboot/',
      },
      {
        no: '阶段 3',
        name: '内核移植',
        dir: 'kernel',
        chapters: 33,
        desc: '双轨策略:NXP BSP (6.12.3) 稳定可靠 + Mainline (7.1) 紧跟上游。设备树、Kconfig、编译与烧写。',
        status: 'done',
        link: '/tutorial/kernel/',
      },
      {
        no: '阶段 4',
        name: '根文件系统',
        dir: 'rootfs',
        chapters: 7,
        desc: 'BusyBox / Buildroot 构建最小 rootfs,init 流程、库依赖、文件系统镜像制作。',
        status: 'done',
        link: '/tutorial/rootfs/',
      },
      {
        no: '阶段 5',
        name: '驱动开发',
        dir: 'driver',
        chapters: 121,
        desc: '从字符设备到 pinctrl/gpio 子系统,从硬件原理到驱动实战 —— 本教程的核心重头戏,持续扩张中。',
        status: 'reviewing',
        link: '/tutorial/driver/',
      },
      {
        no: '阶段 6',
        name: '实战演练',
        dir: 'practical',
        chapters: 5,
        desc: '完整系统构建与调试,从零到一的嵌入式项目实战,把前面所有知识串起来。',
        status: 'planned',
        link: '/tutorial/practical/',
      },
      {
        no: '阶段 7',
        name: '构建系统',
        dir: 'build',
        chapters: 4,
        desc: 'Bash + Make 自动化构建、CI/CD 验证、一键发布,把手工流程变成可信工程。',
        status: 'done',
        link: '/tutorial/build/',
      },
    ],
  },

  favicon: '/imx-forge/Awesome-Embedded.ico',

  homeBanner: {
    'zh-CN': '🚀 新手必读：不知道从哪里开始？请先查看 <a href="/imx-forge/tutorial/start/00_roadmap">学习路线图</a>，了解嵌入式Linux的学习路径和项目结构。',
  },
})
