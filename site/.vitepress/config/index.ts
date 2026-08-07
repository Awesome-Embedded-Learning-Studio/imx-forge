import { defineConfig } from 'vitepress'
import type { DefaultTheme } from 'vitepress'
import { buildSidebar } from './sidebar'
import { resolvePlugins } from '../plugins'
import type { ProjectConfig } from './schema'
import { resolve } from 'path'

// ── Load project config ──────────────────────────────────
// This file is the VitePress entry point. It reads the user's
// project.config.ts and generates the full VitePress config.
//
// Usage: user creates project.config.ts at project root, and
// this file is imported as the VitePress site config.

// Import the project config from the project root.
// The path is relative to this file's location at:
//   site/.vitepress/config/index.ts
// So ../../../project.config reaches the project root.
import projectConfig from '../../../project.config'

const primaryLocale = projectConfig.locales.find(l => l.default)!
const defaultTitle = projectConfig.title[primaryLocale.code]
const defaultDesc = projectConfig.description[primaryLocale.code]
const githubUrl = `https://github.com/${projectConfig.github.owner}/${projectConfig.github.repo}`
const editPatternBase = `${githubUrl}/edit/${projectConfig.github.branch}/${projectConfig.github.documentsPath}`

// Resolve docsRoot relative to this file (site/.vitepress/config/)
const docsRoot = new URL(`../../../${projectConfig.documentsDir}`, import.meta.url).pathname.replace(/\/$/, '')

// Build locales config
function buildLocales(): Record<string, any> {
  const locales: Record<string, any> = {}

  for (const locale of projectConfig.locales) {
    const locKey = locale.default ? 'root' : (locale.prefix?.replace(/\//g, '') || locale.code)
    const title = projectConfig.title[locale.code]
    const desc = projectConfig.description[locale.code]

    const baseConfig: any = {
      label: locale.label,
      lang: locale.code,
      title,
      description: desc,
    }

    if (!locale.default && locale.prefix) {
      baseConfig.link = locale.prefix
    }

    // Add locale-specific theme config (edit link, nav)
    if (!locale.default) {
      baseConfig.themeConfig = {
        nav: projectConfig.nav[locale.code] || [],
        editLink: {
          pattern: `${editPatternBase}${locale.dir ? `/${locale.dir}` : ''}/:path`,
          text: `Edit this page on GitHub`,
        },
      }
    }

    locales[locKey] = baseConfig
  }

  return locales
}

// ── <head> 注入 ──────────────────────────────────────────────
// favicon 之外,当 readingUX 开启时注入两段「防闪烁」内联脚本:
// 它们在 Vue hydration 之前同步执行,把 localStorage 里持久化的字号/侧栏宽度直接应用成
// CSS 变量与 data 属性,避免「先以默认值渲染再跳变」的 FOUC。默认值取自 readingDefaults。
const head: NonNullable<ReturnType<typeof defineConfig>['head']> = [
  ['link', { rel: 'icon', href: projectConfig.favicon || `${projectConfig.base}favicon.ico` }],
]

if (projectConfig.plugins.readingUX) {
  const defaultFont = projectConfig.readingDefaults?.fontTier ?? 'normal'
  // 字号档:校验后写 documentElement.dataset.fontSize(custom.css 的 html[data-font-size] zoom 据此生效)
  head.push([
    'script',
    {},
    `(function(){try{var s=localStorage.getItem('vp-font-size')||'${defaultFont}';if(s!=='xxsmall'&&s!=='small'&&s!=='normal'&&s!=='large'&&s!=='xxlarge'){s='normal';}document.documentElement.dataset.fontSize=s;}catch(e){}})()`,
  ])
  // 侧栏 / 大纲宽度:clamp 到合法区间,越界回落默认(防篡改 / 旧脏值)
  const sbDef = projectConfig.readingDefaults?.sidebarWidth ?? 272
  const aDef = projectConfig.readingDefaults?.asideWidth ?? 256
  head.push([
    'script',
    {},
    `(function(){try{var w=parseInt(localStorage.getItem('vp-sidebar-width'));if(!w||w<200||w>480){w=${sbDef};}document.documentElement.style.setProperty('--vp-sidebar-width',w+'px');var a=parseInt(localStorage.getItem('vp-aside-width'));if(!a||a<180||a>360){a=${aDef};}document.documentElement.style.setProperty('--vp-aside-width',a+'px');}catch(e){}})()`,
  ])
}

export default defineConfig({
  srcDir: `../${projectConfig.documentsDir}`,
  title: defaultTitle,
  description: defaultDesc,
  lang: primaryLocale.code,
  base: projectConfig.base,
  cleanUrls: true,
  lastUpdated: true,
  ignoreDeadLinks: false,

  vue: {
    template: {
      compilerOptions: {
        isCustomElement: (tag: string) => tag.includes('-') || tag.includes('.'),
      },
      // <video>/<source> 引 public/ 里的媒体时,别让 Vue 把 src/poster 当打包资源去 import:
      // 它们是运行时 public 路径(已含 base),交给浏览器直接请求即可。
      transformAssetUrls: {
        video: [],
        source: [],
      },
    },
  },

  locales: buildLocales(),

  head,

  markdown: {
    lineNumbers: true,
    math: projectConfig.plugins.math ?? false,
    theme: {
      light: 'github-light',
      dark: 'github-dark',
    },
    config(md) {
      resolvePlugins(md, projectConfig)
    },
  },

  vite: {
    publicDir: resolve(__dirname, '../public'),
    // mermaid 通过动态 import('mermaid') 懒加载;SSR 构建时把它外置,避免 SSR bundle
    // 试图打包这个浏览器侧重依赖(会因 DOM 依赖失败)。客户端构建照常拆成独立 chunk。
    ssr: {
      external: ['mermaid'],
    },
    build: {
      chunkSizeWarningLimit: 5000,
    },
  },

  themeConfig: {
    nav: projectConfig.nav[primaryLocale.code] || [],
    sidebar: buildSidebar(docsRoot, projectConfig),

    search: {
      provider: 'local',
    },

    editLink: {
      pattern: `${editPatternBase}/:path`,
      text: 'Edit this page on GitHub',
    },

    footer: {
      message: 'Built with VitePress',
      copyright: projectConfig.copyright,
    },

    socialLinks: [
      { icon: 'github', link: githubUrl },
    ],
  } satisfies DefaultTheme.Config,
})
