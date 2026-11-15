<script setup lang="ts">
import { computed, ref } from 'vue'

/**
 * HexHeaderViewer:字节转储逐字段联动卡。
 * 上方字节栅格按字段分色,点字段行或字节格,下方拼读面板给出
 * 字节序拼法(LE 低位在前、BE 高位在前)与互证出处;保留段灰显。
 * 纯前端本地状态,SSG 预渲染默认选中第一个字段,静态页也完整可读。
 * 用法(直接在 markdown 传字段数组):
 * <HexHeaderViewer title="..." bytes="d1 00 20 40 ..."
 *   :fields="[{ name: 'tag', start: 0, size: 1, value: '0xD1', desc: '...' }]" />
 */
interface HexField {
  /** 字段名(表与面板标题) */
  name: string
  /** 起始字节下标(0 起) */
  start: number
  /** 字节数 */
  size: number
  /** 拼读法,缺省 raw 按字节串显示 */
  endian?: 'LE16' | 'LE32' | 'BE16' | 'raw'
  /** 读出值,如 0x87800000 */
  value: string
  /** 用途一句话 */
  desc?: string
  /** 互证出处(可选) */
  source?: string
  /** 保留/未启用段:灰显 */
  reserved?: boolean
}

const props = defineProps<{
  /** 连续 hex 字节串,空格分隔 */
  bytes: string
  fields: HexField[]
  /** 每行字节数,默认 16 */
  columns?: number
  title?: string
  note?: string
}>()

const bytesList = computed(() =>
  props.bytes.trim().split(/[\s,]+/).filter(Boolean),
)

const colCount = computed(() => props.columns ?? 16)

/** 按 columns 切行,保留每格的绝对字节下标。 */
const rows = computed<number[][]>(() => {
  const out: number[][] = []
  const total = bytesList.value.length
  for (let i = 0; i < total; i += colCount.value) {
    out.push(Array.from({ length: Math.min(colCount.value, total - i) }, (_, k) => i + k))
  }
  return out
})

function fieldOf(index: number): { field: HexField; order: number } | null {
  for (let i = 0; i < props.fields.length; i++) {
    const f = props.fields[i]
    if (index >= f.start && index < f.start + f.size) return { field: f, order: i }
  }
  return null
}

/** 色板下标:非保留字段在六个 soft 色间轮换,保留段独立灰。 */
function toneClass(index: number): string {
  const hit = fieldOf(index)
  if (!hit) return 'hxf-tone-none'
  if (hit.field.reserved) return 'hxf-tone-reserved'
  return `hxf-tone-${hit.order % 6}`
}

/** 与右邻是否跨字段:跨字段时右缘画粗界线,字段间免分隔线。 */
function isFieldEdge(index: number): boolean {
  const cur = fieldOf(index)
  const next = fieldOf(index + 1)
  return cur?.order !== next?.order
}

const active = ref(0)
const activeField = computed(() => props.fields[active.value] ?? null)
const activeBytes = computed(() => {
  const f = activeField.value
  if (!f) return []
  return bytesList.value.slice(f.start, f.start + f.size)
})

const endianBadge = computed(() => {
  const e = activeField.value?.endian ?? 'raw'
  if (e === 'LE16' || e === 'LE32') return '小端'
  if (e === 'BE16') return '大端'
  return '按字节'
})

const rowOffset = (rowIndex: number): string =>
  (rowIndex * colCount.value).toString(16).padStart(4, '0')

function selectField(i: number): void {
  active.value = i
}
</script>

<template>
  <div class="hxf-card">
    <div v-if="title" class="hxf-title">{{ title }}</div>
    <div class="hxf-grid">
      <div v-for="(row, r) in rows" :key="r" class="hxf-row">
        <span class="hxf-offset">{{ rowOffset(r) }}</span>
        <span
          v-for="idx in row"
          :key="idx"
          class="hxf-byte"
          :class="[
            toneClass(idx),
            { 'hxf-byte--edge': isFieldEdge(idx), 'hxf-byte--active': fieldOf(idx)?.order === active },
          ]"
          @click="selectField(fieldOf(idx)?.order ?? active)"
        >{{ bytesList[idx] }}</span>
      </div>
    </div>
    <div v-if="activeField" class="hxf-panel" :class="{ 'hxf-panel--reserved': activeField.reserved }">
      <div class="hxf-panel-head">
        <span class="hxf-panel-name">{{ activeField.name }}</span>
        <span class="hxf-panel-meta">偏移 0x{{ activeField.start.toString(16).padStart(2, '0') }} · {{ activeField.size }} 字节</span>
        <span class="hxf-panel-badge">{{ endianBadge }}</span>
        <span v-if="activeField.reserved" class="hxf-panel-badge hxf-panel-badge--dim">保留段</span>
      </div>
      <div class="hxf-panel-bytes">
        <span v-for="(b, i) in activeBytes" :key="i" class="hxf-panel-byte">{{ b }}</span>
        <span v-if="activeField.endian === 'LE16' || activeField.endian === 'LE32'" class="hxf-panel-lead">低位字节在前</span>
        <span v-else-if="activeField.endian === 'BE16'" class="hxf-panel-lead">高位字节在前</span>
        <span class="hxf-panel-value">{{ activeField.value }}</span>
      </div>
      <p v-if="activeField.desc" class="hxf-panel-desc">{{ activeField.desc }}</p>
      <p v-if="activeField.source" class="hxf-panel-source">互证：{{ activeField.source }}</p>
    </div>
    <div class="hxf-table" role="list">
      <button
        v-for="(f, i) in fields"
        :key="f.name + i"
        type="button"
        class="hxf-rowbtn"
        :class="{ 'hxf-rowbtn--active': i === active, 'hxf-rowbtn--reserved': f.reserved }"
        @click="selectField(i)"
      >
        <span class="hxf-col-name">{{ f.name }}</span>
        <span class="hxf-col-off">0x{{ f.start.toString(16).padStart(2, '0') }}</span>
        <span class="hxf-col-val">{{ f.value }}</span>
        <span v-if="f.desc" class="hxf-col-desc">{{ f.desc }}</span>
      </button>
    </div>
    <p v-if="note" class="hxf-note">{{ note }}</p>
  </div>
</template>

<style scoped>
.hxf-card {
  margin: 24px 0;
  padding: 14px 16px 12px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 14px;
  background: var(--article-code-bg, var(--vp-c-bg));
  box-shadow: var(--article-code-shadow, none);
  overflow: hidden;
}

.hxf-title {
  margin-bottom: 10px;
  color: var(--vp-c-text-1);
  font: 600 13px/1.6 var(--vp-font-family-base);
}

.hxf-grid {
  overflow-x: auto;
  padding: 12px 2px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 10px;
  background: var(--article-code-header, var(--vp-c-bg-soft));
}

.hxf-row {
  display: flex;
  align-items: stretch;
  gap: 0;
  white-space: nowrap;
}

.hxf-offset {
  width: 52px;
  padding-right: 10px;
  color: var(--article-code-number, var(--vp-c-text-3));
  font: 500 11px/26px var(--article-code-font, var(--vp-font-family-mono));
  text-align: right;
  user-select: none;
}

.hxf-byte {
  width: 27px;
  padding: 0 1px;
  font: 500 12.5px/26px var(--article-code-font, var(--vp-font-family-mono));
  text-align: center;
  color: var(--vp-c-text-1);
  cursor: pointer;
  transition: filter 0.15s ease, outline-color 0.15s ease;
  outline: 1px solid transparent;
}

.hxf-byte--edge {
  border-right: 2px solid var(--article-code-border, var(--vp-c-divider));
}

.hxf-byte:hover {
  filter: brightness(1.06) saturate(1.2);
}

.hxf-byte--active {
  outline: 1.5px solid var(--vp-c-brand-1);
  outline-offset: -1.5px;
  z-index: 1;
}

/* 六色轮换:soft 令牌自带明暗适配;保留段独立灰。 */
.hxf-tone-0 { background: var(--vp-c-brand-soft); }
.hxf-tone-1 { background: var(--vp-c-indigo-soft); }
.hxf-tone-2 { background: var(--vp-c-purple-soft); }
.hxf-tone-3 { background: var(--vp-c-yellow-soft); }
.hxf-tone-4 { background: var(--vp-c-cyan-soft); }
.hxf-tone-5 { background: var(--vp-c-green-soft); }
.hxf-tone-reserved { background: var(--vp-c-text-3); opacity: 0.35; }
.hxf-tone-none { background: transparent; }

.hxf-panel {
  margin-top: 10px;
  padding: 10px 12px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 10px;
  background: var(--article-code-bg, var(--vp-c-bg));
}

.hxf-panel--reserved {
  opacity: 0.8;
}

.hxf-panel-head {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}

.hxf-panel-name {
  font: 600 13px/1.6 var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-brand-1);
}

.hxf-panel-meta {
  color: var(--vp-c-text-3);
  font-size: 12px;
}

.hxf-panel-badge {
  padding: 1px 8px;
  border: 1px solid var(--article-code-border, var(--vp-c-divider));
  border-radius: 6px;
  color: var(--vp-c-brand-1);
  font: 500 11px/18px var(--vp-font-family-base);
}

.hxf-panel-badge--dim {
  color: var(--vp-c-text-3);
}

.hxf-panel-bytes {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
  margin-top: 8px;
}

.hxf-panel-byte {
  padding: 1px 6px;
  border-radius: 6px;
  background: var(--article-code-badge, var(--vp-c-bg-soft));
  font: 600 12.5px/22px var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-text-1);
}

.hxf-panel-lead {
  color: var(--vp-c-text-3);
  font-size: 12px;
}

.hxf-panel-value {
  margin-left: auto;
  font: 600 15px/22px var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-brand-1);
}

.hxf-panel-desc {
  margin: 8px 0 0;
  color: var(--vp-c-text-1);
  font-size: 13px;
  line-height: 1.7;
}

.hxf-panel-source {
  margin: 4px 0 0;
  color: var(--vp-c-text-2);
  font-size: 12.5px;
  line-height: 1.6;
}

.hxf-table {
  margin-top: 10px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.hxf-rowbtn {
  display: grid;
  grid-template-columns: 110px 52px 108px minmax(0, 1fr);
  gap: 10px;
  align-items: baseline;
  padding: 4px 10px;
  border: 0;
  border-radius: 8px;
  background: none;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.15s ease;
}

.hxf-rowbtn:hover {
  background: var(--article-code-header, var(--vp-c-bg-soft));
}

.hxf-rowbtn--active {
  background: var(--article-code-badge, var(--vp-c-bg-soft));
  outline: 1px solid var(--vp-c-brand-soft);
}

.hxf-rowbtn--reserved {
  opacity: 0.55;
}

.hxf-col-name {
  font: 600 12.5px/1.7 var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-text-1);
}

.hxf-col-off,
.hxf-col-val {
  font: 500 12px/1.7 var(--article-code-font, var(--vp-font-family-mono));
  color: var(--vp-c-text-2);
}

.hxf-col-val {
  color: var(--vp-c-brand-1);
}

.hxf-col-desc {
  overflow: hidden;
  color: var(--vp-c-text-2);
  font-size: 12px;
  line-height: 1.6;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.hxf-note {
  margin: 8px 2px 0;
  color: var(--vp-c-text-3);
  font-size: 12px;
  line-height: 1.6;
}

@media (max-width: 639px) {
  .hxf-rowbtn {
    grid-template-columns: 96px 46px 96px minmax(0, 1fr);
    gap: 8px;
  }
  .hxf-col-desc {
    display: none;
  }
}
</style>
