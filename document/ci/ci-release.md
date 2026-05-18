# Release Build

发布构建工作流，为正式发布准备构建产物。

::: info 产物定位
当前 Release Build 打包的是 `release-all.sh` 生成的构建验证产物，主要来自 BSP 默认链路。IMX-Forge 的交付重点是可复现构建体系，而不是承诺通用可直接烧录的 binary。
:::

## 文件

`.github/workflows/ci-release.yml`

## 触发条件

| 事件 | 条件 |
|------|------|
| `push` | 推送到 `release-*` 分支 |
| `workflow_dispatch` | 手动触发 |

## 版本号提取

从分支名自动提取版本号：

| 分支名 | 提取的版本 |
|--------|------------|
| `release-0.1.0` | `0.1.0` |
| `release-0.2.0-beta` | `0.2.0-beta` |

## 构建流程

### 1. 完整构建

- 执行 `./scripts/release-all.sh`
- 超时：45 分钟

### 2. 产物验证

验证关键产物存在：
- `u-boot-dtb.imx`
- `zImage`
- `busybox`

### 3. 打包

将 `out/release-latest/images/` 打包为：
```
imx-forge-{version}.tar.gz
```

### 4. 上传

| Artifact | 内容 | 保留期 |
|----------|------|--------|
| release-{version} | `imx-forge-{version}.tar.gz` | 90 天 |

### 5. 构建摘要

自动生成包含以下信息的摘要：
- U-Boot 大小
- Linux 大小
- RootFS 大小

## 预计时间

约 25-30 分钟（与 Full Build 相同）

## 发布流程

1. 创建 release 分支：
   ```bash
   git checkout -b release-0.1.0
   git push origin release-0.1.0
   `` ``

2. 等待 CI 构建完成

3. 从 GitHub Actions 下载 artifact

4. 创建 GitHub Release 并上传 artifact

## 与 Full Build 的区别

| 特性 | Full Build | Release Build |
|------|------------|---------------|
| 触发 | main / 标签 PR | release-* 分支 |
| 打包 | 否 | 是 |
| Artifact 保留期 | 30 天 | 90 天 |
| 用途 | 验证构建 | 发布准备 |
