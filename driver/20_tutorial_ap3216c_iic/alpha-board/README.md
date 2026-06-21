# 20_tutorial_ap3216c_iic 驱动

AP3216C 三合一传感器（IR / ALS / PS）的 I2C 驱动，采用 6.12 / 7.1 现代 I2C API。

## 目录结构

```
driver/20_tutorial_ap3216c_iic/
├── alpha-board/
│   ├── 20_tutorial_ap3216c_iic_driver_main.c   # 驱动主体（i2c_driver + 字符设备）
│   ├── ap3216c_hw.c                            # 硬件层（寄存器读写 / 数据读取 / 上电）
│   ├── ap3216c_hw.h                            # 硬件层接口
│   ├── ap3216creg.h                            # AP3216C 寄存器地址定义
│   ├── Makefile                                # 构建文件
│   └── README.md                               # 本文件
```

## 驱动说明

### 20_tutorial_ap3216c_iic_driver_main.c

AP3216C 三合一传感器（IR / ALS / PS）的 I2C 设备驱动，采用 6.12 / 7.1 现代 I2C API：
`module_i2c_driver()` + 单参数 `probe` + `void remove` + 单参数 `class_create`，
通过 `i2c_smbus_*` 完成寄存器读写，对外暴露 `/dev/ap3216c`。

代码组织沿用仓库惯例（参见 `05_tutorial_pinctrl_gpio` / `16_tutorial_platform_led`）：
驱动主体（总线 + 字符设备）与芯片硬件层分离，寄存器地址集中在 `ap3216creg.h`，
避免魔术数字散落代码各处。

**作者**: Charliechen114514
**许可证**: GPL

## 快速开始

### 1. 编译驱动

```bash
# 使用构建脚本（推荐）
./scripts/driver_helper/build_driver.sh 20_tutorial_ap3216c_iic alpha-board

# 或直接使用 Makefile
cd driver/20_tutorial_ap3216c_iic/alpha-board
make
```

预期输出：
```
🔨 编译20_tutorial_ap3216c_iic驱动...
✓ 驱动编译完成: out/driver_artifacts/20_tutorial_ap3216c_iic/alpha-board/20_tutorial_ap3216c_iic_driver.ko
```

### 2. 部署到目标系统

```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh 20_tutorial_ap3216c_iic alpha-board

# 或手动复制
cp out/driver_artifacts/20_tutorial_ap3216c_iic/alpha-board/20_tutorial_ap3216c_iic_driver.ko /path/to/target/lib/modules/
```

### 3. 测试驱动

```bash
# 在目标板上
insmod 20_tutorial_ap3216c_iic_driver.ko

# 查看日志
dmesg | tail

# 卸载驱动
rmmod 20_tutorial_ap3216c_iic_driver
```

## 设备树与数据格式

本驱动没有模块参数，靠设备树匹配。设备树节点放在每章独立的 dts 里（不要直接改共享的
`imx6ull-aes.dtsi`，它会被工作流覆盖回去）：

- [`driver/device_tree/alpha-board/20_tutorial_ap3216c_iic/imx6ull-aes-20_tutorial_ap3216c_iic.dts`](../../../device_tree/alpha-board/20_tutorial_ap3216c_iic/imx6ull-aes-20_tutorial_ap3216c_iic.dts)

这个 dts include 了 base dtsi 后，给 `&i2c1` 挂上 `ap3216c@1e`（`compatible = "imxaes,ap3216c"`、
`reg = <0x1e>`）。注意 base 的 `&i2c1` 里还挂着 NXP EVK 的 mag3110/fxls8471，其中 **fxls8471 的地址
就是 0x1e，和 AP3216C 撞车**——它在 base 里没 label，所以这个 dts 用 `/delete-node/ &{/...}` 按完整
路径把它删掉；I2C1 的引脚复用 base 已配好，无需改动。完整设备树说明见配套教程 `05_device_tree.md`。

配套测试程序（每次 `read` 拿一组 `{ir, als, ps}` 循环打印）：

- [`driver/application/ap3216c/`](../../../application/ap3216c/)

用户空间 `read(/dev/ap3216c)` 每次返回 3 个 `unsigned short`，顺序为：

| 索引 | 含义 |
| ---- | ---- |
| 0    | IR   |
| 1    | ALS  |
| 2    | PS   |

## 开发说明

### 修改驱动

1. 编辑源码文件: `driver/20_tutorial_ap3216c_iic/alpha-board/20_tutorial_ap3216c_iic_driver_main.c`
2. 重新编译: `./scripts/driver_helper/build_driver.sh 20_tutorial_ap3216c_iic alpha-board`
3. 重新部署: `./scripts/driver_helper/deploy_driver.sh 20_tutorial_ap3216c_iic alpha-board`

### 内核类型切换

构建时可以指定内核类型：

```bash
# 使用主线内核
./scripts/driver_helper/build_driver.sh 20_tutorial_ap3216c_iic alpha-board --kernel mainline

# 使用NXP BSP内核
./scripts/driver_helper/build_driver.sh 20_tutorial_ap3216c_iic alpha-board --kernel imx
```

### 清理构建产物

```bash
# 清理特定驱动
cd driver/20_tutorial_ap3216c_iic/alpha-board
make clean

# 或使用构建脚本
./scripts/driver_helper/build_driver.sh --clean 20_tutorial_ap3216c_iic alpha-board
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
modinfo 20_tutorial_ap3216c_iic_driver.ko | grep vermagic
uname -r

# 查看详细错误
dmesg | tail -20
```

## 相关资源

- [Linux内核模块开发指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- 项目构建系统: `scripts/driver_helper/`
- 配套教程: [document/tutorial/driver/08_i2c_ap3216c_driver/](../../../document/tutorial/driver/08_i2c_ap3216c_driver/)

## 维护者

Charliechen114514
