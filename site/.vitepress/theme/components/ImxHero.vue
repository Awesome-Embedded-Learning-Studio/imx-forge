<script setup lang="ts">
import { useData, withBase } from 'vitepress'

// 对齐 anatomy_gui 的 AnatomyHero 设计语言:自定义 hero 替换默认 VPHero,
// 由 home-hero-before 插槽挂载,下方 <style> 里 .VPHome .VPHero { display:none } 关掉默认 hero。
// 数据仍读 frontmatter.hero(标准 VitePress 字段),额外支持 hero.kicker 作为「系列/体裁」小标签。
const { frontmatter } = useData()
</script>

<template>
  <section v-if="frontmatter.hero" class="imx-hero">
    <div class="imx-hero__inner">
      <div class="imx-hero__text">
        <p v-if="frontmatter.hero.kicker" class="imx-hero__kicker">{{ frontmatter.hero.kicker }}</p>
        <h1 class="imx-hero__name">{{ frontmatter.hero.name }}</h1>
        <p v-if="frontmatter.hero.text" class="imx-hero__text-main">{{ frontmatter.hero.text }}</p>
        <p v-if="frontmatter.hero.tagline" class="imx-hero__tagline">{{ frontmatter.hero.tagline }}</p>
        <div v-if="frontmatter.hero.actions?.length" class="imx-hero__actions">
          <a
            v-for="action in frontmatter.hero.actions"
            :key="action.link"
            :href="withBase(action.link)"
            :class="['ih-btn', `ih-btn--${action.theme || 'alt'}`]"
          >
            {{ action.text }}
          </a>
        </div>
      </div>

      <!-- 启动链「解剖图」:ROM → U-Boot → Kernel → 用户空间,脉冲信号沿链路传递(等价 anatomy 的事件循环图) -->
      <div class="imx-hero__art" aria-hidden="true">
        <svg viewBox="0 0 440 340" xmlns="http://www.w3.org/2000/svg" role="img">
          <!-- SoC 边界(虚线圆角框,标注 i.MX6ULL) -->
          <rect x="8" y="120" width="424" height="120" rx="14" fill="none" stroke="var(--vp-c-divider)" stroke-width="1" stroke-dasharray="4 5" />
          <text x="22" y="112" font-size="10" font-family="var(--vp-font-family)" fill="var(--vp-c-text-3)" letter-spacing="1.5">i.MX6ULL · BOOT FLOW</text>

          <!-- 阶段节点(4 个圆角方块) -->
          <g stroke="var(--vp-c-brand-1)" stroke-width="1.5" fill="var(--vp-c-bg)">
            <rect x="24" y="150" width="78" height="60" rx="8" />
            <rect x="134" y="150" width="78" height="60" rx="8" />
            <rect x="244" y="150" width="78" height="60" rx="8" class="imx-hero__kernel" />
            <rect x="354" y="150" width="78" height="60" rx="8" />
          </g>

          <!-- 节点内标签 -->
          <g font-size="12" font-family="var(--vp-font-family)" font-weight="600" fill="var(--vp-c-text-1)" text-anchor="middle">
            <text x="63" y="184">ROM</text>
            <text x="173" y="184">U-Boot</text>
            <text x="283" y="184">Kernel</text>
            <text x="393" y="182">用户</text>
            <text x="393" y="196" font-size="10" font-weight="500" fill="var(--vp-c-text-2)">空间</text>
          </g>
          <!-- 节点内小说明 -->
          <g font-size="9" font-family="var(--vp-font-family)" fill="var(--vp-c-text-3)" text-anchor="middle">
            <text x="63" y="202">片内</text>
            <text x="173" y="202">SPL+proper</text>
            <text x="283" y="202">设备树</text>
          </g>

          <!-- 链路箭头 -->
          <g stroke="var(--vp-c-brand-3)" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round">
            <path d="M104 180 L128 180" />
            <path d="M122 176 L130 180 L122 184" />
            <path d="M214 180 L238 180" />
            <path d="M232 176 L240 180 L232 184" />
            <path d="M324 180 L348 180" />
            <path d="M342 176 L350 180 L342 184" />
          </g>

          <!-- 脉冲启动信号:沿链路从 ROM 一路右行到用户空间,无限循环 -->
          <circle r="4.5" fill="var(--vp-c-brand-1)">
            <animate attributeName="cx" values="104;214;324;348" keyTimes="0;0.35;0.7;0.78" dur="3.2s" repeatCount="indefinite" />
            <animate attributeName="cy" values="180;180;180;180" dur="3.2s" repeatCount="indefinite" />
            <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.1;0.7;0.78" dur="3.2s" repeatCount="indefinite" />
          </circle>
          <!-- Kernel 节点呼吸(等价 anatomy 事件循环脉冲) -->
          <rect x="244" y="150" width="78" height="60" rx="8" fill="none" stroke="var(--vp-c-brand-1)" stroke-width="1.5" opacity="0.5">
            <animate attributeName="opacity" values="0.15;0.6;0.15" dur="2.8s" repeatCount="indefinite" />
            <animate attributeName="stroke-width" values="1.5;3;1.5" dur="2.8s" repeatCount="indefinite" />
          </rect>

          <!-- 解剖风标注:小圆点 + 引线 + 标签 -->
          <g stroke="var(--vp-c-text-3)" stroke-width="0.8" fill="none">
            <path d="M63 150 L63 92 L92 92" />
            <path d="M283 210 L283 268 L312 268" />
            <path d="M393 150 L393 92 L364 92" />
          </g>
          <g fill="var(--vp-c-text-3)" font-size="10.5" font-family="var(--vp-font-family)">
            <circle cx="92" cy="92" r="1.8" />
            <text x="98" y="95">上电首位</text>
            <circle cx="312" cy="268" r="1.8" />
            <text x="318" y="271">驱动 + syscall</text>
            <circle cx="364" cy="92" r="1.8" />
            <text x="358" y="95" text-anchor="end">挂载 rootfs</text>
          </g>

          <!-- 底部「学习路径」提示线 -->
          <g font-size="10" font-family="var(--vp-font-family)" fill="var(--vp-c-brand-1)" font-weight="600">
            <text x="220" y="306" text-anchor="middle" letter-spacing="1">从工具链到驱动实战 · 全栈打通</text>
          </g>
        </svg>
      </div>
    </div>
  </section>
</template>

<style scoped>
.imx-hero {
  padding: 56px 24px 32px;
  max-width: 80rem;
  margin: 0 auto;
}

.imx-hero__inner {
  display: flex;
  align-items: center;
  gap: 48px;
  flex-wrap: wrap;
}

.imx-hero__text {
  flex: 1 1 420px;
  min-width: 0;
}

.imx-hero__kicker {
  font-size: 0.8rem;
  font-weight: 600;
  letter-spacing: 0.16em;
  color: var(--vp-c-brand-1);
  text-transform: uppercase;
  margin: 0 0 12px;
}

.imx-hero__name {
  font-size: 3.4rem;
  font-weight: 800;
  line-height: 1.1;
  letter-spacing: -0.02em;
  margin: 0 0 18px;
  background: linear-gradient(
    135deg,
    var(--vp-c-brand-1) 0%,
    var(--vp-c-brand-2) 50%,
    var(--vp-c-brand-3) 100%
  );
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.imx-hero__text-main {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--vp-c-text-1);
  margin: 0 0 10px;
  line-height: 1.35;
}

.imx-hero__tagline {
  font-size: 1.05rem;
  color: var(--vp-c-text-2);
  line-height: 1.7;
  margin: 0 0 28px;
}

.imx-hero__actions {
  display: flex;
  gap: 14px;
  flex-wrap: wrap;
}

.ih-btn {
  display: inline-flex;
  align-items: center;
  padding: 10px 22px;
  border-radius: 999px;
  font-size: 0.95rem;
  font-weight: 600;
  text-decoration: none !important;
  border: 1.5px solid transparent;
  transition: all 0.25s ease;
}

.ih-btn--brand {
  background: var(--vp-c-brand-1);
  color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-brand-1);
}

.ih-btn--brand:hover {
  background: var(--vp-c-brand-2);
  border-color: var(--vp-c-brand-2);
  transform: translateY(-2px);
}

.ih-btn--alt {
  background: transparent;
  color: var(--vp-c-brand-1);
  border-color: var(--vp-c-brand-1);
}

.ih-btn--alt:hover {
  background: var(--vp-c-brand-soft);
  transform: translateY(-2px);
}

.imx-hero__art {
  flex: 0 1 380px;
  min-width: 280px;
}

.imx-hero__art svg {
  width: 100%;
  height: auto;
  display: block;
}

@media (max-width: 959px) {
  .imx-hero {
    padding: 40px 20px 24px;
  }
  .imx-hero__inner {
    flex-direction: column-reverse;
    gap: 24px;
  }
  .imx-hero__art {
    flex: 0 0 auto;
    max-width: 360px;
  }
  .imx-hero__name {
    font-size: 2.6rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .imx-hero__art svg animate {
    display: none;
  }
}
</style>

<style>
/* 由 ImxHero 在 home-hero-before 接管,关掉默认 VPHero(含其图片+渐变底) */
.VPHome .VPHero {
  display: none !important;
}
</style>
