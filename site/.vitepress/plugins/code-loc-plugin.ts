import type { PluginSimple } from 'markdown-it'
import type MarkdownIt from 'markdown-it'

/**
 * CodeLoc 出处卡:把围栏代码包进「项目徽章 + 文件路径」的出处卡,让代码段
 * 天生带着「在哪个仓库哪个文件第几行」的出处。
 *
 * 用法:
 *   ::: code-loc uboot-mainline arch/arm/include/asm/arch-mx6/imx-regs.h:67
 *   ```c
 *   #define IRAM_BASE_ADDR 0x00900000
 *   ```
 *   :::
 *
 * 第一个空格前是项目名(徽章文案),其余是路径;路径可整体包引号(含空格时用)。
 *
 * 为什么是构建期 markdown-it 容器插件、而不是让作者直接写 <CodeLoc> 标签:
 *   - HTML 块内的 markdown 不解析:标签里直接写 ``` 围栏会被当原文吞掉,
 *     shiki 高亮、复制按钮、行号全丢(HTML block 规则:块级标签吞到空行为止)。
 *   - 容器内的 fence 走完整渲染链,VitePress 的 Shiki/复制按钮/行号/code-fold
 *     全保留。与 code-fold 的关系:fold 覆写 fence 渲染器整段包 <details>,
 *     不感知本容器,fold 卡在出处卡内照常工作(嵌套卡面由 article-code.css 摊平)。
 *
 * 配对机制(为什么 close 不会误伤):
 *   block 解析逐行推进,本 rule 在每个候选行被调用,同一段代码处理 open 和 close:
 *   - 行匹配 `::: code-loc <args>` → 推 open token,只跳一行。内容交由后续
 *     解析(fence 等照常消费),容器内 markdown 因此完整解析——这正是必须拆
 *     open/close 两次推送、不能在 open 时一次扫描吞掉整个区间的原因。
 *   - 行匹配裸 `:::` 且 token 流里最近的 code-loc token 是「未闭合 open」→ 推 close。
 *     该判定天然处理嵌套(tip/code-group 的 open/close 是别的 token 类型,
 *     不参与配对);fence 内部顶格的 ::: 也不会误伤——fence rule 一次性消费
 *     整个围栏区间,期间容器 rule 根本不会被调用。
 *   - 孤立的裸 `:::`(上面没有开着的容器)不生效,原样当段落文本,
 *     作者一眼能看到容器没闭合,失败是显眼的。
 */

const CONTAINER_OPEN = 'container_code-loc_open'
const CONTAINER_CLOSE = 'container_code-loc_close'

// open 行要求 args 非空:没有路径的出处卡没有意义,不匹配则整行当普通段落,
// 让「::: code-loc」字样直接露在正文里提醒作者补参数。
const OPEN_RE = /^:::[ \t]+code-loc[ \t]+(.+?)[ \t]*$/
const CLOSE_RE = /^:::[ \t]*$/

/** HTML 属性转义:容器参数进 <CodeLoc> 的属性值,必须转义 & " < >。 */
function escapeAttr(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

/** 第一个空白处切分项目名与路径;路径允许整体带单/双引号(路径含空格时用)。 */
function parseArgs(raw: string): { project: string; path: string } {
  const trimmed = raw.trim()
  const spaceAt = trimmed.search(/\s/)
  if (spaceAt === -1) return { project: trimmed, path: '' }
  const project = trimmed.slice(0, spaceAt)
  let path = trimmed.slice(spaceAt + 1).trim()
  const quote = path[0]
  const last = path.at(-1)
  if (path.length >= 2 && (quote === '"' || quote === "'") && last === quote) {
    path = path.slice(1, -1)
  }
  return { project, path }
}

/**
 * token 流里最近的 code-loc token 是否为未闭合的 open。
 * 从尾向头找,先碰到 open 说明当前在该容器内(裸 ::: 是它的 close),
 * 先碰到 close 说明容器已闭合(裸 ::: 是孤立的,不生效)。
 */
function isOpenCodeLocPending(tokens: MarkdownIt.Token[]): boolean {
  for (let i = tokens.length - 1; i >= 0; i--) {
    const type = tokens[i].type
    if (type === CONTAINER_OPEN) return true
    if (type === CONTAINER_CLOSE) return false
  }
  return false
}

export const codeLocPlugin: PluginSimple = (md: MarkdownIt) => {
  md.block.ruler.after(
    'fence',
    'container_code-loc',
    (state, startLine, _endLine, silent) => {
      const lineStart = state.bMarks[startLine] + state.tShift[startLine]
      const lineEnd = state.eMarks[startLine]
      const line = state.src.slice(lineStart, lineEnd)

      const openMatch = OPEN_RE.exec(line)
      if (openMatch) {
        if (!silent) {
          const token = state.push(CONTAINER_OPEN, 'div', 1)
          token.block = true
          token.info = openMatch[1] ?? ''
          token.markup = ':::'
          token.map = [startLine, startLine + 1]
        }
        state.line = startLine + 1
        return true
      }

      if (CLOSE_RE.test(line) && isOpenCodeLocPending(state.tokens)) {
        if (!silent) {
          const token = state.push(CONTAINER_CLOSE, 'div', -1)
          token.block = true
          token.markup = ':::'
          token.map = [startLine, startLine + 1]
        }
        state.line = startLine + 1
        return true
      }

      return false
    },
    { alt: ['paragraph', 'reference', 'blockquote', 'list'] },
  )

  md.renderer.rules[CONTAINER_OPEN] = (tokens, idx) => {
    const { project, path } = parseArgs(tokens[idx].info)
    return `<CodeLoc project="${escapeAttr(project)}" path="${escapeAttr(path)}">\n`
  }

  md.renderer.rules[CONTAINER_CLOSE] = () => '</CodeLoc>\n'
}
