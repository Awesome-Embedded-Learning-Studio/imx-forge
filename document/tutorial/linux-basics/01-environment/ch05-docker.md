# 第 5 章  Docker 开发环境搭建

> **Part: Part 1 · 环境搭建**

---

## 引子

你已经在这个 Ubuntu 上装了一堆东西：编译器、调试器、Python 库、各种依赖……然后有一天你需要换一个项目的编译环境，版本冲突了。

「我这台机器上到底装了多少乱七八糟的东西？」

这个问题一旦出现，你离重装系统就不远了。更糟糕的是，嵌入式开发几乎注定会遇到这个问题——不同项目需要不同版本的交叉编译工具链，不同版本的依赖库，甚至不同版本的系统工具。把它们全装在同一台机器上，迟早会炸。

Docker 要解决的，就是「别在你干净的系统上乱装东西」这个问题。它给你一个一次性的、用完就扔的干净环境——像实验室里的无菌操作台，做完实验台面一擦，下次又是全新的。

但这台「无菌操作台」有一个地方和你想的不一样——我们先把 Docker 的三个核心概念搞清楚，再动手装。

---

## 背景与动机

如果你做过嵌入式开发，下面这个场景一定不陌生：

项目 A 用 ARM GCC 9.3，项目 B 用 ARM GCC 12.2，项目 C 切到了 ARM GCC 15.2。三个工具链装在同一台机器上，`PATH` 环境变量指来指去，一不小心就编译出错的版本。更不用说 Python 2 和 Python 3 共存、cmake 版本不匹配、某个库只装了 dev 包没装 runtime 包……

这些问题的根源是同一个：**你在主机上装了太多东西，而这些东西之间不总是兼容的。**

传统解决方案是虚拟机——给每个项目开一个干净的虚拟机。但虚拟机太重了：启动慢、占内存、占磁盘，光装系统就要半小时。你只是想换个编译环境，不是想再开一台电脑。

Docker 在「轻量隔离」和「完整环境」之间找到了一个平衡点。它不需要你装一整套操作系统，而是共享主机的 Linux 内核，只在用户空间做隔离。启动一个容器只需要秒级的时间，销毁也是瞬间的事。

对于嵌入式开发者来说，Docker 的价值尤其明显：

- **环境一致性**：你、你的同事、CI 服务器，用同一个镜像编译出来的东西是完全一致的
- **依赖隔离**：每个项目有自己的容器，互不干扰
- **快速上手**：新项目不需要从头配环境，拉一个镜像就能开始编译
- **用完即弃**：搞坏了？删掉重来，主机不受影响

---

## 概念层

Docker 的核心只有三个东西：**镜像（Image）**、**容器（Container）** 和 **卷（Volume）**。理解了这三个概念，Docker 就没什么神秘的了。

### 镜像：一份打包好的环境蓝图

你可以把镜像想象成一张光盘——里面刻好了操作系统、编译器、依赖库、配置文件，所有东西都冻结在这个状态里。你把这个光盘放进任何一台装了 Docker 的机器里，读出来的环境都是一模一样的。

「光盘」这个比喻有一个地方是错的：真正的光盘是整块塑料一次压制成型的，但 Docker 镜像是**分层**构建的。每一层只记录和上一层相比的增量变化——底层是 Ubuntu 24.04 的基础系统，中间层装了 build-essential，再上面一层加了 ARM 工具链。当你拉取一个镜像时，Docker 会检查本地已有的层，只下载缺失的那些。这意味着两个镜像如果共享底层（比如都用 Ubuntu 24.04 作为基础），那份底层只需要存一份。

镜像是只读的。你没法修改一个已经构建好的镜像——要改，就在它上面叠加新的一层。

### 容器：镜像的运行实例

如果镜像是光盘，容器就是把光盘里的内容加载到内存里跑起来的进程。

```bash
# 从 ubuntu:24.04 镜像启动一个容器
$ docker run -it ubuntu:24.04 bash
# 预期输出
root@1a2b3c4d5e6f:/#
```

注意发生了什么——你的终端突然变成了一个全新的 Ubuntu 环境。`1a2b3c4d5e6f` 是这个容器的 ID，你在里面做的所有操作（装软件、改配置、创建文件）都发生在这个容器自己的可写层里，不会影响镜像本身，也不会影响主机。

当你退出这个容器时：

```bash
root@1a2b3c4d5e6f:/# exit
# 预期输出
exit
```

容器停止了。但它的可写层还在——除非你显式地删除它（`docker rm`），否则你可以随时重新启动（`docker start`）回到之前的状态。

这就是 Docker 的「用完即弃」：当你不需要这个环境了，删掉容器，主机上什么痕迹都不会留下。

### 卷：让数据活下来

但这里有一个问题。

如果容器是临时的，那编译出来的文件怎么办？你在容器里编译了一个小时的固件，删掉容器之后全没了？

这就是 **卷（Volume）** 存在的意义。卷是 Docker 提供的一种数据持久化机制——你可以把主机上的一个目录「挂载」到容器里。容器往这个目录里写的任何东西，实际上是写到了主机上。容器删了，文件还在。

```bash
# 把当前目录挂载到容器的 /workspace
$ docker run -it -v $(pwd):/workspace ubuntu:24.04 bash
```

这条命令的意思是：把主机上当前目录（`$(pwd)`）和容器里的 `/workspace` 目录绑定在一起。你在容器里往 `/workspace` 写的任何文件，主机上立刻就能看到。

对于嵌入式开发来说，这几乎是必用的功能——代码放在主机上方便编辑，编译在容器里进行（因为容器里有配好的工具链），编译产物通过卷挂载自然出现在主机上。

回到那张「光盘」的类比：你现在应该能看出来了，镜像是光盘，容器是正在运行的光驱，而卷就是你插在光驱旁边的那块 U 盘——光驱可以随时弹出换一张碟，但 U 盘上的数据永远在。如果你忘了插 U 盘（没有挂载卷），光盘里跑出来的所有数据都只在内存里，断电即逝。

---

## 实践层

### 5.1 安装 Docker

Ubuntu 上安装 Docker 有好几种方式：snap、convenience script（一键脚本）、Docker 官方 APT 源。我们用**官方 APT 源**——这是 Docker 官方推荐的方式，版本最新，更新也最及时。

> Docker Desktop for Linux 和 Docker Engine 的区别：Docker Desktop 是一个带 GUI 的桌面应用，包含了 Docker Engine 加上一套图形管理界面；Docker Engine 是纯命令行工具。对于开发用途，Docker Engine 就够了，不需要额外的 GUI。

#### 卸载旧版本

如果你之前装过 Docker（或者系统自带了某个版本），先清掉：

```bash
$ sudo apt remove -y docker docker-engine docker.io containerd runc
# 预期输出（如果没有旧版本，会提示找不到包，正常）
# E: Unable to locate package docker
# ...
```

找不到包也没关系，继续往下走。

#### 添加 Docker 官方源

```bash
# 安装必要的依赖
$ sudo apt update
$ sudo apt install -y ca-certificates curl gnupg

# 添加 Docker 的 GPG 密钥
$ sudo install -m 0755 -d /etc/apt/keyrings
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
$ sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 添加 Docker 的 APT 源
$ echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

这些命令在做什么？——`curl` 下载 Docker 的 GPG 公钥，`gpg --dearmor` 把它转换成 APT 能识别的格式，最后那条 `echo` 把 Docker 的软件源地址写到 APT 的配置里。做完这些，`apt` 才知道去哪里找 Docker 的包。

#### 安装 Docker Engine

```bash
$ sudo apt update
$ sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
# 预期输出
# ...（安装过程）
# Setting up docker-ce (5:27.x.x-xxx) ...
```

验证安装：

```bash
$ sudo docker run hello-world
# 预期输出
# Unable to find image 'hello-world:latest' locally
# latest: Pulling from library/hello-world
# ...
# Hello from Docker!
# This message shows that your installation appears to be working correctly.
```

看到 `Hello from Docker!`，说明 Docker 已经跑起来了。

#### 免 sudo 使用 Docker

默认情况下，只有 root 用户和 `docker` 组的用户能操作 Docker。每次都打 `sudo` 太烦了，把你的用户加进 `docker` 组：

```bash
$ sudo usermod -aG docker $USER
```

然后**重新登录**（或者执行 `newgrp docker`），让权限生效：

```bash
$ newgrp docker

# 验证——不需要 sudo 了
$ docker run hello-world
# 预期输出
# Hello from Docker!
```

> ⚠️ **安全隐患**
> 把用户加进 `docker` 组等同于给了这个用户 root 权限。因为 Docker 容器可以挂载主机的任意目录，`docker` 组的用户可以通过容器读写主机上的任何文件，包括 `/etc/shadow`。
> 对于你自己的开发机来说，这通常不是问题。但如果是一台多人共享的服务器，加用户进 `docker` 组之前要三思。

### 5.2 镜像与容器基本操作

Docker 的日常操作其实就是围绕镜像和容器的几个命令。不需要一次全记住，用到的时候回来查就行。

#### 镜像操作

```bash
# 拉取一个 Ubuntu 24.04 镜像
$ docker pull ubuntu:24.04
# 预期输出
# 24.04: Pulling from library/ubuntu
# ...
# Status: Downloaded newer image for ubuntu:24.04

# 查看本地有哪些镜像
$ docker images
# 预期输出（实际输出可能略有不同）
# REPOSITORY    TAG       IMAGE ID       CREATED        SIZE
# ubuntu        24.04     xxxxxxxxxxxx   x weeks ago    77.8MB
# hello-world   latest    xxxxxxxxxxxx   x months ago   13.3kB
```

`ubuntu:24.04` 是一个**镜像名:标签**的组合。`24.04` 这个标签指定了版本——如果不写标签（`docker pull ubuntu`），默认拉 `latest`。

#### 容器的生命周期

容器的完整生命周期是：**创建 → 启动 → 运行 → 停止 → 删除**。

```bash
# 启动一个交互式容器（-i 交互，-t 分配终端）
$ docker run -it ubuntu:24.04 bash
# 预期输出
root@a1b2c3d4e5f6:/#

# 在容器里随便逛逛
root@a1b2c3d4e5f6:/# cat /etc/os-release | head -2
# 预期输出
# NAME="Ubuntu"
# VERSION="24.04 LTS (Noble Numbat)"

# 退出容器
root@a1b2c3d4e5f6:/# exit
```

退出之后容器还在吗？

```bash
# 查看所有容器（包括已停止的）
$ docker ps -a
# 预期输出
# CONTAINER ID   IMAGE          COMMAND   CREATED          STATUS                      ...
# a1b2c3d4e5f6   ubuntu:24.04   "bash"    30 seconds ago   Exited (0) 30 seconds ago   ...
```

容器还在，只是状态变成了 `Exited`。你可以重新启动它：

```bash
# 启动已停止的容器
$ docker start a1b2c3d4e5f6
# 预期输出
# a1b2c3d4e5f6

# 重新进入运行中的容器
$ docker exec -it a1b2c3d4e5f6 bash
# 预期输出
root@a1b2c3d4e5f6:/#
```

`docker exec` 和 `docker run` 的区别很重要：`run` 是从镜像创建一个**新**容器，`exec` 是在**已经运行**的容器里开一个新的进程。

不需要的容器可以删除：

```bash
# 停止容器
$ docker stop a1b2c3d4e5f6

# 删除容器
$ docker rm a1b2c3d4e5f6
# 预期输出
# a1b2c3d4e5f6
```

一个更实用的做法是用 `--rm` 参数——容器退出时自动删除，不用手动清理：

```bash
# 用完即弃
$ docker run -it --rm ubuntu:24.04 bash
```

#### 清理不用的资源

用了一段时间之后，你可能会积累很多停止的容器、过期的镜像：

```bash
# 查看 Docker 占了多少磁盘
$ docker system df
# 预期输出（示例）
# TYPE            TOTAL   ACTIVE  SIZE      RECLAIMABLE
# Images          3       2       1.2GB     500MB (41%)
# Containers      5       1       300MB     280MB (93%)
# ...

# 一键清理所有未使用的资源
$ docker system prune
# 预期输出
# WARNING! This will remove:
#   - all stopped containers
#   - all networks not used by at least one container
#   - all dangling images
#   - all dangling build cache
# Are you sure you want to continue? [y/N] y
```

### 5.3 卷挂载：代码在主机、编译在容器

这一节是 Docker 对嵌入式开发最有价值的部分。

#### 工作模式

典型的嵌入式开发工作流是这样的：

1. 代码放在主机的某个目录里（方便用你喜欢的编辑器修改）
2. 编译环境在 Docker 容器里（工具链、依赖都已经配好）
3. 通过卷挂载把代码目录「映射」进容器
4. 在容器里执行编译命令
5. 编译产物通过卷挂载自动出现在主机上

```bash
# 典型用法：挂载当前目录到容器的 /workspace
$ docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  ubuntu:24.04 bash
```

逐行解释：

- `--rm`：容器退出后自动删除
- `-v $(pwd):/workspace`：把主机当前目录挂载到容器的 `/workspace`
- `-w /workspace`：进入容器后默认在工作目录 `/workspace`

进入容器之后，你会发现你的代码就在眼前：

```bash
root@container:/workspace# ls
# 预期输出：你主机当前目录里的文件列表
```

在容器里编译：

```bash
# 假设容器里已经装了 gcc
root@container:/workspace# gcc -o hello hello.c
# 预期输出（编译成功，无报错）

# 编译产物在主机上也能看到
root@container:/workspace# ls hello
# 预期输出
# hello
```

退出容器之后，`hello` 这个可执行文件依然在你的主机目录里。卷挂载是双向的——容器写的文件主机能看到，主机改的文件容器也能看到。

> ⚠️ **权限问题**
> 如果你在容器里创建的文件，在主机上显示 owner 是 `root`，那是因为容器里默认以 root 用户运行。imx-forge 的 Docker 镜像做了特殊处理，容器内会使用和主机相同的 UID，避免这个问题。如果你自己构建镜像，需要注意这一点。

#### 一个完整的例子

让我们走一遍完整的流程——从零开始用 Docker 跑一个编译环境：

```bash
# 在主机上创建项目目录
$ mkdir -p ~/docker-demo && cd ~/docker-demo

# 写一个简单的 C 程序
$ cat > hello.c << 'EOF'
#include <stdio.h>
int main() {
    printf("Hello from Docker!\\n");
    return 0;
}
EOF

# 用 Ubuntu 容器编译它（容器里默认没有 gcc，先装一个）
$ docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  ubuntu:24.04 \
  bash -c "apt update && apt install -y gcc && gcc -o hello hello.c"
# 预期输出（末尾）
# ...
# Setting up gcc (4:13.2.0-xxx) ...

# 在主机上验证编译产物
$ ./hello
# 预期输出
# Hello from Docker!
```

这个例子虽然简单，但它演示了 Docker 的核心工作流：**代码在主机，编译在容器，产物回主机**。在实际的嵌入式项目中，容器里会预装好完整的工具链，不需要每次都 `apt install`。

#### 国内镜像加速

在国内拉取 Docker Hub 的镜像可能会很慢。配置国内镜像源可以解决这个问题：

```bash
# 创建 Docker 配置目录
$ sudo mkdir -p /etc/docker

# 写入镜像加速配置
$ sudo tee /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF

# 重启 Docker 使配置生效
$ sudo systemctl daemon-reload
$ sudo systemctl restart docker
```

验证加速是否生效：

```bash
$ docker info | grep -A 5 "Registry Mirrors"
# 预期输出
#  Registry Mirrors:
#   https://docker.mirrors.ustc.edu.cn/
```

---

## 练习题

走到这里，Docker 的三个核心概念和基本操作应该清楚了。下面几道题帮你验证一下理解的程度。

**练习 5.1** ⭐（理解）

镜像是只读的，容器是可写的。那么当你在容器里安装了一个软件（比如 `apt install gcc`），然后把这个容器删掉了（`docker rm`），你装的 gcc 去哪了？如果想「保存」这个安装了 gcc 的环境，应该怎么做？

> **提示**：想一想镜像和容器的分层关系。

**练习 5.2** ⭐⭐（应用）

你执行了以下命令：

```bash
docker run -it --rm -v $(pwd):/data ubuntu:24.04 bash
```

进入容器后在 `/data` 目录下创建了一个文件 `test.txt`，然后执行 `exit` 退出。

问题：`test.txt` 还在吗？如果还在，在主机的哪个位置？如果不在，为什么？

**练习 5.3** ⭐⭐⭐（思考）

Docker 容器共享主机的 Linux 内核。这意味着 Docker 容器只能运行 Linux 程序——你没法在 Linux 主机的 Docker 里跑 Windows 程序。

但 WSL2 可以在 Windows 上运行 Linux 程序，而 Docker Desktop for Windows 又利用 WSL2 来运行 Linux 容器。请分析这条链路：Windows → WSL2（Linux 内核）→ Docker（Linux 容器）。为什么 Docker 需要 WSL2，而不能直接在 Windows 上运行容器？这和「容器共享主机内核」这个前提有什么关系？

---

## 本章回响

本章建立的核心认知是：**隔离不是虚拟化的专利**。Docker 通过 Linux 内核的 namespace 和 cgroup 机制，在不需要完整虚拟机的情况下实现了进程级别的环境隔离。这个认知之所以重要，在于它改变了你管理开发环境的方式——不再是「在主机上装一堆东西然后祈祷它们不冲突」，而是「每个项目一个容器，互不干扰，用完即弃」。

还记得开头那个问题吗——「我这台机器上到底装了多少乱七八糟的东西？」现在你应该能回答了：装了多少不重要，重要的是它们被关在各自的容器里。你不需要重装系统，只需要 `docker rm`。

镜像、容器、卷，这三个概念构成了 Docker 的全部基础。镜像是环境的模板，容器是模板的运行实例，卷是连接容器和主机的数据桥梁。掌握了这三个，日常使用 Docker 就不需要再学更多的抽象概念——剩下的都是具体命令的参数组合。

下一章我们将离开「环境搭建」这个 Part，进入命令行的世界。在终端里敲命令是 Linux 开发的日常，而你在前面几章里配置好的 Ubuntu 环境，就是接下来所有练习的舞台。

---

[← 上一章](ch04-file-share.md)
[下一章 →](../02-commandline/ch06-shell.md)
