# template_creator.sh - 交互式驱动创建脚本

## 脚本概述

`template_creator.sh` 是 IMX-Forge 驱动开发基建系统的交互式驱动创建工具。它基于 `example-driver` 模板，通过交互式问答引导用户创建新的驱动目录结构。

### 核心功能

- **交互式向导**：通过问答收集驱动配置信息
- **代码生成**：自动生成驱动源码、Makefile 和 README
- **模块参数支持**：支持定义模块参数
- **许可证选择**：支持多种开源许可证
- **内核类型选择**：支持 mainline 和 imx 内核

### 设计理念

这个脚本的设计目标是让开发者能够快速创建符合项目规范的驱动框架，无需手动复制粘贴和修改模板文件。

### 依赖关系

```
template_creator.sh
    ├─ scripts/lib/driver_buildlib.sh (构建库)
    └─ driver/example-driver/alpha-board (模板目录)
```

## 参数说明

### 命令语法

```bash
./scripts/driver_helper/template_creator.sh [选项]
```

### 选项列表

| 选项 | 说明 |
|------|------|
| `-h, --help` | 显示帮助信息 |

### 保留字列表

以下名称不能用作驱动名：

```
module, init, exit, kernel, linux, driver, device, board,
framework, mainline, test
```

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  阶段 1: 驱动基本信息                                        │
│  - 输入驱动名称（验证规则检查）                              │
│  - 选择/输入板卡名称                                         │
│  - 检查是否覆盖现有驱动                                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  阶段 2: 元数据信息                                          │
│  - 输入作者名（从 git 获取默认值）                           │
│  - 选择许可证类型                                           │
│  - 输入驱动描述                                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  阶段 3: 模块参数配置                                        │
│  - 输入参数数量（0-5）                                      │
│  - 为每个参数配置：                                         │
│    - 参数名（C 变量命名规则）                                │
│    - 参数类型（int/bool/charp）                              │
│    - 默认值                                                 │
│    - 参数描述                                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  阶段 4: 内核配置                                            │
│  - 选择内核类型（mainline/imx）                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  阶段 5: 确认并生成                                          │
│  - 显示配置摘要                                             │
│  - 确认后生成文件：                                         │
│    - <驱动名>_driver.c                                     │
│    - Makefile                                               │
│    - README.md                                              │
└─────────────────────────────────────────────────────────────┘
```

### 生成函数详解

#### generate_driver_source()

**作用**：生成驱动源码文件。

**生成内容**：

```c
// 驱动源码
// 由 template_creator.sh 自动生成

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>

// 模块参数（如果有）
static int param1 = 100;
module_param(param1, int, 0644);
MODULE_PARM_DESC(param1, "参数描述");

// 模块初始化
static int __init <驱动名>_init(void)
{
    pr_info("=== <驱动描述> ===\n");
    pr_info("param1: %d\n", param1);
    pr_info("========================\n");
    return 0;
}

// 模块退出
static void __exit <驱动名>_exit(void)
{
    pr_info("=== <驱动名>驱动卸载成功 ===\n");
    pr_info("========================\n");
}

module_init(<驱动名>_init);
module_exit(<驱动名>_exit);

MODULE_LICENSE("<许可证>");
MODULE_AUTHOR("<作者>");
MODULE_DESCRIPTION("<描述>");
MODULE_VERSION("1.0");
```

#### generate_makefile()

**作用**：生成 Makefile。

**特性**：

- 支持两种内核类型（通过 KERNEL_TYPE 变量）
- 自动设置输出目录
- 提供 help 目标显示使用说明

#### generate_readme()

**作用**：生成 README.md 文档。

**包含内容**：

- 驱动说明
- 目录结构
- 快速开始指南
- 模块参数文档
- 开发说明
- 故障排查

## 使用示例

### 基本用法

```bash
./scripts/driver_helper/template_creator.sh
```

### 交互式创建过程

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   交互式驱动创建脚本
   基于 example-driver 模板
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

=== 阶段 1: 驱动基本信息 ===

请输入驱动名称 (2-30字符, 小写字母/数字/_/-): my-driver

项目中现有的板子:
  - alpha-board
  - beta-board

请输入板名 [默认: alpha-board]: alpha-board

=== 阶段 2: 元数据信息 ===

请输入作者名 [默认: Your Name]: Developer

许可证选项:
  1) GPL      (推荐用于内核模块)
  2) MIT
  3) Apache-2.0
  4) BSD
请选择许可证 [默认: 1]: 1

请输入驱动描述 (简短说明): My first driver

=== 阶段 3: 模块参数配置 ===

需要多少个模块参数? [0-5, 默认: 0]: 1

配置参数 1/1
  参数名: debug_level
  参数类型:
    1) int     (整数)
    2) bool    (布尔值)
    3) charp   (字符串)
  选择 [默认: 1]: 1
  默认值: 0
  参数描述: Debug output level

=== 阶段 4: 内核配置 ===

内核类型选择:
  1) mainline  (主线内核)
  2) imx       (NXP BSP内核)
请选择内核类型 [默认: mainline]: 1

=== 阶段 5: 确认并生成 ==========

========== 配置摘要 ==========
驱动名称:     my-driver
板名:         alpha-board
作者:         Developer
许可证:       GPL
描述:         My first driver
内核类型:     mainline

模块参数:
  - debug_level (int) = 0  # Debug output level

目标目录:    driver/my-driver/alpha-board/
==============================

确认创建驱动? (Y/n): y

创建驱动目录: driver/my-driver/alpha-board/
生成驱动源码: driver/my-driver/alpha-board/my_driver_driver.c
✓ 源码生成完成
生成Makefile: driver/my-driver/alpha-board/Makefile
✓ Makefile生成完成
生成README.md: driver/my-driver/alpha-board/README.md
✓ README.md生成完成

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ 驱动创建成功！

位置: driver/my-driver/alpha-board/

下一步：
  1. 编辑源码: vim driver/my-driver/alpha-board/my_driver_driver.c
  2. 构建驱动: scripts/driver_helper/build_driver.sh my-driver alpha-board
  3. 部署驱动: scripts/driver_helper/deploy_driver.sh my-driver alpha-board
  4. 查看帮助: scripts/driver_helper/build_driver.sh --help

更多信息请查看: driver/my-driver/alpha-board/README.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 验证规则

### 驱动名称验证

| 规则 | 说明 | 示例 |
|------|------|------|
| 长度 | 2-30 个字符 | ✓ `my-driver` |
| 首字符 | 必须是小写字母 | ✓ `a1`, ✗ `1driver` |
| 允许字符 | 小写字母、数字、下划线、连字符 | ✓ `my_driver_01` |
| 保留字 | 不能是保留字 | ✗ `module` |

### 板卡名称验证

| 规则 | 说明 |
|------|------|
| 非空 | 不能为空 |
| 字符集 | 字母、数字、下划线、连字符 |

### 参数名称验证

| 规则 | 说明 | 示例 |
|------|------|------|
| C 变量命名规则 | 字母或下划线开头 | ✓ `param1`, `my_param` |
| 字符集 | 字母、数字、下划线 | ✗ `1param`, `my-param` |

## 故障排除

### 常见错误

#### 错误 1：驱动名验证失败

```
[ERROR] 驱动名只能包含小写字母、数字、下划线和连字符，且必须以字母开头
```

**解决方法**：

使用符合规则的名称，如 `my-driver` 而不是 `My-Driver` 或 `1driver`。

#### 错误 2：使用保留字

```
[ERROR] 'module' 是保留字，不能用作驱动名
```

**解决方法**：

选择其他名称，避免使用保留字。

#### 错误 3：目录已存在

```
[WARN] 驱动目录已存在: driver/my-driver/alpha-board
是否覆盖现有驱动? (y/N):
```

**解决方法**：

1. 输入 `n` 取消操作，使用不同的驱动名
2. 输入 `y` 覆盖现有驱动

#### 错误 4：模板目录不存在

```
[ERROR] 模板目录不存在: driver/example-driver/alpha-board
```

**解决方法**：

确保 example-driver 模板存在。

## 生成文件说明

### 驱动源码结构

```
<驱动名>_driver.c
├── 头文件引用
├── 模块参数定义（如果有）
├── 模块初始化函数
├── 模块退出函数
└── 模块元数据
```

### Makefile 特性

| 特性 | 说明 |
|------|------|
| 双内核支持 | 通过 `KERNEL_TYPE` 变量切换 |
| 输出目录 | `out/driver_artifacts/<驱动>/<板卡>/` |
| 帮助目标 | `make help` 显示使用说明 |
| 清理目标 | `make clean` 清理产物 |

### README.md 内容

- 驱动说明和目录结构
- 快速开始指南（编译、部署、测试）
- 模块参数详细文档
- 开发说明和内核切换方法
- 故障排查指南

## 相关文档

- [build_driver.sh](./build_driver.sh.md) - 驱动构建脚本
- [driver_buildlib.sh](../lib/driver_buildlib.sh) - 核心构建库
- [驱动开发工作流程](./workflow.md)
