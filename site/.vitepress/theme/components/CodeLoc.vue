<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'

/**
 * CodeLoc 出处卡(::: code-loc 容器的壳):头带放项目徽章 + 可点复制的文件路径,
 * 默认 slot 装原生代码卡(article-code.css 把内层卡面摊平,读起来是一张卡)。
 * 复制走 navigator.clipboard;SSG 预渲染时按钮只是静态 DOM,hydration 后才可点,
 * 剪贴板不可用时静默降级——路径本身始终完整可见,可手动选择复制。
 */
const props = defineProps<{
  /** 项目名,画成徽章,例如 uboot-mainline */
  project?: string
  /** 仓库相对路径,可带 :行号 后缀,点击整段复制 */
  path?: string
}>()

const COPIED_MS = 1600
const copied = ref(false)
let timer: ReturnType<typeof setTimeout> | undefined

async function copyPath(): Promise<void> {
  const value = props.path
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
    copied.value = true
    clearTimeout(timer)
    timer = setTimeout(() => {
      copied.value = false
    }, COPIED_MS)
  } catch {
    // 剪贴板不可用(非安全上下文/权限拒绝):静默,不做任何提示。
  }
}

onBeforeUnmount(() => clearTimeout(timer))
</script>

<template>
  <div class="vp-code-loc">
    <div class="vp-cl-head">
      <span v-if="project" class="vp-cl-project">{{ project }}</span>
      <button
        v-if="path"
        type="button"
        class="vp-cl-path"
        :class="{ 'vp-cl-path--copied': copied }"
        :aria-label="`复制路径 ${path}`"
        @click="copyPath"
      >
        <code class="vp-cl-path-text">{{ path }}</code>
        <span class="vp-cl-hint" aria-live="polite">{{ copied ? '已复制' : '复制路径' }}</span>
      </button>
    </div>
    <div class="vp-cl-body">
      <slot />
    </div>
  </div>
</template>
