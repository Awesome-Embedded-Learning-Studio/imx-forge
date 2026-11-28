# review_driver.sh - 驱动审查脚本

## 概述

`review_driver.sh` 是 IMX Forge 项目中的驱动构建产物审查脚本，用于验证驱动模块和设备树的完整性、正确性和安全性。该脚本在部署前对构建产物进行全面检查，确保产物可以安全部署到目标系统。

## 功能特性

- ✅ 驱动模块完整性检查
- ✅ ELF 头信息分析
- ✅ 符号表和依赖关系验证
- ✅ 设备树格式和结构验证
- ✅ 代码段大小分析
- ✅ 构建信息审查
- ✅ 详细的审查报告

## 语法

```bash
./scripts/driver_helper/review_driver.sh <驱动> [板卡]
```

## 参数说明

### 位置参数

| 参数 | 说明 | 默认值 | 必需 |
|------|------|--------|------|
| 驱动 | 驱动名称（如：example-driver、led） | - | 是 |
| 板卡 | 板卡名称（如：alpha-board、beta-board） | alpha-board | 否 |

## 审查项目

### 1. 驱动模块审查

#### 文件信息检查
- 文件路径和大小
- 文件类型（ELF 格式）
- 文件权限和时间戳

#### 模块信息检查
- 模块名称和版本
- 作者和描述信息
- 许可证信息
- 依赖关系

#### ELF 头信息分析
- 架构类型（ARM 验证）
- ELF 类别（32/64 位）
- 文件类型（可重定位文件）
- 入口点和段信息

#### 代码段分析
- text 段大小（代码段）
- data 段大小（数据段）
- bss 段大小（未初始化段）
- 总大小估算

#### 符号表检查
- init 函数存在性
- exit 函数存在性
- 关键符号完整性
- 导出符号列表

#### 依赖关系验证
- 外部模块依赖
- 内核版本依赖
- 符号依赖完整性

#### 模块参数检查
- 参数名称和类型
- 参数默认值
- 参数权限设置

### 2. 设备树审查

#### 文件信息检查
- 文件大小和格式
- DTB 魔数验证（0xd00dfeed）
- 版本信息检查

#### 设备树结构分析
- 节点层次结构
- 节点数量统计
- 属性数量统计

#### 格式验证
- DTB 格式正确性
- 语法错误检查
- 引用完整性

#### 节点检查
- 节点命名规范
- 节点路径完整性
- compatible 属性

#### Compatible 属性验证
- compatible 字符串格式
- 厂商前缀验证
- 设备匹配规则

### 3. 构建信息审查

- 构建时间和用户
- 内核类型和版本
- 源码目录信息
- 产物文件清单
- 构建环境信息

## 使用示例

### 1. 审查单个驱动

```bash
# 审查默认板卡的驱动
./scripts/driver_helper/review_driver.sh example-driver

# 审查指定板卡的驱动
./scripts/driver_helper/review_driver.sh example-driver alpha-board
```

输出示例：
```
========================================
🔍 驱动构建产物审查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] 驱动: example-driver
[INFO] 板卡: alpha-board
[INFO] 目录: out/driver_artifacts/example-driver/alpha-board

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 驱动模块审查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 文件信息:
  文件: out/driver_artifacts/example-driver/alpha-board/example-driver.ko
  大小: 12K
  类型: ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV)

📋 模块信息:
  filename: example-driver.ko
  version: 0.1
  description: Example driver for IMX6ULL
  author: Your Name <your.email@example.com>
  license: GPL

🔍 ELF头信息:
  架构: ARM
  类型: REL (Relocatable file)
  类别: ELF32
  ✓ 架构正确 (ARM)

📊 代码段分析:
  text:  2345  - 代码段
  data:  456   - 数据段
  bss:   128   - 未初始化段
  总计:  2929 (b71)

🎯 关键符号:
  ✓ init 函数存在
  ✓ exit 函数存在

🔗 依赖关系:
  ✓ 无外部依赖 (独立模块)

⚙️  模块参数:
  无模块参数

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 检查总结:
  ✓ 驱动模块结构完整

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌳 设备树审查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 文件信息:
  文件: out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb
  大小: 1.2K

🔍 设备树结构:
/dts-v1/;
/ {
    #address-cells = <0x01>;
    #size-cells = <0x01>;
    compatible = "fsl,imx6ull";

    example-device@40050000 {
        compatible = "vendor,example-driver";
        reg = <0x40050000 0x1000>;
        status = "okay";
    };
};

📋 格式验证:
  ✓ DTB魔数正确 (0xd00dfeed)
  版本: 17
  节点数量: 2

🎯 设备节点:
  - example-device@40050000

🔗 Compatible属性:
  - vendor,example-driver

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ 设备树格式正确

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 构建信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
驱动构建信息
================
构建时间: 2026-04-07 12:34:56
构建用户: charlie@hostname
内核类型: 主线内核 (linux_mainline)
驱动目录: driver/example-driver/alpha-board

产物文件:
  - example-driver.ko (12K)
  - imx6ull-aes-example-driver.dtb (1.2K)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 审查总结
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ 驱动模块审查通过

📦 产物清单:
  12K       example-driver.ko
  1.2K      imx6ull-aes-example-driver.dtb
  256B      build_info.txt

✓ 所有产物审查通过，可以安全部署！

[INFO] 部署命令: ./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

### 2. 审查多个驱动

```bash
# 审查所有已构建的驱动
for driver in out/driver_artifacts/*/; do
    driver_name=$(basename "$driver")
    ./scripts/driver_helper/review_driver.sh "$driver_name"
done
```

### 3. 审查后部署

```bash
# 审查驱动
./scripts/driver_helper/review_driver.sh example-driver

# 如果审查通过，部署驱动
if [ $? -eq 0 ]; then
    ./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
fi
```

## 审查结果

### 成功输出

```
✅ 驱动模块审查通过

📦 产物清单:
  12K       example-driver.ko
  1.2K      imx6ull-aes-example-driver.dtb

✓ 所有产物审查通过，可以安全部署！
```

### 失败输出

```
✗ 驱动模块存在问题

可能的错误：
- ✗ init 函数缺失
- ✗ 架构错误 (期望: ARM, 实际: x86-64)
- ✗ 依赖模块未找到
```

## 常见问题

### 1. 驱动模块不存在

**错误信息**：
```
❌ 构建产物目录不存在: out/driver_artifacts/example-driver/alpha-board
```

**解决方案**：
```bash
# 先构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 然后再审查
./scripts/driver_helper/review_driver.sh example-driver
```

### 2. init/exit 函数缺失

**错误信息**：
```
✗ init 函数缺失
✗ exit 函数缺失
```

**解决方案**：
```bash
# 检查驱动源码
cat driver/example-driver/alpha-board/example-driver.c

# 确保包含模块初始化和退出函数
# module_init() 和 module_exit() 宏
```

### 3. 架构不匹配

**错误信息**：
```
✗ 架构错误 (期望: ARM, 实际: x86-64)
```

**解决方案**：
```bash
# 检查交叉编译工具链
echo $CROSS_COMPILE
# 应该输出: arm-none-linux-gnueabihf-

# 重新构建驱动
./scripts/driver_helper/build_driver.sh example-driver
```

### 4. 设备树格式错误

**错误信息**：
```
❌ 设备树格式错误或损坏
```

**解决方案**：
```bash
# 检查设备树文件
dtc -I dtb -O dts out/driver_artifacts/example-driver/alpha-board/*.dtb

# 重新构建驱动
./scripts/driver_helper/build_driver.sh example-driver
```

### 5. 依赖模块缺失

**错误信息**：
```
🔗 依赖关系:
  依赖: gpio_keys
```

**解决方案**：
```bash
# 确保依赖的模块已构建
./scripts/driver_helper/build_driver.sh gpio_keys

# 或者在内核配置中启用相关模块
```

## 审查最佳实践

### 1. 部署前必审

```bash
# 构建后立即审查
./scripts/driver_helper/build_driver.sh example-driver
./scripts/driver_helper/review_driver.sh example-driver

# 审查通过后再部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

### 2. 版本发布前审查

```bash
# 审查所有驱动
for driver in driver/*/; do
    driver_name=$(basename "$driver")
    if [ -d "out/driver_artifacts/$driver_name/alpha-board" ]; then
        ./scripts/driver_helper/review_driver.sh "$driver_name"
    fi
done
```

### 3. CI/CD 集成

```yaml
# .gitlab-ci.yml 示例
review:
  stage: review
  script:
    - ./scripts/driver_helper/build_driver.sh example-driver
    - ./scripts/driver_helper/review_driver.sh example-driver
  only:
    - merge_requests
```

## 审查报告说明

### 文件信息

- **文件路径**：产物的完整路径
- **文件大小**：产物的磁盘占用
- **文件类型**：ELF 或 DTB 格式

### 模块信息

- **filename**：模块文件名
- **version**：模块版本
- **description**：模块描述
- **author**：作者信息
- **license**：许可证类型

### ELF 头信息

- **架构**：目标处理器架构
- **类型**：ELF 文件类型
- **类别**：32/64 位

### 代码段分析

- **text**：代码段大小（包含执行代码）
- **data**：数据段大小（包含初始化数据）
- **bss**：未初始化段大小
- **总计**：总大小（十进制和十六进制）

### 关键符号

- **init 函数**：模块初始化函数
- **exit 函数**：模块退出函数

### 依赖关系

- **无外部依赖**：独立模块
- **依赖: xxx**：依赖的其他模块

### 设备树验证

- **DTB 魔数**：0xd00dfeed（正确的 DTB 文件）
- **版本**：设备树版本号
- **节点数量**：总节点数
- **Compatible 属性**：设备兼容字符串

## 与其他脚本的配合

### 1. 构建后审查

```bash
# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 审查产物
./scripts/driver_helper/review_driver.sh example-driver
```

### 2. 审查后部署

```bash
# 审查驱动
./scripts/driver_helper/review_driver.sh example-driver

# 审查通过后部署
if [ $? -eq 0 ]; then
    ./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
fi
```

### 3. 审查后查看设备树

```bash
# 审查驱动
./scripts/driver_helper/review_driver.sh example-driver

# 查看设备树详细内容
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/*.dtb --all
```

## 高级用法

### 1. 自动化审查脚本

```bash
#!/bin/bash
# auto_review.sh

for driver_dir in out/driver_artifacts/*/; do
    driver_name=$(basename "$driver_dir")
    echo "审查驱动: $driver_name"

    ./scripts/driver_helper/review_driver.sh "$driver_name"

    if [ $? -eq 0 ]; then
        echo "✓ $driver_name 审查通过"
    else
        echo "✗ $driver_name 审查失败"
        exit 1
    fi
done

echo "所有驱动审查通过！"
```

### 2. 审查日志记录

```bash
# 记录审查结果
./scripts/driver_helper/review_driver.sh example-driver | tee review_$(date +%Y%m%d_%H%M%S).log
```

### 3. 审查报告生成

```bash
# 生成详细审查报告
./scripts/driver_helper/review_driver.sh example-driver > review_report.txt

# 发送审查报告
mail -s "驱动审查报告" user@example.com < review_report.txt
```

## 注意事项

1. **审查时机**：部署前必须审查，确保产物正确
2. **架构匹配**：确保驱动架构与目标系统一致
3. **依赖完整**：检查所有依赖模块是否可用
4. **设备树正确**：验证设备树格式和内容
5. **符号完整**：确保必需的符号都存在
6. **版本兼容**：检查内核版本兼容性

## 相关文档

- [build_driver.md](./build_driver.md) - 驱动构建脚本
- [deploy_driver.md](./deploy_driver.md) - 驱动部署脚本
- [show_device_tree.sh.md](./show_device_tree.sh.md) - 设备树查看脚本
- [configuration.md](./configuration.md) - 配置文件说明
- [driver_buildlib.md](../lib/driver_buildlib.md) - 构建库说明
