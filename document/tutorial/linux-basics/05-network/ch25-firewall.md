# 第 25 章  防火墙：ufw

> **Part: Part 5 · 网络与远程**

---

## 引子

你在虚拟机上起了一个 HTTP 服务，从主机浏览器访问——访问不到。

代码没问题。端口在监听。网络是通的。但就是连不上。

折腾了半小时，最后发现是防火墙把 80 端口挡了。

这件事的反直觉之处在于：Ubuntu 安装完之后，防火墙**默认是关着的**——不是开着，是关着。你从来没有主动挡过任何东西，但某个时刻它被激活了，然后默认策略是「拒绝一切入站」。这个策略本身没问题——问题在于你不知道它什么时候被激活的，哪些端口被挡了，以及怎么按需放行。

还有一个更反直觉的事：如果你在跑 Docker，你的防火墙规则可能根本不起作用——Docker 会悄悄绕过 ufw，直接操作底层的 iptables。你以为关了门，其实后门开着。

本章要把这两件事都搞清楚。

---

## 背景与动机

在嵌入式开发中，你的开发环境经常需要对网络暴露服务：SSH 远程连接（第 23 章我们配过）、NFS 共享根文件系统、HTTP 调试接口、TFTP 下载固件（第 24 章用过）。每一种服务都在开一扇门。

但你需要的是**只开必要的门，剩下的全关上**。这就是防火墙做的事。

Linux 内核级别的防火墙实现叫 **netfilter**，用户空间通过 **iptables** 或更新的 **nftables** 来配置规则。这套系统极其强大——也极其复杂。一条典型的 iptables 规则长这样：

```bash
$ sudo iptables -A INPUT -p tcp --dport 22 -m conntrack \
    --ctstate NEW,ESTABLISHED -j ACCEPT
```

这是在干什么？允许新的和已建立的 TCP 连接到 22 端口。光这一条就得理解协议、连接状态跟踪（conntrack）、目标动作（-j ACCEPT）——如果你只是想「把 SSH 端口打开」，这条命令的信息密度太高了。

Ubuntu 给了一个简化的前端工具：**ufw**（Uncomplicated Firewall）。同样的事情，ufw 只需要一句：

```bash
$ sudo ufw allow 22/tcp
```

简洁。人类可读。但简洁的代价是：ufw 把很多细节藏了起来，当你需要精细控制时（比如跑 Docker），这些被藏起来的细节会浮出水面反咬一口。

---

## 概念层

### ufw 和 iptables 的关系

你可以把 ufw 想象成一栋大楼前台的保安——他拿着一份访客名单，按照名单决定谁可以进来。名单上写着「允许 22 端口的 TCP 连接」「允许 192.168.1.0/24 网段的访问」这类简单规则。你看不懂安防系统的内部原理没关系，跟保安说一声「放行 SSH」就行了。

但这个保安只是门面。大楼真正的安防系统是 **iptables/nftables**——它有摄像头、门禁、电子锁，覆盖每一扇门、每一扇窗、每一条走廊。保安手里的访客名单，最终会被翻译成 iptables 规则，注入到内核的 netfilter 框架里。

ufw 本质上是一个**规则翻译器**：你用简单的命令写规则，ufw 把它翻译成 iptables 规则链，然后交给内核执行。

### 默认策略：拒绝一切

ufw 的核心设计哲学是**默认拒绝**（default deny）：

- **入站（incoming）**：默认拒绝——除非你明确放行，否则所有从外部进来的连接都会被丢弃
- **出站（outgoing）**：默认允许——你主动发起的连接不受限制
- **路由转发（routed/forwarded）**：默认拒绝

这个策略的直觉是：「除非我明确说可以，否则都不行」。对于大多数开发环境来说，这是安全的默认选择——你只需要逐个打开需要的端口。

### 规则的结构

每条 ufw 规则本质上在做一件事：**匹配 + 动作**。

匹配条件可以是：

- 端口号（`22`、`80`、`8080`）
- 协议（`tcp`、`udp`）
- 来源地址（`from 192.168.1.0/24`）
- 目标地址（`to 192.168.1.100`）
- 服务名（`ssh`、`http`、`https`——映射关系定义在 `/etc/services` 里）

动作有三种：

- **allow**：放行
- **deny**：拒绝（丢弃数据包，不给回应——对方会超时）
- **reject**：拒绝但回复一个「拒绝」消息（让对方立刻知道被拒绝了）

规则按编号顺序匹配，先匹配到的生效。

### Docker 绕过 ufw 的机制

但「保安拿访客名单」这个比喻，有一个关键的地方是错的：保安只管正门。

Docker 不走正门。

Docker 安装的时候，直接在 iptables 里建了自己的规则体系——在 **nat 表**（网络地址转换表）里创建了 `DOCKER` 链，并挂载到 `PREROUTING` 链上。当 Docker 启动一个容器并映射端口（比如 `docker run -p 8080:80`），它会往 `DOCKER` 链里插入一条 **DNAT**（目标地址转换）规则，把 8080 端口的流量直接转发给容器。

关键在于：nat 表的处理在 filter 表**之前**。也就是说，一个数据包到达时，先被 nat 表的 PREROUTING 链处理（DNAT 转发），然后才到 filter 表的 INPUT 或 FORWARD 链——而 ufw 的规则正挂在 filter 表上。但此时数据包的目标地址已经被 Docker 改写了，ufw 的端口过滤规则根本不会匹配到它。

**你在 ufw 里写的 deny 规则，对 Docker 映射的端口不起作用。**

Docker 也提供了一个 `DOCKER-USER` 链（在 filter 表中），专门让用户添加自定义规则。这条链在 Docker 自己的转发规则之前被处理，你可以在这里加限制——但这意味着你又回到了直接写 iptables 规则的世界，而那正是 ufw 想帮你避开的东西。

---

## 实践层

### 4.1 基础操作

先看 ufw 当前的状态：

```bash
$ sudo ufw status
# 预期输出
Status: inactive
```

Ubuntu 22.04 和 24.04 安装完之后，ufw 是安装了的，但默认处于 **inactive**（未启用）状态。这意味着防火墙没有在工作——所有端口都是开放的。

启用防火墙之前，有一件事必须先做：**确保 SSH 端口是放行的**。如果你通过 SSH 连接到这台机器，直接 `ufw enable` 会把 SSH 连接也断掉——然后你就再也连不上了。

```bash
# 先放行 SSH
$ sudo ufw allow 22/tcp
Rule added
Rule added (v6)
```

然后启用防火墙：

```bash
$ sudo ufw enable
Command may disrupt existing ssh connections. Proceed with operation (y|n)? y
Firewall is active and enabled on system startup
```

ufw 会提示你可能影响 SSH 连接，输入 `y` 确认。

再看状态：

```bash
$ sudo ufw status
# 预期输出
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
22/tcp (v6)                ALLOW       Anywhere (v6)
```

防火墙已经激活，只放行了 SSH（22 端口）。其他所有入站连接都会被丢弃。

> ⚠️ **注意**
> 如果你正在通过 SSH 操作远程服务器，`ufw enable` 之前一定要先 `ufw allow 22/tcp`。
> 不然你将直接失去连接，而且得去控制台物理操作才能恢复。
> 这个坑我亲眼见过别人踩，恢复起来非常麻烦。

如果需要关闭防火墙（不推荐在生产环境这样做）：

```bash
$ sudo ufw disable
Firewall stopped and disabled on system startup
```

### 4.2 常用规则

放行 HTTP（80 端口）：

```bash
$ sudo ufw allow 80/tcp
Rule added
Rule added (v6)
```

放行 HTTPS（443 端口），用服务名代替端口号：

```bash
$ sudo ufw allow https
Rule added
Rule added (v6)
```

ufw 知道常见服务名和端口的对应关系（这个映射在 `/etc/services` 文件里定义）。`ufw allow https` 和 `ufw allow 443/tcp` 效果一样。

只允许特定网段访问某个端口——这在嵌入式开发中很常见，比如只让局域网内的机器访问 NFS（第 24 章我们用过 TFTP，NFS 也是类似的场景）：

```bash
$ sudo ufw allow from 192.168.1.0/24 to any port 2049
Rule added
```

这条规则的意思是：只允许 192.168.1.0/24 网段（子网掩码 255.255.255.0）的机器访问 NFS 端口（2049）。其他来源的请求一律丢弃。

拒绝某个 IP 的所有访问：

```bash
$ sudo ufw deny from 10.0.0.5
Rule added
```

查看所有规则（带编号）：

```bash
$ sudo ufw status numbered
# 预期输出
Status: active

     To                         Action      From
--                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 443                        ALLOW IN    Anywhere
[ 4] 2049                       ALLOW IN    192.168.1.0/24
[ 5] Anywhere                   DENY IN     10.0.0.5
[ 6] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 7] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 8] 443 (v6)                   ALLOW IN    Anywhere (v6)
```

删除规则用编号：

```bash
$ sudo ufw delete 5
Deleting:
 deny from 10.0.0.5
Proceed with operation (y|n)? y
Rule deleted
```

> ⚠️ **注意**
> 每次删除规则后编号会重新排列。如果你要删除多条规则，从编号最大的开始删，
> 或者每次删完重新 `status numbered` 确认，别按惯性操作。

### 4.3 Docker 与 ufw 的坑

这里才是真正的坑。

先做一个实验。确保 ufw 已启用，并且没有放行 8080 端口：

```bash
$ sudo ufw status | grep 8080
# 应该没有任何输出——8080 没有被放行
```

然后启动一个 Docker 容器，映射 8080 端口：

```bash
$ docker run -d -p 8080:80 nginx
# 预期输出
Unable to find image 'nginx:latest' locally
latest: Pulling from library/nginx...
Digest: sha256:...
Status: Downloaded newer image for nginx:latest
a1b2c3d4e5f6...
```

现在从另一台机器（或主机）访问 `http://<你的IP>:8080`。

你猜会怎样？

**访问成功。**

ufw 明明没有放行 8080，但 Docker 映射的端口从外部可以访问。这就是那个坑。

原因我们前面说过：Docker 在 nat 表的 PREROUTING 链里做了 DNAT，数据包在到达 ufw 的 filter 表之前就已经被转发了。ufw 的规则压根没机会拦截。

验证一下，看 iptables 里 Docker 加了什么：

```bash
$ sudo iptables -t nat -L DOCKER
# 预期输出（简化）
Chain DOCKER (2 references)
TARGET     PROT  OPT SOURCE    DESTINATION
RETURN     all   --  anywhere  anywhere
DNAT       tcp   --  anywhere  anywhere  tcp dpt:8080 to:172.17.0.2:80
```

看到了吗？Docker 直接在 NAT 表里把 8080 端口的流量转给了容器的 80 端口。这条规则优先于 ufw 的过滤。

#### 解决方案一：DOCKER-USER 链

Docker 在 filter 表中提供了一个 `DOCKER-USER` 链，专门让用户添加自定义规则。这条链在 Docker 自己的转发规则之前被处理：

```bash
# 只允许 192.168.1.0/24 网段访问 Docker 映射的端口
$ sudo iptables -I DOCKER-USER -i eth0 ! -s 192.168.1.0/24 -j DROP
```

但这个方案的问题是：你在用 iptables 命令手动操作，回到了 ufw 想帮你避开的那套复杂语法。而且这条规则不会在重启后自动恢复——除非你把它写进了启动脚本。

#### 解决方案二：禁止 Docker 操作 iptables

更彻底的做法是告诉 Docker：不要自己碰 iptables。

编辑（或创建）Docker 的配置文件：

```bash
$ sudo vim /etc/docker/daemon.json
```

添加以下内容（如果文件已有配置，把 `"iptables": false` 加到现有的 JSON 对象里）：

```json
{
  "iptables": false
}
```

然后重启 Docker：

```bash
$ sudo systemctl restart docker
```

> ⚠️ **注意**
> 设置 `"iptables": false` 之后，Docker 的网络功能会受到**严重影响**：
> - 容器的端口映射（`-p`）不再自动工作
> - 容器可能无法访问外网（因为 Docker 不再自动配置 masquerade）
> - 容器间的网络通信需要手动配置
>
> Docker 官方文档的原话是："this option is not appropriate for most users."
> 如果你只是用 Docker 做嵌入式交叉编译环境的隔离（不需要容器对外暴露端口），
> 这个方案可以接受。但如果你需要 Docker 的完整网络功能，建议用 DOCKER-USER 链方案。

改完之后验证：

```bash
$ sudo iptables -t nat -L DOCKER
# 预期输出
Chain DOCKER (2 references)
TARGET     PROT  OPT SOURCE    DESTINATION
RETURN     all   --  anywhere  anywhere
```

Docker 不再自动添加 DNAT 规则。现在 ufw 的规则是唯一的关卡。

回到那个保安的比喻：你现在应该能看出来，ufw 是正门的保安，拿着你给的访客名单放行或拒绝。而 Docker 之前在后墙凿了个洞，自己装了扇门——保安根本不知道，因为保安只在正门值守。`DOCKER-USER` 链是给保安在后门也加了个岗哨；而 `iptables: false` 则是把后门直接封死了——Docker 不再自己开门，所有进出都归保安管。但封死后门的代价是：Docker 容器的网络功能也会大打折扣。

---

## 练习题

走到这里，防火墙的基本逻辑应该清楚了。下面几道题从易到难，建议先不看提示自己想。

**练习 25.1** ⭐（理解）

ufw 的默认策略是「入站拒绝、出站允许」。请解释：为什么出站要默认允许？如果把出站也设为默认拒绝，你的系统会遇到什么问题？

**练习 25.2** ⭐⭐（应用）

你需要配置一台嵌入式开发服务器的防火墙，要求：

- 只允许 SSH（22 端口）从 192.168.0.0/16 网段访问
- 允许 HTTP（80 端口）从任何地方访问
- 拒绝其他所有入站连接

写出需要的 ufw 命令序列。

**练习 25.3** ⭐⭐⭐（思考）

Docker 绕过 ufw 的根本原因是它直接操作 iptables。请思考：为什么 Docker 要这样设计，而不是通过 ufw 来管理端口？如果 Docker 改为通过 ufw 放行端口，会有什么问题？

> **提示**：考虑 Docker 容器的生命周期——创建、销毁、重启——以及多容器同时运行时的规则管理。

---

## 本章回响

防火墙的核心认知其实只有一个：**默认拒绝，按需放行**。这个原则不只是防火墙的设计哲学，也是网络安全的基本思维方式——你不需要的东西，就不该开着。

ufw 把这个原则封装成了几条简单的命令。但理解了 ufw 背后的 iptables 之后，你会对「简单」这个词有更深的认识：ufw 的简单是靠把复杂性藏起来换来的。当 Docker 出现的时候，这些被藏起来的复杂性就会浮出水面——nat 表的 DOCKER 链、filter 表的 DOCKER-USER 链、PREROUTING 的 DNAT——你不得不再去理解 iptables 的表和链、数据包的匹配顺序，才能搞清楚为什么防火墙「不起作用」。

还记得开头那个场景吗——HTTP 服务访问不到，最后发现是防火墙挡了？现在你应该能系统地排查了：先 `ufw status` 看防火墙是否启用，再检查对应端口有没有放行，最后看是不是 Docker 在绕过规则。三个检查点，顺序固定。反过来说，如果你用了 Docker 且没做任何处理，你的容器端口可能已经暴露在网络上——而这个风险你可能一直不知道。

下一章我们会从网络切换到脚本——当你在终端里重复执行同样的命令序列时，是时候把它写成一个脚本了。那是 Part 6 的开始，也是你从「手动操作」到「自动化」的转折点。

---

[← 上一章](ch24-transfer.md)
[下一章 →](../06-script/ch26-bash-basic.md)
