import { nextTick, onMounted } from 'vue'
import { useRouter } from 'vitepress'

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

export function setupMermaid() {
  const router = useRouter()

  onMounted(() => renderMermaidDiagrams())
  router.onAfterRouteChange = () => renderMermaidDiagrams()
}
