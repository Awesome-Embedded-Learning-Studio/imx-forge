# IMX-Forge 待办事项

> **最后更新**：2026-04-06
> **当前历史里程碑**：v0.5
> **正式 release 策略**：从 v0.1.0 开始
> **查看详情**：[roadmap.md](roadmap.md)

---

## 📑 快速导航

- 🗺️ **总体路线图**：[roadmap.md](roadmap.md)
- 📁 **发展方向**：
  - [D1: 环境完善](directions/d1-environment) - 开发环境搭建
  - [D2: 工具完备](directions/d2-tools) - 提升开发效率
  - [D3: 示例展示](directions/d3-examples) - 展示项目能力
  - [D4: 生态成熟](directions/d4-ecosystem) - 建设完整生态
- 🎯 **示例项目**：[projects/](projects/)
- 📦 **已完成**：[archive/v0.5-milestone.md](archive/v0.5-milestone)

---

## 🎯 当前重点：根据兴趣选择方向

我们不再设定严格的里程碑和时间线，而是根据优先级和需求选择任务。

### 如何选择方向？

**新用户**：从 [D1: 环境完善](directions/d1-environment) 开始
**追求效率**：专注于 [D2: 工具完备](directions/d2-tools)
**展示能力**：跳到 [D3: 示例展示](directions/d3-examples)
**深度参与**：致力于 [D4: 生态成熟](directions/d4-ecosystem)

---

## 📊 项目进度

```
[✅] v0.1 - 基础框架搭建
[✅] v0.3 - U-Boot 和内核移植
[✅] 历史里程碑 v0.5 - Mainline 内核迁移 + QT6 支持
[🚧] 当前重点：环境完善与工具开发
[📋] 方向 D1：环境完善
[📋] 方向 D2：工具完备
[📋] 方向 D3：示例展示
[📋] 方向 D4：生态成熟
```

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
├── projects/              # 示例项目详情
├── directions/            # 发展方向
│   ├── d1-environment.md  # D1: 环境完善
│   ├── d2-tools.md        # D2: 工具完备
│   ├── d3-examples.md     # D3: 示例展示
│   └── d4-ecosystem.md    # D4: 生态成熟
├── projects/              # 示例项目详情
│   ├── proj-001-env-monitor.md
│   └── proj-002-image-analyzer.md
└── archive/               # 已完成归档
    └── v0.5-milestone.md
```

---

## 🔗 相关链接

- **快速开始**：[../QUICK_START](../QUICK_START)
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

> 💡 **提示**：新用户建议先阅读 [roadmap.md](roadmap.md) 了解项目全貌，然后根据兴趣选择合适的发展方向。
