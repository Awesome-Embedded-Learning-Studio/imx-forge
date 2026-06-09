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
      { name: 'todo', srcDir: 'todo', urlPrefix: '/todo' },
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
  },

  favicon: '/imx-forge/Awesome-Embedded.ico',

  homeBanner: {
    'zh-CN': '🚀 新手必读：不知道从哪里开始？请先查看 <a href="/imx-forge/tutorial/start/00_roadmap">学习路线图</a>，了解嵌入式Linux的学习路径和项目结构。',
  },
})
