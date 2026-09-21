<script setup lang="ts">
import { inject, computed, unref, type Ref } from 'vue'

const props = withDefaults(defineProps<{
  num?: string | number
  href: string
  desc?: string
  variant?: 'main' | 'sub'
}>(), {
  variant: undefined
})

// 源文件里 <ChapterLink href="xxx.md"> 普遍带了 .md 后缀,浏览器跳过去会被 dev server
// 当 text/markdown 原文返回(不渲染,看起来就是 404)。统一在这里剥掉结尾的 .md(保留
// #hash),让链接落到真正的页面路由;不带 .md 的 href 不受影响。
// (与姊妹项目不同,这里选择静默修复而不是 dev 期 throw:存量 90+ 个文档文件、170+
// 处 .md 后缀写法,throw 会把整站打红。)
const resolvedHref = computed(() => props.href.replace(/\.md(?=#|$)/, ''))

// 外层 ChapterNav provide 的是 ref(变体变化要联动子卡);兼容历史裸字符串注入。
const navVariant = inject<Ref<'main' | 'sub'> | 'main' | 'sub'>('chapterNavVariant', 'main')
const effectiveVariant = computed(() => props.variant ?? unref(navVariant))

// 徽章两位数补零只对数字编号有意义:非数字 num(如教程主页的「★」)原样显示,
// 老逻辑无脑 padStart 会把它补成「0★」。
const badgeText = computed(() => {
  const raw = String(props.num)
  return /^\d+$/.test(raw) ? raw.padStart(2, '0') : raw
})
</script>

<template>
  <a :href="resolvedHref" class="chapter-link" :class="[`chapter-link--${effectiveVariant}`]">
    <span v-if="effectiveVariant === 'main' && num !== undefined" class="chapter-badge">
      {{ badgeText }}
    </span>
    <span v-else-if="effectiveVariant === 'sub'" class="chapter-node" aria-hidden="true">
      <span v-if="num !== undefined">{{ badgeText }}</span>
      <span v-else class="chapter-node-auto" />
    </span>
    <span class="chapter-body">
      <span v-if="effectiveVariant === 'sub'" class="chapter-waymark" aria-hidden="true">
        <span class="chapter-start">起点</span>
        <span class="chapter-finish">终点</span>
      </span>
      <span class="chapter-title">
        <slot />
      </span>
      <span v-if="desc" class="chapter-desc">{{ desc }}</span>
    </span>
    <span class="chapter-arrow" aria-hidden="true">→</span>
  </a>
</template>

<style scoped>
.chapter-link {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 18px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background-color: var(--vp-c-bg);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04),
              0 1px 2px rgba(0, 0, 0, 0.06);
  text-decoration: none !important;
  color: var(--vp-c-text-1);
  transition: border-color 0.35s ease,
              box-shadow 0.35s ease,
              transform 0.35s ease;
}

.chapter-link:hover {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.1),
              0 4px 8px rgba(0, 0, 0, 0.06);
  transform: translateY(-3px);
}

/* ── Badge(main 变体) ─────────────────────── */

.chapter-badge {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 36px;
  height: 36px;
  padding: 0 6px;
  border-radius: 8px;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-soft) 0%,
    var(--vp-c-indigo-soft) 100%
  );
  color: var(--vp-c-brand-1);
  font-size: 13px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  letter-spacing: 0.02em;
  transition: background 0.35s ease, color 0.35s ease, transform 0.35s ease;
}

.chapter-link:hover .chapter-badge {
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-1) 0%,
    var(--vp-c-indigo-1) 100%
  );
  color: var(--vp-c-white);
  transform: scale(1.06);
}

/* ── 标题 + 描述 ──────────────────────────── */

.chapter-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.chapter-title {
  font-size: 14px;
  font-weight: 500;
  line-height: 1.5;
  transition: color 0.35s ease;
}

.chapter-desc {
  font-size: 12.5px;
  font-weight: 400;
  line-height: 1.45;
  color: var(--vp-c-text-3);
}

.chapter-link:hover .chapter-title {
  color: var(--vp-c-brand-1);
}

.chapter-link:hover .chapter-desc {
  color: var(--vp-c-text-2);
}

/* ── Arrow ────────────────────────────────── */

.chapter-arrow {
  flex-shrink: 0;
  font-size: 16px;
  color: var(--vp-c-text-3);
  transition: transform 0.35s ease, color 0.35s ease;
}

.chapter-link:hover .chapter-arrow {
  transform: translateX(4px);
  color: var(--vp-c-brand-1);
}

/* ── Dark Mode ────────────────────────────── */

.dark .chapter-link {
  background-color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-border);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2),
              0 1px 2px rgba(0, 0, 0, 0.15);
}

.dark .chapter-link:hover {
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.3),
              0 4px 8px rgba(0, 0, 0, 0.2);
}

/* ── Responsive ──────────────────────────── */

@media (max-width: 767px) {
  .chapter-link {
    padding: 14px 14px;
    gap: 10px;
  }

  .chapter-badge {
    min-width: 32px;
    height: 32px;
    font-size: 12px;
  }

  .chapter-title {
    font-size: 13.5px;
  }
}

/* ── Sub:小路两侧的站点 ───────────────────── */

.chapter-link.chapter-link--sub {
  position: relative;
  align-self: flex-start;
  width: 86%;
  min-height: 64px;
  gap: 16px;
  padding: 0;
  border: 0;
  background: none;
  box-shadow: none;
  transform: none;
  counter-increment: chapter-stop;
}

.chapter-link--sub:nth-child(even) {
  align-self: flex-end;
  flex-direction: row-reverse;
  text-align: right;
}

.chapter-link.chapter-link--sub:is(:hover, :focus-visible) {
  box-shadow: none;
}

.chapter-link--sub .chapter-body {
  flex: 0 1 auto;
  gap: 4px;
  padding: 4px 0;
  border-radius: 6px;
  background: var(--chapter-map-bg, var(--vp-c-bg));
  overflow-wrap: anywhere;
}

.chapter-link--sub .chapter-title {
  color: var(--vp-c-text-1);
  font-size: 15px;
  font-weight: 600;
}

.chapter-link--sub .chapter-desc {
  color: var(--vp-c-text-2);
  font-size: 13px;
  line-height: 1.6;
}

.chapter-link--sub .chapter-arrow {
  opacity: 0;
  font-size: 16px;
  transition: opacity 0.2s ease;
}

.chapter-link--sub:is(:hover, :focus-visible) .chapter-arrow {
  opacity: 1;
  transform: none;
}

.chapter-link:focus-visible {
  outline: 2px solid var(--vp-c-brand-1);
  outline-offset: 6px;
}

.chapter-node {
  flex: 0 0 46px;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 46px;
  height: 46px;
  border: 2px solid var(--vp-c-brand-1);
  border-radius: 50%;
  background: var(--chapter-map-bg, var(--vp-c-bg));
  color: var(--vp-c-brand-1);
  box-shadow: 0 0 0 6px var(--chapter-map-bg, var(--vp-c-bg));
  font-size: 13px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  transition: background 0.2s ease, color 0.2s ease;
}

.chapter-node-auto::before {
  content: counter(chapter-stop, decimal-leading-zero);
}

/* 首站节点填充/hover 填充。首末站专属装饰(首站填充、末站双圈、起点/终点站牌)
   不在这里写:它们必须以 ChapterNav 的 .chapter-links 容器为锚才不会误伤
   RoadMapPhase 等其它容器里的 sub 卡片,相关规则见 ChapterNav.vue(:deep)。 */
.chapter-link--sub:is(:hover, :focus-visible) .chapter-node {
  background: var(--vp-c-brand-1);
  color: var(--vp-c-bg);
}

.chapter-waymark {
  color: var(--vp-c-brand-1);
  font-size: 10px;
  font-weight: 600;
  line-height: 1.4;
  letter-spacing: 0.12em;
}

/* 站牌默认全隐藏;地铁地图内的首末站由 ChapterNav 侧的 :deep 规则点亮 */
.chapter-waymark,
.chapter-start,
.chapter-finish {
  display: none;
}

.chapter-link--sub:only-child {
  width: 100%;
  min-height: 46px;
}

/* 容器查询依赖 ChapterNav(sub)上的 container: chapter-trail;在
   RoadMapPhase 等非地图容器里的 sub 卡片不会命中,保持宽屏站牌布局。 */
@container chapter-trail (max-width: 560px) {
  .chapter-link.chapter-link--sub {
    width: 100%;
    min-height: 64px;
    gap: 14px;
    flex-direction: row;
    text-align: left;
  }

  .chapter-link--sub:nth-child(even) {
    width: calc(100% - 12px);
  }

  .chapter-link--sub .chapter-arrow {
    display: none;
  }

  .chapter-node {
    flex-basis: 40px;
    width: 40px;
    height: 40px;
    font-size: 12px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .chapter-link,
  .chapter-link * {
    transition: none;
  }

  .chapter-link:hover {
    transform: none;
  }
}
</style>
