# Changelog

## v1.0.0 - 轻量首版

IMX-Forge v1.0.0 是首个轻量可用版本，目标是让正点原子阿尔法 i.MX6ULL 开发板完成从开发环境到系统启动的主线闭环。

### 已验证闭环

- Docker/WSL2 开发环境入口与一键 release 构建流程。
- U-Boot、Linux Kernel、BusyBox、RootFS 与完整镜像装配。
- SD 卡镜像 `imx6ull-aes-sd.img`：`mmc 0`，`root=/dev/mmcblk0p2`。
- eMMC 镜像 `imx6ull-aes-emmc.img`：`mmc 1`，`root=/dev/mmcblk1p2`。
- SD 卡启动与 UUU + UMS eMMC 启动已由仓库主作者 CharlieChen114514 在正点原子阿尔法 i.MX6ULL 开发板上实验通过。

### 本地可生成产物

- `out/release-latest/uboot/u-boot-dtb.imx`
- `out/release-latest/linux/arch/arm/boot/zImage`
- `out/release-latest/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb`
- `out/release-latest/rootfs/`
- `out/release-latest/images/imx6ull-aes-emmc.img`
- `out/release-latest/images/imx6ull-aes-sd.img`
- 对应 `.manifest` 与 `.sha256` 文件

这些产物由用户本地构建生成，v1.0.0 不随 GitHub Release 交付官方 SD/eMMC binary 镜像。

### 已知限制

- 当前正式支持正点原子阿尔法 i.MX6ULL 开发板。
- 其他 i.MX6ULL 板卡需要自行调整设备树、U-Boot 配置和启动参数。
- v1.0.0 不承诺所有进阶教程、示例项目和多板卡生态完结。

### 后续计划

- 继续扩展驱动教程和应用示例。
- 完善 GitHub Release 自动化与发布 checklist。
- 增加更多板卡适配和回归记录。
