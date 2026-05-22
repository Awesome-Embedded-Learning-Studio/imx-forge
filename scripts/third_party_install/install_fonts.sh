#!/usr/bin/env bash
# ==============================================================================
# install_fonts.sh - 字体下载和安装脚本
# ==============================================================================
# 功能：
#   - 下载并安装 DejaVu、Noto CJK、Noto Emoji 字体到 ROOTFS
#   - 支持跳过已安装的字体（通过检测关键文件）
#   - 支持 --force 参数强制重新安装
#
# 使用方法:
#   bash scripts/third_party_install/install_fonts.sh [--force]
#
# 选项:
#   --force    强制重新安装，即使字体已存在
# ==============================================================================

set -euo pipefail

# IMXFORGE_VERBOSE: 0=正常进度, 1=详细输出
: "${IMXFORGE_VERBOSE:=0}"
if [[ "$IMXFORGE_VERBOSE" == "1" ]]; then
    UNZIP_ARGS=""
else
    UNZIP_ARGS="-q"
fi

# ================================================================
# 脚本目录和项目根目录
# ================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/logging.sh
source "${SCRIPT_DIR}/../lib/logging.sh"

# 获取 superproject（主项目）的根目录
GIT_PROJECT_ROOT="$(git rev-parse --show-superproject-working-tree 2>/dev/null)"
: "${GIT_PROJECT_ROOT:=$(git rev-parse --show-toplevel)}"

PROJECT_ROOT="${GIT_PROJECT_ROOT}"
QT_PIPELINE_DIR="${PROJECT_ROOT}/third_party/qt-compile-pipeline"
CONFIG_TARGET_DIR="${QT_PIPELINE_DIR}/config"

# ROOTFS 目录（支持外部传入）
: "${ROOTFS_DIR:=${PROJECT_ROOT}/rootfs/nfs}"

# ================================================================
# 参数解析
# ================================================================
FORCE_REINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [--force]"
            echo ""
            echo "选项:"
            echo "  --force    强制重新安装，即使字体已存在"
            echo ""
            echo "字体将会安装到: ${ROOTFS_DIR}/usr/share/fonts/"
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

# ================================================================
# 加载配置文件
# ================================================================
# shellcheck disable=SC1090
source "${CONFIG_TARGET_DIR}/qt.conf"

# 加载字体配置
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/config/qt/fonts.conf"

# ================================================================
# 工具函数
# ================================================================

# 检查字体是否已安装
# 参数: $1=字体名称, $2=目标目录, $3=关键文件数组名
check_fonts_installed() {
    local font_name="$1"
    local target_dir="$2"
    local -n key_files_ref="$3"
    local missing_count=0

    for font_file in "${key_files_ref[@]}"; do
        local font_path="${target_dir}/${font_file}"
        if [[ ! -f "${font_path}" ]]; then
            ((missing_count++)) || true
            log_debug "  缺少: ${font_file}"
        fi
    done

    if [[ ${missing_count} -eq 0 ]]; then
        return 0  # 所有字体都存在
    else
        return 1  # 有字体缺失
    fi
}

# 下载文件（支持断点续传）
download_file() {
    local url="$1"
    local dest="$2"
    local filename="$(basename "$dest")"

    # 如果目标文件已存在且大小合理，跳过下载
    if [[ -f "${dest}" ]]; then
        local size="$(stat -f%z "${dest}" 2>/dev/null || stat -c%s "${dest}" 2>/dev/null || echo "0")"

        # 对于 ZIP 文件，验证完整性
        if [[ "${filename}" == *.zip ]]; then
            if unzip -t "${dest}" >/dev/null 2>&1; then
                log_info "  ✓ 已存在: ${filename} ($(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size} bytes"))"
                return 0
            else
                log_warn "  文件损坏: ${filename}，将重新下载"
                rm -f "${dest}"
            fi
        # 对于 tar.bz2 文件，检查大小阈值
        elif [[ ${size} -gt 5000000 ]]; then  # 大于 5MB 认为有效
            log_info "  ✓ 已存在: ${filename} ($(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size} bytes"))"
            return 0
        else
            # 删除不完整的小文件
            log_debug "  删除不完整文件: ${filename} (${size} bytes)"
            rm -f "${dest}"
        fi
    fi

    # 创建目标目录
    mkdir -p "$(dirname "$dest")"

    log_info "  正在下载: ${filename}"
    log_info "  来源: ${url}"

    # 使用 curl 下载（先尝试断点续传，失败则重新下载）
    if curl -fL -C - -o "${dest}" "${url}" 2>/dev/null; then
        local size="$(stat -f%z "${dest}" 2>/dev/null || stat -c%s "${dest}" 2>/dev/null || echo "0")"
        log_info "  ✓ 下载完成: $(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size} bytes")"
        return 0
    else
        # 断点续传失败，删除文件后重新下载
        log_debug "  断点续传失败，尝试重新下载..."
        rm -f "${dest}"
        if curl -fL -o "${dest}" "${url}"; then
            local size="$(stat -f%z "${dest}" 2>/dev/null || stat -c%s "${dest}" 2>/dev/null || echo "0")"
            log_info "  ✓ 下载完成: $(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size} bytes")"
            return 0
        else
            log_error "  ✗ 下载失败: ${filename}"
            return 1
        fi
    fi
}

# 安装 DejaVu 字体
install_dejavu() {
    log_info "----------------------------------------"
    log_info "DejaVu Fonts ${DEJAVU_VERSION}"
    log_info "----------------------------------------"

    local cache_dir="${FONTS_CACHE_DIR}/dejavu"
    # Qt 没有 Fontconfig 时不递归扫描子目录，直接拷贝到顶层目录
    local target_dir="${ROOTFS_DIR}/usr/share/fonts"

    # 检查是否已安装
    if [[ "${FORCE_REINSTALL}" == false ]] && check_fonts_installed "DejaVu" "${target_dir}" DEJAVU_KEY_FILES; then
        log_info "  ✓ DejaVu 字体已安装，跳过"
        return 0
    fi

    # 下载
    local archive="${FONTS_DL_DIR}/${DEJAVU_FILE}"
    if ! download_file "${DEJAVU_URL}" "${archive}"; then
        log_error "DejaVu 字体下载失败"
        return 1
    fi

    # 解压
    log_info "  正在解压..."
    mkdir -p "${cache_dir}"
    if ! tar -xjf "${archive}" -C "${cache_dir}"; then
        log_error "  ✗ 解压失败"
        return 1
    fi

    # 查找并拷贝字体文件
    log_info "  正在安装字体文件..."
    mkdir -p "${target_dir}"

    local copied=0
    for font_file in "${DEJAVU_KEY_FILES[@]}"; do
        # 在解压目录中查找字体文件
        local found="$(find "${cache_dir}" -name "${font_file}" -type f 2>/dev/null | head -n1)"
        if [[ -n "${found}" ]]; then
            cp -f "${found}" "${target_dir}/"
            ((copied++)) || true
            log_debug "    ✓ ${font_file}"
        fi
    done

    log_info "  ✓ 已安装 ${copied} 个 DejaVu 字体文件到 ${target_dir}"
}

# 安装 Noto CJK 字体
install_noto_cjk() {
    log_info "----------------------------------------"
    log_info "Noto Sans CJK ${NOTO_CJK_VERSION}"
    log_info "----------------------------------------"

    local cache_dir="${FONTS_CACHE_DIR}/noto-cjk"
    # Qt 没有 Fontconfig 时不递归扫描子目录，直接拷贝到顶层目录
    local target_dir="${ROOTFS_DIR}/usr/share/fonts"

    # 检查是否已安装
    if [[ "${FORCE_REINSTALL}" == false ]] && check_fonts_installed "Noto CJK" "${target_dir}" NOTO_CJK_KEY_FILES; then
        log_info "  ✓ Noto CJK 字体已安装，跳过"
        return 0
    fi

    # 下载
    local archive="${FONTS_DL_DIR}/${NOTO_CJK_FILE}"
    if ! download_file "${NOTO_CJK_URL}" "${archive}"; then
        log_error "Noto CJK 字体下载失败"
        return 1
    fi

    # 解压
    log_info "  正在解压..."
    mkdir -p "${cache_dir}"
    if ! unzip ${UNZIP_ARGS} -o "${archive}" -d "${cache_dir}"; then
        log_error "  ✗ 解压失败"
        return 1
    fi

    # 拷贝字体文件
    log_info "  正在安装字体文件..."
    mkdir -p "${target_dir}"

    local copied=0

    # 首先查找 Super OTC 文件（包含所有 CJK 语言）
    local otc_file="$(find "${cache_dir}" -name "*.ttc" -type f 2>/dev/null | head -n1)"
    if [[ -n "${otc_file}" ]]; then
        cp -f "${otc_file}" "${target_dir}/NotoSansCJK-OTC.ttc"
        ((copied++)) || true
        log_info "    ✓ NotoSansCJK-OTC.ttc ($(numfmt --to=iec-i --suffix=B $(stat -f%z "${otc_file}" 2>/dev/null || stat -c%s "${otc_file}") 2>/dev/null || echo "unknown"))"
    fi

    # 如果没有找到 OTC，尝试查找 OTF 文件
    if [[ ${copied} -eq 0 ]]; then
        log_info "  未找到 TTC 文件，尝试查找 OTF 文件..."
        local otf_files=(
            "NotoSansCJKsc-Regular.otf"
            "NotoSansCJKsc-Bold.otf"
            "NotoSansSC-Regular.otf"
            "NotoSansSC-Bold.otf"
        )
        for otf_file in "${otf_files[@]}"; do
            local found="$(find "${cache_dir}" -name "${otf_file}" -type f 2>/dev/null | head -n1)"
            if [[ -n "${found}" ]]; then
                cp -f "${found}" "${target_dir}/"
                ((copied++)) || true
                log_debug "    ✓ ${otf_file}"
            fi
        done
    fi

    log_info "  ✓ 已安装 ${copied} 个 Noto CJK 字体文件到 ${target_dir}"
}

# 安装 Noto Emoji 字体
install_noto_emoji() {
    log_info "----------------------------------------"
    log_info "Noto Color Emoji ${NOTO_EMOJI_VERSION}"
    log_info "----------------------------------------"

    local cache_dir="${FONTS_CACHE_DIR}/emoji"
    # Qt 没有 Fontconfig 时不递归扫描子目录，直接拷贝到顶层目录
    local target_dir="${ROOTFS_DIR}/usr/share/fonts"

    # 检查是否已安装
    if [[ "${FORCE_REINSTALL}" == false ]] && check_fonts_installed "Noto Emoji" "${target_dir}" NOTO_EMOJI_KEY_FILES; then
        log_info "  ✓ Noto Emoji 字体已安装，跳过"
        return 0
    fi

    # 下载
    local dest="${cache_dir}/${NOTO_EMOJI_FILE}"
    if ! download_file "${NOTO_EMOJI_URL}" "${dest}"; then
        log_error "Noto Emoji 字体下载失败"
        return 1
    fi

    # 拷贝字体文件
    log_info "  正在安装字体文件..."
    mkdir -p "${target_dir}"
    cp -f "${dest}" "${target_dir}/"

    log_info "  ✓ 已安装 Noto Color Emoji 到 ${target_dir}"
}

# 显示安装摘要
show_summary() {
    log_info ""
    log_info "=== 字体安装摘要 ==="
    log_info ""

    # 统计字体数量（都在顶层目录）
    local dejavu_count=0 noto_count=0 emoji_count=0

    local fonts_dir="${ROOTFS_DIR}/usr/share/fonts"

    [[ -d "${fonts_dir}" ]] && dejavu_count=$(find "${fonts_dir}" -maxdepth 1 -name "DejaVu*.ttf" | wc -l)
    [[ -d "${fonts_dir}" ]] && noto_count=$(find "${fonts_dir}" -maxdepth 1 -name "NotoSansCJK*.ttc" | wc -l)
    [[ -d "${fonts_dir}" ]] && emoji_count=$(find "${fonts_dir}" -maxdepth 1 -name "NotoColorEmoji.ttf" | wc -l)

    log_info "已安装字体:"
    log_info "  DejaVu:     ${dejavu_count} 个文件"
    log_info "  Noto CJK:   ${noto_count} 个文件"
    log_info "  Noto Emoji: ${emoji_count} 个文件"

    # 计算总大小
    local total_size=0
    if [[ -d "${fonts_dir}" ]]; then
        local dir_size="$(du -sk "${fonts_dir}" 2>/dev/null | cut -f1)"
        total_size=$((dir_size))
    fi

    log_info ""
    log_info "总大小: ~$((total_size / 1024)) MB"
    log_info ""

    # 显示环境变量配置
    log_info "Qt 字体环境变量配置:"
    log_info "  export QT_QPA_FONTDIR=/usr/share/fonts"
    log_info "  export LANG=C.UTF-8"
    log_info "  export LC_ALL=C.UTF-8"
    log_info ""
}

# ================================================================
# 主流程
# ================================================================
main() {
    log_info "=== 字体安装脚本 ==="
    log_info "项目根目录: ${PROJECT_ROOT}"
    log_info "ROOTFS 目录: ${ROOTFS_DIR}"
    log_info ""

    # 检查 ROOTFS 是否存在
    if [[ ! -d "${ROOTFS_DIR}" ]]; then
        log_error "ROOTFS 目录不存在: ${ROOTFS_DIR}"
        log_error "请先创建 ROOTFS"
        exit 1
    fi

    # 检查是否启用字体安装
    if [[ "${FONTS_ENABLED}" != "true" ]]; then
        log_warn "字体安装已禁用 (FONTS_ENABLED=false)"
        exit 0
    fi

    # 创建必要的目录
    mkdir -p "${FONTS_DL_DIR}"
    mkdir -p "${FONTS_CACHE_DIR}"

    # 显示将要执行的安装
    log_info "将要安装的字体:"
    log_info "  1. DejaVu Fonts ${DEJAVU_VERSION} (拉丁字符 + 等宽字体)"
    log_info "  2. Noto Sans CJK ${NOTO_CJK_VERSION} (中日韩字符)"
    log_info "  3. Noto Color Emoji (Emoji 支持)"
    log_info ""

    if [[ "${FORCE_REINSTALL}" == true ]]; then
        log_warn "--force 模式：将重新安装所有字体"
        log_info ""
    fi
    
    # 执行安装
    local exit_code=0

    if ! install_dejavu; then
        exit_code=1
    fi

    if ! install_noto_cjk; then
        exit_code=1
    fi

    if ! install_noto_emoji; then
        exit_code=1
    fi

    # 显示摘要
    show_summary

    if [[ ${exit_code} -eq 0 ]]; then
        log_info "✓ 字体安装完成"
    else
        log_warn "字体安装完成，但有部分错误"
    fi

    return ${exit_code}
}

# 运行主流程
main "$@"
