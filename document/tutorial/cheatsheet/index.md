---
title: 速查与参考
---

<PageHeader title="速查与参考" description="不按教程顺序读的那一类:命令、脚本、参数、第三方组件" />

## 速查

<ChapterNav>
  <ChapterLink num="01" href="../commands/">命令速查</ChapterLink>
  <ChapterLink num="02" href="../third_party/">第三方支持</ChapterLink>
  <ChapterLink num="03" href="../../scripts/">脚本手册</ChapterLink>
  <ChapterLink num="04" href="../../reference/">参考手册</ChapterLink>
</ChapterNav>

### 命令速查

按用途分组,每条都带真实输出:

- 镜像构建命令(`mkimage`、`build-image` 等);
- 镜像检查命令(怎么确认产物是块合法的 ARM 镜像);
- 存储工具命令(`fdisk`、`losetup`、`mount` 一圈);
- 烧录命令(`dd`、UUU、UMS)。

### 第三方支持

设备树、i.MX6ULL 相关的第三方仓库与组件说明。

### 脚本手册 / 参考手册

`/scripts/` 是仓库内每个构建脚本的逐篇说明(构建、镜像、驱动模板、QEMU、release 等);`/reference/` 是配置项、参数与接口的参考索引。这两个区面向「我要改它」而不是「我要学它」。

::: tip 怎么用这一区
不要顺序读。用浏览器搜索(Ctrl K)直接搜命令名或函数名,命中率比翻侧栏高。
:::
