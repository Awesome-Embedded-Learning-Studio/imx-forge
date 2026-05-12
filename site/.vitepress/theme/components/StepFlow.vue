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
  padding-bottom: 4px;
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
