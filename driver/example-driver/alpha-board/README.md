# Example Driver

这个目录包含用于验证构建工具链的示例驱动和模板。

## 目录结构

```
driver/example-driver/
├── alpha-board/
│   ├── fake_driver.c       # 虚拟驱动示例（不实际驱动硬件）
│   ├── Makefile            # 构建文件
│   └── README.md           # 本文件
```

## 示例驱动说明

### fake_driver.c

这是一个最简单的Linux内核模块，用于验证构建工具链是否正常工作：
- ✅ 交叉编译环境是否正确配置
- ✅ 内核模块构建流程是否正常
- ✅ 部署脚本是否能正确传输文件
- ✅ 驱动加载/卸载流程是否正常工作

**特点**：
- 不访问任何硬件
- 不依赖特定设备树配置
- 只在加载/卸载时打印日志
- 可通过模块参数传递测试值

## 快速验证

### 1. 编译示例驱动

```bash
./scripts/build_driver.sh framework alpha-board
```

预期输出：
```
🔨 编译Framework示例驱动...
✓ 示例驱动编译完成: out/driver_artifacts/framework/alpha-board/fake_driver.ko
```

### 2. 部署到目标系统

```bash
# 方法1: 交互式部署
./scripts/deploy_driver.sh out/driver_artifacts/framework/alpha-board

# 方法2: 直接复制到NFS rootfs
cp out/driver_artifacts/framework/alpha-board/fake_driver.ko rootfs/nfs/lib/modules/
```

### 3. 测试驱动加载

```bash
# 在目标板上
insmod fake_driver.ko

# 查看日志
dmesg | tail

# 卸载驱动
rmmod fake_driver
```

预期日志输出：
```
=== Fake驱动加载成功 ===
测试参数值: 42
这是一个验证构建工具链的虚拟驱动
不实际驱动任何硬件
========================
```

### 4. 传递模块参数

```bash
insmod fake_driver.ko test_value=123
dmesg | grep "测试参数值"
# 应该显示: 测试参数值: 123
```

## 工具链验证清单

使用这个示例驱动可以验证：

- [ ] **交叉编译**: `make` 能否成功生成.ko文件
- [ ] **产物输出**: .ko文件是否在正确位置 (`out/driver_artifacts/framework/alpha-board/`)
- [ ] **部署脚本**: 部署工具能否正确传输文件
- [ ] **模块加载**: insmod能否成功加载模块
- [ ] **日志输出**: dmesg能否看到驱动日志
- [ ] **模块参数**: 模块参数能否正确传递
- [ ] **模块卸载**: rmmod能否成功卸载模块

如果以上所有验证都通过，说明构建工具链工作正常！

## 设备树说明

这个驱动使用独立的设备树文件，位于：
```
driver/device_tree/alpha-board/framework/imx6ull-aes-framework.dts
```

该设备树文件包含完整的include链条，可以独立编译。详细说明请参考设备树目录下的README。

## 创建真实驱动

当工具链验证通过后，可以基于这个示例创建真实驱动：

1. **复制模板**
   ```bash
   mkdir -p driver/my_device/alpha-board
   cp -r driver/framework/alpha-board/* driver/my_device/alpha-board/
   cd driver/my_device/alpha-board
   ```

2. **修改驱动代码**
   - 将 `fake_driver.c` 重命名为你的驱动名
   - 添加实际的硬件操作代码
   - 实现需要的驱动接口

3. **修改Makefile**
   - 更新 `obj-m` 为你的模块名
   - 更新输出目录路径

4. **添加设备树**
   - 创建设备树目录 `driver/device_tree/alpha-board/my_device/`
   - 创建 `imx6ull-aes-my_device.dts` 文件
   - 参考framework设备的设备树示例

## 故障排查

### 编译失败

```bash
# 检查内核路径
echo $KDIR
# 应该指向: third_party/linux_mainline

# 检查交叉编译工具
arm-none-linux-gnueabihf-gcc --version
```

### 模块加载失败

```bash
# 检查内核版本匹配
modinfo fake_driver.ko | grep vermagic
uname -r

# 查看详细错误
dmesg | tail -20
```

## 相关资源

- [Linux内核模块开发指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- [设备树规范](https://www.devicetree.org/)
- 项目构建系统: `scripts/build_helper/`

## 维护者

IMX-Forge Project Team
