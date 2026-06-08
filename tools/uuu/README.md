# i.MX6ULL AES UUU + UMS

这个目录只保留最小 UUU 流程：用 USB SDP 把 U-Boot 临时下载到 RAM 里运行。U-Boot 检测到 USB/mfgtools 启动后，会通过板级 `bootcmd_mfg` 自动暴露 eMMC 为 UMS。

从项目根目录运行：

```bash
sudo uuu tools/uuu/imx6ull-aes-ums.lst
```

当前 lst 会加载：

```text
out/release-latest/uboot/u-boot-dtb.imx
```

生成 eMMC 整盘镜像：

```bash
./scripts/image_builder/build_imx6ull_image.sh --boot-media=emmc
```

U-Boot 的板级制造模式环境会执行：

```text
mmc dev 1
ums 0 mmc 1
```

UMS 出来以后，主机系统会看到整块 eMMC 盘。不要只往弹出来的盘符里复制内核和设备树；这样容易遗漏 U-Boot raw 区域、分区表或 rootfs。

正确流程是使用 Rufus 之类的 raw image 写盘工具，把已经制作好的整盘镜像烧进 UMS 暴露出来的 eMMC：

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

Rufus 操作要点：

1. 选择 UMS 暴露出来的 eMMC 设备。
2. 选择 `imx6ull-aes-emmc.img`。
3. 使用 DD/raw image 写入模式。
4. 写入完成后安全弹出磁盘，再断电切回 eMMC 启动。

这个镜像已经包含：

```text
U-Boot raw offset: 1 KiB
boot partition:    zImage 和 imx6ull-aes.dtb
rootfs partition:  rootfs
```

说明：UUU 这一步只是在 RAM 中临时启动 U-Boot 并进入 UMS；真正永久写入 eMMC 的动作由 Rufus 写入整盘镜像完成。
