# Example Driver 验证指南

> **目标读者**：新手驱动开发者、需要验证环境功能的人
>
> **难度级别**：🟢 初级
>
> **预计时间**：15-20分钟

## 📋 什么是 example-driver？

`example-driver` 是一个**虚拟驱动**，专门用于验证驱动开发基建系统是否正常工作。它不实际驱动任何硬件，而是：

✅ **验证构建工具链** - 确保交叉编译环境配置正确
✅ **验证部署脚本** - 测试驱动文件能否正确部署到目标位置
✅ **验证加载流程** - 确认驱动可以正常加载和卸载
✅ **提供学习示例** - 作为最简单的驱动代码参考

### 特点

- 📝 **代码简单** - 只有不到50行C代码
- 🔧 **零依赖** - 不依赖任何硬件或特定内核配置
- 🚀 **快速验证** - 5分钟内完成完整验证流程
- 📚 **教学友好** - 包含详细注释和说明

## 🚀 快速验证流程

### 第一步：编译驱动

```bash
# 进入项目根目录
cd /home/charliechen/imx-forge

# 编译example-driver
./scripts/driver_helper/build_driver.sh example-driver

# 预期输出：
# ========================================
# 🔨 构建驱动: example-driver/alpha-board
# 内核: mainline
# ========================================
# 编译驱动模块...
# ✓ 编译完成 (1 个模块)
# 编译设备树...
# ✓ 编译完成 (1 个设备树)
# ========================================
# ✓ 构建完成: /home/charliechen/imx-forge/out/driver_artifacts/example-driver/alpha-board
# ========================================
```

### 第二步：检查编译产物

```bash
# 查看生成的文件
ls -lh out/driver_artifacts/example-driver/alpha-board/

# 预期输出：
# 总用量 20K
# -rw-r--r-- 1 user user  10K 4月  7 19:33 fake_driver.ko
# -rw-r--r-- 1 user user  500 4月  7 19:33 imx6ull-aes-example-driver.dtb
# -rw-r--r-- 1 user user  300 4月  7 19:33 build_info.txt
```

**成功标志**：
- ✅ 生成了 `fake_driver.ko` 文件
- ✅ 生成了设备树文件 `.dtb`
- ✅ 文件大小合理（.ko文件约10KB）

### 第三步：部署驱动

#### 方法A：交互式部署（推荐新手）

```bash
# 使用交互式部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board

# 按提示选择：
# 1) TFTP服务器
# 2) NFS rootfs
# 3) 本地目录
# 4) 远程服务器
# 请选择 [1-4]: 3
# 目标目录: /tmp/test-deploy
```

#### 方法B：直接部署（推荐熟练用户）

```bash
# 直接部署到TFTP
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/example-driver/alpha-board \
  --target=tftp

# 预期输出：
# [INFO] 部署到TFTP: ~/tftp
# [INFO]   ✓ imx6ull-aes-example-driver.dtb → imx6ull-aes.dtb
# [INFO] 已复制 1 个设备树文件（.ko 文件已跳过）
# [INFO] ✓ 部署完成
```

**成功标志**：
- ✅ 文件成功复制到目标位置
- ✅ 没有权限错误
- ✅ 目标目录包含正确的文件

### 第四步：板上验证

#### 1. 加载驱动模块

```bash
# 在目标板上执行
insmod fake_driver.ko

# 预期输出：
# (无输出表示成功)
```

#### 2. 检查加载状态

```bash
# 查看内核日志
dmesg | tail -10

# 预期输出：
# [12345.678] === Fake驱动加载成功 ===
# [12345.678] 测试参数值: 42
# [12345.678] 这是一个验证构建工具链的虚拟驱动
# [12345.678] 不实际驱动任何硬件
# [12345.678] ========================

# 检查模块是否加载
lsmod | grep fake

# 预期输出：
# fake_driver             16384  0
```

#### 3. 检查模块信息

```bash
# 查看模块详细信息
modinfo fake_driver

# 预期输出：
# filename:       fake_driver.ko
# version:        1.0
# description:    Fake驱动 - 仅用于验证构建工具链
# author:         IMX-Forge Framework
# license:        GPL
# srcversion:     XXXXXXXXXXXXXXXX
# depends:
# retpoline:      Y
# intree:         Y
# filename:       ( Canadiens)
# parm:           test_value:测试参数 (int)
```

#### 4. 测试模块参数

```bash
# 使用自定义参数加载
rmmod fake_driver
insmod fake_driver.ko test_value=100

# 查看日志确认参数生效
dmesg | tail -5

# 预期输出：
# [12346.789] === Fake驱动加载成功 ===
# [12346.789] 测试参数值: 100          # ← 这里应该显示100
# [12346.789] 这是一个验证构建工具链的虚拟驱动
```

#### 5. 卸载驱动

```bash
# 卸载驱动
rmmod fake_driver

# 查看日志
dmesg | tail -5

# 预期输出：
# [12347.123] === Fake驱动卸载成功 ===
# [12347.123] 工具链验证完成！
# [12347.123] ========================
```

## ✅ 完整验证命令清单

### 开发机器上执行

```bash
# 1. 编译驱动
./scripts/driver_helper/build_driver.sh example-driver

# 2. 检查产物
ls -lh out/driver_artifacts/example-driver/alpha-board/

# 3. 部署到TFTP
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/example-driver/alpha-board \
  --target=tftp

# 4. (可选) 通过网络传输到开发板
# scp out/driver_artifacts/example-driver/alpha-board/fake_driver.ko \
#    user@board:/tmp/
```

### 目标板上执行

```bash
# 1. 加载驱动
insmod fake_driver.ko

# 2. 验证加载
dmesg | tail -10
lsmod | grep fake

# 3. 测试参数
rmmod fake_driver
insmod fake_driver.ko test_value=100
dmesg | tail -5

# 4. 查看模块信息
modinfo fake_driver

# 5. 卸载驱动
rmmod fake_driver

# 6. 确认卸载
lsmod | grep fake
# (应该无输出)
```

## 🎯 成功标志清单

完整的验证成功应该包含以下所有标志：

### 编译阶段
- [ ] 脚本执行无错误
- [ ] 生成了 `fake_driver.ko` 文件
- [ ] 生成了 `.dtb` 设备树文件
- [ ] 产物文件大小合理（.ko约10KB，.dtb约500B）

### 部署阶段
- [ ] 文件成功复制到目标位置
- [ ] 目标目录权限正确
- [ ] 文件完整性保持（大小一致）

### 加载阶段
- [ ] `insmod` 命令无错误输出
- [ ] `dmesg` 显示驱动初始化日志
- [ ] `lsmod` 能查看到模块
- [ ] `modinfo` 显示正确的模块信息

### 运行阶段
- [ ] 模块参数可以正常修改
- [ ] 参数修改后的值在日志中正确显示

### 卸载阶段
- [ ] `rmmod` 命令无错误
- [ ] `dmesg` 显示驱动退出日志
- [ ] `lsmod` 确认模块已移除

## ⚠️ 常见错误和排查方法

### 错误1：编译失败

**现象**：
```bash
make: *** No rule to make target 'modules'. Stop.
```

**可能原因**：
- 内核源码路径配置错误
- 内核未正确配置或编译

**解决步骤**：
```bash
# 1. 检查内核源码路径
ls -la third_party/linux-mainline/

# 2. 检查内核配置
ls -la out/mainline/linux/.config

# 3. 如果缺少配置，重新配置内核
cd third_party/linux-mainline/
make O=../../../out/mainline/linux ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- imx_aes_mainline_defconfig

# 4. 如果需要，准备内核模块
make O=../../../out/mainline/linux ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
```

**预防措施**：
- 首次使用前，确保内核已经配置和编译
- 定期检查内核配置文件是否存在

### 错误2：设备树编译失败

**现象**：
```bash
Warning (unit_address_vs_reg): /fake-i2c-device: node has a reg ...
Error: .../fake-i2c@50: FATAL ERROR: ...
```

**可能原因**：
- 设备树语法错误
- include路径不正确
- 依赖的设备树文件缺失

**解决步骤**：
```bash
# 1. 手动编译设备树查看详细错误
cd driver/device_tree/alpha-board/example-driver/
gcc -E -nostdinc -P -x assembler-with-cpp \
  -I ../../../third_party/linux-mainline/arch/arm/boot/dts \
  -I ../../../third_party/linux-mainline/arch/arm/boot/dts/nxp/imx \
  -I ../../../third_party/linux-mainline/include \
  -I ./linux \
  -undef -D__DTS__ \
  -o /tmp/test.dts imx6ull-aes-example-driver.dts

# 2. 使用dtc编译预处理后的文件
dtc -I dts -O dtb -o /tmp/test.dtb /tmp/test.dts

# 3. 根据错误信息修正设备树文件
```

**预防措施**：
- 使用支持的编辑器编写设备树（支持语法高亮）
- 参考内核文档中的设备树规范
- 编译前先进行语法检查

### 错误3：驱动加载失败

**现象**：
```bash
insmod: ERROR: could not insert module fake_driver.ko: Unknown symbol
```

**可能原因**：
- 内核版本不匹配
- 驱动编译时使用的内核与运行时内核不同

**解决步骤**：
```bash
# 1. 检查内核版本
uname -r

# 2. 检查模块信息
modinfo fake_driver.ko | grep vermagic

# 3. 重新编译驱动，确保使用正确的内核
cd /home/charliechen/imx-forge
./scripts/driver_helper/build_driver.sh example-driver --kernel=mainline

# 或者如果使用imx内核
./scripts/driver_helper/build_driver.sh example-driver --kernel=imx
```

**预防措施**：
- 确保驱动编译时的内核与目标板运行的内核一致
- 使用 `--kernel=` 参数指定正确的内核类型

### 错误4：权限错误

**现象**：
```bash
insmod: ERROR: could not insert module fake_driver.ko: Permission denied
```

**可能原因**：
- 当前用户没有root权限
- 文件系统权限问题

**解决步骤**：
```bash
# 1. 使用sudo加载驱动
sudo insmod fake_driver.ko

# 2. 或者切换到root用户
su -
insmod fake_driver.ko

# 3. 检查文件权限
ls -l fake_driver.ko
# 应该显示 -rw-r--r--
```

**预防措施**：
- 始终使用root权限加载驱动模块
- 在部署时设置正确的文件权限

### 错误5：节点文件未创建

**现象**：
```bash
# 驱动加载成功，但找不到设备节点
ls /dev/fake*
# ls: 无法访问'/dev/fake*': 没有那个文件或目录
```

**可能原因**：
- **这是正常的！** example-driver是虚拟驱动，不创建设备节点
- 驱动初始化代码中没有创建设备节点

**说明**：
```bash
# example-driver不会创建设备节点
# 它只验证驱动加载/卸载流程

# 正确的验证方法是查看内核日志
dmesg | tail -10

# 检查模块是否加载
lsmod | grep fake
```

**预防措施**：
- 理解example-driver是虚拟驱动，不创建设备节点
- 使用 `dmesg` 和 `lsmod` 来验证驱动功能

## 🔍 调试技巧

### 1. 详细日志模式

```bash
# 启用调试输出
export DEBUG=1

# 重新编译
./scripts/driver_helper/build_driver.sh example-driver
```

### 2. 查看构建信息

```bash
# 查看构建信息文件
cat out/driver_artifacts/example-driver/alpha-board/build_info.txt

# 预期输出：
# 驱动构建信息
# ================
# 构建时间: 2026-04-07 19:33:45
# 构建用户: charliechen@hostname
# 内核类型: 主线内核 (linux_mainline)
# 驱动目录: /home/charliechen/imx-forge/driver/example-driver/alpha-board
#
# 产物文件:
#   - fake_driver.ko (10K)
#   - imx6ull-aes-example-driver.dtb (500)
```

### 3. 实时监控日志

```bash
# 在一个终端持续监控日志
watch -n 1 'dmesg | tail -20'

# 在另一个终端操作驱动
insmod fake_driver.ko
rmmod fake_driver
```

### 4. 模块依赖检查

```bash
# 查看模块依赖关系
modprobe --show-depends fake_driver.ko

# 检查符号依赖
nm fake_driver.ko | grep U
```

## 📚 进阶测试

### 测试1：多实例加载

```bash
# 尝试同时加载多个实例
insmod fake_driver.ko test_value=1
insmod fake_driver.ko test_value=2

# 检查结果
lsmod | grep fake
# 应该看到两个fake_driver条目

# 清理
rmmod fake_driver
rmmod fake_driver
```

### 测试2：自动加载测试

```bash
# 复制到系统模块目录
sudo cp fake_driver.ko /lib/modules/$(uname -r)/extra/

# 更新模块依赖
sudo depmod -a

# 使用modprobe加载
sudo modprobe fake_driver test_value=200

# 验证
dmesg | tail -5

# 卸载
sudo modprobe -r fake_driver
```

### 测试3：性能测试

```bash
# 测试加载/卸载速度
time insmod fake_driver.ko
time rmmod fake_driver

# 预期：每次操作应该在毫秒级完成
```

## 🎓 学习要点

通过验证example-driver，你应该掌握：

1. ✅ **驱动编译流程** - 理解交叉编译和内核模块构建
2. ✅ **设备树编译** - 理解DTS到DTB的转换过程
3. ✅ **驱动部署** - 掌握文件传输和部署方法
4. ✅ **模块管理** - 熟练使用insmod/rmmod/modprobe
5. ✅ **日志分析** - 通过dmesg分析驱动行为
6. ✅ **问题排查** - 基本的错误诊断和解决能力

## 🔗 相关文档

- **[系统总览](../driver_helper/overview.md)** - 了解整个基建系统
- **[工作流程](../driver_helper/workflow.md)** - 学习完整的开发流程
- **[错误排查指南](../driver_helper/troubleshooting.md)** - 深入的问题解决方法
- **[构建脚本详解](../driver_helper/build_driver.md)** - build_driver.sh详解
- **[部署脚本详解](../driver_helper/deploy_driver.md)** - deploy_driver.sh详解

## 📞 获取帮助

如果遇到问题：

1. 查看本文档的"常见错误和排查方法"部分
2. 查看日志文件：`out/driver_artifacts/example-driver/alpha-board/build_info.txt`
3. 启用调试模式：`export DEBUG=1`
4. 查看内核日志：`dmesg | grep -i fake`
5. 提问时提供：
   - 使用的完整命令
   - 错误信息
   - 系统环境（内核版本、工具链版本等）

---

**下一步？** → [错误排查指南](../driver_helper/troubleshooting.md) 或 [最佳实践](../driver_helper/best_practices.md)
