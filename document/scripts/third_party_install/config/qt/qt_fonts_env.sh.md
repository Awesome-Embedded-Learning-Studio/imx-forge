# qt_fonts_env.sh - Qt 字体环境变量配置详解

## 脚本概述

`qt_fonts_env.sh` 是 IMX-Forge 项目中用于配置 Qt 应用程序字体环境的关键脚本。它定义了在嵌入式 Linux 系统上正确显示文本（包括中文、emoji 和拉丁字符）所需的环境变量。

### 核心功能

- **字体路径配置**：通过 `QT_QPA_FONTDIR` 指定 Qt 查找字体的目录
- **语言环境设置**：配置 `LANG` 和 `LC_ALL` 确保中文正确显示
- **字体 fallback 支持**：Qt 自动根据字符类型选择合适的字体
- **多语言支持**：支持拉丁字符、中日韩字符和 emoji 的混合显示

### 设计理念

这个脚本的设计遵循"配置即代码"的原则。所有字体相关的环境变量集中在一个文件中，便于管理和维护。脚本本身是可执行的，但通常通过 source 方式使用，确保环境变量在当前 shell 中生效。

**为什么需要专门的字体配置**：

1. **嵌入式系统特性**：嵌入式系统通常使用精简的 rootfs，字体不是默认安装的
2. **Qt 平台抽象**：Qt 使用 QPA (Qt Platform Abstraction) 框架，需要明确指定字体目录
3. **多语言需求**：现代应用需要同时支持拉丁文、中文和 emoji
4. **一致性**：统一的环境变量确保所有 Qt 应用行为一致

### 依赖关系

```
qt_fonts_env.sh
    ├─ /usr/share/fonts/ (字体文件，由 install_fonts.sh 创建)
    └─ Qt 应用程序 (使用此脚本配置的环境)
```

配合使用：

- `install_fonts.sh`：负责安装字体文件到目标目录
- Qt 应用：在启动时 source 此脚本或通过系统环境加载配置

## 环境变量

### 核心环境变量

| 变量 | 值 | 说明 |
|------|-----|------|
| `QT_QPA_FONTDIR` | `/usr/share/fonts` | Qt 字体目录，告诉 Qt 在哪里查找字体文件 |
| `LANG` | `C.UTF-8` | 系统语言环境，确保 UTF-8 编码支持 |
| `LC_ALL` | `C.UTF-8` | 覆盖所有 locale 类别，强制使用 UTF-8 |

### 可选环境变量

脚本中注释掉了平台插件配置，可根据实际需求启用：

| 变量 | 可选值 | 说明 |
|------|--------|------|
| `QT_QPA_PLATFORM` | `linuxfb` / `eglfs` / `wayland` | Qt 平台插件，根据显示 backend 选择 |

### 环境变量详解

#### QT_QPA_FONTDIR

**作用**：指定 Qt 字体引擎查找字体文件的目录。

**默认行为**：如果不设置，Qt 会搜索多个标准位置（如 `/usr/share/fonts`、`/usr/local/share/fonts` 等）。在嵌入式系统中，明确指定可以提高性能和可预测性。

**验证方法**：

```bash
echo $QT_QPA_FONTDIR
# 输出: /usr/share/fonts
```

#### LANG 和 LC_ALL

**作用**：控制系统语言和编码环境。

**为什么设置为 C.UTF-8**：

- `C`：最小化 locale，避免特定语言的格式化行为（如日期、数字格式）
- `UTF-8`：确保 Unicode 字符（中文、emoji）正确处理

**区别**：

- `LANG`：默认 locale，被没有显式设置的类别使用
- `LC_ALL`：覆盖所有 locale 类别，优先级最高

**为什么两者都设置**：确保所有程序行为一致，避免某些程序忽略 `LANG` 而使用默认 locale。

## 字体目录结构

### 目录结构

脚本假定以下字体目录结构（由 `install_fonts.sh` 创建）：

```
/usr/share/fonts/
├── dejavu/
│   ├── DejaVuSans.ttf           # 拉丁文默认字体
│   ├── DejaVuSans-Bold.ttf      # 拉丁文粗体
│   └── DejaVuSansMono.ttf       # 等宽字体
├── noto/
│   └── NotoSansCJK-Regular.ttc  # 中日韩统一字体
└── emoji/
    └── NotoColorEmoji.ttf       # Emoji 字体
```

### 字体用途

| 字体 | 文件 | 覆盖字符 | 用途 |
|------|------|----------|------|
| DejaVu Sans | `DejaVuSans.ttf` | Latin 字符 | 英文和欧洲语言 |
| DejaVu Sans Mono | `DejaVuSansMono.ttf` | Latin 字符 | 终端、代码显示 |
| Noto Sans CJK | `NotoSansCJK-Regular.ttc` | 中日韩字符 | 中文、日文、韩文 |
| Noto Color Emoji | `NotoColorEmoji.ttf` | Emoji 符号 | 表情符号 |

### 字体 Fallback 机制

Qt 会按以下顺序自动选择字体（无需额外配置）：

1. **Latin 字符** (a-z, A-Z, 0-9, 符号) → DejaVu Sans
2. **中日韩字符** (汉字、假名、谚文) → Noto Sans CJK
3. **Emoji** (Unicode Emoji) → Noto Color Emoji
4. **等宽需求** (终端、代码) → DejaVu Sans Mono

**自动 fallback**：当主字体不包含某个字符时，Qt 会自动查找 fallback 字体。这意味着一个字符串可以包含多种字符集，每个字符使用不同的字体渲染。

**示例**：字符串 `"Hello 世界 🎉"` 会使用：
- `Hello` → DejaVu Sans
- `世界` → Noto Sans CJK
- `🎉` → Noto Color Emoji

## 使用方法

### 方法 1：Source 脚本

在 shell 中 source 此脚本：

```bash
source /path/to/qt_fonts_env.sh
```

或在脚本中：

```bash
#!/bin/bash
source /usr/share/qt5/env/qt_fonts_env.sh

# 启动 Qt 应用
./my_qt_app
```

### 方法 2：添加到 /etc/environment

系统级配置，所有用户和进程生效：

```bash
# /etc/environment
QT_QPA_FONTDIR=/usr/share/fonts
LANG=C.UTF-8
LC_ALL=C.UTF-8
```

**注意**：修改后需要重启或重新登录。

### 方法 3：应用启动脚本

在 Qt 应用的启动脚本中配置：

```bash
#!/bin/bash
# my_app.sh

# 设置字体环境
export QT_QPA_FONTDIR=/usr/share/fonts
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# 启动应用
./my_qt_app "$@"
```

### 方法 4：系统服务 (systemd)

在 systemd service 文件中配置：

```ini
[Unit]
Description=My Qt Application
After=graphical.target

[Service]
Environment="QT_QPA_FONTDIR=/usr/share/fonts"
Environment="LANG=C.UTF-8"
Environment="LC_ALL=C.UTF-8"
ExecStart=/usr/bin/my_qt_app

[Install]
WantedBy=multi-user.target
```

### 方法 5：Qt 项目配置

在 Qt 项目文件 (`.pro`) 中配置：

```qmake
unix:!android {
    QT_QPA_FONTDIR = /usr/share/fonts
}
```

或在 C++ 代码中（不推荐，优先使用环境变量）：

```cpp
// C++ 代码中（不推荐，优先使用环境变量）
qputenv("QT_QPA_FONTDIR", "/usr/share/fonts");
```

## C++ 代码示例

### 设置默认字体

```cpp
#include <QApplication>
#include <QFont>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);

    // 设置全局默认字体
    QFont font("Noto Sans CJK SC", 12);
    QApplication::setFont(font);

    // ... 其他代码

    return app.exec();
}
```

### 中英混排文本

```cpp
#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>

void createMixedTextLabel(QWidget *parent) {
    QLabel *label = new QLabel("Hello 世界 🎉", parent);

    // 设置字体
    QFont font("Noto Sans CJK SC", 20);
    label->setFont(font);

    // Qt 会自动处理不同字符的字体 fallback
    // - Hello 使用 DejaVu Sans
    // - 世界 使用 Noto Sans CJK
    // - 🎉 使用 Noto Color Emoji
}
```

### 等宽字体（终端）

```cpp
#include <QTextEdit>
#include <QFont>

void createTerminalWidget(QWidget *parent) {
    QTextEdit *terminal = new QTextEdit(parent);

    // 使用等宽字体
    QFont monoFont("DejaVu Sans Mono", 10);
    terminal->setFont(monoFont);
    terminal->setPlainText("root@imx:~# ls -l\n");
}
```

### 查询可用字体

```cpp
#include <QFontDatabase>
#include <QDebug>

void listAvailableFonts() {
    qDebug() << "Available font families:";
    QStringList families = QFontDatabase::families();

    for (const QString &family : families) {
        qDebug() << "  -" << family;
    }

    // 检查特定字体
    QFontDatabase db;
    if (db.hasFamily("Noto Sans CJK SC")) {
        qDebug() << "Noto Sans CJK SC is available";
    }

    if (db.hasFamily("DejaVu Sans")) {
        qDebug() << "DejaVu Sans is available";
    }
}
```

### 字体回退测试

```cpp
#include <QLabel>
#include <QFont>
#include <QFontDatabase>

void testFontFallback() {
    QLabel *label = new QLabel();
    label->setText("ABC 123 测试 🎉");

    // 使用通用字体族，让 Qt 自动处理 fallback
    QFont font("Sans", 16);
    label->setFont(font);

    // 获取实际渲染使用的字体信息
    QFontInfo info(label->font());
    qDebug() << "Actual font family:" << info.family();
    qDebug() << "Exact match:" << info.exactMatch();
}
```

### 动态字体切换

```cpp
#include <QApplication>
#include <QFont>
#include <QComboBox>

void setupFontSwitcher(QComboBox *combo) {
    // 添加字体选项
    combo->addItem("DejaVu Sans", "DejaVu Sans");
    combo->addItem("Noto Sans CJK SC", "Noto Sans CJK SC");
    combo->addItem("DejaVu Sans Mono", "DejaVu Sans Mono");

    // 字体切换处理
    QObject::connect(combo, QOverload<int>::of(&QComboBox::currentIndexChanged),
                     [combo](int index) {
        QString fontFamily = combo->currentData().toString();
        QFont font(fontFamily, 12);
        QApplication::setFont(font);
    });
}
```

## 验证命令

### 检查字体文件是否存在

```bash
# 检查 DejaVu 字体
ls -l /usr/share/fonts/dejavu/
# 预期输出:
# DejaVuSans.ttf
# DejaVuSans-Bold.ttf
# DejaVuSansMono.ttf

# 检查 Noto CJK 字体
ls -l /usr/share/fonts/noto/
# 预期输出:
# NotoSansCJK-Regular.ttc

# 检查 Emoji 字体
ls -l /usr/share/fonts/emoji/
# 预期输出:
# NotoColorEmoji.ttf
```

### 检查环境变量

```bash
# 检查 Qt 字体目录
echo $QT_QPA_FONTDIR
# 预期输出: /usr/share/fonts

# 检查语言环境
echo $LANG
# 预期输出: C.UTF-8

echo $LC_ALL
# 预期输出: C.UTF-8
```

### 使用 fc-list 验证字体

```bash
# 列出所有已安装的字体
fc-list : family

# 筛选特定字体
fc-list | grep -i deja
fc-list | grep -i noto
fc-list | grep -i emoji
```

### Qt 字体数据库测试

创建简单的测试程序 `test_fonts.cpp`：

```cpp
#include <QApplication>
#include <QFontDatabase>
#include <QDebug>
#include <QLabel>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);

    // 列出所有字体族
    qDebug() << "=== Available Font Families ===";
    QStringList families = QFontDatabase::families();
    for (const QString &family : families) {
        qDebug() << "  " << family;
    }

    // 测试中英混排
    QLabel *label = new QLabel("Hello 世界 🎉 Test 123");
    label->setFont(QFont("Noto Sans CJK SC", 24));
    label->show();

    return app.exec();
}
```

编译运行：

```bash
# 交叉编译示例
arm-linux-gnueabihf-g++ -o test_fonts test_fonts.cpp \
    -I/usr/include/qt5 \
    -I/usr/include/qt5/QtCore \
    -I/usr/include/qt5/QtGui \
    -I/usr/include/qt5/QtWidgets \
    -lQt5Core -lQt5Gui -lQt5Widgets

# 在目标板上运行
./test_fonts
```

### 字体渲染测试

```bash
# 在目标板上运行以下命令测试字体
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_PLATFORM=linuxfb

# 使用 Qt5 的示例程序测试
qt5/qtbase/examples/widgets/widgets/charactermap -platform linuxfb
```

## 故障排除

### 常见问题

#### 问题 1：中文显示为方块

**现象**：中文字符显示为方框（□）或问号。

**可能原因**：

1. 字体文件未正确安装
2. `QT_QPA_FONTDIR` 未设置或设置错误
3. `LANG`/`LC_ALL` 未设置为 UTF-8

**解决方法**：

```bash
# 1. 检查字体文件
ls -l /usr/share/fonts/noto/

# 2. 检查环境变量
echo $QT_QPA_FONTDIR
echo $LANG

# 3. 重新设置
export QT_QPA_FONTDIR=/usr/share/fonts
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# 4. 重新运行应用
```

#### 问题 2：Emoji 不显示

**现象**：Emoji 符号显示为空白或方块。

**可能原因**：

1. Noto Color Emoji 字体未安装
2. Qt 版本不支持彩色 emoji（需要 Qt 5.12+）

**解决方法**：

```bash
# 检查 emoji 字体
ls -l /usr/share/fonts/emoji/

# 检查 Qt 版本
qt5-config --version

# 如果字体缺失，重新运行安装脚本
./scripts/third_party_install/install_fonts.sh
```

#### 问题 3：字体文件存在但仍无法显示

**现象**：字体文件存在，但应用仍无法使用。

**可能原因**：

1. 字体缓存未更新
2. 文件权限问题
3. 字体文件损坏

**解决方法**：

```bash
# 1. 更新字体缓存
fc-cache -fv

# 2. 检查文件权限
ls -l /usr/share/fonts/*/  # 应该是 644 或 444

# 3. 检查字体文件完整性
file /usr/share/fonts/noto/NotoSansCJK-Regular.ttc
```

#### 问题 4：应用启动报错找不到字体

**现象**：应用启动时输出 " QFontDatabase: Cannot find font directory"

**可能原因**：

`QT_QPA_FONTDIR` 指向的目录不存在。

**解决方法**：

```bash
# 1. 检查目录是否存在
ls -ld /usr/share/fonts

# 2. 创建目录或修改环境变量
mkdir -p /usr/share/fonts
# 或
export QT_QPA_FONTDIR=/actual/font/path
```

#### 问题 5：嵌入式设备上字体渲染很慢

**现象**：第一次显示文本时有明显延迟。

**可能原因**：

1. 字体文件较大（特别是 Noto Sans CJK TTC 文件）
2. 系统资源有限（CPU/内存）

**解决方法**：

```bash
# 1. 预加载字体（应用启动时）
fc-cache -fv

# 2. 使用较小的字体子集
#    如果只需要简体中文，可以提取 Noto Sans CJK SC 部分

# 3. 在代码中预先加载字体
QFontDatabase::addApplicationFont("/usr/share/fonts/noto/NotoSansCJK-Regular.ttc");
```

## 设计决策说明

### 为什么使用 /usr/share/fonts

这是 Linux 标准的字体目录位置：

1. **标准化**：符合 Filesystem Hierarchy Standard (FHS)
2. **工具兼容**：fontconfig 等系统工具默认搜索此目录
3. **跨发行版**：所有主流 Linux 发行版都使用此路径

### 为什么设置 LANG 而非 zh_CN.UTF-8

使用 `C.UTF-8` 而非 `zh_CN.UTF-8` 的原因：

1. **避免格式化差异**：`C` locale 使用标准的格式（如日期、数字）
2. **保持一致性**：在不同开发者的机器上行为一致
3. **UTF-8 支持**：`C.UTF-8` 仍支持 Unicode 字符，只是格式化规则是标准的

**示例差异**：

```python
# zh_CN.UTF-8
2024年03月19日

# C.UTF-8
2024-03-19
```

### 为什么使用 TTC 而非 TTF

Noto Sans CJK 使用 TTC (TrueType Collection) 格式：

1. **文件紧凑**：多个字体（简体、繁体、日文、韩文）合并为一个文件
2. **共享字形**：共享的汉字只存储一次
3. **便于管理**：一个文件包含所有 CJK 语言支持

**权衡**：文件较大（约 100MB+），如果只需要简体中文，可以提取 TTF 子集。

### 为什么不需要手动配置 fontconfig

Qt 5 可以直接使用字体文件，不依赖 fontconfig：

1. **简化依赖**：嵌入式系统可以不安装 fontconfig
2. **直接控制**：通过 `QT_QPA_FONTDIR` 明确指定位置
3. **可预测性**：行为不受系统配置影响

**如果使用 fontconfig**，可以通过 `/etc/fonts/fonts.conf` 配置更多选项。

## 扩展和定制

### 添加自定义字体

1. 将字体文件复制到字体目录：

```bash
cp my_custom_font.ttf /usr/share/fonts/custom/
```

2. 更新字体缓存（如果使用 fontconfig）：

```bash
fc-cache -fv
```

3. 在 C++ 代码中使用：

```cpp
QFont font("My Custom Font", 12);
QApplication::setFont(font);
```

### 修改字体目录

如果需要使用不同的字体目录：

```bash
# 方法1：修改环境变量
export QT_QPA_FONTDIR=/opt/myapp/fonts

# 方法2：在应用启动脚本中设置
#!/bin/bash
export QT_QPA_FONTDIR=$(dirname "$0")/fonts
./my_qt_app
```

### 添加更多语言支持

以阿拉伯语为例：

1. 安装 Noto Sans Arabic：

```bash
cp NotoSansArabic-Regular.ttf /usr/share/fonts/noto/
```

2. Qt 会自动处理 fallback，阿拉伯语字符会使用新字体。

### 性能优化

对于资源受限的嵌入式设备：

1. **使用字体子集**：提取需要的字符

```bash
# 使用 pyftsubset 提取常用汉字
pyftsubset NotoSansCJK-Regular.ttc \
    --text-file=common_chinese.txt \
    --output-file=NotoSansCJK-Regular-Subset.ttf
```

2. **预加载字体**：在应用启动时预加载

```cpp
// 在 main() 开始时
QFontDatabase::addApplicationFont("/usr/share/fonts/noto/NotoSansCJK-Regular.ttc");
```

3. **禁用未使用的字体模块**：在 Qt 配置中

```bash
./configure -no-fontconfig -no-freetype
```

## 相关文档

- [install_fonts.sh](../../install_fonts.sh) - 字体安装脚本
- [install_qt_with_compile.sh](../../install_qt_with_compile.sh) - Qt 安装和编译
- [Qt Font Documentation](https://doc.qt.io/qt-5/fonts.html) - Qt 官方字体文档
- [Qt Internationalization](https://doc.qt.io/qt-5/internationalization.html) - Qt 国际化指南
