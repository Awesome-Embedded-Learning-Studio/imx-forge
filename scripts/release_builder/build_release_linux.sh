#!/usr/bin/env bash
#
# Release Build Script for Linux
#
# This script ensures a reproducible release build by:
# 1. Cleaning and resetting all submodules
# 2. Re-cloning submodules fresh
# 3. Applying patches
# 4. Delegating to the main build script
#
# Usage: ./build_release_linux.sh [release_version]
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
LINUX_DIR="${PROJECT_ROOT}/third_party/linux-imx"
PATCH_DIR="${PROJECT_ROOT}/patches/linux-imx"
PATCH="${PATCH_DIR}/linux-imx-latest.patch"
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/linux}"
BUILD_INFO_FILE="${OUTPUT_DIR}/build_info.txt"

# For reproducible builds - use fixed timestamp
# Update SOURCE_DATE_EPOCH for each release
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1609459200}  # 2021-01-01 00:00:00 UTC
export LC_ALL=C

# ============================================
# Step 1: Reset Linux Submodule to Default Branch
# ============================================
log_step "1/5: Resetting Linux Submodule"

cd "$LINUX_DIR"

# Detect default branch
log_info "Detecting default branch..."
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
# Fallback to lf-6.12.y if detection fails
: "${DEFAULT_BRANCH:=lf-6.12.y}"
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

log_info "Linux submodule reset complete"

# ============================================
# Step 2: Verify Submodule State
# ============================================
log_step "2/5: Verifying Submodule State"

# Show current commit for reproducibility
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

PATCHED_FILES=0
if [ ! -f "$PATCH" ]; then
    log_warn "Patch file not found: $PATCH"
    log_warn "Continuing build without patch..."
    PATCHED_FILES=0
    PATCH_NAME="None"
else
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
    PATCH_NAME=$(basename $PATCH)
    log_info "Modified files: ${PATCHED_FILES}"
fi

# ============================================
# Step 5: Build (delegate to build-linux.sh)
# ============================================
log_step "5/5: Building Linux"

cd "$PROJECT_ROOT"

log_info "Calling build-linux.sh..."
"${BUILD_HELPER_DIR}/build-linux.sh"

# ============================================
# Generate Build Info
# ============================================
log_info "Generating build info..."

mkdir -p "$(dirname "$BUILD_INFO_FILE")"

cat > "$BUILD_INFO_FILE" << BUILDINFO
========================================
Linux Release Build Information
========================================
Release Version: ${1:-unknown}
Build Date: $(date -u -d @$SOURCE_DATE_EPOCH 2>/dev/null || date -u)
Source Date Epoch: ${SOURCE_DATE_EPOCH}

Linux Information:
-------------------
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
log_info "Release Build Complete!"
log_info "========================================"
log_info ""
log_info "Build artifacts:"
log_info "  - ${OUTPUT_DIR}/arch/arm/boot/zImage"
log_info "  - ${OUTPUT_DIR}/vmlinux"
log_info "  - ${OUTPUT_DIR}/System.map"
log_info ""
log_info "Build info:"
log_info "  - ${BUILD_INFO_FILE}"
log_info ""
log_info "For reproducible builds, use:"
log_info "  SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
log_info "========================================"
