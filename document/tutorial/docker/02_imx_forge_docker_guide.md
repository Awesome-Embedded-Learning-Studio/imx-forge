# IMX-Forge Docker 开发指南

## 目录

1. [快速开始](#快速开始)
2. [理解 Docker 镜像](#理解-docker-镜像)
3. [日常开发工作流](#日常开发工作流)
4. [高级用法](#高级用法)
5. [调试与烧录](#调试与烧录)
6. [性能优化](#性能优化)
7. [故障排除](#故障排除)
8. [最佳实践](#最佳实践)

---

## 快速开始

### 5分钟上手

适合想快速开始的开发者，详细原理请参考后续章节。

**前提条件**：
- 已安装 Docker（详见 [Docker 基础教程](01_docker_basics.md)）
- 至少 5GB 可用磁盘空间
- 建议内存 4GB 以上

**步骤 1：克隆项目**

```bash
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge
```

**步骤 2：构建 Docker 镜像**

```bash
cd docker

# 国内用户使用优化的 Dockerfile
DOCKER_BUILDKIT=1 docker build -f Dockerfile.cn -t imx-forge:latest .

# 国际用户使用标准 Dockerfile
# DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
```

构建时间约 5-10 分钟（取决于网络速度）。

**步骤 3：运行容器**

```bash
# 返回项目根目录
cd ..

# 运行容器
docker run -it --rm -v $(pwd):/workspace imx-forge:latest
```

**步骤 4：验证环境**

进入容器后，验证工具链：

```bash
arm-none-linux-gnueabihf-gcc --version
```

预期输出：
```
arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
Copyright (C) 2025 Free Software Foundation, Inc.
```

**步骤 5：开始编译**

```bash
# 一键构建所有组件
./scripts/release-all.sh

# 或分步构建
./scripts/build_helper/build-uboot.sh
./scripts/build_helper/build-linux.sh
./scripts/build_helper/build-busybox.sh
```

**步骤 6：查看输出**

编译产物在 `out/` 目录：

```bash
ls -la out/
```

容器退出后，编译产物仍保留在主机上。

---

## 理解 Docker 镜像

### 镜像结构

IMX-Forge Docker 镜像采用**多阶段构建**，优化镜像大小：

```
┌─────────────────────────────────────────┐
│   Build Stage（构建阶段，约 2.5GB）      │
│   - Ubuntu 24.04 基础镜像               │
│   - 构建工具（build-essential等）       │
│   - ARM 工具链（15.2.rel1）             │
│   - 所有编译依赖                        │
└──────────────┬──────────────────────────┘
               │ 复制编译产物
               ↓
┌─────────────────────────────────────────┐
│   Final Stage（最终镜像，约 1.5GB）      │
│   - Ubuntu 24.04 基础镜像               │
│   - ARM 工具链（15.2.rel1）             │
│   - 运行时依赖                          │
│   - 非 root 用户（ubuntu）              │
└─────────────────────────────────────────┘
```

**优势**：
- ✅ 减小最终镜像大小（从 2.5GB → 1.5GB）
- ✅ 构建工具不在最终镜像中，更安全
- ✅ 镜像分层，便于复用和更新

### 包含的工具

**交叉编译工具链**：
- ARM GNU Toolchain 15.2.rel1（arm-none-linux-gnueabihf-gcc）

**构建工具**：
- GCC, Make, CMake, Ninja
- device-tree-compiler（设备树编译器）
- u-boot-tools（mkimage 等）

**依赖库**：
- libssl-dev, libncurses-dev
- python3-pyelftools
- bc, bison, flex, swig

**其他工具**：
- git, wget, curl
- vim, nano, tree
- picocom, minicom（串口工具）

### 镜像大小优化

**为什么需要优化？**
- Docker 镜像包含完整的操作系统，可能很大
- 大镜像占用存储空间，拉取和推送慢

**优化技术**：
1. **多阶段构建**：分离构建环境和运行环境
2. **清理缓存**：在 Dockerfile 中使用 `rm -rf /var/lib/apt/lists/*`
3. **合并指令**：减少层数
4. **使用 .dockerignore**：排除不必要的文件

**镜像大小对比**：
- 优化前：约 2.5GB
- 优化后：约 1.5GB
- 减少约 40%

---

## 日常开发工作流

### 典型工作流程

```
┌─────────┐
│ 修改代码 │
└────┬────┘
     │
     ↓
┌─────────────┐
│ docker run  │ ← 运行容器（挂载项目目录）
└──────┬──────┘
       │
       ↓
┌─────────────┐
│   编译代码   │ ← 在容器内执行构建脚本
└──────┬──────┘
       │
       ↓
┌─────────────┐
│   测试验证   │ ← 在目标板上运行
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ git commit  │ ← 提交代码（在主机上）
└─────────────┘
```

### 方式一：临时容器（推荐）

**适用场景**：日常开发、编译、测试

```bash
docker run -it --rm -v $(pwd):/workspace imx-forge:latest
```

**参数说明**：
- `-it`：交互式终端
- `--rm`：容器退出后自动删除
- `-v $(pwd):/workspace`：挂载当前目录到 `/workspace`
- `imx-forge:latest`：镜像名称

**优点**：
- ✅ 用完即扔，不会留下僵尸容器
- ✅ 简单直接，无需管理容器生命周期
- ✅ 每次都是全新环境，避免状态污染

**示例**：

```bash
# 进入项目目录
cd ~/projects/imx-forge

# 运行容器
docker run -it --rm -v $(pwd):/workspace imx-forge:latest

# 在容器内
root@container:/workspace# ./scripts/build_helper/build-uboot.sh
root@container:/workspace# ./scripts/build_helper/build-linux.sh
root@container:/workspace# exit

# 容器自动删除，编译产物保留在主机
ls out/
```

### 方式二：持久化容器

**适用场景**：长期开发、需要保存容器内状态

```bash
# 创建持久容器
docker run -dit --name imx-dev -v $(pwd):/workspace imx-forge:latest

# 连接到容器
docker exec -it imx-dev bash

# 停止容器
docker stop imx-dev

# 启动已停止的容器
docker start imx-dev

# 删除容器
docker rm imx-dev
```

**优点**：
- ✅ 容器内状态（如安装的软件）会保留
- ✅ 可以随时连接和断开
- ✅ 适合长期项目

**缺点**：
- ⚠️ 需要手动管理容器生命周期
- ⚠️ 可能积累不需要的状态

### 方式三：Docker Compose

**适用场景**：复杂项目、团队协作

**1. 创建 `docker-compose.yml`**：

```yaml
version: '3.8'

services:
  imx-forge:
    build:
      context: .
      dockerfile: docker/Dockerfile
    image: imx-forge:latest
    volumes:
      - .:/workspace
      - ./out:/workspace/out
    working_dir: /workspace
    stdin_open: true
    tty: true
    privileged: true
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0
    environment:
      - CROSS_COMPILE=arm-none-linux-gnueabihf-
      - ARCH=arm
```

**2. 使用 Docker Compose**：

```bash
# 构建镜像
docker-compose build

# 启动服务
docker-compose run imx-forge

# 后台运行
docker-compose up -d

# 停止服务
docker-compose down

# 查看日志
docker-compose logs -f
```

**优点**：
- ✅ 配置文件化，便于版本控制
- ✅ 团队成员使用相同配置
- ✅ 支持多容器编排

---

## 高级用法

### 自定义工具链版本

如果需要使用不同版本的 ARM 工具链：

```bash
# 查看可用的工具链版本
# https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

# 构建时指定版本
docker build \
  --build-arg TOOLCHAIN_VERSION=15.2.rel1 \
  -t imx-forge:latest \
  -f docker/Dockerfile \
  .
```

### 控制构建输出详细程度

Docker 镜像支持通过 `VERBOSE` 构建参数控制容器内命令的输出详细程度；同时，Docker BuildKit 自己还有一层进度输出界面。调试网络或下载问题时，通常需要同时使用 `VERBOSE=1` 和 `--progress=plain`。

两者的职责不同：

- `--build-arg VERBOSE=1`：让 Dockerfile 里的 `wget` 使用详细输出
- `--progress=plain`：让 BuildKit 不使用动态刷新界面，按普通日志逐行输出

```bash
# 默认模式（显示进度条）
docker build -f docker/Dockerfile -t imx-forge:latest .

# 详细输出模式（用于调试）
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile -t imx-forge:latest .

# 国内用户 + 详细输出
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile.cn -t imx-forge:latest .

# 保存完整构建日志
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile -t imx-forge:latest . 2>&1 | tee build.log
```

**参数说明**：

| 参数 | 控制对象 | 效果 |
|------|----------|------|
| `VERBOSE=0` 或未设置 | Dockerfile 内部命令 | 使用默认下载输出 |
| `VERBOSE=1` | Dockerfile 内部命令 | `wget` 使用详细输出 |
| `--progress=plain` | Docker BuildKit 输出界面 | 禁用动态刷新，按普通日志逐行输出 |

**使用场景**：
- **默认模式**：日常构建，输出简洁清晰
- **VERBOSE=1 + --progress=plain**：当构建失败，需要查看完整下载和命令输出时
- **重定向到 build.log**：需要保存完整日志用于复盘或提交问题时

**注意**：如果只设置 `--build-arg VERBOSE=1`，BuildKit 仍可能使用动态进度界面重绘终端，看起来像日志被覆盖。调试时优先使用 `--progress=plain`，通常不需要禁用 BuildKit。

### 多用户支持

如果宿主机用户 ID 不是 1000，可以自定义：

```bash
# 构建时指定用户 ID
docker build \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t imx-forge:latest \
  .

# 运行时指定用户
docker run -it --rm \
  -v $(pwd):/workspace \
  -u $(id -u):$(id -g) \
  imx-forge:latest
```

**为什么需要这个？**

容器内的 `ubuntu` 用户默认 UID=1000。如果你的宿主机用户 UID 不是 1000，编译产物可能属于不同的用户，导致权限问题。

### 自定义 DNS

如果容器内无法解析域名：

```bash
docker run -it --rm \
  --dns 8.8.8.8 \
  --dns 114.114.114.114 \
  -v $(pwd):/workspace \
  imx-forge:latest
```

### 资源限制

限制容器使用的资源：

```bash
# 限制内存和 CPU
docker run -it --rm \
  --memory=4g \
  --cpus=2 \
  -v $(pwd):/workspace \
  imx-forge:latest

# 限制 CPU 核心数（使用第 0 和第 1 核心）
docker run -it --rm \
  --cpuset-cpus="0,1" \
  -v $(pwd):/workspace \
  imx-forge:latest

# 限制交换空间
docker run -it --rm \
  --memory=4g \
  --memory-swap=4g \
  -v $(pwd):/workspace \
  imx-forge:latest
```

**使用场景**：
- 编译大型项目时限制资源
- 在资源受限的机器上运行
- 防止容器占用过多资源

### 环境变量

传递环境变量到容器：

```bash
docker run -it --rm \
  -e CROSS_COMPILE=arm-none-linux-gnueabihf- \
  -e ARCH=arm \
  -e MY_CUSTOM_VAR=value \
  -v $(pwd):/workspace \
  imx-forge:latest
```

或使用 `--env-file`：

```bash
# 创建 .env 文件
cat > .env << EOF
CROSS_COMPILE=arm-none-linux-gnueabihf-
ARCH=arm
MY_CUSTOM_VAR=value
EOF

# 使用 env 文件
docker run -it --rm \
  --env-file .env \
  -v $(pwd):/workspace \
  imx-forge:latest
```

---

## 调试与烧录

### USB 设备访问

#### 方法一：特权模式（简单）

**适用场景**：开发环境，不需要严格的安全隔离

```bash
docker run -it --rm \
  --privileged \
  -v /dev:/dev \
  -v $(pwd):/workspace \
  imx-forge:latest
```

**优点**：
- ✅ 简单，一根命令搞定
- ✅ 可以访问所有设备

**缺点**：
- ⚠️ 安全性较低，容器有完全的设备访问权限
- ⚠️ 不适合生产环境

#### 方法二：特定设备（推荐）

**适用场景**：只访问特定设备，更安全

```bash
# 查看可用的 USB 设备
ls -la /dev/ttyUSB*

# 只挂载特定的 USB 设备
docker run -it --rm \
  --device=/dev/ttyUSB0 \
  --device=/dev/ttyUSB1 \
  -v $(pwd):/workspace \
  imx-forge:latest
```

**优点**：
- ✅ 更安全，只授权特定设备
- ✅ 明确知道哪些设备被访问

**缺点**：
- ⚠️ 需要知道设备名称
- ⚠️ 设备名称可能变化

#### WSL2 USB 设备直通

在 WSL2 中使用 USB 设备需要额外配置：

```powershell
# 1. 在 Windows PowerShell (管理员) 中安装 USBIPD-WIN
winget install usbipd

# 2. 查看 USB 设备
usbipd list

# 输出示例：
# BUSID  DEVICE                                                        STATE
# 1-1    USB Serial Port (COM3)                                        Not attached

# 3. 绑定设备
usbipd bind --busid 1-1

# 4. 附加到 WSL2
usbipd attach --wsl --busid 1-1

# 5. 在 WSL2 中验证
ls /dev/ttyUSB*
```

详细步骤参考：[WSL USB 设备直通文档](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)

### 串口调试

在容器内使用 picocom 进行串口调试：

```bash
# 进入容器（确保 USB 设备已挂载）
docker run -it --rm \
  --privileged \
  -v /dev:/dev \
  -v $(pwd):/workspace \
  imx-forge:latest

# 在容器内使用 picocom
picocom -b 115200 /dev/ttyUSB0
```

**picocom 快捷键**：
- 退出：`Ctrl + A` → `Ctrl + Q`
- 清屏：`Ctrl + A` → `Ctrl + L`
- 发送中断：`Ctrl + A` → `Ctrl + C`

### 烧录 SD 卡

在容器内烧录 U-Boot 到 SD 卡：

```bash
# 进入容器（需要设备访问权限）
docker run -it --rm \
  --privileged \
  -v /dev:/dev \
  -v $(pwd):/workspace \
  imx-forge:latest

# 在容器内烧录
# 注意：请确认 SD 卡设备名称（/dev/sdX）
sudo dd if=out/uboot/u-boot-dtb.imx of=/dev/sdX bs=1K seek=1 conv=notrunc
sync
```

**警告**：`dd` 命令具有破坏性，请务必确认设备名称正确！

### 网络启动

如果使用 NFS 网络启动，容器需要网络访问：

```bash
# 使用 host 网络模式
docker run -it --rm \
  --network host \
  -v $(pwd):/workspace \
  imx-forge:latest

# 或使用桥接网络
docker run -it --rm \
  --network bridge \
  -p 2049:2049 \  # NFS 端口
  -p 69:69 \      # TFTP 端口
  -v $(pwd):/workspace \
  imx-forge:latest
```

---

## 性能优化

### 编译速度优化

**1. 使用 Docker BuildKit**

```bash
# 开启 BuildKit
export DOCKER_BUILDKIT=1

# 构建镜像
docker build -t imx-forge:latest .
```

BuildKit 的优势：
- ✅ 并行构建
- ✅ 更好的缓存利用
- ✅ 更快的构建速度

**2. 并行编译**

在容器内使用 `make -j` 进行并行编译：

```bash
# 使用所有 CPU 核心
make -j$(nproc)

# 或在构建脚本中已自动并行化
./scripts/build_helper/build-linux.sh  # 已使用 -j8
```

**3. 缓存编译产物**

使用卷缓存编译产物，避免重复编译：

```bash
# 创建缓存卷
docker volume create build-cache

# 使用缓存
docker run -it --rm \
  -v build-cache:/workspace/.ccache \
  -v $(pwd):/workspace \
  imx-forge:latest
```

**4. 使用 tmpfs**

将临时目录放在内存中：

```bash
docker run -it --rm \
  --tmpfs /tmp:rw,size=4g \
  -v $(pwd):/workspace \
  imx-forge:latest
```

### 存储优化

**1. 单独挂载 out 目录**

```bash
# 避免将编译产物计入容器层
docker run -it --rm \
  -v $(pwd):/workspace \
  -v $(pwd)/out:/workspace/out \
  imx-forge:latest
```

**2. 定期清理 Docker 缓存**

```bash
# 清理构建缓存
docker builder prune

# 清理未使用的镜像
docker image prune -a

# 清理所有未使用的对象
docker system prune -a --volumes
```

**3. 使用 .dockerignore**

在项目根目录创建 `.dockerignore`：

```
.git
.github
*.md
document/
examples/
!docker/Dockerfile
```

避免将不必要的文件复制到镜像中。

### 网络优化

**1. 国内用户使用 Dockerfile.cn**

```bash
# 国内用户使用优化的 Dockerfile
docker build -f docker/Dockerfile.cn -t imx-forge:latest .
```

Dockerfile.cn 使用国内镜像源（阿里云）加速 APT 包下载。

**2. 配置镜像加速器**

```bash
cd docker
sudo bash setup-mirror.sh
```

详见：[Docker 基础教程 - 国内加速配置](01_docker_basics.md#国内加速配置)

**3. 使用国内 APT 源**

如果需要手动配置，在 Dockerfile 中添加：

```dockerfile
# 使用阿里云 APT 源
RUN sed -i 's@archive.ubuntu.com@mirrors.aliyun.com@g' /etc/apt/sources.list && \
    sed -i 's@security.ubuntu.com@mirrors.aliyun.com@g' /etc/apt/sources.list
```

---

## 故障排除

### 问题 1: Dockerfile 找不到

**错误信息**：
```
ERROR: failed to build: failed to solve: failed to read dockerfile: open Dockerfile: no such file or directory
```

**症状**：从项目根目录运行 `docker build` 时找不到 Dockerfile

**原因**：Dockerfile 位于 `docker/` 子目录中，但当前目录下没有 Dockerfile

**解决方法**：

```bash
# 方式 1：指定 Dockerfile 路径（推荐）
docker build -f docker/Dockerfile -t imx-forge:latest .

# 方式 2：先进入 docker 目录
cd docker
docker build -t imx-forge:latest .

# 方式 3：从 docker 目录构建并使用 build context
cd docker
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
```

**注意**：使用 `-f` 参数时，构建上下文（`.`）仍然是项目根目录，因此 COPY 指令的路径需要相对于项目根目录。

### 问题 2: 构建失败

**症状**：`docker build` 失败

**可能原因**：

1. **网络问题**
   - 基础镜像下载失败
   - 工具链下载失败

**解决方法**：
```bash
# 使用国内镜像源
docker build -f docker/Dockerfile.cn -t imx-forge:latest .

# 或配置代理
docker build \
  --build-arg http_proxy=http://proxy:port \
  --build-arg https_proxy=http://proxy:port \
  -t imx-forge:latest .
```

2. **磁盘空间不足**
```bash
# 检查磁盘空间
df -h

# 清理 Docker 缓存
docker system prune -a --volumes
```

3. **Docker 版本过旧**
```bash
# 检查版本
docker --version

# 更新 Docker
sudo apt update && sudo apt install docker-ce
```

### 问题 3: 容器启动失败

**症状**：`docker run` 失败或容器立即退出

**可能原因**：

1. **权限问题**
```bash
# 检查文件权限
ls -la $(pwd)

# 确保当前用户对项目目录有读写权限
chown -R $USER:$USER /path/to/imx-forge
```

2. **端口冲突**
```bash
# 查看占用的端口
sudo netstat -tulpn

# 使用不同的端口
docker run -it --rm \
  -p 8080:80 \
  -v $(pwd):/workspace \
  imx-forge:latest
```

3. **资源限制**
```bash
# 查看系统资源
free -h
top

# 增加资源限制
docker run -it --rm \
  --memory=8g \
  --cpus=4 \
  -v $(pwd):/workspace \
  imx-forge:latest
```

### 问题 4: 编译错误

**症状**：容器内编译失败

**可能原因**：

1. **工具链路径问题**
```bash
# 在容器内验证工具链
docker run -it --rm \
  -v $(pwd):/workspace \
  imx-forge:latest \
  arm-none-linux-gnueabihf-gcc --version

# 检查 PATH
echo $PATH
```

2. **卷挂载错误**
```bash
# 检查挂载点
docker run -it --rm \
  -v $(pwd):/workspace \
  imx-forge:latest \
  ls -la /workspace

# 确保项目目录已正确挂载
```

3. **用户权限不匹配**
```bash
# 使用与宿主机相同的用户 ID
docker run -it --rm \
  -v $(pwd):/workspace \
  -u $(id -u):$(id -g) \
  imx-forge:latest
```

### 问题 5: 性能问题

**症状**：编译速度慢

**解决方法**：

1. **增加并行度**
```bash
# 在容器内
make -j$(nproc)
```

2. **使用 tmpfs**
```bash
docker run -it --rm \
  --tmpfs /tmp:rw,size=4g \
  -v $(pwd):/workspace \
  imx-forge:latest
```

3. **检查资源限制**
```bash
# 查看容器资源使用
docker stats

# 增加资源限制
docker run -it --rm \
  --memory=8g \
  --cpus=4 \
  -v $(pwd):/workspace \
  imx-forge:latest
```

### 问题 6: 磁盘占用过大

**症状**：Docker 占用大量磁盘空间

**解决方法**：

```bash
# 查看磁盘使用
docker system df

# 清理未使用的镜像
docker image prune -a

# 清理未使用的容器
docker container prune

# 清理未使用的卷
docker volume prune

# 清理所有未使用的对象
docker system prune -a --volumes

# 查看镜像大小
docker images

# 删除特定的镜像
docker rmi imx-forge:old-version
```

---

## 最佳实践

### 开发流程

1. **使用 Git 管理代码**
   - 在主机上使用 Git 进行版本控制
   - 容器只用于编译和测试

2. **在容器内编译和测试**
   - 使用临时容器（`--rm`）
   - 编译产物保留在主机上

3. **定期清理**
   - 定期清理不需要的容器和镜像
   - 使用 `docker system prune` 释放空间

### 安全建议

1. **避免使用 --privileged**
   - 只在必要时使用特权模式
   - 优先使用 `--device` 挂载特定设备

2. **只挂载必要的目录**
   - 避免挂载根目录 `/`
   - 只挂载需要的项目目录

3. **只暴露必要的设备**
   - 使用 `--device=/dev/ttyUSB0` 而不是 `-v /dev:/dev`
   - 明确知道哪些设备被访问

4. **定期更新镜像**
   - 定期重新构建镜像获取更新
   - 关注安全公告

### 团队协作

1. **统一 Docker 镜像版本**
   - 在项目中指定镜像版本
   - 使用固定的镜像标签（如 `v0.1.0` 而不是 `latest`）

2. **使用 Docker Compose**
   - 将配置写入 `docker-compose.yml`
   - 团队成员使用相同配置

3. **CI/CD 集成**
   - 在 CI/CD 流水线中使用相同的镜像
   - 确保构建环境一致

4. **文档化自定义配置**
   - 记录自定义的构建参数
   - 文档化特殊配置的原因

### 性能建议

1. **使用 BuildKit**
   ```bash
   export DOCKER_BUILDKIT=1
   ```

2. **合理设置资源限制**
   - 根据实际需求设置
   - 避免过度限制或过度分配

3. **利用缓存**
   - 使用卷缓存编译产物
   - 使用 `.dockerignore` 减少构建上下文

4. **优化 Dockerfile**
   - 合并指令减少层数
   - 使用多阶段构建减小镜像大小

---

## 实战案例

### 案例 1: 驱动开发工作流

**场景**：开发一个字符设备驱动

**步骤**：

```bash
# 1. 运行容器（挂载项目）
docker run -it --rm -v $(pwd):/workspace imx-forge:latest

# 2. 在容器内编译驱动
cd /workspace/driver/led
make

# 3. 复制 .ko 文件到 rootfs
cp led.ko /workspace/rootfs/nfs/

# 4. 退出容器
exit

# 5. 烧录到 SD 卡
# （在主机上或使用带设备访问的容器）

# 6. 在目标板上测试
# insmod led.ko
```

### 案例 2: 内核调试

**场景**：调试内核启动问题

**步骤**：

```bash
# 1. 运行容器（带串口访问）
docker run -it --rm \
  --privileged \
  -v /dev:/dev \
  -v $(pwd):/workspace \
  imx-forge:latest

# 2. 在容器内修改内核配置
cd /workspace
./scripts/build_helper/build-linux.sh menuconfig

# 3. 重新编译
./scripts/build_helper/build-linux.sh

# 4. 查看串口输出
picocom -b 115200 /dev/ttyUSB0

# 5. 分析启动日志
```

### 案例 3: CI/CD 集成

**场景**：在 CI/CD 流水线中使用 Docker

**GitLab CI 示例**：

```yaml
build:
  image: imx-forge:latest
  script:
    - ./scripts/build_helper/build-uboot.sh
    - ./scripts/build_helper/build-linux.sh
    - ./scripts/build_helper/build-busybox.sh
  artifacts:
    paths:
      - out/
    expire_in: 1 week
```

**GitHub Actions 示例**：

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: imx-forge:latest
    steps:
      - uses: actions/checkout@v2
        with:
          submodules: recursive
      - name: Build U-Boot
        run: ./scripts/build_helper/build-uboot.sh
      - name: Build Linux
        run: ./scripts/build_helper/build-linux.sh
      - name: Upload artifacts
        uses: actions/upload-artifact@v2
        with:
          name: build-output
          path: out/
```

---

## 与主机开发对比

| 场景 | Docker | 主机环境 |
|------|--------|----------|
| **新手上手** | ⭐⭐⭐⭐⭐ 5分钟配置 | ⭐⭐ 需要30分钟+ |
| **编译性能** | ⭐⭐⭐⭐ 接近原生 | ⭐⭐⭐⭐⭐ 原生性能 |
| **灵活性** | ⭐⭐⭐⭐ 受容器限制 | ⭐⭐⭐⭐⭐ 完全控制 |
| **环境一致性** | ⭐⭐⭐⭐⭐ 完全一致 | ⭐⭐ 容易出现差异 |
| **调试体验** | ⭐⭐⭐⭐ 支持良好 | ⭐⭐⭐⭐⭐ 更直接 |
| **团队协作** | ⭐⭐⭐⭐⭐ 环境统一 | ⭐⭐ 需要手动同步 |
| **跨平台** | ⭐⭐⭐⭐⭐ 完美支持 | ⭐ 只支持 Linux |

**总结**：
- **新手**：强烈推荐 Docker
- **高级用户**：Docker 和主机环境各有优势
- **团队开发**：Docker 是首选
- **性能敏感**：主机环境略优，但差异很小

---

## 参考文档

- [docker/README.md](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/docker/README.md) - IMX-Forge Docker 环境详细参考
- [Docker 官方文档](https://docs.docker.com/)
- [项目主 README](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/README.md)
- [快速入门指南](../../QUICK_START.md)

---

## 常用命令速查

```bash
# === 镜像操作 ===
# 构建镜像
docker build -t imx-forge:latest .

# 查看镜像
docker images

# 删除镜像
docker rmi imx-forge:latest

# === 容器操作 ===
# 运行容器（临时）
docker run -it --rm -v $(pwd):/workspace imx-forge:latest

# 运行容器（持久）
docker run -dit --name imx-dev -v $(pwd):/workspace imx-forge:latest

# 查看运行中的容器
docker ps

# 停止容器
docker stop imx-dev

# 删除容器
docker rm imx-dev

# === 清理操作 ===
# 清理所有未使用的对象
docker system prune -a --volumes

# 查看磁盘使用
docker system df

# === 调试操作 ===
# 查看日志
docker logs <container_id>

# 进入运行中的容器
docker exec -it <container_id> bash

# 查看容器资源使用
docker stats
```

---

**Happy Developing with Docker!** 🐳⚡
