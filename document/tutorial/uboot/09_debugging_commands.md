---
title: U-Boot 调试命令
---

# 2026正点原子开发板移植（UBoot篇完结）：U-Boot调试命令：命令行是嵌入式开发的神器

## 板子信息查询：bdinfo 命令

当你拿到一块新板子，或者 U-Boot 启动后第一件事干什么？我的习惯是先看看板子的基本信息。这就像医生看病先要量体温血压一样，你得先知道板子的"健康指标"。

`bdinfo` 命令就是用来查看板子信息的。敲一下这个命令，你会看到一堆信息冒出来：

```
=> bdinfo
arch_number = 0x00000000
boot_params = 0x80000100
DRAM bank   = 0x00000000
-> start    = 0x80000000
-> size     = 0x20000000
flashstart  = 0x00000000
flashsize   = 0x00000000
flashoffset = 0x00000000
baudrate    = 115200 bps
relocaddr   = 0x9ff4a000
reloc off   = 0x17f4a000
Build       = 32-bit
current eth = fec-1:02
ethaddr     = 00:04:25:1c:a0:00
IP addr     = 192.168.1.102
fdt_blob    = 0x88000000
```

别慌，我们来拆一下这些信息都是什么意思。

`arch_number` 是架构号，这个在老版本 U-Boot 里用来传递给内核告诉它自己的机器类型，现在用设备树了基本不怎么用。`boot_params` 是启动参数的地址，内核会从这里读取参数。`DRAM bank` 显示内存信息，i.MX6ULL 有一块 512MB 的 DDR，起始地址 0x80000000，这个信息很关键，如果你要手动加载内核到内存，得知道哪块内存区域是可用的。

`baudrate` 是串口波特率，默认 115200，如果你发现串口输出乱码，第一件事就是检查波特率对不对。`relocaddr` 和 `reloc off` 是 U-Boot 自己的重定位信息，U-Boot 启动后会把自己从 Flash 复制到 DDR 里运行，这两个值告诉你复制到了哪里。`Build` 告诉你这是 32 位还是 64 位构建，i.MX6ULL 是 32 位 ARM 架构。

网络信息是重点，`current eth` 显示当前使用的网卡设备，`ethaddr` 是 MAC 地址，`IP addr` 是 IP 地址。如果你要调试网络相关的问题，比如 tftp 启动失败，第一步就是检查这些信息对不对。`fdt_blob` 是设备树树的地址，后面我们会详细讲怎么用 fdt 命令操作它。

bdinfo 还有一些参数选项。`bdinfo -a` 显示所有信息，`bdinfo -e` 只显示网络信息，`bdinfo -m` 只显示内存信息。这些选项在你只需要看某类信息时很有用，不用在一堆输出里翻来翻去。

我来举一个实际场景。有一次我调试一块板子，tftp 总是超时，换了网线换了交换机都不行。后来用 `bdinfo -e` 一看，发现 IP 地址是 0.0.0.0，根本没有分配到地址。原来是 `ipaddr` 环境变量没设置，设置一下就好了。你看，如果一上来就瞎改网络配置，可能折腾半天也找不到问题，用 bdinfo 看一眼就清楚了。

## 存储操作：mmc 命令家族

存储是嵌入式系统的基石，eMMC、SD 卡这些是 U-Boot 启动和加载文件的关键。`mmc` 命令家族是你与存储设备打交道的工具箱。

### mmc info 和 mmc dev

最基础的是 `mmc info` 命令，它会显示当前 MMC 设备的详细信息：

```
=> mmc info
Device: FSL_SDHC
Manufacturer ID: 11
OEM: 149
Name: SD8GAA
Bus Speed: 52000000
Mode: MMC HS DDR
Rd Block Len: 512
MMC version 5.1
High Capacity: Yes
Capacity: 7.3 GiB
Bus Width: 8-bit DDR
Erase Group Size: 512 KiB
```

这些信息告诉你存储设备的"身份"。 Manufacturer ID 和 OEM 可以帮你识别用的是哪家的芯片，Bus Speed 和 Mode 显示当前传输速度和模式，Capacity 显示容量，Bus Width 显示数据位宽。如果你换了不同容量的 eMMC，或者换了不同厂商的芯片，用这个命令可以确认硬件识别是否正确。

默认情况下，mmc 命令操作的是当前设备。如果你有多个 MMC 设备，比如一个 SD 卡和一个 eMMC，需要用 `mmc dev` 切换：

```
=> mmc dev 0    # 切换到设备 0
=> mmc dev 1    # 切换到设备 1
=> mmc dev      # 不带参数显示当前设备
```

i.MX6ULL 上通常设备 0 是 SD 卡，设备 1 是 eMMC，但这个要看具体的板子设计，不确定的话就用 `mmc list` 命令查看所有设备：

```
=> mmc list
FSL_SDHC: 0 (eMMC)
FSL_SDHC: 1 (SD)
```

### mmc rescan 和 mmc part

有时候你插拔了 SD 卡，或者热插拔了存储设备，U-Boot 不知道设备状态变了，这时候用 `mmc rescan` 重新扫描：

```
=> mmc rescan
```

这个命令会重新初始化 MMC 控制器，重新读取设备信息。如果你发现读取操作失败，或者设备容量显示不对，试试这个命令。

`mmc part` 命令显示分区表：

```
=> mmc part
Partition Map for MMC device 1  --   Partition Type: DOS

Part    Start LBA       Size                Type
  1     0x00000022      0x0007ffa0         0x83 Linux
  2     0x0007ffc2      0x0017ffa8         0x83 Linux
```

这里显示的是 DOS 分区表，有两个 Linux 分区。如果你看到分区表为空或者分区类型不对，可能是烧录出了问题，或者分区表损坏了。

### mmc read 和 mmc write

读取和写入是核心操作。`mmc read` 从存储设备读取数据到内存：

```
=> mmc read <addr> <blk#> <cnt>
```

`addr` 是目标内存地址，`blk#` 是起始块号，`cnt` 是要读取的块数。MMC 设备通常以 512 字节为一个块，所以计算地址的时候要考虑这个。举个例子，要把 eMMC 的第一个块读到内存 0x88000000：

```
=> mmc read 0x88000000 0x0 0x1
MMC read: dev # 1, block # 0, count 1 ... 1 blocks read: OK
```

`mmc write` 是反向操作，从内存写入到存储设备：

```
=> mmc write <addr> <blk#> <cnt>
```

这个命令要慎用，写错了位置可能把 bootloader 或者分区表覆盖掉。一个安全做法是先用 `mmc read` 读取一下看看内容对不对，确认无误后再写。

有个实战技巧：你可以用 `mmc read` 把整个镜像加载到内存，然后用 `iminfo` 命令验证镜像格式，确认没问题后再用 `mmc write` 写回去。这比直接烧录安全多了，至少你知道烧的是什么。

### mmc erase 和 mmc bootbus

`mmc erase` 擦除存储区域：

```
=> mmc erase <blk#> <cnt>
```

这个命令在某些场景下很有用，比如你想清空某个分区，或者测试坏块。不过要注意，eMMC 有擦写寿命，别没事就擦来擦去。

`mmc bootbus` 设置启动总线配置，这个主要和安全启动相关：

```
=> mmc bootbus 1 2 1 0
```

四个参数分别是设备号、数据宽度、强制总线模式、保留位。如果你要做安全启动，可能需要配置这个，但大部分应用场景用不上。

## 网络启动：tftp 和 dhcp 命令

网络启动是嵌入式开发的神技。你想想，每次改了内核或者设备树，都要烧录到 eMMC，多麻烦啊。用网络启动，文件放在服务器上，板子启动时自动下载，改完代码重启就行，开发效率提升一大截。

### dhcp 命令

`dhcp` 命令通过 DHCP 协议获取 IP 地址，并可选地下载启动文件：

```
=> dhcp
BOOTP broadcast 1
BOOTP broadcast 2
DHCP client bound to address 192.168.1.102 (1033 ms)
```

这是最简单的用法，只获取 IP 地址。如果你还想自动下载文件，可以在服务器上配置 BOOTP 文件名，或者在命令里指定：

```
=> dhcp 0x82000000 zImage
```

这会在获取 IP 后，自动把 zImage 下载到 0x82000000 地址。不过我一般不用这种方式，因为不够灵活，我喜欢先用 dhcp 获取 IP，然后手动用 tftp 下载文件。

dhcp 的 IP 分配过程很简单。板子广播一个 DHCP 请求，DHCP 服务器响应一个 offer 包，包含 IP 地址、子网掩码、网关等信息，板子发送请求确认，服务器响应确认完成分配。这个过程通常几百毫秒就能完成。

如果你发现 dhcp 获取不到 IP，先检查网线插好了没，再用 `bdinfo -e` 看看网卡驱动是不是加载了。如果还不行，可能是 DHCP 服务器配置问题，看看服务器日志。

### tftp 命令

`tftp` 命令通过 TFTP 协议下载文件：

```
=> tftp 0x82000000 zImage
Using ethernet@02188000 device
TFTP from server 192.168.1.1; our IP address is 192.168.1.102
Filename 'zImage'.
Load address: 0x82000000
Loading: #################################################################
         6.2 MiB/s
done
Bytes transferred = 6821504 (6824d0 hex)
```

这个命令会从 TFTP 服务器下载 zImage 到内存 0x82000000。下载速度取决于网络状况，你看到的这个 6.2 MB/s 已经很快了，百兆网络理论速度也就 12.5 MB/s，实际能达到 6-8 MB/s 就很不错了。

tftp 服务器怎么搭建？Linux 下最简单的是用 `tftpd-hpa`：

```bash
sudo apt install tftpd-hpa
sudo systemctl start tftpd-hpa
```

把文件放到 `/var/lib/tftpboot/` 目录下就行了。Windows 下可以用 tftpd32 或者 FileZilla Server，都很简单。

TFTP 是基于 UDP 的，所以不保证可靠传输，但实现简单，资源占用少，非常适合嵌入式场景。不过要注意，TFTP 不支持大于 32MB 的文件，如果你要下载更大的东西，得用 NFS 或者 HTTP。

### 网络调试技巧

网络启动常见问题无非这么几个：获取不到 IP、下载超时、下载后校验失败。获取不到 IP 先检查网线和 DHCP 服务器，下载超时先检查防火墙和文件路径，校验失败可能是传输错误，重新下载试试。

有个实用技巧是用 `ping` 命令测试网络连通性：

```
=> ping 192.168.1.1
Using ethernet@02188000 device
host 192.168.1.1 is alive
```

如果 ping 不通，说明网络配置有问题，不用浪费时间尝试 tftp。还要注意，U-Boot 的 `ping` 命令只发送几个包就停止了，不像 Linux 的 ping 会一直跑，这是正常行为。

调试网络问题时，`printenv` 命令也很有用，看看 `ipaddr`、`serverip`、`netmask` 这些环境变量设置对不对：

```
=> printenv ipaddr serverip netmask
ipaddr=192.168.1.102
serverip=192.168.1.1
netmask=255.255.255.0
```

如果这些值不对，用 `setenv` 修改一下，然后 `saveenv` 保存。

## 内核启动：bootm 和 bootz 命令

U-Boot 的终极目标是启动内核。`bootm` 和 `bootz` 是两个最常用的启动命令，区别在于支持的镜像格式。`bootm` 启动 uImage 格式（老式的 Legacy Image），`bootz` 启动 zImage 格式（ARM Linux 的压缩内核镜像）。

### bootz 命令

先说 `bootz`，因为现在大部分 ARM 系统都用 zImage。基本用法：

```
=> bootz 0x82000000 - 0x88000000
Kernel image @ 0x82000000 [ 0x000000 - 0x68238f ]
## Flattened Device Tree blob at 0x88000000
   Booting using the fdt blob at 0x88000000
   Loading Device Tree to 0x87fff000, end 0x88005b9f ... OK

Starting kernel ...
```

三个参数分别是：内核地址、initrd 地址（用 `-` 表示没有）、设备树地址。内核地址就是你用 tftp 下载到的地址，设备树地址通常是加载地址后面的某个位置。

`bootz` 会先解压内核，然后设置启动参数，最后跳到内核入口点执行。解压这个过程需要一点时间，你会看到一段时间的"黑屏"，这是正常的，内核在初始化早期还没有串口输出。

如果启动失败，`bootz` 会停住并显示错误信息。最常见的问题是解压失败、设备树格式不对、内存地址冲突。错误信息会给出一些线索，比如 "Bad magic number" 表示镜像格式不对，"CRC error" 表示文件损坏，重新下载试试。

### bootm 命令

`bootm` 的用法类似，但支持更多镜像格式：

```
=> bootm 0x82000000
## Booting kernel from Legacy Image at 0x82000000 ...
   Image Name:   Linux-5.15.0
   Image Type:   ARM Linux Kernel Image (uncompressed)
   Data Size:    6821504 Bytes = 6.5 MiB
   Load Address: 0x80008000
   Entry Point:  0x80008000
   Verifying Checksum ... OK
```

`bootm` 会先检查镜像头，验证 CRC 校验和，然后根据镜像类型决定如何处理。uImage 格式包含一个头，记录了镜像类型、加载地址、入口点等信息，`bootm` 根据这些信息正确加载和启动。

`bootm` 还支持 FIT 镜像（Flattened Image Tree），这是一种新的镜像格式，把内核、设备树、ramdisk 打包在一起，还支持签名和加密。FIT 镜像更灵活也更安全，是未来的趋势，但目前很多项目还在用 Legacy 格式，因为简单。

### 启动流程细节

无论是 `bootm` 还是 `bootz`，启动流程都分几个阶段。第一阶段是镜像验证，检查魔数、CRC 校验和，确保镜像没有损坏。第二阶段是解压和加载，zImage 需要解压，uImage 可能在正确的位置。第三阶段是设备树处理，把设备树放到内核期望的位置。第四阶段是准备启动参数，设置 ATAGS 或者设备树。最后阶段是跳转到内核。

这个流程中，设备树处理很关键。内核需要知道硬件信息，比如内存布局、外设地址、中断号等，这些都在设备树里描述。U-Boot 要把设备树放到正确的位置，还要根据实际情况修改某些属性，比如 chosen 节点的 bootargs。

## 环境变量管理：printenv、setenv、saveenv

U-Boot 的环境变量是配置系统的核心。它就像一个全局的配置数据库，存储了启动参数、网络配置、设备信息等。掌握环境变量管理，就掌握了 U-Boot 的"配置中心"。

### printenv 查看变量

`printenv` 命令显示环境变量：

```
=> printenv
arch=arm
baudrate=115200
board=mx6ull_14x14_evk
board_name=mx6ull_14x14_evk
bootargs=console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw
bootcmd=mmc dev 1; mmc read 0x82000000 0x800 0x4000; bootz 0x82000000 - 0x88000000
bootdelay=3
...
```

这是显示所有变量。你也可以指定只看某个变量：

```
=> printenv bootargs
bootargs=console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw
```

有个隐藏选项 `-a` 可以显示以点开头的变量，这些通常是系统内部变量，平时用不上：

```
=> printenv -a
```

### setenv 设置变量

`setenv` 命令设置环境变量：

```
=> setenv ipaddr 192.168.1.100
=> setenv serverip 192.168.1.1
=> setenv bootdelay 5
```

设置后会立即生效，但不会永久保存，重启后会丢失。要永久保存需要用 `saveenv` 命令，我们后面会讲。

`setenv` 还可以删除变量，赋值为空就行：

```
=> setenv oldvar
```

这会删除 `oldvar` 变量。有个陷阱要注意，你不能直接 `setenv bootargs` 来删除 bootargs，这样会把它设为空字符串，而不是删除。要删除的话用 `setenv bootargs && saveenv`，或者直接编辑存储设备上的环境变量区域。

### saveenv 保存变量

`saveenv` 命令把当前环境变量保存到存储设备：

```
=> saveenv
Saving Environment to MMC...
Writing to MMC(1)... done
```

这个命令很关键，不然你设置的环境变量重启后就没了。保存位置通常在 eMMC 或者 SD 卡的某个固定区域，具体位置看配置。

如果你发现保存失败，可能是存储设备写保护了，或者环境变量区域满了。eMMC 有时候会有写保护位，需要先清除。环境变量区域大小是固定的，如果变量太多超出了大小，saveenv 会失败，这时候得删掉一些不用的变量。

### 环境变量存储格式

环境变量在存储设备上是有特定格式的。开头是一个 32 位的 CRC 校验和，然后是一系列 "name=value" 字符串，用 null 字符分隔，最后用两个 null 字符表示结束。U-Boot 启动时会读取这个区域，计算 CRC 校验和，如果正确就加载到内存。

这种设计的好处是简单可靠，但缺点是大小固定，用起来不够灵活。新版本的 U-Boot 支持环境变量重叠和多个存储位置，可以提高可靠性，但基本格式还是一样的。

## 控制台信息：coninfo 命令

`coninfo` 命令显示控制台设备信息：

```
=> coninfo
List of available devices
|-- serial
|   |-- stdin
|   |-- stdout
|   |-- stderr
```

这里显示当前有三个标准 IO 设备：stdin（标准输入）、stdout（标准输出）、stderr（标准错误），都映射到了串口设备。

如果你有多个串口或者同时有串口和 LCD 显示器，`coninfo` 会显示更多设备：

```
=> coninfo
List of available devices
|-- serial
|   |-- stdin
|   |-- stdout
|   |-- stderr
|-- vidconsole
|-- serial@021f0000
```

`I` 标志表示该设备可以作输入，`O` 标志表示可以作输出。你可以用 `console` 命令或者修改环境变量来切换控制台设备。

控制台切换的一个实用场景是调试多串口系统。比如你有调试串口和通信串口，想通过通信串口输出日志，就可以用 coninfo 看看设备名，然后修改 `stdout` 环境变量。

## 设备树操作：fdt 命令

设备树是现代 Linux 系统描述硬件的标准方式，U-Boot 提供了 `fdt` 命令来操作设备树。这个命令功能很强大，可以查看、修改、添加节点和属性。

### fdt addr 和 fdt print

先用 `fdt addr` 设置设备树地址：

```
=> fdt addr 0x88000000
```

然后用 `fdt print` 查看设备树内容：

```
=> fdt print /
/ {
    model = "Freescale i.MX6 UltraLite 14x14 EVK Board";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
    #address-cells = <0x00000001>;
    #size-cells = <0x00000001>;
    ...
}
```

你也可以只看某个节点：

```
=> fdt print /memory
memory {
    device_type = "memory";
    reg = <0x80000000 0x20000000>;
};
```

或者只看某个属性：

```
=> fdt print /memory reg
reg = <0x80000000 0x20000000>;
```

`fdt list` 类似 `fdt print`，但只显示一级子节点，不递归显示：

```
=> fdt list /
/ {
    aliases { ... };
    chosen { ... };
    cpus { ... };
    memory { ... };
    soc { ... };
};
```

### fdt set 和 fdt mknode

`fdt set` 修改属性值：

```
=> fdt set /memory reg <0x80000000 0x40000000>
=> fdt set /chosen bootargs "console=ttymxc0,115200 root=/dev/mmcblk1p2"
```

第一个命令修改内存大小为 1GB，第二个命令设置启动参数。注意属性值的格式，数字用尖括号括起来，字符串直接写。

`fdt mknode` 创建新节点：

```
=> fdt mknode /soc mydevice
=> fdt set /soc/mydevice compatible "vendor,mydevice"
=> fdt set /soc/mydevice reg <0x021f0000 0x4000>
```

这会创建一个新设备节点，设置 compatible 和 reg 属性。这在测试新硬件或者临时修改设备树时很有用，不用重新编译设备树就能生效。

### fdt get 和 fdt rm

`fdt get` 读取属性值到环境变量：

```
=> fdt get memsize /memory reg
=> printenv memsize
memsize=0x80000000 0x20000000
=> fdt get addr myvar /soc/mydevice reg
=> printenv myvar
myvar=0x021f0000
```

第一个命令读取整个 reg 属性，第二个命令只读取第一个值。你可以在脚本里用这个命令提取设备树信息，然后根据这些信息做相应操作。

`fdt rm` 删除节点或属性：

```
=> fdt rm /soc/olddevice
=> fdt rm /chosen bootargs
```

第一个命令删除整个节点，第二个命令删除一个属性。这在调试时很有用，比如你怀疑某个设备导致问题，可以先删除它的节点看看。

### fdt apply 和 fdt resize

`fdt apply` 应用设备树叠加（overlay）：

```
=> fdt apply 0x89000000
```

设备树叠加是一种在不修改主设备树的情况下添加或修改节点的方式，很适合模块化设计。比如你有多个硬件配置，每个配置一个叠加文件，启动时根据实际情况选择应用哪个。

`fdt resize` 调整设备树大小：

```
=> fdt resize 0x1000
```

添加节点或属性后，设备树可能会变大，超出原来分配的空间，这时候需要用 resize 命令扩展。参数是额外的空间大小，按需调整。

## 调试技巧和窍门

讲了这么多命令，现在分享一些实战中总结的调试技巧。这些技巧不是命令文档会写的，都是踩坑后总结出来的经验。

### 分段验证法

遇到问题不要一头扎进去，要分段验证。比如网络启动失败，先验证网络通不通，再验证 TFTP 服务器有没有问题，最后验证镜像对不对。

```
=> ping 192.168.1.1              # 1. 测试网络
=> tftp 0x82000000 test.txt      # 2. 测试 TFTP
=> tftp 0x82000000 zImage        # 3. 下载镜像
=> iminfo 0x82000000             # 4. 验证镜像
=> bootz 0x82000000 - 0x88000000 # 5. 启动内核
```

如果第 1 步就失败了，问题在网卡或者网线，不用浪费时间看 TFTP。如果第 2 步失败，问题在 TFTP 服务器配置。如果第 4 步失败，问题在镜像文件。这样一步步排查，很快就能定位到问题。

### 环境变量备份

修改环境变量前先备份，特别是 `bootargs` 和 `bootcmd` 这种关键变量：

```
=> setenv bootargs_backup ${bootargs}
=> setenv bootcmd_backup ${bootcmd}
```

这样改错了还能恢复：

```
=> setenv bootargs ${bootargs_backup}
=> setenv bootcmd ${bootcmd_backup}
=> saveenv
```

我吃过这个亏，改了 bootargs 结果起不来，又忘了原来的值，只能重新烧录。从那以后我养成了备份的习惯，改之前先保存一份。

### 日志收集

调试时多收集日志，不要只盯着报错信息看。串口输出从头到尾都保存下来，很多问题的线索在早期的初始化阶段就出现了。

可以用脚本自动收集日志，比如：

```bash
picocom -b 115200 /dev/ttyUSB0 | tee uboot.log
```

这样串口输出会同时显示在终端和保存到 `uboot.log` 文件。出问题时可以直接看日志，不用凭记忆回忆。

### 最小化配置

怀疑某个配置导致问题时，先最小化配置。比如启动失败，试试最简单的 bootargs：

```
=> setenv bootargs "console=ttymxc0,115200"
=> bootz 0x82000000 - 0x88000000
```

如果这样能起来，说明是原来的 bootargs 有问题，慢慢加参数找原因。如果这样都不行，问题可能在内核或者设备树。

### 比较法

有块工作正常的板子是最好的参照。同样的命令、同样的环境变量、同样的镜像，对比一下哪里不一样：

```
=> printenv > env1.txt      # 问题板子的环境变量
=> printenv > env2.txt      # 正常板子的环境变量
=> diff env1.txt env2.txt   # 找差异
```

这个方法很土但很有效，我遇到过环境变量有个字符打错了导致启动失败的情况，对比一下马上就发现了。

## 常见错误及解决方案

最后整理一些常见的错误和解决办法，这些是笔者在实战中反复遇到过的。

### "Bad Magic Number"

这个错误表示镜像格式不对。可能原因：下载了错误的文件、传输过程中损坏、地址传错了。

解决方法：用 `iminfo` 命令检查镜像格式：

```
=> iminfo 0x82000000

## Checking Image at 82000000 ...
   Bad Magic Number
```

如果显示这个，说明该地址没有有效镜像。检查一下下载地址对不对，重新下载试试。

### "CRC error"

CRC 校验失败，说明镜像文件损坏。可能原因：传输错误、存储设备坏块、文件本身有问题。

解决方法：重新下载文件，如果还是不行，换一个下载源或者下载工具。也可以尝试换个存储设备试试。

### "No MMC device available"

找不到 MMC 设备。可能原因：硬件问题、驱动没加载、设备号不对。

解决方法：先用 `mmc list` 看看有哪些设备：

```
=> mmc list
FSL_SDHC: 0 (eMMC)
FSL_SDHC: 1 (SD)
```

然后切换到正确的设备：

```
=> mmc dev 0
```

如果还是不行，检查硬件连接，看看焊接是不是有问题。

### "TFTP timeout"

TFTP 下载超时。可能原因：网络不通、TFTP 服务器没启动、文件路径不对、防火墙阻止。

解决方法：先 ping 服务器确认网络通：

```
=> ping 192.168.1.1
```

然后检查 TFTP 服务器状态和文件路径。Linux 下可以查看服务器日志：

```bash
sudo journalctl -u tftpd-hpa
```

### "Kernel panic - not syncing"

内核启动时崩溃。可能原因：bootargs 不对、设备树不匹配、内存地址冲突、驱动问题。

解决方法：先简化 bootargs：

```
=> setenv bootargs "console=ttymxc0,115200"
```

如果能启动，说明原来的 bootargs 有问题。如果还是不行，可能是设备树的问题，用 `fdt print` 检查一下。

### "Environment exceeds reserved area"

环境变量空间不足。可能原因：变量太多、某个变量值太大。

解决方法：删除一些不需要的变量，或者增大环境变量区域。增大区域需要修改配置重新编译，这个比较麻烦，优先考虑清理不需要的变量。

## 实战调试案例

最后来两个实战案例，看看怎么综合运用这些命令解决问题。

### 案例一：网络启动失败

现象：tftp 下载总是超时，ping 服务器正常。

排查过程：

1. 先确认网络通：
```
=> ping 192.168.1.1
host 192.168.1.1 is alive
```

2. 检查 TFTP 服务器，发现服务器配置正常，文件也存在。

3. 尝试下载一个小文件：
```
=> tftp 0x82000000 test.txt
```

成功了！说明 TFTP 本身没问题，问题在文件太大。

4. 检查文件大小：
```
=> iminfo 0x82000000
Image Name:   Linux-5.15.0
Data Size:   6821504 Bytes = 6.5 MiB
```

6.5MB 不算大啊，为什么超时？

5. 怀疑是超时时间设置问题，检查环境变量：
```
=> printenv netretry
netretry=no
```

原来是设置了网络不重试，一次超时就放弃。修改一下：
```
=> setenv netretry yes
=> saveenv
```

再试一次，成功了！

### 案例二：内核启动后立刻重启

现象：bootz 启动内核后，看到 "Starting kernel ..." 就重启，没有更多输出。

排查过程：

1. 先简化 bootargs：
```
=> setenv bootargs "console=ttymxc0,115200"
=> bootz 0x82000000 - 0x88000000
```

还是重启，说明不是 bootargs 的问题。

2. 检查设备树：
```
=> fdt print /memory
memory {
    device_type = "memory";
    reg = <0x80000000 0x20000000>;
};
```

内存配置看起来没问题。

3. 检查 CPU 频率设置：
```
=> fdt print /cpu@0
cpu@0 {
    ...
    clock-frequency = <0x47868c00>;
};
```

这个频率有点高啊，换算一下是 1.2GHz，i.MX6ULL 最高 900MHz，可能是频率设置不对导致 CPU 过热或者不稳定。

4. 修改设备树：
```
=> fdt set /cpu@0 clock-frequency <0x35a4e900>
```

设为 900MHz，再启动：

```
=> bootz 0x82000000 - 0x88000000
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 5.15.0 ...
```

成功了！原来是设备树里 CPU 频率设置错误导致的。

## 写在最后

到这里，U-Boot 调试命令的主要内容就讲完了。从板子信息查询到存储操作，从网络启动到内核引导，从环境变量管理到设备树操作，我们系统性地过了一遍。

掌握这些命令不是靠死记硬背，而是要在实战中不断练习。每次遇到问题，先尝试用命令定位，而不是盲目的改代码或者烧录。时间久了，你会形成一种直觉，知道该用哪个命令，该检查什么。

命令行调试不是老派的做法，而是嵌入式开发的基本功。JTAG 很强大，但不是每次都方便用；IDE 很友好，但有时候不如命令行直接。一个好的工程师，应该掌握各种调试方法，根据实际情况选择最合适的工具。

希望这篇文章能帮你建立起对 U-Boot 命令行调试的系统认识，下次遇到问题时，能冷静地敲几个命令，快速定位到原因。调试不是碰运气，而是有方法的，掌握了正确的方法，问题就解决了一半。

---

至此，我们的U-Boot移植教程系列就告一段落了。从认识U-Boot的基础架构，到编译出第一个镜像；从板级配置和设备树移植，到LCD和网络这些复杂外设的驱动适配；再到Logo显示和调试命令的使用——你已经掌握了一套完整的U-Boot移植技能。

这些技能不是孤立的，它们构成了一个完整的知识体系。理解了编译流程，你就知道每次修改后应该如何正确地构建；掌握了设备树，你就具备了硬件描述与代码分离的现代思维；调通了网络，你的开发效率会成倍提升；熟悉了调试命令，你就能从容应对各种突发问题。

嵌入式开发没有银弹，但有方法论。掌握了正确的方法，再复杂的系统也能拆解成可管理的部分。希望这个教程系列能成为你U-Boot学习之路上的垫脚石，让你从"照着做"到"理解为什么"，再到"能独立解决新问题"。

祝你在嵌入式开发的道路上越走越远！
