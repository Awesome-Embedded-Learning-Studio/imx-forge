#!/bin/bash

# 主机依赖检查脚本
# 功能：统一管理所有构建脚本的依赖检查

set -e

# 颜色定义（如果未定义）
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# 日志函数（如果未定义）
if [ -z "$(type -t log_info)" ]; then
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_debug() { if [[ "${DEBUG:-0}" == "1" ]]; then echo -e "${BLUE}[DEBUG]${NC} $1"; fi; }
    log_cmd() { echo -e "${YELLOW}[CMD]${NC} $1"; }
fi

# 所有可能的依赖包
ALL_PKGS=(
    "build-essential"
    "bc"
    "bison"
    "flex"
    "device-tree-compiler"
    "python3"
    "python3-pyelftools"
    "swig"
    "libssl-dev"
    "libgnutls28-dev"
    "libncurses-dev"
)

# 按构建目标划分的依赖包
UBOOT_PKGS=(
    "build-essential"
    "bc"
    "bison"
    "flex"
    "device-tree-compiler"
    "python3"
    "python3-pyelftools"
    "swig"
    "libssl-dev"
    "libgnutls28-dev"
    "libncurses-dev"
    "imagemagick"
)

LINUX_PKGS=(
    "build-essential"
    "bc"
    "bison"
    "flex"
    "device-tree-compiler"
    "python3"
    "libssl-dev"
    "libgnutls28-dev"
    "libncurses-dev"
)

BUSYBOX_PKGS=(
    "build-essential"
    "libncurses-dev"
)

# 检查单个命令是否存在
check_cmd() {
    local cmd=$1
    local pkg=$2
    if command -v ${cmd} &> /dev/null; then
        FOUND_PKGS+=(${pkg})
        return 0
    else
        MISSING_PKGS+=(${pkg})
        return 1
    fi
}

# 检查单个dpkg包是否安装
check_dpkg() {
    local pkg=$1
    if dpkg -s ${pkg} &> /dev/null; then
        FOUND_PKGS+=(${pkg})
        return 0
    else
        MISSING_PKGS+=(${pkg})
        return 1
    fi
}

# 检查单个头文件是否存在
check_header() {
    local header=$1
    local pkg=$2
    if [ -f "${header}" ]; then
        FOUND_PKGS+=(${pkg})
        return 0
    else
        MISSING_PKGS+=(${pkg})
        return 1
    fi
}

# 检查单个Python模块是否安装
check_python_module() {
    local module=$1
    local pkg=$2
    if python3 -c "import ${module}" 2>/dev/null; then
        FOUND_PKGS+=(${pkg})
        return 0
    else
        MISSING_PKGS+=(${pkg})
        return 1
    fi
}

# 检查指定的依赖包列表
check_dependencies() {
    local -n pkgs=$1
    local target_name=$2
    
    log_info "检查 ${target_name:-主机} 依赖包..."

    MISSING_PKGS=()
    FOUND_PKGS=()

    # 检查每个包
    for pkg in "${pkgs[@]}"; do
        case "$pkg" in
            build-essential)
                check_cmd gcc build-essential || true
                check_cmd make build-essential || true
                ;;
            bc)
                check_cmd bc bc || true
                ;;
            bison)
                check_cmd bison bison || true
                ;;
            flex)
                check_cmd flex flex || true
                ;;
            device-tree-compiler)
                check_cmd dtc device-tree-compiler || true
                ;;
            python3)
                check_cmd python3 python3 || true
                ;;
            python3-pyelftools)
                check_python_module elftools python3-pyelftools || true
                ;;
            swig)
                check_cmd swig swig || true
                ;;
            imagemagick)
                check_cmd convert imagemagick || true
                ;;
            libssl-dev)
                if dpkg -s libssl-dev &> /dev/null; then
                    FOUND_PKGS+=(${pkg})
                else
                    MISSING_PKGS+=(${pkg})
                fi
                ;;
            libgnutls28-dev)
                if dpkg -s libgnutls28-dev &> /dev/null || [ -f /usr/include/gnutls/gnutls.h ]; then
                    FOUND_PKGS+=(${pkg})
                else
                    MISSING_PKGS+=(${pkg})
                fi
                ;;
            libncurses-dev)
                if dpkg -s libncurses-dev &> /dev/null || [ -f /usr/include/ncursesw/ncurses.h ] || [ -f /usr/include/ncurses/ncurses.h ]; then
                    FOUND_PKGS+=(${pkg})
                else
                    MISSING_PKGS+=(${pkg})
                fi
                ;;
            *)
                check_dpkg $pkg || true
                ;;
        esac
    done

    # 去重
    FOUND_PKGS=($(echo "${FOUND_PKGS[@]}" | tr ' ' '\n' | sort -u))
    MISSING_PKGS=($(echo "${MISSING_PKGS[@]}" | tr ' ' '\n' | sort -u))

    # 显示结果
    for pkg in "${FOUND_PKGS[@]}"; do
        log_info "  ✓ ${pkg}"
    done

    for pkg in "${MISSING_PKGS[@]}"; do
        log_warn "  ✗ ${pkg} (not found)"
    done

    # 处理缺失的依赖包
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${MISSING_PKGS[*]}"
        echo ""
        log_info "Install missing packages with:"
        echo -e "  ${YELLOW}sudo apt install ${MISSING_PKGS[*]}${NC}"
        echo ""
        
        # 强制启用交互式提示，即使在非交互式环境中
        # 尝试从终端读取，如果失败则从标准输入读取
        if [ -e /dev/tty ]; then
            echo -n "Would you like to install these dependencies automatically? (y/n): "
            read answer < /dev/tty
        else
            echo -n "Would you like to install these dependencies automatically? (y/n): "
            read answer
        fi
        
        case "$answer" in
            [Yy]*)
                # 检查sudo权限
                if ! sudo -v &>/dev/null; then
                    log_error "需要sudo权限来安装依赖包"
                    return 1
                fi
                log_info "Installing dependencies..."
                sudo apt update && sudo apt install -y ${MISSING_PKGS[*]}
                if [ $? -eq 0 ]; then
                    log_info "Dependencies installed successfully"
                    return 0
                else
                    log_error "Failed to install dependencies"
                    return 1
                fi
                ;;
            [Nn]*)
                log_info "Installation skipped"
                return 1
                ;;
            *)
                log_info "Invalid answer, installation skipped"
                return 1
                ;;
        esac
    else
        log_info "All ${target_name:-host} dependencies found"
        return 0
    fi
}

# 检查所有依赖包
check_all_dependencies() {
    check_dependencies ALL_PKGS "所有"
}

# 检查U-Boot依赖包
check_uboot_dependencies() {
    check_dependencies UBOOT_PKGS "U-Boot"
}

# 检查Linux依赖包
check_linux_dependencies() {
    check_dependencies LINUX_PKGS "Linux"
}

# 检查BusyBox依赖包
check_busybox_dependencies() {
    check_dependencies BUSYBOX_PKGS "BusyBox"
}

# 显示帮助信息
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

检查主机依赖包并可选安装缺失的依赖。

OPTIONS:
    --stage <1|2|3>      检查特定构建阶段的依赖包
                         1 = U-Boot依赖
                         2 = Linux依赖（NXP BSP & Mainline）
                         3 = BusyBox依赖
    -h, --help           显示此帮助信息

EXAMPLES:
    $(basename "$0")              # 检查所有依赖包
    $(basename "$0") --stage 1    # 只检查U-Boot依赖包
    $(basename "$0") --help       # 显示帮助信息

EOF
}

# 主函数（如果直接运行）
if [[ "$(basename "$0")" == "env-init.sh" ]]; then
    if [ $# -eq 0 ]; then
        check_all_dependencies
    elif [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        show_help
    elif [ "$1" == "--stage" ] && [ $# -eq 2 ]; then
        case "$2" in
            1)
                log_info "检查 Stage 1 (U-Boot) 依赖包..."
                check_uboot_dependencies
                ;;
            2)
                log_info "检查 Stage 2 (Linux) 依赖包..."
                check_linux_dependencies
                ;;
            3)
                log_info "检查 Stage 3 (BusyBox) 依赖包..."
                check_busybox_dependencies
                ;;
            *)
                echo "Usage: $0 [--stage 1|2|3]"
                echo "Use '$0 --help' for more information"
                exit 1
                ;;
        esac
    else
        echo "Usage: $0 [--stage 1|2|3]"
        echo "Use '$0 --help' for more information"
        exit 1
    fi
fi
