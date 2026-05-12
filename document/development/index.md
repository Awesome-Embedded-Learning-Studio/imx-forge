<PageHeader icon="🛠️" title="开发指南" description="开发 IMX-Forge 相关的工具和指南" />

<ChapterNav variant="sub">
  <ChapterLink href="ENVIRONMENT_SETUP.md" variant="sub">环境搭建 —— 开发环境配置</ChapterLink>
</ChapterNav>

::: info 开发环境要求
**必需：** Ubuntu 22.04+ / WSL2 · ARM GNU Toolchain 15.2 · Git · Node.js 18+ & pnpm（文档构建）

**可选：** QT6 <Badge type="info" text="图形界面" /> · QEMU <Badge type="info" text="模拟器" />
:::

::: details 开发工作流
```bash
# 1. 克隆项目
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git

# 2. 创建分支
git checkout -b feature/your-feature

# 3. 开发和测试
./scripts/release-all.sh

# 4. 提交 PR
```
:::

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回文档首页</ChapterLink>
</ChapterNav>
