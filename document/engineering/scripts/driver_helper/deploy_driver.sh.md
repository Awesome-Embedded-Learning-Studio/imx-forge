# deploy_driver.sh - 驱动部署脚本

## 脚本概述

`deploy_driver.sh` 是 IMX-Forge 驱动开发基建系统的部署脚本。它将构建好的驱动模块和设备树文件部署到目标位置（TFTP、NFS、本地目录或远程服务器）。

### 核心功能

- **多目标部署**：支持 TFTP、NFS、本地、远程四种部署目标
- **交互式选择**：支持多选部署目标
- **灵活输入**：支持驱动名/板卡名或产物目录路径
- **智能查找**：自动查找产物目录
- **列表功能**：列出所有可部署的驱动

### 设计理念

这个脚本专注于"部署"这一单一职责，不关心驱动是如何构建的。它只负责将已构建好的产物复制到目标位置。

### 依赖关系

```
deploy_driver.sh
    ├─ scripts/driver_helper/driver_helper.conf (可选配置)
    └─ out/driver_artifacts/ (驱动构建产物)
```

## 参数说明

### 命令语法

```bash
./scripts/driver_helper/deploy_driver.sh <驱动名> [板名] [选项]
./scripts/driver_helper/deploy_driver.sh <产物目录> [选项]
./scripts/driver_helper/deploy_driver.sh --list
```

### 选项列表

| 选项 | 说明 |
|------|------|
| `--list` | 列出所有可部署的驱动（已构建的产物） |
| `--target=TYPE` | 部署目标 (tftp\|nfs\|local\|remote) |
| `--tftp-dir=PATH` | TFTP 目录 |
| `--nfs-dir=PATH` | NFS 目录 |
| `--local-dir=PATH` | 本地目录 |
| `--remote=HOST` | 远程主机 (user@host) |
| `--remote-path=PATH` | 远程路径 |
| `--help, -h` | 显示帮助信息 |

### 位置参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `驱动名` | 驱动名称 | `chardev_base_00` |
| `板名` | 板卡名称 | `alpha-board` |
| `产物目录` | 产物目录的完整路径 | `out/driver_artifacts/chardev_base_00/alpha-board` |

### 默认配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `TFTP_DIR` | `/srv/tftp` | TFTP 服务目录 |
| `NFS_DIR` | `rootfs/nfs` | NFS rootfs 目录（相对于项目根目录） |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  参数解析                                                    │
│  - 解析选项和位置参数                                       │
│  - 解析驱动名/板卡名或产物目录                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  目录查找                                                    │
│  - 如果是目录路径，直接使用                                  │
│  - 如果是驱动名，在 out/driver_artifacts/ 中查找            │
│  - 支持智能路径推断                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  目标选择                                                    │
│  - 如果指定 --target，直接部署                              │
│  - 否则，交互式选择（支持多选）                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  执行部署                                                    │
│  - TFTP: 只复制 .dtb，重命名为 imx6ull-aes.dtb             │
│  - NFS: 复制 .ko 到 lib/modules/，.dtb 到 boot/            │
│  - Local: 复制所有文件到指定目录                            │
│  - Remote: 通过 scp 复制到远程主机                          │
└─────────────────────────────────────────────────────────────┘
```

### 部署函数详解

#### deploy_tftp()

**作用**：部署驱动到 TFTP 目录。

**特殊处理**：

- 只复制 `.dtb` 文件，跳过 `.ko` 文件
- 目标文件名固定为 `imx6ull-aes.dtb`
- 如果目标文件已存在，先备份

**备份规则**：

```bash
imx6ull-aes.dtb → imx6ull-aes-YYYYMMDDHHMMSS.dtb
```

#### deploy_nfs()

**作用**：部署驱动到 NFS rootfs。

**文件映射**：

| 源文件 | 目标位置 |
|--------|----------|
| `*.ko` | `nfs/lib/modules/` |
| `*.dtb` | `nfs/boot/` |

#### deploy_local()

**作用**：部署到本地目录。

**行为**：复制所有 `.ko` 和 `.dtb` 文件到指定目录。

#### deploy_remote()

**作用**：部署到远程主机。

**前置检查**：

```bash
ssh -o ConnectTimeout=5 "$host" "echo test"
```

**传输方式**：使用 `scp` 复制文件。

## 配置选项

### 配置文件

可以在 `scripts/driver_helper/driver_helper.conf` 中覆盖默认配置：

```bash
# TFTP 目录
TFTP_DIR="/srv/tftp"

# NFS 目录（相对路径或绝对路径）
NFS_DIR="rootfs/nfs"
```

### 目录结构

```
PROJECT_ROOT/
├── out/
│   └── driver_artifacts/            # 构建产物源
│       └── <驱动>/
│           └── <板卡>/
│               ├── *.ko
│               └── *.dtb
├── rootfs/
│   └── nfs/                         # NFS 部署目标
│       ├── lib/
│       │   └── modules/
│       └── boot/
└── scripts/
    └── driver_helper/
        ├── deploy_driver.sh         # 本脚本
        └── driver_helper.conf       # 配置文件
```

## 使用示例

### 列出可部署的驱动

```bash
./scripts/driver_helper/deploy_driver.sh --list
```

**输出示例**：

```
========================================
可部署驱动列表
========================================

📦 example-driver
  └─ alpha-board [✓ KO ✓ DTB]
     路径: out/driver_artifacts/example-driver/alpha-board

📦 chardev_base_00
  └─ alpha-board [✓ KO ]
     路径: out/driver_artifacts/chardev_base_00/alpha-board

========================================
可用的驱动源码
========================================
  📁 example-driver
  📁 chardev_base_00
  📁 led
```

### 使用驱动名和板卡名部署

```bash
# 指定板卡
./scripts/driver_helper/deploy_driver.sh chardev_base_00 alpha-board

# 使用默认板卡 (alpha-board)
./scripts/driver_helper/deploy_driver.sh chardev_base_00
```

### 使用产物目录路径部署

```bash
# 使用完整路径
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/chardev_base_00/alpha-board

# 使用相对路径
./scripts/driver_helper/deploy_driver.sh driver/chardev_base_00/alpha-board
```

### 指定部署目标

```bash
# 部署到 TFTP
./scripts/driver_helper/deploy_driver.sh chardev_base_00 alpha-board --target=tftp

# 部署到 NFS
./scripts/driver_helper/deploy_driver.sh chardev_base_00 alpha-board --target=nfs

# 部署到本地目录
./scripts/driver_helper/deploy_driver.sh chardev_base_00 alpha-board --target=local --local-dir=/tmp/test

# 部署到远程
./scripts/driver_helper/deploy_driver.sh chardev_base_00 alpha-board --target=remote --remote=root@192.168.1.100 --remote-path=/tmp/drivers
```

### 交互式多选部署

```bash
./scripts/driver_helper/deploy_driver.sh chardev_base_00 alpha-board
```

**交互示例**：

```
驱动产物:
  - chardev_base_00_driver.ko (12K)
  - imx6ull-aes-chardev-base-00.dtb (256)

选择部署目标 (可多选，用空格分隔，如: 1 2):
1) TFTP服务器
2) NFS rootfs
3) 本地目录
4) 远程服务器

请选择 [1-4]: 1 2

[INFO] 部署到TFTP: /srv/tftp
  备份现有文件: imx6ull-aes-20240429123456.dtb
  ✓ imx6ull-aes-chardev-base-00.dtb → imx6ull-aes.dtb
已复制 1 个设备树文件（.ko 文件已跳过）

[INFO] 部署到NFS: /home/user/imx-forge/rootfs/nfs
  ✓ chardev_base_00_driver.ko -> lib/modules/
  ✓ imx6ull-aes-chardev-base-00.dtb -> boot/
已复制 2 个文件

✓ 部署完成
```

## 输出示例

### TFTP 部署成功

```
驱动产物:
  - imx6ull-aes-chardev-base-00.dtb (256)

[INFO] 部署到TFTP: /srv/tftp
  备份现有文件: imx6ull-aes-20240429123456.dtb
  ✓ imx6ull-aes-chardev-base-00.dtb → imx6ull-aes.dtb
已复制 1 个设备树文件（.ko 文件已跳过）

✓ 部署完成
```

### 远程部署成功

```
驱动产物:
  - chardev_base_00_driver.ko (12K)
  - imx6ull-aes-chardev-base-00.dtb (256)

[INFO] 部署到远程: root@192.168.1.100:/tmp/drivers
  ✓ chardev_base_00_driver.ko
  ✓ imx6ull-aes-chardev-base-00.dtb
已复制 2 个文件

✓ 部署完成
```

## 故障排除

### 常见错误

#### 错误 1：产物目录不存在

```
[ERROR] 目录不存在: out/driver_artifacts/unknown-driver/alpha-board
```

**解决方法**：

1. 检查驱动名称是否正确
2. 使用 `--list` 查看已构建的驱动
3. 先运行 `build_driver.sh` 构建驱动

#### 错误 2：TFTP 目录权限不足

```
[ERROR] 无法创建目录: /srv/tftp
```

**解决方法**：

使用 sudo 运行脚本或修复权限：

```bash
sudo chown $USER:$USER /srv/tftp
```

#### 错误 3：远程连接失败

```
[ERROR] 无法连接到 root@192.168.1.100
```

**解决方法**：

1. 检查网络连接
2. 确认 SSH 服务运行
3. 检查主机名和端口

#### 错误 4：没有可部署的文件

```
驱动产物:
(空)
```

**解决方法**：

检查构建是否成功：

```bash
ls out/driver_artifacts/<驱动>/<板卡>/
```

## 设计说明

### 为什么 TFTP 只部署 .dtb

TFTP 主要用于 U-Boot 加载设备树，内核模块 (.ko) 需要通过 rootfs 加载，因此：
- TFTP：只需要设备树文件
- NFS：需要内核模块和设备树

### 为什么需要备份机制

在开发过程中，频繁部署设备树可能导致混淆。通过备份，可以：
1. 保留历史版本以便回滚
2. 追踪部署历史
3. 快速定位问题

### 为什么支持多目标部署

在实际开发中，可能需要同时部署到多个位置：
- TFTP：用于板子启动
- NFS：用于运行时加载模块
- 本地：用于备份和测试

## 相关文档

- [build_driver.sh](./build_driver.sh.md) - 驱动构建脚本
- [review_driver.sh](./review_driver.sh.md) - 驱动审查脚本
- [驱动开发工作流程](./workflow.md)
