# 第 15 章  用户与组管理

> **Part 4 · 系统管理**

---

## 引子

你敲了一条命令，终端回你：

```
Operation not permitted
```

你明明是这台电脑的主人——是你装的系统，是你买的硬盘，是你付的电费。凭什么「不允许」？

这个问题的答案藏在 Linux 最底层的设计决策里：**Linux 从来不是为一个人设计的**。从 Unix 诞生那天起，它就是多用户系统——一台机器上同时坐着十个人，每个人有自己的文件、自己的配置、自己的桌面，彼此之间互不干扰。

你刚才碰到的那个「Operation not permitted」，本质上是系统在说：**我不认识你这个人**。或者更准确地说——我认识你，但你现在的身份不够格。

那 Linux 到底怎么「认识」你？怎么判断你够不够格？以及最关键的——怎么让你临时变成那个无所不能的超级管理员？

这就是这一章要拆解的东西。

---

## 背景与动机

如果你只用过 Windows 单机，用户管理这件事可能从来没进入过你的雷达。Windows 的「管理员」权限几乎是默认给所有人的——装软件、改注册表、删系统文件，双击就能干。

但 Linux 不一样。哪怕你是唯一使用这台机器的人，系统也会逼你以「普通用户」身份登录，只在需要的时候通过 `sudo` 临时借用管理员权限。这种设计一开始会让人觉得多此一举，但等你真正上了嵌入式开发板、连上公司的构建服务器，就会发现它是在保护你——防止一个手滑把整棵文件树连根拔起。

在嵌入式开发场景里，用户管理几乎不可避免：搭建交叉编译服务器时你需要创建专门的构建账户；多人共用一块开发板时你需要隔离彼此的环境；配置 NFS 共享目录时你需要对齐用户组——所有这些操作都绕不开 `useradd`、`groupadd`、`/etc/sudoers` 这些概念。

---

## 概念层

### UID 和 GID——系统眼里的你，就是一个数字

Linux 内核不关心你的用户名是 `charlie` 还是 `zhangsan`。在内核的数据结构里，每个进程都挂着一个数字：**UID（User ID）**。权限检查的全部逻辑，就是拿这个 UID 去和文件的属主 UID 比对——匹配就有权限，不匹配就没有。用户名只是给人看的标签，真正起作用的是 UID。

每个用户还属于一个**主组（Primary Group）**，对应一个 **GID（Group ID）**。组的存在是为了解决「一批人对同一批文件有相同权限」这个需求——你不需要给张三、李四、王五分别授权，把他们拉进同一个组，然后给这个组赋权就行了。

你可以把这套机制理解为一栋**写字楼**——每个用户是一个租户，UID 是门禁卡上的编号，GID 是你所属的公司编号。门禁系统不看你叫什么名字，只看你卡上的编号属于哪个楼层、哪个公司。

但「写字楼」这个比喻有一个地方是错的：真正的写字楼有物业管理员，而 Linux 里的 root 用户不是管理员——它是**这栋楼本身**。root 的 UID 是 0，内核在权限检查时看到 UID 为 0 就直接放行，跳过所有规则。这不是「最高权限」，这是「没有权限检查」。

现在来看系统到底把你的身份信息存在哪里。所有的用户账户信息都记录在 `/etc/passwd` 文件里：

```bash
$ cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
...
charlie:x:1000:1000:Charlie Chen,,,:/home/charlie:/bin/bash
```

每一行代表一个用户，字段之间用冒号 `:` 分隔。以最后一行为例，从左到右依次是：

| 字段 | 值 | 含义 |
|------|------|------|
| 用户名 | `charlie` | 登录名 |
| 密码占位 | `x` | 密码已移至 `/etc/shadow` |
| UID | `1000` | 用户 ID |
| GID | `1000` | 主组 ID |
| GECOS | `Charlie Chen,,,` | 描述信息（全名、电话等） |
| 家目录 | `/home/charlie` | 登录后的起始目录 |
| Shell | `/bin/bash` | 登录后使用的 Shell |

那个 `x` 不是密码本身。密码的密文存在 `/etc/shadow` 里，只有 root 能读——这是安全设计，防止普通用户通过 `/etc/passwd` 的可读权限来暴力破解密码。

密码信息在 `/etc/shadow` 中的格式类似这样：

```bash
$ sudo cat /etc/shadow | grep charlie
charlie:$6$xyz...:19800:0:99999:7:::
```

`$6$` 表示使用 SHA-512 加密。后面那一串是密文，不是明文密码。

回到那个「写字楼」的类比：你现在应该能看出来，`/etc/passwd` 就是这栋楼的租户登记表——UID 是门禁卡编号，GID 是公司编号，家目录是你的办公室位置，Shell 是你办公室的门是否开着（`/bin/bash` 是开着，`/usr/sbin/nologin` 是焊死了）。

而 `/etc/shadow` 是锁在物业保险柜里的密码本。如果 `/etc/shadow` 的权限被改错了（比如变成了所有人可读），这栋楼的门禁形同虚设——这就是为什么你绝对不应该手动修改这个文件的权限。

---

### 用户组——权限的批量分发机制

组信息存储在 `/etc/group` 中：

```bash
$ cat /etc/group
root:x:0:
sudo:x:27:charlie
charlie:x:1000:
dialout:x:20:charlie
```

每行的格式是 `组名:密码占位:GID:组成员列表`。注意 `sudo` 那一行——`charlie` 出现在了这里，意味着 `charlie` 属于 `sudo` 组，可以使用 `sudo` 命令。`dialout` 组则控制着串口设备的访问权限——做嵌入式开发的人必须属于这个组，否则无法用 `minicom` 连开发板。

一个用户可以属于多个组。除了 `/etc/passwd` 中指定的主组之外，通过 `/etc/group` 的成员列表附加的组叫**附加组（supplementary group）**。当内核做权限检查时，不仅检查你的主组 GID，还会检查你所有的附加组——只要有一个匹配文件的属组 GID，你就拥有该组的权限。

---

### sudo——临时借用 root 的力量

`sudo` 的字面意思是 "superuser do"。它的本质是：**以另一个用户（默认是 root）的身份执行一条命令**。

它不是切换用户，不是永久提升权限。它只借一次——执行完这条命令，你还是你自己。

`sudo` 的权限配置存储在 `/etc/sudoers` 文件中。这个文件决定了谁可以用 `sudo`、用 `sudo` 时是否需要输入密码、能执行哪些命令。Ubuntu 默认的配置是：属于 `sudo` 组的用户可以执行任意命令，但需要输入**自己的密码**（不是 root 密码）。

```bash
$ cat /etc/sudoers | grep -v "^#" | grep -v "^$"
Defaults	env_reset
Defaults	mail_badpass
%sudo	ALL=(ALL:ALL) ALL
```

`%sudo` 表示 `sudo` 组的所有成员，`ALL=(ALL:ALL) ALL` 意味着：在任何主机上、以任何用户身份、以任何组身份、执行任何命令。

---

## 实践层

### 4.1  查看和创建用户

#### 查看当前用户信息

```bash
$ whoami
charlie

$ id
uid=1000(charlie) gid=1000(charlie) groups=1000(charlie),27(sudo),20(dialout)
```

`whoami` 只告诉你当前的用户名。`id` 则把完整的身份信息全部摊开——UID、GID、所有附加组。在做权限排错时，`id` 是你的第一诊断工具。

#### 创建新用户——useradd

```bash
$ sudo useradd -m -s /bin/bash -G sudo,dialout devuser
```

这条命令做了一连串的事情：

- `-m`：在 `/home/devuser` 创建家目录
- `-s /bin/bash`：指定登录 Shell 为 bash
- `-G sudo,dialout`：把用户加入 `sudo` 和 `dialout` 附加组
- `devuser`：新用户名

新用户创建后还没有密码，需要单独设置：

```bash
$ sudo passwd devuser
New password:
Retype new password:
passwd: password updated successfully
```

验证一下创建结果：

```bash
$ id devuser
uid=1001(devuser) gid=1001(devuser) groups=1001(devuser),27(sudo),20(dialout)

$ ls -la /home/devuser/
total 20
drwxr-x--- 2 devuser devuser 4096 Jan 10 10:00 .
drwxr-xr-x 6 root   root   4096 Jan  9 09:00 ..
-rw-r--r-- 1 devuser devuser  220 Jan 10 10:00 .bash_logout
-rw-r--r-- 1 devuser devuser 3771 Jan 10 10:00 .bashrc
-rw-r--r-- 1 devuser devuser  807 Jan 10 10:00 .profile
```

家目录已就位，Shell 配置文件已自动从 `/etc/skel` 模板复制过来。

> **关于 `useradd` 和 `adduser` 的区别**
>
> Ubuntu 上有两个创建用户的命令：`useradd` 和 `adduser`。
>
> `useradd` 是底层命令——它只做你明确告诉它的事，不创建家目录、不设置密码、不复制配置模板，除非你加对应的选项。`adduser` 是一个 Perl 脚本封装，它会交互式地引导你完成用户创建的全过程：自动建家目录、自动复制 `/etc/skel`、提示你设置密码、询问全名等信息。
>
> 对于新手，`adduser` 更友好。但在自动化脚本和嵌入式构建流程中，`useradd` 更可控，因为你清楚地知道每一步在做什么。两种方式创建出来的用户没有本质区别。

#### 切换用户——su 和 sudo -i

```bash
# 切换到 devuser（需要输入 devuser 的密码）
$ su - devuser
Password:

# 以 root 身份打开一个交互式 Shell（需要输入自己的密码）
$ sudo -i
[sudo] password for charlie:
#

# 以 root 身份执行单条命令
$ sudo whoami
root
```

`su -` 和 `sudo -i` 的区别在于：`su -` 需要目标用户的密码，而 `sudo -i` 需要你自己的密码（前提是你有 sudo 权限）。在 Ubuntu 中，root 账户默认是锁定的，没有密码，所以你无法直接 `su - root`——只能用 `sudo -i`。

---

### 4.2  修改和删除用户

#### 修改用户属性——usermod

```bash
# 把 devuser 加入 plugdev 组（用于访问可拔插设备）
$ sudo usermod -aG plugdev devuser

# 修改 devuser 的登录 Shell 为 zsh
$ sudo usermod -s /usr/bin/zsh devuser

# 修改 devuser 的用户名为 builder
$ sudo usermod -l builder devuser

# 修改 devuser 的家目录位置（-m 表示移动旧家目录的内容）
$ sudo usermod -d /home/builder -m builder
```

这里有坑。`-aG` 是「追加附加组」的意思，`-G` 不带 `a` 则是「替换附加组」——如果你写成了 `sudo usermod -G plugdev devuser`，devuser 会从 `sudo` 和 `dialout` 组中被移除，只剩 `plugdev`。这个坑让我血压拉满过一次。

⚠️ **注意**
`usermod -G` 会替换附加组列表，不是追加！追加请用 `-aG`（a = append）。

#### 删除用户——userdel

```bash
# 删除用户，但保留家目录
$ sudo userdel devuser

# 删除用户，连同家目录一起删
$ sudo userdel -r devuser
```

⚠️ **注意**
`userdel -r` 会递归删除用户的家目录和邮件目录，**不可恢复**。执行前务必确认该用户的文件已经备份，或者你确实不再需要它们。

---

### 4.3  用户组管理

```bash
# 创建新组
$ sudo groupadd embedded

# 把 charlie 和 devuser 加入 embedded 组
$ sudo usermod -aG embedded charlie
$ sudo usermod -aG embedded devuser

# 验证
$ getent group embedded
embedded:x:1002:charlie,devuser

# 删除组
$ sudo groupdel embedded
```

`getent group` 比 `cat /etc/group` 更好——它不仅查本地文件，还会查 LDAP 等网络目录服务，是更通用的查询方式。

---

### 4.4  sudo 配置——从入门到 visudo

#### 为什么需要 visudo

`/etc/sudoers` 的语法非常严格——多一个空格、少一个冒号，都可能导致整个 `sudo` 功能瘫痪。如果你直接用 `vim` 打开改，改错了保存退出，下一次 `sudo` 就会报语法错误，然后你连修复它的权限都没有——因为修复它也需要 `sudo`。

`visudo` 就是为此而生的。它做两件事：第一，用系统默认编辑器打开 `/etc/sudoers`；第二，**在你保存退出之前，自动做语法检查**。如果语法有错，它会拒绝保存并提示你修正。

```bash
$ sudo visudo
```

打开后你会看到类似这样的内容：

```
# User privilege specification
root    ALL=(ALL:ALL) ALL

# Members of the admin group may gain root privileges
%admin  ALL=(ALL:ALL) ALL

# Allow members of group sudo to execute any command
%sudo   ALL=(ALL:ALL) ALL
```

#### 实战：给特定用户限制 sudo 权限

假设你想让 `devuser` 只能使用 `sudo` 执行 `systemctl restart nginx`，而不能做其他任何事：

```bash
$ sudo visudo
```

在文件末尾添加：

```
devuser ALL=(ALL) /usr/bin/systemctl restart nginx
```

保存退出。`visudo` 会自动检查语法。如果没问题，它会静默退出；如果有问题，你会看到：

```
>>> /etc/sudoers: syntax error near line 30 <<<
What now?
```

此时可以选择 `e` 重新编辑，`x` 退出不保存，`Q` 强制保存（**千万别选 Q**）。

验证配置是否生效：

```bash
$ sudo -l -U devuser
User devuser may run the following commands on ubuntu:
    (ALL) /usr/bin/systemctl restart nginx
```

---

## 练习题

走到这里，用户管理的核心机制应该清楚了——或者你以为清楚了。下面几道题难度递进，建议先不看提示独立想，卡住了再翻。

**练习 15.1** ⭐（理解）

用户 `charlie` 的 UID 是 1000，GID 是 1000。请解释 `/etc/passwd` 中以下每一项的含义：

```
charlie:x:1000:1000:Charlie Chen,,,:/home/charlie:/bin/bash
```

如果将最后一项 `/bin/bash` 改为 `/usr/sbin/nologin`，会发生什么？

**练习 15.2** ⭐⭐（应用）

你需要在服务器上创建一个名为 `builder` 的用户，要求：
1. 家目录位于 `/home/builder`
2. 登录 Shell 为 `/bin/bash`
3. 属于 `sudo` 组
4. 密码设置为 `build2024`

请写出完整的命令序列。然后验证：如果 `builder` 执行 `sudo whoami`，预期输出是什么？

> **提示**：注意 `useradd` 的选项顺序，以及 `passwd` 命令的使用方式。

**练习 15.3** ⭐⭐⭐（思考）

你意外执行了 `sudo usermod -G dialout charlie`（没有 `-a`），把 `charlie` 从 `sudo` 组中移除了。此时你还能用 `sudo` 修复这个问题吗？如果能，怎么修？如果不能，还有什么办法？

> **提示**：想一想 `sudo` 的权限来源是 `/etc/sudoers` 中的 `%sudo` 行。如果你已经不属于 `sudo` 组了……

---

## 本章回响

本章真正在做的事情，是建立 Linux 用户身份体系的底层认知。表面上我们在学习 `useradd`、`usermod`、`visudo` 这些命令，实际上我们在理解一个核心问题：**Linux 怎么把一个活生生的人映射成一串数字，然后用这串数字来决定你能干什么。**

UID 是身份，GID 是归属，`/etc/passwd` 是身份证，`/etc/shadow` 是保险柜，`/etc/group` 是花名册——这四份文件构成了 Linux 用户管理的全部基础设施。你不需要记住每一个字段，但你需要知道信息在哪里、格式是什么样的，因为出了问题你总要回来查。

还记得开头那个 `Operation not permitted` 吗？现在你应该能回答了：系统拒绝你不是因为你在用它，而是因为你执行那条命令时用的身份——你的 UID——在那个文件的权限表里没有对应的通行证。解决方式不是换一台电脑，而是换一个身份，或者修改那份权限表。

而「修改权限表」这件事，就是我们下一章要拆解的内容。rwx 九个字符、chmod 八进制、umask 默认值——这些你每天都会遇到的东西，背后是一套简洁到极致、也精确到极致的权限模型。

---

[← 上一章](../03-text/ch14-redirect.md)
[下一章 →](ch16-permission.md)
