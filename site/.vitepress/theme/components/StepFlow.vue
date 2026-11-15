<script setup lang="ts">
withDefaults(defineProps<{
  direction?: 'horizontal' | 'vertical'
}>(), {
  direction: 'horizontal'
})
</script>

<template>
  <div class="step-flow" :class="[`step-flow--${direction}`]">
    <slot />
  </div>
</template>

<style scoped>
.step-flow {
  display: flex;
  gap: 0;
  margin: 1.5em 0;
}

.step-flow--horizontal {
  flex-direction: row;
  align-items: flex-start;
  overflow-x: auto;
  /* 圆形图标 hover 时 scale(1.08),向上下各溢出约 2px;overflow-x 一旦非 visible,
     overflow-y 会被一并强制成裁剪,不留余量放大冒出的圆边就会被削平。
     上 3px 供给放大溢出,下 7px = 滚动条余量 4px + 溢出 3px。 */
  padding: 3px 0 7px;
}

.step-flow--vertical {
  flex-direction: column;
  align-items: stretch;
}

@media (max-width: 639px) {
  .step-flow--horizontal {
    flex-direction: column;
  }
}
</style>
