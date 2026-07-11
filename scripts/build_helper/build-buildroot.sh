#!/bin/bash
#
# build-buildroot.sh - 构建 buildroot rootfs(D2-007)
#
# 封装 buildroot 的 defconfig + make,产出 rootfs 用户空间到 out/release-latest/rootfs/。
# buildroot 只构建 rootfs(Stage 3+4);kernel/uboot 由 build_helper 双轨体系外部提供,
# 镜像由 build_imx6ull_image.sh 从 rootfs 目录组装。
#
# Usage:
#   ./scripts/build_helper/build-buildroot.sh [OPTIONS]
#
# Options:
#   --defconfig NAME      buildroot defconfig 名(默认 imx6ull_aes_defconfig)
#   --clean               只清理 buildroot output(rm -rf)后退出,不构建;再跑本脚本(不带 --clean)构建
#   --source-only         仅下载源码包到 dl/(make source),不构建
#   --reconfigure         强制重新 defconfig(不删 output)
#   --output-dir PATH     buildroot O= 目录(默认 out/release-latest/buildroot)
#   --release-rootfs PATH 最终 rootfs 目录(默认 out/release-latest/rootfs)
#   --help, -h
#
# 相关:buildroot_menuconfig.sh(D2-008)、clean_buildroot.sh(D2-009)

# -o pipefail: Step 2 pipes make | tee | buildmeter; without it a failed make
# would be masked by tee/buildmeter exit-0 and set -e would miss the failure.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT_LIB_DIR="${PROJECT_ROOT}/scripts/lib"

if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
    log_info()  { echo -e "${GREEN}[buildroot]${NC} $1"; }
    log_error() { echo -e "${RED}[buildroot]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[buildroot]${NC} $1"; }
fi

# buildmeter progress bar (optional; auto-falls back to bare make if buildmeter
# is absent or FORGE_PROGRESS_DISABLE=1). See scripts/lib/progress.sh.
source "${SCRIPT_LIB_DIR}/progress.sh" 2>/dev/null || true

BUILDROOT_DIR="${PROJECT_ROOT}/third_party/buildroot"
BR2_EXTERNAL_DIR="${PROJECT_ROOT}/rootfs/buildroot"

DEFCONFIG="${DEFAULT_BUILDROOT_DEFCONFIG:-imx6ull_aes_defconfig}"
OUTPUT_DIR="${PROJECT_ROOT}/out/release-latest/buildroot"
RELEASE_ROOTFS="${PROJECT_ROOT}/out/release-latest/rootfs"
CLEAN=0
RECONFIGURE=0
SOURCE_ONLY=0
# Qt6 fragment:--with-qt6 或 BUILDROOT_QT6=1 触发(CI compile-support-3rd-party label)
WITH_QT6=0
[[ "${BUILDROOT_QT6:-0}" == "1" ]] && WITH_QT6=1

show_usage() {
    sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --defconfig) DEFCONFIG="$2"; shift 2 ;;
        --defconfig=*) DEFCONFIG="${1#*=}"; shift ;;
        --clean) CLEAN=1; shift ;;
        --reconfigure) RECONFIGURE=1; shift ;;
        --source-only) SOURCE_ONLY=1; shift ;;
        --with-qt6) WITH_QT6=1; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --output-dir=*) OUTPUT_DIR="${1#*=}"; shift ;;
        --release-rootfs) RELEASE_ROOTFS="$2"; shift 2 ;;
        --release-rootfs=*) RELEASE_ROOTFS="${1#*=}"; shift ;;
        --help|-h) show_usage; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# 检查 buildroot submodule 与 br2-external tree
if [[ ! -f "${BUILDROOT_DIR}/Makefile" ]]; then
    log_error "Buildroot submodule not initialized: ${BUILDROOT_DIR}"
    log_error "Run: git submodule update --init third_party/buildroot"
    exit 1
fi
if [[ ! -f "${BR2_EXTERNAL_DIR}/external.desc" ]]; then
    log_error "BR2_EXTERNAL tree missing external.desc: ${BR2_EXTERNAL_DIR}"
    exit 1
fi

if [[ ${CLEAN} -eq 1 ]]; then
    log_info "Cleaning buildroot output: ${OUTPUT_DIR}"
    rm -rf "${OUTPUT_DIR}"
    log_info "Cleaned (--clean only). To build, re-run without --clean:"
    log_info "  ./scripts/build_helper/build-buildroot.sh --with-qt6"
    exit 0
fi
mkdir -p "${OUTPUT_DIR}"

# buildroot 严格要求 PATH 不含空格/TAB/换行(否则报 "Your PATH contains spaces")。
# WSL 默认 PATH 带 Windows 路径(如 /mnt/c/Program Files)会触发此错误;Docker 环境 PATH
# 干净,此过滤为 no-op。过滤掉含空白字符的 PATH 组件。
CLEAN_PATH=""
_orig_ifs="$IFS"
IFS=':' read -ra _path_dirs <<< "${PATH}"
IFS="$_orig_ifs"
for d in "${_path_dirs[@]}"; do
    [[ -z "$d" ]] && continue
    [[ "$d" == *' '* || "$d" == *$'\t'* || "$d" == *$'\n'* ]] && continue
    CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d"
done
if [[ "$CLEAN_PATH" != "$PATH" ]]; then
    log_warn "PATH 含空格组件(常见于 WSL Windows 路径),已过滤后传给 buildroot"
    export PATH="$CLEAN_PATH"
fi

# 解析外部工具链根目录(buildroot BR2_TOOLCHAIN_EXTERNAL_PATH 要绝对路径)。
# defconfig 默认写死 /opt/arm-gnu-toolchain(CI 容器位置);本地按 PATH 里
# arm-none-linux-gnueabihf-gcc 的真实位置反推,换机器/换工具链版本都不用改 defconfig。
# buildroot 的 Kconfig 符号不取 `make BR2_X=Y` 命令行覆盖(conf 只读 .config),
# 故算出 TC_ROOT 后在 Step 1c 用 sed 写进 .config + olddefconfig 规范化。
# 遍历 PATH 找真实 gcc,跳过 ccache 包装:CI(及本地若配了 ccache)在 PATH 前段塞
# ccache-bin/arm-none-linux-gnueabihf-gcc -> /usr/bin/ccache 符号链接,command -v 会先命中它,
# readlink -f 解析到 .../ccache → 误把工具链根算成 /usr,buildroot 去找 /usr/bin/...gcc
# 报 "Cannot execute cross-compiler"。取第一个 readlink 后 basename 不是 ccache 的候选。
_tc_gcc=""
_oifs="$IFS"; IFS=':'; read -ra _pd <<< "${PATH}"; IFS="$_oifs"
for _d in "${_pd[@]}"; do
    [[ -z "$_d" ]] && continue
    _c="${_d}/arm-none-linux-gnueabihf-gcc"
    [[ -x "$_c" ]] || continue
    _r="$(readlink -f "$_c" 2>/dev/null || printf '%s' "$_c")"
    [[ "$(basename "$_r")" == "ccache" ]] && continue   # ccache 包装,跳过
    _tc_gcc="$_c"; break
done
unset _oifs _pd _d _c _r
if [[ -n "${_tc_gcc}" ]]; then
    TC_ROOT="$(cd "$(dirname "$(readlink -f "${_tc_gcc}")")/.." && pwd)"
else
    TC_ROOT="/opt/arm-gnu-toolchain"   # fallback = defconfig 默认(CI 容器)
    log_warn "PATH 中找不到 arm-none-linux-gnueabihf-gcc,回退 ${TC_ROOT}"
fi
unset _tc_gcc

log_info "Toolchain:    ${TC_ROOT}"
log_info "========================================"
log_info "Buildroot rootfs build"
log_info "========================================"
log_info "Buildroot:    ${BUILDROOT_DIR}"
log_info "BR2_EXTERNAL: ${BR2_EXTERNAL_DIR}"
log_info "Defconfig:    ${DEFCONFIG}"
log_info "Output (O=):  ${OUTPUT_DIR}"
echo ""

# Step 1: defconfig
if [[ ${CLEAN} -eq 1 || ${RECONFIGURE} -eq 1 || ! -f "${OUTPUT_DIR}/.config" ]]; then
    log_info "Step 1: Applying defconfig ${DEFCONFIG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" "${DEFCONFIG}"
else
    log_info "Step 1: Reusing existing .config (use --reconfigure to re-apply defconfig)"
fi

# Step 1c: 工具链路径落进 .config(defconfig 默认 /opt/arm-gnu-toolchain 仅 CI 容器适用)。
# Kconfig 不取 make 命令行 BR2_ 覆盖,故 sed 改 .config 再 olddefconfig 规范化;
# 复用旧 .config 时也重算,换机器后路径自动正确。已是目标值则跳过(增量构建不重复)。
if ! grep -q "^BR2_TOOLCHAIN_EXTERNAL_PATH=\"${TC_ROOT}\"$" "${OUTPUT_DIR}/.config"; then
    log_info "Step 1c: Toolchain path → ${TC_ROOT} (from PATH)"
    sed -i 's|^BR2_TOOLCHAIN_EXTERNAL_PATH=.*|BR2_TOOLCHAIN_EXTERNAL_PATH="'"${TC_ROOT}"'"|' "${OUTPUT_DIR}/.config"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" olddefconfig
fi

# Qt6 fragment merge(可选):Qt6 全模块编译 2-4h,默认最小 rootfs 不含;
# CI 由 compile-support-3rd-party label 触发,本地用 --with-qt6 或 BUILDROOT_QT6=1。
if [[ ${WITH_QT6} -eq 1 ]]; then
    QT6_FRAGMENT="${BR2_EXTERNAL_DIR}/fragments/qt6.config"
    if [[ ! -f "${QT6_FRAGMENT}" ]]; then
        log_error "Qt6 fragment not found: ${QT6_FRAGMENT}"
        exit 1
    fi
    log_info "Step 1b: Merging Qt6 fragment ($(basename "${QT6_FRAGMENT}"))"
    # merge_config.sh -m:把 fragment 合进 .config;olddefconfig 重解依赖(填 select)
    "${BUILDROOT_DIR}/support/kconfig/merge_config.sh" -m -O "${OUTPUT_DIR}" "${OUTPUT_DIR}/.config" "${QT6_FRAGMENT}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" olddefconfig
fi

echo ""

# Step 2: 构建(或仅下载源码)
if [[ ${SOURCE_ONLY} -eq 1 ]]; then
    log_info "Step 2: Downloading sources only (make source)"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" source
    log_info "Sources downloaded to ${OUTPUT_DIR}/dl/"
    exit 0
fi

NPROC=$(nproc)
# Full build log tee'd here — feed buildmeter AND keep a complete record for
# post-build analysis (e.g. checking ninja [N/M] output from meson/cmake pkgs).
LOG="${OUTPUT_DIR}/buildmeter-full.log"
if forge_progress_enabled; then
    # show-targets lists every package (host+target) buildroot will build → total
    # count, shown on the bar as "All Packages: N" (info only, NOT a %: incremental
    # builds skip already-built pkgs so done undercounts). Excludes a few internal
    # pkgs (skeleton...) show-targets omits; close enough for context. buildroot
    # dry-run can't give a compile ORDER (it halts early), so no ETA/%.
    PKG_TOTAL=$(make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" show-targets 2>/dev/null \
        | tr ' ' '\n' | grep -E '^[a-z][a-z0-9-]*$' | grep -vxE 'directory|make|entering' \
        | sort -u | wc -l)
    log_info "Step 2: Building (make -j${NPROC}) — progress bar on; ${PKG_TOTAL} packages; full log: ${LOG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" -j"${NPROC}" 2>&1 \
        | tee "${LOG}" \
        | python3 "${FORGE_PROGRESS_PY}" buildroot --log "${LOG}" --tail "${FORGE_PROGRESS_TAIL}" --total "${PKG_TOTAL}"
else
    log_info "Step 2: Building (make -j${NPROC}); full log: ${LOG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" -j"${NPROC}" 2>&1 | tee "${LOG}"
fi
echo ""

# Step 3: 同步 target/ → release rootfs
TARGET_DIR="${OUTPUT_DIR}/target"
if [[ ! -d "${TARGET_DIR}" ]]; then
    log_error "buildroot target/ not found: ${TARGET_DIR}"
    exit 1
fi

log_info "Step 3: Syncing target/ → ${RELEASE_ROOTFS}"
mkdir -p "${RELEASE_ROOTFS}"
# rsync --delete:保持 release rootfs 与 buildroot target 完全一致(删除多余文件)
# 排除 NFS root 运行时目录:板子以 root 写这些(seedrng 种子 / urandom / dhcp 租约),
# host 非特权无法删除 → rsync --delete 失败。这些是运行时缓存,不需 host 同步。
rsync -a --delete \
    --exclude ".gitkeep" \
    --exclude ".stamp" \
    --exclude "var/lib/seedrng" \
    --exclude "var/lib/urandom" \
    --exclude "var/lib/misc" \
    --exclude "var/lib/dhcp" \
    --exclude "var/lib/network" \
    "${TARGET_DIR}/" "${RELEASE_ROOTFS}/" || {
    log_error "rsync 到 ${RELEASE_ROOTFS} 失败"
    log_error "常见原因:${RELEASE_ROOTFS} 里有权限受限的旧文件(root 属主残留 / NFS 挂载)"
    log_error "处理:sudo rm -rf ${RELEASE_ROOTFS} 后重跑本脚本"
    exit 1
}

# 最终闸门:确认核心产物在位(post-build.sh 已在 build 过程中跑过 varified 校验)
if [[ ! -x "${RELEASE_ROOTFS}/bin/busybox" ]]; then
    log_error "Verification failed: ${RELEASE_ROOTFS}/bin/busybox missing"
    exit 1
fi

log_info ""
log_info "========================================"
log_info "Buildroot rootfs build complete!"
log_info "========================================"
log_info "  Rootfs:    ${RELEASE_ROOTFS}"
log_info "  Build dir: ${OUTPUT_DIR}"
