# IMX-Forge 项目路线图

> **最后更新**：2026-06-14（对齐实际进度）
> **数据来源**：GitHub Issue #47 + 本地规划
> **当前发布里程碑**：v1.0.0（首个轻量可用版本）

---

## 📑 快速导航

- 📁 **按方向查看**：
  - [D1: 环境完善](./directions/d1-environment.md) - 35项
  - [D2: 工具完备](./directions/d2-tools.md) - 66项
  - [D3: 示例展示](./directions/d3-examples.md) - 11项
  - [D4: 生态成熟](./directions/d4-ecosystem.md) - 18项
- 🔗 **GitHub Issue #47**：[路线任务追踪](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/47)
- 📦 **已完成**：v0.5 里程碑（Mainline 内核迁移 + QT6 支持）

---

## 📊 项目进度概览

```
[✅] v0.1 - 基础框架搭建
[✅] v0.3 - U-Boot 和内核移植
[✅] 历史里程碑 v0.5 - Mainline 内核迁移 + QT6 支持
[✅] v1.0.0 - SD/eMMC 完整构建→烧录→启动闭环
[🚧] 当前阶段：文档建设 + 工具开发
```

---

## 📊 优先级说明

```
P0 ──► 主线闭环，必须完成 (新用户第一次启动的完整路径)
P1 ──► 重要功能，尽快完成 (应用开发+调试能力)
P2 ──► 优化体验，逐步完善 (工作流+高级工具)
P3 ──► 可选补充 (参考资源+更多项目)
```

---

## 💡 如何选择方向

根据你的兴趣和当前状态选择合适的发展方向：

**如果你是新用户：**
- 从 **D1：环境完善** P0 开始 - 搭建开发环境
- 然后根据兴趣选择其他方向

**如果你想提升开发效率：**
- 专注于 **D2：工具完备** P1 - 开发辅助工具

**如果你想展示项目能力：**
- 跳到 **D3：示例展示** P1 - 创建旗舰项目

**如果你想深度参与：**
- 致力于 **D4：生态成熟** P2/P3 - 建设完整生态

---

## 🎯 发展方向

### 📍 方向 D1：环境完善 (35项)

**核心目标**：
- ✅ 提供开箱即用的开发环境
- 📦 容器化构建系统
- 🛠️ 完善辅助工具链
- 📚 完整文档体系

**优先级分布**：
| P0 | P1 | P2 | 总计 |
|----|----|----| ---- |
| 31 | 3 | 1 | 35 |

**详细规划**：[D1 详情](./directions/d1-environment.md)

---

### 📍 方向 D2：工具完备 (66项)

**核心目标**：
- 🔧 完整的辅助脚本集
- ✅ CI/CD 基础建立
- 📖 板卡接入规范
- 🎯 多板卡支持框架

**优先级分布**：
| P0 | P1 | P2 | 总计 |
|----|----|----| ---- |
| - | 55 | 11 | 66 |

**详细规划**：[D2 详情](./directions/d2-tools.md)

---

### 📍 方向 D3：示例展示 (11项)

**核心目标**：
- 🎨 QT6 完整应用示例
- 🏆 至少一个旗舰级项目
- 📸 完整的教程和演示
- 🌟 展示项目价值

**优先级分布**：
| P0 | P1 | P2 | P3 | 总计 |
|----|----|----|----| ---- |
| - | 11 | - | - | 11 |

**详细规划**：[D3 详情](./directions/d3-examples.md)

---

### 📍 方向 D4：生态成熟 (18项)

**核心目标**：
- 🌐 多种 Rootfs 方案
- 🤖 完整的 CI/CD
- 🎮 多个精品项目
- 👥 活跃的社区

**优先级分布**：
| P0 | P1 | P2 | P3 | 总计 |
|----|----|----|----| ---- |
| - | - | 4 | 14 | 18 |

**详细规划**：[D4 详情](./directions/d4-ecosystem.md)

---

## 📋 示例项目清单

### 🥇 旗舰项目（展会级）

| 项目 ID | 项目名称 | 技术栈 | 所属方向 |
|---------|----------|--------|----------|
| PROJ-001 | [便携式环境监测站 + 云端数据看板](./projects/proj-001-env-monitor) | C + Qt + MQTT + 驱动 | D3 |
| PROJ-002 | [嵌入式图像采集与分析仪](./projects/proj-002-image-analyzer) | C++ + Qt + OpenCV + V4L2 | D3 |

### 🥈 精品项目（技术深度）

| 项目 ID | 项目名称 | 技术栈 | 所属方向 |
|---------|----------|--------|----------|
| PROJ-003 | 网络协议分析仪 | C + Qt + libpcap | D4 |
| PROJ-004 | 复古掌机模拟器 | C + Qt + 模拟器 | D4 |
| PROJ-005 | 工业级串口/总线调试工具 | C + Qt + Lua | D4 |
| PROJ-006 | 气象数据记录仪 + Web 服务器 | C + Qt + Web 服务器 | D4 |

### 🥉 快速项目（1-2 个月）

| 项目 ID | 项目名称 | 技术栈 | 所属方向 |
|---------|----------|--------|----------|
| PROJ-007 | 陀螺仪 3D 姿态展示仪 | C + Qt + IIC 驱动 | D4 |
| PROJ-008 | 二维码名片生成器 | C + Qt + ZBar | D4 |
| PROJ-009 | 触摸屏手写白板 | C + Qt + 触摸驱动 | D4 |
| PROJ-010 | 系统性能监视器 | C + Qt + procfs | D4 |

---

## ✅ 已完成工作

### 历史里程碑 v0.5（2026-03）

**完成时间**：2026 年 3 月
**主要成果**：
- ✅ Mainline 内核迁移完成
- ✅ GT911 触摸屏驱动支持
- ✅ QT6 交叉编译流水线
- ✅ 网络启动支持（TFTP/NFS）
- ✅ 补丁自动化工具
- ✅ WSL2 Mirrored 网络模式支持
- ✅ 持续增长的完整教程体系

**详细记录**：v0.5 里程碑已完成 Mainline 内核迁移和 QT6 支持

---

## 🎖️ 贡献者

感谢所有为 IMX-Forge 项目做出贡献的开发者！

- **核心维护者**：Awesome Embedded Learning Studio
- **贡献者**：参见 [GitHub 贡献者页面](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/graphs/contributors)

---

## 📞 联系方式

- **项目主页**：[https://github.com/Awesome-Embedded-Learning-Studio/imx-forge](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge)
- **问题反馈**：[GitHub Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
- **讨论交流**：[GitHub Discussions](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/discussions)

---

**让嵌入式 Linux 开发变得简单！** 🚀
