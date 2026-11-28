---
title: SD 卡烧录 Bring-up 实测
---

# 2026-06-08 SD Card Flashing Bring-up Note

## Goal

Build a full i.MX6ULL AES SD card image, write it through a host SD card reader, then boot the board from SD.

This flow is intentionally different from the eMMC UUU + UMS flow:

- SD card: write the raw image directly with a card reader.
- eMMC: boot U-Boot through UUU, expose eMMC with UMS, then write the raw image.

## Project Assumptions

Current project convention:

```text
SD:   U-Boot mmc 0, Linux root /dev/mmcblk0p2
eMMC: U-Boot mmc 1, Linux root /dev/mmcblk1p2
```

Generated SD image:

```text
out/release-latest/images/imx6ull-aes-sd.img
```

Generated eMMC image:

```text
out/release-latest/images/imx6ull-aes-emmc.img
```

## Build SD Image

From the project root:

```bash
./scripts/release-all.sh --continue --stage 5 --boot-media sd
```

Equivalent direct image-builder command:

```bash
./scripts/image_builder/build_imx6ull_image.sh --release-dir=out/release-latest --boot-media=sd
```

Expected outputs:

```text
out/release-latest/images/imx6ull-aes-sd.img
out/release-latest/images/imx6ull-aes-sd.img.manifest
out/release-latest/images/imx6ull-aes-sd.img.sha256
```

The manifest should include:

```text
boot_media=sd
uboot_mmc_dev=0
linux_root_dev=/dev/mmcblk0p2
```

## Find Host SD Card Device

Before inserting the SD card:

```bash
lsblk
```

Insert the SD card, then run again:

```bash
lsblk
```

Record the new whole-disk device, for example:

```text
/dev/sdX
```

Do not use a partition path such as `/dev/sdX1` when writing the full image.

## Write SD Image

Replace `/dev/sdX` with the actual whole-disk SD card device:

```bash
sudo dd if=out/release-latest/images/imx6ull-aes-sd.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Alternative GUI tools:

- Rufus: choose DD/raw image mode.
- BalenaEtcher: choose the `.img` file and the SD card device.

## Boot From SD

Insert the SD card into the board and set the board boot mode to SD.

In U-Boot, useful manual checks:

```text
mmc list
mmc dev 0
mmc part
ext4ls mmc 0:1 /
ext4ls mmc 0:2 /
```

If the default environment contains `sdbootaes`, boot with:

```text
run sdbootaes
```

Manual boot fallback:

```text
setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw
ext4load mmc 0:1 ${loadaddr} /zImage
ext4load mmc 0:1 ${fdt_addr} /imx6ull-aes.dtb
bootz ${loadaddr} - ${fdt_addr}
```

## Linux Verification

After Linux boots:

```bash
cat /proc/cmdline
mount | grep ' / '
lsblk
```

Expected root device:

```text
/dev/mmcblk0p2
```

## Pitfall Log

This v1.0.0 baseline did not keep a detailed pitfall record for SD boot. The SD card image boot flow was experimentally verified by repository author CharlieChen114514 on the ALIENTEK Alpha i.MX6ULL board.

Future issues should be appended here using:

```text
Symptom:
Root cause:
Fix:
```
