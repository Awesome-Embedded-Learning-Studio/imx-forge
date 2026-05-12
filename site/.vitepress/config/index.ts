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
    },
  },

  locales: buildLocales(),

  head: [
    ['link', { rel: 'icon', href: projectConfig.favicon || `${projectConfig.base}favicon.ico` }],
  ],

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
