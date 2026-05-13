<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'
import type { ProjectConfig } from '../config/schema'

const { lang } = useData()

const props = defineProps<{
  config?: ProjectConfig
}>()

const bannerText = computed(() => {
  const cfg = props.config
  if (!cfg?.homeBanner) return ''
  return cfg.homeBanner[lang.value] || cfg.homeBanner[Object.keys(cfg.homeBanner)[0]] || ''
})

const showBanner = computed(() => !!bannerText.value)
</script>

<template>
  <div v-if="showBanner" class="home-tip-banner">
    <span class="home-tip-icon">
      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/>
        <path d="M9 18h6"/>
        <path d="M10 22h4"/>
      </svg>
    </span>
    <span class="home-tip-text" v-html="bannerText" />
  </div>
</template>

<style scoped>
.home-tip-banner {
  max-width: 1152px;
  margin: -16px auto 32px;
  padding: 16px 24px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  gap: 12px;
  background: linear-gradient(135deg, rgba(83, 162, 83, 0.12) 0%, rgba(83, 162, 83, 0.06) 100%);
  border: 2px solid var(--vp-tip-border, rgba(83, 162, 83, 0.3));
  color: var(--vp-tip-text, var(--vp-c-text-2));
  font-size: 16px;
  line-height: 1.6;
  font-weight: 500;
  box-shadow: 0 2px 8px rgba(83, 162, 83, 0.15);
}

.home-tip-icon {
  flex-shrink: 0;
  color: var(--vp-tip-accent, #53a253);
  display: flex;
  align-items: center;
}

.home-tip-text :deep(a) {
  color: #3b82f6;
  text-decoration: underline;
  text-underline-offset: 3px;
  font-weight: 700;
  transition: all 0.2s ease;
}

.home-tip-text :deep(a:hover) {
  color: #2563eb;
}
</style>
