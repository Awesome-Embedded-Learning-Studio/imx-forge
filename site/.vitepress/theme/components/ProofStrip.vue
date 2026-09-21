<script setup lang="ts">
/**
 * 首页 hero 下的「证明条」:一行圆点胶囊,把项目最硬的几个事实摆在访客第一屏,
 * 先回答「这套教程靠不靠谱」,再往下看内容。机制移植自 TAMCPP 同名组件
 * (圆点渐变胶囊 + fade-up 入场 + 移动端紧凑样式);TAMCPP 按 lang 切中英两套
 * 文案,imx-forge 是纯中文单语言站,简化为组件内一份常量数组,不再读 useData。
 */
// ── 改文案只改这里;每条行尾注明事实口径,变动时顺手核对来源 ──
//   篇数口径:document/ 全卷 .md 共 383 篇(其中 tutorial/ 教程卷 293 篇),
//   故写「380+ 篇中文文档」;若只想宣传教程卷,改成「290+ 篇中文教程」。
const items = [
  '真板 i.MX6ULL 实测', // README:mainline v7.1 真板实测启动
  '主线内核 Linux 7.1', // 2026-09 起单轨 mainline(linux-imx 轨已退役)
  'CI 全绿', // ci-build.yml 徽章:U-Boot/内核/rootfs 每次提交自动验证
  '380+ 篇中文文档', // document/ 全卷 .md 计数(383)
  'Buildroot 全链', // buildroot 接管 rootfs:br2-external + 自定义包 + Qt6 集成
  'MIT 开源', // LICENSE(U-Boot 衍生补丁保留原始 GPL-2.0)
]
</script>

<template>
  <div class="proof-strip">
    <div class="proof-strip__inner">
      <span
        v-for="(it, i) in items"
        :key="i"
        class="proof-chip"
      >
        <span class="proof-chip__dot" />
        <span class="proof-chip__text">{{ it }}</span>
      </span>
    </div>
  </div>
</template>

<style scoped>
.proof-strip {
  max-width: 1152px;
  margin: 8px auto 40px;
  padding: 0 24px;
  animation: proof-fade-up 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94) 0.1s both;
}

.proof-strip__inner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 10px 20px;
  padding: 12px 20px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 999px;
  background: var(--vp-c-bg-soft);
}

.proof-chip {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  color: var(--vp-c-text-2);
  font-size: 13px;
  font-weight: 500;
  line-height: 1;
  white-space: nowrap;
}

/* 圆点用钢蓝→靛蓝渐变,与全站品牌渐变(VPHero 标题/卡图标)同一视觉语系 */
.proof-chip__dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--vp-c-brand-1), var(--vp-c-indigo-1));
  flex-shrink: 0;
}

@keyframes proof-fade-up {
  from { opacity: 0; transform: translateY(10px); }
  to   { opacity: 1; transform: translateY(0); }
}

@media (prefers-reduced-motion: reduce) {
  .proof-strip { animation: none !important; }
}

@media (max-width: 639px) {
  .proof-strip {
    padding: 0 16px;
    margin-bottom: 20px;
  }
  .proof-strip__inner {
    gap: 8px 14px;
    padding: 10px 14px;
    border-radius: 16px; /* 窄屏胶囊改圆角矩形,短文案多行排布更自然 */
  }
  .proof-chip { font-size: 12px; }
}
</style>
