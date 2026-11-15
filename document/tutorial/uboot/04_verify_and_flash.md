---
title: 产物验证与烧录：四个文件各自是什么、怎么落到板子上
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 产物验证与烧录：四个文件各自是什么、怎么落到板子上

> 本篇接着上一篇的产物往下走：上一篇把 EVK 的四个文件编了出来，本篇拿刚出炉的参考产物把验证逐关跑给咱们看，验完再走 SD 卡与 eMMC 两条烧录路。烧录偏移的原理在 flash 卷铺过一章，本篇是它的实操面。板子真正上电的那一刻本篇验不到，哪一段没验、以什么参数为准，文中如实标注。四关与两条烧录路走完，下一篇接串口里的第一行输出。

## 一、四个检查关：架构、设备树、镜像头、尺寸

make 一路绿到 MKIMAGE 那一行，只证明构建系统自己没报错，产物里装的是不是咱们要的东西，它一个字都不担保。所以 build-uboot.sh 在编译收尾安排了一道验收，`verify_build_artifacts` 函数按固定次序查四样，ELF 的架构与入口、u-boot.bin 的尺寸、设备树的内容、imx 镜像的头。真正能让它退出非零的，是四份产物缺失与 ELF 架构不含 ARM 这两类，这两种情况整条构建按失败算，内容与镜像头的判读只写进日志，要不要放行得咱们自己看日志定。本节的走法把尺寸排在末尾当收口，脚本里尺寸的检查夹在中间，次序不同，四样是同样的四样。上一篇收尾留了三个尾巴，readelf 全项、dtc 反编译、mkimage 判读，说好留给本篇，咱们这就逐个兑现，用的产物是 11 月 14 日 14:01 出炉的 EVK 参考 build，每关贴真实输出，顺带讲清这一关拦的是哪类错。

### readelf 看 Machine：架构与入口对得上配置

```bash
# 主机 ~/imx-forge
readelf -h /tmp/uboot-ref-evk/u-boot | sed -n '1,14p'
```

```text
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00 
  Class:                             ELF32
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           ARM
  Version:                           0x1
  Entry point address:               0x87800000
  Start of program headers:          52 (bytes into file)
  Start of section headers:          4658244 (bytes into file)
  Flags:                             0x5000200, Version5 EABI, soft-float ABI
```

这关拦的是交叉编译环节配错工具的错。板上那颗 Cortex-A7 只认 32 位的 ARM 指令，咱们看 Machine 与 Class 两行，这是身份证明，ARM 加 ELF32，再搭上 Flags 里的 Version5 EABI 与 soft-float ABI，三样凑齐才算这个体系的产物。交叉前缀配错（比如误拿了主机自己的 gcc）会产出 x86-64 的 ELF，链接器挑不出毛病，产物自身是自洽的，只有 Machine 一栏当场暴露。`verify_build_artifacts` 的判法朴素，抓 Machine 一行，取到的词里含 ARM 才放行，含不上就报 Wrong architecture 并把退出码置一。

入口那一行也值得咱们核一眼。Entry point address 0x87800000 来自配置项 CONFIG_TEXT_BASE，参考产物目录 `/tmp/uboot-ref-evk` 下那份 `.config` 的第 183 行写着 CONFIG_TEXT_BASE=0x87800000（自家构建对应 `out/uboot/.config`），链接脚本按这个地址给代码排布，ELF 头里的入口与它相等是同一个来源的两面。这个地址后面还会再出现两次，镜像头里一次，BootROM 的跳转里一次，三处对得上，链条才算通。

工具这句也要交代诚实。笔者核对工具链时顺手拿带 `bin/..` 的路径形式试过一回，`/opt/arm-gnu-toolchain/bin/../arm-none-linux-gnueabihf-objcopy` 退出码 127，`bin/..` 退到上一层目录后那个文件并不存在，`command -v` 找到的真身在 `/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objcopy`，版本行是 GNU objcopy (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 2.45.1.20251203。工具链好好的，是那条试出来的路径多退了一级。readelf 也分两套，脚本优先用交叉的 `arm-none-linux-gnueabihf-readelf`，PATH 里没有才退回主机自带的，笔者上面贴的输出用的是 Ubuntu 的 binutils 2.42，两种 readelf 读出来的头一致，头是文件自身的属性，跟谁去读无关。想跟脚本完全一致，把命令换成 `arm-none-linux-gnueabihf-readelf` 即可，它就住在 /opt/arm-gnu-toolchain/bin 下。

### dtc 反编译：设备树里认板卡身份

```bash
# 主机 ~/imx-forge
dtc -I dtb -O dts /tmp/uboot-ref-evk/u-boot.dtb 2>/dev/null | grep -E "compatible|fsl,imx6ull" | head -3
```

```text
	compatible = "fsl,imx6ull-14x14-evk\0fsl,imx6ull";
			compatible = "arm,cortex-a7";
		compatible = "arm,armv7-timer";
```

配错板卡这类错阴在内容里，编译全程一声不吭，脚本这道关也只查文件在不在，真把它揪出来靠咱们自己反编译认内容。为什么编译期查不出来，咱们把机制看一眼：dtb 是独立编译的产物，DTC 那一步只管把 dts 编成语法合法的 blob，不管它描述的板子跟代码里编进去的板卡支持是不是同一块，两半各编各的，对不对得上要运行时才有答案。所以核对要落在内容上。

咱们请 dtc 把二进制的 blob 还原成文本，根节点的 compatible 一条属性挂了两个名字，fsl,imx6ull-14x14-evk 在前，fsl,imx6ull 在后，中间的 \0 是 dtc 打印多字符串时的分隔转义。两级的用法是前细后粗，驱动匹配先试精确的板名，试不上再退到芯片级通配，EVK 上那颗 i.MX6ULL 本就是单核 Cortex-A7，第二行 arm,cortex-a7 认的是 CPU 节点，第三行 arm,armv7-timer 认的是定时器节点。它跟 `.config` 里的 `CONFIG_DEFAULT_DEVICE_TREE="imx6ull-14x14-evk"` 同源，都是 mx6ull_14x14_evk_defconfig 带进来的。本机这份 dtc 是 /usr/bin/dtc，版本 DTC 1.7.0，脚本拿同一条 grep 抓 compatible 或 fsl,imx6ull 字样，命中打 i.MX6ULL device tree detected，不命中只把日志换成 u-boot.dtb: present，两种都放行，这份判读是打给咱们看的，不拦构建。

同一棵树编出来的 AES 板，dtb 是 33096 字节，咱们拿同一条 grep 去反编译，头一行 compatible 还是 fsl,imx6ull-14x14-evk 加 fsl,imx6ull。根节点沿用 EVK 的名字不是巧合，`arch/arm/dts/imx6ull-aes.dts` 第 13 行自己写着 `compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull"`，AES 板的 dts 本就站在 EVK 那套底子上改。所以这道关认的是 i.MX6ULL 这个血统，板与板的差别要看节点内容与尺寸，单看根 compatible 分不出兄弟。

### mkimage -l 读头：认出这是一张 i.MX 启动镜像

```bash
# 主机 ~/imx-forge
mkimage=$(find /tmp/uboot-ref-evk/tools -name mkimage 2>/dev/null | head -1)
echo "mkimage 路径: $mkimage"
/tmp/uboot-ref-evk/tools/mkimage -l /tmp/uboot-ref-evk/u-boot-dtb.imx
```

```text
mkimage 路径: /tmp/uboot-ref-evk/tools/mkimage
Image Type:   Freescale IMX Boot Image
Image Ver:    2 (i.MX53/6/7 compatible)
Mode:         DCD
Data Size:    438272 Bytes = 428.00 KiB = 0.42 MiB
Load Address: 877ff420
Entry Point:  87800000
```

mkimage 不用咱们额外安装，构建系统在编译时已经把它编进输出目录的 tools/ 下（build 日志里 HOSTCC tools 那一大批里就有它的原料），本篇直接拿它查 u-boot-dtb.imx，四个产物里真正拿去烧的就是这一个。这关拦的是烧错文件的错。四份产物里只有 imx 这份带 i.MX 启动头，Image Type 一行写着 Freescale IMX Boot Image，Image Ver 2，i.MX53/6/7 通用。Entry Point 87800000 又与 ELF 入口相等，Load Address 877ff420 与镜像头里 0x10 处的字相等，工具判读和裸字节互相印得上。要是拿 u-boot.bin 来做这步，mkimage 认不出这是启动镜像，这层筛子在烧录之前就把裸 bin 挡下。mkimage 的判读还自动留了一份在镜像旁边，u-boot-dtb.imx.log，194 字节，与上面贴的输出一模一样，脚本抓的正是 Image Type 那一行。

Mode 一栏咱们多说一句。DCD 指镜像头里挂着一张寄存器写入清单，BootROM 照单把 DDR 配好再跳。上一篇提过的另一条路线是 plugin，CONFIG_USE_IMXIMG_PLUGIN 打开后，镜像里编进一小段插件固件，由它代替 DCD 干配内存的活。本篇两块参考板都是 Mode DCD，走的还是清单这条路线。

### 尺寸对参考：四个数都要对得上号

```bash
# 主机 ~/imx-forge
ls -la /tmp/uboot-ref-evk/u-boot /tmp/uboot-ref-evk/u-boot.bin /tmp/uboot-ref-evk/u-boot.dtb /tmp/uboot-ref-evk/u-boot-dtb.imx
```

```text
-rwxr-xr-x 1 charliechen charliechen 4659244 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot
-rw-r--r-- 1 charliechen charliechen  437248 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot-dtb.imx
-rw-r--r-- 1 charliechen charliechen  431144 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot.bin
-rw-r--r-- 1 charliechen charliechen   31744 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot.dtb
```

EVK 的参考数就是这四个，u-boot 4659244，u-boot.bin 431144，u-boot.dtb 31744，u-boot-dtb.imx 437248。数与数之间还埋着关系，比背数可靠得多。u-boot.bin 等于 u-boot-nodtb.bin 加 u-boot.dtb，399400 加 31744 正好 431144，nodtb 那个 399400 咱们在产物目录里量过。另外，u-boot-dtb.imx 比 u-boot.bin 多 6104 字节，这 6104 不是全垫在文件头上的，笔者想当然过一回，拿 python 对着字节量完才发现：头区占前 3072 字节（0xC00），u-boot.bin 本体从第 3072 字节才开始，尾巴上再补 3032 字节零，3072 加 431144 加 3032 正好 437248，一段不差。自己构建完拿这两个式子算一遍，比翻笔记快。

这一关拦的错有两类。一类是文件截断，dd 写卡写到一半拔了卡，读回来的尺寸不够数，这类错到了板子上才发作，串口一点动静都没有，查起来最费人。一类是拿错产物，输出目录里混着别的 defconfig 留下的旧产物，尺寸差着量级，咱们对一下数当场现形。尺寸要跟自己那一轮的参考对，绝对数值背不得，同一棵源码树 11 月 14 日还出了 AES 板的一轮产物，两边放一起看就明白：

| 文件 | EVK（mx6ull_14x14_evk） | AES（mx6ull_aes_emmc） |
|---|---|---|
| u-boot | 4659244 | 7041800 |
| u-boot.bin | 431144 | 1696688 |
| u-boot.dtb | 31744 | 33096 |
| u-boot-dtb.imx | 437248 | 1702912 |

AES 比起 EVK 大出好几倍，是两套 defconfig 功能取舍的差别，细目在对账篇（06 章）铺开。上一篇咱们对照过另一轮 EVK 构建，小产物三个数分毫不差，带调试信息的 u-boot 每轮浮动几个字节，里面散着构建时间与路径。所以尺寸对照认小产物，ELF 的浮动不必当回事。

stat 取字节数打进日志这一半是脚本干的，拿日志跟参考数比还得咱们自己来，四样齐、架构对，脚本才打 All build artifacts verified successfully。

## 二、镜像头里的秘密：一眼 IVT

```bash
# 主机 ~/imx-forge
xxd -l 64 /tmp/uboot-ref-evk/u-boot-dtb.imx
```

<HexHeaderViewer
  title="u-boot-dtb.imx 头 64 字节（EVK，xxd 实拍）"
  bytes="d1 00 20 40 00 00 80 87 00 00 00 00 2c f4 7f 87 20 f4 7f 87 00 f4 7f 87 00 00 00 00 00 00 00 00 00 f0 7f 87 00 b0 06 00 00 00 00 00 d2 01 e8 40 cc 01 e4 04 02 0c 40 68 ff ff ff ff 02 0c 40 6c"
  :fields="[
    { name: 'tag', start: 0, size: 1, endian: 'raw', value: '0xD1', desc: 'IVT 身份标记，i.MX6 的 BootROM 认 0xD1 才继续往下读，不是就当这张介质没有启动镜像，串口一个字都不会有' },
    { name: 'length', start: 1, size: 2, endian: 'LE16', value: '0x0020', desc: 'IVT 自身长度 32 字节' },
    { name: 'version', start: 3, size: 1, endian: 'raw', value: '0x40', desc: '协议版本号' },
    { name: 'entry', start: 4, size: 4, endian: 'LE32', value: '0x87800000', desc: '镜像入口，BootROM 的落脚点', source: '与 readelf 的 Entry point、.config 的 CONFIG_TEXT_BASE 三方相等，一个数在三处各露一次脸' },
    { name: 'reserved', start: 8, size: 4, endian: 'raw', value: '0x00000000', reserved: true, desc: '保留段' },
    { name: 'dcdPtr', start: 12, size: 4, endian: 'LE32', value: '0x877FF42C', desc: 'DCD 指针：BootROM 跳进 U-Boot 前照单执行的寄存器写入清单，大头是 DDR 初始化，清单头就在偏移 0x2C', source: '0x2C 处 d2 01 e8 40：tag 0xD2、长度 0x01E8（大端）= 488 字节' },
    { name: 'bootLoad', start: 16, size: 4, endian: 'LE32', value: '0x877FF420', desc: 'Load Address，mkimage -l 报的加载地址' },
    { name: 'bootSelf', start: 20, size: 4, endian: 'LE32', value: '0x877FF400', desc: 'IVT 自身在内存里的落点' },
    { name: 'csf', start: 24, size: 8, endian: 'raw', value: '0x00000000…', reserved: true, desc: 'CSF 签名区，未启用安全启动时全零' },
    { name: 'bootData', start: 32, size: 4, endian: 'LE32', value: '0x877FF000', desc: '整份镜像搬进内存的起点', source: '与 IVT 落点差 0x400，正是文件前面挂的 1 KiB 分区表区域' },
    { name: 'bootSize', start: 36, size: 4, endian: 'LE32', value: '0x0006B000', desc: '搬运长度 438272 = 文件 437248 + 1024', source: '与 mkimage 报的 Data Size 相等，裸字节和工具判读互相作证' },
    { name: 'reserved2', start: 40, size: 4, endian: 'raw', value: '0x00000000', reserved: true, desc: '保留段' },
    { name: 'dcdTag', start: 44, size: 1, endian: 'raw', value: '0xD2', desc: 'DCD 头的身份标记' },
    { name: 'dcdLen', start: 45, size: 2, endian: 'BE16', value: '0x01E8', desc: 'DCD 清单总长 488 字节，大端读法，从 0x2C 数到 532 正好用完，往后的字节全是零' },
    { name: 'dcdVer', start: 47, size: 1, endian: 'raw', value: '0x40', desc: 'DCD 协议版本号' },
    { name: 'dcdPayload', start: 48, size: 16, endian: 'raw', value: '写入清单', desc: 'DCD 载荷开头：0x020C4068 ← 0xFFFFFFFF、0x020C406C ← 0xFFFFFFFF，逐条寄存器写入，boot-chain 卷逐条专讲' }
  ]"
  note="点字段名或字节格切换拼读面板。写完卡读回来对的就是这 64 字节，卡上第 1024 字节起数出 d1 00 20 40，就说明烧对了。"
/>

mkimage -l 是工具替咱们读，这 64 字节是咱们自己读。为什么 BootROM 非要一张表不可，咱们把处境摆出来：u-boot.bin 是一段裸指令流，指令自己不会说话，BootROM 读到介质上那串字节，不知道入口在哪、内存配没配、往哪跳。IVT（Image Vector Table，镜像向量表）就是给裸指令流配的名片，tag 证明这是一张按 i.MX 的约定做出来的镜像，入口告诉 ROM 跳哪，DCD 指针告诉 ROM 跳之前先把哪些寄存器写好。没有这张名片，裸 bin 写到卡上就是一串 ROM 看不懂的字节。

开头四个字节 d1 00 20 40，咱们按小端把它拼成 32 位字（小端就是低位字节排在前头），得到 0x402000D1。最低字节 0xD1 是 IVT 的 tag，i.MX6 的 BootROM 拿它当身份标记，是 0xD1 才接着往下读——不是的话，这张介质就被当成没有启动镜像，串口一个字符都不会有。中间的 00 20 是长度 0x0020，IVT 自身 32 字节，末字节的 40 是版本号 0x40。

往后咱们逐段看。偏移 0x04 的四字节 00 00 80 87 小端读出 0x87800000，镜像入口，与 readelf 的 Entry point、`.config` 的 CONFIG_TEXT_BASE 三方相等，一个数在三处各露了一次脸。偏移 0x0C 的字读出 0x877FF42C，是 DCD（设备配置数据，BootROM 跳进 U-Boot 前照单执行的一串寄存器写入，大头是 DDR 初始化）的指针，DCD 自己的头就在 0x2C 处，d2 01 e8 40，tag 0xD2，长度字段 0x01E8 折合 488 字节，从 0x2C 数到 532 正好用完，往后的字节全是零。偏移 0x10 的字 0x877FF420 就是 mkimage 报的 Load Address，0x14 的字 0x877FF400 是 IVT 自己的落点，0x20 的字 0x877FF000 是整份镜像搬进内存的起点，0x24 的字 0x0006B000 折合 438272，与 mkimage 报的 Data Size 相等，裸字节和工具判读互相作证。

数目上还有两处咬合值得咱们看一眼。一处是搬运长度，镜像文件 437248 字节，加 1024 正好是 0x24 处写下的 438272，卡上这份文件前头挂着 1024 字节的分区表区域，这组数刚好扣上。另一处是搬运起点与 IVT 落点的差，0x877FF000 与 0x877FF400 差 0x400，本体起点 3072 加上 IVT 落点正好是入口 0x87800000。这几组数互相当证人，谁也没跟谁打架。这 64 字节还有个实用处，写完卡读回来对的就是它们，卡上第 1024 字节起数得出 d1 00 20 40，就说明烧对了。这张表逐字段的完整读法，扩展卷 boot-chain 有专场，本篇认到 tag、入口与 DCD 指针，烧录就够用了。

## 三、烧到板子上：SD 卡与 eMMC 两条路

### SD 卡：一条 dd 与它背后的 1024

烧卡一行命令就够，咱们先把位置站对：在主机上，对整卡设备写，不对分区写。

```bash
# 主机 ~/imx-forge
sudo dd if=out/uboot/u-boot-dtb.imx of=/dev/sdX bs=1K seek=1 conv=notrunc status=none
sync
```

四个参数各有各的活。bs=1K 把块定为 1024 字节，seek=1 表示写入前跳过一个块，文件从整卡的第 1024 字节开始落地。这个 1024 咱们已经见过三面（flash 卷 [启动链路与偏移](../flash/04_imx6ull_boot_flow_and_offsets.md) 讲的写入偏移、第二节里 Data Size 438272 比文件 437248 多出的 1024、搬运起点 0x877FF000 与 IVT 落点 0x877FF400 差出的 0x400），出处是 BootROM 的约定：上电后到介质的第 1024 字节找 IVT，IVT 恰好就在镜像文件的第 0 字节，seek=1 把两边对上，卡的前 1024 字节让给分区表区域。偏移写错了会怎样，咱们把后果说具体：写在第 0 字节，BootROM 到 1024 处找 IVT，读到的是零和分区表内容，tag 对不上，串口静默，跟镜像坏了一个症状。

conv=notrunc 禁止截断，of 指的是整卡设备，后面排着分区和文件系统，不能让 dd 把整卡截成一个 437248 字节的文件。status=none 让 dd 不刷统计，工程脚本里就是这么写的，`scripts/image_builder/build_imx6ull_image.sh` 第 355 行是 `dd if="${UBOOT_IMAGE}" of="${image}" bs=1K seek="${UBOOT_OFFSET_KB}" conv=notrunc status=none`，偏移变量 UBOOT_OFFSET_KB 取 1，跟咱们手敲的是同一个动作，差别只在它把 imx 写进整盘 .img 文件，烧整卡镜像的完整流程在 [09 SD 卡烧录](../flash/09_sd_card_flashing.md)。

有两个细节容易栽，咱们分开看。seek 的单位跟着 bs 走，bs 定成 1K，seek=1 才是一个块即 1024 字节，换成 bs=4M 配 seek=1，文件就写到第 4 MiB 去了，BootROM 自然一个字都找不着。sudo 也是必须的，/dev/sdX 是整卡设备，写它要 root 权限，普通用户直接 Permission denied。

写完想复核，咱们把卡上第 1024 字节起的头 16 字节读回来对数：

```bash
# 主机 ~/imx-forge
sudo dd if=/dev/sdX bs=1K skip=1 count=1 status=none | xxd -l 16
```

读回来的输出应当以 d1 00 20 40 开头，对不上就是写偏了或者写错了文件，直接重烧，别等上电才白等一场。这张只装了 U-Boot 的卡不带内核，走到 U-Boot 接管串口为止，后面挂 rootfs、起内核都是 flash 卷整卡镜像的活，拿来验启动本身正合适，咱们要的答案就一个，串口有没有动静。

::: warning of= 写错设备，被覆盖的就是那块盘本身
后果：of= 指到哪，哪块设备从第 1024 字节起被覆盖，指到主机自己的硬盘，分区表和文件系统当场报废，dd 全程不问一句。根因在 dd 的设计，它只认 if 与 of 两个路径，读前者写后者，写之前不检查目标是什么。咱们敲回车前拿 lsblk 把 /dev/sdX 与卡对上号，容量、名字核两遍，拿不准就拔插一次看设备名怎么变。
:::

### eMMC：UUU 的位置一句带过

eMMC 焊在板上，拔不下来也插不进主机，烧它得让板子自己配合。路数是主机拿 UUU 工具经 USB 把一份 U-Boot 临时送进板子的 RAM 里跑起来，板子执行 `ums 0 mmc 1` 把板上 eMMC 借给主机当一个 U 盘，主机再照 SD 卡的办法把整盘镜像写进去。两条路烧的 U-Boot 是同一份，差别只在板子把存储亮给主机的办法，SD 自己会亮，eMMC 得借道。这条链路的完整实测在 [10 UUU + UMS eMMC 烧录](../flash/10_uuu_ums_emmc_flashing.md)，咱们只把位置摆正：UUU 送进 RAM 的那份 U-Boot 断电就没——它不等于已经烧进 eMMC，真正落进 eMMC 的动作发生在主机往那个 U 盘设备写镜像的那一步。

## 四、烧完之后

卡写完，板子那边还有一套接法，次序颠倒了第一段输出就没了。咱们按线、终端、上电这个次序来。串口线接好，USB 转 TTL 板的 TXD 接板子的 RXD，RXD 接 TXD，两根交叉，地线对地线，插稳。终端跟着开，minicom 或 picocom 都行，参数照下面的清单核，minicom 里记得把 Hardware Flow Control 设成 No，流控开着收发都会卡。上电放在两样之后——U-Boot 复位后只在串口打印一遍开头，终端后开它不等也不补，错过就按复位重来。

上电前咱们按次序核三样：

1. 波特率拨到 115200，8 数据位、无校验、1 停止位，依据是咱们这份 EVK `.config` 里的 CONFIG_BAUDRATE=115200，自己换过 defconfig 的就 grep 自己那份。
2. 串口设备名核准，插上 USB 串口后拿 dmesg 看尾部，/dev/ttyUSB0 或 /dev/ttyACM0 这类名字就在那几行里，咱们拿不准就拔插一次对比设备名。
3. 上电顺序走对，线接好、终端开好、再上电，万一咱们错过开头，按复位键重来，输出不会补。

地线那根咱们不能省。TX 与 RX 是两块板之间的电平信号，谁高谁低全拿地的电位当参考，共地断了，收到的就是一堆乱码，看着像波特率配错，实际是参考都没了。设备名为什么用 dmesg 查，USB 串口插上时内核当场枚举一遍，尾部那几行把新设备认成 ttyUSB 还是 ttyACM，写得清清楚楚，比猜快。

板子上还有一处开关跟这份清单平级，咱们把它也算进核对，启动拨码。它决定 BootROM 到哪块介质找镜像，烧进 SD 卡就拨到 SD 启动那挡，烧进 eMMC 就拨到对应挡位，熔丝那一套是另一条路，[启动链路与偏移](../flash/04_imx6ull_boot_flow_and_offsets.md) 讲过它的位置。拨码没拨对，镜像再合格 BootROM 也不往那儿找，串口一样没动静。

这几样核完、上电，串口里的动静下一篇接手，第一行输出怎么认、哪些数要跟本篇贴出的 ELF 头与镜像头对，下一篇带咱们逐项核。终端怎么装怎么配，[串口工具使用](../start/04_serial_tools_minicom.md) 备着。想在 VSCode 里写代码与看串口两头兼顾的，[串口终端](../workflow/03_serial_terminal.md) 那篇把工作台搭好。

## 继续学习

- [净源码里没有咱们的板卡](./06_aes_vs_evk_diff.md)：本篇验的 EVK 与仓库里 AES 板的差别，从这一篇逐行铺开。
- [七步造出咱们的板卡](./07_board_porting.md)：defconfig 与 Kconfig 的正题，改完配置回来把本篇四关重跑一遍再烧。
- [SD 卡烧录实战](../flash/09_sd_card_flashing.md)：整卡镜像从生成到写卡的实测流程，本篇单烧 U-Boot 的完整版。
