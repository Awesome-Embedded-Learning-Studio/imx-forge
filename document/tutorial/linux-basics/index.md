# Ubuntu Linux 实用教程 —— 嵌入式开发预备营

> 35 章场景驱动教程，从零 Linux 基础到交叉编译，无缝衔接 [imx-forge](../../tutorial/start/00_roadmap.md) 嵌入式 Linux 项目。

---

## 这份教程写给谁

你是有 Windows 使用经验的开发者，可能玩过单片机，对「嵌入式」有模糊的兴趣，但一打开 Linux 终端就手足无措。这份教程不是一本面面俱到的 Linux 百科——它只讲嵌入式开发中真正用得到的东西，每一步都指向一个具体的使用场景。

**前置要求**：一台能上网的电脑（Windows/Linux/macOS 均可），不需要任何 Linux 基础。

**预计学时**：40-60 小时（含练习）。

---

## 目录

### Part 1：环境搭建

> 让你在任何操作系统上拥有一台可用的 Ubuntu 开发环境。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 1 | WSL2：Windows 里秒开 Linux | [ch01-wsl2.md](01-environment/ch01-wsl2.md) |
| 2 | 虚拟机安装 Ubuntu | [ch02-vm.md](01-environment/ch02-vm.md) |
| 3 | 换源、语言、基础工具初始化 | [ch03-init.md](01-environment/ch03-init.md) |
| 4 | Windows 与 Linux 文件互传 | [ch04-file-share.md](01-environment/ch04-file-share.md) |
| 5 | Docker 开发环境搭建 | [ch05-docker.md](01-environment/ch05-docker.md) |

### Part 2：命令行生存

> 能在终端中独立完成日常文件操作，不再害怕黑框框。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 6 | 终端与 Shell 入门 | [ch06-shell.md](02-commandline/ch06-shell.md) |
| 7 | 目录导航 | [ch07-navigate.md](02-commandline/ch07-navigate.md) |
| 8 | 文件操作 | [ch08-fileops.md](02-commandline/ch08-fileops.md) |
| 9 | 文件查看 | [ch09-fileview.md](02-commandline/ch09-fileview.md) |
| 10 | 搜索与查找 | [ch10-search.md](02-commandline/ch10-search.md) |
| 11 | 压缩归档 | [ch11-archive.md](02-commandline/ch11-archive.md) |

### Part 3：文本与编辑

> 能在终端中自如地查看和编辑配置文件、处理日志。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 12 | VIM 编辑器实战 | [ch12-vim.md](03-text/ch12-vim.md) |
| 13 | 文本处理三剑客 | [ch13-textproc.md](03-text/ch13-textproc.md) |
| 14 | 重定向与管道 | [ch14-redirect.md](03-text/ch14-redirect.md) |

### Part 4：系统管理

> 能独立管理 Ubuntu 系统的用户、权限、软件和存储。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 15 | 用户与组管理 | [ch15-user.md](04-system/ch15-user.md) |
| 16 | 权限模型详解 | [ch16-permission.md](04-system/ch16-permission.md) |
| 17 | 软件安装全解 | [ch17-software.md](04-system/ch17-software.md) |
| 18 | 磁盘管理 | [ch18-disk.md](04-system/ch18-disk.md) |
| 19 | 进程管理——程序卡了怎么办 | [ch19-process.md](04-system/ch19-process.md) |
| 20 | 服务管理：systemd | [ch20-systemd.md](04-system/ch20-systemd.md) |

### Part 5：网络与远程

> 能配置网络、远程连接开发板/服务器、传输文件。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 21 | 网络配置 | [ch21-netconfig.md](05-network/ch21-netconfig.md) |
| 22 | 网络诊断 | [ch22-netdiag.md](05-network/ch22-netdiag.md) |
| 23 | SSH 远程连接 | [ch23-ssh.md](05-network/ch23-ssh.md) |
| 24 | 文件传输 | [ch24-transfer.md](05-network/ch24-transfer.md) |
| 25 | 防火墙：ufw | [ch25-firewall.md](05-network/ch25-firewall.md) |

### Part 6：脚本与自动化

> 能写简单的 Shell 脚本完成日常自动化任务。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 26 | Shell 脚本基础 | [ch26-bash-basic.md](06-script/ch26-bash-basic.md) |
| 27 | 流程控制 | [ch27-flow.md](06-script/ch27-flow.md) |
| 28 | 函数与实战案例 | [ch28-function.md](06-script/ch28-function.md) |
| 29 | 定时任务：crontab | [ch29-cron.md](06-script/ch29-cron.md) |
| 30 | 环境变量与 Shell 配置文件 | [ch30-envvar.md](06-script/ch30-envvar.md) |

### Part 7：开发工具链

> 掌握嵌入式开发所需的基础工具，无缝衔接 imx-forge 教程。

| 章节 | 标题 | 链接 |
|:---:|------|------|
| 31 | GCC 与 Makefile 基础 | [ch31-gcc-make.md](07-devtools/ch31-gcc-make.md) |
| 32 | GDB 调试入门 | [ch32-gdb.md](07-devtools/ch32-gdb.md) |
| 33 | 二进制工具箱 | [ch33-binutils.md](07-devtools/ch33-binutils.md) |
| 34 | Git 日常操作手册 | [ch34-git.md](07-devtools/ch34-git.md) |
| 35 | 交叉编译与 imx-forge 衔接 | [ch35-crosscompile.md](07-devtools/ch35-crosscompile.md) |

---

## 下一步

完成全部 35 章后，你将具备以下能力：

- 在 Linux 命令行中自如操作
- 管理用户、权限、软件、网络
- 编写 Shell 脚本自动化日常工作
- 使用 GCC/Makefile 编译 C 程序
- 使用 GDB 调试、Git 管理代码
- 进行 ARM 交叉编译

这些能力是嵌入式 Linux 开发的基石。接下来，进入 imx-forge 项目继续学习：

- [入门路线图](../../tutorial/start/00_roadmap.md) —— 嵌入式 Linux 是什么？从哪里开始？
- [工具链安装](../../tutorial/start/01_start_from_toolchain.md) —— ARM GNU Toolchain 15.2
- [U-Boot 教程](../../tutorial/uboot/) —— Bootloader 基础与移植
- [内核教程](../../tutorial/kernel/) —— Linux 内核开发
- [驱动教程](../../tutorial/driver/) —— 编写你的第一个驱动
