# 2026-06-08 UUU + UMS + eMMC Bring-up Note

## Goal

Bring up the i.MX6ULL AES board through USB SDP, expose eMMC through UMS, burn a full eMMC image, then boot either:

- `run netbootaes`: TFTP kernel/DTB + NFS rootfs.
- `run emmcbootaes`: eMMC boot partition kernel/DTB + eMMC rootfs.

## Conversation Summary

1. Initial plan was to avoid unstable fastboot flashing.
2. UUU should only boot U-Boot into RAM through USB SDP.
3. U-Boot should expose eMMC through UMS.
4. The host should not copy only `zImage`/DTB to a mounted drive letter for production flashing, because that can miss raw U-Boot, partition table, or rootfs.
5. Correct full burn flow: use Rufus/DD/raw-image mode to write `out/release-latest/images/imx6ull-aes-emmc.img` to the UMS-exposed eMMC.
6. First UUU lst failed because it referenced `u-boot-dtb.imx` relative to `tools/uuu/`.
7. Fixed lst to load `../../out/release-latest/uboot/u-boot-dtb.imx`.
8. U-Boot then entered old `bootcmd_mfg`, which fell through to `fastboot 0`.
9. Fixed board default manufacturing environment so USB/mfgtools boot runs UMS instead of fastboot.
10. Updated both U-Boot source and `patches/uboot-imx/charlies_board.patch`.
11. Rebuilt U-Boot at `out/release-latest/uboot/u-boot-dtb.imx`.
12. Verified the new U-Boot image contains:

```text
bootcmd_mfg=echo Run eMMC UMS ...; mmc dev ${emmc_dev}; ums 0 mmc ${emmc_dev};
```

## Files Changed

- `tools/uuu/imx6ull-aes-ums.lst`
- `tools/uuu/README.md`
- `third_party/uboot-imx/include/configs/mx6ull_aes_emmc.h`
- `patches/uboot-imx/charlies_board.patch`

## Current U-Boot Environment Snapshot

The board currently reports:

```text
baudrate=115200
bootcmd=echo Current do not autoboot
bootcmd_mfg=mmc dev 1; ums 0 mmc 1
bootdelay=-1
emmc_dev=1
ethact=ethernet@20b4000
ethprime=eth1
loadaddr=0x80800000
```

The environment is minimal and needs normal boot variables.

## Host-side Assumptions

TFTP directory:

```text
~/tftp
```

Files expected in TFTP:

```text
zImage
imx6ull-aes.dtb
```

NFS rootfs:

```text
/home/charliechen/imx-forge/rootfs/nfs
```

Common tutorial network values:

```text
board ipaddr = 192.168.60.200
serverip     = 192.168.60.1
netmask      = 255.255.255.0
gatewayip    = 192.168.60.1
```

## Host Preparation

Copy TFTP files:

```bash
mkdir -p ~/tftp
cp out/release-latest/images/zImage ~/tftp/
cp out/release-latest/images/imx6ull-aes.dtb ~/tftp/
chmod a+r ~/tftp/zImage ~/tftp/imx6ull-aes.dtb
```

Historical kernel NFS server `/etc/exports` entry:

```text
/home/charliechen/imx-forge/rootfs/nfs 192.168.60.0/24(rw,sync,no_subtree_check,no_root_squash)
```

Reload kernel NFS exports:

```bash
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

Note: on the newer WSL2 setup, kernel `nfs-kernel-server` hung on local NFSv3 mounts. Use NFS-Ganesha instead and pin `mountport=20048`. See:

```text
document/notes/2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md
```

## U-Boot Environment: Quick Paste Block

Paste this in U-Boot, adjusting IP values if the host network differs:

```text
setenv ipaddr 192.168.60.200
setenv serverip 192.168.60.1
setenv gatewayip 192.168.60.1
setenv netmask 255.255.255.0
setenv hostname imx6ull-aes
setenv nfs_iface eth0
setenv loadaddr 0x80800000
setenv fdt_addr 0x83000000
setenv fdt_addr_r 0x83000000
setenv bootfile zImage
setenv fdt_file imx6ull-aes.dtb
setenv nfsrootdir /home/charliechen/imx-forge/rootfs/nfs
setenv nfsargs 'setenv bootargs console=ttymxc0,115200 root=/dev/nfs rw nfsroot=${serverip}:${nfsrootdir},vers=3,proto=tcp,nolock,port=2049,mountport=20048 ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}:${nfs_iface}:off'
setenv netbootaes 'run nfsargs; tftp ${loadaddr} ${bootfile}; tftp ${fdt_addr} ${fdt_file}; bootz ${loadaddr} - ${fdt_addr}'
setenv emmcargs 'setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk1p2 rootfstype=ext4 rootwait rw'
setenv emmcdevsetup 'mmc dev ${emmc_dev}'
setenv loademmcimage 'ext4load mmc ${emmc_dev}:1 ${loadaddr} /zImage'
setenv loademmcfdt 'ext4load mmc ${emmc_dev}:1 ${fdt_addr} /imx6ull-aes.dtb'
setenv emmcbootaes 'run emmcargs; run emmcdevsetup; run loademmcimage; run loademmcfdt; bootz ${loadaddr} - ${fdt_addr}'
setenv bootcmd 'run emmcbootaes'
setenv bootdelay 1
saveenv
```

Manual test commands:

```text
run netbootaes
run emmcbootaes
```

If eMMC rootfs fails with `VFS: Cannot open root device`, try:

```text
setenv emmcargs 'setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw'
run emmcbootaes
```

## Current Caveat

`out/release-latest/images/imx6ull-aes-emmc.img` must be regenerated after U-Boot changes if the image should contain the latest eMMC-resident U-Boot. The temporary UUU U-Boot only runs from RAM.
