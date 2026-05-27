# device_tree_try_03 驱动

Device Tree try

## 目录结构

```
driver/device_tree_try_03/
├── alpha-board/
│   ├── device_tree_try_03_driver.c    # 驱动源码
│   ├── Makefile                   # 构建文件
│   └── README.md                  # 本文件
```

## 驱动说明

### device_tree_try_03_driver.c

这是一个由 `template_creator.sh` 生成的Linux内核模块。

**作者**: Charliechen114514
**许可证**: GPL

## 快速开始

### 1. 编译驱动

```bash
# 使用构建脚本（推荐）
./scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board

# 或直接使用 Makefile
cd driver/device_tree_try_03/alpha-board
make
```

预期输出：
```
🔨 编译device_tree_try_03驱动...
✓ 驱动编译完成: out/driver_artifacts/device_tree_try_03/alpha-board/device_tree_try_03_driver.ko
```

### 2. 部署到目标系统

```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh device_tree_try_03 alpha-board

# 或手动复制
cp out/driver_artifacts/device_tree_try_03/alpha-board/device_tree_try_03_driver.ko /path/to/target/lib/modules/
```

### 3. 测试驱动

```bash
# 在目标板上
insmod device_tree_try_03_driver.ko

# 查看日志
dmesg | tail

# 卸载驱动
rmmod device_tree_try_03_driver
```

## 模块参数



### 参数使用示例

```bash
# 传递模块参数
insmod device_tree_try_03_driver.ko param1=value1 param2=value2

# 查看当前参数值
cat /sys/module/device_tree_try_03_driver/parameters/
```

## 开发说明

### 修改驱动

1. 编辑源码文件: `driver/device_tree_try_03/alpha-board/device_tree_try_03_driver.c`
2. 重新编译: `./scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board`
3. 重新部署: `./scripts/driver_helper/deploy_driver.sh device_tree_try_03 alpha-board`

### 内核类型切换

构建时可以指定内核类型：

```bash
# 使用主线内核
./scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board --kernel mainline

# 使用NXP BSP内核
./scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board --kernel imx
```

### 清理构建产物

```bash
# 清理特定驱动
cd driver/device_tree_try_03/alpha-board
make clean

# 或使用构建脚本
./scripts/driver_helper/build_driver.sh --clean device_tree_try_03 alpha-board
```

## 故障排查

### 编译失败

```bash
# 检查内核路径
ls third_party/linux-*/

# 检查交叉编译工具
${CROSS_COMPILE}gcc --version

# 检查内核配置
ls out/*/linux/.config
```

### 模块加载失败

```bash
# 检查内核版本匹配
modinfo device_tree_try_03_driver.ko | grep vermagic
uname -r

# 查看详细错误
dmesg | tail -20
```

## 相关资源

- [Linux内核模块开发指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- 项目构建系统: `scripts/driver_helper/`
- 驱动开发文档: `document/tutorial/driver/`

## 维护者

Charliechen114514

---
*由 `template_creator.sh` 自动生成*
