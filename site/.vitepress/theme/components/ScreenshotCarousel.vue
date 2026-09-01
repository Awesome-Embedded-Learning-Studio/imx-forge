<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { withBase } from 'vitepress'
import type { HomeScreenshot } from '../../config/schema'

// 首页截图轮播(coverflow):数据来自 project.config.ts 的 homeScreenshots,
// 由 theme/index.ts 通过 shots 注入。无 shots 时不渲染(theme/index.ts 已挡)。
// 图片用 withBase 走 public/,故可以是任意比例 —— 套一层「浏览器外壳」(三点 + 地址栏),
// 让异构图(实拍照片 / UI 截图 / Logo)统一呈现为「网页预览」观感。

const props = defineProps<{ shots: HomeScreenshot[] }>()

const slides = computed(() => props.shots)

const active = ref(0)
const count = computed(() => slides.value.length)
const current = computed(() => slides.value[active.value] ?? slides.value[0])

// 把 href 转成「地址栏短文案」:/tutorial/uboot/ → tutorial/uboot
function addr(href: string): string {
  const s = href.replace(/^https?:\/\/[^/]+/, '').replace(/^\/+/, '').replace(/\/+$/, '')
  return s || 'home'
}

// 每张图相对当前 active 的最短环绕偏移,据此决定它的位置类。
// 用模运算算「最短距离」,翻到头会从另一侧无缝接上,不会跳变。
function position(i: number): string {
  const n = count.value
  let d = i - active.value
  if (d > n / 2) d -= n
  else if (d < -n / 2) d += n
  if (d === 0) return 'is-center'
  if (d === 1) return 'is-right'
  if (d === -1) return 'is-left'
  return d > 0 ? 'is-far-right' : 'is-far-left'
}

function go(dir: 1 | -1) {
  active.value = (active.value + dir + count.value) % count.value
  restart()
}
function select(i: number) {
  if (i === active.value) return
  active.value = i
  restart()
}

// 5s 自动翻页;悬停 / 标签页隐藏时暂停(reduced-motion 下改成无动效切换,仍轮播)
const INTERVAL_MS = 5000
let timer: ReturnType<typeof setInterval> | null = null
function stop() {
  if (timer) {
    clearInterval(timer)
    timer = null
  }
}
function restart() {
  stop()
  timer = setInterval(() => {
    active.value = (active.value + 1) % count.value
  }, INTERVAL_MS)
}
function onVisibility() {
  if (document.hidden) stop()
  else restart()
}

onMounted(() => {
  if (count.value > 1) {
    restart()
    document.addEventListener('visibilitychange', onVisibility)
  }
})
onBeforeUnmount(() => {
  stop()
  document.removeEventListener('visibilitychange', onVisibility)
})
</script>

<template>
  <section class="shot-carousel" aria-roledescription="carousel">
    <header class="shot-carousel__head">
      <h2 class="shot-carousel__title">先睹为快</h2>
      <p class="shot-carousel__sub">每 5 秒自动翻页 · 悬停暂停 · 点中间打开该页</p>
    </header>

    <div
      class="shot-carousel__stage"
      @mouseenter="stop"
      @mouseleave="restart"
    >
      <button
        v-if="count > 1"
        class="shot-carousel__arrow shot-carousel__arrow--prev"
        aria-label="上一张"
        @click="go(-1)"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
      </button>

      <div
        v-for="(s, i) in slides"
        :key="i"
        class="shot-carousel__cell"
        :class="position(i)"
      >
        <a
          class="shot-carousel__link"
          :href="i === active ? withBase(s.href) : undefined"
          :aria-label="s.title"
          :tabindex="i === active ? 0 : -1"
        >
          <div class="shot-carousel__chrome">
            <div class="shot-carousel__chrome-dots">
              <span></span><span></span><span></span>
            </div>
            <div class="shot-carousel__chrome-url">{{ addr(s.href) }}</div>
          </div>
          <img :src="withBase(s.src)" :alt="s.title" loading="lazy" decoding="async" draggable="false" />
        </a>
      </div>

      <button
        v-if="count > 1"
        class="shot-carousel__arrow shot-carousel__arrow--next"
        aria-label="下一张"
        @click="go(1)"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
      </button>
    </div>

    <div class="shot-carousel__caption">
      <span class="shot-carousel__cap-text">{{ current.title }}<span class="shot-carousel__cap-desc"> · {{ current.desc }}</span></span>
      <a class="shot-carousel__cap-link" :href="withBase(current.href)">查看 →</a>
    </div>

    <div v-if="count > 1" class="shot-carousel__dots" role="tablist">
      <button
        v-for="(s, i) in slides"
        :key="i"
        class="shot-carousel__dot"
        :class="{ 'is-active': i === active }"
        :aria-label="`第 ${i + 1} 张`"
        :aria-selected="i === active ? 'true' : 'false'"
        @click="select(i)"
      />
    </div>
  </section>
</template>

<style scoped>
.shot-carousel {
  max-width: 1152px;
  margin: 8px auto 40px;
  padding: 0 24px;
  animation: shot-fade-up 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94) 0.1s both;
}

.shot-carousel__head {
  text-align: center;
  margin-bottom: 14px;
}
.shot-carousel__title {
  margin: 0;
  font-size: 22px;
  font-weight: 700;
  letter-spacing: 0.3px;
  color: var(--vp-c-text-1);
}
.shot-carousel__sub {
  margin: 6px 0 0;
  font-size: 13px;
  color: var(--vp-c-text-2);
}

/* ── Stage:coverflow 容器,带透视 ─────────────────────────── */
.shot-carousel__stage {
  position: relative;
  height: clamp(300px, 42vw, 430px);
  perspective: 1400px;
}

.shot-carousel__cell {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  margin: 0 auto;
  width: min(600px, 86%);
  height: 100%;
  transform-origin: center center;
  transition: transform 0.6s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.45s ease;
  will-change: transform, opacity;
  cursor: pointer;
}
.shot-carousel__cell.is-center {
  transform: translateX(0) scale(1) rotateY(0deg);
  opacity: 1;
  z-index: 3;
  cursor: pointer;
}
.shot-carousel__cell.is-left {
  transform: translateX(-58%) scale(0.76) rotateY(20deg);
  opacity: 0.5;
  z-index: 2;
  pointer-events: none;
}
.shot-carousel__cell.is-right {
  transform: translateX(58%) scale(0.76) rotateY(-20deg);
  opacity: 0.5;
  z-index: 2;
  pointer-events: none;
}
.shot-carousel__cell.is-far-left {
  transform: translateX(-95%) scale(0.6) rotateY(20deg);
  opacity: 0;
  z-index: 0;
  pointer-events: none;
}
.shot-carousel__cell.is-far-right {
  transform: translateX(95%) scale(0.6) rotateY(-20deg);
  opacity: 0;
  z-index: 0;
  pointer-events: none;
}

.shot-carousel__link {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  border-radius: 14px;
  overflow: hidden;
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg-soft);
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.18);
  transition: border-color 0.25s, box-shadow 0.25s;
}
.shot-carousel__cell.is-center:hover .shot-carousel__link {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 20px 48px rgba(15, 52, 96, 0.26);
}

/* ── 浏览器外壳:三点 + 地址栏,让异构图统一为「网页预览」观感 ── */
.shot-carousel__chrome {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  background: var(--vp-c-bg);
  border-bottom: 1px solid var(--vp-c-divider);
  flex-shrink: 0;
}
.shot-carousel__chrome-dots {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
}
.shot-carousel__chrome-dots span {
  width: 11px;
  height: 11px;
  border-radius: 50%;
  background: var(--vp-c-divider);
}
.shot-carousel__chrome-dots span:nth-child(1) { background: #ff5f57; }
.shot-carousel__chrome-dots span:nth-child(2) { background: #febc2e; }
.shot-carousel__chrome-dots span:nth-child(3) { background: #28c840; }
.shot-carousel__chrome-url {
  flex: 1;
  min-width: 0;
  padding: 3px 10px;
  border-radius: 6px;
  background: var(--vp-c-bg-soft);
  color: var(--vp-c-text-3);
  font-size: 12px;
  font-family: var(--vp-font-family-mono, monospace);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: center;
}

.shot-carousel__link img {
  display: block;
  width: 100%;
  flex: 1;
  min-height: 0;
  object-fit: contain;
  background: var(--vp-c-bg-soft);
  pointer-events: none;
}

/* ── Arrows ─────────────────────────────────────────────── */
.shot-carousel__arrow {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  z-index: 5;
  width: 42px;
  height: 42px;
  border-radius: 50%;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  color: var(--vp-c-brand-1);
  background: var(--vp-c-bg-soft);
  border: 1px solid var(--vp-c-divider);
  transition: background 0.2s, color 0.2s, border-color 0.2s, transform 0.1s;
}
.shot-carousel__arrow:hover {
  background: var(--vp-c-brand-soft);
  border-color: var(--vp-c-brand-1);
}
.shot-carousel__arrow:active {
  transform: translateY(-50%) scale(0.94);
}
.shot-carousel__arrow:focus-visible {
  outline: 2px solid var(--vp-c-brand-1);
  outline-offset: 2px;
}
.shot-carousel__arrow--prev { left: max(4px, 1.5%); }
.shot-carousel__arrow--next { right: max(4px, 1.5%); }

/* ── Caption + dots ─────────────────────────────────────── */
.shot-carousel__caption {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  margin-top: 16px;
  min-height: 22px;
  flex-wrap: wrap;
  padding: 0 8px;
}
.shot-carousel__cap-text {
  font-size: 14px;
  font-weight: 600;
  color: var(--vp-c-text-1);
}
.shot-carousel__cap-desc {
  font-weight: 400;
  color: var(--vp-c-text-2);
}
.shot-carousel__cap-link {
  font-size: 13px;
  font-weight: 600;
  color: var(--vp-c-brand-1);
  text-decoration: underline;
  text-underline-offset: 2px;
  white-space: nowrap;
}
.shot-carousel__cap-link:hover {
  color: var(--vp-c-brand-2);
}

.shot-carousel__dots {
  display: flex;
  justify-content: center;
  gap: 8px;
  margin-top: 14px;
}
.shot-carousel__dot {
  width: 8px;
  height: 8px;
  padding: 0;
  border: none;
  border-radius: 50%;
  background: var(--vp-c-divider);
  cursor: pointer;
  transition: background 0.2s, width 0.2s, border-radius 0.2s;
}
.shot-carousel__dot.is-active {
  background: var(--vp-c-brand-1);
  width: 22px;
  border-radius: 999px;
}

@keyframes shot-fade-up {
  from { opacity: 0; transform: translateY(16px); }
  to   { opacity: 1; transform: translateY(0); }
}

@media (prefers-reduced-motion: reduce) {
  .shot-carousel { animation: none !important; }
  .shot-carousel__cell { transition: none !important; }
}

@media (max-width: 639px) {
  .shot-carousel {
    padding: 0 16px;
    margin-bottom: 24px;
  }
  .shot-carousel__stage {
    height: clamp(240px, 56vw, 320px);
  }
  .shot-carousel__cell.is-left {
    transform: translateX(-46%) scale(0.66) rotateY(16deg);
    opacity: 0.42;
  }
  .shot-carousel__cell.is-right {
    transform: translateX(46%) scale(0.66) rotateY(-16deg);
    opacity: 0.42;
  }
  .shot-carousel__cell.is-far-left {
    transform: translateX(-78%) scale(0.55);
  }
  .shot-carousel__cell.is-far-right {
    transform: translateX(78%) scale(0.55);
  }
  .shot-carousel__arrow {
    width: 38px;
    height: 38px;
  }
  .shot-carousel__title { font-size: 19px; }
  .shot-carousel__sub { font-size: 12px; }
  .shot-carousel__cap-desc { display: none; }
}
</style>
