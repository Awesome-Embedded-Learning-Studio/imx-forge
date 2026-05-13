<PageHeader icon="🐳" title="Docker 镜像发布" description="IMX-Forge 预构建 Docker 镜像发布流程，用户可直接拉取使用" />

## 概述

IMX-Forge 提供**预构建的 Docker 镜像**，用户无需手动构建，可直接拉取使用。镜像通过 GitHub Actions 自动构建并发布到 GitHub Container Registry。

## 镜像标签策略

| 标签 | 获取方式 | 稳定性 | 用途 |
|------|----------|--------|------|
| `latest` | 手动触发 / 发布 tag | <Badge type="tip" text="稳定" /> | 推荐给大多数用户 |
| `preview` | 手动触发 | <Badge type="warning" text="实验性" /> | 测试新功能、尝鲜 |
| `v1.0.0` 等 | 发布 tag | <Badge type="tip" text="稳定" /> | 锁定特定版本 |

## 发布流程

### 开发者工作流

<StepFlow>
  <StepItem icon="💻" title="开发完成" description="推送到 main 分支" />
  <StepItem icon="⚡" title="CI 验证" description="等待 CI 测试通过" />
  <StepItem icon="🐳" title="构建 preview" description="手动触发 preview 镜像" />
  <StepItem icon="🧪" title="本地测试" description="拉取 preview 验证" />
  <StepItem icon="✅" title="构建 latest" description="手动触发 latest 镜像" />
  <StepItem icon="🏷️" title="正式发布" description="创建版本 tag" />
</StepFlow>

### 手动触发构建

1. 进入 [GitHub Actions](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions)
2. 选择 **Docker Image Publish** workflow
3. 点击 **Run workflow**
4. 选择标签：
   - `latest` - 稳定版本
   - `preview` - 预览/测试版本

### 正式发布

```bash
# 创建版本 tag
git tag v1.0.0
git push origin v1.0.0

# 自动触发构建：v1.0.0, v1, latest
```

## 镜像内容

镜像基于 **Ubuntu 24.04**，包含：

- **ARM GNU Toolchain 15.2.rel1** - 交叉编译工具链
- **构建工具** - build-essential, cmake, ninja-build, meson
- **内核工具** - bison, flex, device-tree-compiler
- **U-Boot 工具** - u-boot-tools
- **Python 工具** - pyelftools
- **SSL/TLS** - libssl-dev, libgnutls28-dev
- **音频库** - libpulse-dev, libasound2-dev

镜像大小：约 **2GB**（截至文档更新时，实际大小可能存在波动）

## 用户使用

### 拉取镜像

```bash
# 稳定版（推荐）
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest

# 预览版（尝鲜）
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:preview

# 特定版本
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:v1.0.0
```

### 运行容器

```bash
# 基本用法
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/awesome-embedded-learning-studio/imx-forge:latest

# 使用 USB 设备（烧录）
docker run -it --rm --privileged -v /dev:/dev \
  -v $(pwd):/workspace \
  ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
```

### 验证镜像

```bash
# 验证工具链
docker run --rm ghcr.io/awesome-embedded-learning-studio/imx-forge:latest \
  arm-none-linux-gnueabihf-gcc --version

# 预期输出
# arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1) 15.2.1 20251203
```

## 国内用户加速

如果 ghcr.io 拉取较慢，可配置 Docker 镜像加速：

```bash
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

::: warning 注意
大部分国内镜像加速器主要针对 Docker Hub，对 ghcr.io 的加速效果有限。如果仍然较慢，建议使用本地构建方式。
:::

## 故障排查

### 问题：拉取失败

**原因**：镜像不存在或标签错误

**解决**：
```bash
# 查看可用标签
gh api repos/Awesome-Embedded-Learning-Studio/imx-forge/packages | jq -r '.[].name'
```

### 问题：工具链不工作

**原因**：镜像损坏或构建问题

**解决**：重新构建镜像或使用其他版本

## 相关链接

- [Docker 开发环境指南](../tutorial/docker/02_imx_forge_docker_guide.md)
- [GitHub Actions](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions)
- [GitHub Container Registry](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/pkgs/container/imx-forge)

<ChapterNav variant="sub">
  <ChapterLink href="index.md" variant="sub">← 返回 CI/CD 文档</ChapterLink>
</ChapterNav>
