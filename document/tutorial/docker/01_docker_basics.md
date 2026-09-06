---
title: Docker 基础知识
---

# Docker 基础知识

> 本篇是 Docker 卷的第一篇，管地基：容器到底是个什么东西、嵌入式开发为什么值得用它、咱们怎么在 Ubuntu 或 WSL2 上把 Docker 装起来、日常命令怎么使。工具链的手动安装路线在 start 卷的[从 0 开始：安装交叉编译工具链](../start/01_start_from_toolchain.md)，本篇是它的替代路线，两条路殊途同归；装好之后怎么在 imx-forge 里真正编译、烧录，交给下一篇。


::: tip 前置知识·环境
- 前置：一台 Ubuntu 22.04/24.04 主机，或 Windows 10/11 上的 WSL2；宿主机环境还没准备的朋友，可以先看 start 卷的[从 0 开始：安装交叉编译工具链](../start/01_start_from_toolchain.md)，那篇的前半部分对咱们同样适用。
- 仓库实路径：`~/imx-forge`（本机即 `/home/charliechen/imx-forge`），Docker 相关的五个文件都集中在 `docker/` 子目录。
- 路径上下文声明：本篇命令分三处执行，Linux 主机或 WSL 发行版内（块首标 `# 主机 ~/imx-forge`）、Windows 的 PowerShell（标 `# Windows PowerShell`）、容器内（标 `# 容器 /workspace`）；交叉编译用的是镜像里预装的 ARM GNU Toolchain 15.2.rel1，主机上不需要另装。
:::

## 一、容器是什么：一个被隔离的进程

咱们从最常见的误解聊起：不少人把容器理解成“缩小版虚拟机”，画皮像，骨头不像。虚拟机的每个实例都拖着一整套 Guest OS，开机要走完整的引导流程；容器根本没有自己的内核——所有容器共用主机这一个内核，所谓隔离，是内核拿 namespace 隔开各自的视图（进程号、网络栈、挂载点互不可见），再拿 cgroups 给每个容器限额（CPU、内存封顶）。打个比方，虚拟机是每户自带锅炉和水表的独栋，容器是共用大楼水电、门一锁互不打扰的公寓；公寓轻，是因为最贵的那套基础设施只有一份。

把差别列成表，咱们逐行看：

| 特性 | 容器 | 虚拟机 |
|------|------|--------|
| 启动速度 | 秒级 | 分钟级 |
| 资源占用 | MB 级 | GB 级 |
| 性能 | 接近原生 | 有损耗（约 5-20%） |
| 隔离性 | 进程级隔离 | 硬件级隔离 |
| 系统要求 | 共享主机内核 | 每实例一套 Guest OS |
| 可移植性 | 极高 | 较低 |

结构上两张图对照：

```text
虚拟机:App A + Guest OS │ App B + Guest OS   每个 VM 拖一套完整系统
                  Hypervisor
                  Host OS + 硬件

容器:  App A + Bins/Libs │ App B + Bins/Libs 只带各自的运行库
                  Docker Engine
                  Host OS + 硬件(内核只有一份)
```

隔离性那一行咱们要心里有数：进程级隔离的安全边界比硬件级弱，docker 组的权限约等于 root，这个坑留到常见问题再细说。对做嵌入式的咱们来说，主菜是最后两行：同一份镜像在 Ubuntu、WSL2、macOS 上跑，编译结果完全一致，Build once, run anywhere 说的就是这件事。

## 二、嵌入式开发为什么需要它

不用容器的嵌入式开发，痛感集中在环境上。最扎手的是工具链版本：项目 A 要 ARM GCC 9.3，项目 B 要 11.2，到 imx-forge 这里是 15.2.rel1，同一台主机塞三套工具链，PATH 里谁先谁后就成了玄学。依赖清单也长：build-essential、cmake、ninja-build、device-tree-compiler、u-boot-tools、python3-pyelftools、swig、libssl-dev、libncurses-dev 这串包，在不同发行版上版本各不相同，Ubuntu 22.04 能编过的内核，24.04 上可能就报缺依赖。更磨人的是那句经典的“在我机器上能跑”：开发机 Ubuntu 22.04 配 GCC 11.2，CI 是 Ubuntu 20.04 配 GCC 9.3，同事掏出 Ubuntu 24.04 配 15.2，同一份代码三个编译结果，咱们排查起来谁都不服谁。

再往下一层是人的成本。新手入门要过的关有：工具链下载、解压、配 PATH，依赖装齐、对版本，环境变量和权限各种磕碰，还没写第一行代码就先被环境劝退，这种事笔者见过太多回；Windows 用户还得先过 WSL2 或双系统这道门，macOS 用户则有自己的兼容性问题要处理。

Docker 把这些一次性收走：工具链和全部依赖打进一个镜像，谁用谁拉。同一条 `docker run -v` 挂载命令，咱们在 Ubuntu、Windows+WSL2、macOS 上跑出来的是同一个环境；项目 A 用带 GCC 9.3 的镜像、项目 B 用 11.2 的，互不干扰；新同事入职、CI 流水线，拉同一个镜像立即开工，复现问题不再靠运气。

### imx-forge 的镜像里装了什么

咱们不空谈，看仓库 `docker/` 目录的真实文件：

```text
# 主机 ~/imx-forge
$ ls /home/charliechen/imx-forge/docker/
Dockerfile  Dockerfile.cn  README.md  daemon.json  setup-mirror.sh
```

五个文件各管一块，咱们日常打交道的主要是前两个：`Dockerfile` 是标准构建脚本，`Dockerfile.cn` 是国内源优化版，`daemon.json` 与 `setup-mirror.sh` 管镜像加速（第六节细说）。镜像的骨架，grep 一下 Dockerfile 的开头就能看清：

```text
# 主机 ~/imx-forge
$ grep -n 'TOOLCHAIN_VERSION\|FROM' docker/Dockerfile | head -6
12:FROM ubuntu:24.04 AS builder
14:ARG TOOLCHAIN_VERSION=15.2.rel1
15:ARG TOOLCHAIN_URL=https://developer.arm.com/-/media/Files/downloads/gnu/${TOOLCHAIN_VERSION}/binrel/arm-gnu-toolchain-${TOOLCHAIN_VERSION}-x86_64-arm-none-linux-gnueabihf.tar.xz
32:    && mv arm-gnu-toolchain-${TOOLCHAIN_VERSION}-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain \
39:FROM ubuntu:24.04
```

两个 `FROM` 就是多阶段构建：builder 阶段（12 行）只负责从 ARM 官网下载、解压 15.2.rel1 工具链；runtime 阶段（39 行）从干净的 ubuntu:24.04 起步装编译依赖，再 `COPY --from=builder` 把工具链搬过来，下载缓存一层都不进最终镜像。runtime 装的依赖，就是编译 U-Boot、内核、buildroot 要用的那一整串：build-essential、bc、bison、flex、device-tree-compiler、python3-pyelftools、swig、libssl-dev、libgnutls28-dev、libncurses-dev、cmake、ninja-build、meson、cpio、rsync、u-boot-tools、fdisk、ccache 等。镜像还有几个对日常开发要紧的细节——默认用非 root 的 ubuntu 用户（UID 1000）跑，ENV 里预置了 `CROSS_COMPILE=arm-none-linux-gnueabihf-` 与 `ARCH=arm`，咱们进容器就落在 `/workspace` 工作目录。想换工具链版本也不用改文件，构建时 `--build-arg TOOLCHAIN_VERSION=xxx` 覆盖默认值即可。

`docker/README.md` 里记的数字是：最终镜像约 2GB，构建中间阶段约 2.5GB，本地构建 5-10 分钟（看网络）。不想本地构建，咱们可以直接拉官方放在 ghcr.io 上的预构建镜像：`latest` 由维护者的发布流程手动更新，不自动跟随版本 tag；要复现就锁带版本号的 tag。这里有个坑咱们得先说破：ghcr 上的版本 tag 不带 v 前缀——git tag 是 `v1.0.4`，镜像 tag 就是 `1.0.4`（发布工作流里 metadata-action 的 semver 模式会把 v 剥掉），拿 ghcr 的 tags/list 接口核对过，现有版本 tag 里没有任何带 v 的；`docker/README.md` 里写的 `docker pull ...:v1.0.0` 照做会报 manifest unknown，它那个写法是错的，咱们别跟着抄：

```bash
# 主机 ~/imx-forge
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
docker run -it --rm -v $(pwd):/workspace ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
# 锁版本用现有版本 tag,当前是 1.0.4
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:1.0.4
```

锁 1.0.4 之前还有个实情要交代：当前 1.0.4 镜像不含 2026-07-29 的 fdisk 依赖修复，您要按第四节的样子在容器里跑 `./scripts/release-all.sh` 全流程出镜像的话，会在镜像生成那一步撞上缺 sfdisk 的报错；这种情况请改用已含修复的 `latest`，或按第四节的步骤本地构建，等下一个带修复的版本 tag 发布后，这条提醒再滚动更新。

::: warning 未实测标注
本篇成稿时，咱们这台 WSL Ubuntu 24.04 环境里没有安装 docker 命令（`docker --version` 报 Command not found），镜像构建与运行没法在本机复跑；文中引用的工具链验收输出（`arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203`）以 `docker/README.md` 的验收记录为准。
:::

效果对比就摆在这：手动配环境，顺的话半小时，不顺咱们一下午耗在依赖上；Docker 路线构建一次镜像几分钟，之后每次开发都是秒级进容器。下一篇给出验收步骤与预期输出。

## 三、四个核心概念：镜像、容器、卷、Dockerfile

这四个词后面每一篇都会反复出现，咱们一次把关系摆顺：Dockerfile 是配方，镜像是按配方做出的只读模板，容器是镜像跑起来的活实例，卷是容器往外存数据的通道。一句话串起来：写 Dockerfile，build 成镜像，run 出容器，数据走卷。

### 镜像：只读的分层模板

镜像里装着运行所需的一切：基础系统、库、工具链、环境变量。它只读、分层，每条 Dockerfile 指令对应一层，多层还能被不同镜像共享，这就是咱们拉第二个基于 ubuntu:24.04 的镜像时，基础层不用重新下载的原因。看个最小例子：

```dockerfile
FROM ubuntu:24.04                    # 第 1 层:基础镜像
RUN apt update && apt install gcc    # 第 2 层:安装工具
COPY . /app                          # 第 3 层:复制文件
WORKDIR /app                         # 第 4 层:设工作目录
```

### 容器：镜像的运行实例

镜像和容器的关系，类似程序和进程：同一镜像可以同时跑出多个容器，每个容器在只读的镜像层之上叠一个自己的可写层；咱们在容器里写的文件都落在可写层，容器一删就没了，除非数据放到了卷上。生命周期一条线：创建、启动、运行、停止、删除。

### 卷：数据真正的落脚处

卷管的是容器外面的数据：容器删了它还在（持久化），宿主机与容器还借它共享文件。两种形态：命名卷由 Docker 自己管理，存放在 `/var/lib/docker/volumes/` 下；绑定挂载把宿主机的一个目录直通进容器。咱们做 imx-forge 开发用的就是绑定挂载，把仓库根目录挂到容器的 `/workspace`，编译产物直接留在宿主机磁盘上，容器删了也不丢：

```bash
# 主机 ~/imx-forge
docker run -it -v $(pwd):/workspace imx-forge:latest          # 挂当前目录
docker run -it -v $(pwd):/workspace:ro ubuntu:24.04           # 只读挂载
docker run -it -v $(pwd):/workspace -v $(pwd)/out:/output imx-forge:latest  # 多目录挂载
```

只读挂载（`:ro`）适合咱们给容器看参考资料但不许它改；把产物目录单独再挂一个 `-v` 出去，也是 `docker/README.md` 里给的常见做法。

### Dockerfile：镜像的配方

上面几行就是 Dockerfile 的全部形态：`FROM` 定基础镜像，`RUN` 执行命令，`COPY` 拷文件，`ENV` 设变量，`CMD` 定容器默认干的事；imx-forge 的那份咱们第二节已经 grep 过，是标准的多阶段写法。写 Dockerfile 有几条经验值得记：用 `.dockerignore` 把不需要进镜像的文件（比如 `.git` 和 `out/`）挡在外面；多条 `RUN` 合并成一条能少好几层；多阶段构建把下载缓存挡在最终镜像之外；指令顺序把不常变的放前面，构建缓存才命中的多。

## 四、安装 Docker

### Ubuntu：官方 APT 源安装

Ubuntu 仓库自带的 docker.io 包版本偏旧，咱们按官方文档走 APT 源装 docker-ce，步骤按成稿时点的官方文档核对贴出（本机没装 docker，这套步骤没在本地复跑过；官方文档往后若有调整，以 docs.docker.com 为准）：

```bash
# 主机 ~/
# 卸载可能存在的旧版本
sudo apt remove docker docker-engine docker.io containerd runc

# 装前置依赖并加 Docker 官方 GPG 密钥
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 配 APT 源(deb822 格式)
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# 安装并验证
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run hello-world
```

### 免 sudo：把用户加进 docker 组

默认只有 root 能碰 Docker 守护进程，咱们每条命令都得敲 sudo，很烦。把自己加进 docker 组即可：

```bash
# 主机 ~/
sudo usermod -aG docker $USER
newgrp docker            # 立即生效,或重新登录
docker run hello-world   # 不带 sudo 验证
```

::: warning
docker 组的成员等于拿到了 root 级权限：挂载宿主机任意目录、跑特权容器都拦不住。咱们自己的单人开发机无所谓，多人共用的服务器上这个组要慎给。
:::

### WSL2 安装

imx-forge 在 WSL2 上深度测试过，咱们给 Windows 用户的推荐组合是 WSL2（Ubuntu 发行版）加 Docker Desktop 的 WSL2 集成：不用双系统、不用另开虚拟机，文件系统能互访，USB 设备可以直通进来烧录调试，性能接近原生 Linux。

装 WSL2 本身不难，咱们在管理员 PowerShell 里敲一条命令：

```powershell
# Windows PowerShell(管理员)
wsl --install
# 重启电脑,完成 Ubuntu 初始化(建用户、设密码)
```

接着配网络，这一步对咱们做板端开发是刚需。WSL2 默认的 NAT 模式下，发行版藏在 Windows 身后的一段内网地址里，局域网上的开发板根本够不到它，TFTP/NFS 这类网络启动就断了；mirrored 模式让 WSL2 与 Windows 共享同一组网卡地址，问题才有解。不过 mirrored 有版本门槛：按微软 learn.microsoft.com 上的 WSL 网络文档，`networkingMode=mirrored` 要 Windows 11 22H2 及以上才支持，Windows 10 上这项配置不生效，WSL 仍按 NAT 工作，问题原样复现。留在 Win10 的朋友只能继续用 NAT 模式。官方的转发工具只有 `netsh interface portproxy`，而它只转发 TCP：NFS 的 2049/TCP 还能转，TFTP 走的 UDP 69 覆盖不到，网络启动这条路就断了。真要凑，得在 Windows 侧自己跑一个 UDP 中继（比如 socat）把 69 端口转进 WSL，或把 TFTP 服务挪到 Windows 上与板子直连，最实际的建议还是升级 Windows 11 用上 mirrored，或换台 Linux 主机。在 Windows 用户目录建 `.wslconfig`：

```ini
# Windows 用户目录 .wslconfig(最小可用配置)
[wsl2]
networkingMode=mirrored
```

```powershell
# Windows PowerShell
wsl --shutdown
wsl
```

笔者这台机器就是这么配的。mirrored 与 NAT 的完整对比、防火墙怎么放行 TFTP 的 UDP 69 与 NFS 端口、源码和构建目录放哪个盘更快，这些网络与存储的配置细节在开发环境配置卷的[WSL2 环境配置：网络、防火墙与存储位置](../workflow/01_wsl2_env_config.md)，本篇不重复展开。

然后装 Docker Desktop：您去官网下载安装包，安装时勾选 Use WSL 2 based engine；装完在 Settings 的 Resources、WSL Integration 里给自己的 Ubuntu 发行版启用集成，点 Apply & Restart。

::: warning 未实测标注
Docker Desktop 的安装与其 Settings 界面里的 WSL2 集成开关是 Windows 图形界面操作，咱们这台机器只有 WSL 侧的命令行，无法逐屏验证；以 Docker 官方安装向导与 `docker/README.md` 的步骤为准。
:::

验证回到 WSL 里做，您应该看到版本号、hello-world 跑通、`docker info` 正常输出：

```bash
# 主机 ~/(WSL 内)
docker --version
docker run hello-world
docker info
```

网络验证咱们看两样：`ip addr` 能看到与 Windows 相同的网卡，`ping` 开发板的 IP 能通。

::: warning 未实测标注
本环境没有接开发板，咱们没法在这里演示 ping 通板子这一步；mirrored 是否生效的地址对照验证方法，以上一段链接的 WSL2 环境配置一章为准。
:::

您要是撞见 Docker Desktop 起不来，两步排查：`wsl --list --verbose` 确认发行版 VERSION 是 2，`wsl --update` 升级 WSL 内核；还不行就进 BIOS 确认虚拟化（VT-x/AMD-V）已开启。

```powershell
# Windows PowerShell
wsl --list --verbose
wsl --update
```

环境就绪后咱们的日常与 Linux 上没有区别：克隆仓库、构建镜像、跑容器、编译：

```bash
# 主机 ~/
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge/docker
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
cd ..
docker run -it --rm -v $(pwd):/workspace imx-forge:latest
```

```bash
# 容器 /workspace
./scripts/release-all.sh
```

文件互访也有讲究：Windows 的 C 盘挂在 `/mnt/c/` 下，源码和构建目录咱们别放那儿——跨文件系统的 I/O 慢好几倍，实测数据在刚才那篇 WSL2 环境配置里。

USB 串口设备要进 WSL2，咱们得靠 Windows 侧的 usbipd 把设备绑过来（需要 Windows 11 或较新的 Windows 10，微软官方 WSL 文档的 connect-usb 一节有完整说明）；容器再用它，run 时加 `--device=/dev/ttyUSB0`，烧录这类要碰底层设备的场景，`docker/README.md` 给的是 `--privileged` 配 `-v /dev:/dev` 的组合。usbipd 的安装绑定全套步骤与串口终端的选用，见工作流卷的[串口终端：开发台的第二块屏幕](../workflow/03_serial_terminal.md)和 start 卷的[串口工具使用（minicom）](../start/04_serial_tools_minicom.md)：

```bash
# 主机 ~/(WSL 内)
ls /dev/ttyUSB*
docker run -it --rm --device=/dev/ttyUSB0 -v $(pwd):/workspace imx-forge:latest
```

```powershell
# Windows PowerShell(管理员)
winget install usbipd
usbipd list
usbipd bind --busid 1-1
usbipd attach --wsl --busid 1-1
```

### 原生 Windows 与 macOS

咱们不推荐在 Windows 上绕过 WSL2 直接用 Docker Desktop 做嵌入式开发：路径要在 `C:\` 与 `/mnt/c/` 之间来回转换，构建脚本容易踩空；两套文件系统的权限模型不同，编译会出怪问题；文件 I/O 性能也差一截。macOS 用户装 Docker Desktop 即可，`docker --version` 与 `docker run hello-world` 两步验证；不过 imx-forge 的主线验证环境是 Ubuntu 与 WSL2，macOS 上遇到问题得自己兜底。

## 五、日常命令速览

前面各节零散用过一批，这里按类别归拢，您可以当速查表使。镜像类：

```bash
# 主机 ~/
docker images                        # 列本地镜像
docker pull ubuntu:24.04             # 拉取
docker build -t myimage:latest .     # 构建
DOCKER_BUILDKIT=1 docker build -t myimage:latest .   # BuildKit,更快
docker rmi myimage:latest            # 删除
docker rmi -f myimage:latest         # 强制删除
docker image prune                   # 清悬空镜像
```

容器类：

```bash
# 主机 ~/
docker run -it ubuntu:24.04 bash         # 交互式运行
docker run -d ubuntu:24.04 sleep 1000    # 后台运行
docker run -it --rm ubuntu:24.04 bash    # 用完即删
docker ps                            # 运行中的容器
docker ps -a                         # 含已停止的
docker stop <container_id>           # 停止
docker start <container_id>          # 再启动
docker restart <container_id>        # 重启
docker rm <container_id>             # 删除
docker rm -f <container_id>          # 强删运行中的
docker container prune               # 清停止的容器
```

卷类：

```bash
# 主机 ~/
docker volume create mydata          # 建命名卷
docker run -it -v mydata:/data ubuntu:24.04
docker run -it -v $(pwd):/workspace ubuntu:24.04     # 绑定挂载
docker volume ls                     # 列卷
docker volume inspect mydata         # 卷详情
docker volume rm mydata              # 删卷
```

网络类：

```bash
# 主机 ~/
docker network ls
docker network create mynet
docker run --network mynet ubuntu:24.04
docker network inspect mynet
docker network rm mynet
```

日志与调试：

```bash
# 主机 ~/
docker logs <container_id>           # 看日志
docker logs -f <container_id>        # 跟随输出
docker inspect <container_id>        # 详细信息
docker exec -it <container_id> bash  # 进运行中的容器
docker stats                         # 资源占用
```

清理：

```bash
# 主机 ~/
docker system df                     # 磁盘占用
docker system prune -a --volumes     # 清所有未使用对象(慎用)
```

输出详略由两个参数分管：`--build-arg VERBOSE=1` 管的是 Dockerfile 里 `wget` 的输出，`--progress=plain` 管的是 BuildKit 界面刷不刷新，咱们调试下载问题时 plain 更有用。构建路径则分根目录与子目录两种形态：从仓库根目录构建要显式 `-f` 指到 `docker/Dockerfile`，cd 进 docker 再构建就不用：

```bash
# 主机 ~/imx-forge(根目录形态)
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile -t imx-forge:latest .
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile.cn -t imx-forge:latest .

# 主机 ~/imx-forge/docker(子目录形态)
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
DOCKER_BUILDKIT=1 docker build -f Dockerfile.cn -t imx-forge:latest .
```

## 六、国内加速配置

Docker Hub 在境外，咱们国内直连慢甚至超时，拉 ubuntu:24.04 这类基础镜像可能卡十几分钟，构建体验很差。思路是给守护进程配国内的 registry mirror；imx-forge 在仓库里自带了一份现成配置，咱们先看 `docker/daemon.json` 的内容。注意这只是仓库自带的配置，可用性得咱们自己实测，原因往下说：

```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

三个源分别是中国科学技术大学、网易、腾讯云；log 那两行是顺手限制容器日志，单个 10MB 最多留 3 份，防止日志悄悄吃掉咱们的磁盘。

这三个源的现状，咱们得交代个实情：国内公网的 Docker Hub 加速源自 2024 年 6 月起大批停服——中科大 2024-06-06 发公告“由于不可抗力因素，暂时关闭 Docker Hub 镜像缓存服务”（公告见 mirrors.ustc.edu.cn/help/dockerhub.html），网易 hub-mirror 同期停止 Docker Hub 同步，腾讯云的 mirror.ccs.tencentyun.com 只在腾讯云内网生效。所以这份仓库自带的配置咱们只能当个起点，可用性得自己拿 `docker pull` 实测；眼下更稳的主推荐是阿里云控制台“容器镜像服务”里的个人加速器，登录控制台领一个专属地址，塞进 `registry-mirrors` 数组替换上面三个源即可。

::: warning 未实测标注
上面三个源的可用性没有在本篇验证过：本机没装 docker、出口又走代理，本节的配置与验证命令都没真跑过；2024-06 以来国内公网加速源大批停服，最终以咱们自己 `docker pull` 的实测结果为准。
:::

不想手动编辑，就跑仓库里的脚本：它会建 `/etc/docker` 目录、给旧配置备一份带时间戳的副本、写入上面这份配置、重启 Docker，最后用 `docker info` 把生效的加速器列表打出来给您核对（脚本里写死的就是这三个源，想换个人加速器，得先改脚本里那份数组再跑）：

```bash
# 主机 ~/imx-forge/docker
sudo bash setup-mirror.sh
```

咱们手动配置也简单：把上面那段存成 `/etc/docker/daemon.json`（或直接 `sudo cp docker/daemon.json /etc/docker/daemon.json`），然后重启服务：

```bash
# 主机 ~/(Ubuntu/Debian)
sudo systemctl daemon-reload
sudo systemctl restart docker
```

```powershell
# Windows PowerShell(WSL2 场景重启整个 WSL)
wsl --shutdown
wsl
```

验证咱们看两步，`docker info` 里能看到 Registry Mirrors 列表，`docker pull` 能不能真拉下镜像，才是这些源（或您换上的个人加速器）可用与否的最终判据：

```bash
# 主机 ~/
docker info | grep -A 10 "Registry Mirrors"
docker pull ubuntu:24.04
```

加速器也有边界，咱们心里要有数：这批源（含阿里云个人加速器）主要加速 Docker Hub，对 ghcr.io 的效果有限，拉 ghcr.io 上的预构建镜像还是慢的话，老老实实本地构建、用 `Dockerfile.cn`。

## 七、常见问题

### 每条 docker 命令都要 sudo

第四节说过的 docker 组就是解法：`usermod -aG docker $USER` 加组，`newgrp docker` 或重新登录生效。要紧的是咱们得知道自己交出去的是什么权限：docker 组能把宿主机任意路径挂进容器，等价于 root，多人机器慎给。

### 容器里访问不了网络

咱们从防火墙、DNS、网络模式三处依次查。防火墙：`sudo ufw status` 看状态，怀疑它时用 `sudo ufw disable` 临时关掉做对照。DNS：`cat /etc/resolv.conf` 看宿主机配置，`docker run ubuntu:24.04 cat /etc/resolv.conf` 在容器里看，必要时 `--dns 8.8.8.8 --dns 114.114.114.114` 手动指定。网络模式：`docker network ls` 列出现有网络，run 时 `--network bridge` 显式走默认桥接。

### 镜像构建失败

咱们撞见的构建失败多半落在网络、磁盘、版本这三样上。拉基础镜像超时，配第六节的 registry mirror；apt 下载慢，换 `Dockerfile.cn`（国内 APT 源版）；工具链下载要过 ARM 官网，网络受限的环境可以给 build 传 `--build-arg http_proxy`/`https_proxy`。磁盘满：`df -h` 看空间，`docker system prune -a` 与 `docker builder prune` 清缓存。版本过旧：`docker --version` 核对，`sudo apt update && sudo apt install docker-ce` 升级。

### 磁盘被 Docker 吃满

层、构建缓存、停止的容器都占地方，咱们得定期清：`docker container prune` 清停止的容器，`docker image prune -a` 清未使用镜像，`docker volume prune` 清未使用卷，`docker system df` 随时看占用，`docker system prune -a --volumes` 一把全清；注意 `--volumes` 会把不再使用的命名卷一起删，绑定挂载的宿主机目录不受影响。

### 进正在运行的容器、与宿主机互传文件

咱们用 `docker ps` 拿到容器 ID，`docker exec -it <container_id> bash` 进去；镜像里没 bash 的（精简基础镜像常见）换 `sh`。传文件用 `docker cp`，双向都行：`docker cp <container_id>:/path/in/container /path/on/host` 与 `docker cp /path/on/host <container_id>:/path/in/container`。日常开发更推荐 `-v` 挂载，文件天然两边同步，省得来回拷。

### 资源占用的查看与限制

`docker stats` 实时刷新各容器的 CPU、内存、网络与磁盘 I/O，咱们要看单个容器就在后面跟容器 ID。要限制就在 run 时给参数：`--memory=4g` 限内存，`--cpus=2` 限可用核数，`--cpuset-cpus="0,1"` 只允许用 0、1 这两个核，`--memory-swap=4g` 限内存加交换的总上限。

### 容器里要用图形界面

咱们做嵌入式开发基本用不上图形界面，偶尔需要图形程序时走 X11 转发，把显示环境透进去：

```bash
# 主机 ~/
docker run -it -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix ubuntu:24.04
```

### 容器删了，数据还在吗

咱们看数据写在哪：写在容器可写层里的，容器删除即消失；放到卷里的就还在。两条路，命名卷是 `docker volume create mydata` 后 `-v mydata:/data` 挂载，由 Docker 管位置；绑定挂载是 `-v $(pwd)/data:/data`，直接落在宿主机目录。imx-forge 的玩法是整仓挂到 `/workspace`，产物留在宿主机的 `out/` 里，容器用完即删也不心疼。另外，产物的属主咱们得交代个实情：这镜像的默认用户是 ubuntu（UID 1000），不是 root，宿主机用户 UID 不是 1000 时，产物属主会显示成一个陌生的 1000。`docker/README.md` 给的老办法是构建时传 `--build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g)`，但咱们 grep `docker/Dockerfile` 就能发现，这两个 ARG 只有声明、全文件没有一处引用（chown 和 USER 走的都是 `${USER_NAME}`），传了等于没传，老办法在当前镜像上不生效；要修得给 `docker/Dockerfile` 和 `docker/Dockerfile.cn` 补上 usermod，那是仓库层面的改动，超出本篇。眼下真能对齐两边的，是 run 时加 `--user $(id -u):$(id -g)`，不改镜像就把 UID 对上，副作用是容器里没有现成的同名用户，个别往家目录写缓存的工具可能报权限错。

## 踩坑速查表

咱们把上面的坑收成一张表，遇到时按现象对号：

| 现象 | 根因 | 解法 |
|------|------|------|
| 每条命令都报 permission denied | 用户不在 docker 组 | `sudo usermod -aG docker $USER` 后重新登录 |
| 拉 ubuntu 基础镜像超时 | 国内直连 Docker Hub 慢 | 配加速器（公网源自 2024-06 大批停服，主推荐阿里云个人加速器）或改用 `Dockerfile.cn` |
| ghcr.io 预构建镜像拉不动 | 加速器不覆盖 ghcr.io | 本地构建，用 `Dockerfile.cn` |
| 构建中途 No space left on device | 层与构建缓存堆积 | `docker system prune -a`、`docker builder prune` |
| 容器删了编译产物没了 | 数据写在可写层 | `-v $(pwd):/workspace` 绑定挂载 |
| WSL2 里 ping 不通开发板 | 默认 NAT，板子够不到 WSL | `.wslconfig` 切 mirrored（需 Windows 11 22H2+，微软 learn.microsoft.com 的 WSL 网络文档有说明；Win10 上 mirrored 不生效，portproxy 只转 TCP、盖不住 TFTP 的 UDP 69，没有官方转发方案，建议升级系统或换 Linux 主机） |
| 容器里摸不到 /dev/ttyUSB0 | 设备没透进容器 | run 加 `--device` 或 `--privileged` |
| 编译产物属主是个陌生的 UID 1000 | 镜像默认用户固定是 ubuntu（UID 1000），与宿主机不同号 | run 时加 `--user $(id -u):$(id -g)` |
| 磁盘悄悄少了几十 GB | 停止的容器与悬空镜像 | `docker system df` 查，`docker system prune -a` 清 |
| 日志目录越来越大 | 容器日志没限大小 | `daemon.json` 的 log-opts 限 10MB 三份 |

## 继续学习

- 下一篇：[IMX-Forge Docker 开发指南](02_imx_forge_docker_guide.md)，把本篇的地基用起来：构建 imx-forge 镜像、进容器编译各组件、烧录与调试。
- 另一条路线：不想用 Docker、要在主机上手动装工具链的朋友，看 start 卷的[从 0 开始：安装交叉编译工具链](../start/01_start_from_toolchain.md)。
- 跨卷深读：WSL2 网络模式、防火墙与存储位置见[WSL2 环境配置：网络、防火墙与存储位置](../workflow/01_wsl2_env_config.md)；串口设备直通与终端见[串口终端：开发台的第二块屏幕](../workflow/03_serial_terminal.md)与[串口工具使用（minicom）](../start/04_serial_tools_minicom.md)。
- 更全的 Docker 参考在仓库 `docker/README.md`，官方文档站 docs.docker.com 上有 Dockerfile 最佳实践与 Compose 的专章。
