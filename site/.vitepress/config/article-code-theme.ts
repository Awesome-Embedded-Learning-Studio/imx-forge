import type { ThemeRegistration } from 'shiki'
import githubLight from 'shiki/themes/github-light.mjs'
import githubDark from 'shiki/themes/github-dark.mjs'

// 为什么不从零写主题、也不直接用内置 github-light/dark:
//   - 从零写 = 手维护几百条 TextMate scope 规则,shiki 每次升级都要跟着核对;
//   - 直接用内置 = 原版 github 配色饱和度偏高,与站点的低饱和卡片令牌(article-code.css)不搭。
// 折中:以内置 github 主题为底,只把 8 个高频前景色(正文/注释/关键字/字符串等)重映射
// 到自己的低饱和色阶 —— scope 结构原样保留,shiki 升级带来的新规则自动跟进,维护面最小。
function recolor(theme: ThemeRegistration, name: string, palette: Record<string, string>): ThemeRegistration {
  // 命中调色板才替换,未命中的颜色原样透传,避免误伤 github 主题里的其余几十种色值。
  const color = (value: string | undefined) => value && (palette[value.toLowerCase()] ?? value)
  return {
    ...theme,
    name,
    colors: {
      ...theme.colors,
      // editor.foreground 是代码正文的默认前景,行号/未匹配文本也继承它,必须跟着换。
      'editor.foreground': color(theme.colors?.['editor.foreground'])!,
    },
    tokenColors: theme.tokenColors?.map((rule) => ({
      ...rule,
      settings: { ...rule.settings, foreground: color(rule.settings.foreground) },
    })),
  }
}

// 产出 article-light / article-dark 双主题对象,config/index.ts 的 markdown.theme 直接引用。
// 双主题机制本身由 VitePress 接管(明暗各渲一份、html.dark 切换),这里只管两份配色。
export const articleCodeThemes = {
  // 明色:github-light 的 8 个主色 → 偏冷灰/低饱和,与 --article-code-* 明色令牌同族。
  light: recolor(githubLight, 'article-light', {
    '#24292e': '#364152',
    '#6a737d': '#697482',
    '#d73a49': '#925477',
    '#005cc5': '#376b9b',
    '#6f42c1': '#6756a0',
    '#032f62': '#286f66',
    '#22863a': '#347252',
    '#e36209': '#99612f',
  }),
  // 暗色:github-dark 同理 → 提亮降饱和,暗底下对比度够但不刺眼。
  dark: recolor(githubDark, 'article-dark', {
    '#e1e4e8': '#dce3ee',
    '#6a737d': '#9ba6b8',
    '#f97583': '#db9bbb',
    '#79b8ff': '#96bce9',
    '#b392f0': '#c0ade7',
    '#9ecbff': '#9ecfc3',
    '#85e89d': '#99c7a5',
    '#ffab70': '#dcbb8d',
  }),
}
