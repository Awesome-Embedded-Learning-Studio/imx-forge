# 第 29 章  定时任务：crontab

> **Part 6 · 脚本与自动化**

---

## 引子

你写了一个脚本，每天凌晨自动备份代码。但你不打算每天凌晨爬起来手动执行。

cron 是 Linux 的闹钟。你告诉它「每天几点做什么」，它到点就帮你跑。不需要你在线，不需要你干预。服务器上的日志轮转、系统备份、定时清理，背后全是 cron。

crontab 的语法被称为「世界上最难记的五颗星」——五个占位符从左到右分别代表**分、时、日、月、周**。这个顺序没有任何道理可讲——你只能记住它。

但记住语法只是开始。cron 真正让人困惑的地方在于：你在终端里手动跑得好好的脚本，放进 crontab 之后就是不工作。不是语法错了，是环境不同——cron 执行任务时的环境和你登录后的 Shell 环境完全不是一回事。

本章要把这两件事都搞清楚：怎么写 cron 规则，以及为什么它「不按常理出牌」。

---

## 背景与动机

在嵌入式开发的日常中，有一类任务是需要定期执行的：

- 每天凌晨备份交叉编译工具链的输出
- 每小时同步开发板的系统时钟
- 每周清理一次临时构建目录
- 定时从服务器拉取最新的固件版本

这些任务有一个共同特征：**重复、可预测、不需要人工判断**。如果每次都手动执行，你会浪费大量时间在无意义的重复操作上——而重复恰恰是计算机最擅长的事情。

cron 就是 Linux 解决这个问题的标准工具。它从 Unix 的 V6 版本（1975 年）就存在了——将近五十年，几乎所有 Unix-like 系统都在用它。说它是「经过时间检验的」都是轻描淡写了。

但在嵌入式开发中，cron 的价值不只是自动执行任务。当你把开发板部署到现场后，你可能没法随时 SSH 上去手动操作——这时候定时任务就成了唯一能自动维护系统的方式。

---

## 概念层

### cron 的五颗星

cron 的核心是一条规则表达式，由五个字段组成：

```
分  时  日  月  周
*   *   *   *   *  命令
```

从左到右依次是：

| 字段 | 含义 | 取值范围 |
|------|------|----------|
| 分（minute） | 每小时的第几分钟 | 0–59 |
| 时（hour） | 每天的第几小时（24 小时制） | 0–23 |
| 日（day of month） | 每月的第几天 | 1–31 |
| 月（month） | 每年的第几月 | 1–12（或 jan–dec） |
| 周（day of week） | 每周的第几天 | 0–7（0 和 7 都是周日） |

`*` 代表「每一个」——`* * * * *` 的意思是「每分钟执行一次」。

这个语法可以类比为**一套极其精确的闹钟**——你可以设置「每天早上 3 点响」「每月 1 号和 15 号的 6 点响」「每周一到周五的 9 点响」。五颗星从左到右，粒度从细到粗：分钟最细，周最粗。

但「闹钟」这个比喻有一个关键的地方和真实情况不同：普通闹钟只会响铃提醒你，你可以选择无视它。cron 不是提醒你——它到点了会**直接执行命令**。不需要你在线，不需要你确认，甚至不需要你的终端开着。cron 守护进程（`crond`）在后台一直运行，到了匹配的时间点就自动触发。

这也意味着：如果命令写错了，它到点也会毫不犹豫地执行——包括那些你不想自动执行的命令。

### 特殊符号

五个字段不只是填数字和 `*`，还有几个特殊符号：

| 符号 | 含义 | 示例 | 说明 |
|------|------|------|------|
| `*` | 每个 | `* * * * *` | 每分钟 |
| `,` | 列表 | `0 9,12,18 * * *` | 每天 9:00、12:00、18:00 |
| `-` | 范围 | `0 9-17 * * 1-5` | 工作日每小时整点（9 点到 17 点） |
| `/` | 步长 | `*/15 * * * *` | 每 15 分钟 |

这些符号可以组合使用。比如：

```bash
# 每周一到周五，早上 9 点到下午 5 点，每隔 2 小时
0 9-17/2 * * 1-5 /home/user/scripts/build.sh
```

还有几个特殊字符串，是常见时间模式的简写：

| 字符串 | 等价表达式 | 含义 |
|--------|------------|------|
| `@yearly` | `0 0 1 1 *` | 每年 1 月 1 日 0 点 |
| `@monthly` | `0 0 1 * *` | 每月 1 日 0 点 |
| `@weekly` | `0 0 * * 0` | 每周日 0 点 |
| `@daily` | `0 0 * * *` | 每天 0 点 |
| `@hourly` | `0 * * * *` | 每小时整点 |
| `@reboot` | — | 每次系统启动后（不保证网络已就绪） |

### crontab 命令

`crontab` 是管理定时任务的命令：

| 命令 | 作用 |
|------|------|
| `crontab -e` | 编辑当前用户的定时任务 |
| `crontab -l` | 列出当前用户的所有定时任务 |
| `crontab -r` | 删除当前用户的**所有**定时任务 |
| `crontab -ri` | 交互式删除（逐条确认） |

`crontab -e` 第一次运行时会让你选择编辑器（和第 12 章的 `visudo` 类似），之后会用选定的编辑器打开一个临时文件，每行一条 cron 规则。

> ⚠️ **注意**
> `crontab -r` 会**不加任何确认地删除**你的全部定时任务。不是删一条，是删全部。
> 而且没有回收站，删了就是删了。
> `-r`（删除）和 `-e`（编辑）在键盘上紧挨着，按错了就是血泪教训。
> 如果你想安全地删除，用 `crontab -ri`，它会逐条问你确认。

### cron 的环境问题

这里才是 cron 真正「不按常理出牌」的地方。

你在终端里手动运行脚本，脚本能正常工作。你把完全一样的命令放进 crontab，脚本执行了——但结果不对。不是语法错误，不是权限问题，而是**环境变量不同**。

cron 执行任务时的环境和你的交互式 Shell 是不同的：

| 项目 | 交互式 Shell | cron 环境 |
|------|-------------|-----------|
| SHELL | `/bin/bash` | `/bin/sh`（Ubuntu 上是 dash） |
| PATH | `/usr/local/bin:/usr/bin:/bin:...`（很长） | `/usr/bin:/bin`（可能更少） |
| 环境变量 | 加载了 `.bashrc`、`.profile` 等 | 几乎什么都没加载 |

这里有两层含义。

第一层：cron 的默认 Shell 是 `/bin/sh`，在 Ubuntu 上这是 **dash**——不是 bash。dash 不支持 bash 的一些语法特性（比如 `[[ ]]`、数组），如果你的脚本用了这些特性但在 shebang 行写了 `#!/bin/bash`，那脚本本身没问题（因为 shebang 指定了 bash）；但如果你在 crontab 里直接写了一行 bash 语法，它会被 dash 执行，就会报错。

第二层：cron 的 PATH 非常短。Ubuntu 22.04 上（使用 Vixie cron），默认 PATH 通常只有 `/usr/bin:/bin`。Ubuntu 24.04 开始切换到 cronie，PATH 是 `/usr/bin:/bin:/usr/sbin:/sbin`——稍微好一点，但仍然比交互式 Shell 少得多。如果你的脚本里用了 `node`、`python3`、`docker` 这些不在这些路径下的命令，cron 就找不到它们。

回到那个闹钟的比喻：闹钟确实到点响了（cron 确实执行了你的命令），但它响在一个几乎空无一物的房间里——这个房间和你平时工作的房间不是同一个。你平时工作的房间里有工具箱、文件柜、便利贴（PATH、Shell 函数、环境变量），但闹钟响的那个房间只有最基本的一把锤子和一把螺丝刀（`/usr/bin:/bin`）。所以闹钟响了，但「该做的事」因为找不到合适的工具而没做完。

解决方法很简单：在 crontab 文件顶部手动设置环境变量：

```bash
# 在 crontab 文件顶部设置
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 每天凌晨 3 点执行备份脚本
0 3 * * * /home/user/scripts/backup.sh >> /home/user/logs/backup.log 2>&1
```

或者直接在命令里写完整路径：

```bash
0 3 * * * /usr/local/bin/python3 /home/user/scripts/backup.py
```

还有一个常见的坑：cron 任务的输出默认会通过邮件发送给用户。如果系统没配邮件服务（大多数开发环境都没配），输出就丢了——你连错误信息都看不到。所以好的习惯是**总是重定向输出**：

```bash
# 标准输出和错误都追加到日志文件
0 3 * * * /home/user/scripts/backup.sh >> /home/user/logs/backup.log 2>&1
```

---

## 实践层

### 4.1 写第一条 cron 规则

先看当前用户的定时任务：

```bash
$ crontab -l
# 预期输出（如果没有设置过）
no crontab for <你的用户名>
```

编辑 crontab：

```bash
$ crontab -e
# 第一次运行会让你选择编辑器
# 选 vim.basic 或 nano 都行
```

在打开的文件里加一条测试规则——每分钟往日志文件写一行时间戳：

```bash
* * * * * date >> /tmp/cron-test.log
```

保存退出。等一分钟左右，检查日志：

```bash
$ cat /tmp/cron-test.log
# 预期输出
Thu Jun 11 14:30:01 CST 2026
Thu Jun 11 14:31:01 CST 2026
```

每隔一分钟出现一行，说明 cron 在正常工作。

测试完了记得删掉这条规则。可以用 `crontab -e` 手动删除那一行，也可以直接：

```bash
$ crontab -r
# 这会删除当前用户的所有定时任务！
# 如果你还有其他重要的定时任务，用 crontab -e 手动删除指定行
```

### 4.2 实战：每天自动备份

写一个简单的备份脚本。假设你要每天凌晨 3 点备份项目目录：

```bash
#!/bin/bash
# 文件路径: ~/scripts/backup.sh

BACKUP_DIR="$HOME/backups"
SOURCE_DIR="$HOME/project"
DATE=$(date +%Y%m%d)
LOG_FILE="$HOME/logs/backup.log"

# 创建备份目录（如果不存在）
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# 打包备份
tar czf "${BACKUP_DIR}/project-${DATE}.tar.gz" \
    -C "$(dirname "$SOURCE_DIR")" \
    "$(basename "$SOURCE_DIR")" 2>> "$LOG_FILE"

# 检查上一条命令是否成功
if [ $? -eq 0 ]; then
    echo "[$(date)] Backup completed: project-${DATE}.tar.gz" >> "$LOG_FILE"
else
    echo "[$(date)] Backup FAILED!" >> "$LOG_FILE"
fi

# 只保留最近 7 天的备份
find "$BACKUP_DIR" -name "project-*.tar.gz" -mtime +7 -delete
```

这里有几个注意点：
- 所有路径都用 `$HOME` 而不是硬编码用户名——因为 cron 环境下 `~` 不一定能正确展开
- `tar` 的 `-C` 选项先切换到源目录的父目录，再打包，避免备份文件里包含绝对路径
- `find -mtime +7 -delete` 自动清理 7 天前的备份

给脚本加上执行权限：

```bash
$ chmod +x ~/scripts/backup.sh
```

手动跑一次确认脚本能工作：

```bash
$ ~/scripts/backup.sh
$ cat ~/logs/backup.log
# 预期输出
[Thu Jun 11 14:35:00 CST 2026] Backup completed: project-20260611.tar.gz
```

确认没问题后，加入 crontab：

```bash
$ crontab -e
```

在文件顶部加上环境变量，然后添加定时规则：

```bash
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 每天凌晨 3 点备份
0 3 * * * $HOME/scripts/backup.sh
```

输出已经由脚本内部重定向了，所以不需要在 crontab 里再加重定向。

验证 crontab 已生效：

```bash
$ crontab -l
# 预期输出
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 每天凌晨 3 点备份
0 3 * * * $HOME/scripts/backup.sh
```

### 4.3 systemd timer：cron 的现代替代

cron 已经存在了将近五十年，足够稳定，但也有一些设计上的局限：

- **精度只到分钟**：cron 最小粒度是一分钟，不能做「每 30 秒执行一次」
- **没有日志集成**：cron 任务的输出需要你自己管理重定向
- **没有依赖管理**：cron 不知道「网络准备好了没」「上个任务完成了吗」
- **系统重启后不补跑**：如果系统在计划时间关机了，那个任务就跳过了

**systemd timer** 是 systemd 提供的定时任务机制（第 20 章我们介绍过 systemd），它解决了上述大部分问题：

| 特性 | cron | systemd timer |
|------|------|---------------|
| 精度 | 分钟级 | 秒级（需设置 `AccuracySec=1s`） |
| 日志 | 需手动配置重定向 | 集成 `journalctl` |
| 依赖管理 | 无 | 可指定 `After=network-online.target` 等 |
| 错过补跑 | 不支持 | `Persistent=true` 可补跑上一次错过的 |
| 配置方式 | 一行 crontab 规则 | 需要两个文件（.timer + .service） |

创建一个 systemd timer 需要两个文件。以同样的每日备份为例：

**服务单元** `/etc/systemd/system/backup.service`：

```ini
[Unit]
Description=Daily project backup

[Service]
Type=oneshot
ExecStart=/home/user/scripts/backup.sh
```

**定时器单元** `/etc/systemd/system/backup.timer`：

```ini
[Unit]
Description=Run backup daily at 3am

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

启用定时器：

```bash
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now backup.timer
```

查看所有定时器：

```bash
$ systemctl list-timers
# 预期输出
NEXT                         LEFT     LAST          PASSED   UNIT           ACTIVATES
Fri 2026-06-12 03:00:00 CST  12h left Thu 03:00 CST  11h ago  backup.timer   backup.service
```

`OnCalendar` 的语法和 cron 不同，但更可读：`*-*-* 03:00:00` 表示「每年每月每日的 3 点 0 分 0 秒」。`Persistent=true` 的意思是：如果系统在 3 点时是关着的，开机后会补跑一次。

> ⚠️ **注意**
> `Persistent=true` 只会补跑**最近一次**错过的执行——不会把错过三天的任务连跑三遍。
> 这对备份来说通常是合理的，但如果你需要严格补跑每一次，
> 就需要考虑其他方案了。

对于简单的定时任务，cron 够用了——写一行规则就搞定。但如果你需要更精细的控制（依赖管理、错过补跑、日志集成），systemd timer 值得学习。

在 Ubuntu 22.04 和 24.04 上，cron 服务默认是安装并启用的：

```bash
$ systemctl status cron
# 预期输出（关键字段）
Active: active (running)
```

日常使用中，cron 和 systemd timer 可以共存——简单的用 cron，复杂的用 systemd timer。

---

## 练习题

cron 的语法需要练习才能真正记住。下面几道题从语法到实战递进，建议先不看提示独立想。

**练习 29.1** ⭐（理解）

写出以下 cron 表达式：

1. 每天早上 8:30 执行
2. 每周一到周五的下午 6:00 执行
3. 每月 1 号和 15 号的凌晨 2:00 执行

**练习 29.2** ⭐⭐（应用）

你的 crontab 里有一条任务每天凌晨执行，但今天你发现日志文件里已经三天没有新记录了。列出你可能需要排查的原因（至少三个）。

> **提示**：考虑 cron 服务本身是否在运行、脚本路径是不是用的完整路径、脚本里用到的命令在 cron 环境里能不能找到。

**练习 29.3** ⭐⭐⭐（思考）

cron 在系统关机期间错过了计划任务，不会自动补跑。systemd timer 的 `Persistent=true` 可以补跑。但「补跑」本身可能带来问题——请思考：在什么场景下，错过任务后**不补跑**反而是正确的行为？

> **提示**：考虑备份任务——如果系统关了三天，开机后一次性补跑，备份的是三天前的状态还是当前状态？再想想日志轮转（logrotate）——错过的日志轮转需要补吗？

---

## 本章回响

定时任务的本质，是把「什么时候做」这件事从人的记忆里卸载到系统里。你只需要设置一次，之后 cron 就会在每个指定的时间点忠实地执行——不管你在不在线。

cron 的五颗星从左到右是分、时、日、月、周——这个顺序确实没有直觉上的道理，但多写几遍就会变成肌肉记忆。真正需要警惕的不是语法，而是 cron 的运行环境：它不会加载你的 Shell 配置文件，默认 Shell 是 dash（不是 bash），PATH 可能只有 `/usr/bin:/bin`——你的脚本里用到的任何命令都得确认路径。这不是 cron 的 bug，这是它设计上的选择：一个最小化的执行环境，减少不确定性。但这个「最小化」恰恰是无数「我明明手动跑得好好的」的根源。

还记得开头说的吗——手动跑得好好的脚本，放进 crontab 就是不工作？现在你应该知道了，大概率不是脚本的错，而是环境变量的错。加上完整路径、重定向输出、在 crontab 顶部设置 `SHELL` 和 `PATH`——这三步能解决绝大多数 cron 的问题。

systemd timer 作为 cron 的现代替代，提供了秒级精度、日志集成和依赖管理。对于日常的简单定时任务，cron 足够了；但对于嵌入式设备部署后需要精确定时、错过补跑的场景，systemd timer 更合适。两者不冲突——根据场景选择。

下一章我们会深入 Shell 的环境变量体系——`PATH` 到底是怎么被设置的、`.bashrc` 和 `.profile` 的区别是什么、login shell 和 non-login shell 有什么不同。cron 的环境问题只是冰山一角，理解 Shell 的启动流程才是根本。

---

[← 上一章](ch28-function.md)
[下一章 →](ch30-envvar.md)
