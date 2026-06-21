# 21_tutorial_icm20608_spi 驱动

ICM-20608 六轴 IMU（三轴陀螺仪 + 三轴加速度计 + 温度）的 SPI 驱动，采用 6.12 / 7.1 现代 SPI API。

## 目录结构

```
driver/21_tutorial_icm20608_spi/
├── alpha-board/
│   ├── 21_tutorial_icm20608_spi_driver_main.c   # 驱动主体（spi_driver + 字符设备）
│   ├── icm20608_hw.c                            # 硬件层（寄存器读写 / 数据读取 / 上电）
│   ├── icm20608_hw.h                            # 硬件层接口
│   ├── icm20608reg.h                            # ICM-20608 寄存器地址定义
│   ├── Makefile                                 # 构建文件
│   └── README.md                                # 本文件
```

## 驱动说明

### 21_tutorial_icm20608_spi_driver_main.c

ICM-20608 六轴 IMU 的 SPI 设备驱动，采用 6.12 / 7.1 现代 SPI API：
`module_spi_driver()` + 单参数 `probe` + `void remove` + 单参数 `class_create`，
通过 `spi_write_then_read` / `spi_write` 完成寄存器读写（地址 bit7 区分读/写），
对外暴露 `/dev/icm20608`。

代码组织沿用仓库惯例（参见 `05_tutorial_pinctrl_gpio` / `16_tutorial_platform_led`）：
驱动主体（总线 + 字符设备）与芯片硬件层分离，寄存器地址集中在 `icm20608reg.h`，
避免魔术数字散落代码各处。

**作者**: Charliechen114514
**许可证**: GPL

## 快速开始

### 1. 编译驱动

```bash
# 使用构建脚本（推荐）
./scripts/driver_helper/build_driver.sh 21_tutorial_icm20608_spi alpha-board

# 或直接使用 Makefile
cd driver/21_tutorial_icm20608_spi/alpha-board
make
```

预期输出：
```
🔨 编译21_tutorial_icm20608_spi驱动...
✓ 驱动编译完成: out/driver_artifacts/21_tutorial_icm20608_spi/alpha-board/21_tutorial_icm20608_spi_driver.ko
```

### 2. 部署到目标系统

```bash
# 交互式部署
./scripts/driver_helper/deploy_driver.sh 21_tutorial_icm20608_spi alpha-board

# 或手动复制
cp out/driver_artifacts/21_tutorial_icm20608_spi/alpha-board/21_tutorial_icm20608_spi_driver.ko /path/to/target/lib/modules/
```

### 3. 测试驱动

```bash
# 在目标板上
insmod 21_tutorial_icm20608_spi_driver.ko

# 查看日志
dmesg | tail

# 卸载驱动
rmmod 21_tutorial_icm20608_spi_driver
```

## 设备树与数据格式

本驱动没有模块参数，靠设备树匹配。设备树节点放在每章独立的 dts 里（不要直接改共享的
`imx6ull-aes.dtsi`，它会被工作流覆盖回去）：

- [`driver/device_tree/alpha-board/21_tutorial_icm20608_spi/imx6ull-aes-21_tutorial_icm20608_spi.dts`](../../../device_tree/alpha-board/21_tutorial_icm20608_spi/imx6ull-aes-21_tutorial_icm20608_spi.dts)

这个 dts 做了三件事：在 `&iomuxc` 里加 `pinctrl_ecspi3`（CS 走 `GPIO1_IO20`，其余三根线复用
ECSPI3），把 `&ecspi3` 唤醒并配 `cs-gpios`，再挂上 `icm20608@0`（`compatible = "imxaes,icm20608"`、
`spi-max-frequency = <8000000>`、`reg = <0>`）。

⚠️ ECSPI3 复用的是 UART2 那四个引脚，而 base dtsi 里 `&uart2` 是开启的、还挂着蓝牙，会和
ECSPI3 抢 UART2_TX/RX 两个引脚。所以这个 dts 顺手把 `&uart2` 关掉（`status = "disabled"`）腾出
引脚——alpha 板上没有那颗蓝牙芯片，关了无损；若你的板子真在用 UART2 蓝牙，就得换一组 ECSPI3
引脚。完整设备树说明见配套教程 `05_device_tree.md`。

配套测试程序（每次 `read` 拿一组七路原始值，按量程灵敏度换算成物理量后循环打印）：

- [`driver/application/icm20608/`](../../../application/icm20608/)

用户空间 `read(/dev/icm20608)` 每次返回 7 个 `signed int` 原始 ADC 值（顺序如下），
测试程序按量程灵敏度换算成物理量：

| 索引 | 含义         |
| ---- | ------------ |
| 0~2  | 陀螺仪 x/y/z |
| 3~5  | 加速度 x/y/z |
| 6    | 温度         |

## 开发说明

### 修改驱动

1. 编辑源码文件: `driver/21_tutorial_icm20608_spi/alpha-board/21_tutorial_icm20608_spi_driver_main.c`
2. 重新编译: `./scripts/driver_helper/build_driver.sh 21_tutorial_icm20608_spi alpha-board`
3. 重新部署: `./scripts/driver_helper/deploy_driver.sh 21_tutorial_icm20608_spi alpha-board`

### 内核类型切换

构建时可以指定内核类型：

```bash
# 使用主线内核
./scripts/driver_helper/build_driver.sh 21_tutorial_icm20608_spi alpha-board --kernel mainline

# 使用NXP BSP内核
./scripts/driver_helper/build_driver.sh 21_tutorial_icm20608_spi alpha-board --kernel imx
```

### 清理构建产物

```bash
# 清理特定驱动
cd driver/21_tutorial_icm20608_spi/alpha-board
make clean

# 或使用构建脚本
./scripts/driver_helper/build_driver.sh --clean 21_tutorial_icm20608_spi alpha-board
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
modinfo 21_tutorial_icm20608_spi_driver.ko | grep vermagic
uname -r

# 查看详细错误
dmesg | tail -20
```

## 相关资源

- [Linux内核模块开发指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- 项目构建系统: `scripts/driver_helper/`
- 配套教程: [document/tutorial/driver/09_spi_icm20608_driver/](../../../document/tutorial/driver/09_spi_icm20608_driver/)

## 维护者

Charliechen114514
