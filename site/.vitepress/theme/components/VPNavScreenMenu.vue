<script setup lang="ts">
// 覆盖 VitePress 内置 VPNavScreenMenu(见 config/index.ts 的 alias)。
//
// 与桌面端 VPNavBarMenu 覆盖同一动机:内置版 `'link' in item` 优先,「既有 link
// 又有 items」的分区导航项在手机端会退化成纯链接、丢掉二级目录。手机屏没有
// 悬停,不复刻桌面端「文字+箭头」的双区交互,而是交给内置手风琴
// VPNavScreenMenuGroup:组首插入一条「分区总览」链接,其后是该分区的子目录。
// 样式无需携带:内置版本组件无 scoped 样式,子项样式随 VPNavScreenMenuLink /
// VPNavScreenMenuGroup 自带,根节点的 .menu 槽位样式由 VPNavScreen 按根元素
// 继承(Vue scoped 规则),类名不变即全部生效。
import { useData } from 'vitepress'
import VPNavScreenMenuLink from 'vitepress/dist/client/theme-default/components/VPNavScreenMenuLink.vue'
import VPNavScreenMenuGroup from 'vitepress/dist/client/theme-default/components/VPNavScreenMenuGroup.vue'

const { theme } = useData()

// 手风琴组条目:分区总览放最前,保证「直达分区落地页」在手机端永远可达。
function splitGroupItems(item: any) {
  return [
    { text: `${item.text} · 分区总览`, link: item.link },
    ...item.items,
  ]
}
</script>

<template>
  <nav v-if="theme.nav" class="VPNavScreenMenu">
    <template v-for="(item, index) in theme.nav" :key="index">
      <VPNavScreenMenuGroup
        v-if="(item as any).link && (item as any).items"
        :text="(item as any).text"
        :items="splitGroupItems(item)"
      />
      <VPNavScreenMenuLink v-else-if="'link' in item" :item="item" />
      <component
        v-else-if="'component' in item"
        :is="item.component"
        v-bind="item.props"
        screen-menu
      />
      <VPNavScreenMenuGroup v-else :text="item.text || ''" :items="item.items" />
    </template>
  </nav>
</template>
