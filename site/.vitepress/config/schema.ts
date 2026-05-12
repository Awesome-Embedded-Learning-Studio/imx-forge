import type { DefaultTheme } from 'vitepress'

// ── Types ──────────────────────────────────────────────────

export interface LocaleConfig {
  code: string
  label: string
  default?: boolean
  prefix?: string
  dir?: string
}

export interface VolumeConfig {
  name: string
  srcDir: string
  urlPrefix: string
}

export interface ProjectConfig {
  name: string
  title: Record<string, string>
  description: Record<string, string>
  base: string
  copyright: string

  documentsDir: string
  siteDir: string

  locales: LocaleConfig[]

  nav: Record<string, DefaultTheme.NavItem[]>
  sidebar: {
    volumes: VolumeConfig[]
    extra?: Record<string, DefaultTheme.SidebarItem[]>
  }

  github: {
    owner: string
    repo: string
    branch: string
    documentsPath: string
  }

  build: {
    concurrency?: number
    cacheDir?: string
    rootAssets?: string[]
    rootPages?: string[]
  }

  plugins: {
    cppTemplateEscape?: boolean
    kbd?: boolean
    math?: boolean
  }

  homeBanner?: Record<string, string>
  favicon?: string
}

// ── defineProject ──────────────────────────────────────────

export function defineProject(config: ProjectConfig): ProjectConfig {
  const primaryLocale = config.locales.find(l => l.default)
  if (!primaryLocale) {
    throw new Error('project.config.ts: exactly one locale must have default: true')
  }
  if (!config.title[primaryLocale.code]) {
    throw new Error(`project.config.ts: title missing for primary locale "${primaryLocale.code}"`)
  }
  return config
}
