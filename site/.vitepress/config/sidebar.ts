import type { DefaultTheme } from 'vitepress'
import { readdirSync, statSync, readFileSync, existsSync } from 'fs'
import { join } from 'path'
import type { ProjectConfig, TutorialSection, VolumeConfig } from './schema'

type SidebarItem = DefaultTheme.SidebarItem

function extractTitle(filePath: string): string | null {
  try {
    const content = readFileSync(filePath, 'utf-8')
    const fmMatch = content.match(/^---[\s\S]*?^title:\s*['"]?(.+?)['"]?\s*$/m)
    if (fmMatch) return fmMatch[1]
    const h1 = content.match(/^#\s+(.+)$/m)
    if (h1) return h1[1].replace(/\{.*?\}/g, '').trim()
  } catch { /* ignore */ }
  return null
}

function humanize(name: string): string {
  return name
    .replace(/^\d+[-]?/, '')
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
}

// 学习顺序：Linux基础(预备营) → 入门准备 → Docker → U-Boot → 内核 → 文件系统 → Buildroot 根文件系统 → 驱动 → 实战 → 调试与排错 → 工程实战项目 → 镜像烧录 → 命令速查 → 构建进阶 → 开发环境配置 → 第三方 → 来稿
const LEARNING_ORDER = [
  'linux-basics',
  'start',
  'docker',
  'uboot',
  'kernel',
  'rootfs',
  'buildroot',
  'emu',
  'driver',
  'practical',
  'debug',
  'project',
  'flash',
  'commands',
  'build',
  'workflow',
  'third_party',
  'contrib',
]

function sortEntries(a: string, b: string): number {
  const na = a.match(/^(\d+)/)?.[1]
  const nb = b.match(/^(\d+)/)?.[1]
  if (na && nb) return parseInt(na) - parseInt(nb)
  if (na) return -1
  if (nb) return 1

  // 对于没有数字前缀的目录，按学习顺序排序
  const ia = LEARNING_ORDER.indexOf(a)
  const ib = LEARNING_ORDER.indexOf(b)
  if (ia !== -1 && ib !== -1) return ia - ib
  if (ia !== -1) return -1
  if (ib !== -1) return 1

  return a.localeCompare(b, 'en')
}

function scanDir(dir: string, urlPrefix: string, depth = 0): SidebarItem[] {
  if (depth > 5) return []

  let entries: string[]
  try {
    entries = readdirSync(dir).filter(e =>
      !e.startsWith('.') &&
      e !== 'hooks' &&
      e !== 'stylesheets' &&
      e !== 'javascripts' &&
      e !== 'images' &&
      e !== 'logo'
    )
  } catch { return [] }

  entries.sort(sortEntries)
  const items: SidebarItem[] = []

  for (const name of entries) {
    const fullPath = join(dir, name)
    if (!statSync(fullPath).isDirectory() && !name.endsWith('.md')) continue

    if (statSync(fullPath).isDirectory()) {
      const subItems = scanDir(fullPath, `${urlPrefix}/${name}`, depth + 1)
      const indexPath = join(fullPath, 'index.md')
      const title = extractTitle(indexPath) || humanize(name)

      if (subItems.length > 0) {
        items.push({
          text: title,
          link: existsSync(indexPath) ? `${urlPrefix}/${name}/` : undefined,
          items: subItems,
          collapsed: depth > 0,
        })
      } else if (existsSync(indexPath)) {
        items.push({ text: title, link: `${urlPrefix}/${name}/` })
      }
    } else if (name !== 'index.md' && name !== 'tags.md') {
      const title = extractTitle(fullPath) || humanize(name.replace(/\.md$/, ''))
      items.push({ text: title, link: `${urlPrefix}/${name.replace(/\.md$/, '')}` })
    }
  }

  return items
}

export function volumeSidebar(
  docsRoot: string,
  vol: VolumeConfig
): DefaultTheme.SidebarItem[] {
  const dir = join(docsRoot, vol.srcDir)
  const indexPath = join(dir, 'index.md')
  const items = scanDir(dir, vol.urlPrefix)

  const overviewTitle = extractTitle(indexPath) || humanize(vol.srcDir)
  return [
    { text: overviewTitle, link: `${vol.urlPrefix}/` },
    ...items,
  ]
}

// ── 教程分区 ─────────────────────────────────────────────────
// 一个「学习分区」横跨多个物理目录(如「系统构建」= start + uboot + kernel + …)。
// 做法:把该分区内所有目录合并成一份侧栏数组,再挂到分区 slug 与每个目录的
// 路径前缀上。VitePress 的 getSidebar() 按「路径段数」降序取首个命中前缀,
// 因此 `/tutorial/uboot/`(4 段)必压过 `/tutorial/`(3 段),分区视图得以生效。
//
// 注意:跨目录的侧栏必须用绝对路径 —— 同一份数组要挂到多个不同前缀上,
// VitePress 的 base 相对写法在这里无法成立。
export function sectionSidebar(
  docsRoot: string,
  section: TutorialSection
): DefaultTheme.SidebarItem[] {
  const items: DefaultTheme.SidebarItem[] = [
    {
      text: section.overviewText ?? `${section.title} · 分区总览`,
      link: `/tutorial/${section.slug}/`,
    },
  ]

  // 不拥有物理目录的分区(如「快速上手」):总览页是跨目录精选,入口靠手工声明。
  if (section.links?.length) {
    items.push({
      text: section.linksText ?? '精选入口',
      collapsed: false,
      items: section.links.map(link => ({ text: link.text, link: link.link })),
    })
  }

  for (const dir of section.dirs) {
    const dirPath = join(docsRoot, 'tutorial', dir)
    if (!existsSync(dirPath)) continue

    const indexPath = join(dirPath, 'index.md')
    const hasIndex = existsSync(indexPath)
    const subItems = scanDir(dirPath, `/tutorial/${dir}`, 0)

    if (subItems.length === 0 && !hasIndex) continue

    items.push({
      text: extractTitle(indexPath) || humanize(dir),
      link: hasIndex ? `/tutorial/${dir}/` : undefined,
      items: subItems.length > 0 ? subItems : undefined,
      // 分区内各章默认折叠:进入任一页先看到分区骨架,而非上百个章节。
      collapsed: true,
    })
  }

  return items
}

/** 把分区侧栏注册到 slug 与每个目录前缀上,返回 { 前缀: 侧栏 } 映射。 */
export function buildSectionSidebars(
  docsRoot: string,
  sections: TutorialSection[]
): Record<string, DefaultTheme.SidebarItem[]> {
  const map: Record<string, DefaultTheme.SidebarItem[]> = {}
  for (const section of sections) {
    const sidebarItems = sectionSidebar(docsRoot, section)
    for (const prefix of [section.slug, ...section.dirs]) {
      map[`/tutorial/${prefix}/`] = sidebarItems
    }
  }
  return map
}

export function buildSidebar(
  docsRoot: string,
  config: ProjectConfig
): DefaultTheme.Sidebar {
  const sidebar: DefaultTheme.Sidebar = {}

  for (const vol of config.sidebar.volumes) {
    sidebar[`${vol.urlPrefix}/`] = volumeSidebar(docsRoot, vol)
  }

  if (config.sidebar.extra) {
    Object.assign(sidebar, config.sidebar.extra)
  }

  // 教程分区:必须放在 extra 之后 —— extra 里的 '/tutorial/' 是分区导航总览,
  // 而分区侧栏的前缀恒为 4 段(更深),两者互不覆盖。
  if (config.sidebar.sections?.length) {
    Object.assign(sidebar, buildSectionSidebars(docsRoot, config.sidebar.sections))
  }

  // Build sidebar for non-default locales
  for (const locale of config.locales) {
    if (locale.default || !locale.dir) continue
    const localeDir = join(docsRoot, locale.dir)
    if (!existsSync(localeDir)) continue

    const localeItems = scanDir(localeDir, locale.prefix || `/${locale.dir}`)
    if (localeItems.length > 0) {
      const prefix = locale.prefix || `/${locale.dir}/`
      sidebar[prefix] = [{ text: locale.label, items: localeItems }]
    }
  }

  return sidebar
}
