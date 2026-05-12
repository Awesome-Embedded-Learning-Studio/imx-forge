<script setup lang="ts">
const props = withDefaults(defineProps<{
  type: 'done' | 'active' | 'planned' | 'experimental'
  text?: string
}>(), {
  text: undefined
})

const defaultLabels: Record<string, string> = {
  done: '已完成',
  active: '进行中',
  planned: '规划中',
  experimental: '实验性'
}

const label = props.text ?? defaultLabels[props.type]
</script>

<template>
  <span class="status-tag" :class="[`status-tag--${type}`]">
    {{ label }}
  </span>
</template>

<style scoped>
.status-tag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.6;
  white-space: nowrap;
  vertical-align: middle;
}

.status-tag--done {
  background-color: rgba(83, 162, 83, 0.12);
  color: #53a253;
  border: 1px solid rgba(83, 162, 83, 0.25);
}

.status-tag--active {
  background-color: rgba(81, 107, 232, 0.12);
  color: var(--vp-c-brand-1);
  border: 1px solid rgba(81, 107, 232, 0.25);
}

.status-tag--planned {
  background-color: rgba(128, 128, 128, 0.1);
  color: var(--vp-c-text-2);
  border: 1px solid rgba(128, 128, 128, 0.2);
}

.status-tag--experimental {
  background-color: rgba(177, 127, 232, 0.12);
  color: #b17fe8;
  border: 1px solid rgba(177, 127, 232, 0.25);
}

.dark .status-tag--done {
  background-color: rgba(83, 162, 83, 0.15);
  border-color: rgba(83, 162, 83, 0.3);
}

.dark .status-tag--active {
  background-color: rgba(81, 107, 232, 0.15);
  border-color: rgba(81, 107, 232, 0.3);
}

.dark .status-tag--planned {
  background-color: rgba(128, 128, 128, 0.12);
  border-color: rgba(128, 128, 128, 0.25);
}

.dark .status-tag--experimental {
  background-color: rgba(177, 127, 232, 0.15);
  border-color: rgba(177, 127, 232, 0.3);
}
</style>
