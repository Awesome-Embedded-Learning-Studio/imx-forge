# RootFS Overlay 使用指南

## 前言：同一个 Rootfs，多种环境

做项目时经常会遇到这种场景：同一套代码，要适配不同环境。开发环境需要调试工具和日志，生产环境要精简和监控，测试环境可能又要别的配置。

刚开始做 IMX-Forge 的时候，我处理这种需求的办法是：**直接改 rootfs 里的文件，每次部署前手动替换**。这种办法工作了一段时间，但很快就暴露出问题——

- 忘记改配置就发布了，生产环境开着调试端口
- 不同环境的配置文件混杂在一起，不知道哪个是哪个
- 想回滚到之前的配置，发现已经被覆盖了

后来才知道，这不是我要面对的独特问题，而是嵌入式开发的普遍痛点。解决方案就是 **Overlay 模式**：把不同环境的定制内容分离存放，需要时合并到基础 rootfs 上。（这个借鉴了BuildRoot的玩法，这里权当拆看体验以下了~）

这一章，我们就来掌握 RootFS Overlay 的用法，让你能轻松管理多环境配置。

---

## Overlay 概念

### 为什么需要 Overlay

直接修改 rootfs 的问题很明显：

1. **不可逆**：修改后就找不回原版了，除非用 Git 回退
2. **难维护**：不同环境的配置混在一起，不知道哪些是基础配置、哪些是定制
3. **难复用**：同一套定制没法应用到不同的 rootfs 版本

Overlay 模式解决了这些问题：
- **基础 rootfs 保持不变**：所有修改都在 overlay 目录里
- **配置清晰分离**：每个环境一个 overlay 目录，一目了然
- **版本无关**：overlay 可以应用到任何版本的 rootfs 上（只要路径兼容）

---

### rootfs/overlay/ 目录结构

项目的 overlay 目录结构如下：

```bash
tree rootfs/overlay/
```

目前很简单：

```
rootfs/overlay/
└── .gitignore
```

`.gitignore` 的内容通常是：

```
*
!.gitignore
```

这表示 overlay 目录默认是空的，但保留目录结构。我们需要在这里创建自己的 overlay。

**预期的组织方式**：

```
rootfs/overlay/
├── rootfs/       # 基础 overlay（通用配置）
├── qt6/          # Qt6 环境 overlay
├── dev/          # 开发环境 overlay
└── prod/         # 生产环境 overlay
```

每个 overlay 子目录都模拟 rootfs 的结构，合并时会覆盖对应路径的文件。

---

### 合并机制：cp --remove-destination

`merge_overlay_rootfs.sh` 脚本的核心是用 `cp -a --remove-destination` 命令合并文件。

**命令解析**：

```bash
cp -a --remove-destination overlay/rootfs/* rootfs/nfs/
```

参数说明：
- `-a`：归档模式，保留权限、时间戳等元数据
- `--remove-destination`：目标文件存在时先删除再复制，而不是追加

**为什么用 --remove-destination**？

普通的 `cp` 命令在目标已存在时会尝试追加，可能导致权限或属性混乱。`--remove-destination` 确保 overlay 的文件完全替换目标，干净利落。

**踩坑经验**：有一次我用了普通的 `cp -r`，结果 overlay 里的软链接被展开成实际文件，导致 rootfs 体积暴增。用 `cp -a` 才能正确处理软链接。

---

## 使用 merge_overlay_rootfs.sh

### 基本用法

最简单的用法，使用默认设置（overlay/rootfs → rootfs/nfs）：

```bash
./scripts/merge_overlay_rootfs.sh
```

**执行输出**：

```
========================================
RootFS Overlay Merge
========================================
Overlay source: /home/charliechen/imx-forge/rootfs/overlay/rootfs
Target rootfs:  /home/charliechen/imx-forge/rootfs/nfs

Step 1: Safety checks...
  ✓ Target directory is safe

Step 2: Validating target rootfs...
  ✓ Target is a valid rootfs directory

Step 3: Checking overlay directory...
  ✗ Overlay directory is empty or missing

Error: No overlay content to merge.
```

这是正常的，因为我们的 overlay 目录还是空的。先创建一些内容再试。

---

### 指定目标 rootfs

如果你想合并到其他 rootfs，用 `--rootfs-dir` 参数：

```bash
# 合并到 out/release-latest/rootfs
./scripts/merge_overlay_rootfs.sh --rootfs-dir=out/release-latest/rootfs

# 合并到绝对路径
./scripts/merge_overlay_rootfs.sh --rootfs-dir=/tmp/myrootfs
```

---

### 指定 overlay 名称

用 `--overlay-name` 参数选择不同的 overlay：

```bash
# 使用 Qt6 overlay
./scripts/merge_overlay_rootfs.sh --overlay-name=qt6

# 使用开发环境 overlay
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

overlay 目录会变成 `rootfs/overlay/qt6/`，合并到目标 rootfs。

---

### 交互式确认流程

脚本在合并前会要求确认：

```
This will OVERWRITE files in /home/charliechen/imx-forge/rootfs/nfs with content from /home/charliechen/imx-forge/rootfs/overlay/rootfs
Press Ctrl+C to cancel, or Enter to continue...
```

这是一个安全机制，防止误操作。如果你确定要合并，按 Enter 继续；想取消就按 Ctrl+C。

---

### 安全检查机制

脚本内置了多重安全检查：

**1. 防止误操作根目录**

```bash
# 如果目标是 /，脚本会拒绝
./scripts/merge_overlay_rootfs.sh --rootfs-dir=/
```

输出：

```
Error: Target directory appears to be system root. Refusing to operate.
```

**2. 验证目标是否为有效 rootfs**

脚本会检查目标目录是否存在关键目录（`bin`、`sbin`、`usr`）：

```bash
# 如果目标不是 rootfs，会报错
./scripts/merge_overlay_rootfs.sh --rootfs-dir=/tmp
```

输出：

```
Error: Target does not appear to be a valid rootfs directory.
Missing required directories: bin, sbin, usr
```

**3. 检查 overlay 是否有内容**

空的 overlay 会被拒绝，避免无意义的操作：

```
Error: Overlay directory is empty or missing content.
```

这些检查能避免大部分误操作，但建议操作前还是备份一下 rootfs，以防万一。

---

## 创建自定义 Overlay

现在让我们实际创建几个 overlay，看看具体怎么做。

### 示例 1：添加网络配置

假设我们的开发板需要固定 IP 地址，我们创建一个 overlay 来添加网络配置。

**创建 overlay 目录结构**：

```bash
mkdir -p rootfs/overlay/dev/etc/network
```

**添加网络配置文件**：

```bash
cat > rootfs/overlay/dev/etc/network/interfaces << 'EOF'
# Loopback
auto lo
iface lo inet loopback

# Ethernet
auto eth0
iface eth0 inet static
    address 192.168.60.200
    netmask 255.255.255.0
    gateway 192.168.60.1
EOF
```

**添加主机名**：

```bash
mkdir -p rootfs/overlay/dev/etc
cat > rootfs/overlay/dev/etc/hostname << 'EOF'
imx6ull-dev
EOF
```

**合并 overlay**：

```bash
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

输出：

```
========================================
RootFS Overlay Merge
========================================
Overlay source: /home/charliechen/imx-forge/rootfs/overlay/dev
Target rootfs:  /home/charliechen/imx-forge/rootfs/nfs

Step 1: Safety checks...
  ✓ Target directory is safe

Step 2: Validating target rootfs...
  ✓ Target is a valid rootfs directory

Step 3: Checking overlay directory...
  ✓ Overlay directory exists with content
  Overlay contents:
    - etc/network/interfaces
    - etc/hostname

Press Ctrl+C to cancel, or Enter to continue...
```

按 Enter 确认，脚本会合并文件：

```
Step 4: Merging overlay...
  ✓ Merge complete: 2 directories, 2 files

========================================
Overlay merge completed successfully!
========================================
```

**验证合并结果**：

```bash
cat rootfs/nfs/etc/network/interfaces
cat rootfs/nfs/etc/hostname
```

你会看到 overlay 里的内容已经复制到 rootfs 了。

---

### 示例 2：添加系统服务和启动脚本

假设我们需要在系统启动时自动运行一个自定义程序。

**创建服务目录**：

```bash
mkdir -p rootfs/overlay/dev/etc/init.d
mkdir -p rootfs/overlay/dev/usr/bin
```

**添加启动脚本**：

```bash
cat > rootfs/overlay/dev/etc/init.d/myservice << 'EOF'
#!/bin/sh

case "$1" in
    start)
        echo "Starting my custom service..."
        /usr/bin/myapp --daemon
        ;;
    stop)
        echo "Stopping my custom service..."
        killall myapp
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
EOF

chmod +x rootfs/overlay/dev/etc/init.d/myservice
```

**修改 inittab 自动启动服务**：

```bash
mkdir -p rootfs/overlay/dev/etc
cat > rootfs/overlay/dev/etc/inittab << 'EOF'
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty -L 115200 ttymxc0 vt100
::askfirst:/bin/sh
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r

# Custom service
::respawn:/etc/init.d/myservice start
EOF
```

**合并 overlay**：

```bash
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

这样系统启动后会自动运行 `myservice`，如果服务崩溃还会自动重启（`respawn`）。

---

### 示例 3：添加调试工具（开发环境）

开发环境需要很多调试工具，而生产环境不需要。我们可以用 overlay 来区分。

**创建开发环境 overlay**：

```bash
mkdir -p rootfs/overlay/dev/root
mkdir -p rootfs/overlay/dev/usr/bin
```

**添加调试脚本**：

```bash
cat > rootfs/overlay/dev/usr/bin/dev-debug.sh << 'EOF'
#!/bin/sh
# 开发调试脚本

echo "=================================="
echo "Development Debug Information"
echo "=================================="
echo ""
echo "Uptime: $(uptime)"
echo ""
echo "Memory Usage:"
free -m
echo ""
echo "Disk Usage:"
df -h
echo ""
echo "Network Status:"
ifconfig -a
echo ""
echo "Process List:"
ps aux
echo "=================================="
EOF

chmod +x rootfs/overlay/dev/usr/bin/dev-debug.sh
```

**添加开发用配置文件**：

```bash
mkdir -p rootfs/overlay/dev/etc/profile.d
cat > rootfs/overlay/dev/etc/profile.d/dev-env.sh << 'EOF'
# 开发环境变量
export PS1="\u@imx6ull-dev:\w$ "
alias ll='ls -la'
alias logview='tail -f /var/log/syslog'
EOF
```

**合并开发环境 overlay**：

```bash
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

现在开发环境有了调试工具和友好的 Shell 提示符，而生产环境可以通过应用不同的 overlay 保持精简。

---

## 实际应用场景

### 场景 1：开发环境 vs 生产环境

这是最常见的场景，两个环境需要不同的配置。

**开发环境 overlay** (`rootfs/overlay/dev/`)：

```
dev/
├── etc/
│   ├── network/interfaces      # 静态 IP，方便调试
│   ├── inittab                 # 启用调试 shell
│   └── profile.d/
│       └── dev-env.sh          # 开发环境变量
├── usr/
│   └── bin/
│       ├── dev-debug.sh        # 调试脚本
│       └── strace              # 动态链接库
└── root/
    └── .ssh/authorized_keys    # SSH 公钥
```

**生产环境 overlay** (`rootfs/overlay/prod/`)：

```
prod/
├── etc/
│   ├── network/interfaces      # DHCP，自动获取 IP
│   ├── inittab                 # 禁用调试 shell
│   └── profile.d/
│       └── prod-env.sh         # 生产环境变量
└── usr/
    └── bin/
        └── health-check.sh     # 健康检查脚本
```

部署时选择对应的 overlay：

```bash
# 开发环境
./scripts/merge_overlay_rootfs.sh --overlay-name=dev

# 生产环境
./scripts/merge_overlay_rootfs.sh --overlay-name=prod
```

---

### 场景 2：Qt6 应用环境

如果你的系统需要运行 Qt6 应用，可以创建专门的 overlay。

**Qt6 overlay** (`rootfs/overlay/qt6/`)：

```
qt6/
├── etc/
│   └── profile.d/
│       └── qt6-env.sh          # Qt6 环境变量
├── usr/
│   └── lib/
│       └── qt6/                # Qt6 库文件
└── opt/
    └── my-qt-app/              # Qt6 应用程序
        ├── bin/
        ├── lib/
        └── resources/
```

**Qt6 环境变量脚本**：

```bash
cat > rootfs/overlay/qt6/etc/profile.d/qt6-env.sh << 'EOF'
#!/bin/sh
# Qt6 环境配置

export QT_QPA_PLATFORM=linuxfb
export QT_DEBUG_PLUGINS=1
export LD_LIBRARY_PATH=/opt/my-qt-app/lib:$LD_LIBRARY_PATH
EOF
```

**合并 Qt6 overlay**：

```bash
./scripts/merge_overlay_rootfs.sh --overlay-name=qt6
```

---

## 调试和验证

### 验证 Overlay 应用结果

合并完成后，最好验证一下是否正确应用。

**检查合并的文件**：

```bash
# 查看网络配置
cat rootfs/nfs/etc/network/interfaces

# 查看主机名
cat rootfs/nfs/etc/hostname

# 查看启动脚本
ls -la rootfs/nfs/etc/init.d/

# 验证文件权限
ls -la rootfs/nfs/usr/bin/
```

**对比 overlay 和 rootfs**：

```bash
# 比较配置文件
diff rootfs/overlay/dev/etc/network/interfaces rootfs/nfs/etc/network/interfaces
```

如果输出为空，说明文件完全一致；有差异会显示具体不同之处。

---

### 常见问题排查

**问题 1：合并后文件没有变化**

可能原因：
1. overlay 目录路径不对
2. 文件不在 overlay 的正确位置（比如 `overlay/dev/etc/file` 写成了 `overlay/etc/file`）
3. 目标 rootfs 路径不对

**解决方法**：

```bash
# 检查 overlay 内容
tree rootfs/overlay/dev/

# 检查目标路径
ls -la rootfs/nfs/etc/

# 重新合并，查看输出
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

**问题 2：软链接变成了实际文件**

可能原因：使用了 `cp -r` 而不是 `cp -a`。

**解决方法**：确保脚本使用 `cp -a` 命令：

```bash
cp -a --remove-destination overlay/dev/* rootfs/nfs/
```

**问题 3：权限丢失**

可能原因：overlay 里的文件权限不对，或者合并时用了错误的 `cp` 参数。

**解决方法**：

```bash
# 检查 overlay 文件权限
ls -la rootfs/overlay/dev/usr/bin/

# 设置正确的权限
chmod +x rootfs/overlay/dev/usr/bin/*.sh

# 重新合并
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

**问题 4：合并后 rootfs 损坏**

可能原因：overlay 里包含错误的内容，覆盖了关键文件。

**解决方法**：

```bash
# 从备份恢复 rootfs
rm -rf rootfs/nfs
cp -a backup/rootfs/ rootfs/nfs/

# 检查 overlay 内容
tree rootfs/overlay/dev/

# 修复 overlay 后重新合并
./scripts/merge_overlay_rootfs.sh --overlay-name=dev
```

**⚠️ 建议**：合并前先备份 rootfs：

```bash
cp -a rootfs/nfs/ rootfs/nfs.backup/
```

---

## 总结：Overlay 让 Rootfs 定制更简单

到这里，RootFS Overlay 的完整用法你应该已经掌握了。让我们回顾一下核心要点：

- **Overlay 分离配置**：不同环境的定制内容独立存放，互不干扰
- **合并机制简单**：`cp -a --remove-destination` 确保干净替换
- **安全检查完善**：脚本防止误操作，验证目标 rootfs 有效性
- **应用场景广泛**：开发/生产环境隔离、Qt6 应用、定制服务都能搞定
- **操作前先备份**：避免错误配置导致 rootfs 损坏

掌握了 Overlay，你就可以灵活管理多环境配置，而不用每次手动改文件、担心搞混环境。所有配置都是版本可控的，回滚也方便。

---

## 构建系统进阶教程完结

到这里，《构建系统进阶教程》的三章内容就全部完成了。我们学习了：

1. **[out/ 目录结构完全指南](./01_out_directory_structure.md)** —— 搞清楚构建产物的组织方式
2. **[Patch 工作流实战指南](./02_patch_workflow_practice.md)** —— 掌握补丁管理，安全修改底层代码
3. **[RootFS Overlay 使用指南](./03_rootfs_overlay_guide.md)** —— 灵活定制 Rootfs，适配多环境

这三套工具配合使用，你就能构建出既规范又灵活的嵌入式 Linux 系统。从构建产物管理、代码修改管理，到配置文件管理，全流程都有了最佳实践。

祝你折腾愉快！有问题随时回来看教程，或者提 issue 给我们反馈。
