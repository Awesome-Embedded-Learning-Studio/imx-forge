#!/usr/bin/env bash
set -e

# ===== 配置 =====
TEMP_BMP=".tmp.logo.bmp"
TARGET_SIZE="${1:-800x480}"
INPUT_PNG="${2:-document/logo/logo.png}"
TARGET_BMP="${3:-third_party/uboot-mainline/tools/logos/denx.bmp}"

# ===== 查找项目根目录 =====
find_repo_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.git" ] || [ -d "$dir/.git" ] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

REPO_ROOT="$(find_repo_root)"
if [ -z "$REPO_ROOT" ]; then
    echo "Error: Cannot find repository root."
    exit 1
fi

echo "Repository root: $REPO_ROOT"

# ===== 构建绝对路径 =====
INPUT_PATH="$REPO_ROOT/$INPUT_PNG"
TEMP_PATH="$REPO_ROOT/$TEMP_BMP"
TARGET_PATH="$REPO_ROOT/$TARGET_BMP"

# ===== 打印参数表格 =====
echo ""
echo "==================== Logo Helper Parameters ===================="
printf "%-20s %-s\n" "Parameter" "Value"
printf "%-20s %-s\n" "---------" "-----"
printf "%-20s %-s\n" "Target Size" "$TARGET_SIZE"
printf "%-20s %-s\n" "Input PNG" "$INPUT_PATH"
printf "%-20s %-s\n" "Target BMP" "$TARGET_PATH"
echo "=============================================================="
echo ""

# ===== 检查 ImageMagick =====
if ! command -v convert >/dev/null 2>&1; then
    echo "Error: ImageMagick (convert) not found."
    echo "Install with:"
    echo "  sudo apt install imagemagick"
    exit 1
fi

# ===== 检查输入文件 =====
if [ ! -f "$INPUT_PATH" ]; then
    echo "Error: Input PNG not found: $INPUT_PATH"
    exit 1
fi

echo "Found PNG: $INPUT_PATH"

# ===== 转换 =====
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -depth 8 \
    bmp3:"$TEMP_PATH"

echo "Generated temporary BMP: $TEMP_PATH"

# ===== 拷贝到目标位置 =====
TARGET_DIR="$(dirname "$TARGET_PATH")"
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

cp "$TEMP_PATH" "$TARGET_PATH"
echo "Copied to: $TARGET_PATH"

# ===== 清理临时文件 =====
rm -f "$TEMP_PATH"
echo "Cleaned up temporary file"

# ===== 验证 =====
file "$TARGET_PATH"

echo ""
echo "==================== Convert Success! ===================="
echo "See $TARGET_PATH to check!"
echo "=========================================================="