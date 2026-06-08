# SD卡蔟笔者直接设置的

setenv sd_dev 0
setenv fdt_addr 0x83000000
setenv fdt_addr_r 0x83000000
setenv sdargs 'setenv bootargs console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw'
setenv loadsdimage 'ext4load mmc ${sd_dev}:1 ${loadaddr} /zImage'
setenv loadsdfdt 'ext4load mmc ${sd_dev}:1 ${fdt_addr} /imx6ull-aes.dtb'
setenv sdbootaes 'echo Booting AES from SD ...; run sdargs; mmc dev ${sd_dev}; run loadsdimage; run loadsdfdt; bootz ${loadaddr} - ${fdt_addr}'
run sdbootaes

# TFTP和NFS启动笔者设置的
setenv ipaddr 192.168.60.200
setenv serverip 192.168.60.1
setenv gatewayip 192.168.60.1
setenv netmask 255.255.255.0
setenv loadaddr 0x80800000
setenv fdt_addr 0x83000000
setenv bootfile zImage
setenv fdt_file imx6ull-aes.dtb
setenv nfsrootdir /home/charliechen/imx-forge/rootfs/nfs
setenv nfsargs 'setenv bootargs console=ttymxc0,115200 root=/dev/nfs rw nfsroot=${serverip}:${nfsrootdir},vers=3,proto=tcp,nolock,port=2049,mountport=20048 ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}:${nfs_iface}:off'
setenv netbootaes 'run nfsargs; tftp ${loadaddr} ${bootfile}; tftp ${fdt_addr} ${fdt_file}; bootz ${loadaddr} - ${fdt_addr}'
setenv bootcmd 'run netbootaes'
setenv bootdelay 1
saveenv
