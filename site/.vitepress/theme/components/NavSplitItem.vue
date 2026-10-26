<script setup lang="ts">
// 顶栏「可点击 + 可展开」的复合导航项。
//
// VitePress 内置的 VPNavBarMenu 用 `'link' in item` 做判定:同一项既有 link 又有
// items 时,只渲染链接、丢掉二级菜单。这里把两者拆成两个可点击区域 ——
// 文字是链接(直达分区总览),右侧小箭头负责展开二级菜单(悬停即开)。
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import VPNavBarMenuLink from 'vitepress/dist/client/theme-default/components/VPNavBarMenuLink.vue'
import VPMenu from 'vitepress/dist/client/theme-default/components/VPMenu.vue'

const props = defineProps<{
  item: {
    text: string
    link: string
    items: any[]
    activeMatch?: string
  }
}>()

// 文字部分交给内置链接组件渲染,高亮/activeMatch/外链 target 等行为与之完全一致。
const linkItem = computed(() => ({
  text: props.item.text,
  link: props.item.link,
  activeMatch: props.item.activeMatch,
}))

const open = ref(false)
const root = ref<HTMLElement | null>(null)

function closeOnOutside(e: MouseEvent) {
  if (open.value && root.value && !root.value.contains(e.target as Node)) {
    open.value = false
  }
}

function closeOnEscape(e: KeyboardEvent) {
  if (e.key === 'Escape') open.value = false
}

onMounted(() => {
  document.addEventListener('click', closeOnOutside)
  document.addEventListener('keydown', closeOnEscape)
})

onBeforeUnmount(() => {
  document.removeEventListener('click', closeOnOutside)
  document.removeEventListener('keydown', closeOnEscape)
})
</script>

<template>
  <div
    ref="root"
    class="VPNavBarMenuSplit"
    @mouseenter="open = true"
    @mouseleave="open = false"
  >
    <VPNavBarMenuLink :item="linkItem" />

    <button
      type="button"
      class="VPNavBarMenuSplit-caret"
      aria-haspopup="true"
      :aria-expanded="open"
      :aria-label="`${item.text} 子目录`"
      @click.stop="open = !open"
    >
      <span class="vpi-chevron-down" />
    </button>

    <div class="VPNavBarMenuSplit-menu" :class="{ open }">
      <VPMenu :items="item.items" />
    </div>
  </div>
</template>

<style scoped>
.VPNavBarMenuSplit {
  position: relative;
  display: flex;
  align-items: center;
}

/* 收紧文字与小箭头之间的间距,同时保留右侧 12px 与相邻导航项的呼吸感 */
.VPNavBarMenuSplit :deep(.VPNavBarMenuLink) {
  padding-right: 2px;
}

.VPNavBarMenuSplit-caret {
  display: flex;
  align-items: center;
  height: var(--vp-nav-height);
  padding: 0 12px 0 4px;
  font-size: 14px;
  color: var(--vp-c-text-2);
  transition: color 0.25s;
}

.VPNavBarMenuSplit:hover .VPNavBarMenuSplit-caret,
.VPNavBarMenuSplit-caret[aria-expanded='true'] {
  color: var(--vp-c-brand-1);
}

.VPNavBarMenuSplit-menu {
  position: absolute;
  top: calc(var(--vp-nav-height) / 2 + 20px);
  right: 0;
  opacity: 0;
  visibility: hidden;
  transition: opacity 0.25s, visibility 0.25s;
}

.VPNavBarMenuSplit-menu.open {
  opacity: 1;
  visibility: visible;
}
</style>
