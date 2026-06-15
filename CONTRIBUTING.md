# 贡献指南

感谢你对 IMX-Forge 项目的关注！我们欢迎各种形式的贡献。

## 📋 目录

- [如何贡献](#如何贡献)
- [环境设置](#环境设置)
- [开发工作流](#开发工作流)
- [代码规范](#代码规范)
- [获取帮助](#获取帮助)

---

## 🤝 如何贡献

我们欢迎以下三种贡献方式：

### 1. 代码贡献

- 🐛 修复 Bug
- ✨ 添加新功能
- ♻️ 代码重构
- 📝 完善文档
- 🧪 添加测试

### 2. 文档贡献

- 修正错别字和错误
- 改进文档结构和表达
- 翻译文档
- 添加示例和教程

### 3. 反馈和建议

- 提出 Bug 报告
- 提出功能请求
- 参与讨论
- 分享使用经验

---

## 🔧 环境设置

### 系统要求

**开发主机**：
- Ubuntu 22.04+ 或 WSL2 (Ubuntu 22.04/24.04)
- CPU: 4 核心以上
- 内存: 8GB 以上
- 磁盘: 20GB 可用空间

**目标硬件**：
- NXP i.MX6ULL 开发板
- 串口模块（CP2102/CH340/FT232）
- SD 卡 + 读卡器

### 依赖安装

我们推荐使用 Docker 开发环境进行贡献，确保环境一致性：

#### 方式一：Docker 开发环境（推荐）

**优点**：
- ✅ 环境统一，避免"在我机器上能跑"问题
- ✅ 开箱即用，无需配置工具链和依赖
- ✅ 适合团队协作

**快速开始**：

```bash
# 1. 构建 Docker 镜像
cd docker
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
cd ..

# 2. 运行容器
docker run -it --rm -v $(pwd):/workspace imx-forge:latest

# 3. 在容器内开发
# （所有工具链和依赖已预装）
```

**详细文档**：
- [Docker 开发环境](docker/README.md)
- [Docker 教程](document/tutorial/docker)

#### 方式二：主机环境

如果您希望在主机上直接开发，请参考：
- [README.md - 5分钟快速体验](README.md#-5分钟快速体验)
- [QUICK_START.md](document/QUICK_START.md)

### 快速验证

**Docker 环境**：

```bash
# 运行容器并验证
docker run -it --rm -v $(pwd):/workspace imx-forge:latest

# 在容器内执行
cd /workspace
./scripts/release-all.sh
```

**主机环境**：

```bash
cd /path/to/imx-forge

# 一键构建所有组件（NXP BSP 内核）
./scripts/release-all.sh

# 或指定只构建某一阶段
./scripts/release-all.sh --stage 1  # 只构建 U-Boot
./scripts/release-all.sh --stage 2  # 只构建内核
./scripts/release-all.sh --stage 3  # 只构建 BusyBox
```

---

## 🔄 开发工作流

### 分支策略

我们使用以下分支策略：

- **`main`** - 主分支，保持稳定
- **`feature/*`** - 功能开发分支
- **`fix/*`** - Bug 修复分支

#### 提交信息格式

我们遵循语义化提交规范：

```
type(scope): subject

body（可选）

footer（可选）
```

**Type 类型**：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `refactor`: 代码重构
- `test`: 测试相关
- `chore`: 构建/工具链相关

**示例**：

```bash
# 新功能
git commit -s -m "feat(uboot): add support for custom board configuration"

# Bug 修复
git commit -s -m "fix(kernel): resolve Ethernet driver initialization issue"

# 文档更新
git commit -s -m "docs: update Quick Start guide for WSL2"
```

### Pull Request 流程

#### 1. Fork 项目

点击 GitHub 页面右上角的 "Fork" 按钮。

#### 2. 克隆 Fork 仓库

```bash
git clone https://github.com/YOUR_USERNAME/imx-forge.git
cd imx-forge
```

#### 3. 创建分支

```bash
git checkout -b feature/your-feature-name
# 或
git checkout -b fix/your-bug-fix
```

#### 4. 进行更改并提交

```bash
# 进行你的更改
git add .
git commit -s -m "feat: add your feature"
```

#### 5. 推送到 Fork 仓库

```bash
git push origin feature/your-feature-name
```

#### 6. 创建 Pull Request

1. 访问你的 Fork 仓库页面
2. 点击 "Compare & pull request"
3. 填写 PR 描述：
   - 清晰的标题
   - 详细的描述
   - 关联的 Issue（如果有）
   - 测试情况

#### 7. 等待 Code Review

- 维护者会尽快审查你的 PR
- 根据反馈进行修改
- 响应评论和建议

#### 8. 合并

- PR 被批准后，维护者会合并代码
- 分支可能会被删除

---

## 📐 代码规范

### 代码风格

我们使用 `.clang-format` 来统一代码风格。

#### C/C++ 代码风格

- **缩进**：4 空格
- **命名**：驼峰命名（`myFunction`）
- **指针**：左对齐（`int* a`）
- **大括号**：Allman 风格

#### 格式化代码

```bash
# 格式化单个文件
clang-format -i file.c

# 格式化整个目录
find . -name "*.c" -o -name "*.h" | xargs clang-format -i
```

#### IDE 集成

项目包含 `.clangd` 配置，支持：
- VS Code (C/C++ 扩展)
- Vim/Neovim (coc-clangd)
- Emacs (lsp-mode)

### 命名规范

#### C/C++

- 函数：驼峰命名 `myFunction()`
- 变量：驼峰命名 `myVariable`
- 常量：大写下划线 `MAX_SIZE`
- 类型：驼峰命名 + _t 后缀 `typedef struct MyStruct MyStruct_t;`

#### Shell 脚本

- 函数：小写下划线 `my_function()`
- 变量：小写下划线 `my_variable`
- 常量：大写下划线 `MAX_SIZE`

#### 文件名

- C/C++：小写下划线或小写连字符 `my_file.c` / `my-file.h`
- Shell：小写下划线 `my_script.sh`
- Markdown：小写连字符 `read-me.md`

### 测试要求

#### 编译测试

所有代码必须能够成功编译：

```bash
./scripts/release-all.sh
```

#### 功能测试

- 在 i.MX6ULL 开发板上验证功能
- 确保没有引入新的 Bug
- 测试相关的边缘情况

#### 文档更新

- 同步更新相关文档
- 添加必要的注释

---

## 💬 获取帮助

### 沟通渠道

- **GitHub Issues**: [提交问题](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
- **GitHub Discussions**: [参与讨论](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/discussions)

### 文档资源

- [快速开始](document/QUICK_START.md)
- [项目规划](document/todo/roadmap.md)
- [教程目录](document/tutorial/)
- [示例代码](examples/)

### 常见问题

#### Q: 我是一名新手，可以从哪里开始？

A: 我们建议从以下方式开始：
1. 阅读 [快速开始指南](document/QUICK_START.md)
2. 尝试构建项目
3. 查看现有的 [Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)，寻找标记为 `good first issue` 的问题

#### Q: 我不太懂嵌入式开发，可以贡献吗？

A: 当然可以！我们需要各种形式的贡献：
- 📝 改进文档
- 🐛 报告 Bug
- 💡 提出建议
- 🌐 帮助其他用户
- 🎨 设计相关资源

#### Q: 如何报告 Bug？

A: 请通过 [GitHub Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues) 提交，包含：
- 清晰的标题
- 详细的问题描述
- 复现步骤
- 环境信息（操作系统、工具链版本等）
- 相关日志和截图

#### Q: 我的 PR 很久没有回复，怎么办？

A: 请：
1. 检查 PR 是否符合贡献指南
2. 确保 CI 检查通过
3. 在 PR 中 @ 相关维护者
4. 耐心等待，维护者都是志愿者

---

## 📄 许可证

通过贡献代码，你同意你的贡献将根据项目的 [MIT License](LICENSE) 进行许可。

---

## 🙏 再次感谢

感谢你花时间阅读贡献指南！

你的每一个贡献都能让 IMX-Forge 项目变得更好。

让我们一起让嵌入式 Linux 开发变得简单！ 🚀

---

**Sources:**
- [Auth0 Open Source Template](https://github.com/auth0/open-source-template/blob/master/GENERAL-CONTRIBUTING.md)
- [nayafia/contributing-template](https://github.com/nayafia/contributing-template)
- [GitHub Official Documentation](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)
- [开源项目优雅贡献指南 - OSCHINA](https://my.oschina.net/emacs_8006011/blog/19384066)
