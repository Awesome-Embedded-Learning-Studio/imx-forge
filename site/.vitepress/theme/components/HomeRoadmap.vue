<script setup lang="ts">
import { withBase } from 'vitepress'
import type { HomeRoadmapConfig, RoadmapStatus } from '../../config/schema'

// 首页「学习路线图」:阶段卡网格 + 状态徽标 + 章数。
// 数据来自 project.config.ts 的 homeRoadmap(由 roadmap prop 注入),纯 HTML/CSS,零运行时依赖。
// 移植自 C-Journey 的纯 HTML 版(AMCPP 原版用 mermaid,这里不引入 mermaid 依赖)。

defineProps<{ roadmap: HomeRoadmapConfig }>()

const statusMeta: Record<RoadmapStatus, { mark: string; label: string; cls: string }> = {
  done:      { mark: '✓', label: '已完成',   cls: 'rm-chip--done' },
  reviewing: { mark: '✦', label: '撰写中', cls: 'rm-chip--doing' },
  planned:   { mark: '◇', label: '规划中',   cls: 'rm-chip--todo' },
}
</script>

<template>
  <section id="roadmap" class="home-roadmap">
    <div class="home-roadmap__card">
      <h2 class="home-roadmap__title">{{ roadmap.title ?? '📍 学习路线图' }}</h2>

      <div class="home-roadmap__legend">
        <span
          v-for="(m, k) in statusMeta"
          :key="k"
          class="rm-chip"
          :class="m.cls"
        >
          <span class="rm-chip__mark">{{ m.mark }}</span>{{ m.label }}
        </span>
      </div>

      <div class="home-roadmap__stages">
        <a
          v-for="s in roadmap.stages"
          :key="s.dir || s.no"
          class="rm-stage"
          :class="`rm-stage--${s.status}`"
          :href="withBase(s.link)"
        >
          <div class="rm-stage__head">
            <span class="rm-stage__no">{{ s.no }}</span>
            <span
              class="rm-stage__badge"
              :class="statusMeta[s.status].cls"
            >
              <span class="rm-stage__badge-mark">{{ statusMeta[s.status].mark }}</span>
              {{ statusMeta[s.status].label }}
            </span>
          </div>
          <h3 class="rm-stage__name">{{ s.name }}</h3>
          <p class="rm-stage__desc">{{ s.desc }}</p>
          <span v-if="s.chapters != null" class="rm-stage__meta">{{ s.chapters }} 章</span>
        </a>
      </div>

      <p v-if="roadmap.next" class="home-roadmap__next">{{ roadmap.next }}</p>
    </div>
  </section>
</template>

<style scoped>
.home-roadmap {
  max-width: 1152px;
  margin: 40px auto 56px;
  padding: 0 24px;
  scroll-margin-top: 80px;
  animation: roadmap-fade-up 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94) both;
}

.home-roadmap__card {
  padding: 28px 32px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 14px;
  background-color: var(--vp-c-bg);
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.04),
    0 1px 2px rgba(0, 0, 0, 0.06);
  text-align: center;
}

.dark .home-roadmap__card {
  background-color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-border);
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.2),
    0 1px 2px rgba(0, 0, 0, 0.15);
}

.home-roadmap__title {
  margin: 0 0 18px;
  font-size: 20px;
  font-weight: 700;
  line-height: 1.4;
  color: var(--vp-c-text-1);
  border-top: 0;
  padding-top: 0;
}

/* ── Legend ─────────────────────────────────── */
.home-roadmap__legend {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
  margin-bottom: 24px;
}

.rm-chip {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  border-radius: 999px;
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg-soft);
  font-size: 14px;
  font-weight: 500;
  line-height: 1;
  color: var(--vp-c-text-1);
  white-space: nowrap;
}

.rm-chip__mark {
  font-size: 14px;
  font-weight: 700;
}

.rm-chip--done .rm-chip__mark,
.rm-chip--done .rm-stage__badge-mark { color: var(--vp-c-green-1); }
.rm-chip--doing .rm-chip__mark,
.rm-chip--doing .rm-stage__badge-mark { color: #ffc107; }
.rm-chip--todo .rm-chip__mark,
.rm-chip--todo .rm-stage__badge-mark { color: var(--vp-c-text-3); }

/* ── Stage cards ────────────────────────────── */
.home-roadmap__stages {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 14px;
  margin-bottom: 24px;
  text-align: left;
}

.rm-stage {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 18px 20px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background: var(--vp-c-bg);
  text-decoration: none !important;
  color: var(--vp-c-text-1) !important;
  transition: border-color 0.35s ease,
              box-shadow 0.35s ease,
              transform 0.35s ease;
}

.rm-stage:hover {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.1),
              0 4px 8px rgba(0, 0, 0, 0.06);
  transform: translateY(-3px);
}

.rm-stage__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.rm-stage__no {
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.06em;
  color: var(--vp-c-text-3);
  text-transform: uppercase;
}

.rm-stage__badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 3px 10px;
  border-radius: 999px;
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg-soft);
  font-size: 11.5px;
  font-weight: 600;
  line-height: 1;
  color: var(--vp-c-text-2);
}

.rm-stage__name {
  margin: 0;
  font-size: 17px;
  font-weight: 700;
  line-height: 1.4;
  color: var(--vp-c-text-1);
}

.rm-stage:hover .rm-stage__name {
  color: var(--vp-c-brand-1);
}

.rm-stage__desc {
  margin: 0;
  font-size: 13.5px;
  line-height: 1.7;
  color: var(--vp-c-text-2);
  flex: 1;
}

.rm-stage__meta {
  align-self: flex-start;
  font-size: 12px;
  font-weight: 600;
  color: var(--vp-c-brand-1);
  font-variant-numeric: tabular-nums;
}

.home-roadmap__next {
  margin: 0 auto;
  max-width: 720px;
  font-size: 14px;
  line-height: 1.7;
  color: var(--vp-c-text-2);
}

@keyframes roadmap-fade-up {
  from { opacity: 0; transform: translateY(18px); }
  to   { opacity: 1; transform: translateY(0); }
}

@media (prefers-reduced-motion: reduce) {
  .home-roadmap { animation: none !important; }
  .rm-stage { transition: none; }
}

@media (max-width: 639px) {
  .home-roadmap { padding: 0 16px; margin: 28px auto 36px; }
  .home-roadmap__card { padding: 22px 18px; }
  .home-roadmap__title { font-size: 18px; }
  .home-roadmap__stages { grid-template-columns: 1fr; }
  .rm-chip { font-size: 13px; padding: 7px 13px; }
  .rm-stage__name { font-size: 16px; }
}
</style>
