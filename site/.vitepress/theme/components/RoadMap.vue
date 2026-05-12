<template>
  <div class="roadmap">
    <slot />
  </div>
</template>

<style scoped>
.roadmap {
  position: relative;
  padding-left: 32px;
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.roadmap::before {
  content: '';
  position: absolute;
  left: 23px;
  top: 24px;
  bottom: 24px;
  width: 2px;
  background: repeating-linear-gradient(
    180deg,
    var(--vp-c-divider) 0px,
    var(--vp-c-divider) 6px,
    transparent 6px,
    transparent 12px
  );
  z-index: 0;
}

.dark .roadmap::before {
  background: repeating-linear-gradient(
    180deg,
    var(--vp-c-border) 0px,
    var(--vp-c-border) 6px,
    transparent 6px,
    transparent 12px
  );
}

@media (max-width: 639px) {
  .roadmap {
    padding-left: 0;
    gap: 18px;
  }

  .roadmap::before {
    display: none;
  }
}
</style>
