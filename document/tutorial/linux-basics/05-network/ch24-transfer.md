# 第 24 章  文件传输

> **Part 5 · 网络与远程**

---

## 引子

你在开发板上编译好了固件，要传到主机上烧录。
你在主机上改好了设备树，要推到开发板上测试。

文件在两台机器之间来回跑，是嵌入式开发的日常。

但这件事比它看起来的要深——表面上是"传文件"，实际上是一个选择问题。scp 一行命令搞定，但它每次都全量传输。rsync 聪明得多，只传变化的部分——可配置也复杂得多。tftp 简陋到几乎没有安全机制，却是 U-Boot 引导阶段传文件的标准方式。

为什么嵌入式开发不能只用 scp？为什么 U-Boot 阶段非得用 tftp 这种"上古协议"？

答案藏在一个反直觉的事实里：**不同的传输场景，核心矛盾不一样。** 有时候你追求安全，有时候你追求效率，有时候你追求的仅仅是"能跑起来"。

---

## 背景与动机

上一章我们搭好了 SSH 隧道，可以远程连接开发板了。但连上只是第一步——你在主机上写的代码、编译的固件、修改的配置文件，都需要在两台机器之间搬来搬去。

在嵌入式开发中，文件传输的频率比你想象的高得多：

- 编译完内核镜像 `zImage`，要传到开发板去启动
- 修改了设备树 `.dtb`，要推过去让内核重新加载
- 调试驱动时，可能一天要来回传几十次固件
- 最终发布时，整个项目目录需要从开发板同步到主机打包

这些场景对传输工具的需求差异很大。传一个几 MB 的内核镜像，scp 够用。同步一个包含几百个源文件的工程目录，scp 就力不从心了——每次都全量传，浪费时间。而到了 U-Boot 引导阶段，开发板上还没有操作系统，SSH 根本跑不起来，你得用 tftp 这种最原始的方式先把内核传过去。

选对工具，省的不只是时间，还有耐心。

---

## 概念层

### 三种搬运方式——类比第一次：建立映射

你可以把文件传输想象成搬家。

scp 是打车搬家——你把东西装上车，点对点送到目的地，简单直接。不管目的地有没有一样的东西，全部再搬一遍。

rsync 是专业搬家公司——出发前先打电话给目的地确认："这个沙发你们有了吧？有了就不搬了。只搬新买的和换过的东西。"省油、省时、省路费。

tftp 是工地上的传送带——没有包装、没有保险、甚至没有确认签收。但在楼还没盖好之前，它是唯一能把建材送上楼的工具。

但"搬家"这个比喻有一个共同失真的地方：搬家搬的是物理对象，搬完原处就没了。文件传输搬的是**信息**——源文件不会因为传了一份到目的地就消失。rsync 更像"远程复制 + 差异检查"的组合体，它的价值不在于"搬"，而在于"判断该搬什么"。

### scp——最直接的通道

scp（Secure Copy Protocol）基于 SSH 协议，在两台机器之间建立加密通道，然后在这个通道里传文件。你在第 23 章搭好的 SSH 环境，scp 直接就能用——不需要额外安装任何东西。

scp 的语法极其简单：

```bash
# 从本机传到远程
$ scp 本地文件路径 用户名@远程主机:远程路径

# 从远程拉到本机
$ scp 用户名@远程主机:远程文件路径 本地路径

# 传目录需要 -r
$ scp -r 项目目录/ 用户名@远程主机:~/projects/
```

scp 的本质就是"加密的 cp"。它不检查目标位置已有的文件，不做增量判断，每次都是全量传输。传一个 10 MB 的文件，无论目标位置是否已经有 9.9 MB 的相同内容，scp 都会重新传一遍。

对于单个文件、临时传一个小东西，scp 是最优解。但对于项目级同步，它在浪费带宽。

### rsync——只传变化的部分

这就是 rsync 登场的理由。rsync 的全称是 "remote synchronize"，它的核心能力是**增量同步**——只传输源端和目标端之间有差异的部分。

rsync 默认使用"快速检查"（quick check）算法：比较每个文件的**大小**和**最后修改时间**。如果两者都匹配，rsync 认为文件相同，直接跳过。这意味着如果你有 100 个文件的项目目录，只改了其中 2 个，rsync 只传那 2 个文件。

```bash
# 基本同步：将 src/ 目录同步到远程
$ rsync -avz 项目目录/ 用户名@远程主机:~/projects/

# -a  归档模式（保留权限、时间戳、软链接等）
# -v  显示详细过程
# -z  传输时压缩数据
```

回到搬家的类比：rsync 就是那个搬家公司，出发前先盘点"哪些东西已经有了"。

但"快速检查"有一个潜在问题：如果一个文件的内容变了，但你碰巧把它的大小和修改时间也改回了原来的值——概率极低，但理论上可能——rsync 会误判为"没变"。如果你需要绝对精确的比较，加 `-c` 选项让 rsync 计算文件内容的校验和。代价是速度变慢，因为要读每个文件的全部内容来算哈希。

> ⚠️ **危险：`--delete` 选项**
>
> `rsync --delete` 会删除目标端存在但源端不存在的文件，让目标端成为源端的**精确镜像**。
> 这是一个极其危险的操作——如果你把源和目标写反了，rsync 会把目标端多出来的文件全部删掉。
> 这个坑真的能让你血压拉满，尤其是目录里有一周的工作成果的时候。
>
> 建议先加 `--dry-run` 模拟一遍，确认没有误删，再去掉 `--dry-run` 实际执行。

### sftp——交互式文件管理

sftp（SSH File Transfer Protocol）不是 FTP 的安全版本——它是一个完全独立的协议，只是碰巧名字里也有 FTP。sftp 基于 SSH，提供交互式的文件浏览和传输能力。

你可以把 sftp 理解成"命令行版的文件管理器"——它让你像在本地一样 `cd`、`ls`、`mkdir`，但同时操作本地和远程两端的文件系统。

```bash
# 连接到远程主机
$ sftp 用户名@远程主机

# 连上之后进入交互模式
sftp> ls              # 列出远程文件
sftp> lls             # 列出本地文件（命令前加 l 表示 local）
sftp> get 远程文件     # 下载
sftp> put 本地文件     # 上传
sftp> exit            # 退出
```

sftp 适合这种场景：你不确定远程机器上有什么文件，想先看看再决定传哪些。scp 需要提前知道精确的路径，sftp 可以边看边传。

### tftp——嵌入式开发的特殊通道

现在来到本章最关键的部分。

tftp（Trivial File Transfer Protocol）是所有传输工具中最简陋的一个：

- 使用 **UDP** 协议（不是 TCP），没有连接建立的开销
- 没有用户认证，没有加密，没有目录浏览
- 协议极其简单，代码量小到可以塞进 bootloader 里

"这么简陋的东西谁会用？"——你可能会这么想。

答案是：**所有嵌入式开发者都会用。**

原因在于 U-Boot 引导阶段。当开发板上电、U-Boot 启动之后，Linux 内核还没有加载，文件系统还没有挂载——SSH 跑不起来，scp 跑不起来，rsync 更不可能。但你需要把内核镜像和设备树文件传到开发板的内存里，让 U-Boot 加载并启动。

tftp 就是这个阶段的唯一通道。U-Boot 内置了 tftp 客户端，只需要一条命令就能从网络上的 tftp 服务器下载文件到内存：

```
# U-Boot 命令行中的 tftp 操作
=> tftp 0x80800000 zImage
# 从 tftp 服务器下载内核镜像到内存地址 0x80800000

=> tftp 0x83000000 imx6ull.dtb
# 下载设备树文件
```

tftp 的默认端口是 **69/UDP**——客户端初始连接到服务器的 69 端口，后续数据传输使用动态分配的端口。这个端口号是协议规定的，不需要你手动设置。

### 类比第三次——回收验证

回到搬家的类比。你现在应该能看清三种工具各自的定位了：

- **scp 是打车**——临时搬点东西，简单直接，但每次都全量搬运
- **rsync 是搬家公司**——先盘点再出发，只搬变化的部分，适合大规模同步
- **tftp 是工地传送带**——在楼还没盖好的时候，它是唯一能把建材送上楼的工具

如果"工地传送带"坏了——也就是 tftp 服务没配好——你的开发板就卡在 U-Boot 阶段，内核都加载不了。这就是为什么嵌入式开发离不开 tftp：它不是"好用"，而是"没它不行"。

---

## 实践层

### 4.1 用 scp 传文件——日常最简单的选择

**传单个文件**

目标：把编译好的内核镜像传到开发板。

```bash
$ scp zImage dev@192.168.1.100:/home/dev/
# 预期输出
zImage                          100%   10MB   5.2MB/s   00:02
```

`scp` 后面跟的是"源:目标"。本地路径直接写，远程路径用 `用户名@主机:路径` 的格式。传输完成后会显示进度条和速度。

**反向——从开发板拉文件**

```bash
$ scp dev@192.168.1.100:/var/log/syslog ./syslog-dev.log
# 预期输出
syslog                          100%  245KB   3.1MB/s   00:00
```

**传整个目录**

加 `-r` 递归：

```bash
$ scp -r ~/projects/driver-module/ dev@192.168.1.100:~/driver-module/
```

scp 在这里有一个容易踩的坑：远程路径末尾有没有 `/`，结果可能不一样。`~/dir` 表示 `dir` 这个目录本身，`~/dir/` 表示 `dir` 目录**里面**的内容。这一点 rsync 也有同样的行为，后面会遇到。

### 4.2 用 rsync 做增量同步——项目级传输的标准

**基本同步**

假设你在主机上有一个嵌入式项目目录 `imx-driver/`，要同步到开发板：

```bash
$ rsync -avz ~/projects/imx-driver/ dev@192.168.1.100:~/imx-driver/
# 预期输出（第一次同步，全量传输）
sending incremental file list
created directory imx-driver
main.c
driver.h
Makefile
README.md

sent 15,234 bytes  received 128 bytes  6,164.80 bytes/sec
total size is 14,890  speedup is 1.00
```

**验证增量特性——只改一个文件再同步**

```bash
$ touch ~/projects/imx-driver/main.c    # 修改时间戳模拟文件变更
$ rsync -avz ~/projects/imx-driver/ dev@192.168.1.100:~/imx-driver/
# 预期输出（只传了一个文件）
sending incremental file list
main.c

sent 5,120 bytes  received 64 bytes  3,456.00 bytes/sec
total size is 14,890  speedup is 2.90
```

注意 `speedup` 值——这次是 2.90，意味着 rsync 通过跳过未变化的文件，速度是全量传输的近 3 倍。文件越多，这个优势越大。

这里有一个微妙但重要的细节：源路径末尾的 `/`。

```bash
# 有 /  —— 同步目录里面的内容到目标
$ rsync -avz src/ dest/

# 没有 / —— 把 src 目录本身作为子目录放到 dest 下面
$ rsync -avz src dest/
# 结果是 dest/src/
```

这个行为和 scp 一致，但 rsync 用得更多，所以更容易踩到。记不住的话，就记住一条：**同步目录内容，末尾永远加 `/`。**

**`--delete` 的正确用法**

假设你在源端删掉了一些过时的配置文件，希望目标端也同步删除：

```bash
# 先用 --dry-run 模拟，看看会删什么
$ rsync -avz --delete --dry-run ~/projects/imx-driver/ dev@192.168.1.100:~/imx-driver/
# 预期输出
deleting old_config.h
deleting unused_driver.c

# 确认无误后，去掉 --dry-run 实际执行
$ rsync -avz --delete ~/projects/imx-driver/ dev@192.168.1.100:~/imx-driver/
```

`--dry-run` 是你的安全网。每次用 `--delete` 之前先模拟一遍，这不是多余，是必须。

### 4.3 用 sftp 交互式浏览和传输

当你不确定远程机器上有什么文件时，sftp 比 scp 更方便：

```bash
$ sftp dev@192.168.1.100
# 预期输出
Connected to 192.168.1.100.
sftp>
```

进入交互模式后：

```bash
sftp> ls                        # 远程：列出文件
firmware/  drivers/  config.txt  zImage

sftp> lls                       # 本地：列出文件
boot.img  dtb  modules/

sftp> cd firmware               # 远程：进入目录
sftp> get u-boot.imx            # 下载到本地
Fetching /home/dev/firmware/u-boot.imx to u-boot.imx
u-boot.imx                      100%  512KB   4.8MB/s   00:00

sftp> put boot.img firmware/    # 上传到远程指定目录
Uploading boot.img to /home/dev/firmware/boot.img
boot.img                        100%   25MB   6.1MB/s   00:04

sftp> exit
```

sftp 的命令前缀规则很简单：普通命令操作远程，加 `l`（local）前缀操作本地。`ls` 看远程，`lls` 看本地；`cd` 切远程目录，`lcd` 切本地目录。

### 4.4 搭建 tftp 服务器——嵌入式开发必配

这是本章最重要的实操环节。如果你的开发板需要通过 U-Boot 的 tftp 命令加载内核，你必须在主机上跑一个 tftp 服务。

**安装 tftpd-hpa**

Ubuntu 上最常用的 tftp 服务端包是 `tftpd-hpa`：

```bash
$ sudo apt install tftpd-hpa
# 预期输出
Reading package lists... Done
The following NEW packages will be installed:
  tftpd-hpa
...
Setting up tftpd-hpa (5.2+dfsg-1) ...
```

**配置 tftp 服务**

tftpd-hpa 的配置文件在 `/etc/default/tftpd-hpa`：

```bash
$ cat /etc/default/tftpd-hpa
# 默认配置
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
```

`TFTP_DIRECTORY` 是 tftp 的根目录，所有要通过 tftp 传输的文件都放在这里。`TFTP_ADDRESS` 中的 `69` 是 tftp 的默认端口号——这是协议规定的，一般不需要改。来创建目录并设置权限：

```bash
# 创建 tftp 根目录并设置权限
$ sudo mkdir -p /srv/tftp
$ sudo chown -R tftp:tftp /srv/tftp
$ sudo chmod -R 777 /srv/tftp

# 重启 tftp 服务
$ sudo systemctl restart tftpd-hpa
$ sudo systemctl status tftpd-hpa
# 预期输出
● tftpd-hpa.service - LSB: HPA tftp server
     Active: active (running)
```

**测试 tftp 服务器**

在 tftp 根目录放一个测试文件，然后用 tftp 客户端验证下载：

```bash
$ echo "tftp test" | sudo tee /srv/tftp/test.txt
$ sudo apt install tftp-hpa    # 安装 tftp 客户端
$ tftp localhost
tftp> get test.txt
Received 11 bytes in 0.0 seconds
tftp> quit
$ cat test.txt
tftp test
```

能下载，说明 tftp 服务正常工作。

**在 U-Boot 中使用 tftp**

开发板一侧，确保 U-Boot 的网络参数配置正确：

```
# U-Boot 命令行
=> setenv ipaddr 192.168.1.100        # 开发板 IP
=> setenv serverip 192.168.1.10       # tftp 服务器（你的主机）IP
=> saveenv                            # 保存环境变量

# 下载内核镜像到内存
=> tftp 0x80800000 zImage
Using ethernet device
TFTP from server 192.168.1.10; our IP address is 192.168.1.100
Filename 'zImage'.
Load address: 0x80800000
Loading: #################
         2.5 MB/s
done
Bytes transferred = 6144000 (5DC000 hex)
```

到这一步，内核镜像已经躺在开发板的内存里了，等待 U-Boot 的 `bootm` 命令去启动它。tftp 的使命完成——简陋、粗暴，但在操作系统还不存在的阶段，它是唯一的桥梁。

---

## 练习题

走到这里，文件传输的工具箱应该已经装好了。下面几道题帮你确认理解是否到位——或者你以为清楚了。

**练习 24.1** ⭐（理解）

scp 和 rsync 传输同一个 100 MB 的文件，目标位置已经有一个 99 MB 内容相同的旧版本。哪个更快？为什么？

> **提示**：回顾 rsync 的"快速检查"机制——它比较的是什么？

**练习 24.2** ⭐⭐（应用）

搭建 tftp 服务器后，你需要通过 U-Boot 的 tftp 命令加载内核镜像 `zImage` 到内存地址 `0x80800000`，然后启动。写出完整的 U-Boot 命令序列（设置 IP、下载、启动）。

**练习 24.3** ⭐⭐⭐（思考）

为什么 tftp 使用 UDP 而不是 TCP？如果在网络不稳定的环境下使用 tftp 传大文件，可能会出现什么问题？U-Boot 的 tftp 实现为什么不需要 TCP？

> **提示**：想想 bootloader 阶段的资源约束——内存有限、没有操作系统、代码必须尽量小。

---

## 本章回响

本章真正在做的事情，是建立一个选择框架：**不同的传输场景，选择不同的工具**。scp 是日常最简单的选择，适合单文件、临时传输。rsync 是项目级同步的标准，增量特性在文件多的时候优势巨大。sftp 提供交互式浏览，适合你不确定远程有什么的场景。tftp 看起来最简陋，但在 U-Boot 引导阶段，它是唯一能用的通道。

还记得开头那个问题吗——为什么嵌入式开发不能只用 scp，为什么 U-Boot 阶段非得用 tftp？答案现在应该清楚了：scp 依赖 SSH，而 SSH 依赖操作系统。在 U-Boot 引导阶段，操作系统还没加载，SSH 跑不起来。tftp 之所以简陋，恰恰是因为简陋才能塞进 bootloader 几十 KB 的代码空间里——用 UDP，没有加密，没有认证，只保留"从 A 拿文件到 B"的最小功能。它不是设计上的缺陷，而是约束下的最优解。

下一章我们会把视角从"两台机器之间"拉到"谁能连谁"——防火墙。当你搭好了 SSH、配好了 tftp，却发现开发板连不上主机，问题很可能出在防火墙规则上。下一章我们用 `ufw` 把这个最后的障碍扫清。

---

[← 上一章](ch23-ssh.md)
[下一章 →](ch25-firewall.md)
