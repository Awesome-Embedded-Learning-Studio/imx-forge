import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import type { Theme } from 'vitepress'
import HomeTipBanner from './components/HomeTipBanner.vue'
import HomeArchDiagram from './components/HomeArchDiagram.vue'
import HomeShowcase from './components/HomeShowcase.vue'
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
import projectConfig from '../../../project.config.ts'
import './custom.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'home-features-before': () => h(HomeTipBanner, { config: projectConfig }),
      'home-features-after': () => [h(HomeShowcase), h(HomeArchDiagram)],
      'doc-after': () => h(DocNavCards)
    })
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
