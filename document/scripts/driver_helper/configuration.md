# driver_helper.conf - 配置文件说明

## 概述

`driver_helper.conf` 是 IMX Forge 项目中驱动辅助脚本的统一配置文件，用于设置默认参数和路径。所有驱动辅助脚本（build_driver.sh、deploy_driver.sh、review_driver.sh 等）都会读取此配置文件。

## 配置文件位置

```
scripts/driver_helper/driver_helper.conf
```

## 配置项说明

### 1. 默认板卡名称

```bash
DEFAULT_BOARD="alpha-board"
```

**说明**：指定默认的板卡名称，当脚本参数中未指定板卡时使用此值。

**使用场景**：
- 单板卡开发环境
- 减少命令行参数输入

**示例**：
```bash
# 使用配置文件中的默认板卡
./scripts/driver_helper/build_driver.sh example-driver
# 等价于
./scripts/driver_helper/build_driver.sh example-driver alpha-board
```

**可选值**：
- `alpha-board`（默认）
- `beta-board`
- 其他自定义板卡名称

### 2. 默认内核类型

```bash
DEFAULT_KERNEL_TYPE="mainline"
```

**说明**：指定默认的内核类型，影响驱动编译时的内核配置。项目已单轨化，只有主线内核一条，`--kernel` 参数也已退役。

**使用场景**：
- 统一开发环境
- 简化构建命令

**示例**：
```bash
# 使用配置文件中的默认内核类型
./scripts/driver_helper/build_driver.sh example-driver
```

**可选值**：
- `mainline`：主线内核（默认且唯一）

**内核配置**：

| 特性 | mainline |
|------|----------|
| 内核源码 | third_party/linux_mainline |
| 配置文件 | imx_aes_mainline_defconfig |
| 输出目录 | out/linux |
| 特点 | 上游主线内核，版本新、特性多 |

### 3. TFTP 部署目录

```bash
TFTP_DIR="${HOME}/tftp"
```

**说明**：指定 TFTP 服务器的根目录，用于部署设备树文件。

**使用场景**：
- 网络启动开发
- 快速设备树更新

**示例**：
```bash
# 使用配置文件中的 TFTP 目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp

# 可以在命令行中覆盖
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp --tftp-dir=/srv/tftp
```

**常见路径**：
- `~/tftp`（用户目录下，默认）
- `/srv/tftp`（系统级 TFTP 服务）
- `/var/lib/tftpboot`（某些发行版）

**注意事项**：
- 确保目录存在且有写权限
- TFTP 服务需要正确配置
- 部署时只复制 .dtb 文件

### 4. NFS 目录

```bash
NFS_DIR="rootfs/nfs"
```

**说明**：指定 NFS rootfs 的目录路径，用于部署驱动模块和设备树。

**使用场景**：
- NFS rootfs 开发
- 快速驱动测试

**示例**：
```bash
# 使用配置文件中的 NFS 目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs

# 可以在命令行中覆盖
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs --nfs-dir=/path/to/nfs
```

**目录结构要求**：
```
NFS_DIR/
├── lib/
│   └── modules/        # 驱动模块 (.ko)
└── boot/               # 设备树文件 (.dtb)
```

**注意事项**：
- 相对路径相对于项目根目录
- 部署时会自动创建子目录
- 确保 NFS 服务正常运行

### 5. 远程部署配置

```bash
REMOTE_HOST=""
REMOTE_PATH="/lib/modules"
```

**说明**：指定远程主机的地址和路径，用于远程部署。

**使用场景**：
- 远程开发板部署
- 多设备管理
- CI/CD 自动化

**示例**：
```bash
# 在配置文件中设置
REMOTE_HOST="root@192.168.1.100"
REMOTE_PATH="/lib/modules"

# 使用配置文件中的远程配置
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=remote

# 可以在命令行中覆盖
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board \
  --target=remote \
  --remote=debian@10.0.0.50 \
  --remote-path=/home/debian/drivers
```

**格式要求**：
- `REMOTE_HOST`：`user@host` 或 `host`
- `REMOTE_PATH`：绝对路径

**注意事项**：
- 需要配置 SSH 密钥认证
- 确保网络连接正常
- 远程主机需要有写权限

## 配置优先级

配置值的优先级从高到低：

1. **命令行参数**（最高优先级）
2. **环境变量**
3. **配置文件**
4. **脚本默认值**（最低优先级）

### 优先级示例

```bash
# 配置文件中设置
DEFAULT_BOARD="beta-board"
TFTP_DIR="/srv/tftp"

# 环境变量
export DEFAULT_BOARD="gamma-board"
export TFTP_DIR="/tmp/tftp"

# 命令行参数（最高优先级）
./scripts/driver_helper/build_driver.sh example-driver alpha-board
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp --tftp-dir=/custom/tftp

# 实际使用：
# 板卡：alpha-board（命令行参数）
# TFTP 目录：/custom/tftp（命令行参数）
```

## 完整配置文件示例

```bash
# 驱动辅助脚本配置文件
#
# 这个文件包含了驱动辅助脚本的默认配置值
# 修改此文件后，所有脚本将使用新的默认值
#

# 默认板卡名称
DEFAULT_BOARD="alpha-board"

# 默认内核类型 (mainline，单轨)
DEFAULT_KERNEL_TYPE="mainline"

# TFTP 部署目录
TFTP_DIR="${HOME}/tftp"

# NFS 目录（相对于项目根目录）
NFS_DIR="rootfs/nfs"

# 远程部署配置
REMOTE_HOST=""
REMOTE_PATH="/lib/modules"
```

## 使用场景

### 场景1：单板卡开发环境

**配置**：
```bash
DEFAULT_BOARD="alpha-board"
DEFAULT_KERNEL_TYPE="mainline"
TFTP_DIR="${HOME}/tftp"
NFS_DIR="rootfs/nfs"
```

**使用**：
```bash
# 简化的命令
./scripts/driver_helper/build_driver.sh example-driver
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp
```

### 场景2：多板卡开发环境

**配置**：
```bash
DEFAULT_BOARD="alpha-board"  # 最常用的板卡
DEFAULT_KERNEL_TYPE="mainline"
```

**使用**：
```bash
# 默认板卡
./scripts/driver_helper/build_driver.sh example-driver

# 其他板卡
./scripts/driver_helper/build_driver.sh example-driver beta-board
./scripts/driver_helper/build_driver.sh example-driver gamma-board
```

### 场景3：远程部署环境

**配置**：
```bash
REMOTE_HOST="root@192.168.1.100"
REMOTE_PATH="/lib/modules"
```

**使用**：
```bash
# 快速远程部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=remote
```

### 场景4：CI/CD 环境

**配置**：
```bash
DEFAULT_KERNEL_TYPE="mainline"
TFTP_DIR="/srv/tftp"
NFS_DIR=""
REMOTE_HOST="deploy@production-server"
REMOTE_PATH="/lib/modules"
```

**使用**：
```bash
# CI 脚本
./scripts/driver_helper/build_driver.sh example-driver
./scripts/driver_helper/review_driver.sh example-driver
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=remote
```

## 修改配置

### 1. 直接编辑配置文件

```bash
# 编辑配置文件
vim scripts/driver_helper/driver_helper.conf

# 修改后立即生效
./scripts/driver_helper/build_driver.sh example-driver
```

### 2. 使用环境变量覆盖

```bash
# 临时覆盖配置（不影响配置文件）
export DEFAULT_BOARD="beta-board"

# 使用环境变量
./scripts/driver_helper/build_driver.sh example-driver
```

### 3. 使用命令行参数覆盖

```bash
# 最高优先级，不影响配置文件和环境变量
./scripts/driver_helper/build_driver.sh example-driver --board=beta-board
```

## 配置验证

### 1. 检查配置文件语法

```bash
# 检查配置文件是否存在
ls -la scripts/driver_helper/driver_helper.conf

# 检查配置文件语法
bash -n scripts/driver_helper/driver_helper.conf
```

### 2. 验证配置值

```bash
# 查看配置文件内容
cat scripts/driver_helper/driver_helper.conf

# 测试配置是否生效
./scripts/driver_helper/build_driver.sh --help
./scripts/driver_helper/deploy_driver.sh --help
```

### 3. 检查路径有效性

```bash
# 检查 TFTP 目录
ls -la ~/tftp  # 或配置的 TFTP_DIR

# 检查 NFS 目录
ls -la rootfs/nfs  # 或配置的 NFS_DIR

# 检查远程主机连接
ssh root@192.168.1.100 "echo test"  # 或配置的 REMOTE_HOST
```

## 常见问题

### 1. 配置不生效

**问题**：修改配置文件后，脚本仍使用旧值。

**原因**：
- 配置文件语法错误
- 配置文件路径错误
- 环境变量或命令行参数覆盖了配置

**解决方案**：
```bash
# 检查配置文件语法
bash -n scripts/driver_helper/driver_helper.conf

# 清除环境变量
unset DEFAULT_BOARD
unset DEFAULT_KERNEL_TYPE

# 重新运行脚本
./scripts/driver_helper/build_driver.sh example-driver
```

### 2. TFTP 目录权限问题

**问题**：无法部署到 TFTP 目录。

**解决方案**：
```bash
# 修改配置文件中的 TFTP 目录
TFTP_DIR="/tmp/tftp"  # 使用用户目录

# 或修改目录权限
sudo chmod 777 /srv/tftp
```

### 3. 远程主机连接失败

**问题**：无法连接到远程主机。

**解决方案**：
```bash
# 测试 SSH 连接
ssh root@192.168.1.100

# 配置 SSH 密钥
ssh-copy-id root@192.168.1.100

# 或在配置文件中留空，使用命令行参数
REMOTE_HOST=""
```

## 最佳实践

### 1. 团队协作

```bash
# 在版本控制中包含默认配置
git add scripts/driver_helper/driver_helper.conf

# 个人配置使用环境变量
export DEFAULT_BOARD="my-board"
export TFTP_DIR="/custom/tftp"
```

### 2. 多环境配置

```bash
# 开发环境
DEFAULT_BOARD="dev-board"
DEFAULT_KERNEL_TYPE="mainline"
TFTP_DIR="${HOME}/tftp-dev"

# 生产环境
DEFAULT_BOARD="prod-board"
DEFAULT_KERNEL_TYPE="mainline"
TFTP_DIR="/srv/tftp-prod"
```

### 3. 配置文件管理

```bash
# 创建配置文件模板
cp scripts/driver_helper/driver_helper.conf scripts/driver_helper/driver_helper.conf.template

# 个人配置忽略
echo "scripts/driver_helper/driver_helper.conf" >> .gitignore

# 使用时复制模板
cp scripts/driver_helper/driver_helper.conf.template scripts/driver_helper/driver_helper.conf
```

## 相关文档

- [build_driver.md](./build_driver.md) - 驱动构建脚本
- [deploy_driver.md](./deploy_driver.md) - 驱动部署脚本
- [review_driver.md](./review_driver.md) - 驱动审查脚本
- [show_device_tree.md](./show_device_tree.md) - 设备树查看脚本
- [driver_buildlib.md](../lib/driver_buildlib.md) - 构建库说明
