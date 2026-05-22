#!/usr/bin/env bash
#
# Release Build Script for U-Boot
#
# This script ensures a reproducible release build by:
# 1. Cleaning and resetting all submodules
# 2. Re-cloning submodules fresh
# 3. Applying patches
# 4. Delegating to the main build script
#
# Usage: ./build_release_uboot.sh [release_version]
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
UBOOT_DIR="${PROJECT_ROOT}/third_party/uboot-imx"
PATCH_DIR="${PROJECT_ROOT}/patches/uboot-imx"
PATCH="${PATCH_DIR}/charlies_board.patch"
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/uboot}"
BUILD_INFO_FILE="${OUTPUT_DIR}/build_info.txt"

# For reproducible builds - use fixed timestamp
# Update SOURCE_DATE_EPOCH for each release
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1609459200}  # 2021-01-01 00:00:00 UTC
export LC_ALL=C

# ============================================
# Step 1: Reset U-Boot Submodule to Default Branch
# ============================================
log_step "1/5: Resetting U-Boot Submodule"

cd "$UBOOT_DIR"

# Detect default branch
log_info "Detecting default branch..."
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
# Fallback to lf_v2025.04 if detection fails
: "${DEFAULT_BRANCH:=lf_v2025.04}"
log_info "Default branch: ${DEFAULT_BRANCH}"

# Fetch upstream to ensure we have latest state
log_info "Fetching from upstream..."
git fetch origin || true

# Clean current working directory first (discard any local changes)
log_info "Cleaning working directory..."
git reset --hard HEAD 2>/dev/null || true
git clean -ffdx

# Switch to default branch
log_info "Switching to ${DEFAULT_BRANCH}..."
# Use -B to force create/reset the branch from origin
git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"

# Reset to match upstream exactly
log_info "Resetting to origin/${DEFAULT_BRANCH}..."
git reset --hard "origin/${DEFAULT_BRANCH}"

# Clean again to ensure pristine state
git clean -ffdx

log_info "U-Boot submodule reset complete"

# ============================================
# Step 2: Verify Submodule State
# ============================================
log_step "2/5: Verifying Submodule State"

# Show current commit for reproducibility
UBOOT_COMMIT=$(git rev-parse HEAD)
UBOOT_DESCRIBE=$(git describe --tags --always 2>/dev/null || echo "no-tags")
UBOOT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

log_info "U-Boot commit: ${UBOOT_COMMIT}"
log_info "U-Boot version: ${UBOOT_DESCRIBE}"
log_info "U-Boot branch: ${UBOOT_BRANCH}"

# ============================================
# Step 3: Create Release Branch
# ============================================
log_step "3/5: Creating Release Branch"

# Generate branch name from date and commit
BRANCH_NAME="release-build-$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
log_info "Creating branch: ${BRANCH_NAME}"

# Delete branch if it already exists
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    log_info "Branch ${BRANCH_NAME} already exists, deleting it..."
    git branch -D "$BRANCH_NAME"
fi

git checkout -b "$BRANCH_NAME"

log_info "Release branch created"

# ============================================
# Step 4: Apply Patch
# ============================================
log_step "4/5: Applying Patch"

if [ ! -f "$PATCH" ]; then
    log_error "Patch file not found: $PATCH"
    exit 1
fi

log_info "Applying patch: $(basename $PATCH)"
if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    log_info "Patch applied successfully"
else
    log_warn "Patch check failed. Trying with --3way..."
    if git apply --3way "$PATCH"; then
        log_info "Patch applied with --3way"
    else
        log_error "Failed to apply patch"
        exit 1
    fi
fi

# Show patch summary
PATCHED_FILES=$(git diff --name-only HEAD 2>/dev/null | wc -l)
log_info "Modified files: ${PATCHED_FILES}"

# ============================================
# Step 5: Build (delegate to build-uboot.sh)
# ============================================
log_step "5/5: Building U-Boot"

cd "$PROJECT_ROOT"

# 导入依赖检查脚本
source "${SCRIPT_DIR}/../init/env-init.sh"

# 检查依赖
check_uboot_dependencies || {
    log_error "Dependency check failed"
    exit 1
}

log_info "Calling build-uboot.sh..."
"${BUILD_HELPER_DIR}/build-uboot.sh"

# ============================================
# Generate Build Info
# ============================================
log_info "Generating build info..."

mkdir -p "$(dirname "$BUILD_INFO_FILE")"

cat > "$BUILD_INFO_FILE" << BUILDINFO
========================================
U-Boot Release Build Information
========================================
Release Version: ${1:-unknown}
Build Date: $(date -u -d @$SOURCE_DATE_EPOCH 2>/dev/null || date -u)
Source Date Epoch: ${SOURCE_DATE_EPOCH}

U-Boot Information:
-------------------
Commit: ${UBOOT_COMMIT}
Version: ${UBOOT_DESCRIBE}
Branch: ${UBOOT_BRANCH}

Patch Information:
------------------
Patch: $(basename $PATCH)
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
log_info "Release Build Complete!"
log_info "========================================"
log_info ""
log_info "Build artifacts:"
log_info "  - ${OUTPUT_DIR}/u-boot-dtb.imx"
log_info "  - ${OUTPUT_DIR}/u-boot-dtb.bin"
log_info "  - ${OUTPUT_DIR}/u-boot.dtb"
log_info ""
log_info "Build info:"
log_info "  - ${BUILD_INFO_FILE}"
log_info ""
log_info "For reproducible builds, use:"
log_info "  SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
log_info "========================================"
