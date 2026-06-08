<PageHeader icon="📜" title="脚本文档" description="IMX-Forge 构建系统的脚本说明" />

## 主要脚本

<ChapterNav>
  <ChapterLink num="01" href="../scripts/release-all.sh">release-all.sh —— 一键构建所有组件</ChapterLink>
  <ChapterLink num="02" href="../scripts/patch_maker.sh">patch_maker.sh —— 补丁生成工具</ChapterLink>
  <ChapterLink num="03" href="../scripts/server_helper/copy_to_tftp.sh">copy_to_tftp.sh —— TFTP文件部署</ChapterLink>
</ChapterNav>

| 脚本 | 用途 |
|------|------|
| build-uboot.sh | 构建 U-Boot |
| build-linux.sh | 构建 NXP BSP 内核 |
| build-mainline-linux.sh | 构建主线内核 |
| build-busybox.sh | 构建 BusyBox |
| copy_to_tftp.sh | 部署内核和设备树到 TFTP 目录 |

::: details 目录结构
```
scripts/
├── build_helper/          # 组件构建脚本
│   ├── build-uboot.sh
│   ├── build-linux.sh
│   ├── build-mainline-linux.sh
│   └── build-busybox.sh
├── release-all.sh         # 一键构建
├── patch_maker.sh         # 补丁生成
├── lib/                   # 共享库
├── logo_helper/           # Logo 处理
├── release_builder/       # 发布构建
├── server_helper/         # 服务器工具
└── third_party_install/   # 第三方安装
```
:::

::: details 使用方法
```bash
# 一键构建
./scripts/release-all.sh
```

```bash
# 分步构建
./scripts/build_helper/build-uboot.sh
./scripts/build_helper/build-linux.sh
./scripts/build_helper/build-busybox.sh
```

```bash
# 单独构建主线内核
./scripts/build_helper/build-mainline-linux.sh
```
:::

::: details 延伸阅读
- [构建系统文档](../architecture/BUILD_SYSTEM)
- [补丁系统文档](../architecture/PATCH_SYSTEM)
:::

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回文档首页</ChapterLink>
</ChapterNav>
