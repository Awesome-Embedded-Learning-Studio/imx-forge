---
title: 为什么偏偏写到 1KB 偏移：镜像布局与烧录位置
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 为什么偏偏写到 1KB 偏移：镜像布局与烧录位置

> 烧录命令里有个数字，咱们每回敲 dd 都会路过：seek=1，镜像从介质的 1 KiB 偏移写起，开头整整 1 KiB 空着不用。上一篇把 DCD 清单逐条走完，BootROM 替咱们执行的初始化到那一篇全部交割，这个 1 的来历还没单独收拢过。本篇站在烧录这一侧把它收掉：BootROM 为什么偏偏到 0x400 找头，镜像之外那块 4 MiB 的空地住着什么，dd 的每个参数各管什么，偏移写错板子会怎么哑。本篇在交棒之前多停一站，下一篇才进 U-Boot 本体，从入口 _start 与异常向量看起。

## 一、BootROM 的固定找头位置

把疑问立起来。一张空白 SD 卡从第 0 字节起都归咱们写，dd 却被叮嘱从 1 KiB 写起，开头那 1 KiB 像白扔的。要是咱们自作主张写到偏移 0，BootROM 并不会跟着把搜索点往前挪，它只认 0x400，这个数不随镜像变，不随脚本变，也不随咱们的心情变。

字据咱们先摆一份，拿自家产物验文件的头。第 0 字节起就是那张 32 字节的索引卡，d1 开头，01 篇对过这次会师：烧卡写法把文件第 0 字节送到介质 0x400，BootROM 的搜索点正好在那儿：

```bash
# 主机 ~/imx-forge
xxd -l 16 out/uboot/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
```

头四个字节 d1 00 20 40，d1 是 IVT 的标记，02 篇把这张卡逐字段对过表。dd bs=1K seek=1 把文件从介质 1 KiB 处写进去，文件第 0 字节恰好落在 0x400，BootROM 到那儿一读就是它，一个字节都不偏。会师这件事 01 篇用 11 月 14 日那轮参考产物验过，本篇换成 10 月 20 日这轮自家产物，咱们再验一遍，字还是那串字。

0x400 本身的出处，咱们回源码里对。mkimage 打包时按 cfg 里 BOOT_FROM 选中的介质查一张偏移表，宏表住在 include/imximage.h：

```bash
# 主机 ~/imx-forge
sed -n '26,36p' third_party/uboot-mainline/include/imximage.h
```

```text
/* Initial Vector Table Offset */
#define FLASH_OFFSET_UNDEFINED	0xFFFFFFFF
#define FLASH_OFFSET_STANDARD	0x400
#define FLASH_OFFSET_NAND	FLASH_OFFSET_STANDARD
#define FLASH_OFFSET_SD		FLASH_OFFSET_STANDARD
#define FLASH_OFFSET_SPI	FLASH_OFFSET_STANDARD
#define FLASH_OFFSET_ONENAND	0x100
#define FLASH_OFFSET_NOR	0x1000
#define FLASH_OFFSET_SATA	FLASH_OFFSET_STANDARD
#define FLASH_OFFSET_QSPI	0x1000
#define FLASH_OFFSET_FLEXSPI	0x1000
```

咱们把表念一遍。0x400 有个正式名字 FLASH_OFFSET_STANDARD，SD、NAND、SPI、SATA 四档全都指向它，OneNAND 是 0x100，NOR 与 QSPI 是 0x1000。AES 板这份 cfg 的 BOOT_FROM 落在 sd，03 篇翻过 tools/imximage.c 那两张表，查表查出的介质偏移就是 0x400，打包出来的镜像按这个数摆头。这棵树烧 eMMC 用的也是同一份按 sd 查表打出的镜像，SD 与 eMMC 在 BootROM 眼里走同一个找头位置，01 篇交代过这句。芯片那一头真正从哪儿起扫，判读以 NXP 参考手册的 System Boot 章为准（IMX6ULLRM Rev.1 里是第 8 章），前几篇一直照这个口径，本篇不变。

### 为什么偏偏让出 1 KiB

为什么留出这一段，咱们把能验的与不能验的分开说。能验的有两条。一条是让位：扇区 0 归 MBR 分区表用，512 字节，BootROM 的搜索点从 1 KiB 起步，正好让开它，1 KiB 折合两个扇区，镜像头与分区表中间还隔着一整个空扇区当垫。另一条是承袭：mkimage 的报告头一行写着 i.MX53/6/7 compatible，同一张宏表服务这一批芯片，0x400 是它们共同的约定。不能验的是动机本身，手册只给了数字，没附一段为什么，NXP 白纸黑字谈选址缘由的出处笔者没翻到，这里不编传说。让开分区表是咱们能观察到的副作用，它是不是当年定数的原由，手册不说话，咱们也不替它说话。

## 二、镜像之外还有什么

镜像不是介质上的唯一住客，咱们把它的尺寸量一遍，再把它之外的东西一个个点出来。01、02 篇引过的参考产物 /tmp/uboot-ref-aes 这会儿已经不在了，ls 报 No such file or directory，05 篇开头记过同一件事，等价的产物仓库自己就有：

```bash
# 主机 ~/imx-forge
ls -la out/uboot/u-boot-dtb.imx
cat out/uboot/u-boot-dtb.imx.log
```

```text
-rw-r--r-- 1 charliechen charliechen 1702912 Oct 20 10:06 out/uboot/u-boot-dtb.imx
Image Type:   Freescale IMX Boot Image
Image Ver:    2 (i.MX53/6/7 compatible)
Mode:         DCD
Data Size:    1703936 Bytes = 1664.00 KiB = 1.62 MiB
Load Address: 877ff420
Entry Point:  87800000
```

咱们把两个数放一起算，长度就齐了。文件本体 1702912 字节，从介质 0x400 写起，尾巴落在 1703936，折十六进制正好 0x1A0000，与 02 篇对过表的 boot data size 字段同值，一寸不多。mkimage 报的 1.62 MiB 量的就是这段铺开的长度。

### 一张从 0 到 4 MiB 加 8 KiB 的地皮图

咱们照 ls 与日志里的数字把开头的地皮画出来：

```text
0x000000  MBR 分区表（512 字节，扇区 0）
0x000400  u-boot-dtb.imx 起写（1702912 字节，末尾落在 0x1A0000）
0x1A0000  空地（2432 KiB）
0x400000  MMC 环境区（8 KiB，到 0x402000 为止）
0x402000  空地，一直让到第一个分区
0x1000000 p1 boot 分区起步（16 MiB，扇区 32768）
```

图只画到 16 MiB 起步的 p1 为止。p1 起点的数字出自脚本第 39 行 BOOT_START_MB=16，flash 卷 09 篇贴过的 sfdisk 清单里 start=32768 那行与它咬合。10 章记过的那轮诊断镜像 p1 在 8 MiB，那是旧布局，现在脚本默认 16 MiB，两个数都真实，咱们分开记。

### 环境区为什么搬家

环境区住在 4 MiB 不是随手填的数，咱们把 defconfig 的原文翻出来：

```bash
# 主机 ~/imx-forge
sed -n '6,9p' third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
CONFIG_ENV_SIZE=0x2000
# Keep the environment beyond the U-Boot image (including the built-in logo).
CONFIG_ENV_OFFSET=0x400000
CONFIG_MX6ULL=y
```

注释把选址理由写在明面上：环境区要待在镜像外面，内置 Logo 也算镜像的一部分。这句话背后是主线记过的旧事，咱们拿 grep 把 06 章里的出处翻出来：

```bash
# 主机 ~/imx-forge
grep -n "0x400000" document/tutorial/uboot/06_aes_vs_evk_diff.md | head -4
```

```text
114:> CONFIG_ENV_OFFSET=0x400000
145:> CONFIG_FASTBOOT_BUF_SIZE=0x40000000
161:> CONFIG_FASTBOOT_BUF_SIZE=0x40000000
196:注释原话 Keep the environment beyond the U-Boot image (including the built-in logo)，翻译过来是把环境扇区挪到镜像连同内嵌 Logo 的后面，数字从 0xC0000（768 KiB）挪到 0x400000（4 MiB）。（后略）
```

四行里只有 114 与 196 两行是环境区的 0x400000，中间两行是 fastboot 缓冲区的 0x40000000，数字长得像，不是一回事。06 章把话说全了：这张开机图 tools/logos/denx.bmp 在工作区里是 1152054 字节，54 字节 BMP 头加 800×480×3 的像素数据，VIDEO_LOGO 把它整张嵌进镜像。旧位置按 06 章记的是 0xC0000 折 768 KiB，10 章翻仓库笔记又翻到过 0xE0000 折 896 KiB，两个数谁先谁后咱们不替它们排队，共同点只有一条：都小于 0x1A0000，全落在镜像的身体里。EVK 敢把环境贴在 768 KiB，靠的是官方镜像不带大图，咱们这棵树带了。

落在身体里的后果，10 章算过，咱们接过来：环境区与镜像一重叠，saveenv 写下去的位置就是镜像本体，下一次启动读回来的环境变量是烂的，反向重烧镜像又把环境区盖掉。挪到 4 MiB 之后，保护关系两头立住。镜像从 1 KiB 起写，长度最长 4193280 字节（4 MiB 减 1 KiB），再长就压进环境区，现镜像 1702912 字节，余量 2432 KiB。saveenv 写的 0x400000 到 0x402000 这 8 KiB，也碰不到镜像。升级时照旧从 1 KiB 写新镜像，环境变量原地不动，下次启动照常读回。

::: warning 改 ENV_OFFSET 之前量一遍镜像
后果：偏移改小，或者镜像长过 4 MiB 减 1 KiB，环境区与镜像重叠，saveenv 一次就把引导镜像写坏，板子重启串口静默，看着像烧录事故，根子是选址事故。根因：镜像与环境区在介质上排在一起，全靠 CONFIG_ENV_OFFSET 一个数隔开，写超了没有任何机制拦着。咱们动这个偏移之前拿 ls 量一遍镜像尺寸，烧完把卡上对应区段读回来核一遍。
:::

## 三、dd 命令逐参数

命令的真身在脚本里，咱们把偏移变量与那行 dd 一起贴出来：

```bash
# 主机 ~/imx-forge
sed -n '38,39p' scripts/image_builder/build_imx6ull_image.sh
sed -n '354,355p' scripts/image_builder/build_imx6ull_image.sh
```

```text
UBOOT_OFFSET_KB=1
BOOT_START_MB=16
    log_cmd "dd U-Boot to ${image} at ${UBOOT_OFFSET_KB} KiB"
    dd if="${UBOOT_IMAGE}" of="${image}" bs=1K seek="${UBOOT_OFFSET_KB}" conv=notrunc status=none
```

参数咱们一个个过。bs=1K 把块尺寸定为 1024 字节，seek=1 是写入前跳过一个块，两个数相乘才是真实落点，1024 字节，这就是 1 KiB 偏移的全部来历。seek 的单位跟着 bs 走，主线 04 篇记过那个失手：bs 换成 4M，seek=1 就把文件写到 4 MiB 去了，BootROM 在 0x400 一个字都找不着。conv=notrunc 是保命的那一个：脚本这行的 of 指向整盘 .img 文件，后面排着分区和文件系统，不带它，dd 把文件截成 1664 KiB，后面的内容当场蒸发。status=none 只管不刷统计，跟位置无关。

脚本写的是 .img 文件，手工往真卡上单烧 U-Boot 是同一个动作换个目标，咱们把主线 [产物验证与烧录](../04_verify_and_flash.md) 贴过的原样搬过来，sdX 换成 lsblk 认出来的整盘设备名：

```bash
# 主机 ~/imx-forge
sudo dd if=out/uboot/u-boot-dtb.imx of=/dev/sdX bs=1K seek=1 conv=notrunc status=none
sync
```

写完咱们补一步复核，把卡上 1 KiB 起的头 16 字节读回来，见到 d1 00 20 40 才算写对：

```bash
# 主机 ~/imx-forge
sudo dd if=/dev/sdX bs=1K skip=1 count=1 status=none | xxd -l 16
```

整卡镜像写卡是另一条命令，bs 跟着换挡，咱们引 [SD 卡烧录实战](../../flash/09_sd_card_flashing.md) 实测过的原样：

```bash
# 主机 ~/imx-forge
sudo dd if=out/release-latest/images/imx6ull-aes-sd.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

这里的 conv=fsync 换了差事，它管收尾那一下，dd 在结束前把数据尽量刷进设备。咱们拿 grep 把它在 09 篇里的出处翻出来：

```bash
# 主机 ~/imx-forge
grep -n "seek\|bs=1K\|conv=fsync" document/tutorial/flash/09_sd_card_flashing.md | head -6
```

```text
138:  conv=fsync
147:`conv=fsync` 会让 `dd` 在结束前尽量把数据刷到设备上。后面的 `sync` 是再稳一手，尤其是用 USB 读卡器时，不要看到命令返回就马上拔卡。（后略）
```

为什么非要这一手，咱们把路径想一遍：USB 读卡器把尾程数据先收进自己的缓存，dd 一返回，主机这边数是齐的，卡那头未必真收完，这时候拔卡，镜像尾巴就丢在半路。丢尾的镜像到了板子上症状不体面，主线 04 篇把文件截断列为验尺寸要拦的错，板端表现是串口静默，跟烧错偏移一个哑法。sync 是再稳一手，别看命令返回就拔卡。

写错偏移的后果，咱们分两头摆。头一头是分区表被碾：偏移写到 0，或者干脆忘了 seek，镜像的头 512 字节不多不少盖在扇区 0 的 MBR 上。卡插回主机，sfdisk 读不出分区表，lsblk 里分区不见影。板子那头 BootROM 到 0x400 读，按布局推读到的是文件 0x400 起的那段补零，DCD 清单 0x214 就收尾，往后垫零垫到 0xC00，03 篇验过，没有 d1，介质被判成没有镜像，串口静默。两头一起哑，主机看得见分区没了，板子看得见串口没动静。

::: warning dd 的 of= 指哪儿，哪儿被覆盖
后果：of= 写错设备，那块盘从指定偏移起被整段覆盖，指到主机自己的硬盘，分区表与文件系统当场报废，dd 全程不问一句。根因：dd 只认 if 与 of 两个路径，写之前不检查目标是什么。咱们敲回车前拿 lsblk 把设备名与卡对上号，容量核对两遍，拿不准就拔插一次看名字怎么变。
:::

另一头是 ENV 被碾，咱们把两种成因都摆出来：偏移写到 4 MiB 一带，比如上面那个 bs=4M 的失手，镜像直接盖在环境区上。或者镜像本身长过 4193280 字节，尾巴压进 0x400000。重叠之后的症状分两头。重烧镜像盖掉环境区，下次启动横幅里 Loading Environment from MMC... 变成 *** Warning - bad CRC，using default environment，环境回退编译默认值，10 章第五节记的就是这两行。反向 saveenv 盖掉镜像，板子下次重启串口静默。

::: warning 镜像与环境区互碾，没有报错可看
后果：重叠的双方都不会当场喊停，saveenv 写坏镜像要等下一次重启才发作，重烧镜像盖掉环境区只留一行 Warning，板子照旧拿默认环境走，问题拖到改过的环境变量不生效才现形。根因：两块区域在介质上排在一起，位置全靠 CONFIG_ENV_OFFSET 与烧录偏移两个数约定，数错了没有任何机制当场拦下。咱们烧录前对一眼镜像尺寸与 4193280 这条线，改过偏移的卡把两个区段各读回一次核对。
:::

## 四、四篇收拢：芯片一程与介质一侧

扩展卷到这里把芯片那一程连同介质这一侧都铺完了，咱们把四篇串成一根线：

```text
上电
  -> 拨码定模式，配置引脚或熔丝排次序，BootROM 挑中一块介质（01 篇）
  -> 到介质 0x400 读 IVT，认 d1 开头的索引卡（01、02 篇）
  -> 照 dcd 指针逐条执行清单，时钟、引脚、DDR 依次活过来（03 篇）
  -> 按 boot data 把镜像搬进 DDR，跳 0x87800000（03 篇）
  -> U-Boot 接手（05 篇起）
介质侧：扇区 0 归 MBR，1 KiB 起镜像，4 MiB 环境区，16 MiB 起 p1（本篇）
```

回头数一数这一程的分工，01 篇认 BootROM 与介质挑选，02 篇把 IVT 逐字段对表，03 篇走完 488 字节的 DCD 清单，本篇把镜像在介质上的住址摆平，烧录命令里那个 1 从此有出处。板端上电的执行咱们依然没验过，判读口径一直是文件字段与手册互相印证，这一程收拢时这条边界照实保留。

下一篇进 U-Boot 本体，从入口看起：05 篇《从 _start 开始：U-Boot 的第一条指令》接住 ROM 跳进 0x87800000 那一刻，把进门之后、进 C 之前 CPU 被摆成什么状态在源码里逐行对。05 篇里说的『上一篇』都指 03 篇——它篇首前置章链接标的也是 03 篇，别按相邻章号去解。03 篇末尾说的『下一篇』先落到本篇。接缝咱们已经量好了：文件 0xC00 起的第一条指令 b8 00 00 ea，按 03 篇验过的字节，它已经在 0x87800000 等着 ROM 跳进来。

## 继续学习

- [从 _start 开始：U-Boot 的第一条指令](05_entry_and_vectors.md)：下一篇，ROM 跳进 0x87800000 之后 U-Boot 本体的第一段。
- [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md)：上一篇，清单逐条读法与 0xC00 正文起点的验证都在那里。
- [SD 卡烧录实战](../../flash/09_sd_card_flashing.md)：整卡镜像从生成到写卡的完整实测，本篇 dd 参数的实操版。
- [整卡镜像布局](../../flash/06_image_layout_design.md)：16 MiB 分区起点与整盘布局的全貌。
- [存储验收：在 U-Boot 里把 eMMC 摸一遍](../10_emmc_acceptance.md)：环境区保护关系与坏 CRC 现象的完整记录。
