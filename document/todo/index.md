---
title: 项目规划
---

<PageHeader icon="📋" title="项目规划" description="IMX-Forge 项目的规划和进度跟踪" />

## 快速开始

### 新用户入口

如果你是第一次了解 IMX-Forge，建议按以下顺序阅读：

1. **📖 [总体路线图](roadmap)** - 了解项目全貌和发展规划
2. **📦 v1.0.0 发布** - SD/eMMC 完整闭环，见 [release/v1.0.0.md](../release/v1.0.0.md)
3. **🎯 [当前重点：D1 方向](directions/d1-environment)** - 查看环境完善方向

### 贡献者入口

如果你想参与项目开发：

1. **📋 [任务总览](todo)** - 查看所有待办任务
2. **🗺️ [路线图](roadmap)** - 选择你感兴趣的方向
3. **📁 [方向详情](directions/d1-environment)** - 查看具体任务
4. **🎯 [示例项目](projects/)** - 查看项目清单

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="./">TODO 索引 —— 文档导航首页</ChapterLink>
  <ChapterLink num="02" href="roadmap">总体路线图 —— 项目发展规划和方向</ChapterLink>
  <ChapterLink num="03" href="todo">待办事项 —— 当前进度和任务总览</ChapterLink>
  <ChapterLink num="04" href="projects/">示例项目 —— 完整的项目清单和详情</ChapterLink>
</ChapterNav>

::: warning 当前重点：D1 方向 - 环境完善
- [x] Docker 开发环境（D1-001）
- [x] 环境初始化脚本（D1-004）
- [x] 烧录脚本 + flash/ 烧录教程（D1-005）
- [ ] VS Code Devcontainer（D1-003，待办）

P0 文档已完成 23/29，剩余缺口见 [D1 详情](directions/d1-environment)
:::

## 进度概览

| 里程碑 | 状态 |
|---------|------|
| v0.5 Mainline 内核迁移 + QT6 | <StatusTag type="done" /> |
| v1.0.0 SD/eMMC 完整闭环 | <StatusTag type="done" /> |
| D1: 环境完善 | <StatusTag type="active" /> |
| D2: 工具完备 | <StatusTag type="planned" /> |
| D3: 示例展示 | <StatusTag type="planned" /> |
| D4: 生态成熟 | <StatusTag type="planned" /> |

## 发展方向

<ChapterNav variant="sub">
  <ChapterLink href="directions/d1-environment" variant="sub">D1: 环境完善 — Docker 化、辅助脚本</ChapterLink>
  <ChapterLink href="directions/d2-tools" variant="sub">D2: 工具完备 — CI/CD、多板卡支持</ChapterLink>
  <ChapterLink href="directions/d3-examples" variant="sub">D3: 示例展示 — QT6 示例、旗舰项目</ChapterLink>
  <ChapterLink href="directions/d4-ecosystem" variant="sub">D4: 生态成熟 — 多 Rootfs、精品项目</ChapterLink>
</ChapterNav>

## 项目进度

```
[✅] v0.1 - 基础框架搭建
[✅] v0.3 - U-Boot 和内核移植
[✅] v0.5 - Mainline 内核迁移 + QT6 支持
[✅] v1.0.0 - SD/eMMC 完整构建→烧录→启动闭环
[🚧] 当前重点：环境完善与工具开发
[📋] 方向 D1：环境完善
[📋] 方向 D2：工具完备
[📋] 方向 D3：示例展示
[📋] 方向 D4：生态成熟
```

## 示例项目

<ChapterNav variant="sub">
  <ChapterLink href="projects/proj-001-env-monitor" variant="sub">PROJ-001: 便携式环境监测站</ChapterLink>
  <ChapterLink href="projects/proj-002-image-analyzer" variant="sub">PROJ-002: 嵌入式图像分析仪</ChapterLink>
</ChapterNav>

## 如何贡献

我们欢迎所有形式的贡献！

### 贡献方式

1. **代码贡献**：实现一个任务或功能
2. **文档贡献**：完善教程和文档
3. **测试贡献**：测试功能和报告问题
4. **项目贡献**：完成一个示例项目
5. **建议贡献**：提出改进建议

### 贡献流程

1. 阅读 [路线图](roadmap.md) 和 [任务总览](todo.md)
2. 选择你感兴趣的任务
3. 在 GitHub Issues 中声明你的意图
4. Fork 项目并创建分支
5. 提交 Pull Request
6. 等待 Code Review

详见：GitHub 仓库的贡献指南

## 常见问题

### Q: 我应该从哪里开始？

**A**: 如果你是新用户，建议从 [roadmap.md](roadmap.md) 开始。如果你想贡献代码，查看 [todo.md](todo.md) 或 [D1 方向](directions/d1-environment)。

### Q: 方向和里程碑有什么区别？

**A**: 我们使用"方向"而不是"里程碑"来强调灵活性和优先级，而不是严格的时间线。你可以根据兴趣和需求选择任何方向开始，不必按顺序完成。

### Q: 任务的优先级是什么？

**A**: 我们使用 P0/P1/P2/P3 优先级系统：
- **P0**：最高优先级，核心功能
- **P1**：高优先级，重要功能
- **P2**：中等优先级，增强功能
- **P3**：低优先级，可选功能

### Q: 如何查看项目进度？

**A**: 主路线图 [roadmap.md](roadmap.md) 有详细的进度说明和发展方向介绍。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回文档首页</ChapterLink>
</ChapterNav>
