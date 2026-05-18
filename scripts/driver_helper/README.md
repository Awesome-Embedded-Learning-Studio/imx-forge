# Driver Helper Scripts

驱动开发辅助工具集，提供完整的驱动开发、构建、审查和部署流程。

## 📋 脚本清单

### 1. build_driver.sh - 驱动构建脚本
统一的驱动构建入口，支持单个或批量构建驱动模块和设备树。

**功能：**
- 列出所有可用驱动
- 构建指定驱动的模块和设备树
- 批量构建所有驱动
- 按板卡过滤构建
- 支持双内核切换 (mainline/imx)
- 清理构建产物

**用法：**
```bash
# 列出所有驱动
./scripts/driver_helper/build_driver.sh --list

# 构建指定驱动
./scripts/driver_helper/build_driver.sh example-driver alpha-board

# 使用imx内核构建
./scripts/driver_helper/build_driver.sh example-driver --kernel=imx

# 构建所有驱动
./scripts/driver_helper/build_driver.sh --all

# 清理产物
./scripts/driver_helper/build_driver.sh --clean example-driver
./scripts/driver_helper/build_driver.sh --clean --all
```

### 2. deploy_driver.sh - 驱动部署脚本
简化的驱动部署工具，直接复制驱动产物到目标位置。

**功能：**
- TFTP服务器部署
- NFS rootfs部署
- 本地目录复制
- 远程服务器SSH传输

**用法：**
```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board

# 直接部署到TFTP
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=tftp

# 部署到NFS rootfs
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=nfs

# 部署到本地目录
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=local --local-dir=/tmp/drivers

# 部署到远程服务器
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board --target=remote --remote=root@192.168.1.100 --remote-path=/lib/modules
```

### 3. review_driver.sh - 产物审查脚本
驱动构建产物的完整性审查和验证工具。

**功能：**
- 审查驱动模块完整性和正确性
- 检查设备树格式和节点
- 验证符号表和依赖关系
- 显示代码段和符号信息
- 确认产物可以安全部署

**用法：**
```bash
# 审查example-driver
./scripts/driver_helper/review_driver.sh example-driver

# 审查指定板卡
./scripts/driver_helper/review_driver.sh example-driver alpha-board
```

**输出内容：**
- 📦 文件信息 (大小、类型、格式)
- 📋 模块信息 (版本、描述、作者、vermagic)
- 🔍 ELF头信息 (架构验证)
- 📊 代码段分析 (text/data/bss)
- 🎯 关键符号检查 (init/exit函数)
- 🔗 依赖关系检查
- ⚙️ 模块参数列表
- 🌳 设备树格式验证

### 4. show_device_tree.sh - 设备树显示脚本
设备树节点美化显示和预览工具。

**功能：**
- 美化显示设备树节点结构
- 高亮显示节点和属性
- 显示compatible属性
- 搜索节点和属性
- 详细统计信息

**用法：**
```bash
# 基本显示
./scripts/driver_helper/show_device_tree.sh example.dtb

# 显示完整DTS内容
./scripts/driver_helper/show_device_tree.sh example.dtb --all

# 显示详细信息
./scripts/driver_helper/show_device_tree.sh example.dtb --detailed

# 搜索节点
./scripts/driver_helper/show_device_tree.sh example.dtb --search "compatible"
```

## 🔄 完整工作流程

```bash
# 1. 构建驱动
./scripts/driver_helper/build_driver.sh example-driver --kernel=imx

# 2. 审查产物
./scripts/driver_helper/review_driver.sh example-driver

# 3. 预览设备树
./scripts/driver_helper/show_device_tree.sh \
  out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb

# 4. 部署到目标系统
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/example-driver/alpha-board
```

## 📁 目录结构

```
scripts/
├── driver_helper/
│   ├── build_driver.sh       # 驱动构建脚本
│   ├── deploy_driver.sh      # 驱动部署脚本
│   ├── review_driver.sh      # 产物审查脚本
│   ├── show_device_tree.sh   # 设备树显示脚本
│   └── README.md             # 本文件
└── lib/
    └── driver_buildlib.sh    # 共享构建库
```

## ⚙️ 配置

所有脚本使用统一的配置：
- **项目根目录**: 自动检测
- **交叉编译工具**: `arm-none-linux-gnueabihf-`
- **架构**: ARM
- **默认内核**: mainline (可通过 `--kernel=imx` 切换)。这是驱动教程和新内核验证链路的默认值；系统完整构建仍以 NXP BSP 作为默认轨道。

## 🎯 特性

- **统一接口**: 所有脚本使用一致的参数格式
- **彩色输出**: 易于阅读和识别
- **错误检查**: 完整的验证和错误提示
- **模块化设计**: 共享构建库，代码复用
- **灵活性**: 支持多种配置和部署方式

## 📝 产物位置

所有构建产物统一输出到：
```
out/driver_artifacts/<驱动>/<板卡>/
├── <driver>.ko              # 驱动模块
├── <board>.dtb              # 设备树
└── build_info.txt          # 构建信息
```

## 🔧 依赖

- `dtc` - 设备树编译器
- `arm-none-linux-gnueabihf-gcc` - ARM交叉编译器
- 内核源码 (third_party/linux-imx 或 linux_mainline)

## 📚 相关文档

- [Linux内核模块开发指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- [设备树规范](https://www.devicetree.org/)
- 项目主目录: [../../README.md](../../README.md)

## 🚀 快速开始

```bash
# 1. 列出可用驱动
./scripts/driver_helper/build_driver.sh --list

# 2. 构建示例驱动
./scripts/driver_helper/build_driver.sh example-driver --kernel=imx

# 3. 审查构建产物
./scripts/driver_helper/review_driver.sh example-driver

# 4. 预览设备树
./scripts/driver_helper/show_device_tree.sh \
  out/driver_artifacts/example-driver/alpha-board/*.dtb --detailed

# 5. 部署到板子
./scripts/driver_helper/deploy_driver.sh \
  out/driver_artifacts/example-driver/alpha-board
```

## 💡 提示

1. **构建前检查**: 脚本会自动检查内核是否已编译
2. **产物审查**: 每次构建后建议运行 `review_driver.sh` 验证
3. **设备树预览**: 部署前使用 `show_device_tree.sh` 查看节点
4. **清理产物**: 使用 `--clean` 选项清理旧的构建产物
5. **错误输出**: 所有脚本都显示详细错误信息，方便调试

## 🛠️ 故障排查

### 内核未编译
```bash
# 完整编译内核
cd third_party/linux-imx
make O=../../out/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)

# 或快速准备（仅编译必要文件）
make O=../../out/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
```

### 设备树编译失败
- 检查dtc是否安装: `sudo apt-get install device-tree-compiler`
- 确认设备树文件格式正确

### 部署失败
- 检查网络连接
- 确认目标服务器配置正确
- 验证SSH密钥配置

## 📞 支持

如有问题，请查看：
- 项目主目录的 README.md
- 构建日志输出
- 使用 `--help` 选项查看脚本帮助

---

**IMX-Forge Project Team**
