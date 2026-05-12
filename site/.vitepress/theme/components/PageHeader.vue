<script setup lang="ts">
defineProps<{
  icon: string
  title: string
  description: string
}>()
</script>

<template>
  <div class="page-header">
    <span class="page-header-icon">{{ icon }}</span>
    <div class="page-header-body">
      <h1 class="page-header-title">{{ title }}</h1>
      <p class="page-header-desc">{{ description }}</p>
    </div>
  </div>
</template>

<style scoped>
.page-header {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 28px 32px;
  margin: -12px 0 28px;
  border-radius: 14px;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-soft) 0%,
    transparent 50%,
    var(--vp-c-indigo-soft) 100%
  );
  border: 1px solid var(--vp-c-divider);
  position: relative;
  overflow: hidden;
}

.page-header::before {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-1) 0%,
    var(--vp-c-indigo-1) 50%,
    var(--vp-c-purple-1) 100%
  );
  opacity: 0.06;
  pointer-events: none;
}

.page-header-icon {
  flex-shrink: 0;
  font-size: 40px;
  line-height: 1;
  width: 64px;
  height: 64px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: var(--vp-c-bg);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  position: relative;
  z-index: 1;
}

.page-header-body {
  min-width: 0;
  position: relative;
  z-index: 1;
}

.page-header-title {
  margin: 0;
  padding: 0;
  font-size: 22px;
  font-weight: 700;
  line-height: 1.3;
  color: var(--vp-c-text-1);
  border: none;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-1) 0%,
    var(--vp-c-indigo-1) 50%,
    var(--vp-c-purple-1) 100%
  );
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.page-header-desc {
  margin: 4px 0 0;
  font-size: 14px;
  line-height: 1.6;
  color: var(--vp-c-text-2);
}

.dark .page-header {
  border-color: var(--vp-c-border);
}

.dark .page-header-icon {
  background: var(--vp-c-bg-elv);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
}

.dark .page-header::before {
  opacity: 0.1;
}

@media (max-width: 639px) {
  .page-header {
    padding: 20px 18px;
    gap: 14px;
  }

  .page-header-icon {
    width: 48px;
    height: 48px;
    font-size: 28px;
    border-radius: 10px;
  }

  .page-header-title {
    font-size: 18px;
  }

  .page-header-desc {
    font-size: 13px;
  }
}
</style>
