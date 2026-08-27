# Driver Applications

驱动应用层程序目录，用于构建和部署 i.MX6ULL 目标板的应用程序。

**默认构建目标**: ARM 交叉编译（i.MX6ULL）

## 快速开始

### 1. ARM 交叉编译（默认）

```bash
cd driver/application
mkdir build && cd build
cmake ..
cmake --build . -j$(nproc)
```

生成的二进制文件位于 `build/bin/` 目录。

### 2. 部署到 QEMU 模拟板（无板开发）

模拟板经 slirp 内置 TFTP 与宿主共享部署目录（`scripts/driver_helper/driver_helper.conf` 的 `TFTP_DIR`，默认 `~/tftp`）——与真机 netboot 共用同一目录：

```bash
cp build/bin/icm20608_app ~/tftp/
cp ../..//out/driver_artifacts/21_tutorial_icm20608_spi/alpha-board/*.ko ~/tftp/

scripts/qemu_helper/run-qemu.sh        # 启动模拟板，root/root 登录
# guest 内：
#   udhcpc -i eth1
#   tftp -g -r 21_tutorial_icm20608_spi_driver.ko 10.0.2.2 && insmod 21_tutorial_icm20608_spi_driver.ko
#   tftp -g -r icm20608_app 10.0.2.2 && chmod +x icm20608_app && ./icm20608_app
```

改完代码重编 `cmake --build build` 后重投 `~/tftp` 即可，秒级迭代。

### 2. 部署到 rootfs

```bash
# 部署到指定 rootfs 目录
cmake --install build --prefix /path/to/rootfs
```

## 构建选项

### 选择性构建

只构建特定的应用：

```bash
cmake -DBUILD_APPS=app1,app2 ..
```

示例：
```bash
# 只构建 chardev_led_control
cmake -DBUILD_APPS=chardev_led_control ..
```

### 本机构建（主机测试）

用于开发调试，生成 x86-64 可执行文件：

```bash
cmake -DHOST_TEST=ON ..
cmake --build .
```

## 添加新应用

1. 在 `driver/application/` 下创建新的子目录
2. 在子目录中创建 `CMakeLists.txt` 和源文件
3. 顶层 CMake 会自动发现并构建新应用

示例应用目录结构：
```
my_new_app/
├── CMakeLists.txt
└── main.c
```

示例 `CMakeLists.txt`：
```cmake
cmake_minimum_required(VERSION 3.16)

project(my_new_app VERSION 0.1.0 LANGUAGES C)

add_executable(${PROJECT_NAME} main.c)
```

## 工具链要求

- **目标平台**: NXP i.MX6ULL (ARM Cortex-A7, ARMv7-A)
- **工具链**: Arm GNU Toolchain 15.2.rel1 (arm-none-linux-gnueabihf)
- **工具链路径**: 需在 PATH 中可用（如 `/opt/arm-gnu-toolchain/bin`）

验证工具链：
```bash
arm-none-linux-gnueabihf-gcc -v
```

## 验证构建

检查生成的二进制文件架构：
```bash
file build/bin/<app_name>
```

预期输出（ARM 交叉编译，默认）：
```
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV)
```

预期输出（本机编译，HOST_TEST=ON）：
```
ELF 64-bit LSB pie executable, x86-64
```
