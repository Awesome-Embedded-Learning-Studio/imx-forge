<script setup lang="ts">
defineProps<{
  icon: string
  title: string
  href?: string
}>()
</script>

<template>
  <component
    :is="href ? 'a' : 'div'"
    :href="href"
    class="info-card"
    :class="{ 'info-card--link': !!href }"
  >
    <span class="info-card-icon">{{ icon }}</span>
    <div class="info-card-body">
      <span class="info-card-title">{{ title }}</span>
      <span class="info-card-content">
        <slot />
      </span>
    </div>
  </component>
</template>

<style scoped>
.info-card {
  display: flex;
  align-items: flex-start;
  gap: 14px;
  padding: 20px 22px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background-color: var(--vp-c-bg);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04),
              0 1px 2px rgba(0, 0, 0, 0.06);
  transition: border-color 0.35s ease,
              box-shadow 0.35s ease,
              transform 0.35s ease;
}

.info-card--link {
  text-decoration: none !important;
  color: inherit;
  cursor: pointer;
}

.info-card:hover {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.1),
              0 4px 8px rgba(0, 0, 0, 0.06);
  transform: translateY(-3px);
}

.info-card-icon {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 42px;
  height: 42px;
  border-radius: 10px;
  font-size: 20px;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-soft) 0%,
    var(--vp-c-indigo-soft) 100%
  );
  transition: transform 0.35s ease;
}

.info-card:hover .info-card-icon {
  transform: scale(1.08);
}

.info-card-body {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.info-card-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--vp-c-text-1);
  line-height: 1.4;
  transition: color 0.35s ease;
}

.info-card:hover .info-card-title {
  color: var(--vp-c-brand-1);
}

.info-card-content {
  font-size: 13px;
  line-height: 1.6;
  color: var(--vp-c-text-2);
}

.info-card-content :deep(p) {
  margin: 0;
}

.info-card-content :deep(code) {
  font-size: 12px;
}

.dark .info-card {
  background-color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-border);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2),
              0 1px 2px rgba(0, 0, 0, 0.15);
}

.dark .info-card:hover {
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.3),
              0 4px 8px rgba(0, 0, 0, 0.2);
}

@media (max-width: 639px) {
  .info-card {
    padding: 16px 16px;
    gap: 12px;
  }

  .info-card-icon {
    width: 36px;
    height: 36px;
    font-size: 17px;
  }

  .info-card-title {
    font-size: 14px;
  }

  .info-card-content {
    font-size: 12.5px;
  }
}
</style>
