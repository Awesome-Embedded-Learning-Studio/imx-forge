#!/bin/bash
#
# release.sh — release 编排共享库(给 build_helper/build-*.sh 的 --release 模式用)
#
# 封装原先散在 release_builder/build_release_*.sh(已退役)的编排能力:
#   reset 净源码 → 打 patch → 建 release 分支 → 可复现时间戳 → 生成 build_info.txt
#
# 调用方(build-uboot.sh / build-linux.sh / build-mainline-linux.sh)在 --release 模式下:
#   source "${SCRIPT_LIB_DIR}/release.sh"
#   release_prepare "<component>" "${SRC_DIR}" "<patch-arg>" ["${PROJECT_ROOT}"]
#   ... # 原有 distclean/configure/build/verify 流程完全不变
#   release_finalize "<component>" "${OUTPUT_DIR}" ["${release-version}"]
#
# component : uboot | linux-imx | linux-mainline
# patch-arg : uboot/linux-imx = patch 文件路径(linux-imx 可缺);
#             linux-mainline  = patch 目录路径(取目录内最新 *.patch)
#
# 设计要点:
#   * 不改变调用方 cwd —— git 一律走 `git -C "$src"`,这样 build-*.sh 后续步骤(logo_helper /
#     do_build 等)不受影响。
#   * 复用调用方的 log_info/log_warn/log_error(logging.sh 提供);log_step 自带兜底。
#   * 适配 set -eo pipefail:所有 `$(git ... | sed/wc)` 管道尾部加 `|| true`,避免上游 git
#     非零退出被 pipefail 放大成整个管道失败而误中止(原 release_builder 只有 set -e 无此问题)。
#   * 元数据经全局变量 RELEASE_COMMIT/RELEASE_DESCRIBE/RELEASE_BRANCH_REF/
#     RELEASE_PATCH_NAME/RELEASE_PATCHED_FILES 在 prepare→finalize 间传递。

# 双重 source 守卫
[[ "${_RELEASE_SH_SOURCED:-0}" == "1" ]] && return 0
_RELEASE_SH_SOURCED=1

# ---------------------------------------------------------------------------
# 兜底日志(调用方一般已 source logging.sh;仅当缺失时补齐)
# ---------------------------------------------------------------------------
if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
    log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $1"; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&2; }
fi
if ! declare -f log_step >/dev/null 2>&1; then
    log_step() { echo -e "\033[0;34m[STEP]\033[0m $1"; }
fi

# prepare 写入 / finalize 读取 的全局状态
RELEASE_COMMIT=""
RELEASE_DESCRIBE=""
RELEASE_BRANCH_REF=""
RELEASE_PATCH_NAME="None"
RELEASE_PATCHED_FILES=0

# ---------------------------------------------------------------------------
# release_prepare <component> <source-dir> <patch-arg> [<project-root>]
# ---------------------------------------------------------------------------
release_prepare() {
    local component="$1"
    local src="$2"
    local patch_arg="$3"
    local project_root="${4:-}"

    case "$component" in
        uboot|linux-imx|linux-mainline) ;;
        *) log_error "release_prepare: unknown component '$component'"; exit 1 ;;
    esac
    [[ -d "$src" ]] || { log_error "release_prepare: source dir not found: $src"; exit 1; }

    log_step "release_prepare [${component}]: reproducible env"
    case "$component" in
        uboot) : "${SOURCE_DATE_EPOCH:=$(date -u +%s)}" ;;             # 默认当前时间
        linux-imx|linux-mainline) : "${SOURCE_DATE_EPOCH:=1609459200}" ;;  # 固定 2021-01-01 UTC
    esac
    export SOURCE_DATE_EPOCH
    export LC_ALL=C

    log_warn "release_prepare: about to reset/clean ${src} to pristine upstream state — uncommitted changes will be lost."

    # --- reset 净源码 ---
    if [[ "$component" == "linux-mainline" ]]; then
        _release_reset_mainline "$src" "$project_root"
    else
        _release_reset_to_origin "$src" "$component"
    fi

    # --- 捕获元数据 ---
    RELEASE_COMMIT=$(git -C "$src" rev-parse HEAD)
    RELEASE_DESCRIBE=$(git -C "$src" describe --tags --always 2>/dev/null || echo "no-tags")
    RELEASE_BRANCH_REF=$(git -C "$src" rev-parse --abbrev-ref HEAD)
    log_info "${component} commit : ${RELEASE_COMMIT}"
    log_info "${component} version: ${RELEASE_DESCRIBE}"
    log_info "${component} branch : ${RELEASE_BRANCH_REF}"

    # --- 建 release 分支 ---
    _release_create_branch "$src" "$component"

    # --- 打 patch ---
    _release_apply_patch "$component" "$src" "$patch_arg"
}

# uboot / linux-imx:跟 origin 默认分支
_release_reset_to_origin() {
    local src="$1"
    local component="$2"

    local fallback_branch
    case "$component" in
        uboot)     fallback_branch="lf_v2025.04" ;;
        linux-imx) fallback_branch="lf-6.12.y"   ;;
    esac

    local default_branch
    default_branch=$(git -C "$src" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                     | sed 's@^refs/remotes/origin/@@' || true)
    : "${default_branch:=$fallback_branch}"
    log_info "Default branch: ${default_branch}"

    log_info "Fetching from upstream..."
    git -C "$src" fetch origin || true

    log_info "Cleaning working directory..."
    git -C "$src" reset --hard HEAD 2>/dev/null || true
    git -C "$src" clean -ffdx

    log_info "Switching to ${default_branch}..."
    git -C "$src" checkout -B "$default_branch" "origin/$default_branch"
    git -C "$src" reset --hard "origin/$default_branch"
    git -C "$src" clean -ffdx

    log_info "${component} submodule reset complete"
}

# linux-mainline:锁定到超项目 gitlink commit(detached)
_release_reset_mainline() {
    local src="$1"
    local project_root="$2"

    [[ -n "$project_root" ]] || { log_error "release_prepare: linux-mainline requires <project-root> arg"; exit 1; }

    local locked_commit
    locked_commit=$(git -C "$project_root" rev-parse HEAD:third_party/linux_mainline) \
        || { log_error "release_prepare: cannot resolve linux_mainline gitlink from superproject"; exit 1; }
    log_info "Locked commit from superproject: ${locked_commit}"

    if ! git -C "$src" cat-file -e "${locked_commit}^{commit}" 2>/dev/null; then
        log_info "Locked commit not present locally; initializing submodule..."
        git -C "$project_root" submodule update --init --depth=1 third_party/linux_mainline
    fi
    if ! git -C "$src" cat-file -e "${locked_commit}^{commit}" 2>/dev/null; then
        log_error "release_prepare: locked mainline commit unavailable locally: ${locked_commit}"
        exit 1
    fi

    log_info "Cleaning working directory..."
    git -C "$src" reset --hard HEAD 2>/dev/null || true
    git -C "$src" clean -ffdx

    log_info "Checking out locked commit..."
    git -C "$src" checkout --detach "$locked_commit"
    git -C "$src" reset --hard "$locked_commit"
    git -C "$src" clean -ffdx

    log_info "linux_mainline submodule reset complete at locked commit"
}

_release_create_branch() {
    local src="$1"
    local component="$2"

    local prefix
    case "$component" in
        linux-mainline) prefix="release-mainline-build" ;;
        *)              prefix="release-build" ;;
    esac
    local branch_name="${prefix}-$(date +%Y%m%d)-$(git -C "$src" rev-parse --short HEAD)"
    log_info "Creating branch: ${branch_name}"

    if git -C "$src" show-ref --verify --quiet "refs/heads/${branch_name}"; then
        log_info "Branch ${branch_name} already exists, deleting it..."
        git -C "$src" branch -D "$branch_name"
    fi
    git -C "$src" checkout -b "$branch_name"
}

# 按 component 打 patch(必需/可选/目录取最新)
_release_apply_patch() {
    local component="$1"
    local src="$2"
    local patch_arg="$3"

    local patch_file=""
    case "$component" in
        uboot)
            [[ -f "$patch_arg" ]] || { log_error "Patch file not found: $patch_arg"; exit 1; }
            patch_file="$patch_arg"
            ;;
        linux-imx)
            if [[ ! -f "$patch_arg" ]]; then
                log_warn "Patch file not found: $patch_arg"
                log_warn "Continuing build without patch..."
                RELEASE_PATCH_NAME="None"
                RELEASE_PATCHED_FILES=0
                return 0
            fi
            patch_file="$patch_arg"
            ;;
        linux-mainline)
            if [[ ! -d "$patch_arg" ]]; then
                log_warn "Patch directory not found: $patch_arg"
                log_warn "Continuing build without patch..."
                return 0
            fi
            shopt -s nullglob
            local files=("${patch_arg}"/*.patch)
            shopt -u nullglob
            if [[ ${#files[@]} -eq 0 ]]; then
                log_warn "No patch files found: ${patch_arg}/*.patch"
                log_warn "Continuing build without patch..."
                return 0
            fi
            IFS=$'\n' files=($(sort <<<"${files[*]}")); unset IFS
            patch_file="${files[${#files[@]}-1]}"
            log_info "Applying patch: $(basename "$patch_file") (latest of ${#files[@]})"
            ;;
    esac

    log_info "Applying patch: $(basename "$patch_file")"
    if git -C "$src" apply --check "$patch_file" 2>/dev/null; then
        git -C "$src" apply "$patch_file"
        log_info "Patch applied successfully"
    else
        log_warn "Patch check failed. Trying with --3way..."
        if git -C "$src" apply --3way "$patch_file"; then
            log_info "Patch applied with --3way"
        else
            log_error "Failed to apply patch: $(basename "$patch_file")"
            exit 1
        fi
    fi

    RELEASE_PATCHED_FILES=$(git -C "$src" diff --name-only HEAD 2>/dev/null | wc -l || true)
    RELEASE_PATCH_NAME=$(basename "$patch_file")
    log_info "Modified files: ${RELEASE_PATCHED_FILES}"
}

# ---------------------------------------------------------------------------
# release_finalize <component> <output-dir> [<release-version>]
# 写 build_info.txt。linux 两轨必须含 `Kernel Track:` 行(release-all Stage2 grep 硬依赖)。
# ---------------------------------------------------------------------------
release_finalize() {
    local component="$1"
    local output_dir="$2"
    local release_version="${3:-unknown}"

    local build_info_file="${output_dir}/build_info.txt"
    mkdir -p "$(dirname "$build_info_file")"

    local header info_label track_line
    case "$component" in
        uboot)
            header="U-Boot Release Build Information"
            info_label="U-Boot"
            track_line=""
            ;;
        linux-imx)
            header="Linux Release Build Information"
            info_label="Linux"
            track_line="Kernel Track: imx"
            ;;
        linux-mainline)
            header="Linux Mainline Release Build Information"
            info_label="Linux"
            track_line="Kernel Track: mainline"
            ;;
        *) log_error "release_finalize: unknown component '$component'"; exit 1 ;;
    esac

    log_info "Generating build info..."
    {
        echo "========================================"
        echo "${header}"
        echo "========================================"
        echo "Release Version: ${release_version}"
        echo "Build Date: $(date -u -d "@${SOURCE_DATE_EPOCH}" 2>/dev/null || date -u)"
        echo "Source Date Epoch: ${SOURCE_DATE_EPOCH}"
        echo ""
        echo "${info_label} Information:"
        echo "-------------------"
        [[ -n "$track_line" ]] && echo "${track_line}"
        echo "Commit: ${RELEASE_COMMIT}"
        echo "Version: ${RELEASE_DESCRIBE}"
        echo "Branch: ${RELEASE_BRANCH_REF}"
        echo ""
        echo "Patch Information:"
        echo "------------------"
        echo "Patch: ${RELEASE_PATCH_NAME}"
        echo "Files Modified: ${RELEASE_PATCHED_FILES}"
        echo ""
        echo "Build Environment:"
        echo "------------------"
        echo "Build Host: $(hostname)"
        echo "User: $(whoami)"
        echo "Toolchain: arm-none-linux-gnueabihf-"
        echo ""
        echo "========================================"
    } > "$build_info_file"

    log_info "Build info saved to: ${build_info_file}"
}
