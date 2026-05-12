<script setup lang="ts">
defineProps<{
  icon: string
  title: string
  description?: string
  time?: string
}>()
</script>

<template>
  <div class="step-item">
    <div class="step-item-node">
      <span class="step-item-icon">{{ icon }}</span>
      <span class="step-item-connector" />
    </div>
    <div class="step-item-body">
      <span class="step-item-title">{{ title }}</span>
      <span v-if="description" class="step-item-desc">{{ description }}</span>
      <span v-if="time" class="step-item-time">{{ time }}</span>
    </div>
  </div>
</template>

<style scoped>
.step-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  flex: 1;
  min-width: 100px;
  text-align: center;
}

.step-item-node {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
}

.step-item-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  font-size: 22px;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-soft) 0%,
    var(--vp-c-indigo-soft) 100%
  );
  border: 2px solid var(--vp-c-divider);
  z-index: 1;
  transition: border-color 0.35s ease, transform 0.35s ease;
}

.step-item:hover .step-item-icon {
  border-color: var(--vp-c-brand-1);
  transform: scale(1.08);
}

.step-item-connector {
  position: absolute;
  top: 50%;
  left: calc(50% + 24px);
  width: calc(100% - 48px);
  height: 2px;
  background: repeating-linear-gradient(
    90deg,
    var(--vp-c-divider) 0px,
    var(--vp-c-divider) 6px,
    transparent 6px,
    transparent 12px
  );
  z-index: 0;
}

.step-item:last-child .step-item-connector {
  display: none;
}

.step-item-body {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  margin-top: 10px;
}

.step-item-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--vp-c-text-1);
  line-height: 1.4;
}

.step-item-desc {
  font-size: 12px;
  color: var(--vp-c-text-2);
  line-height: 1.4;
}

.step-item-time {
  font-size: 11px;
  font-weight: 600;
  color: var(--vp-c-brand-1);
  background: var(--vp-c-brand-soft);
  padding: 1px 8px;
  border-radius: 10px;
  margin-top: 2px;
}

.dark .step-item-icon {
  border-color: var(--vp-c-border);
  background: linear-gradient(
    135deg,
    rgba(81, 107, 232, 0.2) 0%,
    rgba(177, 127, 232, 0.2) 100%
  );
}

.dark .step-item:hover .step-item-icon {
  border-color: var(--vp-c-brand-1);
}

.dark .step-item-connector {
  background: repeating-linear-gradient(
    90deg,
    var(--vp-c-border) 0px,
    var(--vp-c-border) 6px,
    transparent 6px,
    transparent 12px
  );
}

@media (max-width: 639px) {
  .step-item {
    flex-direction: row;
    text-align: left;
    min-width: unset;
    padding: 8px 0;
    gap: 14px;
  }

  .step-item-node {
    width: auto;
    flex-shrink: 0;
  }

  .step-item-connector {
    display: none;
  }

  .step-item-body {
    align-items: flex-start;
    margin-top: 0;
  }

  .step-item-icon {
    width: 40px;
    height: 40px;
    font-size: 18px;
  }
}
</style>
