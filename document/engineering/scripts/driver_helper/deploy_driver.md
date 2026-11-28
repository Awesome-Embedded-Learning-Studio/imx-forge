# deploy_driver.sh - 驱动部署脚本

## 概述

`deploy_driver.sh` 是 IMX Forge 项目中的驱动部署脚本，用于将构建好的驱动模块和设备树文件部署到目标系统。支持多种部署方式，包括 TFTP、NFS、本地目录和远程服务器。

## 功能特性

- ✅ 支持多种部署方式（TFTP、NFS、本地、远程）
- ✅ 交互式和命令行两种操作模式
- ✅ TFTP 部署时自动备份现有设备树
- ✅ 自动创建目标目录
- ✅ 详细的部署日志和错误提示
- ✅ 支持自定义部署路径

## 语法

```bash
./scripts/driver_helper/deploy_driver.sh <产物目录> [选项]
```

## 参数说明

### 位置参数

| 参数 | 说明 | 必需 |
|------|------|------|
| 产物目录 | 驱动产物目录路径（通常是 `out/driver_artifacts/<驱动>/<板卡>/`） | 是 |

### 选项参数

| 选项 | 说明 | 示例 | 默认值 |
|------|------|------|--------|
| `--target=TYPE` | 部署目标类型（tftp\|nfs\|local\|remote） | `--target=tftp` | 交互式选择 |
| `--tftp-dir=PATH` | TFTP 服务器目录 | `--tftp-dir=/srv/tftp` | `~/tftp` 或 `/srv/tftp` |
| `--nfs-dir=PATH` | NFS rootfs 目录 | `--nfs-dir=/path/to/nfs` | `rootfs/nfs` |
| `--local-dir=PATH` | 本地目标目录 | `--local-dir=/tmp/drivers` | - |
| `--remote=HOST` | 远程主机地址 | `--remote=user@192.168.1.100` | - |
| `--remote-path=PATH` | 远程目标路径 | `--remote-path=/lib/modules` | `/lib/modules` |
| `--help, -h` | 显示帮助信息 | `--help` | - |

## 部署方式详解

### 1. TFTP 部署

**特点**：
- 只部署设备树文件（.dtb）
- 自动备份现有的设备树文件
- 固定目标文件名为 `imx6ull-aes.dtb`
- 适合网络启动场景

**使用场景**：
- 开发板通过网络启动
- 需要频繁更新设备树
- 多台开发板共享同一设备树

**示例**：
```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board

# 直接部署到 TFTP
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp

# 指定 TFTP 目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp --tftp-dir=/srv/tftp
```

**备份机制**：
```
部署前:
/srv/tftp/
└── imx6ull-aes.dtb  (现有文件)

部署后:
/srv/tftp/
├── imx6ull-aes-20260407123456.dtb  (备份文件)
└── imx6ull-aes.dtb  (新文件)
```

**注意事项**：
- TFTP 部署不会复制 .ko 文件
- 备份文件使用时间戳命名
- 确保目标目录有写权限

### 2. NFS 部署

**特点**：
- 同时部署驱动模块和设备树
- 驱动模块存放在 `lib/modules/`
- 设备树存放在 `boot/`
- 适合 NFS rootfs 场景

**使用场景**：
- 开发板使用 NFS rootfs
- 需要同时更新驱动和设备树
- 快速迭代开发

**示例**：
```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board

# 直接部署到 NFS
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs

# 指定 NFS 目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs --nfs-dir=/path/to/nfs/rootfs
```

**目录结构**：
```
NFS rootfs/
├── lib/
│   └── modules/
│       ├── example-driver.ko
│       └── led.ko
└── boot/
    ├── imx6ull-aes-example-driver.dtb
    └── imx6ull-aes-led.dtb
```

### 3. 本地部署

**特点**：
- 将产物复制到指定本地目录
- 保留原始文件名
- 适合打包或临时存储

**使用场景**：
- 准备发布包
- 临时备份
- 转移到其他位置

**示例**：
```bash
# 交互式部署（会提示输入目录）
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board

# 直接部署到本地目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=local --local-dir=/tmp/drivers

# 部署到当前目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=local --local-dir=.
```

### 4. 远程部署

**特点**：
- 通过 SSH/SCP 部署到远程主机
- 自动测试连接
- 自动创建远程目录
- 适合远程开发板或服务器

**使用场景**：
- 远程开发板
- CI/CD 自动化部署
- 多台设备批量部署

**示例**：
```bash
# 部署到远程主机
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board \
  --target=remote \
  --remote=root@192.168.1.100 \
  --remote-path=/lib/modules

# 部署到远程主机的自定义路径
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board \
  --target=remote \
  --remote=debian@10.0.0.50 \
  --remote-path=/home/debian/drivers
```

**要求**：
- SSH 密钥配置或密码认证
- 远程主机有写权限
- 网络连接正常

## 使用示例

### 1. 交互式部署

```bash
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

输出示例：
```
[INFO] 驱动产物:
[INFO]   - example-driver.ko (12K)
[INFO]   - imx6ull-aes-example-driver.dtb (1.2K)

选择部署目标:
1) TFTP服务器
2) NFS rootfs
3) 本地目录
4) 远程服务器

请选择 [1-4]: 1

[INFO] 部署到TFTP: /srv/tftp
[INFO]   备份现有文件: imx6ull-aes-20260407123456.dtb
[INFO]   ✓ imx6ull-aes-example-driver.dtb → imx6ull-aes.dtb
[INFO] 已复制 1 个设备树文件（.ko 文件已跳过）

[INFO] ✓ 部署完成
```

### 2. 命令行模式部署

```bash
# TFTP 部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp

# NFS 部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs

# 本地部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=local --local-dir=/tmp/drivers

# 远程部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=remote --remote=root@192.168.1.100 --remote-path=/lib/modules
```

### 3. 批量部署多个驱动

```bash
# 部署所有已构建的驱动
for driver_dir in out/driver_artifacts/*/; do
    ./scripts/driver_helper/deploy_driver.sh "$driver_dir/alpha-board" --target=nfs
done
```

### 4. 部署后验证

```bash
# 部署到 NFS
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs

# 验证文件是否正确部署
ls -lh rootfs/nfs/lib/modules/
ls -lh rootfs/nfs/boot/
```

## 常见问题

### 1. 产物目录不存在

**错误信息**：
```
❌ 目录不存在: out/driver_artifacts/example-driver/alpha-board
```

**解决方案**：
```bash
# 先构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 然后再部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

### 2. TFTP 目录权限不足

**错误信息**：
```
mkdir: cannot create directory '/srv/tftp': Permission denied
```

**解决方案**：
```bash
# 使用 sudo
sudo ./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp

# 或者修改 TFTP 目录权限
sudo chmod 777 /srv/tftp
```

### 3. 远程主机连接失败

**错误信息**：
```
❌ 无法连接 to root@192.168.1.100
```

**解决方案**：
```bash
# 测试 SSH 连接
ssh root@192.168.1.100

# 配置 SSH 密钥
ssh-copy-id root@192.168.1.100

# 检查网络连接
ping 192.168.1.100
```

### 4. NFS 目录不存在

**错误信息**：
```
❌ 目录不存在: /path/to/nfs
```

**解决方案**：
```bash
# 创建 NFS 目录
mkdir -p /path/to/nfs/lib/modules
mkdir -p /path/to/nfs/boot

# 或者使用配置文件中的默认路径
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs --nfs-dir=rootfs/nfs
```

### 5. 设备树文件未找到

**错误信息**：
```
[INFO] 已复制 0 个设备树文件
```

**解决方案**：
```bash
# 检查产物目录内容
ls -la out/driver_artifacts/example-driver/alpha-board/

# 确保有 .dtb 文件
# 如果没有，检查构建过程是否包含设备树编译
```

## 配置文件

可以通过配置文件 `driver_helper.conf` 设置默认值：

```bash
# 默认 TFTP 目录
TFTP_DIR="${HOME}/tftp"

# 默认 NFS 目录
NFS_DIR="rootfs/nfs"

# 默认远程主机
REMOTE_HOST=""

# 默认远程路径
REMOTE_PATH="/lib/modules"
```

## 注意事项

1. **TFTP 部署**：
   - 只部署设备树文件，不部署 .ko 文件
   - 自动备份现有文件
   - 确保目标文件名正确

2. **NFS 部署**：
   - 需要确保 NFS 服务正常运行
   - 检查挂载点和权限
   - 验证部署后文件是否生效

3. **远程部署**：
   - 确保 SSH 连接正常
   - 配置免密登录以自动化
   - 测试远程目录权限

4. **本地部署**：
   - 目标目录必须已存在或可创建
   - 检查磁盘空间
   - 验证文件完整性

5. **通用注意事项**：
   - 部署前建议先审查产物
   - 保留原始产物的备份
   - 记录部署的版本和时间

## 与其他脚本的配合

### 1. 构建后部署

```bash
# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 部署驱动
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

### 2. 审查后部署

```bash
# 审查驱动
./scripts/driver_helper/review_driver.sh example-driver

# 审查通过后部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

### 3. 查看设备树后部署

```bash
# 查看设备树内容
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/*.dtb

# 确认无误后部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

## 高级用法

### 1. 自动化部署脚本

```bash
#!/bin/bash
# auto_deploy.sh

# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver || exit 1

# 审查产物
./scripts/driver_helper/review_driver.sh example-driver || exit 1

# 部署到 NFS
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/example-driver/alpha-board \
  --target=nfs || exit 1

echo "部署完成！"
```

### 2. 多目标批量部署

```bash
#!/bin/bash
# 批量部署到多个目标

ARTIFACT_DIR="out/driver_artifacts/example-driver/alpha-board"

# 部署到 TFTP
./scripts/driver_helper/deploy_driver.sh "$ARTIFACT_DIR" --target=tftp

# 部署到 NFS
./scripts/driver_helper/deploy_driver.sh "$ARTIFACT_DIR" --target=nfs

# 部署到远程
./scripts/driver_helper/deploy_driver.sh "$ARTIFACT_DIR" \
  --target=remote \
  --remote=root@192.168.1.100 \
  --remote-path=/lib/modules
```

### 3. CI/CD 集成

```yaml
# .gitlab-ci.yml 示例
deploy:
  stage: deploy
  script:
    - ./scripts/driver_helper/build_driver.sh example-driver
    - ./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=remote --remote=$DEPLOY_HOST --remote-path=$DEPLOY_PATH
  only:
    - main
```

## 相关文档

- [build_driver.md](./build_driver.md) - 驱动构建脚本
- [review_driver.md](./review_driver.md) - 驱动审查脚本
- [show_device_tree.sh.md](./show_device_tree.sh.md) - 设备树查看脚本
- [configuration.md](./configuration.md) - 配置文件说明
- [driver_buildlib.md](../lib/driver_buildlib.md) - 构建库说明
