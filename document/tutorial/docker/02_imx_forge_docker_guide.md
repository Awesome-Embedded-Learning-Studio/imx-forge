---
title: IMX-Forge Docker 开发指南
---

# IMX-Forge Docker 开发指南

> 上一篇咱们补齐了 Docker 的概念、安装与常用命令，本篇把这些通识落到 imx-forge 仓库本身：容器一挂载，U-Boot、内核、Buildroot rootfs、整盘镜像全都能在里面编出来，串口、烧录、CI 流水线这些日常动作也一并搬进容器。读完您手里就有了一套不污染主机的完整构建环境；板卡侧的接线与硬件问题不在本篇范围，交给硬件速查表。


::: tip 前置知识 · 咱们的环境
- Docker 的安装与基本命令见 [Docker 基础知识](01_docker_basics.md)；板卡接口、串口接线与启动介质见 [板子硬件接口速查表](../start/03_hardware_quick_reference.md)；整个项目的上手路线见 [IMX-Forge 快速入门指南](../../QUICK_START.md)
- 仓库实路径：本机即 /home/charliechen/imx-forge，下文统一写作 ~/imx-forge；docker/ 目录下有 Dockerfile、Dockerfile.cn、daemon.json、setup-mirror.sh 和 README.md 五个文件
- 路径上下文声明：本篇命令分两侧，主机侧在 ~/imx-forge 仓库根执行，容器侧把仓库根挂载到 /workspace 后在容器内执行；操作对象是 imx-forge 的源码树与 out/ 产物目录，交叉工具链用镜像预装的 arm-none-linux-gnueabihf-（ARM GNU Toolchain 15.2.rel1）
:::

## 一、五分钟跑通第一条构建

### 镜像从哪来

咱们正式 release 在 ghcr.io 上提供预构建镜像，`docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest` 直接拉。想保证可复现，主推路径是本地构建：拿仓库里当前的 docker/Dockerfile 自己 build 出镜像，镜像依赖跟源码一起走，这才真的复现得起来。锁已发布 tag 的话得知道一件事：已发布的 git tag v1.0.0 到 v1.0.4 全在 2026 年 6 月，而 GHCR 上的镜像 tag 不带 v 前缀，git tag v1.0.4 发布出的镜像 tag 是 1.0.4，这是 01 章拿 ghcr 的 tags/list 接口核实过的口径。这批 tag 的镜像还赶不上后来两次补依赖的提交：which、bzip2、perl 由 a61b8287（2026-07-06，PR #89）加进 Dockerfile，fdisk（提供 sfdisk）则由 081ff1b2（2026-07-29，PR #97）补上，两次都晚于 v1.0.4（6 月 15 日），所以这些 tag 的镜像里四样全缺，编当前 main 的源码会更早死在 Buildroot 那一步（宿主依赖自检缺 bzcat/bzip2，busybox 源码包是 .tar.bz2），整盘镜像阶段的 sfdisk 都轮不到。真要用 tag 镜像（比如 1.0.4），补装得走 root，因为镜像里没有 sudo，提权靠的是 `-u 0`：

```bash
# 容器内(root)
docker run -it --rm -u 0 -v $(pwd):/workspace ghcr.io/awesome-embedded-learning-studio/imx-forge:1.0.4
apt-get update && apt-get install -y which bzip2 perl fdisk
```

装完在同一容器里接着跑构建（--rm 的容器退出即删，装与编得在同一回里完成）；起的是持久容器，就改用 `docker exec -u 0` 进去装。或者让 tag 镜像只配它对应时点的源码。国内网络拉 ghcr.io 慢的话，咱们转本地构建，顺手把国内加速也配上：

```bash
# 主机 ~/imx-forge
# 拉 GHCR 预构建镜像
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest

# 国内加速：套用 docker/daemon.json（USTC、163、腾讯云三个镜像源），或跑 docker/setup-mirror.sh
cd docker
sudo cp daemon.json /etc/docker/daemon.json
sudo systemctl daemon-reload && sudo systemctl restart docker

# 国内源 Dockerfile 本地构建（APT 换阿里云源）
DOCKER_BUILDKIT=1 docker build -f Dockerfile.cn -t imx-forge:latest .
```

daemon.json 里的 registry-mirrors 只加速 Docker Hub，对 ghcr.io 基本无效。您要是发现 GHCR 死活拉不动，别在加速器上耗着，直接转本地构建是正解。

用标准 Dockerfile 从仓库根构建时记得带 `-f docker/Dockerfile`，构建上下文（命令末尾那个点）仍然是仓库根，Dockerfile 里 COPY 的路径都相对它解析。构建耗时约五到十分钟，大头在下载 15.2.rel1 的工具链压缩包。磁盘预算给足：最终镜像约 2GB、构建阶段约 2.5GB，加上源码与产物，笔者这台机器上一个完整 release 实测占了 15GB（`du -sh out/release-latest/` 的原话），整盘预留 20GB 以上比较稳，内存建议 4GB 起步。

### 容器跑起来，验一把工具链

```bash
# 主机 ~（克隆时记得带 --recurse-submodules，third_party/ 是子模块）
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge

# 主机 ~/imx-forge
docker run -it --rm -v $(pwd):/workspace imx-forge:latest
```

咱们拿 `-it` 拿到交互终端，`--rm` 退出即删，`-v $(pwd):/workspace` 把仓库根挂进容器，编译产物直接写回主机磁盘，容器删了也不丢。进容器后头一件事是确认工具链在 PATH 里：

```bash
# 容器内 /workspace
arm-none-linux-gnueabihf-gcc --version | head -1
```

```text
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
```

这行输出是笔者在本机宿主的同版本工具链（/opt/arm-gnu-toolchain）上实际打印的，镜像里装的是同一个 15.2.rel1，容器内应一致。

::: warning 未实测标注
docker 命令在本环境未安装（which docker 查无此命令），上面的 pull、build、run 与容器内的版本输出没法在这里实际执行；命令与预期输出口径来自 docker/README.md 的验收测试一节，以您本机的实际运行为准。
:::

### 编什么：一键编排与分步脚本

咱们的一键入口是 `./scripts/release-all.sh`，注意是连字符不是下划线。它在仓库根按五个阶段推进：U-Boot、内核、rootfs（经 Buildroot 产出 BusyBox 加用户空间）、rootfs 验证门、SD/eMMC 整盘镜像，产物统一进 out/release-latest/。默认内核轨道是 imx（NXP BSP），要编主线内核就加 `--mainline`，两轨的依赖完全一致；嫌每次全量清理慢可以加 `--fast-build` 跳过 distclean，断点续跑还有 `--continue`。

分步脚本在 scripts/build_helper/ 下，咱们真跑了一遍目录清单，输出原样如下：

```bash
# 主机 ~/imx-forge
ls scripts/build_helper/ scripts/driver_helper/
```

```text
scripts/build_helper/:
build-buildroot.sh
build-linux.sh
build-mainline-linux.sh
build-qemu.sh
build-uboot.sh
buildroot_menuconfig.sh
clean_buildroot.sh

scripts/driver_helper/:
README.md
build_driver.sh
deploy_driver.sh
driver_helper.conf
driver_helper.conf.template
review_driver.sh
show_device_tree.sh
template_creator.sh
```

各管一摊，咱们对着上面那份清单认：

| 脚本 | 管什么 |
|------|------|
| build-uboot.sh | 编 U-Boot |
| build-linux.sh | 编 NXP BSP 轨内核 |
| build-mainline-linux.sh | 编主线轨内核 |
| build-buildroot.sh | 构建 rootfs 用户空间，产物进 out/release-latest/rootfs/ |
| buildroot_menuconfig.sh | 管 Buildroot 的配置界面 |
| build-qemu.sh | 服务 QEMU 板级模拟 |
| clean_buildroot.sh | 负责清理 |

旧文档里出现过的 build-busybox.sh 并不存在，rootfs 的现行方案是 Buildroot，BusyBox 只是它产出的用户空间之一，构建细节咱们另有一整卷：[Buildroot 根文件系统](../buildroot/)。

构建完成后看产物，同样真跑：

```bash
# 主机 ~/imx-forge
ls -l out/release-latest/uboot/u-boot-dtb.imx
ls out/release-latest/images/
```

```text
-rw-r--r-- 1 charliechen charliechen 1735680 Jul 11 08:44 out/release-latest/uboot/u-boot-dtb.imx
imx6ull-aes-emmc.img
imx6ull-aes-emmc.img.manifest
imx6ull-aes-emmc.img.sha256
imx6ull-aes-sd.img
imx6ull-aes-sd.img.manifest
imx6ull-aes-sd.img.sha256
imx6ull-aes.dtb
u-boot-dtb.imx
zImage
```

咱们把这份清单认清楚：u-boot-dtb.imx 是烧到 SD/eMMC 偏移 1KB 处的引导镜像；整盘 imx6ull-aes-emmc.img 约 216MB，旁边跟着 manifest 与 sha256 校验文件，直接 dd 整盘也能启动。imx6ull-aes-sd 三件套是当初拿 `--boot-media sd` 跑整盘镜像那一步（脚本里的 Stage 5）生成的 SD 启动介质版本（release-all.sh 的 `--boot-media` 收 emmc、sd、both 三个值），跟 emmc 那组同源不同目标；末尾的 imx6ull-aes.dtb、u-boot-dtb.imx、zImage 三个是软链接，分别指回 out/release-latest/ 下内核与 U-Boot 的构建产物，是整盘镜像那一步留在 images/ 里的聚合入口。容器退出后这些文件都躺在主机磁盘上，这就是挂载挂对了的回报。

## 二、镜像里装了什么

### 多阶段结构

咱们这份 Dockerfile 分两个阶段，都从 ubuntu:24.04 起步。builder 阶段只干一件事：下载并解压 ARM 工具链；final 阶段重新起一个干净的基础镜像，把工具链拷进去，装上编译期依赖（device-tree-compiler、u-boot-tools、bc、bison、flex、swig、python3-pyelftools 这类内核与 U-Boot 构建的刚需），再配上 git、wget、curl、picocom 这些日常工具，最后以非 root 的 ubuntu 用户收尾。最终镜像约 2GB，builder 那 2.5GB 的中间层不进最终镜像，体积与攻击面一起收窄。

这样分层的好处很实际：工具链想换版本，改一个 ARG 重构建就行；构建依赖要更新，重跑 apt 那几层，工具链层照旧吃缓存。Dockerfile 里咱们用得上的构建参数如下：

| 构建参数 | 默认值 | 作用 |
|------|------|------|
| TOOLCHAIN_VERSION | 15.2.rel1 | 控制从 developer.arm.com 下载哪个版本的工具链 |
| USER_ID / GROUP_ID | 1000 | 声明了但未接线：Dockerfile 里没有 usermod 消费它们，传了不生效；UID 对齐用运行时 `-u` |
| VERBOSE | 0 | 置 1 时 Dockerfile 里的 wget 用详细输出 |

### 两层输出开关

构建卡住想看日志时，咱们得把两层开关分清：`--build-arg VERBOSE=1` 管的是 Dockerfile 内部命令（wget）的输出详细程度；`--progress=plain` 管的是 BuildKit 的界面，让它别做动态刷新、按普通日志逐行打印。只设 VERBOSE 不设 plain 的话，终端还是会被进度条重绘，看起来就像日志被覆盖掉了。排查网络问题两个一起上，要留档再接 tee：

```bash
# 主机 ~/imx-forge
# 详细输出模式（调试下载问题）
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile -t imx-forge:latest .

# 完整日志保存成文件，方便复盘或提 issue
docker build --progress=plain --build-arg VERBOSE=1 -f docker/Dockerfile -t imx-forge:latest . 2>&1 | tee build.log
```

| 参数 | 控制对象 | 效果 |
|------|------|------|
| VERBOSE=0 或未设置 | Dockerfile 内部命令 | wget 用默认进度输出 |
| VERBOSE=1 | Dockerfile 内部命令 | wget 用详细输出 |
| --progress=plain | BuildKit 输出界面 | 禁用动态刷新，普通日志逐行输出 |

## 三、日常的三种容器形态

### 临时容器：日常默认

```bash
# 主机 ~/imx-forge
docker run -it --rm -v $(pwd):/workspace imx-forge:latest
```

用完即删，不留僵尸容器，每次都是干净环境，状态污染这条路直接堵死。日常编译、跑构建脚本，笔者基本只用这一种：

```bash
# 容器内 /workspace
./scripts/build_helper/build-uboot.sh
./scripts/build_helper/build-linux.sh
exit

# 主机 ~/imx-forge（容器已自动删除，产物还在）
ls out/
```

### 持久容器：要留状态时

```bash
# 主机 ~/imx-forge
docker run -dit --name imx-dev -v $(pwd):/workspace imx-forge:latest
docker exec -it imx-dev bash        # 随时进出
docker stop imx-dev                 # 停下但保留
docker start imx-dev                # 再启动
docker rm imx-dev                   # 收摊删除
```

容器里临时装的软件、改的环境变量，您下一次 exec 进去还在，这是它与临时容器的本质差别；代价是生命周期得自己管，忘了删就越积越多。适合连续几天调同一套环境，不适合当默认习惯。

### Docker Compose：配置文件化

```yaml
# docker/docker-compose.yml（仓库未提供，这份文件由咱们自己新建；
# docker/README.md 的 Docker Compose 一节有份旧版示例可对照）
services:
  imx-forge:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    image: imx-forge:latest
    volumes:
      - ..:/workspace
    working_dir: /workspace
    stdin_open: true
    tty: true
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0
```

```bash
# 主机 ~/imx-forge/docker
docker compose run imx-forge     # 起一个服务容器（老版本命令是 docker-compose，带连字符）
docker compose down              # 收掉
```

这份 yml 得咱们自己动手建，仓库里没有现成的 docker-compose.yml，docker/README.md 里那份示例是旧版口径，照着改就行。建好之后，Compose 把 docker run 的参数收进这一份文件，把它提交进版本库，设备挂载、卷、环境变量改一处、全队生效，成员之间不存在环境漂移这回事。单机个人用不上它，两三人以上的协作场景它就开始值钱了。

无论哪种形态，有一条原则咱们要守住：git 操作留在主机做，容器只负责编译和测试。容器是可抛弃的构建环境，版本控制不掺和进去。

## 四、进阶配置

### UID 对齐

容器内 ubuntu 用户的 UID 是 1000。您的主机用户要是恰好也是 1000（多数 Linux 发行版的第一个用户都是），产物属主天然对齐；不是的话，编出来的文件在主机上就归一个不存在的 UID 所有，改权限改得人头疼。能用的解法是运行时覆盖，一条 `-u` 就够：

```bash
# 主机 ~/imx-forge
# 运行时临时指定（不改镜像）
docker run -it --rm -u $(id -u):$(id -g) -v $(pwd):/workspace imx-forge:latest
```

为什么不给"构建时把 UID 烧进镜像"这条路？两份 Dockerfile 里确实声明了 USER_ID/GROUP_ID 这两个构建参数，但全文件没有任何 usermod/useradd 去消费它们，chown 与 USER 指令用的都是 ${USER_NAME}（ubuntu）。传 `--build-arg USER_ID=$(id -u)` 构建出的镜像里，ubuntu 用户的 UID 仍是 1000，"构建时定制 UID"目前是无效操作；真想把它做实，得先给 Dockerfile 补一层 usermod 再重构建，日常场景咱们用运行时 -u 就够了。

### 换工具链版本

```bash
# 主机 ~/imx-forge
docker build --build-arg TOOLCHAIN_VERSION=15.2.rel1 -f docker/Dockerfile -t imx-forge:15.2 .
```

版本号对应 developer.arm.com 下载页的目录名。换了版本建议同时换镜像标签，别让 latest 名不副实，回头排查工具链差异时您会感谢这个习惯。

### DNS、资源与环境变量

容器内域名解析失败，`--dns 8.8.8.8 --dns 114.114.114.114` 直接指定解析服务器。资源侧，`--memory=4g --cpus=2` 限总量，`--cpuset-cpus="0,1"` 把容器绑在指定核心，`--memory-swap` 与 `--memory` 同值等于禁用交换；编译大项目时咱们拿它们防止容器吃光主机资源，`docker stats` 实时看占用，`free -h`、`top` 看主机余量。环境变量用 `-e` 传，量大就写文件：

```bash
# 主机 ~/imx-forge
cat > .env << EOF
CROSS_COMPILE=arm-none-linux-gnueabihf-
ARCH=arm
EOF

docker run -it --rm --env-file .env -v $(pwd):/workspace imx-forge:latest
```

这些参数对咱们用的三种容器形态通用，Compose 里对应 mem_limit、cpus、environment 字段，思路不变。

## 五、串口、烧录与网络启动

### USB 设备进容器

咱们宽松的一条路是特权模式：`docker run` 加 `--privileged -v /dev:/dev`，一条命令全设备可见，适合自己机器上快速烧录；但容器拿到了主机的全部设备权限，共享机器上别这么干。收窄的一条路是按设备授权：

```bash
# 主机 ~/imx-forge
ls -la /dev/ttyUSB*    # 确认设备名
docker run -it --rm --device=/dev/ttyUSB0 -v $(pwd):/workspace imx-forge:latest
```

咱们只放行指定的串口，权限边界清楚；代价是设备名变了（ttyUSB0 变 ttyUSB1）就得重跑命令，插拔顺序一变它就漂。

WSL2 用户多一道手续：USB 设备默认停在 Windows 侧，咱们得用 usbipd 把它透进 WSL，容器里才看得见。四条 PowerShell 命令（管理员窗口里跑）把这事办完：

```powershell
# Windows PowerShell（管理员）
winget install usbipd
usbipd list
usbipd bind --busid 1-1
usbipd attach --wsl --busid 1-1
```

四条命令咱们挨个认：winget 装 usbipd-win，list 列出 Windows 侧全部 USB 设备和总线号，这两个管的是"看见"；bind 把设备登记为可共享，attach 才真正把它交给 WSL，这两个管的是"交出去"。bind 要管理员权限；usbipd-win 5.0 起 attach 不再要求提权，旧版仍要，这条口径出自微软的 [WSL USB 设备直通文档](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)。list 的输出形如（busid 以实际输出为准，1-1 是文档示例里的编号）：

```text
BUSID  DEVICE                                                        STATE
1-1    USB Serial Port (COM3)                                        Not attached
```

attach 完成后咱们回 WSL 侧 `ls /dev/ttyUSB*` 就能看到设备，容器里再按上面 --device 的路子挂进去。串口场景的完整展开、dialout 组与 udev 规则两道权限关，[串口终端：开发台的第二块屏幕](../workflow/03_serial_terminal.md) 有整章，细节回那边看。

::: warning 未实测标注
usbipd 的命令要在 Windows PowerShell（管理员）里执行，本环境是 WSL2 终端，进不了 PowerShell 没法实测；上面的命令顺序与示例输出口径出自微软 WSL 文档与 docker 卷旧版的记载，您本机跑的时候，busid 以 `usbipd list` 的实际输出为准。
:::

### 串口终端

设备透进来后，咱们在容器里直接开 picocom：

```bash
# 容器内 /workspace
picocom -b 115200 /dev/ttyUSB0
```

退出咱们按 Ctrl+A 再按 Ctrl+X。串口参数（115200、8N1、无流控）与日志留档的完整套路在 workflow/03，那边是主场，本篇不展开。

### 烧录 SD/eMMC

咱们烧录认路径之前得先知道 U-Boot 的产物有两条输出树：分步脚本 build-uboot.sh 的默认产物在仓库顶层的 out/uboot/（脚本给 OUTPUT_DIR 设的缺省值就是它），release-all.sh 编 U-Boot 那一步则把 OUTPUT_DIR 指到 out/release-latest/uboot/，产物落在那边。两棵树都是现行路径，谁也不是残留，烧的时候认准与本次构建对应的那一份。走分步脚本就烧 out/uboot/u-boot-dtb.imx，走 release-all.sh 才烧 out/release-latest/uboot/u-boot-dtb.imx。拿不准就比一比两份的 build_info 与时间戳，新编出来的那份才是这次要烧的。本机实测顶层那份的时间戳停在 Jul 8、release-latest 下是 Jul 11，只是这台机器上次分步构建更旧，不是顶层路径失效：

```bash
# 主机 ~/imx-forge（或 --privileged 容器内 /workspace）
ls -l out/release-latest/uboot/u-boot-dtb.imx
sudo dd if=out/release-latest/uboot/u-boot-dtb.imx of=/dev/sdX bs=1K seek=1 conv=notrunc
sync
```

dd 之前咱们拿 lsblk 反复核对 /dev/sdX 就是读卡器里那张卡，写错盘没有撤销键；seek=1 是 i.MX6ULL 启动 ROM 认的 1KB 偏移，照抄别改。烧整盘（SD 卡）就把 if 换成 out/release-latest/images/imx6ull-aes-sd.img、去掉 seek；imx6ull-aes-emmc.img 是给 eMMC 的，走 UUU/UMS 写入，介质与镜像得配对（flash/09、flash/10 各有完整流程）。在容器里做烧录要 `--privileged` 且建议 `-u 0` 起，否则 ubuntu 用户写不了块设备；这一步留在主机做也完全成立，产物本来就是共享的。

::: warning 未实测标注
dd 烧录作用于实体 SD/eMMC 卡，本环境没有插卡设备，无法实际执行；命令、偏移与权限口径以上文为准，您首次烧录建议先拿空白卡演练。
:::

### 网络启动

板子走 TFTP/NFS 网络启动时，咱们得先满足一个前提：这份镜像没预装 TFTP/NFS 的服务端（apt 清单里既没有 tftpd-hpa 也没有 nfs-server）。要让容器自己当服务器，得进容器装包配置，临时容器装了即丢，起码得起个持久容器；更常见的做法是把服务留在主机——本仓库的现行拓扑就是主机侧 tftp 加 nfs-ganesha，容器只要跟板子同网段访问就行，这时最省心的是 host 网络模式：

```bash
# 主机 ~/imx-forge
docker run -it --rm --network host -v $(pwd):/workspace imx-forge:latest
```

容器直接共用主机网络栈，2049、69 这些端口不用映射。桥接模式加 `-p 2049:2049 -p 69:69` 只覆盖 NFS 与 TFTP 的主端口，NFS 的 mountd 端口是动态分配的，跨容器十有八九连不上，咱们别给自己埋这个坑。

## 六、性能与磁盘

编译速度上容器与主机差距很小，真要抠也有余地。构建开关这边最见效的是保持 BuildKit 开启（`DOCKER_BUILDKIT=1`），并行构建与缓存利用都靠它。并行度其实不用咱们操心，脚本里已经是 `make -j$(nproc)`（build-linux.sh 里就是 `-j${NPROC}`）。

您要是反复重编 Buildroot，可以挂个缓存卷，不过得挂对路径：Buildroot 开了 BR2_CCACHE=y，缓存目录是 `$(HOME)/.buildroot-ccache`，容器内即 /home/ubuntu/.buildroot-ccache，所以卷得写成 `-v build-cache:/home/ubuntu/.buildroot-ccache` 才真的接上。内核与 U-Boot 两条轨道走的是裸 make，当前不消费 ccache，给它们挂缓存卷是白挂。

临时文件吃 IO 的话，咱们拿 `--tmpfs /tmp:rw,size=4g` 把 /tmp 挪进内存。

磁盘这边，咱们不用为 out/ 操心：它本来就落在仓库根的绑定挂载里，不存在撑大容器层的说法，旧文档里单独挂载 out 的写法可以省了；真正的空间大头是悬空镜像与构建缓存，`docker system df` 先看占用，`docker system prune -a --volumes` 一次清干净，下手前确认没有要保留的旧版本镜像。另外，项目根放一份 .dockerignore，把 .git、document/ 这类进镜像没用的东西排除掉，构建上下文小了，上传与缓存判断都快。

## 七、故障排除

排障思路一句话：分层。docker build 挂了是镜像构建层，docker run 挂了是容器层，容器里编译挂了才是工具链层；三层的报错经常互相伪装，咱们把层分清再动手。常见问题收在下面这张表里：

| 现象 | 根因 | 解法 |
|------|------|------|
| 仓库根执行 docker build 报找不到 Dockerfile | 没指定 -f，默认在当前目录找 | `docker build -f docker/Dockerfile ...`，或 cd docker 后再构建 |
| 构建卡在工具链下载，最终网络错误 | developer.arm.com 访问慢或不通 | `--build-arg http_proxy=http://proxy:port` 与 `--build-arg https_proxy=http://proxy:port` 走代理，或 `--build-arg TOOLCHAIN_URL=` 指向镜像站；换 Dockerfile.cn 没用，它的工具链下载地址与标准 Dockerfile 完全相同 |
| apt 下载慢导致构建失败 | Ubuntu 官方 APT 源访问慢 | 换 Dockerfile.cn（APT 换阿里云源） |
| 容器里编出的文件在主机上改不动 | 容器 ubuntu 用户 UID 与宿主用户不一致 | 运行时 `-u $(id -u):$(id -g)`（构建参数 USER_ID 未接线，传了不生效） |
| 容器内 /workspace 是空的 | run 时不在仓库根，$(pwd) 挂错了目录 | 回仓库根重跑；`docker inspect` 查 Mounts 确认 |
| arm-none-linux-gnueabihf-gcc 提示 command not found | PATH 没带上工具链的 bin 目录 | 重进容器让 profile 生效；echo $PATH 逐段排查 |
| 容器启动即退出或行为异常 | 端口冲突、内存不足或 Docker 版本过旧 | netstat 查端口、free -h 查内存、docker --version 对版本 |
| picocom 打不开 /dev/ttyUSB0 | 设备没透进容器，或 WSL 侧没 attach | run 加 --device 或 --privileged；WSL2 先走 usbipd |
| Docker 占的磁盘只增不减 | 悬空镜像、停掉的容器、构建缓存堆积 | `docker system df` 排查，`docker system prune -a --volumes` 清理 |
| ghcr.io 拉镜像超时 | registry-mirrors 只加速 Docker Hub | 转本地构建（Dockerfile.cn） |

表里没覆盖的，咱们用 `docker logs` 看容器输出、`docker exec -it` 进现场、`docker stats` 看资源，三件套足够把大多数问题逼出原形；再深一层就轮到本节开头说的分层法了。

## 八、最佳实践

安全上咱们守住这几条：`--privileged` 只在烧录这类确实要全设备的场景开，平时用 `--device` 点对点放行；挂载只挂仓库根，别把 / 或整个 /dev 卷进来；镜像里非 root 的 ubuntu 用户别图省事改成 root 长期用。

协作上，团队统一锁一个镜像标签（比如 1.0.4，git tag 是 v1.0.4、镜像 tag 不带 v，tag 镜像缺依赖的局限，镜像从哪来那节说过了）而不是各自追 latest；构建参数的差异写进 README 或 Compose 文件里做版本化；CI 与本地用同一个镜像，出了问题才不用在咱们各自的机器之间互相怀疑。定期重拉或重建镜像拿安全更新，顺手 `docker system prune` 保持磁盘健康。

## 九、三个实战案例

### 案例一：外挂驱动的构建与部署

场景是编一个教程驱动并部署进板子的 rootfs。旧文档写过 cd /workspace/driver/led 手动 make、再 cp led.ko 到 rootfs/nfs，这条路已经走不通：driver/ 下是 01_tutorial_chardev_base 这类教程驱动目录，rootfs 树也不是随手 cp 的地方。现行做法是 scripts/driver_helper/ 的脚本集，咱们看有哪些驱动可编：

```bash
# 容器内 /workspace（主机 ~/imx-forge 同样可跑）
./scripts/driver_helper/build_driver.sh --list
```

```text
[INFO] 可用驱动列表
[INFO] 
[INFO] 📦 01_tutorial_chardev_base
[INFO]   └─ alpha-board [✓ Makefile 源码]
……（中间 22 组省略，完整名单自己跑一遍就有）……
[INFO] 总计: 24 个驱动, 22 个板卡配置
```

这份输出是笔者在本机实际跑出来的（24 个驱动、22 个板卡配置，色彩码已去）。接着构建、审查、部署三连：

```bash
# 容器内 /workspace
./scripts/driver_helper/build_driver.sh 04_tutorial_chardev_led_v2 --kernel=imx
./scripts/driver_helper/review_driver.sh 04_tutorial_chardev_led_v2
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/04_tutorial_chardev_led_v2/alpha-board --target=nfs
```

build_driver.sh 编出 .ko，产物收在 out/driver_artifacts/<驱动>/<板卡>/；驱动在 driver/device_tree/ 下配有 dts 覆盖时还会一并编出 .dtb，比如 05_tutorial_pinctrl_gpio 配了 imx6ull-aes-05_tutorial_pinctrl_gpio.dts。咱们这个示例 04 没配 dts，产物目录里只有 chardev_led_v2_02_driver.ko 和 build_info.txt，找不到设备树是正常现象。review_driver.sh 跑 modinfo 列出模块信息（vermagic 就列在里面，肉眼跟内核对），并核对符号表与依赖关系；deploy_driver.sh 把产物送去该去的地方，脚本开头的自述就是简化的驱动部署脚本、直接复制驱动产物到目标位置。`--target` 除了 nfs 还有 tftp（目录在 driver_helper.conf 里配，本机指向 /home/charliechen/tftp）、local、remote（SSH 传远端）。`--kernel=imx` 别省：驱动脚本默认按主线内核编，而系统完整构建默认走 NXP BSP 轨，轨错了 vermagic 对不上，板子上 insmod 直接被拒。

::: warning 未实测标注
部署完成后在实际板子上 insmod 加载、观察 dmesg 的输出，需要实体板子加串口终端，本环境没有板子无法验证；部署目标与参数以 scripts/driver_helper/README.md 和脚本 `--help` 为准，您实际部署时以板端的加载结果为准。
:::

### 案例二：改内核配置再重编

build-linux.sh 不收 menuconfig 这类参数，咱们看脚本 Usage 行的原话就知道：`Usage: $0 [--fast-build] [--release] [--release-version V]`，只认这几项。改内核配置得直接进内核构建树调 menuconfig，分步脚本的默认输出树是 out/linux：

```bash
# 容器内 /workspace
make -C third_party/linux-imx O=../../out/linux ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- menuconfig
```

这里有个坑要拆穿：`--fast-build` 跳过的只是 distclean，跳不过配置重放，脚本 main() 在 fast-build 模式下同样无条件执行 prepare_defconfig 加 do_configure，prepare_defconfig 每次把模板 driver/device_tree/alpha-board/linux/imx_aes_defconfig.template 灌进内核树，do_configure 再从 defconfig 重新生成 out/linux/.config。menuconfig 改完直接跑 `build-linux.sh --fast-build`，咱们的改动会被静默覆盖。想让改动活下来有两条路：一条是写回源头，menuconfig 之后用 `make ... savedefconfig` 把改动收成 defconfig，拿它更新模板 imx_aes_defconfig.template（把 CONFIG_EXTRA_FIRMWARE_DIR 的值改回 `${FIRMWARE_DIR}` 占位符，别把机器相关的绝对路径烧进共享模板），再跑 `build-linux.sh --fast-build` 增量重编，重放出来的 .config 就是咱们要的样子；另一条是绕开脚本手动增量编，.config 不会被碰：

```bash
# 容器内 /workspace（手动增量重编，不重放 .config）
make -C third_party/linux-imx O=../../out/linux ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc) zImage dtbs
```

要改的是 rootfs 配置就换一条路：`./scripts/build_helper/buildroot_menuconfig.sh` 打开的是 Buildroot 的配置界面，退出时加 `--savedefconfig` 把改动存回 rootfs/buildroot/configs/ 下的 defconfig。两个 menuconfig 管两棵不同的树，咱们别把它们混成一回事。

### 案例三：CI 流水线

咱们把同一镜像搬进 CI，本地与流水线的构建环境就完全一致了。GitLab CI 一段就够：

```yaml
# .gitlab-ci.yml
variables:
  GIT_SUBMODULE_STRATEGY: recursive
build:
  image: ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
  script:
    - ./scripts/release-all.sh
  artifacts:
    paths:
      - out/release-latest/
    expire_in: 1 week
```

GitHub Actions 这边咱们用 container 字段承接同一镜像：

```yaml
# .github/workflows/build.yml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Build all
        run: ./scripts/release-all.sh
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: out/release-latest/
```

两个示例都走 release-all.sh 一键入口，产物目录统一指到 out/release-latest/，与本地的权威路径一致；要拆细就换成分步脚本逐个调，效果相同。还有一处咱们别漏：本仓库的构建强依赖 third_party/ 下的子模块，GitLab 默认不拉子模块，所以上面配了 `GIT_SUBMODULE_STRATEGY: recursive`——GitHub 那边的 `submodules: recursive` 干的是同一件事；少了这步，头一个编 U-Boot 的阶段一开场就会在 third_party/uboot-imx 上摔跤。

::: warning 未实测标注
两段流水线配置没有在本环境的 CI 上实际跑过（本机没有可用的 CI 执行环境）；字段语法以 GitLab 与 GitHub 当前文档为准，镜像地址换成您仓库实际可拉取的来源。
:::

## 十、容器还是主机

| 对比项 | 容器开发 | 主机直装 |
|------|------|------|
| 新环境搭建 | 拉镜像即用，分钟级 | 装工具链加一堆依赖，半小时起步 |
| 编译性能 | 接近原生，挂载卷有少量开销 | 原生 |
| 环境一致性 | 全队同一镜像，可复现 | 机器之间容易漂移 |
| 设备访问 | 要 --device 或 --privileged 透传 | 直接可用 |
| 调试体验 | 串口烧录需额外参数 | 更直接 |
| 跨平台 | Linux、Windows（WSL2）、macOS 都行 | 基本限 Linux |
| 磁盘占用 | 镜像加缓存动辄数 GB | 只有工具链与源码 |

笔者的结论：新手与团队协作选容器，环境问题在 Docker 这一层一次性解决；主机直装留给性能敏感的全量构建与深度调试，两者的速度差异其实很小，不值得为它回去手装依赖。真要双轨并行，注意别让两套环境交叉写同一个 out/ 产物目录，新旧构建互相踩的排查成本远高于省下的那点配置时间。

## 常用命令速查

```bash
# 主机 ~/imx-forge
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest  # 拉镜像
docker build -f docker/Dockerfile -t imx-forge:latest .                # 本地构建
docker run -it --rm -v $(pwd):/workspace imx-forge:latest              # 临时容器
docker run -dit --name imx-dev -v $(pwd):/workspace imx-forge:latest   # 持久容器
docker exec -it imx-dev bash                                           # 进持久容器
docker images                                                          # 看镜像
docker ps                                                              # 看容器
docker system df                                                       # 看磁盘占用
docker system prune -a --volumes                                       # 全面清理
```

```bash
# 容器内 /workspace
./scripts/release-all.sh                        # 一键全量构建（连字符）
./scripts/build_helper/build-uboot.sh           # U-Boot
./scripts/build_helper/build-linux.sh           # NXP BSP 轨内核
./scripts/build_helper/build-mainline-linux.sh  # 主线轨内核
./scripts/build_helper/build-buildroot.sh       # Buildroot rootfs
picocom -b 115200 /dev/ttyUSB0                  # 串口终端
```

## 继续学习

- 上一篇：[Docker 基础知识](01_docker_basics.md)，容器、镜像与卷这些概念的地基
- 下一篇：Docker 卷到本篇收尾，rootfs 的构建细节接着去 [Buildroot 根文件系统](../buildroot/) 补全，那边从工作原理一路讲到 Qt6 集成
- 深读：串口通道选型与 usbipd 全流程见 [串口终端：开发台的第二块屏幕](../workflow/03_serial_terminal.md)；板卡接口与启动介质见 [板子硬件接口速查表](../start/03_hardware_quick_reference.md)；项目整体上手路线见 [IMX-Forge 快速入门指南](../../QUICK_START.md)
