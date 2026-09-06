---
title: Docker 教程
---

# Docker 教程

> 嵌入式开发的头一道门槛常常不在代码而在环境：工具链版本、依赖库、设备权限，随便一样都够咱们耗掉一个下午。本卷把整套编译环境打进 Docker 镜像，拉下来就能编 U-Boot、编内核；上承[入门准备](../start/)卷的开发准备，下接 [U-Boot 教程](../uboot/)卷的引导移植，是三条装环境路线里最省事的一条。


::: tip 前置知识·环境
- 前置章：建议您先读完[入门准备](../start/)，至少完成仓库克隆与板子连线
- 仓库实路径：`docker/`，Dockerfile、Dockerfile.cn、daemon.json、setup-mirror.sh、README.md 全在这里
- 路径上下文：本篇是 `document/tutorial/docker/` 的卷首页；咱们操作的对象是 imx-forge 源码仓库，交叉编译用镜像内的 ARM GNU Toolchain 15.2.rel1，宿主机只需要装好 Docker 本身
:::

<ChapterNav>
  <ChapterLink num="01" href="01_docker_basics">Docker 基础知识</ChapterLink>
  <ChapterLink num="02" href="02_imx_forge_docker_guide">IMX-Forge Docker 开发指南</ChapterLink>
</ChapterNav>

## 装环境的三条路线

同一套 imx-forge 源码，把编译环境搭起来有三条路。手动路线在[入门准备](../start/)里带着您逐项安装工具链与依赖，好处是每个组件都过目；[工作流](../workflow/)卷走的是 WSL2 + Remote-SSH 开发台路线，环境仍装在本地 WSL，只是编辑器经 SSH 接入，串口与传文件的配置同卷配齐；Docker 路线就是本卷，镜像里预装了一切，宿主机保持干净。

一句话说清谁该走 Docker 路线：如果您只想尽快把内核编出来，不想在宿主机铺一整套交叉工具链，或者您在 Windows 上透过 WSL2 开发，走这儿；想把环境亲手装一遍、顺带弄明白每层依赖的朋友，去 start 卷更合适。

| 路线 | 做法 | 适合谁 |
|------|------|--------|
| Docker 路线(本卷) | 拉取或构建镜像，容器内自带工具链与依赖 | 求快、宿主机要干净、Windows + WSL2 用户 |
| 手动路线(start 卷) | 宿主机逐项安装工具链与依赖 | 想把环境每一层都弄明白的您 |
| WSL2 + Remote-SSH 路线(workflow 卷) | 环境装在本地 WSL，编辑器经 SSH 接入 | 想把编辑器、串口、传文件配成顺手开发台的朋友 |

## 镜像里有什么，怎么进去

笔者在本仓库实际清点过 docker/ 目录，内容如下：

```text
# 主机 ~/imx-forge
$ ls docker/
Dockerfile
Dockerfile.cn
README.md
daemon.json
setup-mirror.sh
```

镜像以 Ubuntu 24.04 为底，预装 ARM GNU Toolchain 15.2.rel1 与全部编译依赖；Dockerfile.cn 是国内加速版，daemon.json 是镜像加速器配置。正式发布的预构建镜像放在 ghcr.io，当前版本 v1.0.4（2026-06-15 发布）。有个细节要留意：ghcr 上的镜像 tag 比仓库的 git tag 少个 v 前缀，锁定版本得写 1.0.4。不过 1.0.4 镜像不含 2026-07-29 的 fdisk 依赖修复，您要跑 release-all.sh 全流程出镜像的话，请改用已含修复的 latest，或按后文本地构建。咱们进环境只要两条命令：

```bash
# 主机 ~/imx-forge
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
docker run -it --rm -v $(pwd):/workspace ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
```

不愿用预构建镜像的话，在 docker/ 目录里执行 `DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .` 本地构建，README 标称约 5 到 10 分钟。进容器后仓库出现在 /workspace，咱们可以直接跑 build-uboot.sh、build-linux.sh、build-buildroot.sh，一键入口是 release-all.sh；烧录要用 USB 设备时，README 的做法是 run 加 --privileged 并把 /dev 挂进来。

::: warning 未实测标注
Windows 侧 Docker Desktop 与 WSL2 集成属图形界面安装流程，本环境(Linux 主机)验证不了；具体步骤以 [Docker 基础知识](01_docker_basics.md) 的 WSL2 安装一节为准，容器行为以您本机实测为准。
:::

## 学习路径与速查

学习顺序上笔者建议：完全没碰过容器的朋友先过 [Docker 基础知识](01_docker_basics.md)，把镜像、容器、卷挂载混个脸熟；急着开工就直接翻 [IMX-Forge Docker 开发指南](02_imx_forge_docker_guide.md) 的快速开始，编完第一个内核再回头补概念，这样吸收最快。

性能和调试是您最关心的两件事：容器接近原生，编译速度与宿主机几乎相同；GDB、串口、网络启动，咱们在容器里也都能做。真正的坑多半出在设备透传和网络配置，速查如下：

| 现象 | 根因 | 解法 |
|------|------|------|
| 容器里看不到板子串口 | USB 设备默认不进容器 | run 时加 --privileged 并挂载 /dev |
| 构建镜像拉依赖超时 | 默认软件源在境外 | 改用 Dockerfile.cn，或按 daemon.json 配加速器 |
| 容器内改动重启后消失 | 可写层随 --rm 销毁 | 改动放 /workspace，由卷挂载落回宿主机 |

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../start/" variant="sub">← 入门准备</ChapterLink>
  <ChapterLink href="../uboot/" variant="sub">U-Boot 教程 →</ChapterLink>
</ChapterNav>
