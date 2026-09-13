#!/bin/bash
#
# 顶层驱动构建脚本
# 统一的驱动构建入口
#
# 用法：
#   ./scripts/build_driver.sh [选项] [驱动] [板卡]
#
# 选项：
#   --list              列出所有可用驱动
#   --all               构建所有驱动
#   --board=NAME        只构建指定板卡的驱动
#   --help              显示帮助信息
#
# 示例：
#   ./scripts/build_driver.sh --list                              # 列出所有驱动
#   ./scripts/build_driver.sh led alpha-board                     # 构建LED驱动
#   ./scripts/build_driver.sh --all                               # 构建所有驱动
#   ./scripts/build_driver.sh --all --board=alpha-board           # 构建alpha板的所有驱动

# 注意：不使用 set -e，某些命令(如read)可能返回非零值但不应导致脚本退出

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载共享构建库
source "${SCRIPT_DIR}/../lib/driver_buildlib.sh"

# 默认参数
ACTION="build"
DRIVER_NAME=""
BOARD_NAME=""
KERNEL_TYPE="${DEFAULT_KERNEL_TYPE}"

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename "$0") [选项] [驱动] [板卡]

选项:
  --list              列出所有可用的驱动
  --all               构建所有驱动
  --clean             清理构建产物（仅清理最终产物）
  --deep-clean        深度清理（清理最终产物和中间构建文件）
  --board=NAME        只构建指定板卡的驱动
  --help, -h          显示此帮助信息

参数:
  驱动                驱动名称 (如: led, framework, spi)
  板卡                板卡名称 (如: alpha-board, beta-board，默认: alpha-board)

示例:
  # 列出所有可用驱动
  $(basename "$0") --list

  # 构建指定驱动
  $(basename "$0") led alpha-board
  $(basename "$0") example-driver

  # 构建所有驱动
  $(basename "$0") --all

  # 只构建alpha板的所有驱动
  $(basename "$0") --all --board=alpha-board

  # 清理指定驱动的构建产物
  $(basename "$0") --clean example-driver

  # 清理所有驱动的构建产物
  $(basename "$0") --clean --all

  # 深度清理指定驱动（包括中间构建文件）
  $(basename "$0") --deep-clean example-driver

  # 深度清理所有驱动
  $(basename "$0") --deep-clean --all

内核:
  mainline 主线树（单轨，不可选）

产物位置:
  out/driver_artifacts/<驱动>/<板卡>/

EOF
}

# 列出所有可用驱动
list_drivers() {
    log_info "========================================"
    log_info "可用驱动列表"
    log_info "========================================"

    local driver_count=0
    local board_count=0

    for driver_dir in "${PROJECT_ROOT}"/driver/*/; do
        if [[ -d "$driver_dir" ]]; then
            local driver=$(basename "$driver_dir")
            # 跳过非驱动目录
            if [[ "$driver" == "base_driver" ]] || [[ "$driver" == "device_tree" ]] || [[ "$driver" == "firmwares" ]] || [[ "$driver" == "application" ]]; then
                continue
            fi

            log_info ""
            log_info "📦 $driver"
            driver_count=$((driver_count + 1))

            # 列出该驱动下的所有板卡
            for board_dir in "$driver_dir"*/; do
                if [[ -d "$board_dir" ]]; then
                    local board=$(basename "$board_dir")
                    local has_makefile=0
                    local has_source=0

                    # 检查是否有Makefile和源码
                    [[ -f "${board_dir}/Makefile" ]] && has_makefile=1
                    [[ $(find "$board_dir" -maxdepth 1 -name "*.c" -type f | wc -l) -gt 0 ]] && has_source=1

                    if [[ $has_makefile -eq 1 || $has_source -eq 1 ]]; then
                        local status="✓"
                        [[ $has_makefile -eq 1 ]] && status="${status} Makefile"
                        [[ $has_source -eq 1 ]] && status="${status} 源码"
                        log_info "  └─ ${board} [${status}]"
                        board_count=$((board_count + 1))
                    fi
                fi
            done
        fi
    done

    log_info ""
    log_info "========================================"
    log_info "总计: $driver_count 个驱动, $board_count 个板卡配置"
    log_info "========================================"
}

# 构建指定驱动
build_specific_driver() {
    local driver="$1"
    local board="${2:-alpha-board}"
    local kernel="${3:-$DEFAULT_KERNEL_TYPE}"

    log_info "========================================"
    log_info "构建驱动: $driver/$board"
    log_info "内核: $kernel"
    log_info "========================================"

    # 调用共享构建库
    if driver_build "$driver" "$board" "build" "$kernel"; then
        log_info ""
        log_info "📦 产物位置: ${PROJECT_ROOT}/out/driver_artifacts/${driver}/${board}/"
        log_info "========================================"

        # 构建成功后询问是否部署
        echo ""
        echo -e "${GREEN}构建成功！${NC}"
        echo -n "是否部署驱动? [Y/n]: "
        read -r response

        # 默认为是，除非用户明确输入 n 或 N
        if [[ -z "$response" ]] || [[ "$response" =~ ^[Yy]$ ]]; then
            echo ""
            log_info "开始部署驱动..."
            # 调用部署脚本
            "${SCRIPT_DIR}/deploy_driver.sh" "$driver" "$board"
        else
            log_info "跳过部署"
        fi
    else
        log_error ""
        log_error "构建失败，跳过部署"
        return 1
    fi
}

# 清理指定驱动
clean_specific_driver() {
    local driver="$1"
    local board="${2:-alpha-board}"

    log_info "========================================"
    log_info "清理驱动: $driver/$board"
    log_info "========================================"

    # 调用共享构建库
    driver_build "$driver" "$board" "clean" ""

    log_info ""
    log_info "========================================"
}

# 深度清理指定驱动
deep_clean_specific_driver() {
    local driver="$1"
    local board="${2:-alpha-board}"

    log_info "========================================"
    log_info "深度清理驱动: $driver/$board"
    log_info "========================================"

    # 调用共享构建库
    driver_build "$driver" "$board" "deep_clean" ""

    log_info ""
    log_info "========================================"
}

# 构建所有驱动
build_all_drivers() {
    local target_board="${1}"
    local kernel="${2:-$DEFAULT_KERNEL_TYPE}"
    local total=0
    local success=0
    local failed=0

    log_info "========================================"
    log_info "批量构建所有驱动"
    [[ -n "$target_board" ]] && log_info "板卡过滤: $target_board"
    log_info "内核: $kernel"
    log_info "========================================"
    log_info ""

    for driver_dir in "${PROJECT_ROOT}"/driver/*/; do
        if [[ -d "$driver_dir" ]]; then
            local driver=$(basename "$driver_dir")
            # 跳过非驱动目录
            if [[ "$driver" == "base_driver" ]] || [[ "$driver" == "device_tree" ]] || [[ "$driver" == "firmwares" ]] || [[ "$driver" == "application" ]]; then
                continue
            fi

            # 遍历板卡
            for board_dir in "$driver_dir"*/; do
                if [[ -d "$board_dir" ]]; then
                    local board=$(basename "$board_dir")

                    # 板卡过滤
                    if [[ -n "$target_board" && "$board" != "$target_board" ]]; then
                        continue
                    fi

                    # 检查是否有Makefile或源码
                    if [[ -f "${board_dir}/Makefile" ]] || [[ $(find "$board_dir" -maxdepth 1 -name "*.c" -type f | wc -l) -gt 0 ]]; then
                        total=$((total + 1))

                        log_info "[$total] 构建: $driver/$board"

                        if driver_build "$driver" "$board" "build" "$kernel"; then
                            success=$((success + 1))
                            log_info "  ✓ 成功"
                        else
                            failed=$((failed + 1))
                            log_error "  ✗ 失败"
                        fi
                        log_info ""
                    fi
                fi
            done
        fi
    done

    log_info "========================================"
    log_info "构建完成"
    log_info "========================================"
    log_info "总计: $total | 成功: $success | 失败: $failed"
    log_info "========================================"

    # 如果有失败，返回非零退出码
    [[ $failed -eq 0 ]]
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            list_drivers
            exit 0
            ;;
        --clean)
            ACTION="clean"
            shift
            if [[ $# -gt 0 && "$1" == "--all" ]]; then
                DRIVER_NAME="--all"
                shift
            fi
            ;;
        --deep-clean)
            ACTION="deep_clean"
            shift
            if [[ $# -gt 0 && "$1" == "--all" ]]; then
                DRIVER_NAME="--all"
                shift
            fi
            ;;
        --all)
            if [[ "$ACTION" != "clean" ]]; then
                ACTION="all"
            fi
            shift
            ;;
        --board=*)
            BOARD_NAME="${1#*=}"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            DRIVER_NAME="$1"
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                BOARD_NAME="$1"
                shift
            fi
            ;;
    esac
done

# 执行相应的操作
case $ACTION in
    all)
        build_all_drivers "$BOARD_NAME" "$KERNEL_TYPE"
        ;;
    clean)
        if [[ "$DRIVER_NAME" == "--all" || -z "$DRIVER_NAME" ]]; then
            # 清理所有驱动
            log_info "========================================"
            log_info "批量清理所有驱动"
            log_info "========================================"

            for driver_dir in "${PROJECT_ROOT}"/driver/*/; do
                if [[ -d "$driver_dir" ]]; then
                    driver=$(basename "$driver_dir")
                    # 跳过非驱动目录
                    if [[ "$driver" == "base_driver" ]] || [[ "$driver" == "device_tree" ]] || [[ "$driver" == "firmwares" ]] || [[ "$driver" == "application" ]]; then
                        continue
                    fi

                    # 遍历板卡
                    for board_dir in "$driver_dir"*/; do
                        if [[ -d "$board_dir" ]]; then
                            board=$(basename "$board_dir")
                            driver_build "$driver" "$board" "clean" ""
                        fi
                    done
                fi
            done

            log_info "========================================"
            log_info "✓ 清理完成"
            log_info "========================================"
        else
            # 清理指定驱动
            clean_specific_driver "$DRIVER_NAME" "$BOARD_NAME"
        fi
        ;;
    deep_clean)
        if [[ "$DRIVER_NAME" == "--all" || -z "$DRIVER_NAME" ]]; then
            # 深度清理所有驱动
            log_info "========================================"
            log_info "批量深度清理所有驱动"
            log_info "========================================"

            for driver_dir in "${PROJECT_ROOT}"/driver/*/; do
                if [[ -d "$driver_dir" ]]; then
                    driver=$(basename "$driver_dir")
                    # 跳过非驱动目录
                    if [[ "$driver" == "base_driver" ]] || [[ "$driver" == "device_tree" ]] || [[ "$driver" == "firmwares" ]] || [[ "$driver" == "application" ]]; then
                        continue
                    fi

                    # 遍历板卡
                    for board_dir in "$driver_dir"*/; do
                        if [[ -d "$board_dir" ]]; then
                            board=$(basename "$board_dir")
                            driver_build "$driver" "$board" "deep_clean" ""
                        fi
                    done
                fi
            done

            log_info "========================================"
            log_info "✓ 深度清理完成"
            log_info "========================================"
        else
            # 深度清理指定驱动
            deep_clean_specific_driver "$DRIVER_NAME" "$BOARD_NAME"
        fi
        ;;
    build)
        if [[ -z "$DRIVER_NAME" ]]; then
            log_error "缺少驱动名称参数"
            log_info "用法: $(basename "$0") <驱动> [板卡]"
            log_info "使用 --list 查看可用驱动"
            exit 1
        fi
        build_specific_driver "$DRIVER_NAME" "$BOARD_NAME" "$KERNEL_TYPE"
        ;;
esac
