# Example Driver设备树

这个目录包含example-driver设备的设备树文件。

## 文件说明

### imx6ull-aes-example-driver.dts

Example driver的完整设备树文件，用于验证构建工具链。

**特点**：
- 包含完整的include链条
- 可以独立编译成.dtb文件
- 不对应实际硬件，可以安全测试

## 编译方法

### 使用构建脚本（推荐）

```bash
# 编译example-driver驱动和设备树
./scripts/build_driver.sh example-driver alpha-board

# 产物位置
out/driver_artifacts/example-driver/alpha-board/
├── fake_driver.ko                    # 驱动模块
├── imx6ull-aes-example-driver.dtb    # 设备树
└── build_info.txt                    # 构建信息
```

### 手动编译设备树

```bash
# 进入内核源码目录
cd third_party/linux-imx

# 设置架构和交叉编译工具
export ARCH=arm
export CROSS_COMPILE=arm-none-linux-gnueabihf-
export DTB=../../driver/device_tree/alpha-board/framework/imx6ull-aes-framework.dts

# 编译设备树
make dtbs

# 或者使用dtc直接编译
dtc -I dts -O dtb \
    -i arch/arm/boot/dts \
    -i arch/arm/boot/dts/nxp/imx \
    -i ../../driver/device_tree/alpha-board/linux \
    -o ../../out/driver_artifacts/framework/alpha-board/imx6ull-aes-framework.dtb \
    ../../driver/device_tree/alpha-board/framework/imx6ull-aes-framework.dts
```

## Include链条说明

这个设备树文件包含完整的include链条：

```dts
#include "imx6ull.dtsi"                          // SoC基础定义
#include "../../linux/imx6ull-aes.dtsi"          // 主板配置
```

**第一层**: `imx6ull.dtsi`
- 提供i.MX6ULL SoC的基础定义
- 包含CPU、内存、总线等核心硬件

**第二层**: `imx6ull-aes.dtsi`
- 提供alpha-board的硬件配置
- 包含引脚复用、外设配置等

**设备节点**: 在这两层基础上添加设备特定的节点

## 设备树验证

### 检查编译后的.dtb文件

```bash
# 反编译查看内容
dtc -I dtb -O dts -o /tmp/framework.dts \
    out/driver_artifacts/framework/alpha-board/imx6ull-aes-framework.dtb

# 查看fake_device节点
dtc -I dtb -O dts out/driver_artifacts/framework/alpha-board/imx6ull-aes-framework.dtb | \
    grep -A 10 "fake_device"
```

### 在目标系统上验证

```bash
# 检查设备树是否加载
ls /sys/firmware/devicetree/base/ | grep fake

# 查看设备compatible属性
hexdump -C /sys/firmware/devicetree/base/fake_device/compatible

# 检查设备状态
cat /sys/firmware/devicetree/base/fake_device/status
```

## 部署到目标系统

### 方法1: 通过TFTP部署

```bash
# 部署到TFTP目录
./scripts/deploy_driver.sh out/driver_artifacts/framework/alpha-board

# 在U-Boot中加载
tftpboot ${loadaddr} imx6ull-aes-framework.dtb
```

### 方法2: 通过NFS部署

```bash
# 复制到NFS rootfs的boot目录
cp out/driver_artifacts/framework/alpha-board/imx6ull-aes-framework.dtb \
   rootfs/nfs/boot/

# 在目标板上重启
```

### 方法3: 运行时测试（不推荐用于生产）

```bash
# 在运行中的系统上测试设备树
# 注意：这不会实际生效，因为fake设备已经被disabled
```

## 与驱动配合使用

### 1. 加载驱动模块

```bash
# 在目标板上
insmod fake_driver.ko

# 查看日志
dmesg | tail
```

### 2. 验证驱动和设备树匹配

```bash
# 检查驱动是否注册
cat /proc/modules | grep fake

# 检查设备树节点
ls /sys/firmware/devicetree/base/fake_device

# 查看驱动probe日志
dmesg | grep -i fake
```

## 设备树Overlay支持

如果需要动态加载设备树（用于调试），可以创建overlay版本：

```dts
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/";
        __overlay__ {
            fake_device {
                compatible = "imx-fake";
                status = "okay";
            };
        };
    };
};
```

编译overlay：
```bash
dtc -I dts -O dtb -o fake_device.dtbo imx6ull-aes-framework.dtso
```

## 故障排查

### 编译失败

```bash
# 检查include路径是否正确
dtc -I dts -O dtb -o /tmp/test.dtb \
    -i third_party/linux-imx/arch/arm/boot/dts \
    imx6ull-aes-framework.dts

# 查看详细错误信息
dtc -I dts -O dtb -o /tmp/test.dtb imx6ull-aes-framework.dts -v
```

### 设备树未生效

```bash
# 检查设备树是否正确加载
ls /sys/firmware/devicetree/base/

# 检查内核日志
dmesg | grep -i device tree

# 验证设备状态
cat /sys/firmware/devicetree/base/fake_device/status
# 应该输出: disabled
```

## 相关资源

- [设备树规范](https://www.devicetree.org/)
- [i.MX6ULL设备树参考](https://www.nxp.com/docs/en/reference-manual/IMX6ULLRM.pdf)
- 项目设备树: `driver/device_tree/alpha-board/linux/`
- 驱动代码: `driver/framework/alpha-board/`

## 维护者

IMX-Forge Project Team
