---
title: WSL2 NFS Rootfs 排查
---

# 2026-06-08 WSL2 NFS Rootfs Troubleshooting Note

## Symptom

The i.MX6ULL board booted a new Linux 7.0 kernel with NFS rootfs bootargs:

```text
console=ttymxc0,115200 root=/dev/nfs rw nfsroot=192.168.60.1:/home/charliechen/imx-forge/rootfs/nfs,v3,tcp ip=192.168.60.200:192.168.60.1:192.168.60.1:255.255.255.0::eth0:off
```

The kernel brought up Ethernet and completed static IP configuration:

```text
fec 20b4000.ethernet eth0: Link is Up - 100Mbps/Full - flow control rx/tx
IP-Config: Complete:
     device=eth0, hwaddr=b8:ae:1d:01:00:04, ipaddr=192.168.60.200, mask=255.255.255.0, gw=192.168.60.1
     bootserver=192.168.60.1, rootserver=192.168.60.1, rootpath=
```

But the board did not mount the NFS rootfs. Packet capture did not show the expected NFS mount traffic from the board.

## Important Lesson

Do not start by blaming the board, bootargs, firewall, or kernel config when the host-side NFS server changed.

First prove the host can mount its own export locally:

```bash
sudo mkdir -p /tmp/nfs-test
sudo mount -v -t nfs -o vers=3,proto=tcp,nolock \
  127.0.0.1:/home/charliechen/imx-forge/rootfs/nfs /tmp/nfs-test
```

In this case, localhost NFSv3 mount also hung. That immediately moved the fault boundary from board/kernel to WSL2 NFS service.

## Failed Kernel NFS Server Evidence

`nfs-kernel-server` appeared superficially alive:

```bash
sudo exportfs -rav
sudo exportfs -v
rpcinfo -p 127.0.0.1
showmount -e 127.0.0.1
```

But actual NFSv3 mount hung around the MOUNT/NFS RPC flow:

```text
mount.nfs: prog 100003, trying vers=3, prot=6
mount.nfs: trying 127.0.0.1 prog 100003 vers 3 prot TCP port 2049
mount.nfs: prog 100005, trying vers=3, prot=6
mount.nfs: trying 127.0.0.1 prog 100005 vers 3 prot TCP port <random>
```

The kernel nfsd export table was also empty even after `exportfs -rav`:

```bash
sudo cat /proc/fs/nfsd/threads
# 8

sudo cat /proc/fs/nfsd/exports
# Version 1.1
# Path Client(Flags) # IPs
```

A minimal `/srv/nfs-test` export had the same failure, so the problem was not the rootfs directory.

Conclusion: this new WSL2 environment's kernel NFS server path was unusable for NFSv3 rootfs boot.

## Working Fix: NFS-Ganesha

Install Ganesha and the VFS FSAL plugin:

```bash
sudo apt install nfs-ganesha nfs-ganesha-vfs
```

Stop the kernel NFS server but keep `rpcbind`:

```bash
sudo systemctl stop nfs-kernel-server
sudo systemctl restart rpcbind
```

Use this `/etc/ganesha/ganesha.conf`:

```text
NFS_CORE_PARAM {
    Protocols = 3;
    Bind_addr = 0.0.0.0;
    NFS_Port = 2049;
    MNT_Port = 20048;
    mount_path_pseudo = false;
    Enable_NLM = false;
}

EXPORT_DEFAULTS {
    Access_Type = RW;
    Squash = no_root_squash;
    SecType = sys;
}

EXPORT {
    Export_Id = 1;
    Path = /home/charliechen/imx-forge/rootfs/nfs;
    Pseudo = /nfsroot;

    Access_Type = RW;
    Squash = no_root_squash;
    SecType = sys;
    Protocols = 3;
    Transports = TCP;

    FSAL {
        Name = VFS;
    }

    CLIENT {
        Clients = 127.0.0.1, 192.168.60.0/24;
        Access_Type = RW;
        Squash = no_root_squash;
    }
}

LOG {
    Default_Log_Level = INFO;

    Facility {
        name = FILE;
        destination = "/var/log/ganesha/ganesha.log";
        enable = active;
    }
}
```

Restart and verify:

```bash
sudo systemctl restart nfs-ganesha
rpcinfo -p 127.0.0.1
showmount -e 127.0.0.1
```

Expected key ports:

```text
100003    3   tcp   2049  nfs
100005    3   tcp  20048  mountd
```

Expected export:

```text
Export list for 127.0.0.1:
/home/charliechen/imx-forge/rootfs/nfs 127.0.0.1/32,192.168.60.0/24
```

If `showmount` is empty, check `/var/log/ganesha/ganesha.log`. A common missing package error is:

```text
Failed to load FSAL (VFS) because: No such file or directory
No export entries found in configuration file !!!
```

Fix it with:

```bash
sudo apt install nfs-ganesha-vfs
sudo systemctl restart nfs-ganesha
```

## Final Working U-Boot Bootargs

Direct `bootargs`:

```text
setenv bootargs 'console=ttymxc0,115200 root=/dev/nfs rw nfsroot=192.168.60.1:/home/charliechen/imx-forge/rootfs/nfs,vers=3,proto=tcp,nolock,port=2049,mountport=20048 ip=192.168.60.200:192.168.60.1:192.168.60.1:255.255.255.0:imx6ull-aes:eth0:off'
```

Reusable U-Boot environment:

```text
setenv ipaddr 192.168.60.200
setenv serverip 192.168.60.1
setenv gatewayip 192.168.60.1
setenv netmask 255.255.255.0
setenv hostname imx6ull-aes
setenv nfsrootdir /home/charliechen/imx-forge/rootfs/nfs
setenv nfsargs 'setenv bootargs console=ttymxc0,115200 root=/dev/nfs rw nfsroot=${serverip}:${nfsrootdir},vers=3,proto=tcp,nolock,port=2049,mountport=20048 ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}:eth0:off'
setenv netbootaes 'run nfsargs; tftp ${loadaddr} ${bootfile}; tftp ${fdt_addr} ${fdt_file}; bootz ${loadaddr} - ${fdt_addr}'
run netbootaes
```

## Why `mountport=20048` Matters

NFSv3 uses both:

- NFS service: RPC program `100003`, normally TCP port `2049`.
- MOUNT service: RPC program `100005`, often a random dynamic port.

Ganesha was configured with:

```text
NFS_Port = 2049;
MNT_Port = 20048;
```

The kernel bootargs then pin both ports:

```text
port=2049,mountport=20048
```

This avoids random mountd ports and makes WSL/Windows firewall or port-forwarding troubleshooting much less painful.

## Debug Checklist

1. Check that the board got IP:

```text
IP-Config: Complete
device=eth0
rootserver=192.168.60.1
```

2. Check Ganesha exports:

```bash
showmount -e 127.0.0.1
rpcinfo -p 127.0.0.1
```

3. Check Ganesha logs:

```bash
sudo tail -120 /var/log/ganesha/ganesha.log
```

4. If using NFSv3 rootfs, always include:

```text
vers=3,proto=tcp,nolock,port=2049,mountport=20048
```

5. If the board cannot reach it but localhost can, inspect Windows/WSL networking next.
