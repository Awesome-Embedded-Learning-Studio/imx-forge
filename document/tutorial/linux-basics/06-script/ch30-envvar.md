# 第 30 章  环境变量与 Shell 配置文件

> **Part 6 · 脚本与自动化**

---

## 引子

你在终端里敲 `gcc`，系统怎么知道 `gcc` 在哪？

因为 `PATH` 环境变量里写了搜索路径。

你在终端里设置了一个别名，关掉终端再打开，别名没了。因为那个别名只存在于当前 Shell 进程里，进程死了它就没了。

环境变量是 Shell 和操作系统之间的「共享记忆」，而 `.bashrc`、`.profile`、`/etc/profile` 这些配置文件，是这段记忆的「持久化存储」。

但这里有一个问题，几乎每个初学者都踩过：你的配置到底应该写在 `.bashrc` 里还是 `.profile` 里？为什么有时候改了 `.bashrc` 不生效，有时候又生效了？搞清楚 login shell 和 non-login shell 的区别，这些困惑就迎刃而解。

---

## 背景与动机

如果你在前面章节跟下来了，现在应该已经能写 Shell 脚本了。但有一个问题你可能一直隐隐感觉到，却没有深究：为什么有些变量你在脚本里设了，另一个脚本就看不到了？为什么 `echo $PATH` 能输出一长串目录，你从来没手动设过这些东西？

答案藏在两个机制里：**环境变量的继承规则**，以及 **Shell 启动时加载的配置文件**。

这两个机制在嵌入式开发中尤其重要。当你配置交叉编译工具链的时候（我们会在第 35 章讲到），你需要把工具链的路径加到 `PATH` 里——写错位置，要么每次开机都要手动设一遍，要么 SSH 登录时找不到编译器。理解环境变量的生命周期和 Shell 配置文件的加载顺序，才能一次性把配置写对。

---

## 概念层

### 什么是环境变量

环境变量是操作系统维护的一组键值对，每个运行中的进程都持有自己的一份副本。你可以用 `printenv` 或 `env` 查看当前 Shell 进程的全部环境变量：

```bash
$ printenv | head -10
HOME=/home/charlie
LANG=en_US.UTF-8
LOGNAME=charlie
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash
TERM=xterm-256color
USER=charlie
```

你可以把环境变量想象成**工作台上的便签纸**。每个进程有一张工作台，上面贴着各种便签。有些便签是进程自己写的（Shell 变量），有些是「交接班时从前一个工人那里继承来的」——后面这类就是环境变量。`HOME` 告诉程序你的家目录在哪，`PATH` 告诉 Shell 去哪些目录找可执行文件，`LANG` 告诉程序该用什么语言。

但这个类比有一个地方是错的。真正的便签纸贴在桌面上，谁路过都能看到。环境变量不是这样的——它是进程启动时的一份**拷贝**。子进程拿到的是父进程环境变量的副本，之后子进程怎么改，父进程都不会知道。这个继承是单向的、一次性的。

在 Shell 里设置一个变量很简单：

```bash
# 设置一个 Shell 变量（只有当前 Shell 能看到）
$ MY_VAR="hello"

# 验证
$ echo $MY_VAR
hello
```

但如果你现在开一个新的 Shell——比如输入 `bash` 回车——新 Shell 里是看不到 `MY_VAR` 的：

```bash
$ bash
$ echo $MY_VAR

# 空的——新进程没有继承这个变量
$ exit
```

### export：把变量放进环境

`export` 命令做的事情，就是把一个 Shell 变量「升级」为环境变量，让它能被子进程继承：

```bash
$ MY_VAR="hello"
$ export MY_VAR
$ bash
$ echo $MY_VAR
hello
# 这次看到了——因为 export 让子进程拿到了一份拷贝
$ exit
```

也可以一步到位：

```bash
$ export MY_VAR="hello"
```

对应的逆操作是 `unset`，删除一个变量：

```bash
$ unset MY_VAR
$ echo $MY_VAR

# 空的——变量没了
```

回到便签纸的类比。`export` 就是把你桌上的便签贴到「交接班记录本」上，下一个接班的人（子进程）翻开记录本就能看到。没 `export` 的便签只在你自己的桌上，接班的人看不到。而 `.bashrc` 和 `.profile` 这些配置文件，就是记录本的模板——每次开班之前，系统会按模板把便签贴好。

### PATH：系统怎么找到命令

`PATH` 是最关键的环境变量之一。它的值是一个以冒号 `:` 分隔的目录列表：

```bash
$ echo $PATH
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

当你在终端里输入 `gcc` 并回车时，Shell 按以下步骤工作：

1. 检查 `gcc` 是不是 Shell 内建命令——不是。
2. 从 `PATH` 最左边的目录 `/usr/local/sbin` 开始，看看里面有没有叫 `gcc` 的可执行文件——没有。
3. 继续找下一个目录 `/usr/local/bin`——也没有。
4. 再找 `/usr/bin`——找到了，执行 `/usr/bin/gcc`。

**搜索是从左到右的，找到第一个就停。** 这意味着如果你在 `PATH` 前面加了一个目录，里面放了一个也叫 `gcc` 的文件，系统会优先执行那个——原来的 `gcc` 就被「遮盖」了。

这个特性在实践中非常有用。当你安装交叉编译工具链时，工具链里有 `arm-linux-gnueabihf-gcc` 这样的命令，你需要把工具链的 `bin/` 目录加到 `PATH` 里，Shell 才能找到它：

```bash
# 临时加到 PATH（只在当前 Shell 有效）
$ export PATH="/opt/arm-toolchain/bin:$PATH"
```

⚠️ **注意格式**：是 `PATH="新目录:$PATH"`，不是 `PATH="新目录"`。后者会覆盖整个 PATH，你的系统就找不到任何命令了——连 `ls` 都得用完整路径 `/bin/ls` 来执行。说实话，这个坑我踩过不止一次。

### login shell vs non-login shell

这是理解 Shell 配置文件的关键。

**login shell** 是需要完整登录流程的 Shell。典型的场景：
- SSH 远程登录
- 在 TTY 终端（Ctrl+Alt+F1~F6）输入用户名密码登录
- `su - username` 切换用户

**non-login shell** 是不需要登录流程的 Shell。典型的场景：
- 在桌面环境里打开终端模拟器（Ubuntu 里右键「Open Terminal」）
- 在已有 Shell 里输入 `bash` 开新 Shell
- `su username`（不带 `-`）切换用户

判断方法很简单：

```bash
$ echo $0
-bash
# 前面有减号 → login shell

$ echo $0
bash
# 前面没有减号 → non-login shell
```

为什么要区分？因为这两种 Shell 启动时读取的配置文件不一样。

### 配置文件的加载顺序

login shell 启动时读取：

```
/etc/profile
  → ~/.bash_profile（如果存在）
  → ~/.bash_login（如果上面不存在）
  → ~/.profile（如果上面两个都不存在）
```

non-login shell 启动时读取：

```
~/.bashrc
```

就这些？看起来很不对称。Ubuntu 默认的 `~/.profile` 里有一段关键代码：

```bash
# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
```

这段代码的意思是：如果当前 Shell 是 Bash，就把 `~/.bashrc` 也 source 进来。所以实际上，login shell 会先读 `/etc/profile` 和 `~/.profile`，然后再读 `~/.bashrc`。non-login shell 只读 `~/.bashrc`。

这也是为什么大部分人的经验是「把配置写在 `.bashrc` 里就行了」——因为不管哪种 Shell，`.bashrc` 都会被读到。但如果你换到一个不 source `.bashrc` 的系统（比如某些最小化安装），写在 `.bashrc` 里的配置在 login shell 里就不生效。

**经验法则**：

| 配置类型 | 写在哪里 | 原因 |
|---|---|---|
| 环境变量（PATH 等） | `~/.profile` | 只需在登录时设置一次 |
| 别名、函数、Shell 选项 | `~/.bashrc` | 每开一个 Shell 都需要生效 |
| 全局配置（所有用户） | `/etc/profile` | 系统管理员级别 |

修改配置文件后，用 `source` 让它在当前 Shell 生效：

```bash
$ source ~/.bashrc
```

`source` 也可以简写为一个点：

```bash
$ . ~/.bashrc
```

两种写法完全等价。

---

## 实践层

### 4.1  查看和操作环境变量

查看所有环境变量：

```bash
$ env
# 或者
$ printenv
```

查看某个特定的变量：

```bash
$ echo $HOME
/home/charlie

$ printenv HOME
/home/charlie
```

注意这两种写法的区别：`echo $HOME` 是 Shell 展开变量后交给 `echo` 打印，`printenv HOME` 是直接查环境变量表。通常两者结果一致，但在某些边缘情况下（比如变量名包含特殊字符），`printenv` 更可靠。

设置、导出、验证、清除一个变量的完整流程：

```bash
$ TOOLCHAIN_DIR="/opt/arm-toolchain"
$ export TOOLCHAIN_DIR
$ bash -c 'echo $TOOLCHAIN_DIR'
/opt/arm-toolchain
# 子进程能看到

$ unset TOOLCHAIN_DIR
$ bash -c 'echo $TOOLCHAIN_DIR'

# 子进程看不到了
```

### 4.2  理解 PATH 的工作机制

先看看当前的 PATH：

```bash
$ echo $PATH
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
```

用 `which` 查看某个命令的实际位置——它就是在 PATH 的目录里逐个搜索：

```bash
$ which gcc
/usr/bin/gcc

$ which python3
/usr/bin/python3

$ which ls
alias ls='ls --color=auto'
    /usr/bin/ls
```

`which ls` 的输出有点奇怪——它先显示了一个 alias，然后才是实际路径。这是因为 Bash 在查找可执行文件之前，会先检查 alias 和 Shell 内建命令。

模拟一下 PATH 遮盖的效果。假设你在家目录下创建了一个脚本，名字也叫 `ls`：

```bash
$ mkdir -p ~/mybin
$ echo '#!/bin/bash' > ~/mybin/ls
$ echo 'echo "这是假的 ls"' >> ~/mybin/ls
$ chmod +x ~/mybin/ls
$ export PATH="$HOME/mybin:$PATH"
$ ls
这是假的 ls
```

Shell 找到了 `~/mybin/ls`，就不再继续找后面的 `/usr/bin/ls` 了。

恢复：

```bash
$ export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
$ rm -rf ~/mybin
```

### 4.3  配置文件实战

看看你系统上这几个配置文件的实际情况：

```bash
# 全局配置（系统管理员设置）
$ cat /etc/profile

# 用户级 login shell 配置
$ cat ~/.profile

# 用户级 non-login shell 配置
$ cat ~/.bashrc
```

`.bashrc` 里通常已经有一些默认内容——Ubuntu 安装时自动生成的。你会发现里面有 alias 定义（比如 `alias ll='ls -alF'`）、提示符设置（`PS1`）、以及一些 if-fi 条件块。

我们来做一个实际练习：把一个自定义目录永久加到 PATH 里。

打开 `~/.bashrc`，在文件末尾加一行：

```bash
export PATH="$HOME/mybin:$PATH"
```

保存后让配置生效：

```bash
$ source ~/.bashrc
$ echo $PATH
/home/charlie/mybin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
```

`$HOME/mybin` 出现在了 PATH 最前面。

为什么写在 `.bashrc` 而不是 `.profile`？对于 PATH 这种环境变量，严格来说写在 `.profile` 更符合设计意图——它只在登录时设一次，然后通过继承传递给所有子进程。但实际中很多人习惯写在 `.bashrc` 里，因为 Ubuntu 的 `.profile` 会 source `.bashrc`，所以两种写法都能生效。如果你追求规范性，PATH 写 `.profile`，别名和函数写 `.bashrc`。

这里还有一件事值得提一下。如果你需要配置交叉编译工具链——后面第 35 章会用到——标准的做法是在 `.bashrc` 末尾加一段：

```bash
# ARM 交叉编译工具链
if [ -d "/opt/arm-toolchain/bin" ]; then
    export PATH="/opt/arm-toolchain/bin:$PATH"
fi
```

加了目录存在性检查（`-d`），防止工具链没装的时候 PATH 里出现无效路径。

---

## 练习题

走到这里，环境变量和配置文件的加载逻辑应该清楚了——或者你以为清楚了。下面两道题帮你验证。

**练习 30.1** ⭐（理解）

login shell 和 non-login shell 在启动时分别读取哪些配置文件？如果在 `~/.profile` 里写了一句 `export MY_VAR="from_profile"`，在 `~/.bashrc` 里写了 `export MY_VAR="from_bashrc"`，在一个 Ubuntu 桌面环境打开终端后，`echo $MY_VAR` 会输出什么？为什么？

**练习 30.2** ⭐⭐（应用）

假设你安装了一个交叉编译工具链，可执行文件在 `/opt/gcc-arm/bin/` 目录下。请说明：
1. 如何临时让当前终端能找到 `arm-linux-gnueabihf-gcc`？
2. 如何永久生效？应该把配置写在哪个文件里？
3. 如果写完之后 SSH 登录能找到命令，但桌面终端里找不到，可能是什么原因？

> **提示**：思考 login shell 和 non-login shell 的配置文件加载差异。

---

## 本章回响

环境变量表面上是一组键值对，实际上它解决的问题是进程间的信息传递。一个进程怎么告诉它的子进程「家目录在哪」「去哪里找命令」「用什么语言」？靠的就是这份启动时复制过去的环境。理解了这个单向继承机制，`export` 和 `source` 的行为就不再神秘——前者决定信息能不能传下去，后者是在当前进程里执行一段配置脚本。

还记得开头那两个问题吗——系统怎么知道 `gcc` 在哪，以及为什么你的别名关掉终端就没了？第一个答案：`PATH` 环境变量里写了一组目录，Shell 从左到右搜。第二个答案：别名只在当前 Shell 进程里存在，进程死了就没了——要持久化，必须写进 `.bashrc` 或 `.profile` 这样的配置文件里。

`.bashrc` 和 `.profile` 之间的「恩怨情仇」，本质上就是 login shell 和 non-login shell 的区别。Ubuntu 的 `.profile` 会 source `.bashrc`，所以大部分时候你感受不到差异。但理解这套加载顺序，在遇到「配置不生效」的问题时，你就能快速定位原因。

下一章我们会进入开发工具链的领域——当你的 C 程序编译完了，怎么调试它，是 GDB 要解决的问题。

---

[← 上一章：定时任务](ch29-cron.md)
[下一章：GCC 与 Makefile 基础 →](../07-devtools/ch31-gcc-make.md)
