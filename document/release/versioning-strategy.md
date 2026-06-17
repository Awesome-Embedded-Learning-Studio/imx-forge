# IMX-Forge 版本号管理策略

> **状态**: 已确认，第一阶段已实施
> **日期**: 2026-06-09
> **基线版本**: v1.0.0
> **适用范围**: IMX-Forge 主仓库的版本发布、CI/CD 发布入口、Docker 镜像标签、README 版本展示

---

## 1. 评审结论

当前阶段不采用 PR 自动打 tag，也不新增强制 PR release label。

IMX-Forge 目前更适合采用 **维护者手动触发 release workflow** 的策略：

- PR 只承担代码和文档变更，不承担版本号决策。
- 版本号不是单个 PR 的属性，而是维护者对一批变更形成稳定发布点后的判断。
- 是否发布、发布为 PATCH / MINOR / MAJOR，由维护者在触发 workflow 时决定。
- workflow 负责执行机械动作：计算版本号、打 tag，并按维护者选择创建 GitHub Release、触发 Docker 发布。

这样可以避免小修小补频繁发布 PATCH，也保留 CI 自动化带来的可重复性和低出错率。

---

## 2. 仓库现状统计

截至 2026-06-09，本仓库发布相关状态如下：

| 项目 | 当前状态 | 评估 |
|---|---|---|
| 最新 git tag | `v1.0.0` | 已有明确发布基线 |
| Release 文档 | `document/release/v1.0.0.md` | 适合继续按正式版本维护 |
| CHANGELOG | `changelog/CHANGELOG.md` | 已存在，后续沿用此路径 |
| GitHub Actions workflow | 5 个 | 已有 CI、Full Build、Pages、Docker 发布基础 |
| Docker 发布触发 | release workflow dispatch + 手动 dispatch + tag push 兜底 | 与手动 release workflow 衔接，并支持按版本跳过 |
| `package.json` version | `0.0.1` 且 `private: true` | 不作为项目发布版本源 |

现有 workflow：

- `.github/workflows/ci-build.yml`
- `.github/workflows/ci-full.yml`
- `.github/workflows/ci-pr.yml`
- `.github/workflows/deploy.yml`
- `.github/workflows/docker-publish.yml`

关键点：GitHub Actions 使用 `GITHUB_TOKEN` 推送 tag 时，不会级联触发另一个 `push tags` workflow。release workflow 因此在 `publish_docker_image=true` 时显式 `workflow_dispatch` 调用 `.github/workflows/docker-publish.yml`，并以新 tag 作为 `--ref`。本地或人工推送 `v*.*.*` tag 时，Docker workflow 仍可通过 tag push 触发作为兜底。

---

## 3. 设计目标

- 版本号清晰传达变更影响范围，用户能判断是否值得升级。
- 维护者控制发布节奏，避免低价值 PATCH 版本刷屏。
- 用 workflow 执行发布动作，减少本地手动打 tag 的失误。
- git tag 作为项目版本唯一可信来源，不在业务代码中硬编码项目版本。
- Release 页面展示用户应关注的稳定发布点。

---

## 4. 版本号规则

### 4.1 格式

正式版本使用语义化版本：

```text
vX.Y.Z
```

示例：

```text
v1.0.0
v1.0.1
v1.1.0
v2.0.0
```

版本号基于 git tag 管理。构建脚本如需展示版本，统一通过 git 获取：

```bash
IMX_FORGE_VERSION="${IMX_FORGE_VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
```

### 4.2 PATCH

PATCH 表示值得用户获得的修复或小改进。

典型场景：

- 构建脚本 bug 修复
- 烧录、镜像生成、rootfs 合成等流程修复
- 文档中的关键命令、路径、参数修正
- 小范围兼容性修复
- 不改变使用方式的小功能补充

不建议因为普通错别字、排版调整、无用户影响的内部整理发布 PATCH。

### 4.3 MINOR

MINOR 表示新增能力或有规模的用户可见改进，并保持向后兼容。

典型场景：

- 新增板卡适配
- 新增驱动教程体系或完整章节
- 新增烧录方式、构建方式、部署方式
- U-Boot / Linux / BusyBox / Toolchain 等组件版本升级
- Docker 开发环境有明显能力增强
- mainline 内核路径有阶段性进展

### 4.4 MAJOR

MAJOR 只用于不兼容变化。

典型场景：

- rootfs 分区方案改变
- 启动参数或启动流程不兼容旧版本
- 镜像布局、烧录流程发生破坏性变化
- 构建脚本公共接口发生破坏性变化
- 移除已正式支持的板卡或关键能力

不建议仅因为“功能积累很多”升级 MAJOR。里程碑式功能积累如果保持兼容，优先发布为 MINOR。

### 4.5 不发布版本

以下变更通常不触发版本发布：

- 普通错别字
- 文档排版调整
- README 局部润色
- 内部说明整理
- 不影响用户行为的元数据调整
- 未形成稳定用户价值的中间开发提交

---

## 5. 发布策略

### 5.1 不采用 PR 自动打 tag

不在 PR 合并后自动 bump 版本，也不强制新增 release label。

原因：

- 当前维护者和贡献者数量较少，人工判断成本低。
- 很多 PR 的版本影响模糊，强制分类容易制造流程负担。
- 小 PR 自动发布 PATCH 会让用户困惑。
- tag 对用户意味着稳定发布点，不应退化为每个 PR 的流水号。
- Docker 镜像会跟随 tag 发布，自动 tag 会放大低价值发布。

### 5.2 采用手动 release workflow

新增 `.github/workflows/release.yml`，由维护者通过 `workflow_dispatch` 手动触发。

建议输入项：

| 输入项 | 类型 | 说明 |
|---|---|---|
| `release_type` | `patch` / `minor` / `major` | 必填，决定版本号升级段 |
| `version_override` | string | 可选，手动指定版本号；为空时自动计算 |
| `create_github_release` | boolean | 默认 `false`，是否创建 GitHub Release |
| `publish_docker_image` | boolean | 默认 `true`，是否发布 Docker 镜像 |
| `dry_run` | boolean | 默认 `true`，仅计算和预览，不推送 tag |

正式发布示例：

```text
当前最新 tag: v1.0.3
release_type=patch -> v1.0.4
release_type=minor -> v1.1.0
release_type=major -> v2.0.0
```

### 5.3 workflow 职责

release workflow 应执行以下动作：

```text
维护者手动触发
  |
  |-- fetch 完整 git tags
  |-- 读取最新正式版本 tag
  |-- 根据 release_type 计算新版本号
  |-- 校验新版本号不存在
  |-- 运行必要发布前检查
  |-- 创建 annotated tag
  |-- push tag
  |-- 按 create_github_release 决定是否创建 GitHub Release
  |-- 按 publish_docker_image 决定是否显式 dispatch docker-publish.yml
```

建议 tag 使用 annotated tag，并写入发布意图：

```text
IMX-Forge v1.1.0

Release-Type: minor
GitHub-Release: true
Docker-Image: true
```

注意：`Docker-Image` 字段主要用于人工 tag push 的兜底路径。release workflow 创建 tag 后，会直接通过 `workflow_dispatch` 触发 Docker workflow，避免 `GITHUB_TOKEN` tag push 不触发后续 workflow 的限制。

### 5.4 发布前检查

发布 workflow 至少应执行：

- checkout 时使用 `fetch-depth: 0`
- 校验 tag 格式为 `vX.Y.Z`
- 校验目标 tag 不存在
- 校验 `changelog/CHANGELOG.md` 存在
- 校验对应 MINOR/MAJOR release 文档存在，或在 workflow 中明确允许跳过
- 运行文档构建检查，例如 `pnpm install --frozen-lockfile` 和 `pnpm build`

Full Build 是否放进 release workflow 可按阶段决定。当前建议：

- 第一阶段：release workflow 只做轻量检查、打 tag、发 Release。
- 第二阶段：可增加可选输入 `run_full_build`，需要时发布前运行完整构建。

---

## 6. GitHub Release 策略

正式 tag 默认不创建 GitHub Release。维护者只在该版本值得公告时开启 `create_github_release`。

建议：

- PATCH Release 可以简短，只记录关键修复。
- MINOR / MAJOR Release 需要完整 release notes，并关联 release 文档。
- 不为了普通小改动发布 PATCH。

Release notes 来源建议先保持人工整理。当前不引入 Issue draft 累积机制，避免自动化复杂度过高。

### 6.1 Release 标题

格式：

```text
IMX-Forge vX.Y.Z
```

### 6.2 Release 内容

推荐结构：

```markdown
## Highlights

- ...

## Changes

- ...

## Known Limits

- ...

## Documents

- Release note: document/release/vX.Y.Z.md
- Changelog: changelog/CHANGELOG.md
```

---

## 7. README 版本 Banner

在 README.md badge 区域追加版本 badge，使用 shields.io 同时显示最新 GitHub tag 和最新 GitHub Release：

```markdown
[![Tag](https://img.shields.io/github/v/tag/Awesome-Embedded-Learning-Studio/imx-forge?sort=semver&style=flat-square&label=Tag&color=blue)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/tags)
[![Latest Stable](https://img.shields.io/github/v/release/Awesome-Embedded-Learning-Studio/imx-forge?style=flat-square&label=latest%20stable&color=blue)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/releases/latest)
```

插入位置建议在 CI badge 之后：

```markdown
[![CI](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions/workflows/ci-build.yml/badge.svg)](...)
[![Tag](https://img.shields.io/github/v/tag/Awesome-Embedded-Learning-Studio/imx-forge?sort=semver&style=flat-square&label=Tag&color=blue)](...)
[![Latest Stable](https://img.shields.io/github/v/release/Awesome-Embedded-Learning-Studio/imx-forge?style=flat-square&label=latest%20stable&color=blue)](...)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)
```

由于 GitHub Release 与 Docker 镜像发布已经解耦，Tag badge 展示最新 git tag，避免 PATCH 版本只打 tag、不创建 GitHub Release 时页面版本号滞后；latest stable badge 展示最新 GitHub Release，用于公告稳定节点。

---

## 8. 发版文档规范

### 8.1 Release 文档

每个 MINOR / MAJOR 版本在 `document/release/` 下维护独立文档：

```text
document/release/vX.Y.Z.md
```

格式参考现有 `document/release/v1.0.0.md`。

建议包含：

- 定位说明
- 支持板卡列表
- 已验证闭环
- 本地可生成产物
- 已知限制
- 组件版本快照表

PATCH 版本默认不要求独立 release 文档；如 PATCH 修复影响较大，也可以补充独立文档。

### 8.2 CHANGELOG

CHANGELOG 使用现有路径：

```text
changelog/CHANGELOG.md
```

建议后续逐步整理为类似 Keep a Changelog 的结构：

```markdown
## [1.1.0] - 2026-07-xx

### Added
- 支持新板卡

### Changed
- 升级 Linux NXP BSP

### Fixed
- 修复 eMMC 烧录分区对齐问题
```

### 8.3 组件版本快照

每个 MINOR / MAJOR release 文档中记录组件版本，便于用户对照：

```markdown
## 组件版本

| 组件 | 版本 |
|---|---|
| U-Boot | lf_v2025.04 |
| Linux (NXP BSP) | lf-6.12.y |
| Linux (Mainline) | v7.1 |
| BusyBox | master / pinned commit |
| Toolchain | ARM GNU 15.2.rel1 |
```

---

## 9. 预发布版本规划

当前阶段暂不实现 alpha / beta / rc 自动化。

后续当项目进入以下场景时，再扩展预发布：

- 新板卡适配需要外部用户验证
- 分区、启动、镜像布局存在较大变更
- Qt 或第三方组件体系需要阶段性测试
- MAJOR 发布前需要候选版本

预期格式：

```text
v1.1.0-alpha.1
v1.1.0-beta.1
v1.1.0-rc.1
v1.1.0
```

后续 workflow 可增加输入：

| 输入项 | 类型 | 说明 |
|---|---|---|
| `release_channel` | `stable` / `alpha` / `beta` / `rc` | 发布通道 |
| `target_version` | string | 预发布所属正式版本，如 `v1.1.0` |
| `prerelease_number` | number | 预发布序号 |

第一版 release workflow 只实现 stable 版本，避免过早引入复杂度。

---

## 10. 实施清单

第一阶段实施项：

| # | 项目 | 类型 | 说明 |
|---|---|---|---|
| 1 | `.github/workflows/release.yml` | 新增 | 手动触发 release，计算版本号、打 tag，并按选项创建 Release / 发布 Docker |
| 2 | `README.md` | 修改 | 在 badge 区域增加 Release badge |
| 3 | `changelog/CHANGELOG.md` | 修改 | 保持现有路径，后续按版本补充 |
| 4 | `document/release/versioning-strategy.md` | 修改 | 本策略文档，已接入发布文档站 |
| 5 | `.github/workflows/docker-publish.yml` | 修改 | 支持 release workflow dispatch，在 tag push 兜底路径中按 tag message 的 `Docker-Image` 决定是否发布 |

暂不实施：

- 不新增 PR release label。
- 不要求每个 PR 标注版本影响。
- 不实现 PR 合并后自动 tag。
- 不实现 Issue draft changelog 累积机制。
- 不实现 alpha / beta / rc 自动化。

---

## 11. 版本路线图

| 版本 | 定位 | 典型变更 |
|---|---|---|
| v1.0.0 | 已发布基线 | 正点原子阿尔法 SD/eMMC 完整闭环 |
| v1.0.Z | PATCH | 值得用户获取的 bug 修复、小改进 |
| v1.1.0 | MINOR | 新板卡、教程体系、组件升级、构建能力增强 |
| v1.2.0 | MINOR | Qt 示例、进阶驱动教程、生态扩展 |
| v2.0.0 | MAJOR | 分区方案、启动流程、脚本接口等不兼容变化 |

---

## 12. 最终原则

IMX-Forge 的版本发布原则：

```text
版本影响由维护者判断，发布动作由 workflow 执行，tag 代表稳定发布点。
```
