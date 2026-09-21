import { nextTick, onMounted } from 'vue'
import { subscribeAfterRouteChange } from './router-hooks'
import { openMermaidLightbox } from './mermaid-lightbox'

// Mermaid 走 npm 打包(非 CDN):Vite 把下面的 `import('mermaid')` 拆成独立 chunk,
// 仅在「当前页真有 mermaid 图」时才按需加载。随站点一起部署 —— 离线 / 内网照常渲染,
// 不依赖任何外部 CDN。chunk 较大(数百 KB),但因懒加载,无图的页面零成本。
//
// SSR 安全:renderMermaidDiagrams 顶部 typeof window 守卫 + 仅在 onMounted / 路由切换
// 调用,SSR 期永不触发动 import。config 里另有 vite.ssr.external:['mermaid'] 让构建不卡。

interface MermaidApi {
  initialize: (config: Record<string, unknown>) => void
  render: (id: string, text: string) => Promise<{ svg: string; bindFunctions?: (el: Element) => void }>
}

let mermaidPromise: Promise<MermaidApi> | null = null
let initialized = false

// 动态 import → 独立 chunk。mod.default 是 mermaid 10.x 的 API 对象(initialize/render)。
function loadMermaid(): Promise<MermaidApi> {
  if (mermaidPromise) return mermaidPromise
  mermaidPromise = import('mermaid').then((mod) => {
    const api = (mod as { default?: MermaidApi }).default ?? (mod as unknown as MermaidApi)
    return api
  })
  return mermaidPromise
}

function initMermaid(api: MermaidApi) {
  if (initialized) return
  api.initialize({
    startOnLoad: false,
    securityLevel: 'loose',
    // 固定浅色(default)主题:initialize 只跑一次,图内配色不跟站点暗色模式走;
    // 让图随暗色切换重渲染是后续项,先维持现状。
    theme: 'default',
    flowchart: {
      htmlLabels: true,
      nodeSpacing: 50,
      rankSpacing: 50,
      padding: 15,
    },
    themeVariables: {
      fontSize: '15px',
    },
  })
  initialized = true
}

async function renderMermaidDiagrams() {
  if (typeof window === 'undefined') return

  // 先找图,再决定是否加载 chunk —— 无 mermaid 的页面不产生任何网络/解析成本。
  const nodes = Array.from(
    document.querySelectorAll<HTMLElement>('.mermaid-diagram[data-rendered="false"]')
  )
  if (nodes.length === 0) return

  const api = await loadMermaid()
  initMermaid(api)
  await nextTick()
  await new Promise<void>((r) => requestAnimationFrame(() => r()))

  for (let i = 0; i < nodes.length; i++) {
    const el = nodes[i]
    const raw = el.dataset.mermaid
    if (!raw) continue

    const source = decodeURIComponent(raw)
    const id = `mermaid-${Date.now()}-${i}-${Math.random().toString(36).slice(2, 8)}`

    try {
      const { svg } = await api.render(id, source)
      el.innerHTML = svg
      el.dataset.rendered = 'true'
      attachMaximize(el, source)
    } catch {
      el.dataset.rendered = 'error'
      el.innerHTML = `<pre class="mermaid-error">${escapeHtml(source)}</pre>`
    }
  }
}

function escapeHtml(s: string) {
  return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;')
}

// ── maximize 按钮:每张图都挂(跟 GitHub 一样,所有图都可缩放),点开进全屏模态 ──

// Feather maximize-2 图标(四角向外箭头),currentColor 随主题。
const MAXIMIZE_ICON =
  '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" ' +
  'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/>' +
  '<line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>'

function attachMaximize(el: HTMLElement, source: string) {
  const svg = el.querySelector('svg')
  if (!svg) return
  el.classList.add('mermaid-diagram--zoomable')

  const btn = document.createElement('button')
  btn.type = 'button'
  btn.className = 'mermaid-maximize-btn'
  btn.setAttribute('aria-label', '放大查看图表')
  btn.title = '放大查看图表'
  btn.innerHTML = MAXIMIZE_ICON
  btn.addEventListener('click', () => {
    openMermaidLightbox({ svg, source, trigger: btn })
  })
  el.appendChild(btn)
}

export function setupMermaid() {
  // 用订阅器而非直接赋值 router.onAfterRouteChange:后者是单值属性,
  // 会被 ReadingProgress 等组件覆盖,导致 SPA 跳转后 mermaid 不渲染。
  // .catch 治「静默失败」:之前调用没接住 reject,加载失败时图直接消失无痕。
  onMounted(() => renderMermaidDiagrams().catch((e) => console.error('[mermaid] onMounted 渲染失败', e)))
  subscribeAfterRouteChange(() => renderMermaidDiagrams().catch((e) => console.error('[mermaid] 路由切换渲染失败', e)))
}
