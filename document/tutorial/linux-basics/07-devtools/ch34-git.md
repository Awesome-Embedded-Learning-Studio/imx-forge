# 第 34 章  Git 日常操作手册

> **Part: Part 7 · 开发工具链**

---

## 引子

你改了十几个文件，测试通过了，想保存当前状态。
一周后你发现改错了，想回到之前的版本——但你已经记不清改了哪些文件了。

这不是假设，这是每天都会发生的事。

Git 是时间机器。它记录你每一次修改，让你随时回到过去任何一个时刻。它让你开分支做实验，实验失败了直接扔掉，主线不受影响。

但 Git 有一个反直觉的设计：它记录的不是文件，而是**每一次修改的完整快照**。这不是同一个意思——"记录文件"意味着 Git 只关心最终状态，而"记录快照"意味着 Git 保留了完整的历史轨迹。每一个提交（commit）都是一个独立的时间点，包含了那个时刻项目的完整状态。

嵌入式开发离不开 Git——imx-forge 项目就托管在 Git 上。学会 Git 的日常操作，是你参与任何开源项目的第一步。

---

## 背景与动机

你可能用过一些"版本管理"的方式：把文件复制一份叫 `main_v2.c`，再复制一份叫 `main_final.c`，再复制一份叫 `main_final_really.c`。每个做过开发的人都被这个方法折磨过。

Git 解决的核心问题只有一个：**让你不用怕改代码**。

没有版本控制的时候，你每次改代码之前都会犹豫——万一改坏了怎么办？这种恐惧感会拖慢你的开发速度。有了 Git，你可以放心大胆地改：改坏了？一条命令回到上一个状态。想实验一个新方案？开一个分支随便折腾，失败了删掉就行，主线完全不受影响。

在嵌入式开发中，Git 的价值更加突出：

- 驱动代码需要频繁调试和迭代，每次改动都应该有记录
- 设备树文件的配置项很多，改乱了需要能回退
- imx-forge 这样的开源项目通过 Git 协作，你需要会 clone、pull、push
- 编译环境和工具链的配置脚本也需要版本管理

---

## 概念层

### 三层模型——类比第一次：建立映射

Git 的设计里有一个让新手最容易困惑的概念：**工作区、暂存区、仓库**。你可以把它想象成游戏的存档系统。

工作区（Working Directory）就是你正在玩的关卡——文件就在那里，你随时可以改。改了就是改了，不存档的话关机就没了。

暂存区（Staging Area）是存档前的确认界面——你选择"这一局我想保存哪些操作"。不是所有操作都值得存档——你可能改了十个文件，但只想保存其中三个的改动。

仓库（Repository）是存档文件——按了确认键之后，选中的操作被永久写入存档。每一个存档点都是一个独立的快照，不会覆盖之前的版本。

每次 `git add`，你是在告诉 Git"这个改动我想存档"。每次 `git commit`，你是在按下确认键，把暂存区的内容永久写入仓库。如果你改了文件但没有 `git add`，那这些改动就像打了但没存的游戏进度——Git 不会帮你记入版本历史。

但"游戏存档"这个比喻有一个关键失真：游戏存档通常只存一个状态（覆盖写），后来的存档会覆盖前面的。而 Git 的每次 commit 都是一个**独立完整的项目快照**，永远不会覆盖之前的版本。你的仓库里存的不只是"最新状态"，而是一条完整的时间线——你可以回到任何一个历史节点。

### 初始化和第一次提交

```bash
# 创建项目目录并初始化 Git 仓库
$ mkdir ~/my-driver && cd ~/my-driver
$ git init
# 预期输出
hint: Using 'master' as the name for the initial branch.
Initialized empty Git repository in /home/charlie/my-driver/.git/
```

到这里有一个细节需要注意。

> **关于默认分支名**
>
> `git init` 在 Ubuntu 22.04/24.04 上默认分支名仍然是 `master`。虽然 GitHub 等平台从 2020 年开始默认使用 `main`，但 Git 本身（哪怕是 Ubuntu 24.04 上的 Git 2.43）默认还是 `master`。
>
> 从 Git 2.28 开始，你可以通过配置修改默认分支名：
>
> ```bash
> $ git config --global init.defaultBranch main
> ```
>
> 或者单次初始化时指定：
>
> ```bash
> $ git init --initial-branch=main
> # 或简写
> $ git init -b main
> ```
>
> 以下教程中我们使用 `main` 作为主分支名，和主流平台保持一致。

现在我们有了一个空的 Git 仓库。创建一个文件并做第一次提交：

```bash
$ cat > README.md << 'EOF'
# My Driver Project

A simple Linux driver project.
EOF

# 查看状态
$ git status
# 预期输出
On branch master
No commits yet
Untracked files:
  README.md

nothing added to commit but untracked files present
```

`Untracked files` 意味着 Git 知道这个文件存在，但还没有被纳入版本管理。它现在处于工作区，既不在暂存区也不在仓库里。

```bash
# 添加到暂存区
$ git add README.md

# 再次查看状态
$ git status
# 预期输出
On branch master
No commits yet
Changes to be committed:
  new file:   README.md
```

状态变了——`README.md` 现在是 `Changes to be committed`，意味着它从工作区进入了暂存区，等待被提交。

```bash
# 提交到仓库
$ git commit -m "Initial commit: add README"
# 预期输出
[master (root-commit) a1b2c3d] Initial commit: add README
 1 file changed, 3 insertions(+)
 create mode 100644 README.md
```

到这一步，你的第一个快照已经永久保存在 Git 仓库里了。

**配置用户信息**

如果这是你第一次用 Git，commit 之前需要告诉 Git 你是谁：

```bash
$ git config --global user.name "Your Name"
$ git config --global user.email "your.email@example.com"
```

这两条命令只需要执行一次。Git 会把配置保存在 `~/.gitconfig` 里，以后所有仓库都会使用这个身份信息。

### 查看历史——git log

```bash
$ git log
# 预期输出
commit a1b2c3d4e5f6789012345678901234567890abcd (HEAD -> master)
Author: Your Name <your.email@example.com>
Date:   Thu Jun 11 10:00:00 2026 +0800

    Initial commit: add README
```

`git log` 显示提交历史。每一次提交都有一个唯一的哈希值（`a1b2c3d...`），作者信息，时间，和提交消息。`HEAD -> master` 表示你当前在 `master` 分支上，指向这个提交。

`git log` 的输出可能会很长。几个常用的简化选项：

```bash
# 单行显示（最常用）
$ git log --oneline
a1b2c3d Initial commit: add README

# 图形化显示分支结构
$ git log --oneline --graph

# 查看最近 3 条
$ git log --oneline -3
```

`--oneline` 是日常最高频的选项，每个提交压缩成一行，一目了然。

### 查看差异——git diff

`git diff` 是你检查"到底改了什么"的工具。它比较的对象取决于你的文件处于三层模型的哪个位置：

```bash
# 修改 README
$ echo "## Features" >> README.md
$ echo "- Basic driver framework" >> README.md

# 查看工作区和暂存区的差异
$ git diff
# 预期输出
diff --git a/README.md b/README.md
index 3b18e51..e69de29 100644
--- a/README.md
+++ b/README.md
@@ -2,3 +2,5 @@

 A simple Linux driver project.
+## Features
+- Basic driver framework
```

`git diff`（不带参数）比较的是**工作区和暂存区**的差异——也就是你改了但还没 `git add` 的内容。

```bash
# 添加到暂存区后
$ git add README.md
$ git diff --cached
# 预期输出（同样的内容，但现在比较的是暂存区和最近提交的差异）
```

`git diff --cached`（或 `git diff --staged`）比较的是**暂存区和最近一次提交**的差异——也就是你 `git add` 了但还没 `git commit` 的内容。

一个实用的记忆方式：

| 命令 | 比较对象 | 你在问什么 |
|---|---|---|
| `git diff` | 工作区 vs 暂存区 | "我改了什么还没 add？" |
| `git diff --cached` | 暂存区 vs 仓库 | "我 add 了什么还没 commit？" |
| `git diff HEAD` | 工作区 vs 仓库 | "从上次 commit 到现在我改了什么？" |

### 分支——平行时间线

分支是 Git 最强大的功能之一。你可以把分支理解为平行宇宙——在某个时间点分叉出去，两条时间线各自独立发展，互不干扰。

为什么需要分支？假设你正在开发一个 LED 驱动，但突然发现之前的按键驱动有一个 bug 需要紧急修复。两种选择：

1. 在 `main` 分支上直接改——但你的 LED 驱动还没写完，代码可能编译不过，改完 bug 想提交都不行
2. 开一个 `fix/button-bug` 分支，在分支上修复 bug，修好了合并回 `main`——LED 驱动的开发不受任何影响

分支让这两种工作可以并行推进。

```bash
# 创建并切换到新分支
$ git checkout -b feature/led-driver
# 预期输出
Switched to a new branch 'feature/led-driver'

# 或者用新语法（Git 2.23+，语义更清晰）
$ git switch -c feature/led-driver
```

`git switch` 是 2019 年引入的新命令，专门用来切换分支。`git checkout` 功能太杂（既能切分支又能恢复文件），所以 Git 团队把它拆成了 `git switch`（切分支）和 `git restore`（恢复文件）。两个命令都能用，新语法更不容易犯错。

```bash
# 查看所有分支
$ git branch
# 预期输出
  main
* feature/led-driver    # * 表示当前分支

# 切换回主分支
$ git switch main
```

Git 的分支极其轻量——创建分支只是在 `.git/refs/` 下创建一个 41 字节的文件，指向某个提交。不管你的项目有多大，创建分支都是瞬间完成的。这和很多传统版本控制系统（比如 SVN）完全不同，后者的分支是完整的目录拷贝。

### 合并——时间线收敛

当你在分支上的工作完成了，需要把它合并回主线：

```bash
# 确保 main 是最新的
$ git switch main

# 合并 feature 分支
$ git merge feature/led-driver
# 预期输出（如果没冲突）
Merge made by the 'ort' strategy.
 led.c | 45 ++++++++++++++
 led.h | 12 +++++
 2 files changed, 57 insertions(+)
 create mode 100644 led.c
 create mode 100644 led.h
```

合并成功后，`feature/led-driver` 分支的改动就进入了 `main`。这个分支的历史使命完成了，可以删掉：

```bash
$ git branch -d feature/led-driver
```

#### merge 和 rebase 的区别

合并分支有两种方式：`git merge` 和 `git rebase`。它们在历史记录上的形态完全不同。

`git merge` 会创建一个**合并提交**（merge commit），保留完整的分支历史——你能看到"这里分叉了，然后又合回来了"。历史是**非线性**的。

`git rebase` 把分支上的提交"重新播放"到目标分支的最新位置，让历史变成**一条直线**。看起来更干净，但会**重写提交的哈希值**——因为每个提交的父提交变了，哈希必须重新计算。

简单原则：**在本地自己的分支上可以用 rebase 保持历史整洁，但永远不要对已经推送到远程的共享分支使用 rebase**。因为重写历史会让别人的本地仓库和远程产生冲突——他们的提交是基于旧哈希的，你把历史重写了，他们就找不到北了。

### 远程仓库——协作基础

到目前为止，你的 Git 仓库只存在于本地。要和别人协作，你需要一个远程仓库——GitHub、GitLab、Gitee 都行。

```bash
# 克隆远程仓库
$ git clone https://github.com/username/project.git
# 预期输出
Cloning into 'project'...
remote: Enumerating objects: 42, done.
Receiving objects: 100% (42/42), done.

# 查看远程仓库信息
$ git remote -v
origin  https://github.com/username/project.git (fetch)
origin  https://github.com/username/project.git (push)
```

`origin` 是远程仓库的默认别名。`fetch` 和 `push` 分别是拉取和推送的地址。

```bash
# 从远程拉取最新更新
$ git pull origin main
# 预期输出（如果有新提交）
Updating a1b2c3d..f5e6d7c
Fast-forward
 new_file.txt | 2 ++
 1 file changed, 2 insertions(+)

# 推送本地提交到远程
$ git push origin main
```

`git pull` 实际上是 `git fetch` + `git merge` 的组合——先从远程下载新提交，然后合并到你的当前分支。大多数时候用 `pull` 就够了，但如果你想先看看远程有什么更新再决定是否合并，可以先 `git fetch` 再手动 `git merge`。

### .gitignore——不追踪哪些文件

不是所有文件都应该被 Git 管理。编译产物、临时文件、工具链——这些文件要么每次都会重新生成，要么体积太大不适合放进仓库。

Git 用 `.gitignore` 文件来指定哪些文件不需要追踪。对于嵌入式项目，一个典型的 `.gitignore` 长这样：

```bash
$ cat > .gitignore << 'EOF'
# 编译产物
*.o
*.ko
*.elf
*.bin
*.hex
*.map

# 可执行文件
myapp
*.out

# 工具链和镜像（太大，不适合 Git 管理）
toolchain/
images/*.img

# IDE 和编辑器文件
.vscode/
.idea/
*.swp

# 系统文件
.DS_Store
Thumbs.db
EOF
```

嵌入式项目的 `.gitignore` 特别重要，因为编译产物（`.o`、`.bin`、`.elf`）和工具链动辄几十 MB 甚至几个 GB，放进 Git 仓库会让仓库体积暴涨。而像 `toolchain/` 这种目录，每个开发者可能安装在不同的位置，不应该纳入版本管理。

`.gitignore` 本身也需要被 Git 管理：

```bash
$ git add .gitignore
$ git commit -m "Add .gitignore for embedded project"
```

### 冲突解决

当两个人同时修改了同一个文件的同一个位置，合并时就会产生冲突。这不是错误，是 Git 在告诉你"我不知道该用谁的版本，你来决定"。

```bash
$ git merge feature/conflicting-change
# 预期输出
CONFLICT (content): Merge conflict in driver.c
Automatic merge failed; fix conflicts and then commit the result.
```

打开冲突文件，你会看到这样的标记：

```
<<<<<<< HEAD
int led_brightness = 100;  // 你的版本
=======
int led_brightness = 50;   // 对方的版本
>>>>>>> feature/conflicting-change
```

解决冲突的步骤：

1. 手动编辑文件，决定保留哪个版本（或者写一个合并后的新版本）
2. 删除冲突标记（`<<<<<<<`、`=======`、`>>>>>>>`）
3. `git add` 标记为已解决
4. `git commit` 完成合并

```bash
# 编辑解决冲突后
$ git add driver.c
$ git commit -m "Merge: resolve led_brightness conflict"
```

冲突不可怕——它只是 Git 在说"我需要你做决定"。可怕的是不知道怎么解决。

### 类比第三次——回收验证

回到游戏存档的类比。你现在应该能看清三层模型和各个操作之间的对应关系了：

- **`git add`** 是在存档确认界面勾选"要保存哪些进度"——你可以选择只保存部分改动
- **`git commit`** 是按下确认键——勾选的内容被永久写入存档文件
- **`git branch`** 是开一条新的平行游戏线路——在这条线路上随便折腾，不影响主线进度
- **`git merge`** 是把两条线路的成果合并——如果改了同一个地方，就需要你手动裁决
- **`git push`** 是把存档上传到云端——别人可以下载你的进度继续玩

还记得开头说的吗——Git 记录的不是文件，而是每一次修改的完整快照。这个设计决定了 Git 的几乎所有行为：分支很轻量（只是一个指向某个快照的指针），切换分支很快（只需要恢复对应快照的文件状态），合并和回退都很容易（因为每个快照都是自包含的）。三层模型——工作区、暂存区、仓库——是数据在"未保存→待确认→已存档"之间的流转过程。理解了这个流转，Git 的命令就都不神秘了。

---

## 实践层

### 4.1 从零搭建 Git 仓库

**初始化并配置**

```bash
$ mkdir ~/led-driver && cd ~/led-driver

# 配置 Git 用户信息（如果还没配过）
$ git config --global user.name "Your Name"
$ git config --global user.email "your.email@example.com"

# 设置默认分支名为 main（和 GitHub 保持一致）
$ git config --global init.defaultBranch main

# 初始化仓库
$ git init -b main
# 预期输出
Initialized empty Git repository in /home/charlie/led-driver/.git/
```

**创建项目文件**

```bash
$ cat > led.c << 'EOF'
#include <stdio.h>

void led_on(int id) {
    printf("LED %d: ON\n", id);
}

void led_off(int id) {
    printf("LED %d: OFF\n", id);
}
EOF

$ cat > Makefile << 'EOF'
CC = gcc
CFLAGS = -Wall

led-test: led.c
	$(CC) $(CFLAGS) led.c -o led-test

clean:
	rm -f led-test
.PHONY: clean
EOF

$ cat > .gitignore << 'EOF'
*.o
led-test
EOF
```

**第一次提交**

```bash
$ git add led.c Makefile .gitignore
$ git status
# 预期输出
On branch main
No commits yet
Changes to be committed:
  new file:   .gitignore
  new file:   Makefile
  new file:   led.c

$ git commit -m "Initial commit: LED driver with Makefile"
# 预期输出
[main (root-commit) b1c2d3e] Initial commit: LED driver with Makefile
 3 files changed, 28 insertions(+)
 create mode 100644 .gitignore
 create mode 100644 Makefile
 create mode 100644 led.c
```

### 4.2 分支工作流——功能开发实战

**创建功能分支**

```bash
$ git switch -c feature/blink
# 预期输出
Switched to a new branch 'feature/blink'
```

在分支上开发新功能：

```bash
$ cat >> led.c << 'EOF'

void led_blink(int id, int times) {
    for (int i = 0; i < times; i++) {
        led_on(id);
        led_off(id);
    }
}
EOF

$ git add led.c
$ git commit -m "Add led_blink function"
```

**回到主线修复 bug**

```bash
$ git switch main

# 修改 Makefile：加 -Wextra
$ sed -i 's/CFLAGS = -Wall/CFLAGS = -Wall -Wextra/' Makefile
$ git add Makefile
$ git commit -m "Fix: add -Wextra to catch more warnings"
```

**把功能分支合并回来**

```bash
$ git merge feature/blink
# 预期输出（Fast-forward，因为 main 上只有一个新提交且不冲突）
Updating b1c2d3e..c4d5e6f
Fast-forward
 led.c | 6 ++++++
 1 file changed, 6 insertions(+)

# 删除已合并的分支
$ git branch -d feature/blink
```

`Fast-forward` 意味着 Git 直接把 `main` 指针移到了 `feature/blink` 的最新提交——不需要创建合并提交，因为 `main` 上没有分叉。

### 4.3 连接远程仓库——以 GitHub 为例

**关联远程仓库**

```bash
# 在 GitHub 上创建好仓库后，添加远程地址
$ git remote add origin https://github.com/username/led-driver.git

# 验证
$ git remote -v
# 预期输出
origin  https://github.com/username/led-driver.git (fetch)
origin  https://github.com/username/led-driver.git (push)
```

**推送代码**

```bash
# 首次推送，设置上游分支
$ git push -u origin main
# 预期输出
Branch 'main' set up to track remote branch 'main' from 'origin'.
To https://github.com/username/led-driver.git
 * [new branch]      main -> main
```

`-u`（`--set-upstream`）让 Git 记住本地 `main` 分支对应远程的 `origin/main`。以后只需要 `git push` 和 `git pull` 就行，不用每次都写远程名和分支名。

**协作——拉取别人的更新**

```bash
$ git pull
# 预期输出（如果远程有新提交）
Updating b1c2d3e..e4f5a6b
Fast-forward
 README.md | 5 +++++
 1 file changed, 5 insertions(+)
```

### 4.4 冲突解决实战

制造一个冲突，体验一下完整流程：

```bash
# 创建分支并修改 led.c
$ git switch -c feature/conflict
$ sed -i 's/LED %d: ON/LED %d: ON (v2)/' led.c
$ git add led.c
$ git commit -m "Change LED ON message to v2"

# 回到 main，修改同一个位置
$ git switch main
$ sed -i 's/LED %d: ON/LED %d: turned on/' led.c
$ git add led.c
$ git commit -m "Change LED ON message to 'turned on'"

# 合并——冲突来了
$ git merge feature/conflict
# 预期输出
CONFLICT (content): Merge conflict in led.c
Automatic merge failed; fix conflicts and then commit the result.
```

查看冲突内容：

```bash
$ cat led.c
# 预期输出（冲突标记）
...
<<<<<<< HEAD
    printf("LED %d: turned on\n", id);
=======
    printf("LED %d: ON (v2)\n", id);
>>>>>>> feature/conflict
...
```

`<<<<<<< HEAD` 到 `=======` 之间是你当前分支（`main`）的版本，`=======` 到 `>>>>>>> feature/conflict` 之间是被合并分支的版本。

解决：保留更清晰的 v2 版本：

```bash
# 手动编辑 led.c，将冲突部分改为：
#     printf("LED %d: ON (v2)\n", id);

$ git add led.c
$ git commit -m "Merge: resolve LED message conflict, keep v2 format"
# 预期输出
[main f5e6d7c] Merge: resolve LED message conflict, keep v2 format
```

冲突解决完毕。整个过程就是这样——不是什么可怕的事情，Git 把选择权交给了你。

---

## 练习题

走到这里，Git 的日常操作应该上手了。下面几道题帮你巩固——第二题和第三题需要你动脑筋。

**练习 34.1** ⭐（理解）

解释工作区、暂存区、仓库三层模型。`git add` 和 `git commit` 分别在哪两层之间移动数据？如果一个文件被修改了但没有 `git add`，`git commit` 会把它纳入提交吗？

**练习 34.2** ⭐⭐（应用）

你正在 `feature/i2c` 分支上开发 I2C 驱动，写到一半突然发现 `main` 分支上有一个紧急 bug。请写出完整的命令序列：暂存当前工作 → 切换到 main → 修复 bug 并提交 → 推送到远程 → 切回 feature/i2c 继续开发。

> **提示**：当前工作还没做完不想提交，用什么命令可以临时保存？查一下 `git stash`。

**练习 34.3** ⭐⭐⭐（思考）

`git merge` 和 `git rebase` 都能把分支的改动合并到主线上。但很多团队规定"不要对已推送到远程的分支使用 rebase"。为什么？如果你 rebase 了一个别人已经基于它开发的新提交的分支，会发生什么？

> **提示**：rebase 重写了提交的哈希值。而 Git 用哈希值来标识提交。如果哈希变了，基于旧哈希的提交会怎样？

---

## 本章回响

本章真正在做的事情，是建立 Git 的**三层模型和快照式存储**这两个核心认知。

工作区是你看到的文件，暂存区是你选择要保存的改动，仓库是所有历史快照的集合。每一次 `git commit` 都在仓库里创建一个独立的时间点，包含项目在那个时刻的完整状态——这就是为什么 Git 能让你"回到过去"。数据在三层之间的流转构成了 Git 日常操作的基本模型：`git add` 从工作区搬到暂存区，`git commit` 从暂存区搬到仓库，`git push` 从本地仓库搬到远程仓库。

还记得开头说的吗——Git 记录的不是文件，而是每一次修改的完整快照？这个设计决定了 Git 的几乎所有行为。分支很轻量（只是一个指向某个快照的指针），切换分支很快（只需要恢复对应快照的文件状态），合并和回退都很容易（因为每个快照都是自包含的）。Git 的所有命令——不管看起来多复杂——本质上都是在操作这三层之间的数据流。

分支和合并是协作的核心。分支让你可以并行工作，合并让并行的工作汇合。冲突不可怕——它只是 Git 在说"这里有歧义，你来决定"。`.gitignore` 是嵌入式项目的标配——编译产物和工具链不应该进仓库。

下一章是整个专栏的终点站——交叉编译与 imx-forge 衔接。你将把前 34 章学到的所有技能汇聚在一起：用 Git 拉取 imx-forge 仓库，用 Makefile 编译项目，用 SSH 连接开发板，用 tftp 传输固件。所有工具在这一刻合流。

---

[← 上一章](ch33-binutils.md)
[下一章 →](ch35-crosscompile.md)
