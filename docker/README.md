# IMX-Forge Docker 开发环境

基于 Docker 的 i.MX6ULL 嵌入式 Linux 开发环境，预装所有必需的工具链和依赖。

## 特性

- ✅ **Ubuntu 24.04** 基础镜像
- ✅ **ARM GNU Toolchain 15.2.rel1** 交叉编译工具链
- ✅ **多阶段构建** 优化镜像大小
- ✅ **非 root 用户** 运行（安全）
- ✅ **预装所有依赖** 开箱即用

## 快速开始

### 方式一：直接拉取预构建镜像（推荐）

我们已经为你构建好了 Docker 镜像，可以直接拉取使用：

```bash
# 拉取最新版本
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest

# 启动开发环境
cd imx-forge
docker run -it --rm -v $(pwd):/workspace ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
```

使用特定版本：
```bash
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:v1.0.0
```

### 方式二：本地构建

如需自定义或使用国内镜像优化版，可以本地构建：

#### 0. 国内用户加速（推荐）

如果你在中国大陆，建议使用国内镜像源版本：

```bash
cd docker

# 方法 1：配置 Docker 镜像加速器（推荐）
sudo mkdir -p /etc/docker
sudo cp daemon.json /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker

# 方法 2：使用国内优化的 Dockerfile
DOCKER_BUILDKIT=1 sudo docker build -f Dockerfile.cn -t imx-forge:latest .
```

### 1. 构建镜像

```bash
cd docker

# 使用 BuildKit 构建（推荐）
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .

# 或使用传统方式
docker build -t imx-forge:latest .
```

构建时间：约 5-10 分钟（取决于网络速度）

### 2. 运行容器

#### 基本用法

```bash
docker run -it --rm \
    -v $(pwd)/..:/workspace \
    imx-forge:latest
```

#### 挂载项目目录

```bash
docker run -it --rm \
    -v /path/to/imx-forge:/workspace \
    -v /path/to/output:/workspace/out \
    imx-forge:latest
```

#### 使用 USB 设备（烧录）

```bash
docker run -it --rm \
    --privileged \
    -v /dev:/dev \
    -v $(pwd)/..:/workspace \
    imx-forge:latest
```

### 3. 编译项目

进入容器后，可以使用以下命令：

```bash
./scripts/build_helper/build-uboot.sh      # 编译 U-Boot
./scripts/build_helper/build-linux.sh      # 编译 Linux 内核
./scripts/build_helper/build-busybox.sh    # 编译 BusyBox
./scripts/release-all.sh                   # 一键构建所有组件
```

## 镜像信息

### 大小

- 最终镜像大小：约 2GB（截至文档更新时，实际大小可能存在波动）
- 构建阶段镜像：约 2.5GB（仅构建时使用）

### 包含的工具

| 工具 | 版本/说明 |
|------|----------|
| ARM GNU Toolchain | 15.2.rel1 |
| build-essential | GCC, Make 等 |
| device-tree-compiler | 设备树编译器 |
| u-boot-tools | U-Boot 工具 |
| python3-pyelftools | Python ELF 工具 |
| 其他依赖 | bc, bison, flex, swig 等 |

## 高级用法

### 自定义用户 ID

如果你的宿主机用户 ID 不是 1000，可以自定义：

```bash
docker build \
    --build-arg USER_ID=$(id -u) \
    --build-arg GROUP_ID=$(id -g) \
    -t imx-forge:latest \
    .
```

### 使用特定工具链版本

```bash
docker build \
    --build-arg TOOLCHAIN_VERSION=15.2.rel1 \
    -t imx-forge:latest \
    .
```

### 持久化容器

创建一个持久化的开发容器：

```bash
docker run -dit \
    --name imx-dev \
    -v $(pwd)/..:/workspace \
    imx-forge:latest

docker exec -it imx-dev bash
```

### Docker Compose

创建 `docker-compose.yml`：

```yaml
version: '3'
services:
  imx-forge:
    build: .
    image: imx-forge:latest
    volumes:
      - ..:/workspace
      - ./out:/workspace/out
    stdin_open: true
    tty: true
    privileged: true
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0
```

运行：

```bash
docker-compose run imx-forge
```

## 验收测试

### 测试工具链

```bash
arm-none-linux-gnueabihf-gcc --version
```

预期输出：
```
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
```

### 测试 U-Boot 编译

```bash
cd /workspace
./scripts/build_helper/build-uboot.sh
```

### 测试 Linux 内核编译

```bash
cd /workspace
./scripts/build_helper/build-linux.sh
```

### 测试 BusyBox 编译

```bash
cd /workspace
./scripts/build_helper/build-busybox.sh
```

## 常见问题

### Q: 镜像构建失败，提示网络错误？

A: 工具链下载需要访问 ARM 官网，可能需要配置代理：

```bash
docker build \
    --build-arg http_proxy=http://proxy:port \
    --build-arg https_proxy=http://proxy:port \
    -t imx-forge:latest \
    .
```

### Q: 容器内无法访问 USB 设备？

A: 需要使用 `--privileged` 参数或将设备挂载到容器：

```bash
docker run -it --rm \
    --privileged \
    -v /dev:/dev \
    imx-forge:latest
```

### Q: 编译产物权限问题？

A: 使用与宿主机相同的用户 ID 构建：

```bash
docker build \
    --build-arg USER_ID=$(id -u) \
    --build-arg GROUP_ID=$(id -g) \
    -t imx-forge:latest \
    .
```

### Q: 国内用户 ghcr.io 拉取镜像慢怎么办？

A: 可以配置 Docker 镜像加速器。以下是国内常用的镜像加速源：

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

**注意**: 大部分国内镜像加速器主要针对 Docker Hub，对 ghcr.io 的加速效果有限。如果仍然较慢，建议使用本地构建方式（Dockerfile.cn）。

### Q: 如何清理构建缓存？

A: Docker 构建会占用磁盘空间，可以定期清理：

```bash
docker system prune -a
```

## 开发建议

1. **使用卷挂载**：将 `out` 目录单独挂载，避免编译产物占用容器空间
2. **定期更新**：定期重新构建镜像以获取最新工具链和依赖
3. **CI/CD 集成**：可以在 CI/CD 流水线中使用此镜像进行自动化构建

## 许可证

MIT License

## 相关链接

- [IMX-Forge 主项目](../README.md)
- [ARM GNU Toolchain](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain)
- [Docker 官方文档](https://docs.docker.com/)
