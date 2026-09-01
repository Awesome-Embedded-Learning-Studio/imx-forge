#!/bin/bash
#
# build-qemu.sh - Build the self-hosted QEMU (arm-softmmu only) for board emulation
#
# Usage: build-qemu.sh [OPTIONS]
#
# Options:
#   --jobs=N         Parallel build jobs (default: nproc)
#   --reconfigure    Re-run configure even if the build dir exists
#   -h, --help       Show this help message
#
# Builds third_party/qemu (submodule, pinned per .gitmodules) into
# out/qemu/build with the teaching-relevant feature set:
#   --target-list=arm-softmmu  one machine family, minutes not tens of minutes
#   --disable-tools --disable-docs  no qemu-img/docs, faster builds
#   --enable-slirp    user-mode networking (-nic user), built as a meson
#                     subproject so no system libslirp-dev is needed
#
# Host prerequisites (not auto-installed, need sudo once):
#   sudo apt-get install -y ninja-build flex bison libglib2.0-dev \
#       libpixman-1-dev libfdt-dev zlib1g-dev python3-venv
#   Optional: libgtk-3-dev for the interactive gtk display window — without
#   it the build is headless-only (--display gtk unavailable; --smoke and
#   -nographic unaffected).
#   (meson >= 1.5 is bootstrapped by QEMU's own mkvenv into the build dir;
#    system meson 1.3 on Ubuntu 24.04 is too old but unused)
#
# The resulting binary (out/qemu/build/qemu-system-arm) is picked up
# automatically by scripts/qemu_helper/run-qemu.sh, which falls back to the
# system qemu-system-arm (8.2 on Ubuntu 24.04 — no LCDIF model, several
# address holes) when the self-built one is missing.
#
# Why 11.1: eLCDIF real display model, FlexCAN model in tree, MMDC/OCOTP/
# QSPI/USBMISC unimplemented stubs instead of address holes. The U-Boot
# boot chain patches (Bin Meng, 2026-08) are NOT in 11.1 — they are still
# under review upstream; revisit with 11.2 (~2026-12).
#
# Environment variables:
#   PROJECT_ROOT   Project root directory (auto-detected if not set)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

QEMU_SRC="${PROJECT_ROOT}/third_party/qemu"
BUILD_DIR="${PROJECT_ROOT}/out/qemu/build"
JOBS="$(nproc)"
RECONFIGURE=0

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# //g; s/^#//g'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs=*)    JOBS="${1#*=}" ;;
        --reconfigure) RECONFIGURE=1 ;;
        -h|--help)   usage ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            ;;
    esac
    shift
done

log()  { echo "[build-qemu] $*"; }
die()  { echo "[build-qemu] error: $*" >&2; exit 1; }

[[ -f "${QEMU_SRC}/configure" ]] || die "qemu source not found: ${QEMU_SRC} (git submodule update --init third_party/qemu)"
command -v ninja >/dev/null || die "ninja not found (sudo apt-get install ninja-build)"
pkg-config --exists glib-2.0 || die "glib-2.0 dev not found (sudo apt-get install libglib2.0-dev)"
pkg-config --exists pixman-1 || die "pixman dev not found (sudo apt-get install libpixman-1-dev) — required by the eLCDIF display model"

# --- apply our patch series (numbered, applied in order — the qemu component
# is exempt from the repo's one-rolled-patch convention; squashed patch series
# of this size cannot be rebased, see the 100askTeam/qemu cautionary tale) ---
# "clean pin" is judged against the gitlink RECORDED in the parent repo, not
# by resolving the v11.1.0 tag inside the submodule — shallow clones (CI,
# .gitmodules shallow=true) fetch the commit but no tags, and a tag-less
# resolution would silently skip the patch series and build stock QEMU.
PATCH_DIR="${PROJECT_ROOT}/patches/qemu"
SUBMODULE_REL="third_party/qemu"
RECORDED_PIN="$(git -C "${PROJECT_ROOT}" ls-tree HEAD "${SUBMODULE_REL}" | awk '{print $3}')"
if [[ -n "${RECORDED_PIN}" && "$(git -C "${QEMU_SRC}" rev-parse HEAD)" == "${RECORDED_PIN}" ]]; then
    # submodule sits on the clean pin: (re)apply our series
    git -C "${QEMU_SRC}" checkout -- . 2>/dev/null || true
    for p in "${PATCH_DIR}"/*.patch; do
        [[ -e "$p" ]] || { log "no patches in ${PATCH_DIR}, building stock v11.1.0"; break; }
        log "applying $(basename "$p")"
        git -C "${QEMU_SRC}" apply "$p" || die "failed to apply $p (patch/base drift?)"
    done
else
    log "WARNING: submodule HEAD != recorded gitlink ${RECORDED_PIN:-?} (dev checkout?) — building as-is, patch series SKIPPED"
fi

# gtk display support is optional: needed only for the interactive window
# (run-qemu.sh --display gtk); headless smoke/-nographic works without it.
if pkg-config --exists gtk+-3.0 2>/dev/null; then
    GTK_FLAG="--enable-gtk"
    log "gtk+ dev found — gtk display enabled"
else
    GTK_FLAG="--disable-gtk"
    log "gtk+ dev NOT found — building headless-only (install libgtk-3-dev for --display gtk)"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [[ ! -f build.ninja || "${RECONFIGURE}" -eq 1 ]]; then
    log "configuring in ${BUILD_DIR}"
    if ! "${QEMU_SRC}/configure" \
        --target-list=arm-softmmu \
        --disable-tools \
        --disable-docs \
        --disable-werror \
        --enable-slirp \
        "${GTK_FLAG}" > "${BUILD_DIR}/configure.log" 2>&1; then
        tail -40 "${BUILD_DIR}/configure.log" >&2
        die "configure failed (full log: ${BUILD_DIR}/configure.log)"
    fi
    tail -3 "${BUILD_DIR}/configure.log"
else
    log "build dir already configured (use --reconfigure to redo)"
fi

log "building with ${JOBS} jobs"
ninja -j "${JOBS}" 2>&1 | tail -2

BIN="${BUILD_DIR}/qemu-system-arm"
[[ -x "${BIN}" ]] || die "build finished but ${BIN} missing"
log "done: ${BIN} ($(${BIN} --version | head -1))"
log "run-qemu.sh picks it up automatically"
