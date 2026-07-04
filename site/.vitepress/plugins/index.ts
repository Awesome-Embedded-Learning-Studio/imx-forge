import type MarkdownIt from 'markdown-it'
import type { ProjectConfig } from '../config/schema'
import { cppTemplateEscapePlugin } from './escape-cpp-templates'
import { kbdPlugin } from './kbd-plugin'
import { languageAliasPlugin } from './language-aliases'
import { codeFoldPlugin } from './code-fold-plugin'
import { mermaidPlugin } from './mermaid-plugin'

export function resolvePlugins(md: MarkdownIt, config: ProjectConfig): void {
  md.use(languageAliasPlugin)
  if (config.plugins.cppTemplateEscape) {
    cppTemplateEscapePlugin(md)
  }
  if (config.plugins.kbd) {
    md.use(kbdPlugin)
  }
  // 长代码折叠:覆写 fence 渲染器,把 >阈值行数的代码块包成 <details>。
  if (config.plugins.codeFold) {
    const lines = config.readingDefaults?.codeFoldLines ?? 20
    md.use(codeFoldPlugin(lines))
  }
  // Mermaid:用 core ruler 把 ```mermaid fence 改型为 mermaid_diagram(交给客户端 CDN 渲染)。
  // 与 code-fold 无注册顺序要求:mermaid 在 core 阶段(渲染前)就把 token 类型改掉,
  // 故 code-fold 的 fence 渲染器永远拿不到 mermaid 块,两插件互不干扰。
  if (config.plugins.mermaid) {
    md.use(mermaidPlugin)
  }
}
