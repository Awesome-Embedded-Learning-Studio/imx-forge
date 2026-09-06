---
title: 主机与板子传文件：scp、rsync 与 NFS root 的三种选法
---

# 主机与板子传文件：scp、rsync 与 NFS root 的三种选法

> 交叉编译出来的 demo 怎么放到板子上，板上抓的日志怎么回宿主，这是咱们每天都在做的小动作，可一旦选错通道，等着您的就是连不上、被拒、传完就丢这一串坑。本篇是工作流卷的收尾篇，把 scp、rsync 与 NFS root 三种通道的适用边界讲清楚。上一篇 [tasks.json 命令模板](05_tasks_json.md) 把构建命令一键化之后，这一篇补上产物与板子之间的最后一段路；后面调试卷部署要调试的程序、抓日志，用的都是这里打通的链路。

::: tip 前置知识 · 咱们的环境
- WSL2 环境的网络与文件系统差异，您回 [WSL2 开发注意事项](01_wsl2_env_config.md) 看；首次把板子跑起来、串口登录的完整流程见 [启动与调试](../practical/03_boot_and_debug.md)
- 咱们本篇的大量结论可以在仓库里直接核实：rootfs 配置在 rootfs/buildroot/configs/imx6ull_aes_defconfig，本地构建树在 out/release-latest/buildroot，rootfs 目录在 out/release-latest/rootfs
- 路径上下文：咱们的宿主操作都在仓库根 ~/imx-forge 下进行，menuconfig 走 ./scripts/build_helper/buildroot_menuconfig.sh，rootfs 构建走 ./scripts/build_helper/build-buildroot.sh，交叉工具链装在 /opt/arm-gnu-toolchain(Arm GNU Toolchain 15.2.Rel1)
:::

## 一、先分清两棵目录树

咱们手上其实一直有两棵树。一棵在宿主上，就是 ~/imx-forge 这棵工作区：源码、脚本、补丁，加上 out/ 底下的构建产物，全部归您在主机侧支配。另一棵在板子上，rootfs 展开出来的运行系统，内核拿它当根，init 从里面起，咱们的程序在里面跑。传文件这件事，本质就是把字节从这棵树搬到那棵树，方向有两个：产物下去，日志上来。

三种通道对应三类搬家需求。scp 管一次性小件，一个二进制、一份日志，推一下拉一下就完；rsync 管目录级同步，整个目录反复推，只想传有变化的那部分；NFS root 则把问题整个换了个形态。板子以 NFS 方式启动时，它的根文件系统就是宿主导出的那个目录，两棵树在文件层面合成了同一棵：您在宿主上往导出目录里写一个文件，板子上立刻就能看到。这时候传文件退化成了写文件，写到导出目录就是部署。这个视角是第四节的前提，咱们先把它放在这。

## 二、scp：一次性小件

### dropbear 不在 defconfig 里

这里有个必须交代清楚的勘误，也是本篇最重要的前提：板端的 ssh/scp 服务由 dropbear 提供，而仓库的 defconfig 里没有开它。咱们拿 grep 核实：

```bash
# 主机 ~/imx-forge
grep -n DROPBEAR rootfs/buildroot/configs/imx6ull_aes_defconfig; echo rc=$?
```

```text
rc=1
```

没有任何输出，退出码 1，defconfig 里一行 DROPBEAR 都没有。也就是说，干净构建、CI 产出的 rootfs 是没有 ssh 与 scp 的。而本地 out 树是另一回事：out/release-latest/buildroot/.config 第 2433 行附近，dropbear 是咱们手动开出来的本地实验状态：

```ini
# out/release-latest/buildroot/.config(本地实验状态)
BR2_PACKAGE_DROPBEAR=y
BR2_PACKAGE_DROPBEAR_CLIENT=y
# ……中间行省略……
# BR2_PACKAGE_RSYNC is not set
```

所以咱们本地 rootfs 里能 ls 到这两样东西，但它们是本地实验状态，不是内置事实：

```bash
# 主机 ~/imx-forge
ls out/release-latest/rootfs/usr/bin/scp out/release-latest/rootfs/etc/init.d/S50dropbear
```

```text
out/release-latest/rootfs/etc/init.d/S50dropbear
out/release-latest/rootfs/usr/bin/scp
```

您想让干净构建也带上，就进 menuconfig 把包开出来，菜单位置是 Target packages → Networking applications → dropbear，进去时给脚本带上 --savedefconfig：

```bash
# 主机 ~/imx-forge
./scripts/build_helper/buildroot_menuconfig.sh --savedefconfig
```

这个参数管的是持久化：menuconfig 里保存只写 out/release-latest/buildroot/.config，不回写 defconfig，您要是省了它，干净构建与 CI 产出的 rootfs 照样没有 dropbear，--reconfigure 重放 defconfig 时还会把开关悄悄改回去。不带参数跑，退出时脚本也会提醒您补这一步；带上它，退出菜单后脚本自动 make savedefconfig，把改动写回 rootfs/buildroot/configs/imx6ull_aes_defconfig，干净构建才真带上。不想动 defconfig 也随您，那就停在本地实验状态，和上面交代的“不是内置事实”是同一回事。

这与调试卷开 gdbserver 是同一个套路：defconfig 刻意留白，让您自己动手开一次，知道这东西从哪来，细节在 [gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md) 的第二节。好消息是 dropbear 是普通包，不像工具链那颗开关有 stamp 的坑，开完重跑 build-buildroot.sh 就会正常编进 rootfs。编进之后，rootfs 里多出来的实体二进制只有一个：366680 字节的 /usr/sbin/dropbear，外加一个 S50dropbear 启动脚本。咱们 ls -l 会看到 /usr/bin/ 下的 scp、ssh、dbclient、dropbearkey、dropbearconvert，五个全是 -> ../sbin/dropbear 的软链。dropbear 是个多调用二进制，起个名字就变一个程序。

### 板端服务与登录现状

S50dropbear 这类 S 打头的脚本由 rcS 在开机时启动，服务有没有真起来，咱们看虚拟机里的串口日志：

```text
Starting dropbear sshd: OK
```

登录的密码现状咱们同样拿 grep 核实：defconfig 没有设 root 密码(grep ROOT_PASSWD 零命中)，而本地 .config 第 553 行是 BR2_TARGET_GENERIC_ROOT_PASSWD="root"，于是本地 rootfs 的 /etc/shadow 里 root 行是一个 SHA-256 哈希：

```text
root:$5$94ylje7l$oLImnXo28VeZcsAhPWOEdSYqTyICyu6oG02J8OUk42C:::::::
```

这段哈希对应密码 root，是本地构建时的配置；您自己构建时以您设的值为准，menuconfig 的 System configuration 里可以改 Root password。有一个机制值得您知道：dropbear 默认拒绝空密码登录，所以干净构建若不给 root 设密码，ssh 是登不进去的，先设密码再谈传输。板子的 IP 从哪看？网络启动的内核日志有 IP-Config: Complete 那几行，dhcp 场景看 udhcpc 的回显，这些行的字段怎么对应，[NFS 网络启动排查](../rootfs/05_nfs_wsl_troubleshoot.md) 里有现成案例和速查表条目；内核日志整体的分段怎么读，是 [串口日志怎么读](../debug/03_serial_log_reading.md) 一章的主场，这里不占用篇幅。

### 推与拉

板端服务就绪后，两个方向的命令各一条：

```bash
# 主机 ~/imx-forge
scp -O demo root@板子IP:/root/        # 推：产物下去
scp -O root@板子IP:/root/log.txt .    # 拉：日志上来
```

实际板子上跑的同样是 dropbear，咱们这两条命令里的 -O 也得带上，理由见下面的实测。

::: warning 未实测标注
实际的板子上的 ssh 交互回显(首次登录的指纹确认、传输进度条)本环境采集不了，笔者手边没有上电的 i.MX6ULL;命令形式与认证流程以下面 QEMU 等价环境的实测为准，参数完全一致。
:::

### 手边没板子？QEMU 等价环境(全程实测)

手边没板子时，咱们让 QEMU 客户机把同一条链路原样跑一遍，思路与 [gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md) 的 QEMU 路线一致：一块 -nic user 网卡加 hostfwd，把宿主的 5022 转进虚拟机的 22。命令按实测现场原样给出：

```bash
# 主机 ~/imx-forge
out/qemu/build/qemu-system-arm -M mcimx6ul-evk -m 512M \
    -kernel out/mainline/linux/arch/arm/boot/zImage \
    -dtb out/qemu/imx6ull-aes.dtb \
    -append "console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw" \
    -drive file=out/qemu/rootfs.ext4,if=sd,index=1,format=raw \
    -nic user,hostfwd=tcp:127.0.0.1:5022-:22 \
    -nographic -no-reboot
```

咱们登录进虚拟机后把网络点亮(网卡命名反转的来龙去脉在调试卷讲过，这里照抄结论)：

```bash
# QEMU 客户机 /
udhcpc -i eth1 >/dev/null 2>&1; ping -c 1 -W 3 10.0.2.2 >/dev/null 2>&1; echo NETRC=$?
echo DROPBEAR_PID=$(pidof dropbear)
```

串口日志摘录贴在下面给咱们核对，三行证据都齐：链路点亮、到网关的路通了、dropbear 在跑：

```text
Starting dropbear sshd: OK
# ……中间启动日志省略……
# udhcpc -i eth1 >/dev/null 2>&1; ping -c 1 -W 3 10.0.2.2 >/dev/null 2>&1; echo NETRC=$?
[   31.214335] fec 2188000.ethernet eth1: Link is Up - 100Mbps/Full - flow control rx/tx
NETRC=0
# echo DROPBEAR_PID=$(pidof dropbear)
DROPBEAR_PID=132
```

咱们从宿主侧连 127.0.0.1:5022 探一下，服务端版本应声而出：

```bash
# 主机 ~/imx-forge
nc 127.0.0.1 5022 < /dev/null | head -1
```

```text
SSH-2.0-dropbear_2025.89
```

咱们推一个 47 字节的文本上去，两端各跑一遍 md5sum 比对哈希：

```bash
# 主机 ~/imx-forge
scp -O -P 5022 /tmp/from-host.txt root@127.0.0.1:/root/
ssh -p 5022 root@127.0.0.1 'ls -l /root/from-host.txt; md5sum /root/from-host.txt'
md5sum /tmp/from-host.txt
```

```text
-rw-------    1 root     root            47 Sep  2 04:35 /root/from-host.txt
414ce994242bc9ef58730805bc405d54  /root/from-host.txt
414ce994242bc9ef58730805bc405d54  /tmp/from-host.txt
```

哈希一字不差，文件完整落进了虚拟机的 /root，推的方向通了。权限位这里也交代清楚：宿主侧 /tmp/from-host.txt 本是 644，落到板端成了 600，机制在 S50dropbear——它带着 umask 077 启动 dropbear，传统 SCP 协议建新文件要过这道掩码，0644 被削到 0600，属预期行为。拉的方向咱们同样验证过：虚拟机里执行 dmesg > /root/log.txt 生成 19444 字节的内核日志，宿主 scp -O -P 5022 root@127.0.0.1:/root/log.txt . 拉回来，字节数一致。head -2 的第二行才是内核版本行，原样 7.1.0-dirty(那个 -dirty 后缀是内核树上带着未提交改动才有的)，编译器正是 Arm GNU Toolchain 15.2.Rel1。链路双向可用，咱们两头都试过了。

::: warning scp 报 /usr/libexec/sftp-server: not found
咱们实测过一次不带 -O 的 scp，传输就断在这两行：

```text
sh: /usr/libexec/sftp-server: not found
scp: Connection closed
```

原因是宿主的 OpenSSH 客户端(本机 9.6p1)从 9.0 起默认走 SFTP 协议，而咱们板端的 dropbear 不带 sftp-server 组件。解法是加 -O 让客户端退回传统 SCP 协议，上面命令里的 -O 对 dropbear 是必需的。
:::

::: warning localhost 卡超时先查解析顺序(机制性提醒，本机未复现)
hostfwd 写 tcp::5022-:22 时 slirp 只监听 IPv4，而有的机器上 localhost 会先解析到 ::1，ssh 就挂在 Connection timed out 上。咱们在本机实测时 localhost 与 127.0.0.1 都完成了 SSH 握手，这条超时没有复现；hostfwd 与连接两头显式写 127.0.0.1 属于防御性写法，不把链路押在 localhost 的解析顺序上。您在别的机器上卡超时时，可以先查这里。
:::

## 三、rsync：目录级同步

要频繁推整个目录时，scp 就不够看了：它每次全量拷贝，目录里改了一个文件也得整个重来。rsync 只传差异，这正是它的位置。但板端现状到底如何，咱们在虚拟机里实际跑一条命令就见分晓：

```bash
# 主机 ~/imx-forge(经 ssh 在 QEMU 客户机里执行)
ssh -p 5022 root@127.0.0.1 'rsync --version 2>&1 | head -1'
```

```text
sh: rsync: not found
```

板端没有 rsync，defconfig 与本地 .config 都没开，这层现状咱们记下。主要的路子是开这项软件包：menuconfig 里与 dropbear 同一节，Target packages → Networking applications → rsync，照第二节的 --savedefconfig 那一步存回 defconfig，重跑构建，然后目录推送一条命令，第二次执行只传有变化的部分：

```bash
# 主机 ~/imx-forge
rsync -av demo_dir/ root@板子IP:/root/demo_dir/
```

退而求其次的选法不需要动配置，咱们借现成的 ssh 通道走一行 tar 管道，同样全程实测过：宿主打包、管道过 ssh、板端解开，md5 两端一致：

```bash
# 主机 ~/imx-forge
tar czf - -C /tmp/scp-proof tardir | ssh root@板子IP 'cd /root && tar xzf -'
ssh root@板子IP 'ls -l /root/tardir; md5sum /root/tardir/a.txt'
md5sum /tmp/scp-proof/tardir/a.txt
```

```text
total 8
-rw-r--r--    1 1000     1000            23 Sep  2 03:18 a.txt
-rw-r--r--    1 1000     1000            14 Sep  2 03:18 b.txt
102fab5c254aeb315970767e19a3f0e1  /root/tardir/a.txt
102fab5c254aeb315970767e19a3f0e1  /tmp/scp-proof/tardir/a.txt
```

选型一句话：您若频繁同步整目录且要增量，rsync 值得开这项；一次性搬运，tar 管道不动配置最省事。

## 四、NFS root：写进就是部署

NFS root 形态下咱们连传输命令都省了。本仓的 scripts/manual_mount_nfs.sh 做的就是导出源的 bind-mount，脚本头部的默认值写得明明白白：

```bash
# 主机 ~/imx-forge
sed -n '40,41p' scripts/manual_mount_nfs.sh
```

```text
DEFAULT_SOURCE_DIR="${PROJECT_ROOT}/out/release-latest/rootfs"
DEFAULT_TARGET_DIR="${PROJECT_ROOT}/rootfs/nfs"
```

默认导出源就是 out/release-latest/rootfs 本身。也就是说板子的根文件系统与咱们的 release rootfs 是同一份文件：cp demo out/release-latest/rootfs/root/ 敲完，板子上 /root/demo 立刻可见，这就是“写进就是部署”的开发效率，也是 NFS 在开发阶段无可替代的原因。

用 --source= 换掉 bind-mount 的源目录后，咱们必须重启 NFS 服务(本仓用 nfs-ganesha)，否则板子上已拿到的文件句柄全部失效，读写报 ESTALE，这是项目里实际踩过的已知坑；NFS 服务端的排查全景在 [NFS 网络启动排查](../rootfs/05_nfs_wsl_troubleshoot.md)。

直接改 out/release-latest/rootfs 的文件，活不过下一次构建：build-buildroot.sh 的 Step 3 用 rsync --delete 把 buildroot 的 target/ 同步过来，脚本里的原话是“保持 release rootfs 与 buildroot target 完全一致(删除多余文件)”，您手写进去的文件正是那个多余文件。[gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md) 第二节末尾有同款提醒，这里只补一句后果：改完不重新打包镜像就重启 QEMU，或下次跑构建，文件就没了。

那什么东西可以留在 rootfs 里？纪律是分层的。临时调试件放板端 /tmp，什么都不用管，重启自己清掉。要留存的配置走 overlay：本地 .config 第 580 行就是现成配置 BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"，落到 rootfs/buildroot/overlay/ 目录，现在里面只有一个 README.md，等着您添第一批文件。要留存的程序正经做成 package，构建、依赖、清理都归 Buildroot 管，做法在 [添加自定义 package](../buildroot/07_custom_package.md) 有展开。

## 五、选型判据与一条纪律

三种通道不是并列的三选一，咱们按文件的留存意图分层。第一问永远是：这个文件明天还要不要在？不要，scp 丢进板端 /tmp，用完拉倒。要，而且它是配置，进 overlay，跟着构建走。要，而且它是程序产物，走构建出镜像，scp 只当验证的便道。NFS root 期间“写进就是部署”最顺手，但请把它当调试的便利，别当留存的手段，Step 3 的 rsync --delete 不会跟您商量。

咱们把这条纪律立住之后，回头看三种选法其实各就各位：scp 管一次性小件，rsync 管目录增量，NFS root 管开发节奏。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| scp/ssh 连不上板子 | defconfig 没开 dropbear，或网卡没地址 | menuconfig 开软件包重构建；看内核日志确认 IP |
| 登录被拒(Permission denied) | root 空密码(dropbear 默认拒)或密码与构建配置不符 | menuconfig 设 Root password，本地为 root |
| scp 报 sftp-server not found | OpenSSH 9.0+ 默认走 SFTP，dropbear 无此组件 | scp 加 -O 退回传统协议 |
| localhost:5022 连接超时 | slirp hostfwd 只监听 IPv4，localhost 解析到 ::1 | hostfwd 与连接两头写 127.0.0.1 |
| 改了 out/release-latest/rootfs，下次构建消失 | Step 3 的 rsync --delete 清多余文件 | 留存走 overlay 或 package，临时进 /tmp |
| NFS 读写报 ESTALE | bind-mount 换源后没重启 nfs-ganesha | 重启 NFS 服务后再挂载 |
| rsync 报 command not found | 板端没开 BR2_PACKAGE_RSYNC | 开软件包重构建，或退到 tar 管道 |

## 继续学习

- 上一篇：[tasks.json 命令模板](05_tasks_json.md)
- 下一篇：工作流卷到此收尾。接下来两条路：调试卷从 [gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md) 进入，那一篇部署试验程序用的正是本篇的 scp；工程实战卷在 document/tutorial/project/ 目录下等着咱们
- 深读：把程序做成 package 的做法看 [添加自定义 package](../buildroot/07_custom_package.md)，构建侧调试选项的取舍再看 [Buildroot 调试与排错](../buildroot/10_debugging.md)；NFS 服务端排查全景与板端 IP(IP-Config 行)的读法回 [NFS 网络启动排查](../rootfs/05_nfs_wsl_troubleshoot.md)；内核日志怎么读，[串口日志怎么读](../debug/03_serial_log_reading.md) 有专章
