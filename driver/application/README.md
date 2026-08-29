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

模拟板经 slirp 内置 TFTP 与宿主共享部署目录（`scripts/driver_helper/driver_helper.conf` 的 `TFTP_DIR`，默认 `~/tftp`）——与真机 netboot 共用同一目录。改完代码重编 `cmake --build build` 后重投 `~/tftp` 即可，秒级迭代。

#### 速查卡（每次验证照抄）

```bash
# ── 宿主：构建产物投递到 ~/tftp ─────────────────────
cmake --build build                                    # Qt/C app
cp build/bin/<name> ~/tftp/                            # 或 make install（驱动 .ko 一并）
# 内核 .ko: scripts/driver_helper/build_driver.sh <name> alpha-board
#           + cp out/driver_artifacts/<name>/alpha-board/*.ko ~/tftp/

# ── 宿主：启动模拟板（改过 QEMU patch 后先 build-qemu.sh）──
scripts/build_helper/build-qemu.sh                     # 仅 QEMU patch 变更后需要
scripts/qemu_helper/run-qemu.sh --display=gtk          # 有 LCD 窗口；去掉 --display 为 headless

# ── guest（root/root 登录后）：TFTP 拉取 + 运行 ─────────
udhcpc -i eth1                                         # 拿 IP（每次启动后一次）
tftp -g -r <文件> 10.0.2.2 && chmod +x <文件>          # 10.0.2.2 = 宿主
insmod <驱动.ko>                                       # 内核模块
./<app>                                                # 应用

# ── lcd_button 一行式（LCD+触摸验证）─────────────────
LANG=C.UTF-8 ./lcd_button -platform linuxfb -plugin evdevtouch:/dev/input/event1 &

# ── 触摸注入（monitor：Ctrl-A C 切入，Ctrl-A C 切回）────
(qemu) gt911_touch 512 300        # 按下
(qemu) gt911_release              # 松开
(qemu) gpio_set gpio0 18 0        # 模拟按键
(qemu) qom-set <QOM路径> <属性> <值>   # 传感器数据注入

# ── 验证断言（无人值守一键体检）──────────────────────
scripts/qemu_helper/e2e-test.sh                        # 15 项外设 PASS/FAIL
```

#### 注意事项

- **改过设备树**（dts/dtsi）后：`scripts/qemu_helper/make-qemu-dtb.sh` 重编 dtb（run-qemu.sh 自动检测也会触发）
- **改过 rootfs 内容**后：直接 `run-qemu.sh`（自动重建 ext4 镜像）
- **改过内核**后：`build-mainline-linux.sh` 重编 zImage（run-qemu.sh 消费 `out/mainline/linux/arch/arm/boot/zImage`）
- lcd_button 的 evdevtouch 插件**必须显式 `-plugin`**（linuxfb 不默认加载，环境变量只传参不加载）

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
