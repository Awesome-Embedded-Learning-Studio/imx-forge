# 驱动开发工作流程指南

> **目标读者**：新手、有经验的开发者 | **阅读时间**：10分钟 | **难度**：🟢-🟡

## 📋 目录

- [工作流程概览](#工作流程概览)
- [场景1：从零创建新驱动](#场景1从零创建新驱动)
- [场景2：日常开发迭代](#场景2日常开发迭代)
- [场景3：调试和排查问题](#场景3调试和排查问题)
- [最佳实践](#最佳实践)
- [常见问题](#常见问题)

---

## 工作流程概览

### 🔄 完整开发周期

```
┌─────────────────────────────────────────────────────────────┐
│                    驱动开发完整流程                           │
└─────────────────────────────────────────────────────────────┘

  开发阶段                          构建阶段
  ┌─────────────┐                  ┌─────────────┐
  │ 1. 编写代码 │                  │ 4. 构建驱动 │
  │ 2. 编写DTS  │ ───────────────▶ │ 5. 编译DTB  │
  │ 3. 本地测试 │                  │ 6. 生成产物 │
  └─────────────┘                  └──────┬──────┘
                                          │
  验证阶段                          部署阶段
                                          │
  ┌─────────────┐                  ┌──────▼──────┐
  │ 9. 功能验证 │ ◀─────────────── │ 7. 审查产物 │
  │10. 性能测试 │                  │ 8. 部署驱动 │
  └─────────────┘                  └─────────────┘
```

### 📊 工作流程阶段

| 阶段 | 任务 | 脚本/工具 | 难度 |
|-----|------|----------|-----|
| **开发** | 编写驱动代码、设备树 | 编辑器 | 🟢 |
| **构建** | 编译驱动模块、设备树 | `build_driver.sh` | 🟢 |
| **审查** | 验证产物完整性 | `review_driver.sh` | 🟡 |
| **部署** | 上传到目标设备 | `deploy_driver.sh` | 🟢 |
| **验证** | 功能测试、调试 | `show_device_tree.sh` | 🟡 |

---

## 场景1：从零创建新驱动

> **难度**：🟢 初级 | **预计时间**：30-45分钟

### 📝 前置条件

确保已完成以下准备工作：
- ✅ 内核已编译（`out/mainline/linux/.config`存在）
- ✅ 交叉编译工具链已安装
- ✅ 项目结构已初始化

### 步骤1：创建驱动目录结构 🟢

#### 1.1 创建驱动源码目录

```bash
# 创建驱动目录
mkdir -p driver/my-driver/alpha-board

# 进入目录
cd driver/my-driver/alpha-board
```

#### 1.2 编写驱动代码

创建`my-driver.c`：

```c
// driver/my-driver/alpha-board/my-driver.c
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

// 驱动信息
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("My Custom Driver");
MODULE_VERSION("1.0");

// Probe函数
static int my_driver_probe(struct platform_device *pdev)
{
    pr_info("my-driver: Probe function called\n");

    // 读取设备树属性
    struct device_node *np = pdev->dev.of_node;
    const char *compatible;
    of_property_read_string(np, "compatible", &compatible);
    pr_info("my-driver: compatible = %s\n", compatible);

    return 0;
}

// Remove函数
static int my_driver_remove(struct platform_device *pdev)
{
    pr_info("my-driver: Remove function called\n");
    return 0;
}

// 设备树匹配表
static const struct of_device_id my_driver_of_match[] = {
    { .compatible = "imx,my-driver", },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, my_driver_of_match);

// 平台驱动结构
static struct platform_driver my_driver = {
    .probe = my_driver_probe,
    .remove = my_driver_remove,
    .driver = {
        .name = "my_driver",
        .of_match_table = my_driver_of_match,
    },
};
module_platform_driver(my_driver);
```

#### 1.3 创建Makefile

创建`Makefile`：

```makefile
# driver/my-driver/alpha-board/Makefile
obj-m += my-driver.o

# 内核构建目录
KERNEL_SRC := $(HOME)/imx-forge/third_party/linux_mainline
BUILD_DIR := $(HOME)/imx-forge/out/mainline/linux

# 构建目标
all:
	$(MAKE) ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- \
	      -C $(KERNEL_SRC) M=$(PWD) O=$(BUILD_DIR) modules

clean:
	$(MAKE) ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- \
	      -C $(KERNEL_SRC) M=$(PWD) O=$(BUILD_DIR) clean
```

### 步骤2：创建设备树文件 🟡

#### 2.1 创建设备树目录

```bash
# 创建设备树目录
mkdir -p driver/device_tree/alpha-board/my-driver
```

#### 2.2 编写设备树源文件

创建`imx6ull-aes-my-driver.dts`：

```dts
// driver/device_tree/alpha-board/my-driver/imx6ull-aes-my-driver.dts
/dts-v1/;

#include "imx6ull-aes.dtsi"  // 主板设备树

/ {
    model = "Alpha Board with My Driver";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

    // 自定义节点
    my_driver: my-driver {
        compatible = "imx,my-driver";
        status = "okay";

        // 自定义属性
        clock-frequency = <50000000>;
        gpio-count = <4>;
    };
};
```

### 步骤3：构建驱动 🟢

```bash
# 回到项目根目录
cd /path/to/imx-forge

# 构建驱动
./scripts/driver_helper/build_driver.sh my-driver alpha-board
```

**预期输出**：
```
========================================
构建驱动: my-driver/alpha-board
内核: mainline
========================================

[INFO] 检查内核配置...
[INFO] ✓ 内核已配置
[INFO] 编译驱动模块...
[INFO] ✓ 编译完成 (1 个模块)
[INFO] 编译设备树...
[INFO] ✓ 编译完成 (1 个设备树)
[INFO] ✓ 构建完成

📦 产物位置: out/driver_artifacts/my-driver/alpha-board/
========================================
```

### 步骤4：审查构建产物 🟡

```bash
# 审查产物
./scripts/driver_helper/review_driver.sh my-driver alpha-board
```

**检查项目**：
- ✅ 驱动模块架构（ARM）
- ✅ init/exit函数存在
- ✅ 设备树格式正确
- ✅ 符号表完整

### 步骤5：查看设备树 🟢

```bash
# 查看设备树结构
./scripts/driver_helper/show_device_tree.sh \
  out/driver_artifacts/my-driver/alpha-board/imx6ull-aes-my-driver.dtb
```

**预期输出**：
```
🌳 设备树节点结构
═════════════════════════════════════════════════════

🌲 节点树结构
│  ├──my_driver
│     ✦ compatible = "imx,my-driver"
│     ✦ status = "okay"
│     ✦ clock-frequency = "50000000"
│     ✦ gpio-count = "4"
```

### 步骤6：部署驱动 🟢

#### 6.1 选择部署方式

**方式1：TFTP部署（推荐用于开发）**
```bash
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/my-driver/alpha-board \
  --target=tftp
```

**方式2：NFS部署（推荐用于测试）**
```bash
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/my-driver/alpha-board \
  --target=nfs
```

#### 6.2 验证部署

```bash
# 检查TFTP目录
ls -lh ~/tftp/imx6ull-aes.dtb

# 检查NFS目录
ls -lh rootfs/nfs/lib/modules/
ls -lh rootfs/nfs/boot/
```

### 步骤7：在目标板上验证 🟡

#### 7.1 加载驱动模块

```bash
# 在目标板上执行
insmod my-driver.ko

# 检查日志
dmesg | tail -20
```

**预期输出**：
```
[ 123.456789] my-driver: Probe function called
[ 123.456890] my-driver: compatible = imx,my-driver
```

#### 7.2 检查设备节点

```bash
# 检查设备是否注册
ls -l /sys/devices/platform/my-driver/

# 检查驱动绑定
ls -l /sys/bus/platform/drivers/my_driver/
```

#### 7.3 卸载驱动

```bash
# 卸载驱动
rmmod my_driver

# 检查日志
dmesg | tail -10
```

**预期输出**：
```
[ 234.567890] my-driver: Remove function called
```

### ✅ 完成检查清单

- [ ] 驱动代码编译通过
- [ ] 设备树编译通过
- [ ] 产物审查通过
- [ ] 部署成功
- [ ] 驱动加载成功
- [ ] 功能验证通过
- [ ] 卸载无错误

---

## 场景2：日常开发迭代

> **难度**：🟢 初级 | **预计时间**：10-15分钟

### 🔄 迭代开发流程

#### 步骤1：修改代码 🟢

```bash
# 编辑驱动代码
vim driver/my-driver/alpha-board/my-driver.c

# 或编辑设备树
vim driver/device_tree/alpha-board/my-driver/imx6ull-aes-my-driver.dts
```

#### 步骤2：快速重新构建 🟢

```bash
# 增量构建（只编译修改的文件）
./scripts/driver_helper/build_driver.sh my-driver alpha-board
```

**提示**：系统会自动检测修改，只重新编译必要的文件。

#### 步骤3：快速审查 🟡

```bash
# 快速审查产物
./scripts/driver_helper/review_driver.sh my-driver
```

#### 步骤4：快速部署 🟢

```bash
# 使用历史命令快速部署
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/my-driver/alpha-board \
  --target=tftp
```

#### 步骤5：验证修改 🟡

```bash
# 在目标板上
rmmod my_driver           # 卸载旧版本
insmod my-driver.ko       # 加载新版本
dmesg | tail -20          # 查看日志
```

### 🚀 批量开发场景

#### 同时开发多个驱动

```bash
# 构建所有驱动
./scripts/driver_helper/build_driver.sh --all

# 只构建特定板卡的驱动
./scripts/driver_helper/build_driver.sh --all --board=alpha-board
```

#### 批量部署

```bash
# 部署所有驱动（脚本循环）
for driver in driver/*/; do
    name=$(basename "$driver")
    ./scripts/driver_helper/deploy_driver.sh \
      "out/driver_artifacts/${name}/alpha-board" \
      --target=nfs
done
```

### 📊 版本管理建议

#### 修改前的准备工作

```bash
# 1. 备份当前工作版本
./scripts/driver_helper/build_driver.sh my-driver alpha-board
cp -r out/driver_artifacts/my-driver/alpha-board \
      out/driver_artifacts/my-driver/alpha-board.backup

# 2. 创建Git分支
git checkout -b dev/my-new-feature

# 3. 记录当前状态
./scripts/driver_helper/review_driver.sh my-driver > \
  out/review_before.txt
```

#### 修改后的验证

```bash
# 1. 构建新版本
./scripts/driver_helper/build_driver.sh my-driver alpha-board

# 2. 对比产物
./scripts/driver_helper/review_driver.sh my-driver > \
  out/review_after.txt
diff out/review_before.txt out/review_after.txt

# 3. 保留两个版本用于回滚
# out/driver_artifacts/my-driver/alpha-board/      # 新版本
# out/driver_artifacts/my-driver/alpha-board.backup/ # 旧版本
```

---

## 场景3：调试和排查问题

> **难度**：🟡-🔴 中级 | **预计时间**：15-30分钟

### 🔍 常见问题诊断

#### 问题1：构建失败 🟡

**症状**：
```
[ERROR] 驱动编译失败
make: *** No rule to make target 'modules'
```

**诊断步骤**：

1. **检查内核编译状态**
```bash
# 检查内核配置
ls -l out/mainline/linux/.config

# 检查关键文件
ls -l out/mainline/linux/Module.symvers
ls -l out/mainline/linux/include/generated/autoconf.h
```

2. **启用调试模式**
```bash
# 启用详细输出
DEBUG=1 ./scripts/driver_helper/build_driver.sh my-driver
```

3. **解决方法**
```bash
# 方案A：完整编译内核
cd third_party/linux_mainline
make O=../../out/mainline/linux \
     ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- \
     -j$(nproc)

# 方案B：快速准备（推荐）
cd third_party/linux_mainline
make O=../../out/mainline/linux \
     ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- \
     modules_prepare
```

#### 问题2：设备树编译失败 🟡

**症状**：
```
[WARN] device-tree编译失败
Error: /path/to/file.dts:10.1-9 syntax error
```

**诊断步骤**：

1. **手动编译设备树（获取详细错误）**
```bash
# 预处理
gcc -E -nostdinc -P -x assembler-with-cpp \
    -I third_party/linux_mainline/arch/arm/boot/dts \
    -I third_party/linux_mainline/arch/arm/boot/dts/nxp/imx \
    -I third_party/linux_mainline/include \
    -I driver/device_tree/alpha-board/linux \
    -undef -D__DTS__ \
    -o /tmp/preprocessed.dts \
    driver/device_tree/alpha-board/my-driver/imx6ull-aes-my-driver.dts

# 编译
dtc -I dts -O dtb \
    -i third_party/linux_mainline/arch/arm/boot/dts \
    -o /tmp/output.dtb \
    /tmp/preprocessed.dts
```

2. **检查include路径**
```bash
# 查看实际使用的include路径
DEBUG=1 ./scripts/driver_helper/build_driver.sh my-driver | grep Include
```

3. **验证设备树语法**
```bash
# 反编译检查
dtc -I dtb -O dts -o /tmp/check.dts \
    out/driver_artifacts/my-driver/alpha-board/imx6ull-aes-my-driver.dtb
```

#### 问题3：驱动加载失败 🟡

**症状**：
```
# insmod: ERROR: could not insert module my-driver.ko: Unknown symbol
```

**诊断步骤**：

1. **检查模块依赖**
```bash
# 查看依赖关系
modinfo out/driver_artifacts/my-driver/alpha-board/my-driver.ko | grep depends

# 检查符号表
readelf -s out/driver_artifacts/my-driver/alpha-board/my-driver.ko | grep UND
```

2. **检查内核版本匹配**
```bash
# 查看模块版本
modinfo my-driver.ko | grep vermagic

# 查看内核版本
uname -r
```

3. **启用详细日志**
```bash
# 在目标板上
insmod my-driver.ko

# 查看详细日志
dmesg | grep -i "my-driver\|error\|symbol"
```

#### 问题4：设备树不生效 🔴

**症状**：
```
# 驱动加载但probe函数不被调用
# dmesg中无probe日志
```

**诊断步骤**：

1. **检查设备树是否加载**
```bash
# 在目标板上
# 查看设备树
ls -l /sys/firmware/devicetree/base/

# 查找自定义节点
find /sys/firmware/devicetree/base/ -name "*my*"
```

2. **检查compatible属性**
```bash
# 查看设备树中的compatible
cat /sys/firmware/devicetree/base/my-driver/compatible

# 查看驱动支持的compatible
modprobe my-driver
grep -r "imx,my-driver" /sys/module/my_driver/sections/
```

3. **检查驱动绑定**
```bash
# 查看驱动是否绑定
ls -l /sys/bus/platform/drivers/my_driver/

# 手动绑定（如需要）
echo my-driver > /sys/bus/platform/drivers/my_driver/bind
```

### 🛠️ 调试工具和技巧

#### 1. 使用show_device_tree.sh调试

```bash
# 查看完整设备树
./scripts/driver_helper/show_device_tree.sh \
  out/driver_artifacts/my-driver/alpha-board/imx6ull-aes-my-driver.dtb \
  --all

# 搜索特定节点
./scripts/driver_helper/show_device_tree.sh \
  imx6ull-aes-my-driver.dtb \
  --search "compatible"
```

#### 2. 启用内核调试选项

在内核配置中启用：
```
CONFIG_DYNAMIC_DEBUG=y
CONFIG_DEBUG_FS=y
```

#### 3. 使用动态调试

```bash
# 在目标板上
# 查看可用的调试信息
echo 'module my_driver +p' > /sys/kernel/debug/dynamic_debug/control

# 查看所有调试信息
cat /sys/kernel/debug/dynamic_debug/control | grep my_driver
```

#### 4. 使用strace跟踪系统调用

```bash
# 在目标板上跟踪insmod
strace -o trace.log insmod my-driver.ko

# 查看跟踪结果
cat trace.log
```

### 📋 调试检查清单

#### 构建阶段
- [ ] 内核已正确编译
- [ ] 交叉编译工具链正确
- [ ] 设备树语法正确
- [ ] 源码文件无语法错误

#### 审查阶段
- [ ] 模块架构匹配（ARM）
- [ ] 符号表完整
- [ ] 设备树格式正确
- [ ] 无未解析的符号

#### 部署阶段
- [ ] 文件传输成功
- [ ] 文件权限正确
- [ ] 目标路径正确
- [ ] 设备树文件名匹配

#### 运行阶段
- [ ] 内核版本匹配
- [ ] 依赖模块已加载
- [ ] 设备树已加载
- [ ] compatible属性匹配

---

## 最佳实践

### ✅ 开发习惯

#### 1. 代码组织

```bash
# 推荐的目录结构
driver/my-driver/
├── alpha-board/               # 板卡特定代码
│   ├── Makefile              # 板卡Makefile
│   ├── my-driver.c           # 驱动源码
│   └── my-driver.h           # 头文件
└── beta-board/               # 其他板卡
    ├── Makefile
    └── my-driver.c

driver/device_tree/
└── alpha-board/              # 板卡设备树
    └── my-driver/
        └── imx6ull-aes-my-driver.dts
```

#### 2. 版本控制

```bash
# 提交前检查
./scripts/driver_helper/build_driver.sh my-driver
./scripts/driver_helper/review_driver.sh my-driver

# 提交产物信息
git add out/driver_artifacts/my-driver/*/build_info.txt
```

#### 3. 文档记录

在驱动目录中创建`README.md`：

```markdown
# My Driver

## 功能描述
驱动的主要功能说明

## 硬件连接
- GPIO: GPIO1_IO01
- 时钟: 50MHz

## 设备树属性
- compatible: "imx,my-driver"
- clock-frequency: 时钟频率
- gpio-count: GPIO数量

## 测试命令
```bash
insmod my-driver.ko
dmesg | grep my-driver
```

## 已知问题
- 版本1.0: 无
```

### 🚀 性能优化

#### 1. 并行构建

```bash
# 使用多核编译
export MAKEFLAGS="-j$(nproc)"
./scripts/driver_helper/build_driver.sh --all
```

#### 2. 增量编译

```bash
# 只编译修改的文件
./scripts/driver_helper/build_driver.sh my-driver
```

#### 3. 缓存产物

```bash
# 保留常用版本的产物
mkdir -p out/artifacts_cache
cp -r out/driver_artifacts/my-driver/alpha-board \
      out/artifacts_cache/my-driver-stable
```

### 🔒 安全建议

#### 1. 备份重要文件

```bash
# 部署前备份
cp ~/tftp/imx6ull-aes.dtb ~/tftp/imx6ull-aes.dtb.backup
```

#### 2. 测试环境隔离

```bash
# 使用单独的测试目录
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/my-driver/alpha-board \
  --target=local \
  --local-dir=/tmp/test-env
```

#### 3. 逐步验证

```bash
# 先在本地测试
# 再部署到开发板
# 最后部署到生产环境
```

---

## 常见问题

<details>
<summary><b>❓ 如何切换内核类型？</b></summary>

使用`--kernel`参数：
```bash
# 使用mainline内核
./scripts/driver_helper/build_driver.sh my-driver --kernel=mainline

# 使用imx内核
./scripts/driver_helper/build_driver.sh my-driver --kernel=imx
```

</details>

<details>
<summary><b>❓ 如何清理构建产物？</b></summary>

```bash
# 清理特定驱动
./scripts/driver_helper/build_driver.sh --clean my-driver

# 清理所有驱动
./scripts/driver_helper/build_driver.sh --clean --all

# 手动清理产物目录
rm -rf out/driver_artifacts/
```

</details>

<details>
<summary><b>❓ 如何查看可用驱动？</b></summary>

```bash
# 列出所有驱动
./scripts/driver_helper/build_driver.sh --list
```

</details>

<details>
<summary><b>❓ 部署后如何回滚？</b></summary>

```bash
# TFTP部署会自动备份旧文件
# 在~/tftp/目录中查找带时间戳的备份文件
ls -lh ~/tftp/imx6ull-aes-*.dtb

# 恢复备份
cp ~/tftp/imx6ull-aes-20240301120000.dtb ~/tftp/imx6ull-aes.dtb
```

</details>

<details>
<summary><b>❓ 如何调试设备树问题？</b></summary>

```bash
# 1. 查看设备树结构
./scripts/driver_helper/show_device_tree.sh output.dtb --all

# 2. 搜索特定节点
./scripts/driver_helper/show_device_tree.sh output.dtb --search "compatible"

# 3. 在目标板上查看加载的设备树
cat /sys/firmware/devicetree/base/my-driver/compatible
```

</details>

---

## 附录

### 快速参考卡

#### 构建命令
```bash
# 单个驱动
./scripts/driver_helper/build_driver.sh <驱动> [板卡]

# 所有驱动
./scripts/driver_helper/build_driver.sh --all

# 列出驱动
./scripts/driver_helper/build_driver.sh --list

# 清理产物
./scripts/driver_helper/build_driver.sh --clean <驱动>
```

#### 部署命令
```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh <产物目录>

# 直接部署
./scripts/driver_helper/deploy_driver.sh <产物目录> --target=<类型>
```

#### 审查命令
```bash
# 审查产物
./scripts/driver_helper/review_driver.sh <驱动> [板卡]
```

#### 设备树命令
```bash
# 查看设备树
./scripts/driver_helper/show_device_tree.sh <设备树文件>

# 搜索节点
./scripts/driver_helper/show_device_tree.sh <设备树文件> --search "<关键词>"

# 完整显示
./scripts/driver_helper/show_device_tree.sh <设备树文件> --all
```

### 产物目录结构

```
out/driver_artifacts/<驱动>/<板卡>/
├── <驱动>.ko                 # 驱动模块
├── <板卡>-<驱动>.dtb        # 设备树文件
└── build_info.txt            # 构建信息
```

### 相关文档

- **[系统总览](./overview.md)** - 了解系统概况
- **[架构设计](./architecture.md)** - 深入理解系统原理
- **[脚本参考](./overview.md)** - 详细脚本文档
- **[错误排查指南](./troubleshooting.md)** - 常见问题解决

---

**返回目录** → [README](./README.md)
**继续学习** → [架构设计文档](./architecture.md)
