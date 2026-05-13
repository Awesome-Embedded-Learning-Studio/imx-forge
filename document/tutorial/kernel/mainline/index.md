<PageHeader icon="🌐" title="Mainline 主线内核" description="IMX-Forge 已完成向上游主线内核的迁移" />

## 为什么要用主线内核？

| 特性 | linux-imx (NXP BSP) | mainline |
|------|---------------------|----------|
| 稳定性 | ✅ 高 | ✅ 高 |
| 驱动支持 | ✅ 完善 | ⚠️ 需适配 |
| 长期维护 | ⚠️ 取决于 NXP | ✅ 社区维护 |
| 上游贡献 | ❌ 困难 | ✅ 容易 |
| 版本更新 | ⚠️ 较慢 | ✅ 快速 |

<ChapterNav variant="sub">
  <ChapterLink href="01_why_mainline" variant="sub">为什么要用主线内核</ChapterLink>
</ChapterNav>

::: details 构建命令
```bash
# 使用主线内核构建脚本
./scripts/build_helper/build-mainline-linux.sh

# 或手动构建
cd third_party/linux_mainline
make imx_aes_mainline_defconfig O=../../out/mainline/linux
make -j8 O=../../out/mainline/linux
```
:::

::: details 延伸阅读
- [Linux 内核邮件列表](https://lkml.org/)
- [内核开发流程](https://www.kernel.org/doc/html/latest/process/)
:::

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回内核教程</ChapterLink>
</ChapterNav>
