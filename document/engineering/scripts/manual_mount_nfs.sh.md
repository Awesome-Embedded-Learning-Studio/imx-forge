# manual_mount_nfs.sh - 手动 NFS 挂载辅助脚本

## 脚本概述

`manual_mount_nfs.sh` 是 IMX-Forge 项目的 NFS 挂载辅助脚本。它提供了一种快速方式将构建的 rootfs 挂载到 NFS 目录，方便内核访问。

### 核心功能

- **快速挂载**：一键挂载 rootfs 到 NFS 目录
- **安全检查**：防止误操作挂载到系统关键目录
- **rootfs 验证**：验证目录是否为有效的 rootfs
- **懒卸载支持**：支持懒卸载（lazy unmount）处理忙状态
- **目录验证**：检查源目录和目标目录的有效性

### 设计理念

这个脚本的设计目标是简化开发过程中频繁的 rootfs 挂载操作，同时确保操作的安全性。

### 依赖关系

```
manual_mount_nfs.sh
    ├─ scripts/lib/bash/lib_common.sh (日志库)
    └─ mount (系统命令)
```

## 参数说明

### 命令语法

```bash
sudo ./scripts/manual_mount_nfs.sh [选项]
```

### 选项列表

| 选项 | 说明 |
|------|------|
| `--unmount, -u` | 卸载而不是挂载 |
| `--lazy-unmount` | 懒卸载（立即分离，稍后清理） |
| `--source=PATH` | 自定义源目录（默认：`out/release-latest/rootfs`） |
| `--target=PATH` | 自定义目标目录（默认：`rootfs/nfs`） |
| `--debug` | 启用调试输出 |
| `--help, -h` | 显示帮助信息 |

### 默认配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `DEFAULT_SOURCE_DIR` | `out/release-latest/rootfs` | 源 rootfs 目录 |
| `DEFAULT_TARGET_DIR` | `rootfs/nfs` | 目标 NFS 目录 |

## 执行流程

### 挂载流程

```
┌─────────────────────────────────────────────────────────────┐
│  权限检查                                                    │
│  - 检查是否以 root 权限运行                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  源目录验证                                                  │
│  - 检查源目录是否存在                                       │
│  - 安全性检查（不能是 /）                                    │
│  - 验证是否为有效 rootfs（包含 bin, sbin, usr）              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  目标目录检查                                                │
│  - 检查是否已挂载                                           │
│  - 验证目标目录安全性                                       │
│  - 如不存在则创建                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  执行挂载                                                    │
│  - 使用 mount --bind 绑定挂载                               │
│  - 验证挂载成功                                             │
└─────────────────────────────────────────────────────────────┘
```

### 卸载流程

```
┌─────────────────────────────────────────────────────────────┐
│  权限检查                                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  目标目录验证                                                │
│  - 检查目录是否存在                                         │
│  - 检查是否为挂载点                                         │
│  - 安全性检查                                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  执行卸载                                                    │
│  - 普通卸载：umount                                         │
│  - 懒卸载：umount -l                                         │
└─────────────────────────────────────────────────────────────┘
```

## 使用示例

### 基本挂载

```bash
# 使用默认目录挂载
sudo ./scripts/manual_mount_nfs.sh
```

**输出示例**：

```
========================================
Manual NFS Mount Helper
========================================

Source directory: /home/user/imx-forge/out/release-latest/rootfs
Target directory: /home/user/imx-forge/rootfs/nfs

  Source directory is safe
  Target directory is safe

Mounting: /home/user/imx-forge/out/release-latest/rootfs -> /home/user/imx-forge/rootfs/nfs
[CMD] mount --bind /home/user/imx-forge/out/release-latest/rootfs /home/user/imx-forge/rootfs/nfs
✓ Successfully mounted
Verify with: mount | grep nfs

========================================
✓ Operation completed successfully!
========================================
```

### 基本卸载

```bash
# 普通卸载
sudo ./scripts/manual_mount_nfs.sh --unmount
```

**输出示例**：

```
========================================
Manual NFS Mount Helper
========================================

Target directory: /home/user/imx-forge/rootfs/nfs

  Target directory is safe

Unmounting: /home/user/imx-forge/rootfs/nfs
[CMD] umount /home/user/imx-forge/rootfs/nfs
✓ Successfully unmounted

========================================
✓ Operation completed successfully!
========================================
```

### 懒卸载

```bash
# 当目标忙碌时使用懒卸载
sudo ./scripts/manual_mount_nfs.sh --unmount --lazy-unmount
```

**输出示例**：

```
========================================
Manual NFS Mount Helper
========================================

Target directory: /home/user/imx-forge/rootfs/nfs

  Target directory is safe

Lazy unmounting: /home/user/imx-forge/rootfs/nfs
This will detach immediately and clean up when not busy
[CMD] umount -l /home/user/imx-forge/rootfs/nfs
✓ Successfully lazy unmounted
The filesystem will be cleaned up when no longer in use

========================================
✓ Operation completed successfully!
========================================
```

### 自定义目录

```bash
# 指定源和目标目录
sudo ./scripts/manual_mount_nfs.sh --source=/tmp/my_rootfs --target=rootfs/custom-nfs
```

### 启用调试

```bash
# 查看详细的执行过程
sudo ./scripts/manual_mount_nfs.sh --debug
```

## 安全检查

### 目录安全验证

脚本会对目录进行多层安全检查：

```bash
check_directory_safe() {
    local dir="$1"
    local dir_name="${2:-directory}"

    # 不能是 /
    if [[ "$dir" == "/" ]]; then
        log_error "The $dir_name cannot be '/'"
        return 1
    fi

    # 必须是可访问的绝对路径
    local abs_dir
    if ! abs_dir=$(cd "$dir" 2>/dev/null && pwd); then
        log_error "Cannot access $dir_name: $dir"
        return 1
    fi

    # 解析后不能是 /
    if [[ "$abs_dir" == "/" ]]; then
        log_error "The $dir_name resolves to '/' (unsafe)"
        return 1
    fi

    return 0
}
```

### rootfs 有效性检查

```bash
check_valid_rootfs() {
    local rootfs="$1"
    local missing=()

    # 检查必需的目录
    for dir in "bin" "sbin" "usr"; do
        if [[ -d "${rootfs}/${dir}" ]]; then
            found+=("$dir")
        else
            missing+=("$dir")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Parent directory does not appear to be a valid rootfs"
        log_error "Missing required directories: ${missing[*]}"
        return 1
    fi

    return 0
}
```

## 故障排除

### 常见错误

#### 错误 1：非 root 用户运行

```
[ERROR] This script must be run as root (sudo)

Please run with sudo:
  sudo ./scripts/manual_mount_nfs.sh
```

**解决方法**：使用 `sudo` 运行脚本。

#### 错误 2：目标已挂载

```
[WARN] Target is already a mount point: rootfs/nfs
[INFO] Use '--unmount' to unmount first
```

**解决方法**：

1. 先卸载：`sudo ./scripts/manual_mount_nfs.sh --unmount`
2. 然后再挂载

#### 错误 3：目标忙碌

```
[ERROR] Unmount failed
[WARN] The target might be busy. Try with --lazy-unmount
[WARN] Or check with: sudo lsof +D rootfs/nfs
```

**解决方法**：

1. 查找占用进程：`sudo lsof +D rootfs/nfs`
2. 停止占用进程后重试
3. 或使用懒卸载：`--lazy-unmount`

#### 错误 4：无效的 rootfs

```
[ERROR] Parent directory does not appear to be a valid rootfs
[ERROR] Missing required directories: bin, sbin, usr
[ERROR] Please ensure parent has at least: bin, sbin, usr
```

**解决方法**：

确保源目录是有效的 rootfs，包含必要的目录结构。

#### 错误 5：不安全的目录路径

```
[ERROR] The source directory cannot be '/'
[ERROR] Source directory validation failed
```

**解决方法**：

不要使用 `/` 作为源或目标目录。

## 设计说明

### 为什么使用 bind mount

Bind mount（绑定挂载）允许将一个目录挂载到另一个位置，而不是挂载整个文件系统。这对于：

1. 开发过程中快速共享文件
2. 不需要修改 `/etc/fstab`
3. 可以随时卸载

### 为什么需要懒卸载

当目标目录被进程占用时，普通 `umount` 会失败。懒卸载 (`umount -l`)：

1. 立即从文件系统命名空间分离挂载点
2. 实际清理在文件系统不再忙碌时进行
3. 允许脚本立即返回

### 为什么需要 rootfs 验证

验证 rootfs 有效性可以避免：

1. 挂载错误的目录
2. 内核启动时找不到关键文件
3. 难以调试的问题

## 相关文档

- [Linux 挂载机制](https://man7.org/linux/man-pages/man8/mount.8.html)
- Rootfs 构建指南
- NFS 配置说明
