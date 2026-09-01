import DefaultTheme from 'vitepress/theme'
import { defineComponent, h, type VNodeChild } from 'vue'
import type { Theme } from 'vitepress'
import ImxHero from './components/ImxHero.vue'
import ScreenshotCarousel from './components/ScreenshotCarousel.vue'
import HomeRoadmap from './components/HomeRoadmap.vue'
import HomeCommunity from './components/HomeCommunity.vue'
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
import projectConfig from '../../../project.config.ts'
import './custom.css'

// 首页设计对齐 anatomy_gui:自定义 ImxHero(替换默认 VPHero)+ 社区卡 + 截图轮播 + features + HomeRoadmap。
// Layout 用 defineComponent 包,以便在 setup() 里:
//  (1) 条件挂载 mermaid 客户端(useRouter/onMounted 必须在组件 setup 上下文调用);
//  (2) 据 projectConfig 条件拼装 Layout 插槽 —— 阅读体验三件套 / 截图轮播 / 路线图 / 社区卡均走配置开关。
// HomeTipBanner / HomeArchDiagram / HomeShowcase 组件文件保留(可逆),但不再挂到首页。
const Layout = defineComponent({
  setup() {
    if (projectConfig.plugins.mermaid) {
      setupMermaid()
    }

    const slots: Record<string, () => VNodeChild> = {}

    // ── 首页 hero 之前:自定义 ImxHero(组件内关掉默认 VPHero)──
    slots['home-hero-before'] = () => h(ImxHero)

    // ── 首页 features 之前:截图轮播「先睹为快」(有数据才挂)──
    const hasShots = !!(projectConfig.homeScreenshots && projectConfig.homeScreenshots.length)
    if (hasShots) {
      slots['home-features-before'] = () =>
        h(ScreenshotCarousel, { shots: projectConfig.homeScreenshots! })
    }

    // ── 首页 hero 之后:技术交流卡(有数据才挂,紧跟 hero 首屏可见)──
    if (projectConfig.community) {
      slots['home-hero-after'] = () => h(HomeCommunity, { community: projectConfig.community! })
    }

    // ── 首页 features 之后:学习路线图(有数据才挂)──
    if (projectConfig.homeRoadmap && projectConfig.homeRoadmap.stages.length) {
      slots['home-features-after'] = () => h(HomeRoadmap, { roadmap: projectConfig.homeRoadmap! })
    }

    // ── 阅读体验三件套(readingUX 总开关)──
    // layout-top:阅读进度条(固定 3px)+ 侧栏拖拽手柄(运行时注入 DOM,无视觉模板)
    // nav-bar-content-after / nav-screen-content-after:字号切换器 A-/A+
    if (projectConfig.plugins.readingUX) {
      slots['layout-top'] = () => [h(ReadingProgress), h(ResizableSidebar)]
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
