<PageHeader icon="📋" title="项目规划" description="IMX-Forge 项目的规划和进度跟踪" />

<ChapterNav>
  <ChapterLink num="01" href="README">TODO 索引 —— 文档导航首页</ChapterLink>
  <ChapterLink num="02" href="roadmap">总体路线图 —— 项目发展规划和方向</ChapterLink>
  <ChapterLink num="03" href="todo">待办事项 —— 当前进度和任务总览</ChapterLink>
  <ChapterLink num="04" href="projects/">示例项目 —— 完整的项目清单和详情</ChapterLink>
</ChapterNav>

::: warning 当前重点：D1 方向 - 环境完善
- [ ] Docker 开发环境
- [ ] 环境初始化脚本
- [ ] 烧录脚本
- [ ] VS Code Devcontainer

详见：[D1 详情](directions/d1-environment)
:::

## 进度概览

| 里程碑 | 状态 |
|---------|------|
| v0.5 Mainline 内核迁移 + QT6 | <StatusTag type="done" /> |
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

## 示例项目

<ChapterNav variant="sub">
  <ChapterLink href="projects/proj-001-env-monitor" variant="sub">PROJ-001: 便携式环境监测站</ChapterLink>
  <ChapterLink href="projects/proj-002-image-analyzer" variant="sub">PROJ-002: 嵌入式图像分析仪</ChapterLink>
</ChapterNav>

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回文档首页</ChapterLink>
</ChapterNav>
