<script setup lang="ts">
import { useData } from 'vitepress'
import { computed } from 'vue'

const { page, theme, site } = useData()
const base = site.value.base // e.g. '/imx-forge/'

interface FlatPage {
  text: string
  link: string
}

function flattenSidebar(items: any[], result: FlatPage[] = []): FlatPage[] {
  for (const item of items) {
    if (item.link) {
      result.push({ text: item.text, link: item.link })
    }
    if (item.items) {
      flattenSidebar(item.items, result)
    }
  }
  return result
}

function normalize(link: string): string {
  return link.replace(/\.md$/, '').replace(/\/index$/, '/').replace(/\/$/, '')
}

const navInfo = computed(() => {
  const sidebar = theme.value.sidebar
  if (!sidebar) return null

  let allPages: FlatPage[] = []
  for (const key of Object.keys(sidebar)) {
    const group = sidebar[key]
    if (Array.isArray(group)) {
      flattenSidebar(group, allPages)
    }
  }

  if (allPages.length === 0) return null

  // Try multiple path formats to find current page
  const relPath = page.value.relativePath // e.g. "tutorial/uboot/07_network_porting.md"
  const candidates = [
    normalize('/' + relPath),              // /tutorial/uboot/07_network_porting
    normalize('/' + relPath.replace(/\.md$/, '') + '/'), // for index pages
  ]

  let idx = -1
  for (const candidate of candidates) {
    idx = allPages.findIndex(p => normalize(p.link) === candidate)
    if (idx >= 0) break
  }

  if (idx < 0) {
    // Fallback: try matching the end of the path
    const endPath = relPath.replace(/\.md$/, '').replace(/\/index$/, '')
    idx = allPages.findIndex(p => normalize(p.link).endsWith(endPath))
  }

  if (idx < 0) return null

  const prefixLink = (p: FlatPage) => ({
    text: p.text,
    link: (base + p.link.replace(/^\//, '')).replace(/\/\//g, '/')
  })

  return {
    prev: idx > 0 ? prefixLink(allPages[idx - 1]) : null,
    next: idx < allPages.length - 1 ? prefixLink(allPages[idx + 1]) : null
  }
})
</script>

<template>
  <div v-if="navInfo && (navInfo.prev || navInfo.next)" class="doc-nav-cards">
    <a v-if="navInfo.prev" :href="navInfo.prev.link" class="doc-nav-card doc-nav-card--prev">
      <span class="doc-nav-card-label">← 上一章</span>
      <span class="doc-nav-card-title">{{ navInfo.prev.text }}</span>
    </a>
    <span v-else class="doc-nav-card doc-nav-card--placeholder" />
    <a v-if="navInfo.next" :href="navInfo.next.link" class="doc-nav-card doc-nav-card--next">
      <span class="doc-nav-card-label">下一章 →</span>
      <span class="doc-nav-card-title">{{ navInfo.next.text }}</span>
    </a>
  </div>
</template>

<style scoped>
.doc-nav-cards {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-top: 2.5em;
  padding-top: 1.5em;
  border-top: 1px dashed var(--vp-c-divider);
}

.doc-nav-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px 18px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background-color: var(--vp-c-bg);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04),
              0 1px 2px rgba(0, 0, 0, 0.06);
  text-decoration: none !important;
  color: inherit;
  transition: border-color 0.35s ease,
              box-shadow 0.35s ease,
              transform 0.35s ease;
}

.doc-nav-card:hover {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.1),
              0 4px 8px rgba(0, 0, 0, 0.06);
  transform: translateY(-2px);
}

.doc-nav-card--next {
  text-align: right;
}

.doc-nav-card--placeholder {
  visibility: hidden;
}

.doc-nav-card-label {
  font-size: 12px;
  font-weight: 500;
  color: var(--vp-c-brand-1);
  line-height: 1.4;
}

.doc-nav-card-title {
  font-size: 14px;
  font-weight: 500;
  color: var(--vp-c-text-1);
  line-height: 1.5;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  transition: color 0.35s ease;
}

.doc-nav-card:hover .doc-nav-card-title {
  color: var(--vp-c-brand-1);
}

.dark .doc-nav-card {
  background-color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-border);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2),
              0 1px 2px rgba(0, 0, 0, 0.15);
}

.dark .doc-nav-card:hover {
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.3),
              0 4px 8px rgba(0, 0, 0, 0.2);
}

@media (max-width: 639px) {
  .doc-nav-cards {
    grid-template-columns: 1fr;
  }

  .doc-nav-card--next {
    text-align: left;
  }

  .doc-nav-card--placeholder {
    display: none;
  }
}
</style>
