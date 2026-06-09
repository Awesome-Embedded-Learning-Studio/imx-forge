# 快速开始

IMX-Forge 提供两种开发环境方式，都经过充分测试：

- **Docker（推荐 ⭐）** —— 跨平台，5 分钟配置完成
- **WSL2 + Docker（Windows 用户首选）** —— 无需双系统，原生开发体验

---

## 🐳 Docker 环境（推荐）

### 系统要求

- Linux / macOS / Windows（需 WSL2）
- Docker Engine 20.10+
- Docker Compose（可选）

### 快速启动

```bash
# 1. 克隆项目（含子模块）
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge

# 2. 构建 Docker 镜像（国内用户使用 Dockerfile.cn）
cd docker && docker build -t imx-forge:latest . && cd ..

# 3. 运行容器并开始编译
docker run -it --rm -v $(pwd):/workspace imx-forge:latest

# 在容器内执行一键构建
./scripts/release-all.sh
```

### 国内用户加速

```bash
cd docker
docker build -f Dockerfile.cn -t imx-forge:latest .
```

### 串口和烧录支持

```bash
# 添加设备访问权限
docker run -it --rm \
  --device /dev/ttyUSB0 \
  --device /dev/ttyUSB1 \
  -v $(pwd):/workspace \
  imx-forge:latest
```

**详细文档**: [Docker 开发环境指南](docker/README.md)

---

## 🪟 WSL2 + Docker（Windows 用户）

### 为什么选择 WSL2？

- ✅ 无需双系统，Windows 下原生开发
- ✅ 完整的 Linux 工具链支持
- ✅ Docker 与 WSL2 无缝集成
- ✅ Mirrored 网络模式直接访问开发板
- ✅ USB 设备直通（烧录、串口调试）

### 安装步骤

#### 1. 安装 WSL2

```powershell
# PowerShell（管理员）
wsl --install
```

重启后按提示完成 Ubuntu 安装。

#### 2. 配置 Mirrored 网络模式

编辑 `%USERPROFILE%\.wslconfig`：

```ini
[wsl2]
networkingMode=mirrored
```

重启 WSL：

```powershell
wsl --shutdown
```

#### 3. 安装 Docker Desktop

1. 下载 [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. Settings → Resources → WSL Integration
3. 启用你的 WSL2 发行版

#### 4. 验证安装

```bash
# 在 WSL2 终端中
docker --version
docker run hello-world
```

#### 5. 开始使用

在 WSL2 终端中执行 Docker 环境的命令即可。

**详细教程**: [WSL2 + Docker 配置指南](document/tutorial/docker/01_docker_basics.md#wsl2-安装)

---

## 💻 主机环境（高级用户）

如果你希望在主机上直接开发：

### 系统要求

- Ubuntu 24.04+ / Debian 12+ / Arch Linux
- ARM GNU Toolchain 15.2.rel1
- 其他依赖见 [Dockerfile](docker/Dockerfile)

### 安装工具链

```bash
# 下载 ARM GNU Toolchain 15.2.rel1
wget https://developer.arm.com/downloads/-/arm-gnu-toolchain-15.2-rel1-x86_64-arm-none-linux-gnueabihf

# 解压到 /opt/
sudo tar xf arm-gnu-toolchain-*.tar.xz -C /opt/

# 添加到 PATH
echo 'export PATH=/opt/arm-gnu-toolchain-*/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 验证
arm-none-linux-gnueabihf-gcc --version
```

### 编译项目

```bash
./scripts/release-all.sh
```

---

## 🚀 下一步

快速开始后，建议按以下顺序学习：

1. [Docker 教程](document/tutorial/docker/) —— 熟悉开发环境
2. [工具链教程](document/tutorial/start/) —— 理解交叉编译
3. [U-Boot 教程](document/tutorial/uboot/) —— Bootloader 基础
4. [内核教程](document/tutorial/kernel/) —— Linux 内核开发
5. [驱动开发](document/tutorial/driver/) —— 编写你的第一个驱动

**完整教程**: [教程目录](document/tutorial/index.md)

---

## 🆘 常见问题

### Q: Docker 构建失败？

A: 确保使用 `DOCKER_BUILDKIT=1`：

```bash
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
```

### Q: WSL2 无法访问开发板？

A: 确保配置了 Mirrored 网络模式，并检查防火墙设置。

### Q: 串口权限被拒绝？

A: 将用户添加到 dialout 组：

```bash
sudo usermod -aG dialout $USER
# 重新登录后生效
```

### Q: 更多问题？

A: 查看 [Docker FAQ](docker/README.md#常见问题) 或提交 [GitHub Issue](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
