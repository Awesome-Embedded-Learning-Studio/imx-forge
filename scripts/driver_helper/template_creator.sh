#!/bin/bash
#
# 交互式驱动创建脚本
# 基于example-driver模板创建新的驱动目录结构
#

# 加载共享库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/driver_buildlib.sh"

# 模板路径
TEMPLATE_DIR="${PROJECT_ROOT}/driver/example-driver/alpha-board"
DRIVER_BASE_DIR="${PROJECT_ROOT}/driver"

# 保留字列表（不能作为驱动名）
RESERVED_WORDS=("module" "init" "exit" "kernel" "linux" "driver" "device" "board" "framework" "mainline" "test")

# ==============================================================================
# 验证函数
# ==============================================================================

validate_driver_name() {
    local name="$1"

    # 检查长度
    if [[ ${#name} -lt 2 || ${#name} -gt 30 ]]; then
        log_error "驱动名长度必须在2-30个字符之间"
        return 1
    fi

    # 检查字符集（只允许小写字母、数字、下划线、连字符）
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        log_error "驱动名只能包含小写字母、数字、下划线和连字符"
        return 1
    fi

    # 检查保留字
    for word in "${RESERVED_WORDS[@]}"; do
        if [[ "$name" == "$word" ]]; then
            log_error "'$name' 是保留字，不能用作驱动名"
            return 1
        fi
    done

    return 0
}

validate_board_name() {
    local name="$1"

    # 基本检查：不能为空，不能包含特殊字符
    if [[ -z "$name" ]]; then
        log_error "板名不能为空"
        return 1
    fi

    if [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
        log_error "板名只能包含字母、数字、下划线和连字符"
        return 1
    fi

    return 0
}

validate_param_name() {
    local name="$1"

    # C变量命名规则
    if [[ ! "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_error "参数名必须符合C变量命名规则：字母或下划线开头，只包含字母、数字、下划线"
        return 1
    fi

    return 0
}

check_duplicate_driver() {
    local driver_name="$1"
    local board_name="$2"
    local target_dir="${DRIVER_BASE_DIR}/${driver_name}/${board_name}"

    if [[ -d "$target_dir" ]]; then
        log_warn "驱动目录已存在: $target_dir"
        return 1
    fi

    return 0
}

# ==============================================================================
# 交互提示函数
# ==============================================================================

prompt_driver_info() {
    log_info "=== 阶段 1: 驱动基本信息 ==="

    # 获取驱动名
    while true; do
        echo ""
        read -p "请输入驱动名称 (2-30字符, 小写字母/数字/_/-): " driver_name

        if validate_driver_name "$driver_name"; then
            break
        fi
    done

    # 显示现有板子并获取板名
    echo ""
    log_info "项目中现有的板子:"
    if [[ -d "${DRIVER_BASE_DIR}/example-driver" ]]; then
        find "${DRIVER_BASE_DIR}" -maxdepth 2 -type d -name "*-board" 2>/dev/null | \
            sed 's|.*/||' | sort -u | while read board; do
            echo "  - $board"
        done
    fi

    echo ""
    read -p "请输入板名 [默认: alpha-board]: " board_name
    board_name="${board_name:-alpha-board}"

    if ! validate_board_name "$board_name"; then
        return 1
    fi

    # 检查重复
    if ! check_duplicate_driver "$driver_name" "$board_name"; then
        read -p "是否覆盖现有驱动? (y/N): " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "将覆盖现有驱动目录"
            DRIVER_OVERWRITE=1
        else
            log_error "取消操作"
            return 1
        fi
    fi

    DRIVER_NAME="$driver_name"
    BOARD_NAME="$board_name"

    # 提取用于C代码的基础名称（去掉 序号_tutorial_ 前缀）
    if [[ "$DRIVER_NAME" =~ ^[0-9]+_tutorial_(.+)$ ]]; then
        DRIVER_BASE_NAME="${BASH_REMATCH[1]}"
    else
        DRIVER_BASE_NAME="$DRIVER_NAME"
    fi

    # C安全名称：将连字符转为下划线
    DRIVER_C_NAME="${DRIVER_BASE_NAME//-/_}"

    return 0
}

prompt_metadata() {
    log_info ""
    log_info "=== 阶段 2: 元数据信息 ==="

    # 尝试从git获取作者名
    local git_author=""
    if command -v git &>/dev/null && [[ -d "${PROJECT_ROOT}/.git" ]]; then
        git_author=$(git config user.name 2>/dev/null)
    fi

    echo ""
    if [[ -n "$git_author" ]]; then
        read -p "请输入作者名 [默认: $git_author]: " author
        author="${author:-$git_author}"
    else
        read -p "请输入作者名: " author
    fi

    # 许可证选择
    echo ""
    log_info "许可证选项:"
    echo "  1) GPL      (推荐用于内核模块)"
    echo "  2) MIT"
    echo "  3) Apache-2.0"
    echo "  4) BSD"
    read -p "请选择许可证 [默认: 1]: " license_choice
    license_choice="${license_choice:-1}"

    case "$license_choice" in
        1) license="GPL" ;;
        2) license="MIT" ;;
        3) license="Apache-2.0" ;;
        4) license="BSD" ;;
        *) license="GPL" ;;
    esac

    # 描述
    echo ""
    read -p "请输入驱动描述 (简短说明): " description

    DRIVER_AUTHOR="$author"
    DRIVER_LICENSE="$license"
    DRIVER_DESCRIPTION="$description"
    return 0
}

prompt_module_parameters() {
    log_info ""
    log_info "=== 阶段 3: 模块参数配置 ==="

    echo ""
    read -p "需要多少个模块参数? [0-5, 默认: 0]: " param_count
    param_count="${param_count:-0}"

    # 验证范围
    if [[ ! "$param_count" =~ ^[0-5]$ ]]; then
        log_warn "无效的参数数量，使用默认值: 0"
        param_count=0
    fi

    MODULE_PARAMS=()

    # 如果没有参数，跳过参数配置
    if [[ "$param_count" -eq 0 ]]; then
        log_info "跳过模块参数配置"
        return 0
    fi

    for ((i=1; i<=param_count; i++)); do
        echo ""
        log_info "配置参数 $i/$param_count"

        # 参数名
        while true; do
            read -p "  参数名: " param_name
            if validate_param_name "$param_name"; then
                break
            fi
        done

        # 参数类型
        echo "  参数类型:"
        echo "    1) int     (整数)"
        echo "    2) bool    (布尔值)"
        echo "    3) charp   (字符串)"
        read -p "  选择 [默认: 1]: " type_choice
        type_choice="${type_choice:-1}"

        case "$type_choice" in
            1) param_type="int" ;;
            2) param_type="bool" ;;
            3) param_type="charp" ;;
            *) param_type="int" ;;
        esac

        # 默认值
        read -p "  默认值: " param_default

        # 描述
        read -p "  参数描述: " param_desc

        MODULE_PARAMS+=("$param_name|$param_type|$param_default|$param_desc")
    done

    return 0
}

prompt_kernel_config() {
    log_info ""
    log_info "=== 阶段 4: 内核配置 ==="

    echo ""
    log_info "内核类型选择:"
    echo "  1) mainline  (主线内核)"
    echo "  2) imx       (NXP BSP内核)"
    read -p "请选择内核类型 [默认: ${DEFAULT_KERNEL_TYPE}]: " kernel_choice

    if [[ -z "$kernel_choice" ]]; then
        KERNEL_TYPE="$DEFAULT_KERNEL_TYPE"
    else
        case "$kernel_choice" in
            1) KERNEL_TYPE="mainline" ;;
            2) KERNEL_TYPE="imx" ;;
            *) KERNEL_TYPE="$DEFAULT_KERNEL_TYPE" ;;
        esac
    fi

    log_info "注意: 内核类型可以在构建时通过 build_driver.sh --kernel 参数覆盖"

    return 0
}

confirm_and_generate() {
    log_info ""
    log_info "=== 阶段 5: 确认并生成 ==="

    echo ""
    echo "========== 配置摘要 =========="
    echo "驱动名称:     $DRIVER_NAME"
    echo "板名:         $BOARD_NAME"
    echo "作者:         $DRIVER_AUTHOR"
    echo "许可证:       $DRIVER_LICENSE"
    echo "描述:         $DRIVER_DESCRIPTION"
    echo "内核类型:     $KERNEL_TYPE"
    echo ""
    echo "模块参数:"
    for param in "${MODULE_PARAMS[@]}"; do
        IFS='|' read -r name type default desc <<< "$param"
        echo "  - $name ($type) = $default  # $desc"
    done
    echo ""
    echo "目标目录:    ${DRIVER_BASE_DIR}/${DRIVER_NAME}/${BOARD_NAME}/"
    echo "=============================="

    echo ""
    read -p "确认创建驱动? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "取消操作"
        return 1
    fi

    return 0
}

# ==============================================================================
# 模板生成函数
# ==============================================================================

generate_driver_source() {
    local target_dir="$1"
    local source_file="${target_dir}/${DRIVER_NAME}_driver.c"

    log_info "生成驱动源码: ${source_file}"

    # 读取模板
    local template_file="${TEMPLATE_DIR}/fake_driver.c"
    if [[ ! -f "$template_file" ]]; then
        log_error "模板文件不存在: $template_file"
        return 1
    fi

    # 开始生成源码
    cat > "$source_file" << 'EOF'
// 驱动源码
// 由 template_creator.sh 自动生成
//

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>

EOF

    # 添加模块参数
    local param_decls=""
    for param in "${MODULE_PARAMS[@]}"; do
        IFS='|' read -r name type default desc <<< "$param"

        case "$type" in
            int)
                echo "static int $name = $default;" >> "$source_file"
                ;;
            bool)
                echo "static bool $name = $default;" >> "$source_file"
                ;;
            charp)
                echo "static char *$name = \"$default\";" >> "$source_file"
                ;;
        esac

        echo "module_param($name, $type, 0644);" >> "$source_file"
        echo "MODULE_PARM_DESC($name, \"$desc\");" >> "$source_file"
        echo "" >> "$source_file"
    done

    # 添加初始化函数
    cat >> "$source_file" << INITEOF
// 模块初始化
static int __init ${DRIVER_C_NAME}_init(void)
{
	pr_info("=== ${DRIVER_DESCRIPTION} ===\\n");
INITEOF

    # 添加参数打印语句（如果有参数）
    if [[ ${#MODULE_PARAMS[@]} -gt 0 ]]; then
        for param in "${MODULE_PARAMS[@]}"; do
            IFS='|' read -r name type default desc <<< "$param"
            case "$type" in
                charp)
                    echo -e "\tpr_info(\"$name: %s\\\\n\", $name == NULL ? \"null\" : $name);" >> "$source_file"
                    ;;
                bool)
                    echo -e "\tpr_info(\"$name: %d\\\\n\", $name);" >> "$source_file"
                    ;;
                *)
                    echo -e "\tpr_info(\"$name: %d\\\\n\", $name);" >> "$source_file"
                    ;;
            esac
        done
    fi

    # 完成初始化函数
    cat >> "$source_file" << INITEOF2
	pr_info("========================\\n");
	return 0;
}

// 模块退出
static void __exit ${DRIVER_C_NAME}_exit(void)
{
	pr_info("=== ${DRIVER_C_NAME}驱动卸载成功 ===\\n");
	pr_info("========================\\n");
}

module_init(${DRIVER_C_NAME}_init);
module_exit(${DRIVER_C_NAME}_exit);

MODULE_LICENSE("${DRIVER_LICENSE}");
MODULE_AUTHOR("${DRIVER_AUTHOR}");
MODULE_DESCRIPTION("${DRIVER_DESCRIPTION}");
MODULE_VERSION("1.0");
INITEOF2

    log_info "✓ 源码生成完成"
    return 0
}

generate_makefile() {
    local target_dir="$1"
    local makefile="${target_dir}/Makefile"

    log_info "生成Makefile: ${makefile}"

    cat > "$makefile" << EOF
# ${DRIVER_DESCRIPTION} Makefile
#
# 由 template_creator.sh 自动生成

# Kernel module definition
obj-m := ${DRIVER_NAME}_driver.o

# ── 项目配置 ────────────────────────────────────────
PROJECT_ROOT := \$(shell realpath \$(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := \$(PROJECT_ROOT)/third_party/linux-\${KERNEL_TYPE}
KOBJ := \$(PROJECT_ROOT)/out/\${KERNEL_TYPE}

# 输出目录
OUTPUT_DIR := \$(PROJECT_ROOT)/out/driver_artifacts/${DRIVER_NAME}/${BOARD_NAME}

.PHONY: all modules clean install help

all: modules

modules:
	@echo "🔨 编译${DRIVER_NAME}驱动..."
	@mkdir -p \$(OUTPUT_DIR)
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR) O=\$(KOBJ) \\
		ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) modules
	@cp *.ko \$(OUTPUT_DIR)/ 2>/dev/null || true
	@echo "✓ 驱动编译完成: \$(OUTPUT_DIR)/${DRIVER_NAME}_driver.ko"

clean:
	@echo "🧹 清理构建产物..."
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR) O=\$(KOBJ) \\
		ARCH=\$(ARCH) CROSS_COMPILE=\$(CROSS_COMPILE) clean 2>/dev/null || true
	@rm -rf \$(OUTPUT_DIR)

install: modules
	@echo "📦 驱动位置: \$(OUTPUT_DIR)"
	@ls -lh \$(OUTPUT_DIR)/*.ko 2>/dev/null || echo "无.ko文件"
	@echo ""
	@echo "使用方法："
	@echo "  1. 构建驱动: scripts/driver_helper/build_driver.sh ${DRIVER_NAME} ${BOARD_NAME}"
	@echo "  2. 部署驱动: scripts/driver_helper/deploy_driver.sh ${DRIVER_NAME} ${BOARD_NAME}"
	@echo "  3. 测试驱动: insmod ${DRIVER_NAME}_driver.ko"
	@echo "  4. 查看日志: dmesg | tail"

help:
	@echo "${DRIVER_DESCRIPTION}"
	@echo ""
	@echo "用法："
	@echo "  make           - 编译驱动"
	@echo "  make clean     - 清理构建产物"
	@echo "  make install   - 显示使用说明"
	@echo ""
	@echo "产物位置: \$(OUTPUT_DIR)"
EOF

    log_info "✓ Makefile生成完成"
    return 0
}

generate_readme() {
    local target_dir="$1"
    local readme="${target_dir}/README.md"

    log_info "生成README.md: ${readme}"

    # 生成模块参数文档
    local param_docs=""
    for param in "${MODULE_PARAMS[@]}"; do
        IFS='|' read -r name type default desc <<< "$param"
        param_docs+="### $name\n\n"
        param_docs+="- **类型**: $type\n"
        param_docs+="- **默认值**: \`$default\`\n"
        param_docs+="- **描述**: $desc\n\n"
    done

    cat > "$readme" << EOF
# ${DRIVER_NAME} 驱动

${DRIVER_DESCRIPTION}

## 目录结构

\`\`\`
driver/${DRIVER_NAME}/
├── ${BOARD_NAME}/
│   ├── ${DRIVER_NAME}_driver.c    # 驱动源码
│   ├── Makefile                   # 构建文件
│   └── README.md                  # 本文件
\`\`\`

## 驱动说明

### ${DRIVER_NAME}_driver.c

这是一个由 \`template_creator.sh\` 生成的Linux内核模块。

**作者**: ${DRIVER_AUTHOR}
**许可证**: ${DRIVER_LICENSE}

## 快速开始

### 1. 编译驱动

\`\`\`bash
# 使用构建脚本（推荐）
./scripts/driver_helper/build_driver.sh ${DRIVER_NAME} ${BOARD_NAME}

# 或直接使用 Makefile
cd driver/${DRIVER_NAME}/${BOARD_NAME}
make
\`\`\`

预期输出：
\`\`\`
🔨 编译${DRIVER_NAME}驱动...
✓ 驱动编译完成: out/driver_artifacts/${DRIVER_NAME}/${BOARD_NAME}/${DRIVER_NAME}_driver.ko
\`\`\`

### 2. 部署到目标系统

\`\`\`bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh ${DRIVER_NAME} ${BOARD_NAME}

# 或手动复制
cp out/driver_artifacts/${DRIVER_NAME}/${BOARD_NAME}/${DRIVER_NAME}_driver.ko /path/to/target/lib/modules/
\`\`\`

### 3. 测试驱动

\`\`\`bash
# 在目标板上
insmod ${DRIVER_NAME}_driver.ko

# 查看日志
dmesg | tail

# 卸载驱动
rmmod ${DRIVER_NAME}_driver
\`\`\`

## 模块参数

$(echo "$param_docs")

### 参数使用示例

\`\`\`bash
# 传递模块参数
insmod ${DRIVER_NAME}_driver.ko param1=value1 param2=value2

# 查看当前参数值
cat /sys/module/${DRIVER_NAME}_driver/parameters/
\`\`\`

## 开发说明

### 修改驱动

1. 编辑源码文件: \`driver/${DRIVER_NAME}/${BOARD_NAME}/${DRIVER_NAME}_driver.c\`
2. 重新编译: \`./scripts/driver_helper/build_driver.sh ${DRIVER_NAME} ${BOARD_NAME}\`
3. 重新部署: \`./scripts/driver_helper/deploy_driver.sh ${DRIVER_NAME} ${BOARD_NAME}\`

### 内核类型切换

构建时可以指定内核类型：

\`\`\`bash
# 使用主线内核
./scripts/driver_helper/build_driver.sh ${DRIVER_NAME} ${BOARD_NAME} --kernel mainline

# 使用NXP BSP内核
./scripts/driver_helper/build_driver.sh ${DRIVER_NAME} ${BOARD_NAME} --kernel imx
\`\`\`

### 清理构建产物

\`\`\`bash
# 清理特定驱动
cd driver/${DRIVER_NAME}/${BOARD_NAME}
make clean

# 或使用构建脚本
./scripts/driver_helper/build_driver.sh --clean ${DRIVER_NAME} ${BOARD_NAME}
\`\`\`

## 故障排查

### 编译失败

\`\`\`bash
# 检查内核路径
ls third_party/linux-*/

# 检查交叉编译工具
\${CROSS_COMPILE}gcc --version

# 检查内核配置
ls out/*/linux/.config
\`\`\`

### 模块加载失败

\`\`\`bash
# 检查内核版本匹配
modinfo ${DRIVER_NAME}_driver.ko | grep vermagic
uname -r

# 查看详细错误
dmesg | tail -20
\`\`\`

## 相关资源

- [Linux内核模块开发指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- 项目构建系统: \`scripts/driver_helper/\`
- 驱动开发文档: \`document/tutorial/driver/\`

## 维护者

${DRIVER_AUTHOR}

---
*由 \`template_creator.sh\` 自动生成*
EOF

    log_info "✓ README.md生成完成"
    return 0
}

create_driver_directory() {
    local target_dir="${DRIVER_BASE_DIR}/${DRIVER_NAME}/${BOARD_NAME}"

    log_info ""
    log_info "创建驱动目录: ${target_dir}"

    # 如果需要覆盖，先删除现有目录
    if [[ "${DRIVER_OVERWRITE:-0}" == "1" && -d "$target_dir" ]]; then
        log_warn "删除现有目录..."
        rm -rf "$target_dir"
    fi

    # 创建目录
    mkdir -p "$target_dir" || {
        log_error "创建目录失败: $target_dir"
        return 1
    }

    # 生成文件
    generate_driver_source "$target_dir" || return 1
    generate_makefile "$target_dir" || return 1
    generate_readme "$target_dir" || return 1

    return 0
}

# ==============================================================================
# 帮助系统
# ==============================================================================

show_help() {
    cat << EOF
交互式驱动创建脚本 - 基于example-driver模板创建新驱动

用法:
  $0 [选项]

选项:
  -h, --help     显示此帮助信息

描述:
  此脚本通过交互式问答引导用户创建新的Linux内核模块驱动。
  生成的驱动包含：
    - 驱动源码文件 (.c)
    - Makefile构建文件
    - README.md文档

  生成的驱动完全集成到IMX-Forge构建系统中，可以通过以下命令使用：
    - build_driver.sh     : 编译驱动
    - deploy_driver.sh    : 部署驱动
    - review_driver.sh    : 查看驱动信息

示例:
  $0
  # 运行交互式创建向导

相关文件:
  模板目录: driver/example-driver/alpha-board/
  驱动输出: driver/<驱动名>/<板名>/

更多信息请参考: scripts/driver_helper/README.md
EOF
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    # 显示横幅
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   交互式驱动创建脚本"
    echo "   基于 example-driver 模板"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 检查模板是否存在
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        log_error "模板目录不存在: $TEMPLATE_DIR"
        log_error "请确保 example-driver 存在"
        exit 1
    fi

    # 执行交互流程
    prompt_driver_info || exit 1
    prompt_metadata || exit 1
    prompt_module_parameters || exit 1
    prompt_kernel_config || exit 1
    confirm_and_generate || exit 0

    # 创建驱动
    echo ""
    if create_driver_directory; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "✓ 驱动创建成功！"
        echo ""
        echo "位置: driver/${DRIVER_NAME}/${BOARD_NAME}/"
        echo ""
        echo "下一步："
        echo "  1. 编辑源码: vim driver/${DRIVER_NAME}/${BOARD_NAME}/${DRIVER_NAME}_driver.c"
        echo "  2. 构建驱动: scripts/driver_helper/build_driver.sh ${DRIVER_NAME} ${BOARD_NAME}"
        echo "  3. 部署驱动: scripts/driver_helper/deploy_driver.sh ${DRIVER_NAME} ${BOARD_NAME}"
        echo "  4. 查看帮助: scripts/driver_helper/build_driver.sh --help"
        echo ""
        echo "更多信息请查看: driver/${DRIVER_NAME}/${BOARD_NAME}/README.md"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    else
        log_error "驱动创建失败"
        exit 1
    fi
}

# 执行主函数
main "$@"
