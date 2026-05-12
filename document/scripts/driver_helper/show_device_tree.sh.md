# show_device_tree.sh - 设备树节点美化打印脚本

## 脚本概述

`show_device_tree.sh` 是一个用于美化显示设备树内容的工具脚本。它可以将 `.dtb` 或 `.dts` 文件以树形结构展示，并高亮显示重要属性。

### 核心功能

- **树形显示**：以树状结构展示设备树节点
- **属性高亮**：高亮显示 compatible、status 等重要属性
- **格式支持**：支持 `.dtb`（二进制）和 `.dts`（源码）格式
- **搜索功能**：支持在设备树中搜索特定内容
- **详细信息**：显示节点统计和详细信息
- **完整内容**：可选显示完整 DTS 源码

### 设计理念

这个脚本的设计目标是帮助开发者在部署前快速预览设备树内容，确保节点结构正确，属性设置合理。

### 依赖关系

```
show_device_tree.sh
    └─ dtc (设备树编译器)
```

## 参数说明

### 命令语法

```bash
./scripts/driver_helper/show_device_tree.sh <设备树文件> [选项]
```

### 位置参数

| 参数 | 说明 |
|------|------|
| `设备树文件` | `.dtb` 或 `.dts` 文件路径 |

### 选项列表

| 选项 | 说明 |
|------|------|
| `--all, -a` | 显示完整 DTS 内容 |
| `--search, -s <term>` | 搜索节点或属性 |
| `--detailed, -d` | 显示详细信息 |
| `--help, -h` | 显示帮助信息 |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  参数验证                                                    │
│  - 检查文件参数                                             │
│  - 检查文件是否存在                                         │
│  - 检查 dtc 工具是否可用                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  模式选择                                                    │
│  - 搜索模式：如果指定 --search                               │
│  - 详细模式：如果指定 --detailed                            │
│  - 树形模式：默认显示                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  内容显示                                                    │
│  - print_device_tree()：树形结构                            │
│  - search_node()：搜索结果                                  │
│  - print_device_tree_detailed()：详细信息                   │
└─────────────────────────────────────────────────────────────┘
```

### 显示函数详解

#### print_device_tree()

**作用**：以树形结构显示设备树节点。

**显示内容**：

```
🌳 设备树节点结构
═════════════════════════════════════════════════════

📁 文件: out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb
📏 大小: 256

🌲 节点树结构

│  ├──root
│  │   ├──example-device
│  │   │   ✦ compatible = "example,imx6ull-driver"
│  │   │   ✦ status = "okay"
│  │   │   └──reg = <0x01234567 0x1000>

═════════════════════════════════════════════════════
```

**颜色方案**：

| 元素 | 颜色 | 说明 |
|------|------|------|
| 树形线条 | 蓝色 | `│  └──` |
| 节点名 | 绿色 | 节点名称 |
| 属性名 | 青色 | 属性字段名 |
| 属性值 | 黄色 | 属性值 |
| 星号 | 洋红 | `✦` 标记 |
| 状态 okay | 绿色 | 启用状态 |
| 状态 disabled | 黄色 | 禁用状态 |

#### search_node()

**作用**：在设备树中搜索特定内容。

**输出示例**：

```
🔍 搜索: compatible
═════════════════════════════════════════════════════

行 45:     compatible = "example,imx6ull-driver";
行 78:     compatible = "fixed-clock";
```

#### print_device_tree_detailed()

**作用**：显示设备树的统计信息。

**输出示例**：

```
🔍 设备树详细信息
═════════════════════════════════════════════════════

📊 统计信息:
  节点数量: 5
  属性数量: 12
  Compatible属性: 2

🌲 所有节点:
  - root
  - example-device
  - aliases
  - chosen
  - memory

🔗 Compatible属性:
  - example,imx6ull-driver
  - fixed-clock
```

## 使用示例

### 基本用法

```bash
# 显示 .dtb 文件
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb

# 显示 .dts 文件
./scripts/driver_helper/show_device_tree.sh driver/device_tree/alpha-board/example-driver/imx6ull-aes-example-driver.dts
```

### 显示完整内容

```bash
./scripts/driver_helper/show_device_tree.sh example.dtb --all
```

**输出示例**：

```
🌳 设备树节点结构
═════════════════════════════════════════════════════

📁 文件: example.dtb
📏 大小: 256

🌲 节点树结构

│  ├──root
│  │   ├──example-device
│  │   │   ✦ compatible = "example,imx6ull-driver"
│  │   │   ✦ status = "okay"
│  │   │   └──reg = <0x01234567 0x1000>

═════════════════════════════════════════════════════

📄 完整DTS内容

/dts-v1/;
/ {
    #address-cells = <1>;
    #size-cells = <1>;
    example-device {
        compatible = "example,imx6ull-driver";
        status = "okay";
        reg = <0x01234567 0x1000>;
    };
};
```

### 搜索功能

```bash
# 搜索 compatible 属性
./scripts/driver_helper/show_device_tree.sh example.dtb --search "compatible"

# 搜索特定节点
./scripts/driver_helper/show_device_tree.sh example.dtb --search "example"
```

### 显示详细信息

```bash
./scripts/driver_helper/show_device_tree.sh example.dtb --detailed
```

### 组合使用

```bash
# 显示完整内容并搜索
./scripts/driver_helper/show_device_tree.sh example.dtb --all --search "status"
```

## 故障排除

### 常见错误

#### 错误 1：缺少 dtc 工具

```
错误: dtc工具不可用
请安装设备树编译器: sudo apt-get install device-tree-compiler
```

**解决方法**：

```bash
sudo apt install device-tree-compiler
```

#### 错误 2：文件不存在

```
错误: 文件不存在: unknown.dtb
```

**解决方法**：

1. 检查文件路径是否正确
2. 使用绝对路径或相对于项目根目录的路径

#### 错误 3：不支持的文件格式

```
错误: 不支持的文件格式
```

**解决方法**：

确保文件扩展名为 `.dtb` 或 `.dts`。

#### 错误 4：设备树格式错误

```
错误: 无法读取设备树文件
```

**原因**：DTB 文件损坏或格式不正确。

**解决方法**：

1. 检查文件是否为有效的 DTB
2. 使用 `fdtdump` 或 `dtc` 验证文件

## 显示说明

### 树形结构符号

| 符号 | 含义 |
|------|------|
| `│`  | 垂直连线 |
| `└──` | 末端分支 |
| `├──` | 中间分支 |
| `✦`  | 属性标记 |

### 状态颜色

| 状态 | 颜色 | 说明 |
|------|------|------|
| `okay` | 绿色 | 设备已启用 |
| `disabled` | 黄色 | 设备已禁用 |
| `reserved` | 红色 | 保留状态 |

## 相关文档

- 设备树编译机制 - 内核如何处理设备树
- 设备树编译迁移 - 设备树编译实现
- [deploy_driver.sh](./deploy_driver.sh.md) - 驱动部署脚本
