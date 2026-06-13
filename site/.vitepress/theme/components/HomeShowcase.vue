<script setup lang="ts">
import { withBase } from 'vitepress'

// 真实开发板实拍：U-Boot 点亮 LCD + 主线 Linux 7 运行
const shots = [
  {
    src: withBase('/lcd-on.jpg'),
    title: 'U-Boot 点亮 LCD',
    desc: '上电即见——Bootloader 阶段就把 7 寸屏幕点亮'
  },
  {
    src: withBase('/linux7.png'),
    title: '跑起来 Linux 7',
    desc: '上游主线内核 7.0rc 在 i.MX6ULL 上稳定运行'
  }
]
</script>

<template>
  <section class="home-showcase">
    <div class="home-showcase-inner">
      <header class="home-showcase-header">
        <h2 class="home-showcase-title">📸 实测成果</h2>
        <p class="home-showcase-desc">不是 PPT，是正点原子阿尔法 i.MX6ULL 上的真实运行画面</p>
      </header>

      <div class="showcase-grid">
        <figure v-for="s in shots" :key="s.src" class="showcase-card">
          <div class="showcase-img-wrap">
            <img class="showcase-img-bg" :src="s.src" alt="" aria-hidden="true" loading="lazy" />
            <img class="showcase-img-fg" :src="s.src" :alt="s.title" loading="lazy" />
          </div>
          <figcaption class="showcase-caption">
            <span class="showcase-caption-title">{{ s.title }}</span>
            <span class="showcase-caption-desc">{{ s.desc }}</span>
          </figcaption>
        </figure>
      </div>
    </div>
  </section>
</template>

<style scoped>
.home-showcase {
  padding: 48px 24px 16px;
  overflow: visible;
}

.home-showcase-inner {
  max-width: 1000px;
  margin: 0 auto;
}

.home-showcase-header {
  text-align: center;
  margin-bottom: 36px;
}

.home-showcase-title {
  margin: 0;
  font-size: 28px;
  font-weight: 700;
  line-height: 1.5;
  background: linear-gradient(135deg, var(--vp-c-brand-1), var(--vp-c-indigo-1), var(--vp-c-purple-1));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.home-showcase-desc {
  margin: 10px 0 0;
  font-size: 15px;
  color: var(--vp-c-text-2);
  line-height: 1.7;
}

.showcase-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 20px;
}

.showcase-card {
  margin: 0;
  border: 1px solid var(--vp-c-divider);
  border-radius: 16px;
  overflow: hidden;
  background-color: var(--vp-c-bg);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04),
              0 1px 2px rgba(0, 0, 0, 0.06);
  transition: border-color 0.39s ease,
              box-shadow 0.39s ease,
              transform 0.39s ease;
}

.showcase-card:hover {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.1),
              0 4px 8px rgba(0, 0, 0, 0.06);
  transform: translateY(-4px);
}

.showcase-img-wrap {
  position: relative;
  width: 100%;
  aspect-ratio: 4 / 3;
  background: var(--vp-c-bg-soft);
  overflow: hidden;
}

/* 背景层：同一张图放大 + 重模糊，铺满整个容器，消除留白 */
.showcase-img-bg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  filter: blur(22px);
  transform: scale(1.18);
  z-index: 0;
}

/* 前景层：原图按比例完整居中，文字（如 uname -a）不被裁切 */
.showcase-img-fg {
  position: relative;
  z-index: 1;
  width: 100%;
  height: 100%;
  object-fit: contain;
  display: block;
}

.showcase-caption {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 16px 20px;
}

.showcase-caption-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--vp-c-text-1);
}

.showcase-caption-desc {
  font-size: 13px;
  line-height: 1.6;
  color: var(--vp-c-text-2);
}

.dark .showcase-card {
  background-color: var(--vp-c-bg-elv);
  border-color: var(--vp-c-border);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2),
              0 1px 2px rgba(0, 0, 0, 0.15);
}

.dark .showcase-card:hover {
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.3),
              0 4px 8px rgba(0, 0, 0, 0.2);
}

@media (max-width: 639px) {
  .home-showcase {
    padding: 32px 16px 8px;
  }

  .showcase-grid {
    grid-template-columns: 1fr;
  }

  .home-showcase-title {
    font-size: 22px;
  }
}
</style>
