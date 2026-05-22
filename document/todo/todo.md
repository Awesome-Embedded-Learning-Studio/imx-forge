# IMX-Forge 待办事项

> **最后更新**：2026-05-21
> **数据来源**：GitHub Issue #47 + 本地规划
> **当前历史里程碑**：v0.5

---

## 📑 快速导航

- 🗺️ **总体路线图**：[roadmap.md](roadmap.md)
- 📁 **按方向查看**：
  - [D1: 环境完善](directions/d1-environment) - 25项 (6工具 + 19文档)
  - [D2: 工具完备](directions/d2-tools) - 23项 (6工具 + 17文档)
  - [D3: 示例展示](directions/d3-examples) - 11项 (3工具 + 8文档)
  - [D4: 生态成熟](directions/d4-ecosystem) - 18项 (7工具 + 11文档)
- 🎯 **示例项目**：[projects/](projects/)
- 📦 **已完成**：[archive/v0.5-milestone.md](archive/v0.5-milestone)
- 🔗 **GitHub Issue #47**：[路线任务追踪](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/47)

---

## 📊 优先级说明

```
P0 ──► 主线闭环，必须完成 (新用户第一次启动的完整路径)
P1 ──► 重要功能，尽快完成 (应用开发+调试能力)
P2 ──► 优化体验，逐步完善 (工作流+高级工具)
P3 ──► 可选补充 (参考资源+更多项目)
```

---

## 📊 任务统计总览

### 按方向统计

| 方向 | P0 | P1 | P2 | P3 | 总计 |
|------|----|----|----|----| ---- |
| D1: 环境完善 | 21 | 3 | 1 | - | 25 |
| D2: 工具完备 | - | 20 | 3 | - | 23 |
| D3: 示例展示 | - | 11 | - | - | 11 |
| D4: 生态成熟 | - | - | 4 | 14 | 18 |
| **总计** | **21** | **34** | **8** | **14** | **77** |

### 按类型统计

| 类型 | 数量 |
|------|------|
| 工具任务 | 22项 (D1:6 + D2:6 + D3:3 + D4:7) |
| 文档任务 | 55项 (来自 Issue #47) |
| **总计** | **77项** |

---

## 🎯 当前重点

我们根据优先级和需求选择任务：

**新用户**：从 [D1: 环境完善](directions/d1-environment) P0 开始
**追求效率**：专注于 [D2: 工具完备](directions/d2-tools) P1
**展示能力**：跳到 [D3: 示例展示](directions/d3-examples) P1
**深度参与**：致力于 [D4: 生态成熟](directions/d4-ecosystem) P2/P3

---

## ✅ 历史里程碑 v0.5 已完成（2026-03）

### 主要成果

- [x] **Mainline 内核迁移**：完成 Linux 主线内核（v6.12）到 i.MX6ULL 的迁移
- [x] **GT911 触摸屏驱动**：支持多点触控，为 QT 应用提供基础
- [x] **QT6 交叉编译流水线**：一键编译 QT6 应用
- [x] **网络启动支持**：TFTP/NFS 网络启动，大幅提升开发效率
- [x] **补丁自动化工具**：简化补丁管理流程
- [x] **WSL2 Mirrored 网络模式**：Windows 用户无缝使用
- [x] **完整教程体系**：持续增长的教程内容覆盖完整学习路径

**详细记录**：参见 [v0.5 归档](archive/v0.5-milestone)

---

## 🎯 示例项目概览

### 🥇 旗舰项目（展会级）

| 项目 ID | 项目名称 | 所属方向 | 详情 |
|---------|----------|----------|------|
| PROJ-001 | 便携式环境监测站 | D3 | [查看](projects/proj-001-env-monitor) |
| PROJ-002 | 嵌入式图像分析仪 | D3 | [查看](projects/proj-002-image-analyzer) |

### 🥈 精品项目（技术深度）

| 项目 ID | 项目名称 | 所属方向 |
|---------|----------|----------|
| PROJ-003 | 网络协议分析仪 | D4 |
| PROJ-004 | 复古掌机模拟器 | D4 |
| PROJ-005 | 工业级串口/总线调试工具 | D4 |
| PROJ-006 | 气象数据记录仪 + Web 服务器 | D4 |

### 🥉 快速项目（1-2 个月）

| 项目 ID | 项目名称 | 所属方向 |
|---------|----------|----------|
| PROJ-007 | 陀螺仪 3D 姿态展示仪 | D4 |
| PROJ-008 | 二维码名片生成器 | D4 |
| PROJ-009 | 触摸屏手写白板 | D4 |
| PROJ-010 | 系统性能监视器 | D4 |

---

## 📁 文档结构

```
document/todo/
├── roadmap.md             # 总体路线图（从这里开始！）
├── todo.md                # 本文件：任务总览
├── directions/            # 发展方向
│   ├── d1-environment.md  # D1: 环境完善 (25项)
│   ├── d2-tools.md        # D2: 工具完备 (23项)
│   ├── d3-examples.md     # D3: 示例展示 (11项)
│   └── d4-ecosystem.md    # D4: 生态成熟 (18项)
├── projects/              # 示例项目详情
├── archive/               # 已完成归档
│   └── v0.5-milestone.md
```

---

## 🔗 相关链接

- **快速开始**：[../QUICK_START.md](../QUICK_START.md)
- **教程目录**：[../tutorial/](../tutorial/)
- **GitHub Issues**：[提交问题](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)

---

## 📞 如何贡献

我们欢迎所有形式的贡献！

1. 查看 [roadmap.md](roadmap.md) 了解项目规划
2. 根据你的兴趣选择一个方向
3. 在该方向中选择合适的任务
4. 在 GitHub Issues 中声明你的意图
5. 提交 Pull Request

详见：GitHub 仓库的贡献指南

---

**让嵌入式 Linux 开发变得简单！** 🚀
