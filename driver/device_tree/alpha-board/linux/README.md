# Alpha Board Device Tree（Linux 侧 · 唯一原件）

这里的设备树维护的是——正点原子 2025 年代的 i.MX6ULL 开发板（AES 板），
对应配置是 7 寸 1024x600 的 GT911 触摸 LCD。

## 这个目录是唯一真理源

2026-10 的 v7.2.9 重推之后，**内核侧没有补丁**。本目录下的两个文件就是
板级设备树的唯一原件，`build-linux.sh` 每次构建时把它们拷进内核树并注册
dtb（`copy_board_dts`，幂等）：

| 文件 | 作用 |
|---|---|
| `imx6ull-aes.dts` | 板级入口，引用 SoC dtsi + 本目录的板级 dtsi |
| `imx6ull-aes.dtsi` | 板上全部外设：内存/串口/SD/eMMC/双 FEC/I2C/SPI/音频/显示/CAN/USB/教程节点 |
| `imx6ull_mainline_defconfig.template` | 内核配置模板（含 `${FIRMWARE_DIR}` 占位符，构建时替换） |

改设备树**只改这里**，然后直接跑构建——不存在"同步三处"的问题了
（旧机制是补丁 + 子模块树 + 本目录副本三处手工同步，本目录曾因此漂移过）。

## 内核版本

子模块 `third_party/linux_mainline` 钉在 **v7.2.9**（stable 树 tag，
.gitmodules 的 URL 已指向 stable——7.2.x 稳定点的提交只存在于 stable 树）。
升版本 = bump gitlink + 跑构建，设备树拷贝对版本无感，标签失效会在 dtc
编译时当场报错。

## 已知的等价性破口（记录在案）

QEMU 的 gt911 模型监听 I2C2 **0x5d**（patches/qemu/0008 硬编码），而
真板实测在 **0x14**。本 dts 写 0x5d（QEMU 断言依赖它）；真板验证触摸
用驱动篇 11 章的板级 dts（地址 0x14）。修复要等 QEMU 11.2 rebase
（2026-12 里程碑）。
