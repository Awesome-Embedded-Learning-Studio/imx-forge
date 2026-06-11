# 第 20 章  服务管理：systemd

> **Part 4 · 系统管理**

---

## 引子

你写了一个网络服务程序，希望它开机就跑、挂了自动重启、日志统一管理。

以前你得自己写启动脚本，放在 init.d 下面，祈祷它能正常工作。现在 systemd 把这些全接管了——一个 unit 文件定义服务行为，`systemctl` 管生命周期，`journalctl` 管日志查看。

systemd 的争议很大，但它赢了。Ubuntu 用它，绝大多数 Linux 发行版都用它。

这里有一个容易被忽略的问题：`systemctl enable` 和 `systemctl start`，看起来都是在「启动服务」，但它们做的事情完全不同。搞混这两个，你的服务要么开机不启动，要么改了配置不生效。本章我们会把这个区别讲清楚。

理解 systemd 的基本操作，是管理任何 Linux 服务的起点。

---

## 背景与动机

在 systemd 出现之前，Linux 用的是 SysV init——一套来自 Unix System V 时代的设计。它的核心是一个叫 `/etc/init.d/` 的目录，里面放着一堆 Shell 脚本，每个脚本负责启动或停止一个服务。

这套机制最大的问题是：**所有服务按编号顺序启动，没有依赖管理。**

假设服务 B 依赖服务 A（比如 Web 服务器依赖网络）。SysV init 的做法是给 A 编一个更小的编号，祈祷 A 比 B 先启动完。"祈祷"这个字我没有在开玩笑——它真的就是在祈祷，因为 A 启动慢了，B 照样会在 A 没准备好的时候跑起来，然后莫名其妙地失败。

到了 2010 年代，这套机制越来越扛不住：启动慢、没有进程监控（服务挂了没人管）、日志散落在 `/var/log/` 的各种文件里、没有统一的查询工具。

systemd 在 2010 年由 Lennart Poettering 发布，接管了 init 的位置。它引入了声明式的 unit 文件来定义服务，内置依赖管理实现并行启动，自带进程监控和自动重启，还通过 journald 统一收集日志。

社区对 systemd 的争议一直没停——批评者说它违背了 Unix「做一件事并做好」的哲学，把太多功能塞进了 PID 1。但争论归争论，事实是：Ubuntu 从 15.04 开始用 systemd，Debian、Fedora、Arch 也全都切换了。它已经是 Linux 世界的标准 init 系统。

对于我们做嵌入式开发的人来说，systemd 的意义更直接：你迟早要写一个自定义服务（比如开发板上的守护进程），写 unit 文件比写 Shell 启动脚本靠谱得多。而且 systemd 提供的日志和状态查询，在调试板子的时候能省很多事。

---

## 概念层

### systemd 是什么

systemd 是 Linux 系统的 init 系统——内核启动后运行的第一个用户态进程，PID 永远是 1。

你可以把 systemd 想象成一个**工厂的车间主任**。整个 Linux 系统是一个工厂，每个服务是一个工位。车间主任手里有一份工位清单（unit 文件），上面写着每个工位什么时候开、需要哪些前置条件、出了问题怎么处理。主任按清单把所有工位安排好，然后盯着它们运行——哪个工位停了，主任会按预设的规则决定是重启还是报警。

但这个类比有一个地方是错的。真正的车间主任只能看到工位的最终产出，看不到工位内部在干什么。systemd 不一样——它通过 Linux 内核的 cgroup 机制追踪每个服务的所有进程，精确知道哪个进程在跑、占用了多少资源、输出了什么日志。它比任何车间主任都更「全知」。

PID 1 这个位置意味着什么？意味着 systemd 是所有用户态进程的最终祖先。不管你的服务是怎么启动的——是 systemd 直接拉起来的，还是某个子进程 fork 出来的——systemd 都能追踪到它。这也是为什么它有能力在服务崩溃时自动重启。

### Unit 文件：声明式的服务定义

systemd 用 unit 文件来定义和管理各种资源。最常见的是 service 类型的 unit（服务），但还有 target（目标组）、timer（定时器）、socket（套接字）等类型。

一个 service unit 文件长这样：

```ini
[Unit]
Description=My Custom Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/my-service
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

三个段落，各有分工：

**`[Unit]`** —— 描述和依赖关系。`Description` 是给人看的说明。`After` 表示「在什么之后启动」——这里写 `network.target`，意思是等网络就绪后再启动。注意 `After` 只是顺序约束，不是依赖声明；真正的依赖用 `Wants` 或 `Requires`。

**`[Service]`** —— 服务运行的具体配置。`Type=simple` 是最常见的类型，表示 `ExecStart` 指定的进程就是服务的主进程。`Restart=on-failure` 表示非正常退出时自动重启。`RestartSec=5` 表示重启前等 5 秒，防止连续崩溃时疯狂重启。

**`[Install]`** —— 安装信息，定义 `enable` 时服务会被挂到哪个 target 下面。`WantedBy=multi-user.target` 是最常见的选择，表示在多用户模式下启动。

Unit 文件存在三个位置，优先级从高到低：

| 路径 | 说明 |
|---|---|
| `/etc/systemd/system/` | 管理员自定义，优先级最高 |
| `/run/systemd/system/` | 运行时动态生成 |
| `/lib/systemd/system/` | 软件包安装的，不要直接改 |

自定义的 unit 文件放在 `/etc/systemd/system/`。为什么不放 `/lib/systemd/system/`？因为软件包升级会覆盖 `/lib/` 下的文件，你改的东西就丢了。

### systemctl 的核心操作

`systemctl` 是和 systemd 交互的主命令。日常用的就这么几个：

```bash
# 查看服务状态
$ systemctl status ssh

# 启动 / 停止 / 重启
$ sudo systemctl start ssh
$ sudo systemctl stop ssh
$ sudo systemctl restart ssh

# 开机自启：启用 / 禁用
$ sudo systemctl enable ssh
$ sudo systemctl disable ssh

# 查看所有正在运行的服务
$ systemctl list-units --type=service --state=running
```

这里有一个极其常见的混淆点，值得单独拎出来说。

**`enable` ≠ `start`。**

`enable` 做的事情是：在 `/etc/systemd/system/` 对应的 target 目录下创建一个指向 unit 文件的符号链接。这条链接告诉 systemd：下次开机的时候，把这个服务拉起来。但它不会影响当前运行状态。

`start` 做的事情是：立刻执行 unit 文件里 `ExecStart` 指定的命令，把服务跑起来。但它不影响开机自启设置。

所以这四种组合都是合法的：

| 命令 | 当前状态 | 开机行为 |
|---|---|---|
| `enable --now` | 立刻启动 | 开机自启 |
| `enable` | 不启动 | 开机自启 |
| `start` | 立刻启动 | 开机不自启 |
| 什么都不做 | 不启动 | 开机不自启 |

`enable --now` 是同时执行 enable 和 start 的简写，日常用起来很方便。

修改了 unit 文件之后，必须执行一条命令让 systemd 重新加载配置：

```bash
$ sudo systemctl daemon-reload
```

这条命令不重启服务，只是让 systemd 重新读取磁盘上的 unit 文件。**忘记执行这条命令是最常见的「我改了配置但不生效」的原因。**

### journalctl：集中式日志

systemd 自带 journald 日志守护进程，所有服务的输出（stdout、stderr）都会被 journald 收集。查询日志的命令是 `journalctl`。

```bash
# 查看某个服务的日志
$ journalctl -u ssh

# 实时跟踪日志（类似 tail -f）
$ journalctl -u ssh -f

# 只看今天的日志
$ journalctl -u ssh --since today

# 查看最近一次启动的所有日志
$ journalctl -b
```

`-u` 是 `--unit` 的缩写，后面跟服务名。`-b` 是 `--boot` 的缩写，显示当前启动会话的日志。`-f` 是 `--follow`，实时跟踪新日志。

回到那个车间主任的类比。`systemctl status` 是去车间看一眼某个工位还在不在运行，`journalctl` 是调出那个工位的工作日志。`enable` 是在排班表上加一条——下次开班（开机）时这个工位要开工。`start` 是现在就派人去开机器。

如果你只 enable 了没 start，就像只在排班表上写了名字但今天没派人去——明天会开工，但今天工位是空的。反过来，只 start 没 enable，今天在跑，但明天重启就没了。`systemctl status` 的输出里 `enabled` 或 `disabled` 字段会告诉你排班表上有没有这个名字——和工位当前是不是在运行，是两码事。

---

## 实践层

### 4.1  认识系统里已有的服务

先看看你的系统里跑着哪些服务：

```bash
$ systemctl list-units --type=service --state=running
```

输出会是一张表，列出所有正在运行的服务：

```
UNIT                           LOAD   ACTIVE SUB     DESCRIPTION
accounts-daemon.service        loaded active running Accounts Service
cron.service                   loaded active running Regular background program
dbus.service                   loaded active running D-Bus System Message Bus
NetworkManager.service         loaded active running Network Manager
ssh.service                    loaded active running OpenBSD Secure Shell server
...
```

挑一个你认识的服务，看看它的状态：

```bash
$ systemctl status ssh
```

```
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/lib/systemd/system/ssh.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2025-06-11 10:00:00 CST; 2h 30min ago
   Main PID: 1234 (sshd)
      Tasks: 3 (limit: 4915)
     Memory: 4.2M
        CPU: 120ms
     CGroup: /system.slice/ssh.service
             └─1234 "sshd: /usr/sbin/sshd -D"
```

输出里的关键信息：
- **Loaded**：unit 文件的位置，以及是否 enabled
- **Active**：当前状态和运行时长
- **Main PID**：主进程的 PID
- **CGroup**：systemd 用 cgroup 追踪的进程树

这个服务的 unit 文件位于 `/lib/systemd/system/ssh.service`——这是软件包（`openssh-server`）安装时放进去的。可以用 `systemctl cat ssh` 查看完整内容。

### 4.2  写一个自己的服务

我们来创建一个简单的自定义服务：一个每 5 秒向文件写入时间戳的脚本，用来练习 systemd 的完整操作流程。

先创建服务脚本：

```bash
$ sudo tee /usr/local/bin/timestamp-service > /dev/null << 'EOF'
#!/bin/bash
# timestamp-service: 每 5 秒输出一条心跳日志
LOGFILE="/tmp/timestamp.log"

echo "[$(date)] 服务启动" >> "$LOGFILE"

while true; do
    echo "心跳 $(date)"
    echo "[$(date)] 心跳" >> "$LOGFILE"
    sleep 5
done
EOF
```

给它执行权限：

```bash
$ sudo chmod +x /usr/local/bin/timestamp-service
```

然后创建 unit 文件：

```bash
$ sudo tee /etc/systemd/system/timestamp.service > /dev/null << 'EOF'
[Unit]
Description=Timestamp Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/timestamp-service
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`Restart=on-failure` 搭配 `RestartSec=5`，保证服务非正常退出后等 5 秒再重启——防止连续崩溃时疯狂重启吃满 CPU。

### 4.3  启动、开机自启与日志查看

让 systemd 重新加载配置——这一步必须做，因为我们是新加的 unit 文件：

```bash
$ sudo systemctl daemon-reload
```

启动服务：

```bash
$ sudo systemctl start timestamp
```

检查状态：

```bash
$ systemctl status timestamp
```

```
● timestamp.service - Timestamp Service
     Loaded: loaded (/etc/systemd/system/timestamp.service; disabled; ...)
     Active: active (running) since Thu 2025-06-11 12:00:00 CST; 5s ago
   Main PID: 5678 (timestamp-service)
      Tasks: 2
     Memory: 1.0M
        CPU: 10ms
     CGroup: /system.slice/timestamp.service
             └─5678 /bin/bash /usr/local/bin/timestamp-service
```

注意 **disabled**——服务在运行（active），但没有开机自启（disabled）。这验证了前面说的：`start` 和 `enable` 是两件事。

看看日志文件有没有在写：

```bash
$ cat /tmp/timestamp.log
```

```
[Thu Jun 11 12:00:00 CST 2025] 服务启动
[Thu Jun 11 12:00:00 CST 2025] 心跳
[Thu Jun 11 12:00:05 CST 2025] 心跳
```

用 journalctl 看服务的 stdout 输出——我们的脚本在 `echo "心跳 $(date)"` 这行同时往 stdout 写了内容，所以 journald 会捕获到：

```bash
$ journalctl -u timestamp --since "5 minutes ago"
```

```
Jun 11 12:00:00 hostname timestamp-service[5678]: 心跳 Thu Jun 11 12:00:00 CST 2025
Jun 11 12:00:05 hostname timestamp-service[5678]: 心跳 Thu Jun 11 12:00:05 CST 2025
```

设置开机自启：

```bash
$ sudo systemctl enable timestamp
```

```
Created symlink /etc/systemd/system/multi-user.target.wants/timestamp.service → /etc/systemd/system/timestamp.service.
```

这条输出验证了我们前面说的机制：`enable` 在 `multi-user.target.wants/` 目录下创建了一个符号链接。

> ⚠️ **踩坑提醒**
> 修改 unit 文件后，一定要 `systemctl daemon-reload`。我见过太多人（包括我自己）改了 unit 文件直接 restart，然后纳闷为什么配置没生效——因为 systemd 还在用内存里缓存的旧配置。**daemon-reload → restart**，这个顺序记住就行。

验证一下自动重启能力——手动杀掉服务进程：

```bash
$ sudo systemctl kill timestamp --signal=SIGKILL
$ sleep 6
$ systemctl status timestamp
```

如果一切正常，状态仍然是 `active (running)`，但 Main PID 变了——systemd 检测到进程异常退出，等了 5 秒后自动把它拉起来了。

实验完了，清理一下：

```bash
$ sudo systemctl disable --now timestamp
$ sudo rm /etc/systemd/system/timestamp.service
$ sudo rm /usr/local/bin/timestamp-service
$ rm /tmp/timestamp.log
$ sudo systemctl daemon-reload
```

`disable --now` 是 `disable` + `stop` 的简写，一步到位。

---

## 练习题

走到这里，systemd 的基本操作应该清楚了。下面两道题帮你确认——第一道是理解题，第二道需要动手。

**练习 20.1** ⭐（理解）

`systemctl enable` 和 `systemctl start` 分别做了什么？如果你只执行了 `enable` 没执行 `start`，服务当前在运行吗？重启之后呢？

**练习 20.2** ⭐⭐（应用）

写一个 unit 文件，要求：
1. 服务脚本是一个 Bash 脚本，每 10 秒向 `/tmp/my-service.log` 写入当前时间
2. 服务在网络就绪后启动
3. 崩溃后自动重启，重启间隔 3 秒
4. 设置为开机自启

写出 unit 文件内容，并说明让服务生效需要执行哪些命令。

> **提示**：参考本章节的实践步骤，注意 `daemon-reload` 的时机。

---

## 本章回响

systemd 做的事情，本质上是在回答一个问题：怎么让一堆服务有序、可控、可观测地运行。

它用声明式的 unit 文件替代了过程式的 Shell 脚本，用依赖管理替代了编号排序，用 cgroup 追踪替代了盲目等待，用 journald 替代了散落各地的日志文件。这些设计并不是没有代价——systemd 的复杂度确实比 SysV init 高很多。但对于每天都要和服务打交道的人来说，这个复杂度换来的是一套可预测、可调试的管理体系。

还记得开头那个问题吗——你写了一个网络服务，希望它开机就跑、挂了自动重启、日志统一管理？现在你应该知道怎么做了：写一个 unit 文件，`systemctl enable --now`，搞定。unit 文件里的 `Restart=on-failure` 解决了自动重启，`journalctl -u` 解决了日志查看。不需要祈祷，不需要手写 Shell 脚本。

下一章我们会从系统管理转向网络——当你的开发需要联网、需要远程连接开发板的时候，网络配置和诊断就成了必须掌握的技能。

---

[← 上一章：进程管理](ch19-process.md)
[下一章：网络配置 →](../05-network/ch21-netconfig.md)
