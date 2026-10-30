<script setup lang="ts">
// 覆盖 VitePress 内置 VPNavBarMenu(见 config/index.ts 的 alias)。
//
// 与内置版唯一差别:支持「同时有 link 与 items」的导航项 —— 内置版优先匹配
// `'link' in item`,会把 items 丢掉;这里改成交给 NavSplitItem,让文字可跳转、
// 箭头可展开二级菜单。其余分支保持原样。
import { useData } from 'vitepress'
import VPNavBarMenuLink from 'vitepress/dist/client/theme-default/components/VPNavBarMenuLink.vue'
import VPNavBarMenuGroup from 'vitepress/dist/client/theme-default/components/VPNavBarMenuGroup.vue'
import NavSplitItem from './NavSplitItem.vue'

const { theme } = useData()
</script>

<template>
  <nav
    v-if="theme.nav"
    aria-labelledby="main-nav-aria-label"
    class="VPNavBarMenu"
  >
    <span id="main-nav-aria-label" class="visually-hidden">
      Main Navigation
    </span>
    <template v-for="(item, index) in theme.nav" :key="index">
      <NavSplitItem
        v-if="(item as any).link && (item as any).items"
        :item="item as any"
      />
      <VPNavBarMenuLink v-else-if="'link' in item" :item="item" />
      <component
        v-else-if="'component' in item"
        :is="item.component"
        v-bind="item.props"
      />
      <VPNavBarMenuGroup v-else :item="item" />
    </template>
  </nav>
</template>

<style scoped>
.VPNavBarMenu {
  display: none;
}

@media (min-width: 768px) {
  .VPNavBarMenu {
    display: flex;
  }
}
</style>
