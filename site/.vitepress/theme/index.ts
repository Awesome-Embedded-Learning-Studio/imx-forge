import DefaultTheme from 'vitepress/theme'
import { defineComponent, h, type VNodeChild } from 'vue'
import type { Theme } from 'vitepress'
import ImxHero from './components/ImxHero.vue'
import ScreenshotCarousel from './components/ScreenshotCarousel.vue'
import HomeRoadmap from './components/HomeRoadmap.vue'
import HomeCommunity from './components/HomeCommunity.vue'
import HomeTipBanner from './components/HomeTipBanner.vue'
import HomeFeatureGrid from './components/HomeFeatureGrid.vue'
import ProofStrip from './components/ProofStrip.vue'
import NavSpinner from './components/NavSpinner.vue'
import MermaidLightbox from './components/MermaidLightbox.vue'
import ChapterNav from './components/ChapterNav.vue'
import ChapterLink from './components/ChapterLink.vue'
import PageHeader from './components/PageHeader.vue'
import StatusTag from './components/StatusTag.vue'
import StepFlow from './components/StepFlow.vue'
import StepItem from './components/StepItem.vue'
import InfoCard from './components/InfoCard.vue'
import RoadMap from './components/RoadMap.vue'
import RoadMapPhase from './components/RoadMapPhase.vue'
import DocNavCards from './components/DocNavCards.vue'
import FontSizeSwitcher from './components/FontSizeSwitcher.vue'
import ResizableSidebar from './components/ResizableSidebar.vue'
import ReadingProgress from './components/ReadingProgress.vue'
import { setupMermaid } from './mermaid-client'
import { setupDevFakeLag } from './dev-fake-lag'
import projectConfig from '../../../project.config.ts'
// CSS 顺序即覆盖优先级:custom.css(设计令牌/首页/阅读体验) → article-code.css(代码卡)
// → article-quote.css(引用卡)。同特异性规则靠后者胜出,勿倒置。
import './custom.css'
import './article-code.css'
import './article-quote.css'

// 首页设计对齐 TAMCPP/anatomy_gui:自定义 ImxHero(替换默认 VPHero)+ 证明条 + 社区卡
// + 截图轮播 + 新手引导横幅 + 自绘卡网格(默认 VPHomeFeatures 被 CSS 隐藏) + HomeRoadmap。
// Layout 用 defineComponent 包,以便在 setup() 里:
//  (1) 条件挂载 mermaid 客户端(useRouter/onMounted 必须在组件 setup 上下文调用);
//  (2) 据 projectConfig 条件拼装 Layout 插槽 —— 阅读体验三件套 / 截图轮播 / 路线图 / 社区卡均走配置开关。
// HomeArchDiagram / HomeShowcase 组件文件保留(可逆),但不再挂到首页。
const Layout = defineComponent({
  setup() {
    if (projectConfig.plugins.mermaid) {
      setupMermaid()
    }

    const slots: Record<string, () => VNodeChild> = {}

    // ── 首页 hero 之前:自定义 ImxHero(组件内关掉默认 VPHero)──
    slots['home-hero-before'] = () => h(ImxHero)

    // ── 首页 features 之前:截图轮播「先睹为快」+ 新手引导横幅 + 自绘卡网格 ──
    // 卡网格自绘版读 frontmatter.features(与被 CSS 隐藏的默认网格同源,SEO 无损),
    // features 为空时组件内 v-if 不渲染。
    const hasShots = !!(projectConfig.homeScreenshots && projectConfig.homeScreenshots.length)
    const hasBanner = !!projectConfig.homeBanner
    slots['home-features-before'] = () => [
      hasShots ? h(ScreenshotCarousel, { shots: projectConfig.homeScreenshots! }) : null,
      hasBanner ? h(HomeTipBanner, { config: projectConfig }) : null,
      h(HomeFeatureGrid),
    ]

    // ── 首页 hero 之后:证明条(紧贴 hero 下沿)+ 技术交流卡 ──
    slots['home-hero-after'] = () => [
      h(ProofStrip),
      ...(projectConfig.community
        ? [h(HomeCommunity, { community: projectConfig.community! })]
        : []),
    ]

    // ── 首页 features 之后:学习路线图(有数据才挂)──
    if (projectConfig.homeRoadmap && projectConfig.homeRoadmap.stages.length) {
      slots['home-features-after'] = () => h(HomeRoadmap, { roadmap: projectConfig.homeRoadmap! })
    }

    // ── layout-top:SPA 跳转两级反馈(常驻,与 readingUX 开关正交)
    //    + Mermaid 全屏放大镜(mermaid 开关;Teleport 模态,未打开时零渲染)
    //    + 阅读进度条(固定 3px)/ 侧栏拖拽手柄(readingUX 开关,运行时注入 DOM)──
    slots['layout-top'] = () => {
      const items: VNodeChild[] = [h(NavSpinner)]
      if (projectConfig.plugins.mermaid) items.push(h(MermaidLightbox))
      if (projectConfig.plugins.readingUX) items.push(h(ReadingProgress), h(ResizableSidebar))
      return items
    }

    // ── 字号切换器 A-/A+(nav-bar / nav-screen 两处,readingUX 开关)──
    if (projectConfig.plugins.readingUX) {
      slots['nav-bar-content-after'] = () => h(FontSizeSwitcher)
      slots['nav-screen-content-after'] = () => h(FontSizeSwitcher)
    }

    // ── 文档页底部:上下篇导航卡 ──
    slots['doc-after'] = () => h(DocNavCards)

    return () => h(DefaultTheme.Layout, null, slots)
  },
})

export default {
  extends: DefaultTheme,
  Layout,
  setup() {
    // dev-only 假卡顿开关(localStorage.fakeLag=N 毫秒),模拟弱网测 NavSpinner;
    // 生产构建被 import.meta.env.DEV 摇掉,零影响。
    setupDevFakeLag()
  },
  enhanceApp({ app }) {
    app.component('ChapterNav', ChapterNav)
    app.component('ChapterLink', ChapterLink)
    app.component('PageHeader', PageHeader)
    app.component('StatusTag', StatusTag)
    app.component('StepFlow', StepFlow)
    app.component('StepItem', StepItem)
    app.component('InfoCard', InfoCard)
    app.component('RoadMap', RoadMap)
    app.component('RoadMapPhase', RoadMapPhase)
  }
} satisfies Theme
