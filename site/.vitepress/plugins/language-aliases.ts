import type MarkdownIt from 'markdown-it'

const ALIASES: Record<string, string> = {
  'dts': 'c',
  'dtsi': 'c',
  'kconfig': 'ini',
  'qmake': 'makefile',
  'gitmodules': 'ini',
  'config': 'ini',
  'assembly': 'asm',
}

export function languageAliasPlugin(md: MarkdownIt): void {
  md.core.ruler.push('language-alias', (state) => {
    for (const token of state.tokens) {
      if (token.type === 'fence') {
        const lang = token.info.trim().split(/\s+/)[0]
        if (ALIASES[lang]) {
          token.info = ALIASES[lang] + token.info.slice(lang.length)
        }
      }
    }
    return true
  })
}
