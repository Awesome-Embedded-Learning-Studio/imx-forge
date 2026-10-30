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

/**
 * 教程分区:把一个「学习分区」映射到 tutorial 下的若干物理目录。
 *
 * 动机见 site/.vitepress/config/sidebar.ts:VitePress 的多侧栏按「路径段数」
 * 匹配,所以只要为分区下每个目录前缀都注册同一份侧栏数组,就能让 18 个目录
 * 各归其位、而无需移动任何正文文件(URL 保持不变)。
 */
export interface TutorialSection {
  /** 分区落地页所在目录名,/tutorial/<slug>/ 即分区总览。 */
  slug: string
  /** 分区显示名,用于侧栏首项与导航。 */
  title: string
  /** 该分区覆盖的 tutorial 子目录名(不含 slug 自身)。 */
  dirs: string[]
  /** 侧栏首项文案,缺省 `${title} · 分区总览`。 */
  overviewText?: string
  /**
   * 手工补充的侧栏入口。用于 `dirs: []` 的分区(如「快速上手」):这类分区
   * 不拥有任何物理目录,总览页本身是跨目录的精选导航,需要显式列出入口,
   * 否则侧栏只剩「分区总览」一项。
   */
  links?: { text: string; link: string }[]
  /** `links` 分组标题,缺省「精选入口」。 */
  linksText?: string
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

/** 首页社区区块的 QQ 群信息。qrCode 走 withBase(public/ 下相对路径)。 */
export interface CommunityQqConfig {
  /** 群号(展示用)。 */
  group: string
  /** 加群链接。 */
  link: string
  /** 二维码图片路径(public/ 下,如 '/qq-group.svg')。 */
  qrCode: string
  desc?: string
}

/** 首页社区区块。留空/不设则首页不渲染。 */
export interface CommunityConfig {
  title?: string
  qq: CommunityQqConfig
}

/**
 * 顶栏导航项:既可直接跳转(link)、又可展开二级菜单(items)。
 *
 * VitePress 的 NavItem 是两个互斥的联合成员,对象字面量里同时写 link 与 items
 * 会被多余属性检查拒掉;主题侧已覆盖 VPNavBarMenu 支持这种形态(见
 * theme/components/NavSplitItem.vue),这里同步补上类型。
 *
 * 注意:不能写成 `NavItemWithLink & { items: NavItem[] }` —— 内置 NavItemWithLink
 * 的 `items?: never` 是判别字段,交叉后 items 归并为 never,该类型实际不可用,
 * 字面量检查必然报「多余属性」。先 Omit 掉判别字段,再补真实子目录类型。
 */
export type NavItemWithLinkAndItems = Omit<
  DefaultTheme.NavItemWithLink,
  'items'
> & {
  items: DefaultTheme.NavItem[]
}

export type ProjectNavItem = DefaultTheme.NavItem | NavItemWithLinkAndItems

export interface ProjectConfig {
  name: string
  title: Record<string, string>
  description: Record<string, string>
  base: string
  copyright: string

  documentsDir: string
  siteDir: string

  locales: LocaleConfig[]

  nav: Record<string, ProjectNavItem[]>
  sidebar: {
    volumes: VolumeConfig[]
    extra?: Record<string, DefaultTheme.SidebarItem[]>
    /** 教程分区:每个分区会覆盖其 slug 与 dirs 的全部路径前缀侧栏。 */
    sections?: TutorialSection[]
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

  /** 首页社区区块(QQ 交流群)数据。留空/不设则首页不渲染社区卡。 */
  community?: CommunityConfig

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
