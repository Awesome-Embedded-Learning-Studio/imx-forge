# logo_helper.sh - Logo转换工具详解

## 脚本概述

`logo_helper.sh` 是 IMX-Forge 项目中用于将 PNG 格式的 Logo 图片转换为 U-Boot 可用的 BMP 格式的辅助脚本。它简化了 Logo 图片的准备流程，自动化了图片格式转换、尺寸调整和文件部署等操作。

### 核心功能

- **自动格式转换**：将 PNG 图片转换为 BMP 格式（BMP3，8位深度）
- **尺寸调整**：强制调整图片到指定尺寸（不保持宽高比）
- **Alpha通道处理**：自动去除透明通道，确保BMP兼容性
- **自动部署**：将转换后的BMP文件直接复制到U-Boot源码的logos目录
- **参数验证**：检查依赖工具和输入文件是否存在
- **路径解析**：自动查找项目根目录，支持从任意位置调用

### 设计理念

这个脚本遵循"简单即美"的设计原则。它只做一件事：将PNG图片转换为U-Boot可以使用的BMP格式。

**为什么需要这个脚本**：

1. **U-Boot的Logo要求特殊**：U-Boot的 `bmp_logo` 工具对输入BMP格式有严格要求（必须是无压缩、特定位深的BMP）
2. **手动转换繁琐**：使用ImageMagick手动转换需要记住多个参数，容易出错
3. **自动化部署**：转换后直接放到U-Boot源码目录，省去手动复制的步骤
4. **开发效率**：开发阶段需要频繁调整Logo，自动化工具大大提高效率

### 在构建流程中的位置

```
┌─────────────────────────────────────────────────────────────┐
│  U-Boot 构建流程                                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  1. Logo准备阶段                                             │
│     ┌───────────────────────────────────────────────────┐   │
│     │  logo_helper.sh                                  │   │
│     │    PNG → BMP → third_party/uboot-mainline/tools/logos/│   │
│     └───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 代码编译阶段                                             │
│     ┌───────────────────────────────────────────────────┐   │
│     │  bmp_logo 工具                                   │   │
│     │    BMP → C头文件 → 编译进u-boot.bin               │   │
│     └───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 运行时显示                                               │
│     U-Boot启动时显示Logo                                    │
└─────────────────────────────────────────────────────────────┘
```

### 依赖关系

```
logo_helper.sh
    ├─ ImageMagick (convert 命令)
    ├─ Git (用于查找项目根目录)
    └─ Bash 4+
```

被调用方：

```
├─ build-uboot.sh (构建U-Boot时自动调用)
└─ 手动调用 (开发者调试时)
```

## 使用方法

### 基本用法

```bash
# 使用默认参数（推荐）
./scripts/logo_helper/logo_helper.sh

# 指定输出尺寸
./scripts/logo_helper/logo_helper.sh 1024x600

# 完整自定义参数
./scripts/logo_helper/logo_helper.sh <尺寸> <输入PNG> <输出BMP>
./scripts/logo_helper/logo_helper.sh 800x480 custom/logo.png custom/output.bmp
```

### 命令行参数

| 位置参数 | 说明 | 默认值 | 示例 |
|---------|------|--------|------|
| `$1` | 目标BMP尺寸（宽x高） | `800x480` | `1024x600` |
| `$2` | 输入PNG文件路径（相对于项目根目录） | `document/logo/logo.png` | `custom/mylogo.png` |
| `$3` | 输出BMP文件路径（相对于项目根目录） | `third_party/uboot-mainline/tools/logos/denx.bmp` | `custom/output.bmp` |

**注意**：
- 尺寸参数使用 `!` 强制调整，不保持宽高比
- 如果Logo比例与目标尺寸不符，图片会变形

### 环境变量

此脚本不使用环境变量配置。所有参数通过命令行传递。

## 执行流程

### 总体架构

脚本的执行流程可以分为以下几个阶段：

```
┌─────────────────────────────────────────────────────────────┐
│  1. 初始化阶段                                               │
│     - 解析命令行参数                                         │
│     - 查找项目根目录                                         │
│     - 构建绝对路径                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 预检查阶段                                               │
│     - check_imagemagick()                                   │
│     - check_input_file()                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 转换阶段                                                 │
│     - do_convert()                                          │
│     - ImageMagick convert 命令                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 部署阶段                                                 │
│     - ensure_target_dir()                                   │
│     - copy_to_target()                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. 清理阶段                                                 │
│     - cleanup_temp_file()                                   │
│     - verify_output()                                       │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### find_repo_root()

**作用**：自动查找Git仓库根目录。

**实现方式**：

```bash
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
```

**工作原理**：

1. 从当前目录开始
2. 检查当前目录是否是Git仓库根目录（存在 `.git` 文件或目录）
3. 如果不是，向上移动到父目录
4. 重复直到找到根目录或到达文件系统根目录

**为什么需要这个函数**：

- 脚本可以从项目任意位置调用
- 路径参数可以相对于项目根目录，便于使用
- 避免硬编码绝对路径

#### 参数解析

脚本使用位置参数直接获取配置：

```bash
TARGET_SIZE="${1:-800x480}"
INPUT_PNG="${2:-document/logo/logo.png}"
TARGET_BMP="${3:-third_party/uboot-mainline/tools/logos/denx.bmp}"
```

**参数说明**：

- `${1:-default}`：使用第一个参数，如果为空则使用默认值
- `:-` 语法：Bash参数扩展，提供默认值

#### 参数打印

脚本在开始转换前会打印参数表格：

```
==================== Logo Helper Parameters ====================
Parameter            Value
---------            -----
Target Size          800x480
Input PNG            /path/to/imx-forge/document/logo/logo.png
Target BMP           /path/to/imx-forge/third_party/uboot-mainline/tools/logos/denx.bmp
==============================================================
```

**好处**：

- 让用户确认参数是否正确
- 便于调试问题
- 清晰显示绝对路径

#### 依赖检查

**ImageMagick检查**：

```bash
if ! command -v convert >/dev/null 2>&1; then
    echo "Error: ImageMagick (convert) not found."
    echo "Install with:"
    echo "  sudo apt install imagemagick"
    exit 1
fi
```

**检查方式**：

- `command -v convert`：检查命令是否存在
- `>/dev/null 2>&1`：丢弃输出
- `!`：取反，不存在时执行then块

**输入文件检查**：

```bash
if [ ! -f "$INPUT_PATH" ]; then
    echo "Error: Input PNG not found: $INPUT_PATH"
    exit 1
fi
```

**检查内容**：

- 文件是否存在
- 是否是普通文件（不是目录）

#### do_convert()

**作用**：使用ImageMagick转换图片格式。

**执行的命令**：

```bash
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -depth 8 \
    bmp3:"$TEMP_PATH"
```

**参数解释**：

| 参数 | 说明 |
|------|------|
| `-resize ${TARGET_SIZE}!` | 调整尺寸到指定大小，`!`表示强制调整，不保持宽高比 |
| `-alpha off` | 去除透明通道（Alpha channel） |
| `-depth 8` | 设置位深为8位（256色） |
| `bmp3:` | 输出为BMP3格式 |

**为什么使用这些参数**：

- `-resize ...!`：确保输出尺寸精确匹配，U-Boot的Logo显示需要精确尺寸
- `-alpha off`：BMP格式不支持透明通道，必须去除
- `-depth 8`：U-Boot的bmp_logo工具支持8位BMP
- `bmp3:`：确保输出标准BMP格式

#### ensure_target_dir()

**作用**：确保目标目录存在。

**实现方式**：

```bash
TARGET_DIR="$(dirname "$TARGET_PATH")"
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi
```

**设计细节**：

- `dirname`：提取路径中的目录部分
- `mkdir -p`：递归创建目录，如果父目录不存在也会创建

#### copy_to_target()

**作用**：将转换后的BMP文件复制到目标位置。

**实现方式**：

```bash
cp "$TEMP_PATH" "$TARGET_PATH"
echo "Copied to: $TARGET_PATH"
```

**为什么需要复制**：

- 临时文件在项目根目录
- 目标文件在U-Boot源码目录
- 使用临时文件是为了避免转换失败时覆盖原有文件

#### cleanup_temp_file()

**作用**：清理临时文件。

**实现方式**：

```bash
rm -f "$TEMP_PATH"
echo "Cleaned up temporary file"
```

**设计考虑**：

- `-f`：强制删除，文件不存在也不报错
- 只清理自己的临时文件，不删除其他文件

#### verify_output()

**作用**：验证输出文件。

**实现方式**：

```bash
file "$TARGET_PATH"
```

**输出示例**：

```
third_party/uboot-mainline/tools/logos/denx.bmp: PC bitmap, Windows 3.x format, 800 x 480 x 8
```

**为什么需要验证**：

- 确认文件确实是BMP格式
- 确认尺寸正确
- 确认位深正确

## 配置选项

### 硬编码配置

脚本开头定义了默认配置：

```bash
TEMP_BMP=".tmp.logo.bmp"
TARGET_SIZE="${1:-800x480}"
INPUT_PNG="${2:-document/logo/logo.png}"
TARGET_BMP="${3:-third_party/uboot-mainline/tools/logos/denx.bmp}"
```

### 默认路径说明

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 临时文件 | `.tmp.logo.bmp` | 项目根目录的隐藏文件 |
| 目标尺寸 | `800x480` | 常见的7寸LCD分辨率 |
| 输入PNG | `document/logo/logo.png` | 项目Logo目录 |
| 输出BMP | `third_party/uboot-mainline/tools/logos/denx.bmp` | U-Boot默认Logo位置 |

### 目录结构

```
PROJECT_ROOT/
├── document/
│   └── logo/
│       └── logo.png             # 输入：源PNG文件
├── third_party/
│   └── uboot-mainline/
│       └── tools/
│           └── logos/
│               └── denx.bmp     # 输出：U-Boot Logo
├── scripts/
│   └── logo_helper/
│       └── logo_helper.sh      # 本脚本
└── .tmp.logo.bmp                # 临时文件（转换后删除）
```

## 使用示例

### 基本用法

```bash
# 使用默认参数（800x480）
./scripts/logo_helper/logo_helper.sh
```

### 自定义尺寸

```bash
# 适配1024x600的10寸屏
./scripts/logo_helper/logo_helper.sh 1024x600

# 适配480x272的小屏
./scripts/logo_helper/logo_helper.sh 480x272
```

### 自定义输入输出

```bash
# 使用自定义PNG文件
./scripts/logo_helper/logo_helper.sh 800x480 my_custom_logo.png

# 完全自定义
./scripts/logo_helper/logo_helper.sh 800x480 assets/logo.png output/mylogo.bmp
```

### 在U-Boot构建中使用

```bash
# build-uboot.sh会自动调用此脚本
./scripts/build_helper/build-uboot.sh

# 输出示例
[INFO] Preparing logo...
==================== Logo Helper Parameters ====================
Parameter            Value
---------            -----
Target Size          800x480
Input PNG            /home/user/imx-forge/document/logo/logo.png
Target BMP           /home/user/imx-forge/third_party/uboot-mainline/tools/logos/denx.bmp
==============================================================

Found PNG: /home/user/imx-forge/document/logo/logo.png
Generated temporary BMP: .tmp.logo.bmp
Creating target directory: third_party/uboot-mainline/tools/logos
Copied to: third_party/uboot-mainline/tools/logos/denx.bmp
Cleaned up temporary file
third_party/uboot-mainline/tools/logos/denx.bmp: PC bitmap, Windows 3.x format, 800 x 480 x 8

==================== Convert Success! ====================
See third_party/uboot-mainline/tools/logos/denx.bmp to check!
==========================================================
```

### 输出示例

**成功执行**：

```
==================== Logo Helper Parameters ====================
Parameter            Value
---------            -----
Target Size          800x480
Input PNG            /home/charliechen/imx-forge/document/logo/logo.png
Target BMP           /home/charliechen/imx-forge/third_party/uboot-mainline/tools/logos/denx.bmp
==============================================================

Found PNG: /home/charliechen/imx-forge/document/logo/logo.png
Generated temporary BMP: .tmp.logo.bmp
Copied to: /home/charliechen/imx-forge/third_party/uboot-mainline/tools/logos/denx.bmp
Cleaned up temporary file
third_party/uboot-mainline/tools/logos/denx.bmp: PC bitmap, Windows 3.x format, 800 x 480 x 8

==================== Convert Success! ====================
See third_party/uboot-mainline/tools/logos/denx.bmp to check!
==========================================================
```

## 设计决策说明

### 为什么使用BMP格式而不是PNG

U-Boot使用BMP格式的原因：

1. **解析简单**：BMP是简单的位图格式，不需要复杂的解码库
2. **内存效率**：嵌入式系统资源有限，BMP可以直接显示
3. **历史原因**：BMP是Windows标准格式，工具支持成熟

**为什么不直接用PNG**：

- PNG需要zlib解压库
- PNG解码代码量大
- 对于简单的Logo，BMP已经足够

### 为什么强制调整尺寸（使用!）

脚本使用 `-resize ${TARGET_SIZE}!` 强制调整尺寸：

```bash
convert "$INPUT_PATH" -resize ${TARGET_SIZE}! ...
```

**为什么不保持宽高比**：

1. **精确控制**：LCD显示需要精确的像素尺寸
2. **简化处理**：不需要考虑黑边填充
3. **符合预期**：开发者明确知道输出尺寸

**如果希望保持比例**：

可以手动修改脚本，去掉 `!` 或添加背景填充：

```bash
# 保持比例，可能有黑边
convert "$INPUT_PATH" -resize ${TARGET_SIZE} ...

# 保持比例，填充背景
convert "$INPUT_PATH" -resize ${TARGET_SIZE} -background black -gravity center -extent ${TARGET_SIZE} ...
```

### 为什么使用临时文件

转换流程是：PNG → 临时BMP → 目标BMP

**为什么不直接输出到目标位置**：

1. **原子操作**：转换完成才复制，避免产生不完整的文件
2. **权限问题**：目标目录可能不存在或无写权限
3. **错误处理**：转换失败时不会覆盖原有文件

### 为什么去除Alpha通道

PNG支持透明（Alpha通道），但BMP不支持（标准BMP）。

**不去除会怎样**：

- ImageMagick会尝试转换为带Alpha的BMP
- U-Boot的bmp_logo工具可能不支持
- 显示效果不可预测

**处理方式**：

```bash
-alpha off
```

这会使用白色背景填充透明区域。

### 为什么使用8位深度

U-Boot的bmp_logo工具支持多种位深，但8位是最通用的：

| 位深 | 颜色数 | 支持情况 | 文件大小 |
|------|--------|----------|----------|
| 8位 | 256色 | 所有U-Boot版本 | 小 |
| 16位 | 65536色 | 需要CONFIG_BMP_16BPP | 中 |
| 24位 | 1670万色 | 需要CONFIG_BMP_24BPP | 大 |

**使用8位的好处**：

1. **兼容性最好**：所有U-Boot版本都支持
2. **文件最小**：节省Flash空间
3. **Logo足够**：对于简单Logo，256色足够

### 为什么输出到 denx.bmp

`denx.bmp` 是U-Boot的默认Logo文件：

- DENX是U-Boot的维护组织
- 这是U-Boot源码中的传统位置
- 编译时会自动处理这个文件

**如果想用其他文件名**：

需要修改U-Boot的Makefile或配置：

```makefile
# tools/Makefile
LOGO_BMP = $(srctree)/tools/logos/your_logo.bmp
```

## 故障排除

### 常见错误

#### 错误1：ImageMagick未安装

```
Error: ImageMagick (convert) not found.
Install with:
  sudo apt install imagemagick
```

**解决方法**：

```bash
sudo apt install imagemagick
```

**如果已经安装但仍报错**：

```bash
# 检查convert命令
which convert

# 如果没有，可能需要安装legacy工具
sudo apt install imagemagick-6.q16

# 或者检查是否是路径问题
export PATH=$PATH:/usr/local/bin
```

#### 错误2：输入PNG文件不存在

```
Error: Input PNG not found: /path/to/imx-forge/document/logo/logo.png
```

**可能原因**：

1. Logo文件不存在
2. 路径错误
3. 从项目外调用但路径解析失败

**解决方法**：

```bash
# 检查文件是否存在
ls -la document/logo/logo.png

# 如果不存在，创建默认Logo
mkdir -p document/logo
# ... 复制或创建Logo文件

# 使用绝对路径
./scripts/logo_helper/logo_helper.sh 800x480 /absolute/path/to/logo.png
```

#### 错误3：ImageMagick权限限制

```
convert: attempt to perform an operation not allowed by the security policy `PDF' @ error/constitute.c/IsCoderAuthorized/426
```

**原因**：ImageMagick的安全策略限制了某些操作。

**解决方法**：

编辑 `/etc/ImageMagick-6/policy.xml`（或 `/etc/ImageMagick/policy.xml`）：

```xml
<!-- 找到这一行 -->
<policy domain="coder" rights="none" pattern="PDF" />

<!-- 修改为 -->
<policy domain="coder" rights="read|write" pattern="PDF" />

<!-- 或者添加 -->
<policy domain="path" rights="read|write" pattern="*" />
```

#### 错误4：BMP格式不符合U-Boot要求

**现象**：U-Boot编译或运行时Logo显示异常。

**排查方法**：

```bash
# 检查BMP格式
file third_party/uboot-mainline/tools/logos/denx.bmp

# 应该看到类似
# PC bitmap, Windows 3.x format, 800 x 480 x 8

# 检查BMP详细信息
identify third_party/uboot-mainline/tools/logos/denx.bmp
```

**期望输出**：

```
denx.bmp BMP 800x480 800x480+0+0 8-bit sRGB 256c 384KB 0.000u 0:00.000
```

#### 错误5：Logo显示变形

**现象**：Logo在LCD上显示变形。

**原因**：使用了强制尺寸调整（`!`参数）。

**解决方法**：

1. 保持原始比例：

```bash
# 修改脚本，去掉!
convert "$INPUT_PATH" -resize ${TARGET_SIZE} ...
```

2. 或者准备符合比例的源图片：

```bash
# 如果目标尺寸是800x480（5:3）
# 源图片也应该是5:3比例
```

3. 使用填充方式：

```bash
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE} \
    -background black \
    -gravity center \
    -extent ${TARGET_SIZE} \
    bmp3:"$TEMP_PATH"
```

#### 错误6：Logo颜色异常

**现象**：Logo显示但颜色不对。

**可能原因**：

1. **位深问题**：8位色彩不够

**解决方法**：

```bash
# 使用24位BMP
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -depth 24 \
    bmp3:"$TEMP_PATH"
```

2. **RGB顺序问题**：BMP默认是BGR顺序

**解决方法**：

```bash
# 转换时指定RGB顺序
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -depth 8 \
    -set colorspace RGB \
    bmp3:"$TEMP_PATH"
```

3. **调色板问题**：8位BMP使用调色板

**解决方法**：

```bash
# 优化色彩量化
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -colors 256 \
    -dither None \
    bmp3:"$TEMP_PATH"
```

### 调试技巧

#### 查看详细转换信息

```bash
# 添加 -verbose 参数
convert -verbose "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -depth 8 \
    bmp3:"$TEMP_PATH"
```

#### 检查中间结果

```bash
# 不删除临时文件，手动检查
# 注释掉脚本中的 rm -f "$TEMP_PATH"
# 然后检查
file .tmp.logo.bmp
identify .tmp.logo.bmp
```

#### 手动测试转换

```bash
# 测试不同参数
convert document/logo/logo.png -resize 800x480! -alpha off -depth 8 test.bmp

# 检查结果
file test.bmp
ls -lh test.bmp
```

## 扩展和定制

### 添加水印

如果需要在Logo上添加水印：

```bash
# 修改convert命令
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \
    -alpha off \
    -depth 8 \
    -pointsize 20 \
    -fill white \
    -gravity southeast \
    -annotate 0 'Build: $(date +%Y%m%d)' \
    bmp3:"$TEMP_PATH"
```

### 添加边框

如果需要添加边框：

```bash
convert "$INPUT_PATH" \
    -resize $((WIDTH-20))x$((HEIGHT-20))! \
    -bordercolor black \
    -border 10 \
    -alpha off \
    -depth 8 \
    bmp3:"$TEMP_PATH"
```

### 批量处理多个Logo

创建批量处理脚本：

```bash
#!/bin/bash
# batch_logo_convert.sh

SIZES=(
    "800x480"
    "1024x600"
    "480x272"
)

for size in "${SIZES[@]}"; do
    echo "Converting for $size..."
    ./scripts/logo_helper/logo_helper.sh "$size" \
        document/logo/logo.png \
        "output/logo_$size.bmp"
done
```

### 自动验证颜色数量

```bash
# 转换后验证
COLORS=$(identify -format %k "$TARGET_PATH")
if [ "$COLORS" -gt 256 ]; then
    echo "Warning: Image has $COLORS colors, more than 256"
fi
```

### 集成到CI/CD

在GitHub Actions或GitLab CI中使用：

```yaml
# .github/workflows/build.yml
- name: Prepare Logo
  run: |
    sudo apt install -y imagemagick
    ./scripts/logo_helper/logo_helper.sh
```

## BMP格式详解

### BMP文件结构

标准BMP文件由以下部分组成：

```
┌─────────────────────────────────────────────────────────────┐
│  文件头（File Header）                                      │
│  - Magic Number: 'BM' (0x4D42)                             │
│  - File Size: 文件总大小                                   │
│  - Reserved: 保留字段                                      │
│  - Data Offset: 像素数据偏移                               │
├─────────────────────────────────────────────────────────────┤
│  信息头（Info Header）                                      │
│  - Header Size: 信息头大小                                 │
│  - Width: 图片宽度                                         │
│  - Height: 图片高度                                        │
│  - Planes: 颜色平面数（总是1）                             │
│  - Bit Count: 每像素位数（8/16/24/32）                     │
│  - Compression: 压缩方式（0=无压缩）                       │
│  - Image Size: 像素数据大小                                │
│  - X/Y Pixels Per Meter: 分辨率                           │
│  - Colors Used: 使用的颜色数                               │
│  - Important Colors: 重要颜色数                            │
├─────────────────────────────────────────────────────────────┤
│  调色板（Color Palette）- 仅8位BMP                         │
│  - 256个RGBQUAD结构                                        │
├─────────────────────────────────────────────────────────────┤
│  像素数据（Pixel Data）                                    │
│  - 从下到上存储（BMP是"倒置"的）                           │
│  - 每行4字节对齐                                           │
└─────────────────────────────────────────────────────────────┘
```

### 8位BMP的特点

1. **调色板**：256色的RGB值
2. **像素数据**：每个像素1字节，索引到调色板
3. **行对齐**：每行数据填充到4字节边界

### 验证BMP格式

```bash
# 检查文件头
hexdump -C third_party/uboot-mainline/tools/logos/denx.bmp | head -n 5

# 应该看到
# 00000000  42 4d ...                           <- BM魔数
```

## 与U-Boot的集成

### U-Boot Logo处理流程

```
denx.bmp
    ↓
tools/bmp_logo --gen-info
    ↓
include/bmp_logo.h (尺寸信息)
    ↓
tools/bmp_logo --gen-data
    ↓
include/bmp_logo_data.h (调色板和像素数据)
    ↓
编译进 common/bmp_logo.c
    ↓
链接进 u-boot.bin
    ↓
运行时显示在LCD上
```

### 相关配置选项

```kconfig
CONFIG_VIDEO=y
CONFIG_VIDEO_LOGO=y
CONFIG_BMP_8BPP=y
CONFIG_SPLASH_SCREEN=y
```

### 运行时显示

U-Boot启动时自动显示Logo：

```c
// common/lcd.c
static int lcd_display_bitmap(ulong bmp_image, int x, int y)
{
    // 读取BMP信息
    // 显示到LCD
}
```

## 相关文档

- [U-Boot构建脚本](../build_helper/build-uboot.sh) - 调用此脚本的构建脚本
- Logo和启动画面教程 - Logo配置详解
- LCD移植指南 - LCD显示配置
- U-Boot环境变量配置 - 环境变量设置

## 更新日志

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-03-15 | 1.0 | 初始文档版本 |

---

> **文档生成时间**: 2026-03-15
> **脚本路径**: `scripts/logo_helper/logo_helper.sh`
