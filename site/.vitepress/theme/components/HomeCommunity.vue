<script setup lang="ts">
import { withBase } from 'vitepress'
import type { CommunityConfig } from '../../config/schema'

// 首页「技术交流」区块:QQ 群二维码 + 群号 + 加群按钮,挂 home-hero-after 紧跟 hero(首屏可见)。
// 数据来自 project.config.ts 的 community(由 prop 注入),纯 HTML/CSS,零运行时依赖。
defineProps<{ community: CommunityConfig }>()
</script>

<template>
  <section id="community" class="home-community">
    <div class="home-community__card">
      <h2 class="home-community__title">{{ community.title ?? '💬 技术交流' }}</h2>

      <div class="home-community__body">
        <a
          class="home-community__qr"
          :href="community.qq.link"
          target="_blank"
          rel="noopener"
          aria-label="加入 QQ 交流群"
        >
          <img
            :src="withBase(community.qq.qrCode)"
            alt="QQ 交流群二维码"
            width="160"
            height="160"
            loading="lazy"
            decoding="async"
          />
        </a>

        <div class="home-community__info">
          <p class="home-community__group">
            QQ 交流群：<a
              class="home-community__group-link"
              :href="community.qq.link"
              target="_blank"
              rel="noopener"
            >{{ community.qq.group }}</a>
          </p>
          <p v-if="community.qq.desc" class="home-community__desc">{{ community.qq.desc }}</p>
          <a
            class="home-community__btn"
            :href="community.qq.link"
            target="_blank"
            rel="noopener"
          >💬 加入群聊</a>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.home-community {
  max-width: 1152px;
  margin: 40px auto 56px;
  padding: 0 24px;
  scroll-margin-top: 80px;
  animation: community-fade-up 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94) both;
}

.home-community__card {
  padding: 28px 32px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 14px;
  background-color: var(--vp-c-bg);
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.04),
    0 1px 2px rgba(0, 0, 0, 0.06);
  text-align: center;
}

.dark .home-community__card {
  background-color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-border);
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.2),
    0 1px 2px rgba(0, 0, 0, 0.15);
}

.home-community__title {
  margin: 0 0 18px;
  font-size: 20px;
  font-weight: 700;
  line-height: 1.4;
  color: var(--vp-c-text-1);
  border-top: 0;
  padding-top: 0;
}

/* ── 二维码 + 信息横向排布 ───────────────────── */
.home-community__body {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 36px;
  text-align: left;
}

/* 二维码容器:QR 的白底是可扫前提,暗色模式下不能跟着变暗 —— 显式白底 + 边框圆角,呈「白卡装进深卡」。 */
.home-community__qr {
  flex: 0 0 auto;
  display: block;
  padding: 10px;
  background: #fff;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  transition: border-color 0.35s ease, transform 0.35s ease;
}

.home-community__qr:hover {
  border-color: var(--vp-c-brand-1);
  transform: translateY(-3px);
}

.home-community__qr img {
  display: block;
  width: 160px;
  height: 160px;
}

.home-community__info {
  max-width: 460px;
}

.home-community__group {
  margin: 0 0 10px;
  font-size: 17px;
  font-weight: 700;
  line-height: 1.4;
  color: var(--vp-c-text-1);
}

.home-community__group-link {
  color: var(--vp-c-brand-1);
  text-decoration: none !important;
  font-variant-numeric: tabular-nums;
}

.home-community__group-link:hover {
  text-decoration: underline !important;
}

.home-community__desc {
  margin: 0 0 18px;
  font-size: 14px;
  line-height: 1.7;
  color: var(--vp-c-text-2);
}

.home-community__btn {
  display: inline-flex;
  align-items: center;
  padding: 10px 22px;
  border-radius: 999px;
  font-size: 0.95rem;
  font-weight: 600;
  text-decoration: none !important;
  background: var(--vp-c-brand-1);
  color: var(--vp-c-bg-elv);
  border: 1.5px solid var(--vp-c-brand-1);
  transition: all 0.25s ease;
}

.home-community__btn:hover {
  background: var(--vp-c-brand-2);
  border-color: var(--vp-c-brand-2);
  transform: translateY(-2px);
}

@keyframes community-fade-up {
  from { opacity: 0; transform: translateY(18px); }
  to   { opacity: 1; transform: translateY(0); }
}

@media (prefers-reduced-motion: reduce) {
  .home-community { animation: none !important; }
  .home-community__qr { transition: none; }
  .home-community__btn { transition: none; }
}

@media (max-width: 639px) {
  .home-community { padding: 0 16px; margin: 28px auto 36px; }
  .home-community__card { padding: 22px 18px; }
  .home-community__title { font-size: 18px; }
  .home-community__body { flex-direction: column; gap: 20px; text-align: center; }
  .home-community__qr img { width: 140px; height: 140px; }
  .home-community__group { font-size: 16px; }
}
</style>
