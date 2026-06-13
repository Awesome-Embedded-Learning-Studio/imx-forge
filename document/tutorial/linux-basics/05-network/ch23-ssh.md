# 第 23 章  SSH 远程连接

> **Part 5 · 网络与远程**

---

## 引子

你的开发板在桌子上，没有显示器，没有键盘，只有一根网线。

你怎么操作它？答案是 SSH——Secure Shell。
一条命令，终端就变成了开发板的终端，像坐在板子面前一样。

但第一次连的时候，终端问你要不要信任一个你从来没见过的密钥指纹。
这是什么意思？点了 Yes 会不会把板子搞崩？

理解 SSH 的信任模型——密钥对、指纹验证、免密登录——
不仅是为了安全，更是为了理解 Linux 网络通信的基本范式。

---

## 背景与动机

在 SSH 出现之前，远程登录的标准工具是 **telnet**。
telnet 的问题不是功能不够——而是它在网上**明文传输**一切：
你的用户名、你的密码、你敲的每一条命令，全部裸奔。
任何人在网络中间截一刀，你的密码就没了。

SSH 在 1995 年由芬兰程序员 Tatu Ylönen 设计，目的就是解决 telnet 的安全问题。
SSH 对所有通信加密——密码、命令、文件传输，全部是密文。
截到了也看不懂。

在嵌入式开发中，SSH 是你和开发板之间的「脐带」：
开发板通常不接显示器（很多开发板甚至没有显示接口），
你通过网线连上去，用 SSH 操作它的命令行——
编译、调试、部署、查看日志，全在终端里完成。
板端通常运行一个轻量级的 SSH 服务器（`dropbear` 或 `openssh-server`），
等待你的连接。

---

## 概念层

### 密钥对：一把锁和一把钥匙

SSH 支持两种认证方式：**密码认证**和**密钥对认证**。
密钥对认证是更安全也更方便的方式——理解它的原理，是理解 SSH 信任模型的核心。

你可以把密钥对想象成一套**锁和钥匙**——
**公钥**（public key）是锁，你把它装到每一台你想登录的服务器上；
**私钥**（private key）是钥匙，只留在你自己的机器上，绝不给别人。

当你 SSH 到一台服务器时，服务器用你的公钥（锁）出一道题，
只有拿着正确私钥（钥匙）的人才能解出来。
解出来了，服务器就让你进去——不需要输密码。

但「锁和钥匙」这个比喻有一个关键的地方不够准确：
现实中的锁和钥匙是物理插入的——你把钥匙插进锁里转一下，锁就开了。
SSH 的认证过程不是这样的。
服务器不会要求你把私钥「发过来」验证——
它发一段随机数据（challenge），你用私钥在本地加密后发回去（response），
服务器用公钥解密验证。整个过程私钥从未离开你的机器。
这叫**挑战-响应**（challenge-response）协议，
它比「插钥匙」安全得多——因为钥匙永远不会经过网络。

### 指纹验证：第一次连接的信任问题

第一次 SSH 到一台新机器时，你会看到这样的提示：

```
The authenticity of host '192.168.1.50 (192.168.1.50)' can't be established.
ED25519 key fingerprint is SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdefg.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

这行信息是什么意思？

SSH 不知道 `192.168.1.50` 这台机器是不是你真正想连的那块开发板——
它可能是，也可能是网络中间有人伪装的（中间人攻击，Man-in-the-Middle）。
SSH 给你展示了这台机器的**密钥指纹**（fingerprint）——
相当于那台机器的「身份证号」。
你确认了，SSH 就把这个指纹记下来（存在 `~/.ssh/known_hosts` 里）。
以后再连，SSH 会核对指纹是否一致。如果某天指纹变了——
SSH 会大声警告你：这台机器可能被换掉了，或者有人在冒充它。

这种模型叫 **TOFU**（Trust On First Use，首次使用时信任）。
它不完美——第一次连接时你没法确认指纹是否正确——
但在实践中足够好用：你第一次连开发板的时候通常是插着网线坐在它旁边，
物理环境是安全的。

### SSH 配置文件：别每次都敲一长串

每次 `ssh user@192.168.1.50 -p 2222` 敲一长串太烦了。
`~/.ssh/config` 文件可以给每个主机起别名：

```
Host board
    HostName 192.168.1.50
    User root
    Port 2222
```

配好之后，`ssh board` 就行了。

### SSH 隧道：端口转发

SSH 除了远程登录，还能做**端口转发**（Port Forwarding）——
把一个本地端口通过 SSH 隧道映射到远程机器的某个端口上。

最常见的场景：开发板上跑了一个 Web 服务（端口 80），
但你在 Ubuntu 上无法直接访问（可能因为防火墙或网络隔离）。
你可以通过 SSH 把本地 8080 端口转发到开发板的 80 端口：

```bash
$ ssh -L 8080:localhost:80 root@192.168.1.50
```

这条命令建立了一条 SSH 隧道。
之后你在 Ubuntu 上访问 `http://localhost:8080`，
请求会通过 SSH 加密隧道到达开发板的 80 端口。
对你来说，就像开发板的 Web 服务跑在本地一样。

---

## 实践层

### 4.1  第一次 SSH 连接

确保目标机器（开发板或服务器）已经启动了 SSH 服务。
如果是 Ubuntu 虚拟机，需要先装 SSH 服务器：

```bash
# 在目标机器上安装并启动 SSH 服务
$ sudo apt install openssh-server
$ sudo systemctl start ssh
$ sudo systemctl enable ssh
# 预期输出（enable）
Synchronizing state of ssh.service with SysV service script with /lib/systemd/systemd-sysv-install.
Executing: /lib/systemd/systemd-sysv-install enable ssh.
```

嵌入式开发板通常已经预装了 `dropbear`（轻量级 SSH 服务器）或 `openssh-server`，不需要你手动装。

从你的 Ubuntu 连过去：

```bash
$ ssh root@192.168.1.50
# 预期输出（第一次连接）
The authenticity of host '192.168.1.50 (192.168.1.50)' can't be established.
ED25519 key fingerprint is SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdefg.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
# 输入 yes 后
Warning: Permanently added '192.168.1.50' (ED25519) to the list of known hosts.
root@192.168.1.50's password:
# 输入密码后（不会显示任何字符，这是正常的）
# 预期输出
Last login: Thu Jun 11 12:00:00 2026
root@imx-board:~#
```

连上了。你现在终端里敲的每一条命令都在开发板上执行。

> ⚠️ 密码输入时屏幕上不会显示任何字符——没有星号，没有圆点，什么都没有。这不是卡了，是 SSH 的安全设计：防止旁观者通过字符数量猜测密码长度。大胆地敲完回车就行。

退出来：

```bash
$ exit
# 预期输出
logout
Connection to 192.168.1.50 closed.
```

如果指纹变了——比如你重装了开发板系统——SSH 会报错拒绝连接：

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
```

这不一定代表被攻击了——更常见的原因是目标机器重装了系统，密钥变了。
确认安全后，删掉 `~/.ssh/known_hosts` 里对应的那一行，重新连接即可：

```bash
$ ssh-keygen -R 192.168.1.50
# 预期输出
# Host 192.168.1.50 found: line 3
~/.ssh/known_hosts updated.
Original contents retained as ~/.ssh/known_hosts.old
```

### 4.2  配置免密登录：密钥对认证

每次连都要输密码太麻烦了。密钥对认证可以让你直接登录，不用输密码。

**第一步：生成密钥对**

```bash
$ ssh-keygen -t ed25519 -C "dev-board-key"
# 预期输出
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/你的用户名/.ssh/id_ed25519):
# 直接回车，使用默认路径
Enter passphrase (empty for no passphrase):
# 可以设一个密码保护私钥，也可以直接回车留空
Enter same passphrase again:
Your identification has been saved in ~/.ssh/id_ed25519
Your public key has been saved in ~/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdefg dev-board-key
```

`-t ed25519` 指定使用 Ed25519 算法。
Ed25519 是目前推荐的密钥类型——比 RSA 更短、更快、更安全。
如果你看到别的教程用 `-t rsa -b 4096`，那是一种更旧但仍然安全的方案，
但 Ed25519 是更好的选择。

`-C` 后面的注释只是帮你识别这把钥匙的用途，不影响功能。

生成了一对文件：
- `~/.ssh/id_ed25519` — 私钥（**绝对不能泄露**）
- `~/.ssh/id_ed25519.pub` — 公钥（可以随便分发）

> ⚠️ **私钥泄露等于密码泄露。** 不要把私钥传到网上、发到聊天工具、或者复制到不安全的地方。`~/.ssh/` 目录的权限应该是 `700`，私钥文件的权限应该是 `600`。`ssh-keygen` 会自动帮你设好这些权限——但如果你手动复制过文件，权限可能会变，需要手动修复：`chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519`。

**第二步：把公钥部署到目标机器**

```bash
$ ssh-copy-id root@192.168.1.50
# 预期输出
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "~/.ssh/id_ed25519.pub"
root@192.168.1.50's password:
# 输入目标机器的密码

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'root@192.168.1.50'"
and check to make sure that only the key(s) you wanted were added.
```

`ssh-copy-id` 做的事情很简单：
把你的公钥追加到目标机器的 `~/.ssh/authorized_keys` 文件里。
如果你没有 `ssh-copy-id`（某些嵌入式环境），手动复制也行：

```bash
$ cat ~/.ssh/id_ed25519.pub | ssh root@192.168.1.50 \
    "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

**第三步：验证免密登录**

```bash
$ ssh root@192.168.1.50
# 预期输出——直接进入，不需要输密码
Last login: Thu Jun 11 12:00:00 2026
root@imx-board:~#
```

回到了那个「锁和钥匙」的比喻——
你刚才做的事情是：造了一把钥匙（私钥），打了一把锁（公钥），
把锁装到了开发板上（`authorized_keys`）。
现在只有拿着这把钥匙的人能开这把锁。
而且你不需要把钥匙交给任何人——
开发板用公钥出题，你用私钥在本地解题，钥匙从未离开你的机器。

### 4.3  配置 SSH 别名

`ssh root@192.168.1.50` 敲多了也烦。给开发板起个名字：

```bash
$ vim ~/.ssh/config
```

写入以下内容：

```
Host board
    HostName 192.168.1.50
    User root
    IdentityFile ~/.ssh/id_ed25519
```

保存后直接：

```bash
$ ssh board
# 预期输出——自动用 root@192.168.1.50 和指定密钥连接
Last login: Thu Jun 11 12:00:00 2026
root@imx-board:~#
```

如果有多个设备，多写几段就行：

```
Host board
    HostName 192.168.1.50
    User root

Host server
    HostName 10.0.0.100
    User admin
    Port 2222

Host vm
    HostName 192.168.1.200
    User charlie
```

### 4.4  SSH 隧道：本地端口转发

开发板上跑了一个 Web 服务（端口 80），但你无法直接从 Ubuntu 访问（比如开发板在内网）。
SSH 隧道可以把本地端口「接」到远程端口上：

```bash
$ ssh -L 8080:localhost:80 root@192.168.1.50
# 这条命令会保持 SSH 连接
# 在另一个终端里测试
$ curl http://localhost:8080
# 预期输出：开发板上 Web 服务的响应内容
```

`-L` 参数的格式是 `本地端口:目标地址:目标端口`。
`localhost:80` 里的 `localhost` 是相对于远程机器（开发板）而言的——
意思是「从开发板的角度看 localhost 的 80 端口」。

这条命令会保持 SSH 会话——你需要开着这个终端。
如果想后台运行，加 `-f -N`：

```bash
$ ssh -f -N -L 8080:localhost:80 root@192.168.1.50
# 没有输出，直接回到命令行。隧道在后台运行。
```

`-f` 让 SSH 在后台运行，`-N` 表示不执行远程命令（只做端口转发）。

关闭隧道：

```bash
# 找到隧道进程
$ ps aux | grep "ssh -f -N"
# 预期输出
user       12345  ... ssh -f -N -L 8080:localhost:80 root@192.168.1.50

# 杀掉它
$ kill 12345
```

---

## 练习题

SSH 的日常用法到这里应该够用了。下面几道题帮你把理解从「会用」推到「知道为什么」。
第二题是实操题，第三题如果你做出来了，说明你对 SSH 隧道有了真正的理解。

**练习 23.1** ⭐（理解）

SSH 第一次连接时显示的 `SHA256:AbCdEf...` 是什么？
如果有一天你再次连接同一个 IP，SSH 报 `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`，可能的原因有哪些？

> **提示**：回顾 TOFU 模型和 `~/.ssh/known_hosts` 的作用。

**练习 23.2** ⭐⭐（应用）

请完成以下操作：
1. 在你的 Ubuntu 上生成一个 Ed25519 密钥对
2. 将公钥部署到一台远程机器（虚拟机或开发板）
3. 配置 `~/.ssh/config`，使你可以用 `ssh mydev` 直接免密登录

写出你执行的每一步命令。

> **提示**：按 4.2 和 4.3 的步骤走，注意文件权限。

**练习 23.3** ⭐⭐⭐（思考）

你在公司网络里，有一台远程服务器 `server.example.com`（可以 SSH 访问），
那台服务器内网里有一台数据库机器 `db.internal`，端口 3306，
但你无法从你的机器直接访问 `db.internal`。
请说明如何用 SSH 隧道让你在本地通过 `localhost:3306` 访问到 `db.internal:3306`。

> **提示**：`-L` 参数中 `目标地址` 不一定是 `localhost`——它可以是远程服务器能访问到的任何地址。想一想 `-L 3306:db.internal:3306 server.example.com` 的含义。

---

## 本章回响

这一章的核心认知是：SSH 的安全不是来自「加密」一个属性，而是来自一整套**信任模型**的配合。
密钥对认证让你不需要在网上传输密码，
指纹验证让你能在第一时间发现伪装者，
`known_hosts` 是你亲手建立的「信任名单」。

还记得开头那个问题吗——第一次连接时终端问你「要不要信任这个密钥指纹」？
现在你应该能回答了：那是 SSH 在让你确认这台机器的身份。
你点了 yes，SSH 就记住了它的「身份证号」。
以后如果有人冒充这台机器——指纹对不上——SSH 会拒绝连接并大声警告。
这不是在吓唬你，这是 SSH 在保护你。
它比你随手输入密码然后祈祷没人截获要安全得多。

回到那把「锁和钥匙」——
你把锁（公钥）装到了开发板上，钥匙（私钥）留在了自己手里。
开发板用锁出题，你用钥匙解题，钥匙从未离开你的机器。
这就是为什么密钥对认证比密码认证更安全：
密码需要你每次在网上发送，而私钥永远只在本地。

但 SSH 解决的是「远程操作」的问题——你能在开发板上敲命令了。
文件怎么传？编译好的固件怎么推到板子上？日志文件怎么拉回来分析？
下一章我们讲文件传输——scp、rsync、sftp，
它们让文件在你的 Ubuntu 和开发板之间流动起来。

---

[← 上一章](ch22-netdiag.md)
[下一章 →](ch24-transfer.md)
