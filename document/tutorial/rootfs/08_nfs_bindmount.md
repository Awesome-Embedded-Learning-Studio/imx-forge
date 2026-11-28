---
title: NFS rootfs 多版本切换
---

# NFS rootfs 多版本切换：用 bind mount 解决嵌入式开发痛点

> 场景：嵌入式板子通过 NFS 挂载 rootfs，需要频繁在不同版本之间切换，但每次都要重启 NFS 服务太麻烦。

## 问题背景

在做嵌入式开发时，板子通过 NFS 挂载宿主机上的 rootfs，`/etc/exports` 大概长这样：

```
/home/charliechen/imx-forge/rootfs/nfs  192.168.60.0/24(rw,sync,no_root_squash,no_subtree_check)
```

测试不同版本的 rootfs 时，如果每次都要 `systemctl stop nfs-server` → 改配置 → `systemctl start nfs-server`，效率极低。

## 尝试过的方案：symlink（不管用）

第一直觉是把导出的目录改成 symlink，指向不同的实际 rootfs 目录：

```bash
mv /srv/nfs/rootfs /srv/nfs/rootfs-v1.0
ln -s /srv/nfs/rootfs-v1.0 /srv/nfs/rootfs
```

**结论：不管用。**

原因：NFS 服务在加载 `exports` 配置时会**直接解析并记住 symlink 背后的真实路径（inode）**。之后改 symlink 指向，NFS 完全感知不到，依然访问的是原来的目录。

## 正确方案：bind mount

bind mount 是在内核层面把一个目录"映射"到另一个挂载点，NFS 看到的始终是那个固定的挂载点路径，背后指向谁可以随时换。

### 初始设置

```bash
# 把现有 nfs 目录内容移走，保存为第一个版本
mv /home/charliechen/imx-forge/rootfs/nfs \
   /home/charliechen/imx-forge/rootfs/rootfs-v1.0

# 重新建一个空目录作为固定挂载点
mkdir /home/charliechen/imx-forge/rootfs/nfs

# 把 v1.0 bind mount 到这个目录
sudo mount --bind /home/charliechen/imx-forge/rootfs/rootfs-v1.0 \
                  /home/charliechen/imx-forge/rootfs/nfs
```

`/etc/exports` **一个字不用改**，NFS 服务也完全不用动。

### 切换版本

```bash
NFS_MNT=/home/charliechen/imx-forge/rootfs/nfs

sudo umount $NFS_MNT
sudo mount --bind /home/charliechen/imx-forge/rootfs/rootfs-v2.0 $NFS_MNT
```

板子端重新挂载一次即可：

```bash
umount /mnt && mount -t nfs 192.168.60.x:/home/charliechen/imx-forge/rootfs/nfs /mnt
```

### 封装成脚本

```bash
#!/bin/bash
# switch-rootfs.sh
# 用法：./switch-rootfs.sh v2.0

set -e

BASE=/home/charliechen/imx-forge/rootfs
NFS_MNT=$BASE/nfs
TARGET=$BASE/rootfs-$1

if [ ! -d "$TARGET" ]; then
    echo "Error: $TARGET does not exist"
    exit 1
fi

sudo umount "$NFS_MNT"
sudo mount --bind "$TARGET" "$NFS_MNT"
echo "✓ Switched to rootfs-$1"
```

用法：

```bash
chmod +x switch-rootfs.sh
./switch-rootfs.sh v2.0
./switch-rootfs.sh dev
```

## 方案对比总结

| 方案 | 切换操作 | 需要重启 NFS | 是否有效 |
|------|---------|-------------|---------|
| 直接改 exports | 编辑文件 + `exportfs -r` | ❌ | ✅ 但麻烦 |
| symlink | `ln -sfn` | ❌ | ❌ NFS 不感知 |
| **bind mount（推荐）** | 一条 `mount --bind` | ❌ | ✅ |

## 关键知识点

- **为什么 symlink 不行**：NFS 在 export 时解析的是文件系统 inode，symlink 只是一个路径别名，内核不会因为 symlink 改变而重新解析导出路径。
- **为什么 bind mount 可以**：bind mount 是在 VFS 层创建了一个新的挂载点，NFS 导出的是这个挂载点，挂载点背后的内容可以随时替换，NFS 只认挂载点本身。
- **`no_subtree_check` 的作用**：禁用子树检查，可以避免 bind mount 场景下的一些路径验证问题，建议开启。