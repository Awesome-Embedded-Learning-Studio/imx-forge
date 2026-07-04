#!/bin/bash
#
# ALSA (alsa-lib + alsa-utils) Installation Script for RootFS
#
# 交叉编译 alsa-lib 与 alsa-utils，把 aplay / amixer / arecord / alsactl 装进 rootfs，
# 让 alpha 板能验证 WM8960 声卡（见 tutorial/driver/12_wm8960_audio_driver/）。
#
# Environment variables:
#   ROOTFS_DIR    - 目标 rootfs 路径（由 varified_rootfs_ok.sh 注入）
#   PROJECT_ROOT  - 项目根路径（由 varified_rootfs_ok.sh 注入）
#   ALSA_LIB_VER  - 可覆盖 alsa-lib 版本（默认 1.2.12）
#   ALSA_UTILS_VER- 可覆盖 alsa-utils 版本（默认 1.2.12）
#   FORCE         - =1 强制重装（默认幂等：aplay 已存在则跳过）
#
# Usage:
#   自动：varified_rootfs_ok.sh 会执行本脚本
#   手动：ROOTFS_DIR=rootfs/nfs ./install_alsa.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[install_alsa]${NC} $1"; }
log_error() { echo -e "${RED}[install_alsa]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[install_alsa]${NC} $1"; }

# Cross-compiler prefix（与 build_helper/*.sh 统一）
CROSS_COMPILE=arm-none-linux-gnueabihf-

# Defaults
: "${PROJECT_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${ROOTFS_DIR:=${PROJECT_ROOT}/rootfs/nfs}"
: "${ALSA_LIB_VER:=1.2.12}"
: "${ALSA_UTILS_VER:=1.2.12}"
: "${FORCE:=0}"

WORKDIR="${PROJECT_ROOT}/out/.alsa-workdir"
STAGE="${WORKDIR}/_stage"          # DESTDIR 暂存（alsa-lib/alsa-utils 装这里再拷进 rootfs）
SRC="${WORKDIR}/src"               # 源码解压目录
TARBALL_CACHE="${WORKDIR}/tarball" # 下载的 tarball 缓存（幂等：下次直接复用）

log_info "Installing ALSA ${ALSA_LIB_VER} (lib) + ${ALSA_UTILS_VER} (utils) to: ${ROOTFS_DIR}"

# ---- 前置检查 -------------------------------------------------------------
if [[ ! -d "$ROOTFS_DIR" ]]; then
    log_error "Rootfs directory not found: ${ROOTFS_DIR}"
    exit 1
fi

if ! command -v "${CROSS_COMPILE}gcc" &> /dev/null; then
    log_error "Cross compiler '${CROSS_COMPILE}gcc' not found in PATH."
    log_error "Run scripts/init/env-init.sh first to source the toolchain."
    exit 1
fi

# 幂等：aplay 已存在且未强制重装 → 跳过
if [[ -x "${ROOTFS_DIR}/usr/bin/aplay" && "$FORCE" != "1" ]]; then
    log_info "aplay already present in rootfs (use FORCE=1 to rebuild). Skipping."
    exit 0
fi

mkdir -p "${STAGE}" "${SRC}" "${TARBALL_CACHE}" \
         "${ROOTFS_DIR}/usr/bin" "${ROOTFS_DIR}/usr/lib" "${ROOTFS_DIR}/usr/share"

# ---- 下载函数（带缓存）----------------------------------------------------
download() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        log_info "  cached: $(basename "$dest")"
        return 0
    fi
    log_info "  downloading $(basename "$dest")"
    curl -fL --retry 3 --connect-timeout 30 -o "$dest" "$url"
}

# ---- 1) alsa-lib ----------------------------------------------------------
ALSA_LIB_TARBALL="${TARBALL_CACHE}/alsa-lib-${ALSA_LIB_VER}.tar.bz2"
log_info "[1/2] alsa-lib ${ALSA_LIB_VER}"
download "https://www.alsa-project.org/files/pub/lib/alsa-lib-${ALSA_LIB_VER}.tar.bz2" \
         "${ALSA_LIB_TARBALL}"

if [[ ! -d "${SRC}/alsa-lib-${ALSA_LIB_VER}" ]]; then
    tar -xf "${ALSA_LIB_TARBALL}" -C "${SRC}"
fi

(
    cd "${SRC}/alsa-lib-${ALSA_LIB_VER}"
    log_info "  configure alsa-lib"
    # 静态库用不到，关掉省体积；shared 是 libasound.so.*
    ./configure \
        --host="${CROSS_COMPILE%-}" \
        --prefix=/usr \
        --enable-shared \
        --disable-static \
        --quiet
    log_info "  make alsa-lib"
    make -j"$(nproc)" >/dev/null
    log_info "  install alsa-lib -> stage"
    make install DESTDIR="${STAGE}" >/dev/null
    # 修正 libasound.la 的 libdir → stage 绝对路径（libtool 交叉链接 alsatplg 才找得到，
    # 否则报 "cannot find /usr/lib/libasound.la" 因为 .la 里 libdir=/usr/lib 被当 host 路径）
    sed -i "s|^libdir=.*|libdir='${STAGE}/usr/lib'|" "${STAGE}/usr/lib/libasound.la" 2>/dev/null || true
    sed -i "s|/usr/lib/libasound.la|${STAGE}/usr/lib/libasound.la|g" "${STAGE}/usr/lib/libasound.la" 2>/dev/null || true
    sed -i "s|^libdir=.*|libdir='${STAGE}/usr/lib'|" "${STAGE}/usr/lib/libatopology.la" 2>/dev/null || true
    sed -i "s|/usr/lib/libasound.la|${STAGE}/usr/lib/libasound.la|g" "${STAGE}/usr/lib/libatopology.la" 2>/dev/null || true
    # 修 alsa.pc 的 prefix/exec_prefix → stage：alsa-utils 通过 pkg-config 读 alsa.pc 拿 libdir，
    # 不改的话 alsatplg/aplay 链接命令里写死 /usr/lib/libasound.la（host 路径）找不到
    if [[ -f "${STAGE}/usr/lib/pkgconfig/alsa.pc" ]]; then
        sed -i "s|^prefix=.*|prefix=${STAGE}/usr|" "${STAGE}/usr/lib/pkgconfig/alsa.pc"
        sed -i "s|^exec_prefix=.*|exec_prefix=${STAGE}/usr|" "${STAGE}/usr/lib/pkgconfig/alsa.pc"
        sed -i "s|^libdir=.*|libdir=${STAGE}/usr/lib|" "${STAGE}/usr/lib/pkgconfig/alsa.pc"
        sed -i "s|^includedir=.*|includedir=${STAGE}/usr/include|" "${STAGE}/usr/lib/pkgconfig/alsa.pc"
    fi
)

# ---- 2) alsa-utils（依赖上一步的 libasound，从 STAGE 取头文件/库）---------
ALSA_UTILS_TARBALL="${TARBALL_CACHE}/alsa-utils-${ALSA_UTILS_VER}.tar.bz2"
log_info "[2/2] alsa-utils ${ALSA_UTILS_VER}"
download "https://www.alsa-project.org/files/pub/utils/alsa-utils-${ALSA_UTILS_VER}.tar.bz2" \
         "${ALSA_UTILS_TARBALL}"

if [[ ! -d "${SRC}/alsa-utils-${ALSA_UTILS_VER}" ]]; then
    tar -xf "${ALSA_UTILS_TARBALL}" -C "${SRC}"
fi

(
    cd "${SRC}/alsa-utils-${ALSA_UTILS_VER}"
    log_info "  configure alsa-utils"
    # alsamixer 要 ncurses、alsaconf 要 python、bat 要 fftw —— 先全禁掉，减少宿主依赖。
    # aplay/arecord/amixer/alsactl/alsaucm 都是纯命令行，不依赖这些。
    PKG_CONFIG_SYSROOT_DIR="${STAGE}" \
    PKG_CONFIG_PATH="${STAGE}/usr/lib/pkgconfig" \
    ./configure \
        --host="${CROSS_COMPILE%-}" \
        --prefix=/usr \
        --disable-alsamixer \
        --disable-alsaconf \
        --disable-bat \
        --disable-alsaloop \
        --disable-alsatopology \
        --disable-xmlto \
        CFLAGS="-I${STAGE}/usr/include -O2" \
        LDFLAGS="-L${STAGE}/usr/lib" \
        --quiet
    log_info "  make alsa-utils（alsatplg 链接可能仍失败，忽略；只要 aplay/amixer/arecord 编出）"
    make -j"$(nproc)" >/dev/null || log_warn "  make 有目标失败（alsatplg？），只要 aplay 编出就继续"
    make install DESTDIR="${STAGE}" >/dev/null 2>&1 || log_warn "  make install 部分失败，继续看 aplay 是否到位"
)

# ---- 3) stage -> rootfs ---------------------------------------------------
log_info "Copying into rootfs..."

# libasound（运行时只要 .so*）
cp -a "${STAGE}/usr/lib/libasound.so"* "${ROOTFS_DIR}/usr/lib/" 2>/dev/null || log_warn "  no libasound.so found"

# 工具二进制（aplay/arecord 是同一多调用二进制的不同 symlink，cp -a 保留链接关系）
for bin in aplay arecord amixer alsactl alsaucm speaker-test; do
    if [[ -e "${STAGE}/usr/bin/${bin}" ]]; then
        cp -a "${STAGE}/usr/bin/${bin}" "${ROOTFS_DIR}/usr/bin/"
    fi
done

# ALSA 配置树（PCM plug 定义、缺省参数；aplay/amixer 运行时依赖）
if [[ -d "${STAGE}/usr/share/alsa" ]]; then
    mkdir -p "${ROOTFS_DIR}/usr/share"
    rm -rf "${ROOTFS_DIR}/usr/share/alsa"
    cp -a "${STAGE}/usr/share/alsa" "${ROOTFS_DIR}/usr/share/"
fi

# ---- 汇总 -----------------------------------------------------------------
log_info "ALSA installation complete:"
if [[ -x "${ROOTFS_DIR}/usr/bin/aplay" ]]; then
    log_info "  /usr/bin/aplay     OK"
    log_info "  /usr/bin/amixer    $([ -x "${ROOTFS_DIR}/usr/bin/amixer" ] && echo OK || echo MISSING)"
    log_info "  /usr/bin/arecord   $([ -e "${ROOTFS_DIR}/usr/bin/arecord" ] && echo OK || echo MISSING)"
    log_info "  libasound: $(ls "${ROOTFS_DIR}/usr/lib"/libasound.so.* 2>/dev/null | head -1 | xargs -r basename || echo MISSING)"
else
    log_error "  aplay missing after install — check build log"
    exit 1
fi
