# IMX-Forge 项目路线图

> **最后更新**：2026-04-06
> **当前历史里程碑**：v0.5
> **正式 release 策略**：从 v0.1.0 开始

---

## 📊 项目进度概览

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

## 💡 如何选择方向

根据你的兴趣和当前状态选择合适的发展方向：

**如果你是新用户：**
- 从 **D1：环境完善** 开始 - 搭建开发环境
- 然后根据兴趣选择其他方向

**如果你想提升开发效率：**
- 专注于 **D2：工具完备** - 开发辅助工具

**如果你想展示项目能力：**
- 跳到 **D3：示例展示** - 创建旗舰项目

**如果你想深度参与：**
- 致力于 **D4：生态成熟** - 建设完整生态

---

## 🎯 发展方向

### 📍 方向 D1：环境完善

**核心目标**：
- ✅ 提供开箱即用的开发环境
- 📦 容器化构建系统
- 🛠️ 完善辅助工具链
- 📚 更新文档体系

**如何开始**：
根据你的需求选择任务（详见 [D1 详情](./directions/d1-environment)）：
- 新用户：D1-004 (env-init.sh) → D1-001 (Dockerfile)
- VS Code 用户：D1-001 (Dockerfile) → D1-003 (Devcontainer)
- 需要烧录：D1-004 (env-init.sh) → D1-005 (flash.sh)

**详细规划**：参见 [D1 详情](./directions/d1-environment)

---

### 📍 方向 D2：工具完备

**核心目标**：
- 🔧 完整的辅助脚本集
- ✅ CI/CD 基础建立
- 📖 板卡接入规范
- 🎯 多板卡支持框架

**如何开始**：
根据你的需求选择任务（详见 [D2 详情](./directions/d2-tools)）：
- 提升效率：D2-001 (menuconfig.sh) → D2-002 (clean.sh)
- 多板卡支持：D2-003 (select-board.sh) → D2-004 (板卡接入文档)
- 代码质量：D2-005 (CI - Patch 校验) → D2-006 (CI - Docker 构建)

**详细规划**：参见 [D2 详情](./directions/d2-tools)

---

### 📍 方向 D3：示例展示

**核心目标**：
- 🎨 QT6 完整应用示例
- 🏆 至少一个旗舰级项目
- 📸 完整的教程和演示
- 🌟 展示项目价值

**如何开始**：
根据你的兴趣选择任务（详见 [D3 详情](./directions/d3-examples)）：
- 必须先做：D3-001 (QT6 完整应用示例)
- IoT 方向：D3-002 (PROJ-001 环境监测站)
- 图像处理：D3-003 (PROJ-002 图像分析仪)

**详细规划**：参见 [D3 详情](./directions/d3-examples)

---

### 📍 方向 D4：生态成熟

**核心目标**：
- 🌐 多种 Rootfs 方案
- 🤖 完整的 CI/CD
- 🎮 多个精品项目
- 👥 活跃的社区

**如何开始**：
根据你的兴趣选择任务（详见 [D4 详情](./directions/d4-ecosystem)）：
- 系统构建：D4-001 (Buildroot) → D4-002 (Debian)
- DevOps：D4-003 (完善 CI/CD)
- 网络技术：D4-004 (PROJ-003 协议分析仪)
- 游戏开发：D4-005 (PROJ-004 游戏模拟器)

**详细规划**：参见 [D4 详情](./directions/d4-ecosystem)

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

**详细记录**：参见 [v0.5 归档](./archive/v0.5-milestone)

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
