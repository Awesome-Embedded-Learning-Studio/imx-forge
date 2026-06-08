#!/usr/bin/env bash
#
# Release Build Script for Linux Mainline
#
# This script ensures a reproducible release build by:
# 1. Cleaning and resetting the linux_mainline submodule to the locked gitlink commit
# 2. Applying the latest mainline patch
# 3. Delegating to the mainline build script
#
# Usage: ./build_release_mainline_linux.sh [--fast-build] [release_version]
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_HELPER_DIR="${PROJECT_ROOT}/scripts/build_helper"
LINUX_DIR="${PROJECT_ROOT}/third_party/linux_mainline"
PATCH_DIR="${PROJECT_ROOT}/patches/linux_mainline"
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/mainline/linux}"
BUILD_INFO_FILE="${OUTPUT_DIR}/build_info.txt"

FAST_BUILD=0
RELEASE_VERSION="unknown"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast-build)
            FAST_BUILD=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--fast-build] [release_version]"
            exit 0
            ;;
        *)
            RELEASE_VERSION="$1"
            shift
            ;;
    esac
done

# For reproducible builds - use fixed timestamp
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1609459200}  # 2021-01-01 00:00:00 UTC
export LC_ALL=C

# ============================================
# Step 1: Reset Linux Mainline Submodule to Locked Commit
# ============================================
log_step "1/5: Resetting Linux Mainline Submodule to Locked Commit"

LOCKED_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse HEAD:third_party/linux_mainline)
log_info "Locked commit from superproject: ${LOCKED_COMMIT}"

if [[ ! -d "${LINUX_DIR}/.git" && ! -f "${LINUX_DIR}/.git" ]]; then
    log_info "Initializing linux_mainline submodule at locked commit..."
    git -C "$PROJECT_ROOT" submodule update --init --depth=1 third_party/linux_mainline
fi

if ! git -C "$LINUX_DIR" cat-file -e "${LOCKED_COMMIT}^{commit}" 2>/dev/null; then
    log_info "Locked commit not present locally; fetching submodule gitlink commit..."
    git -C "$PROJECT_ROOT" submodule update --init --depth=1 third_party/linux_mainline
fi

if ! git -C "$LINUX_DIR" cat-file -e "${LOCKED_COMMIT}^{commit}" 2>/dev/null; then
    log_error "Locked mainline commit is unavailable locally: ${LOCKED_COMMIT}"
    exit 1
fi

cd "$LINUX_DIR"

log_info "Cleaning working directory..."
git reset --hard HEAD 2>/dev/null || true
git clean -ffdx

log_info "Checking out locked commit..."
git checkout --detach "$LOCKED_COMMIT"

log_info "Resetting to locked commit..."
git reset --hard "$LOCKED_COMMIT"

git clean -ffdx

log_info "Linux mainline submodule reset complete at locked commit"

# ============================================
# Step 2: Verify Submodule State
# ============================================
log_step "2/5: Verifying Submodule State"

LINUX_COMMIT=$(git rev-parse HEAD)
LINUX_DESCRIBE=$(git describe --tags --always 2>/dev/null || echo "no-tags")
LINUX_BRANCH=$(git rev-parse --abbrev-ref HEAD)

log_info "Linux commit: ${LINUX_COMMIT}"
log_info "Linux version: ${LINUX_DESCRIBE}"
log_info "Linux branch: ${LINUX_BRANCH}"

# ============================================
# Step 3: Create Release Branch
# ============================================
log_step "3/5: Creating Release Branch"

BRANCH_NAME="release-mainline-build-$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
log_info "Creating branch: ${BRANCH_NAME}"

if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    log_info "Branch ${BRANCH_NAME} already exists, deleting it..."
    git branch -D "$BRANCH_NAME"
fi

git checkout -b "$BRANCH_NAME"

log_info "Release branch created"

# ============================================
# Step 4: Apply Patch
# ============================================
log_step "4/5: Applying Mainline Patch"

PATCHED_FILES=0
PATCH_NAME="None"

if [[ ! -d "$PATCH_DIR" ]]; then
    log_warn "Patch directory not found: $PATCH_DIR"
    log_warn "Continuing build without patch..."
else
    shopt -s nullglob
    patch_files=("${PATCH_DIR}"/*.patch)
    shopt -u nullglob

    if [[ ${#patch_files[@]} -eq 0 ]]; then
        log_warn "No patch files found: ${PATCH_DIR}/*.patch"
        log_warn "Continuing build without patch..."
    else
        IFS=$'\n' patch_files=($(sort <<<"${patch_files[*]}"))
        unset IFS

        PATCH="${patch_files[${#patch_files[@]}-1]}"
        PATCH_NAME=$(basename "$PATCH")
        log_info "Applying patch: ${PATCH_NAME} (latest of ${#patch_files[@]})"

        if git apply --check "$PATCH" 2>/dev/null; then
            git apply "$PATCH"
            log_info "Patch applied successfully"
        else
            log_warn "Patch check failed. Trying with --3way..."
            if git apply --3way "$PATCH"; then
                log_info "Patch applied with --3way"
            else
                log_error "Failed to apply patch: ${PATCH_NAME}"
                exit 1
            fi
        fi

        PATCHED_FILES=$(git diff --name-only HEAD 2>/dev/null | wc -l)
        log_info "Modified files: ${PATCHED_FILES}"
    fi
fi

# ============================================
# Step 5: Build (delegate to build-mainline-linux.sh)
# ============================================
log_step "5/5: Building Linux Mainline"

cd "$PROJECT_ROOT"

BUILD_ARGS=()
if [[ ${FAST_BUILD} -eq 1 ]]; then
    BUILD_ARGS+=(--fast-build)
fi

log_info "Calling build-mainline-linux.sh..."
"${BUILD_HELPER_DIR}/build-mainline-linux.sh" "${BUILD_ARGS[@]}"

# ============================================
# Generate Build Info
# ============================================
log_info "Generating build info..."

mkdir -p "$(dirname "$BUILD_INFO_FILE")"

cat > "$BUILD_INFO_FILE" << BUILDINFO
========================================
Linux Mainline Release Build Information
========================================
Release Version: ${RELEASE_VERSION}
Build Date: $(date -u -d @$SOURCE_DATE_EPOCH 2>/dev/null || date -u)
Source Date Epoch: ${SOURCE_DATE_EPOCH}

Linux Information:
-------------------
Kernel Track: mainline
Commit: ${LINUX_COMMIT}
Version: ${LINUX_DESCRIBE}
Branch: ${LINUX_BRANCH}

Patch Information:
------------------
Patch: ${PATCH_NAME}
Files Modified: ${PATCHED_FILES}

Build Environment:
------------------
Build Host: $(hostname)
User: $(whoami)
Toolchain: arm-none-linux-gnueabihf-

========================================
BUILDINFO

log_info "Build info saved to: $BUILD_INFO_FILE"

# ============================================
# Summary
# ============================================
log_info ""
log_info "========================================"
log_info "Linux Mainline Release Build Complete!"
log_info "========================================"
log_info ""
log_info "Build artifacts:"
log_info "  - ${OUTPUT_DIR}/arch/arm/boot/zImage"
log_info "  - ${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb"
log_info "  - ${OUTPUT_DIR}/vmlinux"
log_info "  - ${OUTPUT_DIR}/System.map"
log_info ""
log_info "Build info:"
log_info "  - ${BUILD_INFO_FILE}"
log_info ""
log_info "For reproducible builds, use:"
log_info "  SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
log_info "========================================"
