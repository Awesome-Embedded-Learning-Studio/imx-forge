#!/bin/bash
#
# 共享的驱动构建库
# 被 scripts/build_driver.sh 和 driver/*/build.sh 调用
#
#
# 注意：不使用 set -e，因为某些命令(如read)可能返回非零值
# 这是正常的，不应该导致脚本退出


# 防止重复加载（简单检查，不在主上下文中使用return）
if [[ -z "$DRIVER_BUILDLIB_LOADED" ]]; then
    DRIVER_BUILDLIB_LOADED=1
fi

# 颜色定义
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $1"; }

# 项目根目录（自动检测）
DRIVER_PROJECT_ROOT="${DRIVER_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 加载配置文件（如果存在）
CONFIG_FILE="${DRIVER_PROJECT_ROOT}/scripts/driver_helper/driver_helper.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    log_debug "加载配置文件: $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# 配置参数
ARCH="${ARCH:-arm}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-none-linux-gnueabihf-}"

# 内核类型配置（单轨：仅 mainline 树；键名保留 "mainline" 供内部函数引用）
declare -A KERNEL_CONFIGS
KERNEL_CONFIGS[mainline]="linux_mainline|out/linux|imx_aes_mainline_defconfig|主线内核"

# 默认内核类型
DEFAULT_KERNEL_TYPE="${DEFAULT_KERNEL_TYPE:-mainline}"

#
# 检查并配置内核
#
ensure_kernel_configured() {
    local kernel_type="$1"
    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    local kdir="${DRIVER_PROJECT_ROOT}/third_party/${kernel_name}"
    local kobj="${DRIVER_PROJECT_ROOT}/${kobj_dir}"

    # 检查内核源码是否存在
    if [[ ! -d "$kdir" ]]; then
        log_error "内核源码目录不存在: $kdir"
        return 1
    fi

    # 检查是否已配置
    if [[ -f "${kobj}/.config" ]]; then
        log_debug "内核已配置: $kernel_desc"
        return 0
    fi

    log_warn "内核未配置，正在自动配置..."
    log_info "  内核类型: $kernel_desc ($kernel_name)"
    log_info "  配置文件: $defconfig"

    # 确保输出目录存在
    mkdir -p "$kobj"

    # 配置内核
    cd "$kdir"
    if make O="$kobj" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$defconfig" >/dev/null 2>&1; then
        log_info "✓ 内核配置完成"
        return 0
    else
        log_error "内核配置失败"
        log_error "命令: make O=$kobj ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE $defconfig"
        log_error "内核目录: $kdir"
        log_error "defconfig: $defconfig"
        # 重新运行以显示详细错误
        make O="$kobj" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$defconfig" 2>&1 | tail -20 || true
        return 1
    fi
}

#
# 检查内核是否已编译
#
check_kernel_built() {
    local kernel_type="$1"
    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    local kdir="${DRIVER_PROJECT_ROOT}/third_party/${kernel_name}"
    local kobj="${DRIVER_PROJECT_ROOT}/${kobj_dir}"

    log_debug "检查内核编译状态: $kernel_desc"

    # 检查关键文件是否存在
    local missing_files=()

    # 检查配置文件
    if [[ ! -f "${kobj}/.config" ]]; then
        missing_files+=("内核配置文件: .config")
    fi

    # 检查必要的头文件
    if [[ ! -f "${kobj}/include/generated/autoconf.h" ]]; then
        missing_files+=("autoconf.h")
    fi

    # 检查Module.symvers（编译驱动需要内核导出的符号信息）
    if [[ ! -f "${kobj}/Module.symvers" ]]; then
        missing_files+=("Module.symvers (需要编译内核 vmlinux)")
    fi

    # 检查编译产物（选择性地检查，避免强制完整编译）
    local kernel_image=""
    case "$ARCH" in
        arm)
            kernel_image="${kobj}/arch/arm/boot/zImage"
            ;;
        *)
            kernel_image="${kobj}/vmlinux"
            ;;
    esac

    # 如果缺少关键文件，给出详细提示
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "========================================"
        log_error "❌ 内核未正确编译"
        log_error "========================================"
        log_error "内核类型: $kernel_desc ($kernel_name)"
        log_error "内核目录: $kdir"
        log_error "输出目录: $kobj"
        log_error ""
        log_error "缺少以下文件："
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
        log_error ""
        log_error "💡 解决方案："
        log_error "   1. 完整编译内核："
        log_error "      cd $kdir"
        log_error "      make O=$kobj ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE -j\$(nproc)"
        log_error ""
        log_error "   2. 或者使用快速编译（仅生成必要文件）："
        log_error "      cd $kdir"
        log_error "      make O=$kobj ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE vmlinux -j\$(nproc)"
        log_error ""
        log_error "📌 重要说明"
        log_error "   你需要确保："
        log_error "   1.1 至少编译过一次 vmlinux（或完整内核），以生成 Module.symvers"
        log_error "   1.2. ln -s vmlinux.symvers $kobj/Module.symvers"
        log_error ""
        log_error "========================================"
        return 1
    fi

    log_debug "✓ 内核编译检查通过"
    return 0
}

#
# 编译驱动模块
#
build_driver_module() {
    local driver_dir="$1"
    local output_dir="$2"
    local kernel_type="${3:-$DEFAULT_KERNEL_TYPE}"

    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    local kdir="${DRIVER_PROJECT_ROOT}/third_party/${kernel_name}"
    local kobj="${DRIVER_PROJECT_ROOT}/${kobj_dir}"

    log_info "编译驱动模块..."
    log_debug "  驱动目录: $driver_dir"
    log_debug "  内核: $kernel_desc"
    log_debug "  输出: $output_dir"

    # 确保输出目录存在
    mkdir -p "$output_dir"

    # 编译
    cd "$driver_dir"
    local build_output
    build_output=$(make \
        ARCH="$ARCH" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        -C "$kdir" \
        M="$driver_dir" \
        O="$kobj" \
        modules 2>&1)
    local build_status=$?

    if [[ $build_status -ne 0 ]]; then
        log_error "驱动编译失败"
        log_error "编译错误:"
        echo "$build_output" | head -50
        return 1
    fi

    # 复制.ko文件到输出目录
    local ko_count=0
    for ko_file in *.ko; do
        if [[ -f "$ko_file" ]]; then
            cp "$ko_file" "$output_dir/"
            ko_count=$((ko_count + 1))
        fi
    done

    if [[ $ko_count -gt 0 ]]; then
        log_info "✓ 编译完成 ($ko_count 个模块)"
        return 0
    else
        log_warn "未找到.ko文件"
        return 1
    fi
}

#
# 编译设备树
#
build_device_tree() {
    local driver_dir="$1"
    local output_dir="$2"
    local kernel_type="${3:-$DEFAULT_KERNEL_TYPE}"

    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    local kdir="${DRIVER_PROJECT_ROOT}/third_party/${kernel_name}"
    local kobj="${DRIVER_PROJECT_ROOT}/${kobj_dir}"

    # 优先在新的设备树目录中查找：driver/device_tree/<board>/<function>/
    local driver_name=$(basename $(dirname "$driver_dir"))
    local board_name=$(basename "$driver_dir")
    local device_tree_dir="${DRIVER_PROJECT_ROOT}/driver/device_tree/${board_name}/${driver_name}"

    log_debug "  查找设备树目录: $device_tree_dir"

    # 查找.dts文件（优先新位置，回退到驱动目录）
    local dts_files=()
    if [[ -d "$device_tree_dir" ]]; then
        dts_files=($(find "$device_tree_dir" -maxdepth 1 -name "*.dts" -type f))
        log_debug "  在新位置找到 ${#dts_files[@]} 个设备树文件"
    fi

    # 如果新位置没找到，在驱动目录中查找
    if [[ ${#dts_files[@]} -eq 0 ]]; then
        dts_files=($(find "$driver_dir" -maxdepth 1 -name "*.dts" -type f))
        log_debug "  在驱动目录找到 ${#dts_files[@]} 个设备树文件"
    fi

    if [[ ${#dts_files[@]} -eq 0 ]]; then
        log_debug "未找到设备树文件"
        return 0
    fi

    log_info "编译设备树..."

    # 设置include搜索路径
    local dts_include_dirs="${kdir}/arch/arm/boot/dts"
    if [[ -d "${kdir}/arch/arm/boot/dts/nxp/imx" ]]; then
        dts_include_dirs="${dts_include_dirs} ${kdir}/arch/arm/boot/dts/nxp/imx"
    fi

    # 添加主板设备树目录到include路径
    local board_dts_dir="${DRIVER_PROJECT_ROOT}/driver/device_tree/${board_name}/linux"
    if [[ -d "$board_dts_dir" ]]; then
        dts_include_dirs="${dts_include_dirs} ${board_dts_dir}"
    fi

    log_debug "  Include路径: $dts_include_dirs"

    # 编译每个.dts文件
    local dtb_count=0
    for dts_file in "${dts_files[@]}"; do
        local dts_name=$(basename "$dts_file" .dts)
        local dtb_file="${output_dir}/${dts_name}.dtb"

        # 构建include参数（使用数组）
        local include_args_array=()
        for inc_dir in $dts_include_dirs; do
            include_args_array+=("-i" "$inc_dir")
        done

        # 按内核方式：先用gcc预处理，再用dtc编译
        local gcc_args=(
            -E -nostdinc -P -x assembler-with-cpp
            -I "${kdir}/arch/arm/boot/dts"
            -I "${kdir}/arch/arm/boot/dts/nxp/imx"
            -I "${kdir}/include"
            -I "$board_dts_dir"
            -undef -D__DTS__
        )

        # 创建临时文件存储预处理结果
        local dtc_tmp="/tmp/dtc-$(basename "$dts_file" .dts).tmp"

        # 先用gcc预处理，再用dtc编译
        local dtc_output
        dtc_output=$(gcc "${gcc_args[@]}" -o "$dtc_tmp" "$dts_file" 2>&1 && \
                    dtc -I dts -O dtb "${include_args_array[@]}" -o "$dtb_file" "$dtc_tmp" 2>&1)
        local dtc_status=$?

        # 清理临时文件
        rm -f "$dtc_tmp"

        if [[ $dtc_status -eq 0 && -f "$dtb_file" ]]; then
            dtb_count=$((dtb_count + 1))
            local dtb_size=$(ls -lh "$dtb_file" | awk '{print $5}')
            log_debug "  ✓ ${dts_name}.dtb ($dtb_size)"
        else
            log_warn "  ✗ ${dts_name}.dts 编译失败"
            log_warn "  错误信息: $dtc_output"
        fi
    done

    if [[ $dtb_count -gt 0 ]]; then
        log_info "✓ 编译完成 ($dtb_count 个设备树)"
        return 0
    else
        log_warn "设备树编译失败"
        return 1
    fi
}

#
# 生成构建信息
#
generate_build_info() {
    local driver_dir="$1"
    local output_dir="$2"
    local kernel_type="${3:-$DEFAULT_KERNEL_TYPE}"

    local info_file="${output_dir}/build_info.txt"
    local build_date=$(date '+%Y-%m-%d %H:%M:%S')
    local build_user=$(whoami)@$(hostname)

    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    cat > "$info_file" << EOF
驱动构建信息
================
构建时间: $build_date
构建用户: $build_user
内核类型: $kernel_desc ($kernel_name)
驱动目录: $driver_dir

产物文件:
EOF

    # 列出.ko文件
    for ko_file in "$output_dir"/*.ko; do
        if [[ -f "$ko_file" ]]; then
            local ko_name=$(basename "$ko_file")
            local ko_size=$(ls -lh "$ko_file" | awk '{print $5}')
            echo "  - $ko_name ($ko_size)" >> "$info_file"
        fi
    done

    # 列出.dtb文件
    for dtb_file in "$output_dir"/*.dtb; do
        if [[ -f "$dtb_file" ]]; then
            local dtb_name=$(basename "$dtb_file")
            local dtb_size=$(ls -lh "$dtb_file" | awk '{print $5}')
            echo "  - $dtb_name ($dtb_size)" >> "$info_file"
        fi
    done

    log_debug "构建信息已生成: $info_file"
}

#
# 清理构建产物
#
clean_driver_artifacts() {
    local output_dir="$1"

    if [[ -d "$output_dir" ]]; then
        log_info "清理构建产物: $output_dir"
        rm -rf "$output_dir"
        log_info "✓ 清理完成"
    else
        log_debug "无需清理: $output_dir 不存在"
    fi
}

#
# 深度清理构建产物（包括中间文件）
#
deep_clean_driver_artifacts() {
    local output_dir="$1"
    local driver_dir="$2"

    # 1. 清理最终产物
    if [[ -d "$output_dir" ]]; then
        log_info "清理最终产物: $output_dir"
        rm -rf "$output_dir"
    fi

    # 2. 清理中间构建文件
    if [[ -d "$driver_dir" ]]; then
        log_info "清理中间构建文件: $driver_dir"

        # 删除常见的内核构建中间文件
        log_debug "  删除 .o, .ko, .mod, .cmd 等文件"
        find "$driver_dir" -maxdepth 1 \
            \( -name "*.o" -o \
               -name "*.ko" -o \
               -name "*.mod" -o \
               -name "*.mod.c" -o \
               -name "*.mod.o" -o \
               -name "*.cmd" -o \
               -name "Module.symvers" -o \
               -name "modules.order" \) -delete 2>/dev/null || true

        # 删除 .tmp_versions 目录
        log_debug "  删除 .tmp_versions 目录"
        find "$driver_dir" -maxdepth 1 -name ".tmp_versions" -type d -exec rm -rf {} + 2>/dev/null || true

        # 运行 make clean 以确保彻底清理
        cd "$driver_dir"
        make clean >/dev/null 2>&1 || true

        log_info "✓ 深度清理完成"
    else
        log_debug "驱动目录不存在: $driver_dir"
    fi
}

#
# 主构建函数
#
driver_build() {
    local driver_name="$1"
    local board="${2:-${DEFAULT_BOARD:-alpha-board}}"
    local action="${3:-build}"
    local kernel_type="${4:-$DEFAULT_KERNEL_TYPE}"

    local driver_dir="${DRIVER_PROJECT_ROOT}/driver/${driver_name}/${board}"
    local output_dir="${DRIVER_PROJECT_ROOT}/out/driver_artifacts/${driver_name}/${board}"

    # 检查驱动目录是否存在
    if [[ ! -d "$driver_dir" ]]; then
        log_error "驱动目录不存在: $driver_dir"
        return 1
    fi

    case $action in
        build)
            log_info "🔨 构建驱动: ${driver_name}/${board}"
            log_info "========================================"

            # 检查内核是否已配置
            ensure_kernel_configured "$kernel_type" || return 1

            # 检查内核是否已编译
            check_kernel_built "$kernel_type" || return 1

            # 编译驱动模块
            build_driver_module "$driver_dir" "$output_dir" "$kernel_type" || return 1

            # 编译设备树
            build_device_tree "$driver_dir" "$output_dir" "$kernel_type"

            # 生成构建信息
            generate_build_info "$driver_dir" "$output_dir" "$kernel_type"

            log_info "========================================"
            log_info "✓ 构建完成: $output_dir"
            ;;
        clean)
            log_info "🧹 清理驱动: ${driver_name}/${board}"
            clean_driver_artifacts "$output_dir"

            # 也清理本地目录的构建产物
            cd "$driver_dir"
            make clean >/dev/null 2>&1 || true
            log_info "✓ 清理完成"
            ;;
        deep_clean)
            log_info "🧹 深度清理驱动: ${driver_name}/${board}"
            deep_clean_driver_artifacts "$output_dir" "$driver_dir"
            log_info "✓ 深度清理完成"
            ;;
        *)
            log_error "未知操作: $action"
            log_info "支持的操作: build, clean, deep_clean"
            return 1
            ;;
    esac
}

log_debug "驱动构建库已加载"
