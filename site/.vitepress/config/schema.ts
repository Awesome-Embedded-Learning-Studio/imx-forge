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

/** 正文字号档位,由 FontSizeSwitcher 切换并持久化到 localStorage('vp-font-size')。 */
export type FontTier = 'xxsmall' | 'small' | 'normal' | 'large' | 'xxlarge'

/** 阅读体验默认值:首屏防闪脚本与初次拖拽时使用。全部可选,有内置兜底。 */
export interface ReadingDefaults {
  /** 默认字号档,首次访问(无 localStorage)时应用。默认 'normal'。 */
  fontTier?: FontTier
  /** 左侧导航栏默认宽度(px),范围 200–480。默认 272(VitePress 原值)。 */
  sidebarWidth?: number
  /** 右侧大纲栏默认宽度(px),范围 180–360。默认 256。 */
  asideWidth?: number
  /** 代码块超过该行数则自动折叠。默认 20。 */
  codeFoldLines?: number
}

/** 首页截图轮播的单张幻灯片。src 走 withBase(public/ 下相对路径)。 */
export interface HomeScreenshot {
  src: string
  href: string
  title: string
  desc: string
}

export type RoadmapStatus = 'done' | 'reviewing' | 'planned'

/** 首页学习路线图的一个阶段卡。 */
export interface RoadmapStage {
  no: string
  name: string
  dir?: string
  chapters?: number
  desc: string
  status: RoadmapStatus
  link: string
}

export interface HomeRoadmapConfig {
  title?: string
  /** 卡片下方的「学习顺序说明」脚注。 */
  next?: string
  stages: RoadmapStage[]
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
    /** 阅读体验三件套:字号切换 + 侧栏/大纲可拖拽 + 顶部阅读进度条(含首屏防闪)。默认 true。 */
    readingUX?: boolean
    /** 长代码块(超 readingDefaults.codeFoldLines 行)自动折叠为 <details>。默认 true。 */
    codeFold?: boolean
    /** Mermaid 图表渲染(markdown-it 插件 + 按需 CDN 客户端)。默认 false(离线零影响)。 */
    mermaid?: boolean
  }

  /** 阅读体验默认值。可选,字段缺失走内置兜底。 */
  readingDefaults?: ReadingDefaults

  /** 首页截图轮播数据。留空/不设则首页不渲染轮播。 */
  homeScreenshots?: HomeScreenshot[]

  /** 首页学习路线图数据。留空/不设则首页不渲染路线图。 */
  homeRoadmap?: HomeRoadmapConfig

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

  // 为新增插件开关填充「sensible defaults」:未显式设置时走主题推荐默认值。
  // 这样旧的 project.config.ts 不写新字段也能拿到合理行为,主题保持「写少即可用」。
  if (config.plugins.readingUX === undefined) config.plugins.readingUX = true
  if (config.plugins.codeFold === undefined) config.plugins.codeFold = true
  if (config.plugins.mermaid === undefined) config.plugins.mermaid = false

  return config
}
