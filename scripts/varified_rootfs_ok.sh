#!/bin/bash
#
# RootFS Verification and Completion Script
#
# Usage:
#   scripts/varified_rootfs_ok.sh --rootfs-dir=rootfs/nfs
#

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"
THIRD_PARTY_INSTALL_DIR="${SCRIPT_DIR}/third_party_install"

# Source shared logging (with fallback for standalone usage)
if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_debug() { if [[ "${DEBUG:-0}" == "1" ]]; then echo -e "${BLUE}[DEBUG]${NC} $1"; fi; }
    log_cmd()   { echo -e "${YELLOW}[CMD]${NC} $1"; }
fi

# Configuration
CROSS_COMPILE=arm-none-linux-gnueabihf-
ROOTFS_DIR=""
SHOW_HELP=0

# Required directories in rootfs
REQUIRED_DIRS=("bin" "sbin" "usr")

# All directories to ensure exist in rootfs
ROOTFS_DIRS=("bin" "dev" "etc" "lib" "mnt" "proc" "root" "sbin" "sys" "tmp" "usr" "home")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            SHOW_HELP=1
            ;;
        --rootfs-dir=*)
            ROOTFS_DIR="${1#*=}"
            ;;
        --rootfs-dir)
            shift
            ROOTFS_DIR="$1"
            ;;
        *)
            log_error "Unknown option: $1"
            SHOW_HELP=1
            ;;
    esac
    shift
done

# Default rootfs directory
: "${ROOTFS_DIR:=${PROJECT_ROOT}/rootfs/nfs}"

# Display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --rootfs-dir=PATH    Path to rootfs directory (default: rootfs/nfs)
  --help, -h           Show this help message

Description:
  This script verifies and completes a root filesystem by:
  1. Checking that the directory is safe (not / or pointing to /)
  2. Verifying required directories exist (bin, sbin, usr)
  3. Creating missing standard directories
  4. Installing system configuration files (fstab, rcS, inittab)
  5. Running third-party dependency installation scripts

Examples:
  $0                                    # Use default rootfs/nfs
  $0 --rootfs-dir=rootfs/nfs            # Specify rootfs directory
  $0 --rootfs-dir=/path/to/rootfs       # Use custom path

EOF
}

# Check if directory is safe (not / or pointing to /)
check_directory_safe() {
    local dir="$1"

    # Check if directory is exactly /
    if [[ "$dir" == "/" ]]; then
        log_error "Rootfs directory cannot be '/'"
        return 1
    fi

    # Resolve to absolute path
    local abs_dir
    abs_dir="$(cd "$dir" 2>/dev/null && pwd)" || {
        log_error "Cannot access directory: $dir"
        return 1
    }

    # Check if resolved path is /
    if [[ "$abs_dir" == "/" ]]; then
        log_error "Rootfs directory resolves to '/' (unsafe)"
        return 1
    fi

    log_debug "Directory safety check passed: $abs_dir"
    return 0
}

# Check if required directories exist
check_required_dirs() {
    local rootfs="$1"
    local missing=()
    local found=()

    for dir in "${REQUIRED_DIRS[@]}"; do
        if [[ -d "${rootfs}/${dir}" ]]; then
            found+=("$dir")
        else
            missing+=("$dir")
        fi
    done

    if [[ ${#found[@]} -gt 0 ]]; then
        log_info "Found required directories: ${found[*]}"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required directories: ${missing[*]}"
        log_error "Please ensure your rootfs has at least: bin, sbin, usr"
        return 1
    fi

    return 0
}

# Create rootfs directory structure
create_rootfs_structure() {
    local rootfs="$1"

    log_info "Creating rootfs directory structure..."

    for dir in "${ROOTFS_DIRS[@]}"; do
        local target="${rootfs}/${dir}"
        if [[ ! -d "$target" ]]; then
            log_debug "  Creating: $dir"
            mkdir -p "$target"
        else
            log_debug "  Exists: $dir"
        fi
    done

    # Preserve existing linuxrc symlink or create to busybox
    local linuxrc="${rootfs}/linuxrc"
    if [[ ! -e "$linuxrc" ]]; then
        log_info "Creating linuxrc -> bin/busybox symlink"
        ln -sf bin/busybox "$linuxrc"
    elif [[ -L "$linuxrc" ]]; then
        local target
        target="$(readlink "$linuxrc")"
        log_info "Preserving existing linuxrc -> $target"
    else
        log_warn "linuxrc exists but is not a symlink"
    fi

    log_info "Rootfs directory structure created"
}

# Create fstab configuration
create_fstab() {
    local rootfs="$1"
    local fstab_file="${rootfs}/etc/fstab"

    log_info "Creating etc/fstab..."

    # Remove existing file if present and writable
    if [[ -e "$fstab_file" ]]; then
        if [[ -w "$fstab_file" ]]; then
            rm -f "$fstab_file"
        elif [[ -w "${rootfs}/etc" ]]; then
            # Directory is writable but file is not, try to remove
            rm -f "$fstab_file" 2>/dev/null || true
        else
            log_warn "  Cannot remove existing file (not writable)"
            log_warn "  Skipping fstab creation"
            return 0
        fi
    fi

    # Create the file
    cat > "$fstab_file" << 'EOF'
#<file system>  <mount point>   <type>  <options>   <dump>  <pass>
proc            /proc           proc    defaults    0       0
tmpfs           /tmp            tmpfs   defaults    0       0
sysfs           /sys            sysfs   defaults    0       0
EOF

    log_info "  Created: $fstab_file"
}

# Create rcS init script
create_rcs() {
    local rootfs="$1"
    local rcs_file="${rootfs}/etc/init.d/rcS"

    log_info "Creating etc/init.d/rcS..."

    mkdir -p "${rootfs}/etc/init.d"

    # Check if we can write to the target location
    if [[ -e "$rcs_file" ]] && [[ ! -w "$rcs_file" ]] && [[ ! -w "${rootfs}/etc/init.d" ]]; then
        log_warn "  Cannot write to $rcs_file (not writable)"
        log_warn "  Skipping rcS creation"
        return 0
    fi

    cat > "$rcs_file" << 'EOF'
#!/bin/sh
#
# System initialization script
#

PATH=/sbin:/bin:/usr/sbin:/usr/bin:$PATH
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/lib
export LD_LIBRARY_PATH

# Mount all filesystems specified in fstab
mount -a

# Create and mount devpts for pseudo-terminal support
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

# Populate /dev with device nodes
mdev -s
EOF

    chmod +x "$rcs_file" 2>/dev/null || true
    log_info "  Created: $rcs_file (executable)"
}

# Create inittab configuration
create_inittab() {
    local rootfs="$1"
    local inittab_file="${rootfs}/etc/inittab"

    log_info "Creating etc/inittab..."

    # Check if we can write to the target location
    if [[ -e "$inittab_file" ]] && [[ ! -w "$inittab_file" ]] && [[ ! -w "${rootfs}/etc" ]]; then
        log_warn "  Cannot write to $inittab_file (not writable)"
        log_warn "  Skipping inittab creation"
        return 0
    fi

    cat > "$inittab_file" << 'EOF'
# /etc/inittab - init process configuration

# System initialization
::sysinit:/etc/init.d/rcS

# Console getty (askfirst = prompt before starting shell)
console::askfirst:-/bin/sh

# Restart handling
::restart:/sbin/init

# Ctrl+Alt+Del handling
::ctrlaltdel:/sbin/reboot

# Shutdown actions
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
EOF

    log_info "  Created: $inittab_file"
}

# Run third-party installation scripts
run_third_party_installs() {
    local rootfs="$1"

    # Skip third-party installations if requested
    if [[ "${SKIP_THIRD_PARTY_INSTALL:-false}" == "true" ]]; then
        log_info "Skipping third-party installations (SKIP_THIRD_PARTY_INSTALL=true)"
        return 0
    fi

    if [[ ! -d "$THIRD_PARTY_INSTALL_DIR" ]]; then
        log_debug "Third-party install directory not found: $THIRD_PARTY_INSTALL_DIR"
        return 0
    fi

    # Find all .sh scripts in third_party_install directory
    local scripts=()
    while IFS= read -r -d '' script; do
        # Skip README files and hidden files
        local basename
        basename="$(basename "$script")"
        if [[ "$basename" == README* ]] || [[ "$basename" == .* ]]; then
            continue
        fi
        scripts+=("$script")
    done < <(find "$THIRD_PARTY_INSTALL_DIR" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)

    if [[ ${#scripts[@]} -eq 0 ]]; then
        log_debug "No third-party installation scripts found"
        return 0
    fi

    log_info "Running third-party installation scripts..."

    # 任一安装脚本失败将使本函数返回非零；循环仍继续以便一次看到所有失败，
    # 但最终致命 —— 不再像过去那样 "continuing anyway" 后还打印 RootFS 成功（issue #76）。
    local failed=0
    for script in "${scripts[@]}"; do
        local name
        name="$(basename "$script")"
        log_info "  Executing: $name"

        # Export ROOTFS_DIR for scripts to use
        export ROOTFS_DIR="$rootfs"
        export PROJECT_ROOT="$PROJECT_ROOT"

        if bash "$script"; then
            log_info "    ✓ $name completed"
        else
            log_error "    ✗ $name failed"
            failed=1
        fi
    done

    log_info "Third-party installations completed"
    return $failed
}

# Verify rootfs completion
verify_rootfs() {
    local rootfs="$1"

    log_info "Verifying rootfs completion..."

    local all_ok=1

    # Check directories
    for dir in "${ROOTFS_DIRS[@]}"; do
        if [[ -d "${rootfs}/${dir}" ]]; then
            log_debug "  ✓ ${dir}/ exists"
        else
            log_error "  ✗ ${dir}/ missing"
            all_ok=0
        fi
    done

    # Check linuxrc
    if [[ -e "${rootfs}/linuxrc" ]]; then
        log_debug "  ✓ linuxrc exists"
    else
        log_warn "  ! linuxrc missing"
    fi

    # Check config files
    local config_files=("etc/fstab" "etc/init.d/rcS" "etc/inittab")
    for file in "${config_files[@]}"; do
        if [[ -f "${rootfs}/${file}" ]]; then
            log_debug "  ✓ ${file} exists"
        else
            log_error "  ✗ ${file} missing"
            all_ok=0
        fi
    done

    if [[ $all_ok -eq 1 ]]; then
        log_info "Rootfs verification passed"
        return 0
    else
        log_error "Rootfs verification failed"
        return 1
    fi
}

# Verify Qt artifacts (only invoked when third-party install actually ran).
# 致命集：任何 Qt6 构建必产出的核心产物，缺失即判定 Qt 安装失败。
# 软警告集：qmake 等 host 工具可能被裁剪部署，缺失只 warn 不致命。
verify_qt_artifacts() {
    local rootfs="$1"

    log_info "Verifying Qt artifacts..."

    local all_ok=1

    # 致命：libQt6Core.so*（Qt6 核心 .so；glob 兼容 .so / .so.6 / .so.6.x.x）
    local qt_core_hit
    qt_core_hit=$(compgen -G "${rootfs}/usr/lib/libQt6Core.so*" 2>/dev/null | head -1)
    if [[ -n "$qt_core_hit" ]]; then
        log_debug "  ✓ libQt6Core.so found"
    else
        log_error "  ✗ libQt6Core.so* missing under ${rootfs}/usr/lib/"
        all_ok=0
    fi

    # 致命：plugins/platforms/ 非空（target.conf 强制 FEATURE_linuxfb=ON，必有 libqlinuxfb.so）
    local platforms_dir="${rootfs}/usr/lib/qt6/plugins/platforms"
    if [[ -d "$platforms_dir" ]] && [[ -n "$(ls -A "$platforms_dir" 2>/dev/null)" ]]; then
        log_debug "  ✓ Qt platform plugins present"
    else
        log_error "  ✗ Qt platform plugins missing or empty: ${platforms_dir}"
        all_ok=0
    fi

    # 软警告：qmake（host 工具，裁剪部署可能省略）
    if [[ -f "${rootfs}/usr/bin/qmake" ]] || [[ -f "${rootfs}/usr/bin/qmake6" ]]; then
        log_debug "  ✓ qmake found"
    else
        log_warn "  ! qmake not found under ${rootfs}/usr/bin/ (host tool, may be stripped)"
    fi

    if [[ $all_ok -eq 1 ]]; then
        log_info "Qt artifact verification passed"
        return 0
    else
        log_error "Qt artifact verification failed"
        return 1
    fi
}

# Main function
main() {
    # Handle help
    if [ ${SHOW_HELP} -eq 1 ]; then
        show_usage
        exit 0
    fi

    log_info "========================================"
    log_info "RootFS Verification and Completion"
    log_info "========================================"
    log_info "Rootfs directory: ${ROOTFS_DIR}"
    log_info "Cross compiler:   ${CROSS_COMPILE}gcc"
    log_info ""

    # Safety checks
    log_info "Step 1: Safety checks..."
    check_directory_safe "$ROOTFS_DIR" || exit 1
    log_info "  ✓ Directory is safe"
    log_info ""

    # Check required directories
    log_info "Step 2: Verifying required directories..."
    check_required_dirs "$ROOTFS_DIR" || exit 1
    log_info "  ✓ All required directories present"
    log_info ""

    # Create directory structure
    log_info "Step 3: Creating directory structure..."
    create_rootfs_structure "$ROOTFS_DIR"
    log_info ""

    # Create configuration files
    log_info "Step 4: Creating configuration files..."
    create_fstab "$ROOTFS_DIR"
    create_rcs "$ROOTFS_DIR"
    create_inittab "$ROOTFS_DIR"
    log_info ""

    # Run third-party installations
    log_info "Step 5: Running third-party installations..."
    run_third_party_installs "$ROOTFS_DIR" || { log_error "Third-party installation failed"; exit 1; }
    log_info ""

    # Verify
    log_info "Step 6: Verifying completion..."
    verify_rootfs "$ROOTFS_DIR" || { log_error "Rootfs verification failed"; exit 1; }

    # Qt 产物校验：仅在第三方安装实际执行（未被 SKIP）且 install_qt_with_compile.sh 存在时进行，
    # 避免误伤默认 CI（SKIP_THIRD_PARTY_INSTALL=true 时不装 Qt）。
    if [[ "${SKIP_THIRD_PARTY_INSTALL:-false}" != "true" \
        && -f "${THIRD_PARTY_INSTALL_DIR}/install_qt_with_compile.sh" ]]; then
        verify_qt_artifacts "$ROOTFS_DIR" || { log_error "Qt artifact verification failed"; exit 1; }
    fi
    log_info ""

    log_info "========================================"
    log_info "RootFS completed successfully!"
    log_info "========================================"
    log_info ""
    log_info "Your rootfs is ready at: ${ROOTFS_DIR}"
    log_info ""
    log_info "To use this rootfs:"
    log_info "  1. Export via NFS: ${ROOTFS_DIR}"
    log_info "  2. Set bootargs to mount NFS root"
    log_info "  3. Boot your board"
}

main "$@"
