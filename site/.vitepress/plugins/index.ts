import type MarkdownIt from 'markdown-it'
import type { ProjectConfig } from '../config/schema'
import { cppTemplateEscapePlugin } from './escape-cpp-templates'
import { kbdPlugin } from './kbd-plugin'
import { languageAliasPlugin } from './language-aliases'

export function resolvePlugins(md: MarkdownIt, config: ProjectConfig): void {
  md.use(languageAliasPlugin)
  if (config.plugins.cppTemplateEscape) {
    cppTemplateEscapePlugin(md)
  }
  if (config.plugins.kbd) {
    md.use(kbdPlugin)
  }
}
