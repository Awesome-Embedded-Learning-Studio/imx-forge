<script setup lang="ts">
import { computed, ref } from 'vue'

/**
 * MemLayoutBar:内存/介质布局条。
 * 按真实比例画一段地址窗口内的分段(窗口用 viewStart/viewEnd 指定,
 * 窗口外的段自动裁掉),段窄到不足 1.6% 时画成竖线,信息移到下方图例,
 * 不扭曲比例。点图例或条内分段,下方详情面板给出起止地址、大小与用途。
 * 纯前端本地状态,SSG 预渲染默认选中第一段,静态页完整可读。
 * 用法:
 * <MemLayoutBar title="..." :view-start="0x80000000" :view-end="0x88000000"
 *   :segments="[{ label: 'zImage', start: 0x82000000, size: 10369960, desc: '...' }]" />
 */
interface LayoutSegment {
  /** 段名 */
  label: string
  /** 起始地址(绝对值) */
  start: number
  /** 大小(与地址同单位) */
  size: number
  /** 用途一句话 */
  desc?: string
  /** 空闲/建议虚位段:斜纹虚显 */
  soft?: boolean
}

const props = defineProps<{
  /** 可视窗口起点(绝对地址) */
  viewStart: number
  /** 可视窗口终点(不含) */
  viewEnd: number
  segments: LayoutSegment[]
  title?: string
  note?: string
}>()

const SPAN = computed(() => Math.max(1, props.viewEnd - props.viewStart))
const MIN_PCT = 1.6

interface Placed extends LayoutSegment {
  left: number
  width: number
  /** 不足 MIN_PCT 的窄段:条内画竖线 */
  hairline: boolean
  /** 与窗口求交后的可见大小 */
  visibleSize: number
}

const placed = computed<Placed[]>(() => {
  const out: Placed[] = []
  for (const seg of props.segments) {
    const segEnd = seg.start + seg.size
    const start = Math.max(seg.start, props.viewStart)
    const end = Math.min(segEnd, props.viewEnd)
    if (end <= start) continue
    const left = ((start - props.viewStart) / SPAN.value) * 100
    const rawWidth = ((end - start) / SPAN.value) * 100
    const width = Math.max(rawWidth, seg.soft ? 0.8 : MIN_PCT)
    out.push({
      ...seg,
      left,
      width: Math.min(width, 100 - left),
      hairline: rawWidth < MIN_PCT,
      visibleSize: end - start,
    })
  }
  return out.sort((a, b) => a.start - b.start)
})

const active = ref(0)
const activeSeg = computed(() => placed.value[active.value] ?? null)

function hex(n: number): string {
  return '0x' + n.toString(16).toUpperCase()
}

function sizeText(n: number): string {
  if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MiB`
  if (n >= 1024) return `${(n / 1024).toFixed(1)} KiB`
  return `${n} B`
}

function toneClass(order: number): string {
  return `mlb-tone-${order % 6}`
}

function select(i: number): void {
  active.value = i
}
</script>

<template>
  <div class="mlb-card">
    <div v-if="title" class="mlb-title">{{ title }}</div>
    <div class="mlb-scale">
      <span>{{ hex(viewStart) }}</span>
      <span>{{ hex(viewEnd) }}</span>
    </div>
    <div class="mlb-bar">
      <span
        v-for="(seg, i) in placed"
        :key="seg.label + i"
        class="mlb-seg"
        :class="[toneClass(i), { 'mlb-seg--soft': seg.soft, 'mlb-seg--hairline': seg.hairline, 'mlb-seg--active': i === active }]"
        :style="{ left: `${seg.left}%`, width: `${seg.width}%` }"
        :title="`${seg.label} · ${hex(seg.start)}`"
        @click="select(i)"
      />
    </div>
    <div class="mlb-legend">
      <button
        v-for="(seg, i) in placed"
        :key="seg.label + i"
        type="button"
        class="mlb-item"
        :class="{ 'mlb-item--active': i === active, 'mlb-item--soft': seg.soft }"
        @click="select(i)"
      >
        <span class="mlb-swatch" :class="toneClass(i)" />
        <span class="mlb-item-label">{{ seg.label }}</span>
        <span class="mlb-item-addr">{{ hex(seg.start) }}</span>
      </button>
    </div>
    <div v-if="activeSeg" class="mlb-panel">
      <div class="mlb-panel-head">
        <span class="mlb-panel-name">{{ activeSeg.label }}</span>
        <span class="mlb-panel-meta">{{ hex(activeSeg.start) }} 起 · {{ sizeText(activeSeg.visibleSize) }}</span>
        <span class="mlb-panel-meta">占窗口 {{ ((activeSeg.visibleSize / SPAN) * 100).toFixed(1) }}%</span>
      </div>
      <p v-if="activeSeg.desc" class="mlb-panel-desc">{{ activeSeg.desc }}</p>
    </div>
    <p v-if="note" class="mlb-note">{{ note }}</p>
  </div>
</template>

<style scoped>
.mlb-card {
  margin: 24px 0;
  padding: 14px 16px 12px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 14px;
  background: var(--article-code-bg, var(--vp-c-bg));
  box-shadow: var(--article-code-shadow, none);
  overflow: hidden;
}

.mlb-title {
  margin-bottom: 8px;
  color: var(--vp-c-text-1);
  font: 600 13px/1.6 var(--vp-font-family-base);
}

.mlb-scale {
  display: flex;
  justify-content: space-between;
  color: var(--article-code-number, var(--vp-c-text-3));
  font: 500 11px/1.6 var(--article-code-font, var(--vp-font-family-mono));
  user-select: none;
}

.mlb-bar {
  position: relative;
  height: 46px;
  margin: 4px 0 10px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 10px;
  background: var(--article-code-header, var(--vp-c-bg-soft));
  overflow: hidden;
}

.mlb-seg {
  position: absolute;
  top: 0;
  height: 100%;
  min-width: 2px;
  cursor: pointer;
  transition: filter 0.15s ease, outline-color 0.15s ease;
  outline: 1.5px solid transparent;
  outline-offset: -1.5px;
}

.mlb-seg:hover {
  filter: brightness(1.08) saturate(1.15);
}

.mlb-seg--hairline {
  min-width: 4px;
}

.mlb-seg--soft {
  background-image: repeating-linear-gradient(
    135deg,
    transparent 0 5px,
    rgb(128 128 128 / 22%) 5px 9px
  );
}

.mlb-seg--active {
  outline-color: var(--vp-c-brand-1);
  z-index: 1;
}

/* 六色轮换,与 HexHeaderViewer 同一套 soft 令牌,明暗自适应。 */
.mlb-tone-0 { background-color: var(--vp-c-brand-soft); }
.mlb-tone-1 { background-color: var(--vp-c-indigo-soft); }
.mlb-tone-2 { background-color: var(--vp-c-purple-soft); }
.mlb-tone-3 { background-color: var(--vp-c-yellow-soft); }
.mlb-tone-4 { background-color: var(--vp-c-cyan-soft); }
.mlb-tone-5 { background-color: var(--vp-c-green-soft); }

.mlb-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.mlb-item {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 9px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 8px;
  background: none;
  cursor: pointer;
  transition: background-color 0.15s ease, border-color 0.15s ease;
}

.mlb-item:hover {
  background: var(--article-code-header, var(--vp-c-bg-soft));
}

.mlb-item--active {
  border-color: var(--vp-c-brand-1);
  background: var(--article-code-badge, var(--vp-c-bg-soft));
}

.mlb-item--soft .mlb-item-label {
  color: var(--vp-c-text-3);
}

.mlb-swatch {
  width: 12px;
  height: 12px;
  border-radius: 4px;
}

.mlb-item--soft .mlb-swatch {
  background-image: repeating-linear-gradient(
    135deg,
    transparent 0 3px,
    rgb(128 128 128 / 25%) 3px 6px
  );
}

.mlb-item-label {
  font: 600 12px/1.6 var(--vp-font-family-base);
  color: var(--vp-c-text-1);
}

.mlb-item-addr {
  font: 500 11px/1.6 var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-text-3);
}

.mlb-panel {
  margin-top: 10px;
  padding: 10px 12px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 10px;
}

.mlb-panel-head {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.mlb-panel-name {
  font: 600 13px/1.6 var(--vp-font-family-base);
  color: var(--vp-c-brand-1);
}

.mlb-panel-meta {
  font: 500 12px/1.6 var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-text-2);
}

.mlb-panel-desc {
  margin: 6px 0 0;
  color: var(--vp-c-text-1);
  font-size: 13px;
  line-height: 1.7;
}

.mlb-note {
  margin: 8px 2px 0;
  color: var(--vp-c-text-3);
  font-size: 12px;
  line-height: 1.6;
}
</style>
