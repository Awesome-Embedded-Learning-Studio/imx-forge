# IMX-Forge 开发环境搭建指南

> 本文档详细说明如何搭建 IMX-Forge 项目的完整开发环境，包括系统依赖、交叉编译工具链、VSCode 配置、调试工具以及环境验证方法。

---

## 目录

1. [系统要求](#系统要求)
2. [完整依赖清单](#完整依赖清单)
3. [交叉编译工具链安装](#交叉编译工具链安装)
4. [VSCode 配置](#vscode-配置)
5. [调试环境配置](#调试环境配置)
6. [常用工具安装](#常用工具安装)
7. [环境验证](#环境验证)
8. [常见问题排查](#常见问题排查)

---

## 系统要求

### 支持的开发环境

| 环境 | 最低版本 | 推荐版本 | 说明 |
|------|---------|---------|------|
| Ubuntu | 20.04 LTS | 24.04 LTS | 原生支持，配置最简单 |
| Debian | 11 | 12 (Bookworm) | 与 Ubuntu 类似 |
| WSL2 | Ubuntu 20.04 | Ubuntu 24.04 | 需要额外的网络配置 |
| macOS | 12 (Monterey) | 14 (Sonoma) | 需要使用 Docker 或虚拟机 |

### 硬件要求

| 组件 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 4 核 x86_64 | 8 核 x86_64 |
| 内存 | 8 GB | 16 GB 或更多 |
| 磁盘空间 | 30 GB 可用空间 | 50 GB 或更多 SSD |
| 网络 | - | 以太网连接（用于 TFTP/NFS 调试） |

### 目标平台

| 平台 | 架构 | 处理器 |
|------|------|--------|
| i.MX6ULL | ARMv7 | Cortex-A7 |
| i.MX6UL | ARMv7 | Cortex-A7 |
| i.MX8M Mini | ARMv8 | Cortex-A53 |

---

## 完整依赖清单

### Ubuntu/Debian 系统依赖

安装所有必要的系统包：

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    git git-lfs \
    bc bison flex \
    device-tree-compiler \
    libssl-dev libgnutls28-dev \
    libncurses-dev \
    python3 python3-pip python3-pyelftools \
    swig \
    zip unzip \
    wget curl \
    rsync \
    udev-tools \
    kmod \
    parted \
    dosfstools \
    e2fsprogs \
    mtd-utils \
    xorriso \
    qemu-user-static \
    binfmt-support
```
PS: 截止到2026年3月15日还能下到，下载之前建议跑一下

```bash
apt-cache policy build-essential git git-lfs bc bison flex device-tree-compiler libssl-dev libgnutls28-dev libncurses-dev python3 python3-pip python3-pyelftools swig zip unzip wget curl rsync udev-tools kmod parted dosfstools e2fsprogs mtd-utils xorriso qemu-user-static binfmt-support 2>&1 | grep -v "Candidate:" | grep -q "Unable to locate package" && echo "有包下载不到" || echo "所有包都能下载"
```

### 依赖说明

| 包名 | 用途 | 组件 |
|------|------|------|
| build-essential | GCC 编译器基础工具链 | 全部 |
| git | 版本控制 | 全部 |
| git-lfs | Git 大文件支持 | 全部 |
| bc | 内核配置计算工具 | Kernel |
| bison | 语法分析器生成器 | Kernel/U-Boot |
| flex | 词法分析器生成器 | Kernel/U-Boot |
| device-tree-compiler | 设备树编译器 (dtc) | Kernel/U-Boot |
| libssl-dev | OpenSSL 开发库 | U-Boot/Kernel |
| libgnutls28-dev | GnuTLS 开发库 | U-Boot |
| libncurses-dev | ncurses 开发库 | Kernel/BusyBox menuconfig |
| python3 | Python 3 解释器 | Kernel |
| python3-pyelftools | ELF 文件解析工具 | U-Boot |
| swig | 简化包装接口生成器 | U-Boot |
| zip/unzip | 压缩工具 | 各种 |
| wget/curl | 下载工具 | 各种 |
| rsync | 文件同步工具 | Rootfs |
| udev-tools | 设备管理 | 各种 |
| kmod | 内核模块管理 | 各种 |
| parted | 分区工具 | SD 卡镜像 |
| dosfstools | FAT 文件系统工具 | SD 卡镜像 |
| e2fsprogs | ext2/3/4 文件系统工具 | SD 卡镜像 |
| mtd-utils | MTD 设备工具 | Flash 操作 |
| xorriso | ISO 镜像工具 | 各种 |
| qemu-user-static | 用户空间 QEMU | 各种 |
| binfmt-support | 二进制格式支持 | 各种 |

### 网络调试工具（可选）

如果需要使用 TFTP/NFS 进行网络调试：

```bash
# TFTP 服务器
sudo apt install tftpd-hpa

# NFS 服务器
sudo apt install nfs-kernel-server

# 串口通信工具
sudo apt install picocom minicom screen

# 网络调试工具
sudo apt install tcpdump nmap net-tools iperf3
```

---

## 交叉编译工具链安装

### 选择工具链版本

IMX-Forge 项目推荐使用 ARM 官方发布的 Arm GNU Toolchain：

| 版本 | 发布时间 | 推荐度 |
|------|---------|--------|
| 15.2.Rel1 | 2025-04 | 推荐（最新稳定版） |
| 13.3.Rel1 | 2024-05 | 稳定 |
| 12.3.Rel1 | 2023-05 | 保守 |

### 下载工具链

```bash
# 创建工具链目录
sudo mkdir -p /opt/arm-toolchain
cd /opt/arm-toolchain

# 下载 ARM GNU Toolchain 15.2.Rel1 (ARM32 Linux)
wget https://developer.arm.com/downloads/-/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz

# 解压
tar -xf arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz

# 重命名为简短的目录名
sudo mv arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf arm-15.2-rel1
```

### 配置环境变量

创建或编辑 `~/.bashrc`，添加以下内容：

```bash
# ARM 交叉编译工具链
export ARM_TOOLCHAIN_ROOT=/opt/arm-toolchain
export ARM_TOOLCHAIN_VERSION=arm-15.2-rel1
export PATH="${ARM_TOOLCHAIN_ROOT}/${ARM_TOOLCHAIN_VERSION}/bin:${PATH}"

# 交叉编译前缀（供 Makefile 使用）
export CROSS_COMPILE=arm-none-linux-gnueabihf-
export ARCH=arm
```

刷新环境变量：

```bash
source ~/.bashrc
```

### 验证工具链安装

```bash
# 检查 GCC 版本
arm-none-linux-gnueabihf-gcc --version

# 预期输出示例：
# arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
# Copyright (C) 2025 Free Software Foundation, Inc.

# 检查其他工具
arm-none-linux-gnueabihf-ld --version
arm-none-linux-gnueabihf-objdump --version
```

### 工具链目录结构

```
/opt/arm-toolchain/arm-15.2-rel1/
├── bin/                          # 可执行工具
│   ├── arm-none-linux-gnueabihf-gcc
│   ├── arm-none-linux-gnueabihf-g++
│   ├── arm-none-linux-gnueabihf-as
│   ├── arm-none-linux-gnueabihf-ld
│   ├── arm-none-linux-gnueabihf-objcopy
│   ├── arm-none-linux-gnueabihf-objdump
│   └── ...
├── lib/                          # 主机库
├── libexec/                      # GCC 内部库
├── arm-none-linux-gnueabihf/     # 目标架构库
│   ├── bin/                      # 目标架构工具
│   ├── include/                  # 目标架构头文件
│   └── lib/                      # 目标架构库（libc, libm 等）
└── share/                        # 共享文件
```

---

## VSCode 配置

VSCode 的具体配置已拆到教程站的开发环境配置卷维护，这里只给入口：

- 远程开发（Windows 的 VSCode 连 WSL + 串口终端双通道）：[workflow/02](../tutorial/workflow/02_vscode_remote_ssh.md)
- 代码索引（clangd + compile_commands.json）：[workflow/04](../tutorial/workflow/04_clangd_cross_compile.md)
- 构建任务模板（tasks.json）：[workflow/05](../tutorial/workflow/05_tasks_json.md)
- 断点调试（gdbserver + launch.json）：[debug/01](../tutorial/debug/01_gdbserver_remote_debug.md)

最小可用组合：VSCode 连进 WSL 后装 clangd 扩展、把 C/C++ 扩展的 IntelliSense 设为 disabled，再拷一份 tasks.json 模板，编译与跳转就能一键化。

## 调试环境配置

### 串口调试工具

#### minicom

安装：

```bash
sudo apt install minicom
```

配置：

```bash
sudo minicom -s
```

使用方法：

```bash
# 直接连接
minicom -D /dev/ttyUSB0 -b 115200

# 使用配置文件
minicom
```

快捷键：
- `Ctrl + A` 然后 `Z`：显示帮助菜单
- `Ctrl + A` 然后 `Q`：退出
- `Ctrl + A` 然后 `X`：重置并退出

#### USB 串口权限配置

避免每次都需要 sudo：

```bash
# 创建 udev 规则
sudo nano /etc/udev/rules.d/99-usb-serial.rules

# 添加以下内容：
SUBSYSTEM=="tty", ATTRS{idVendor}=="XXXX", ATTRS{idProduct}=="XXXX", MODE="0666"
# 或者简单粗暴：
KERNEL=="ttyUSB*", MODE="0666"
KERNEL=="ttyACM*", MODE="0666"

# 重新加载 udev 规则
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### TFTP 配置

#### 安装 TFTP 服务器

```bash
sudo apt install tftpd-hpa
```

#### 配置 TFTP

编辑配置文件：

```bash
sudo nano /etc/default/tftpd-hpa
```

修改为：

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/home/<username>/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create"
```

创建 TFTP 目录：

```bash
mkdir -p ~/tftp
sudo chmod 777 ~/tftp
sudo chmod o+x ~  # 允许 tftp 用户进入你的 home 目录
```

重启 TFTP 服务：

```bash
sudo systemctl restart tftpd-hpa
sudo systemctl status tftpd-hpa
```

测试 TFTP：

```bash
# 创建测试文件
echo "Hello TFTP" > ~/tftp/test.txt

# 在本地测试
echo "get test.txt" | tftp 127.0.0.1
```

### NFS 配置

#### 安装 NFS 服务器

```bash
sudo apt install nfs-kernel-server
```

#### 配置导出目录

编辑 `/etc/exports`：

```bash
sudo nano /etc/exports
```

添加：

```
/home/<username>/imx-forge/rootfs/nfs 192.168.60.0/24(rw,sync,no_subtree_check,no_root_squash)
```

应用配置：

```bash
sudo exportfs -ra
```

验证导出：

```bash
sudo exportfs -v
```

#### 配置固定端口（WSL2 必需）

编辑 `/etc/nfs.conf`：

```bash
sudo nano /etc/nfs.conf
```

添加：

```ini
[nfsd]
port=2049

[mountd]
port=20048

[lockd]
port=32803
udp-port=32769

[statd]
port=32765
```

重启 NFS 服务：

```bash
sudo systemctl restart nfs-server
```

### 网络配置

#### WSL2 Mirrored 模式（推荐）

在 Windows 用户目录下创建 `.wslconfig`：

```ini
[wsl2]
networkingMode=mirrored
firewall=true
```

重启 WSL：

```powershell
wsl --shutdown
```

验证网络模式：

```bash
ip addr
# 应该能看到与 Windows 相同的网卡
```

#### Windows 防火墙配置

在管理员 PowerShell 中执行：

```powershell
# TFTP
New-NetFirewallRule -DisplayName "WSL TFTP" `
    -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow

# NFS
New-NetFirewallRule -DisplayName "NFS-TCP-111" -Direction Inbound -Protocol TCP -LocalPort 111 -Action Allow
New-NetFirewallRule -DisplayName "NFS-TCP-2049" -Direction Inbound -Protocol TCP -LocalPort 2049 -Action Allow
New-NetFirewallRule -DisplayName "NFS-mountd-20048" -Direction Inbound -Protocol TCP -LocalPort 20048 -Action Allow
New-NetFirewallRule -DisplayName "NFS-lockd-32803" -Direction Inbound -Protocol TCP -LocalPort 32803 -Action Allow
New-NetFirewallRule -DisplayName "NFS-statd-32765" -Direction Inbound -Protocol TCP -LocalPort 32765 -Action Allow
```

---

## 常用工具安装

### Git 配置

```bash
# 基本配置
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# 更好的差异合并工具
git config --global merge.diffdriver "vimdiff"

# 别名
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.unstage 'reset HEAD --'
git config --global alias.last 'log -1 HEAD'
git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

# Git LFS（大文件支持）
git lfs install
```

### build-essential

```bash
sudo apt install build-essential
```

包含：
- gcc
- g++
- make
- libc6-dev
- dpkg-dev

### 设备树编译器

```bash
sudo apt install device-tree-compiler
```

验证：

```bash
dtc --version
# 预期输出：Version: DTC 1.6.1
```

### QEMU（用于模拟）

```bash
sudo apt install qemu-system-arm qemu-user-static binfmt-support
```

### 其他开发工具

```bash
# 代码分析
sudo apt install cscope global

# 调试工具（宿主原生 gdb，只用于调试本机 x86 程序；
# 交叉调试用的是工具链自带的 arm-none-linux-gnueabihf-gdb 与 rootfs 里的 gdbserver，
# 见教程 debug/01）
sudo apt install gdb gdbserver

# 性能分析
sudo apt install perf-tools-linux strace ltrace

# 十六进制编辑器
sudo apt install hexedit bvi ghex

# 二进制工具
sudo apt install binutils

# 压缩工具
sudo apt install xz-utils lzop
```

---

## 环境验证

### 验证脚本

创建环境验证脚本 `scripts/verify_env.sh`：

```bash
#!/bin/bash
#
# IMX-Forge Environment Verification Script
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++))
}

check_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo "========================================"
echo "IMX-Forge Environment Verification"
echo "========================================"
echo ""

# === System ===
check_info "Checking system..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    check_pass "OS: $PRETTY_NAME"
else
    check_warn "Cannot determine OS version"
fi

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    check_pass "Architecture: $ARCH"
else
    check_warn "Architecture: $ARCH (may not be fully supported)"
fi

# === Build Tools ===
check_info "Checking build tools...

for cmd in gcc g++ make; do
    if command -v $cmd &> /dev/null; then
        check_pass "$cmd: $(command -v $cmd)"
    else
        check_fail "$cmd: not found"
    fi
done

# === Cross Toolchain ===
check_info "Checking cross toolchain..."

if command -v arm-none-linux-gnueabihf-gcc &> /dev/null; then
    GCC_VERSION=$(arm-none-linux-gnueabihf-gcc --version | head -n1)
    check_pass "Cross compiler: $GCC_VERSION"
else
    check_fail "Cross compiler: arm-none-linux-gnueabihf-gcc not found"
fi

for tool in arm-none-linux-gnueabihf-ld arm-none-linux-gnueabihf-objcopy arm-none-linux-gnueabihf-objdump; do
    if command -v $tool &> /dev/null; then
        check_pass "$tool: found"
    else
        check_fail "$tool: not found"
    fi
done

# === Kernel Build Tools ===
check_info "Checking kernel build tools..."

for cmd in bc bison flex dtc; do
    if command -v $cmd &> /dev/null; then
        check_pass "$cmd: $(command -v $cmd)"
    else
        check_fail "$cmd: not found"
    fi
done

# === Libraries ===
check_info "Checking libraries..."

for lib in libssl-dev libncurses-dev; do
    if dpkg -s $lib &> /dev/null; then
        check_pass "$lib: installed"
    else
        check_fail "$lib: not installed"
    fi
done

# === Python ===
check_info "Checking Python..."

if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    check_pass "Python: $PYTHON_VERSION"
else
    check_fail "Python 3: not found"
fi

if python3 -c "import elftools" 2>/dev/null; then
    check_pass "pyelftools: installed"
else
    check_warn "pyelftools: not installed (optional but recommended)"
fi

# === Git ===
check_info "Checking Git..."

if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version)
    check_pass "Git: $GIT_VERSION"
else
    check_fail "Git: not found"
fi

if command -v git-lfs &> /dev/null; then
    check_pass "Git LFS: installed"
else
    check_warn "Git LFS: not installed (optional)"
fi

# === Serial Tools ===
check_info "Checking serial tools..."

for cmd in picocom minicom screen; do
    if command -v $cmd &> /dev/null; then
        check_pass "$cmd: installed"
    else
        check_warn "$cmd: not installed (optional)"
    fi
done

# === Network Debug Tools ===
check_info "Checking network debug tools..."

if systemctl is-active --quiet tftpd-hpa 2>/dev/null; then
    check_pass "TFTP server: running"
else
    check_warn "TFTP server: not running (optional)"
fi

if systemctl is-active --quiet nfs-server 2>/dev/null; then
    check_pass "NFS server: running"
else
    check_warn "NFS server: not running (optional)"
fi

# === Project Structure ===
check_info "Checking project structure..."

if [ -d "third_party/uboot-imx" ]; then
    check_pass "U-Boot source: found"
else
    check_warn "U-Boot source: not found (run git submodule update)"
fi

if [ -d "third_party/linux-imx" ]; then
    check_pass "Linux source: found"
else
    check_warn "Linux source: not found (run git submodule update)"
fi

if [ -d "third_party/busybox" ]; then
    check_pass "BusyBox source: found"
else
    check_warn "BusyBox source: not found (run git submodule update)"
fi

# === Summary ===
echo ""
echo "========================================"
echo "Verification Summary"
echo "========================================"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARN_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "Please install missing dependencies before continuing."
    exit 1
else
    echo "Environment verification passed!"
    exit 0
fi
```

使用方法：

```bash
chmod +x scripts/verify_env.sh
./scripts/verify_env.sh
```

### 检查清单

完成以下检查确认环境已正确配置：

- [ ] **操作系统**：Ubuntu 20.04+ / Debian 11+
- [ ] **编译工具**：gcc, g++, make 已安装
- [ ] **交叉工具链**：arm-none-linux-gnueabihf-gcc 可用
- [ ] **内核工具**：bc, bison, flex, dtc 已安装
- [ ] **开发库**：libssl-dev, libncurses-dev 已安装
- [ ] **Python**：python3 和 python3-pyelftools 已安装
- [ ] **版本控制**：git 和 git-lfs 已安装
- [ ] **串口工具**：picocom（或 minicom/screen）已安装
- [ ] **网络调试**：TFTP/NFS 已配置（可选）
- [ ] **VSCode**：推荐插件已安装
- [ ] **项目代码**：子模块已更新

### 快速验证命令

```bash
# 一键验证所有关键组件
echo "=== Quick Environment Check ===" && \
arm-none-linux-gnueabihf-gcc --version && \
dtc --version && \
git --version && \
python3 --version && \
echo "=== All critical tools present ==="
```

---

## 常见问题排查

### 工具链问题

#### 问题：`arm-none-linux-gnueabihf-gcc: command not found`

**原因**：工具链未安装或未添加到 PATH

**解决方法**：

1. 确认工具链已安装：
   ```bash
   ls /opt/arm-toolchain/
   ```

2. 检查 PATH：
   ```bash
   echo $PATH | grep arm-toolchain
   ```

3. 重新加载环境变量：
   ```bash
   source ~/.bashrc
   ```

4. 如果仍然失败，手动添加到 PATH：
   ```bash
   export PATH="/opt/arm-toolchain/arm-15.2-rel1/bin:$PATH"
   ```

#### 问题：编译时出现 `/usr/bin/ld: cannot find -lxxx`

**原因**：缺少链接库

**解决方法**：

1. 检查库是否存在：
   ```bash
   arm-none-linux-gnueabihf-gcc --print-search-dirs
   ```

2. 安装缺少的库：
   ```bash
   sudo apt install libxxx-dev
   ```

### 编译问题

#### 问题：U-Boot 编译失败 `error: implicit declaration of function 'xxx'`

**原因**：头文件路径问题或配置不正确

**解决方法**：

1. 清理并重新配置：
   ```bash
   make distclean
   make mx6ull_aes_emmc_defconfig
   make -j$(nproc)
   ```

2. 检查 defconfig 是否正确

#### 问题：内核编译失败 `make: dtc: Command not found`

**原因**：缺少设备树编译器

**解决方法**：

```bash
sudo apt install device-tree-compiler
```

### 网络调试问题

#### 问题：TFTP 传输超时 `T T T T T`

**原因**：防火墙拦截或网络不通

**解决方法**：

1. 检查 TFTP 服务状态：
   ```bash
   sudo systemctl status tftpd-hpa
   ```

2. 检查端口监听：
   ```bash
   sudo ss -ulnp | grep 69
   ```

3. 配置防火墙规则（见前文）

4. 检查网络连通性：
   ```bash
   ping <开发板IP>
   ```

#### 问题：NFS 挂载失败

**原因**：配置错误或权限问题

**解决方法**：

1. 检查 exports 配置：
   ```bash
   sudo exportfs -v
   ```

2. 检查端口是否固定：
   ```bash
   rpcinfo -p localhost
   ```

3. 测试本地挂载：
   ```bash
   sudo mount -t nfs 127.0.0.1:/path/to/nfs /mnt
   ```

### WSL2 问题

#### 问题：WSL2 无法访问开发板网络

**原因**：NAT 模式网络隔离

**解决方法**：

切换到 mirrored 模式（见前文 WSL2 Mirrored 模式配置）

#### 问题：WSL2 中 TFTP/NFS 端口不通

**原因**：Windows 防火墙拦截

**解决方法**：

添加 Windows 防火墙规则（见前文 Windows 防火墙配置）

---

## 附录

### 完整依赖安装命令

```bash
#!/bin/bash
#
# IMX-Forge 完整依赖安装脚本
#

set -e

echo "Installing IMX-Forge dependencies..."

# 基础工具
sudo apt update
sudo apt install -y \
    build-essential \
    git git-lfs \
    bc bison flex \
    device-tree-compiler \
    libssl-dev libgnutls28-dev \
    libncurses-dev \
    python3 python3-pip python3-pyelftools \
    swig \
    zip unzip \
    wget curl \
    rsync

# 调试工具
sudo apt install -y \
    picocom minicom screen \
    tftpd-hpa \
    nfs-kernel-server

# 其他工具
sudo apt install -y \
    qemu-system-arm qemu-user-static \
    cscope global \
    gdb gdbserver \
    perf-tools-linux strace \
    hexedit

echo "Dependencies installed successfully!"
```

> 注：这里的 `gdb` 是宿主原生版本，只用于调试本机 x86 程序；交叉调试用的是工具链自带的 `arm-none-linux-gnueabihf-gdb` 与 rootfs 里的 `gdbserver`，见教程 [debug/01](../tutorial/debug/01_gdbserver_remote_debug.md)。

### 环境变量模板

`~/.bashrc` 添加内容：

```bash
# IMX-Forge Environment
export IMX_FORGE_ROOT="$HOME/imx-forge"

# ARM Toolchain
export ARM_TOOLCHAIN_ROOT="/opt/arm-toolchain"
export ARM_TOOLCHAIN_VERSION="arm-15.2-rel1"
export PATH="${ARM_TOOLCHAIN_ROOT}/${ARM_TOOLCHAIN_VERSION}/bin:${PATH}"

# Cross Compile
export CROSS_COMPILE="arm-none-linux-gnueabihf-"
export ARCH="arm"

# Project Shortcuts
export UBOOT_SRC="$IMX_FORGE_ROOT/third_party/uboot-imx"
export LINUX_SRC="$IMX_FORGE_ROOT/third_party/linux-imx"
export BUSYBOX_SRC="$IMX_FORGE_ROOT/third_party/busybox"

# Aliases
alias uboot='cd $UBOOT_SRC'
alias linux='cd $LINUX_SRC'
alias busybox='cd $BUSYBOX_SRC'
alias tftp='cd ~/tftp'
alias nfs='cd $IMX_FORGE_ROOT/rootfs/nfs'
```

### VSCode 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Ctrl + Shift + B` | 运行构建任务 |
| `Ctrl + P` | 快速打开文件 |
| `Ctrl + G` | 跳转到行 |
| `Ctrl + Shift + F` | 全局搜索 |
| `F5` | 启动调试 |
| `Ctrl + `` ` | 打开终端 |

### 参考资源

- [ARM 官方工具链下载](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
- [U-Boot 官方文档](https://www.denx.de/wiki/U-Boot)
- [Linux 内核文档](https://www.kernel.org/doc/html/latest/)
- [Device Tree 规范](https://www.devicetree.org/)
- [BusyBox 官方网站](https://busybox.net/)

---

**文档版本**：v1.0
**最后更新**：2026-03-15
**维护者**：IMX-Forge 项目团队
