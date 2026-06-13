# 第 3 章  换源、语言、基础工具初始化

> **Part 1 · 环境搭建**

---

## 引子

Ubuntu 装好了。你兴冲冲地打开终端，敲下第一行命令——

然后等了五分钟。

不是命令错了，是默认的软件源在地球另一边。
国内访问 Ubuntu 官方源，速度堪比拨号上网。
这还只是第一个问题：中文显示方块、输入法没法用、
连 git 和 vim 都没装……

一台刚装好的 Ubuntu，离"能干活"之间，还差一次系统级的初始化。
这次初始化做得好不好，直接决定你接下来每一章的体验。

---

## 背景与动机

无论你用的是 WSL2 还是虚拟机，刚装好的 Ubuntu 都是一副"毛坯房"的状态——系统能跑，但什么都别扭。

这种感觉就像搬进了一套新房子：水电是通的，但水龙头流出来的水得等半小时（软件源在地球另一边），门牌号写的是英文（系统语言没配），工具箱是空的（开发工具一个没装）。你不能在这种状态下开始干活——你得先把基础设施搞定。

这次初始化要做四件事：

1. **换源**——把软件仓库从官方源（国外）换成国内镜像源，下载速度从 KB/s 跳到 MB/s。
2. **中文环境**——安装中文语言包和字体，让系统不再显示方块字。
3. **输入法**——装一个能用的中文输入法，后面写注释、查文档都用得到。
4. **开发工具**——安装 git、vim、build-essential 等基础工具链。

这些事没有严格的顺序依赖，但有一个逻辑上的先后：先换源（因为后面所有 `apt install` 都依赖源的速度），再装其他东西。

这一章的内容同时适用于 WSL2 和虚拟机——命令完全一样，不需要区分。

---

## 概念层

### APT 与软件仓库——Linux 的"供应链"

在 Linux 上安装软件，最常用的方式是通过**包管理器**。Ubuntu 的包管理器叫 **APT**（Advanced Package Tool）。

APT 的工作方式像一条供应链：当你说"我要装 vim"，APT 不会凭空变出一个 vim——它会去**软件仓库**（repository）里找。仓库是一个存放了成千上万软件包的服务器。APT 连上去，下载软件包，解压安装，一气呵成。

```
你（apt install vim）
  → APT 去仓库服务器查找 vim
    → 仓库返回 vim 的安装包
      → APT 下载并安装
```

问题出在哪？Ubuntu 的默认仓库服务器在英国（Canonical 的官方服务器）。从国内访问，延迟高、带宽受限，一个几 MB 的软件包可能要下几分钟。而一次系统更新动辄几百 MB——按这个速度，等它下完你可以去喝杯咖啡再回来。

这就是为什么要换源。所谓"源"，就是仓库服务器的地址。换成国内的镜像服务器（比如清华、中科大、阿里云的），同样的软件包，下载速度快几十倍。

**供应链类比**：默认的源就像你住在上海，但日用品要从伦敦的仓库发货——每个快递漂洋过海要好几周。换源就是在北京找个同品牌的仓库，同样的商品，隔天就到。

但这个类比有一个地方需要修正——仓库里的"商品"（软件包）不是复制品，它们和官方源上的**完全相同**。国内镜像服务器做的事，是定时从官方源同步一份完整的拷贝。你拿到的软件包，内容和校验码都和从伦敦下载的一模一样——只是快递快了。

现在问题来了：既然镜像源这么好，Ubuntu 为什么不默认用国内源？因为 Ubuntu 不知道你在中国——它面向全球用户，默认指向官方源是最通用的选择。手动换源，是你根据自己所在位置做的一次"本地化优化"。

### sources.list——仓库地址簿

APT 去哪个仓库找软件，由一个配置文件决定。在 Ubuntu 22.04 上，这个文件是：

```
/etc/apt/sources.list
```

在 Ubuntu 24.04 上，Ubuntu 引入了一种新的格式（DEB822），默认配置文件变成了：

```
/etc/apt/sources.list.d/ubuntu.sources
```

无论哪种格式，核心内容都一样：一行行仓库地址，标注了仓库名、版本代号（jammy 或 noble）和组件分类（main、restricted、universe、multiverse）。

换源的本质操作就是：把这个文件里的官方域名（`archive.ubuntu.com`）替换成国内镜像域名（比如 `mirrors.tuna.tsinghua.edu.cn`）。

---

## 实践层

### 4.1  备份并替换软件源

这是这一章的第一步，也是最重要的一步。先备份，再替换。万一换出问题了，还能恢复。

```bash
# 备份原始源配置文件
# Ubuntu 22.04
$ sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup

# Ubuntu 24.04（如果你用的是 24.04）
$ sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.backup
```

> ⚠️ **永远先备份**
> 每次修改系统配置文件之前，先备份一份。这不是矫情，是工程习惯。后面你在嵌入式开发中修改设备树、内核配置、U-Boot 环境变量时，这个习惯会救你很多次。

现在查看你的 Ubuntu 版本代号：

```bash
# 查看系统版本信息
$ lsb_release -a
# 预期输出（22.04）
# Distributor ID: Ubuntu
# Description:    Ubuntu 22.04.x LTS
# Release:        22.04
# Codename:       jammy

# 预期输出（24.04）
# Distributor ID: Ubuntu
# Description:    Ubuntu 24.04.x LTS
# Release:        24.04
# Codename:       noble
```

记住这个 Codename（`jammy` 或 `noble`）——它决定了源的 URL 格式。

**Ubuntu 22.04 —— 编辑 sources.list**：

用 `sed` 直接替换域名，这是最快也最不容易出错的方法：

```bash
# 将官方源替换为清华镜像源
$ sudo sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
$ sudo sed -i 's|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
```

如果你想手动编辑看清楚改了什么：

```bash
$ sudo nano /etc/apt/sources.list
```

把文件中的 `archive.ubuntu.com` 和 `security.ubuntu.com` 全部替换为 `mirrors.tuna.tsinghua.edu.cn`。替换后的文件看起来类似这样：

```
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
```

**Ubuntu 24.04 —— 编辑 ubuntu.sources**：

24.04 使用新的 DEB822 格式。同样用 `sed` 替换：

```bash
# 将官方源替换为清华镜像源（24.04 DEB822 格式）
$ sudo sed -i 's|http://archive.ubuntu.com/ubuntu|https://mirrors.tuna.tsinghua.edu.cn/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources
$ sudo sed -i 's|http://security.ubuntu.com/ubuntu|https://mirrors.tuna.tsinghua.edu.cn/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources
```

替换完成后，更新本地索引：

```bash
# 刷新软件包列表
$ sudo apt update
# 预期输出（截取关键行）
# 命中:1 https://mirrors.tuna.tsinghua.edu.cn/ubuntu jammy InRelease
# 命中:2 https://mirrors.tuna.tsinghua.edu.cn/ubuntu jammy-updates InRelease
# ...
# 正在读取软件包列表... 完成
```

如果看到"命中"而不是"忽略"或"错误"，说明换源成功了。从现在开始，所有 `apt install` 都从清华的服务器下载——速度应该比之前快一个数量级。

**其他可选镜像源**：清华不是唯一的选择。如果清华的源偶尔抽风，换成别的试试：

| 镜像源 | 域名 |
|--------|------|
| 清华大学 | `mirrors.tuna.tsinghua.edu.cn` |
| 中国科技大学 | `mirrors.ustc.edu.cn` |
| 阿里云 | `mirrors.aliyun.com` |
| 华为云 | `mirrors.huaweicloud.com` |

替换方法完全一样，只是把域名换一下。这些镜像之间，软件包内容完全相同，差别只在同步速度和网络连通性。

顺便把系统已有的包升级到最新：

```bash
# 升级所有已安装的软件包
$ sudo apt upgrade -y
```

这一步可能需要几分钟，取决于有多少包需要更新。`-y` 参数表示自动确认，不用你一个个按回车。

### 4.2  中文环境配置

换完源之后，装什么都快了。先解决中文显示问题。

```bash
# 安装中文语言包
$ sudo apt install -y language-pack-zh-hans language-pack-zh-hans-base

# 设置系统语言环境
$ sudo update-locale LANG=zh_CN.UTF-8
```

安装中文字体（桌面环境需要，WSL2 如果只用终端可以跳过）：

```bash
# 安装中文字体
$ sudo apt install -y fonts-noto-cjk fonts-wqy-zenhei
```

`fonts-noto-cjk` 是 Google 的 Noto 字体家族（中日韩），开源且覆盖全面。`fonts-wqy-zenhei` 是文泉驿正黑，经典的开源中文字体。两个都装上，基本不会再遇到方块字的问题。

让语言设置生效：

```bash
# 让当前终端会话加载新的语言设置
$ source /etc/default/locale

# 验证
$ echo $LANG
# 预期输出
zh_CN.UTF-8
```

如果你用的是虚拟机，注销并重新登录可以让整个桌面环境的语言生效。WSL2 的话，关掉终端重新打开就行。

### 4.3  输入法安装

中文输入法在 Linux 上一直是个生态短板——不如 Windows 上的搜狗、微信输入法那么好用，但能凑合。

推荐方案是 **Fcitx5 + 拼音**，比系统自带的 IBus 拼音体验好不少：

```bash
# 安装 Fcitx5 输入法框架和拼音引擎
$ sudo apt install -y fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5

# 将 Fcitx5 设为默认输入法框架
$ im-config -n fcitx5
```

虚拟机用户：注销并重新登录后，右上角会出现一个键盘图标。点击它 → 配置 → 添加"拼音"输入法。切换快捷键默认是 `Ctrl + Space`。

WSL2 用户：WSL2 里没有桌面环境，输入法对你暂时没用——你在 Windows 终端里直接用 Windows 的输入法就行。但如果你后面要在 WSLg 里跑 GUI 程序，上面的安装步骤同样适用。

**一个诚实的评价**：Linux 上的中文输入法和 Windows 上的相比，选词准确率和词库丰富度都有差距。如果你实在受不了，可以在虚拟机里安装搜狗 Linux 版（从搜狗官网下载 `.deb` 包），但搜狗目前只适配 Fcitx（旧版本），对 Fcitx5 的支持还在跟进中。先用系统自带的凑合，后面真觉得难受了再换。

### 4.4  基础开发工具安装

回到那个供应链的类比——现在仓库已经换到本地了（清华镜像源），快递速度上来了。接下来开始采购"工具箱"。

嵌入式开发有几样东西是装机必备的：

```bash
# 安装基础编译工具链（gcc, g++, make 等）
$ sudo apt install -y build-essential

# 安装 Git 版本控制
$ sudo apt install -y git

# 安装 Vim 编辑器（系统自带的是精简版 vim.tiny，功能太少）
$ sudo apt install -y vim

# 安装其他常用工具
$ sudo apt install -y curl wget tree htop
```

逐个解释为什么要装这些：

**build-essential**：这是一个元包（meta package），装它会自动拉取 `gcc`、`g++`、`make`、`libc-dev` 等编译工具。后面第 31 章讲 GCC 和 Makefile 时，你离不开它们。即使你现在还不知道这些工具是干什么的，先装上，后面用到时不会抓瞎。

**git**：版本控制系统。嵌入式项目的代码量通常不小（内核源码几千万行），没有版本管理就是在玩火。第 34 章会专门讲 Git 的日常操作。

**vim**：终端里的文本编辑器。配置文件、脚本、源码——在 Linux 下你需要频繁编辑纯文本文件，Vim 是效率最高的工具之一（等你熟练之后）。第 12 章会专门讲 Vim 的使用。注意，Ubuntu 默认装的 `vim.tiny` 是精简版，很多功能（语法高亮、可视化模式）没有，必须手动装完整版。

**curl / wget**：命令行下载工具。后面下载交叉编译工具链、拉取源码时常用。

**tree**：以树状结构显示目录，比 `ls -R` 直观得多。

**htop**：增强版的任务管理器，比系统自带的 `top` 好用。

装完之后，验证一下：

```bash
# 验证 gcc
$ gcc --version
# 预期输出
# gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
# （版本号可能不同，有输出就行）

# 验证 git
$ git --version
# 预期输出
# git version 2.34.1（22.04）或更新版本

# 验证 vim
$ vim --version | head -n 1
# 预期输出
# VIM - Vi IMproved 8.2（22.04）或 9.x（24.04）
```

每一行都有输出，就说明工具装好了。

### 4.5  WSL2 和虚拟机的初始化差异

这一章的内容在 WSL2 和虚拟机上完全通用——命令一模一样。但有几个小细节值得说明：

**WSL2 用户**：
- 不需要安装桌面字体和输入法（你用的是 Windows 的桌面和输入法）。
- 不需要安装 Fcitx5。
- WSL2 默认的 `/etc/apt/sources.list` 可能和虚拟机略有不同（微软发行的 Ubuntu 在微软的仓库里有定制包），但换源方法一样。
- WSL2 里没有 `systemd` 的完整支持——某些服务管理命令行为会不同。不过目前这一章不涉及 systemd。

**虚拟机用户**：
- 桌面分辨率如果还是看着别扭，在 Ubuntu 设置 → 显示 里调整。VMware Tools（装系统后 VMware 会提示你安装）装好之后，分辨率可以自动适配窗口大小。
- 虚拟机里可以安装 VMware Tools 增强功能（支持剪贴板共享、拖拽文件、自适应分辨率）：

```bash
# 安装 VMware Tools 的开源替代 open-vm-tools
$ sudo apt install -y open-vm-tools open-vm-tools-desktop
```

---

## 练习题

走到这里，你的 Ubuntu 应该已经从"毛坯房"变成了"精装房"。
下面几道题检验一下你是不是真懂了，而不只是照着敲命令。

**练习 3.1** ⭐（理解）

请用自己的话解释：什么是软件源（repository）？为什么要换国内镜像源？换源之后，你安装的软件和从官方源安装的软件有什么区别？

**练习 3.2** ⭐⭐（应用）

你的同事告诉你，他执行 `sudo apt update` 时速度很慢，并且报了一些 "Failed to fetch" 的错误。请给出排查步骤：你会先检查什么？最可能的原因是什么？怎么修复？

> **提示**：回想一下这一章的换源过程。`apt update` 是从哪里获取软件包列表的？

**练习 3.3** ⭐⭐⭐（思考）

Ubuntu 22.04 的版本代号是 `jammy`，24.04 是 `noble`。如果有人把 22.04 的 sources.list 直接复制到 24.04 的机器上使用（不修改版本代号），会发生什么？为什么？

> **提示**：软件包的版本、依赖关系在不同 Ubuntu 版本之间是否兼容？

---

## 本章回响

本章做的事情很"世俗"——换源、装语言包、装工具。没有高深的概念，没有炫技的操作。但正是这些琐碎的事情，决定了一台 Linux 机器能不能真正用于开发。

理解了 APT 和软件源的工作机制之后，你会发现 Linux 的软件安装逻辑和 Windows 完全不同。Windows 的习惯是"去网站下载安装包 → 双击运行 → 下一步下一步"。Linux 的方式是"告诉包管理器你要什么 → 它去仓库找 → 自动下载安装并处理依赖"。后者看起来多了一层抽象，但它解决了一个 Windows 上长期存在的痛点：依赖地狱（DLL Hell）。当你装一个软件，它依赖的库自动装好，卸载时没用的依赖自动清理——这套机制在第 17 章讲软件安装时会详细展开。

还记得开头说的吗——刚装好的 Ubuntu，离"能干活"之间还差一次系统级的初始化。现在这道鸿沟已经被填平了。你的 Ubuntu 有了快速的软件源、能显示中文、装好了基础开发工具。从下一章开始，无论我们装什么新软件、配什么新工具，都不用再忍受"五分钟等一个包"的煎熬了。

下一章我们要解决另一个实际问题——Windows 和 Linux 之间的文件传输。你在 Windows 下下载了开发板的 SDK 压缩包，怎么最快地搬进 WSL2 或虚拟机里？有好几种方案，各有各的适用场景。我们接着走。

---

[← 上一章](ch02-vm.md)
[下一章 →](ch04-file-share.md)
