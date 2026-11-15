---
title: 存储验收：在 U-Boot 里把 eMMC 摸一遍
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 存储验收：在 U-Boot 里把 eMMC 摸一遍

> 继 04 章的产物验证与 05 章的串口验收之后，主线把验收挪到存储介质：咱们在串口的 U-Boot 命令行里，用 mmc 这一类命令把板上的 eMMC 摸一遍，确认控制器认了卡、分区表读得出、boot 分区点得进去，顺手把环境变量在 eMMC 上的住处交代清楚。镜像怎么验、怎么烧，[产物验证与烧录](./04_verify_and_flash.md) 刚走过一遍，usdhc2 节点的设备树细节在 [设备树](./08_device_tree_aes.md) 铺过，本篇只回收一句。板子不在笔者手边，板端期望形态对着仓库源码与构建脚本写，每个判定标准都注明以什么为准。

## 一、mmc 命令家族的两个角色

咱们敲进串口的 mmc 命令是操作台，真正搬数据的，是板上那两个 USDHC 控制器，这是这个命令家族里的两个角色。i.MX6ULL 芯片内部长了两个 USDHC 控制器，usdhc1 的寄存器从 0x02190000 起，usdhc2 从 0x02194000 起，两个节点都写在芯片级的 `imx6ul.dtsi` 里，出厂状态都是 disabled，等板级设备树来点头。命令跟控制器怎么对上号、设备编号从哪来，咱们不背书，拿源码里的证据说话。

```bash
# 主机 ~/imx-forge
grep -n "mmc0\|mmc1" third_party/uboot-mainline/arch/arm/dts/imx6ul.dtsi
```

```text
33:		mmc0 = &usdhc1;
34:		mmc1 = &usdhc2;
```

编号写在设备树的 aliases 节点里，mmc0 对 usdhc1，mmc1 对 usdhc2，U-Boot 给控制器排号就认这份表。落到 AES 板上，对应关系一句话：0 号口接 SD 卡座，卡可以拔，1 号口接 eMMC，芯片焊在板上拔不了。后面每一条命令都靠着这份对应，mmc dev 1 切的是 eMMC，mmc dev 0 切的是卡座，咱们记牢这一句就够用。真板上谁是谁，以 aliases 与 CONFIG_ENV_MMC_DEVICE_INDEX 为准，别拿别处样例的括号标注当数。

每条命令各自读什么，笔者按层次分开说。mmc list 把驱动注册出来的控制器列一遍，报的是 FSL_SDHC 加编号。mmc dev 后面跟设备号，把当前设备切过去，切换这个动作自带一次强制初始化，`cmd/mmc.c` 第 598 行调 `__init_mmc_device` 时 force 参数传的就是 true，切设备等于重新扫了一遍卡。mmc info 读卡片的身份，厂商、产品名、速度、位宽、容量，字段翻译全在 `cmd/mmc.c` 第 24 行的 `print_mmcinfo` 里。mmc rescan 只做初始化这一件事，卡座换卡之后靠它找回状态，它不带 mmc dev 那次强制切换，只对当前设备动手。mmc part 往下一层，读介质上的分区表。ext4ls 再往下，读文件系统的目录。

控制器注册成功的第一个证词在启动横幅里。U-Boot 起来时会把认到的 MMC 控制器打在 MMC: 那一行，06 章贴过的启动日志样例里是 MMC: FSL_SDHC: 0, FSL_SDHC: 1 两项，跟着还有一行 Loading Environment from MMC... OK。咱们拿到真板横幅时照这个位置看，少一项，就说明有一个控制器没被设备树放出来，那张板的 usdhc 节点得回 08 章重核。AES 这棵树的板级 dtsi 把 usdhc1 与 usdhc2 都扳成 okay，板级 dts 又把 usdhc2 覆盖成 8 位配置，两个控制器都在册，真板横幅长什么样，以实测为准。

## 二、eMMC 挂在哪个口

咱们回配置里拿证据。第一份证据来自 defconfig，一行一行都是编译时定好的事实：

```bash
# 主机 ~/imx-forge
grep -n "ENV_OFFSET\|ENV_IS_IN_MMC\|ENV_MMC_DEVICE_INDEX\|CONFIG_CMD_MMC\|SUPPORT_EMMC_BOOT" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
8:CONFIG_ENV_OFFSET=0x400000
30:CONFIG_CMD_MMC=y
46:CONFIG_ENV_IS_IN_MMC=y
48:CONFIG_ENV_MMC_DEVICE_INDEX=1
63:CONFIG_SUPPORT_EMMC_BOOT=y
```

这五行咱们一句话一行地过。第 30 行 CONFIG_CMD_MMC=y 把 mmc 命令编进镜像，没这行，串口里敲 mmc 直接报未知命令。第 46 行 CONFIG_ENV_IS_IN_MMC=y 声明环境变量住在 MMC 里。第 48 行 CONFIG_ENV_MMC_DEVICE_INDEX=1 把住处定到 1 号控制器，按第一节 aliases 的对应，1 号就是接 eMMC 的 usdhc2。第 63 行 CONFIG_SUPPORT_EMMC_BOOT=y 打开 eMMC 硬件 boot 分区的操作支持，eMMC 芯片内部另有两块小小的 boot0 与 boot1 区域，这颗开关影响 mmc 命令对它们的读写，第三节还会碰到。第 8 行的 0x400000 单独留给第五节。

defconfig 里还有一处同方向的佐证：第 59 行 CONFIG_FASTBOOT_FLASH_MMC_DEV=1，fastboot 烧写的目标也指到 1 号。板级头文件再补两行：第 61 行把默认环境的 mmcdev 绑到 CONFIG_ENV_MMC_DEVICE_INDEX 上，第 63 行把 mmcroot 指到 /dev/mmcblk1p2，内核那边的编号同样是 1。引导与内核两个世界用同一个编号，这条线索咱们到第五节还会回收。

控制器想被 mmc 命令看见，还要设备树点头，咱们看板级 dts：

```bash
# 主机 ~/imx-forge
grep -n "usdhc" third_party/uboot-mainline/arch/arm/dts/imx6ull-aes.dts | head -8
```

```text
32:	usdhc2 is assigned from arch/arm/dts/imx6ull-14x14-evk-emmc.dts
35:&usdhc2 {
37:	pinctrl-0 = <&pinctrl_usdhc2_8bit>;
38:	pinctrl-1 = <&pinctrl_usdhc2_8bit_100mhz>;
39:	pinctrl-2 = <&pinctrl_usdhc2_8bit_200mhz>;
```

板级 dts 对 &usdhc2 做的事，完整节点在第 35 到 43 行：三组 pinctrl 对应默认、100 兆、200 兆三个速度态，bus-width = <8> 声明 8 位总线，non-removable 告诉驱动这卡焊在板上、不用做插拔检测，status 写成 okay 就是点头的那一下。status 与 pinctrl 属于软件这头的条件，硬件那头的供电与焊接不归它们管，两头的条件都齐，卡才会出现在 mmc list 里。三组 pinctrl 之间的电气参数差在哪，08 章按引脚讲过，咱们回收这一句就够。

还有一个细节值得咱们知道：两个控制器在 `imx6ul.dtsi` 里的出厂状态都是 disabled，usdhc1 节点在第 894 行，usdhc2 在第 908 行，各自的 status 都写着 disabled，是板卡的 dtsi 把它们扳成 okay 的。usdhc1 那份默认配置只开 4 位总线，SD 卡够用，eMMC 的 8 位是板级 dts 覆盖出来的，8 位对 4 位，带宽差一倍，这正是板级 dts 要单独重写 usdhc2 的原因。

两个口怎么分工，板卡补丁里看得最全：

```bash
# 主机 ~/imx-forge
grep -n "usdhc" patches/uboot-mainline/charlies_board.patch | head -6
```

```text
38:+	usdhc2 is assigned from arch/arm/dts/imx6ull-14x14-evk-emmc.dts
41:+&usdhc2 {
43:+	pinctrl-0 = <&pinctrl_usdhc2_8bit>;
44:+	pinctrl-1 = <&pinctrl_usdhc2_8bit_100mhz>;
45:+	pinctrl-2 = <&pinctrl_usdhc2_8bit_200mhz>;
442:+&usdhc1 {
```

前五行为板级 dts 补上 &usdhc2 那段 8 位配置，第 442 行往 dtsi 里加 &usdhc1 节点，cd-gpios 挂在 gpio1 第 19 脚、低电平有效，那是卡座的插拔检测脚，vmmc-supply 还给卡座单独接了供电。一个口管插拔的 SD，一个口管焊板的 eMMC，跟第一节 aliases 的编号对得上。两份证据合起来，eMMC 的位置就清楚了：物理上它接在 usdhc2 这只控制器上，软件上排在 1 号，环境变量与 fastboot 烧写都指到 1 号，咱们验收时敲 mmc dev 1，喊的正是它。

## 三、验收清单

验收按四步走，咱们每步给一条命令配一个判定标准，执行位置统一在串口的 U-Boot 命令行里，怎么拦进命令行，[第一次上电与串口检查](../start/05_first_boot_check.md) 写过，这里不重复。次序也有讲究：前两步验卡与控制器的通路，第三步验介质上的分区表，第四步验文件系统，一层一层往上走，哪一步断了，断点就落在那一步与上一步之间。四步全过，存储链路算合格，后面把内核装进内存、挂根文件系统，走的都是这条链。

### mmc dev 1：让 eMMC 应声

```bash
# 板端 U-Boot 命令行
mmc dev 1
```

判定标准：串口打出两行，switch to partitions #0, OK 与 mmc1(part 0) is current device。两句字符串都出自 `cmd/mmc.c`，第 608 行打第一句，第二句有 615、617 两个分支：带不带 (part 0) 取决于芯片在 EXT_CSD 里报的分区支持位（`drivers/mmc/mmc.c` 第 2435-2437 行），eMMC 一般带，SD 才是不带的形态。第一句里的 partitions 说的是 eMMC 的硬件分区，0 号是用户区，boot0、boot1 各有编号，第二节那颗 CONFIG_SUPPORT_EMMC_BOOT 开关管的就是这几块区域的操作，切不过去时 OK 会变成 ERROR。平时咱们只在用户区干活，两行都以 OK 收尾才算干净。还有个版本差异值得留意：有的教程或更老的 U-Boot 里，mmc dev 会连身份信息一起打出来，咱们这棵 v2026.10 的树不会——它只报设备号，容量与模式是 mmc info 的活，判定时别拿错标准。设备号敲成 0，应声的就是卡座，卡座没插卡时初始化会停在握手那一步，报错形态见第四节。

### mmc info：对身份

```bash
# 板端 U-Boot 命令行
mmc dev 1
mmc info
```

判定标准咱们按字段过一遍。Device 应为 FSL_SDHC，这是 i.MX USDHC 驱动注册时的名字。Capacity 应与板上焊的 eMMC 标称容量同一个数量级，8 GB 标称的卡报出 7 点几 GiB 属正常，厂商按十进制标称、U-Boot 按二进制 GiB 打印，mmc info 读的是器件原始容量，不经文件系统。Bus Width 期望 8-bit：节点里 bus-width = <8> 是软件的愿望，硬件真把八根数据线都送通了，这里才会报 8-bit，若打成 4-bit，说明有一根线没通或者 8 位 pinctrl 没生效，链路能走但带宽减半，验收算过，带宽折扣记下来，后面单独追。Mode 期望高速模式，Bus Speed 打出 52000000 配 MMC HS DDR 是常见的高速档形态。Mode 这行能不能打出来取决于 CONFIG_MMC_VERBOSE，它在 `drivers/mmc/Kconfig` 第 231 行默认 y，咱们这份 defconfig 没关它。eMMC 的报文比 SD 多出 Boot Capacity 与 RPMB Capacity 几行，print_mmcinfo 对 4.41 版以上的 eMMC 专门加报，boot0、boot1 那两块硬件分区的大小就在这里看。剩下的字段没有单独的门槛：Rd Block Len 常见 512，MMC 版本报 5.x，High Capacity 应为 Yes，Erase Group Size 大容量卡常见 512 KiB，对得上板上芯片的规格就是过。

### mmc part：读分区表

```bash
# 板端 U-Boot 命令行
mmc part
```

判定标准：打出 Partition Map for MMC device 1 一行，下面跟着两张 0x83 类型的分区记录，第一张带 Boot 标记。期望形态咱们从仓库脚本推：`build_imx6ull_image.sh` 用 sfdisk 写表，第 341 行 label 定的 dos，也就是 MBR，boot 分区从 16 MiB 起步（第 39 行 BOOT_START_MB=16），折合起始扇区 32768，默认 64 MiB，折合 131072 个扇区，rootfs 紧随其后从扇区 163840 起。表头写的是 Start Sector 而不是 Start LBA，这是这版源码的措辞，`disk/part_dos.c` 第 334 行管表头，第 55 行管记录行，UUID 列是构建时写下的磁盘签名加分区号，每次构建不一样，对不上别慌。defconfig 第 43 行 CONFIG_EFI_PARTITION=y 也开着，GPT 的卡它一样认，只是类型行会写 EFI。哪边烧的分区表，类型行就跟着哪边走。

### ext4ls：进 boot 分区点个名

```bash
# 板端 U-Boot 命令行
ext4ls mmc 1:1 /
```

咱们把冒号后那个 1 讲清楚：它是分区号，跟设备号是两回事，mmc 1:1 读的是 1 号设备的 1 号分区。判定标准：根目录列得出来，期望看到 zImage、imx6ull-aes.dtb、boot.cmd、boot 子目录与 mke2fs 自带的 lost+found，这份清单跟 `build_imx6ull_image.sh` 第 389 行往后的 boot_files 清单对得上。这一步依赖整卡镜像已经烧进介质，只烧过 U-Boot 单文件的卡根本没有 p1，ext4ls 会失败，这种失败属于预期内，不怪链路，咱们补烧一张整卡镜像就好。烧卡的两条路，SD 卡走 flash 卷 09 篇（SD 卡烧录），eMMC 走 flash 卷 10 篇（UUU + UMS eMMC 烧录），两边烧完再回到这四步把验收跑一遍。

::: warning mmc write 别对着引导区练手
后果：mmc write 的块号算错一格，落进 1 KiB 起的引导区，板子下次重启串口就静默，BootROM 到 1 KiB 找 IVT，读到的是写进来的数据，tag 对不上，链子在第一环就断。根因：eMMC 上引导镜像与环境变量都住在裸扇区上，mmc write 按块写，写之前不问一句。咱们练写操作时避开低扇区，写完拿 mmc read 读回来逐字节比。
:::

## 四、烧错与读错的典型现象

往下看表之前，咱们把看法说一句：三行覆盖的是硬件、协商、烧写三个方向上的失败，遇到别的现象，对上号再动手，排查方法重于答案。

| 现象 | 根因 | 解法 |
|------|------|------|
| mmc dev 1 报 Card did not respond to voltage select!，或干脆报找不到可用设备 | 设备树里 &usdhc2 没使能、控制器或卡的供电没上、eMMC 焊接不良，初始化握手时卡不应答，这句报错的原文出自 `drivers/mmc/mmc.c` 第 3043 行 | 回 08 章核 status 属性，拿万用表量 eMMC 供电脚，怀疑虚焊就补焊，然后 mmc rescan 再切一次 |
| mmc info 里 Capacity 对得上，Bus Width 却不足 8-bit，Mode 落在低速档 | 总线协商降级：八根数据线有一根不通或高速 pinctrl 态没生效，驱动凑不齐位宽就往 4 位、1 位退，速度模式跟着降，降级的链路照样能用 | 对照 08 章 pinctrl 三态逐项核配置，硬件上量数据线通断，能读能写先记录在案，带宽问题单独追 |
| mmc part 打不出分区行，或报读不到有效分区表 | 介质上没有分区表：只烧过 U-Boot 单文件的卡，分区表压根不在卡上，整卡镜像没写过 | 回 flash 卷重烧整卡镜像，SD 卡走 [09 SD 卡烧录](../flash/09_sd_card_flashing.md)，eMMC 走 [10 UUU + UMS eMMC 烧录](../flash/10_uuu_ums_emmc_flashing.md) |

第一行那个报错，笔者在源码里翻到的原文是 Card did not respond to voltage select!，后面还跟一个错误码，log_err 打印，落在电压协商收不到卡应答的那条路径上，意思是卡在第一步就没接住话，硬件嫌疑排在配置前面。降级那一行再补一句：降级不丢数据也不坏卡，只是慢，验收算过不算败，记下来，免得后面跑大镜像时才发现慢在哪里。排查的次序也按成本走：重扫与改配置几分钟的事，量供电得动表笔，补焊得动烙铁，重烧镜像得来回传文件，一级比一级贵，从便宜的那头查起，能少走回头路。

## 五、环境变量住在哪

这趟验收的收尾一站，咱们看环境变量的住处。defconfig 第 7、8 行的原文就这两行：

```text
# Keep the environment beyond the U-Boot image (including the built-in logo).
CONFIG_ENV_OFFSET=0x400000
```

0x400000 折合 4 MiB，第 6 行 CONFIG_ENV_SIZE=0x2000 折合 8 KiB，注释把选址理由写在明面上：环境区要待在镜像外面，内置 Logo 算镜像的一部分。这个选址是挪过一次的，笔者翻仓库笔记（`document/notes/2026-10-20-uboot-shared-mdio-handoff.md`）翻到了旧值：环境区原先放在 0xE0000，折合 896 KiB，那时带内置 Logo 的 u-boot-dtb.imx 约 1.62 MiB，从介质 1 KiB 处开始写，896 KiB 的环境区一头扎进镜像文件的身体里。后果具体到动作上：手工往 896 KiB 清 8 KiB 的制卡步骤，清掉的是镜像自己的内容，saveenv 保存一次，镜像就被环境变量覆盖一块。

挪到 4 MiB 之后，咱们看保护区怎么立起来。U-Boot 从 1 KiB 写起，最长写到 4 MiB 减 1 KiB 折合 4193280 字节为止，都碰不到环境区，saveenv 写的 4 MiB 到 4 MiB 加 8 KiB 这一小段，也碰不到镜像。升级时照旧从 1 KiB 写新镜像，只要新镜像不长过那条线，环境变量原地不动，咱们下一次启动照常读回，保护关系就是这一来一回互不越界。现镜像 1.62 MiB，离 4193280 字节的线还剩约 2.4 MiB 余量，比现镜像本体还宽出一段。

那份笔记里留了一张当时诊断镜像的布局表，咱们抄在这里当参考，数字是那次产物的，别跟现在脚本的默认值混着记：

| 区域 | 起点 | 大小或边界 |
|------|------|------|
| MBR 分区表 | 0 | 512 字节 |
| U-Boot | 1 KiB | 结束于 4 MiB 环境区之前 |
| MMC 环境 | 4 MiB | 8 KiB |
| p1：ext4，标签 boot | 8 MiB，扇区 16384 | 64 MiB，装 zImage 与 imx6ull-aes.dtb |
| p2：ext4，标签 rootfs | 72 MiB，扇区 147456 | 64 MiB，最小 BusyBox 根文件系统 |

表里 boot 分区起点是 8 MiB，第三节推的默认布局是 16 MiB，两个数都真实——8 MiB 是那次诊断镜像的取值，16 MiB 是现在脚本 BOOT_START_MB 的默认值，咱们分开记就行。环境区的 4 MiB 在两种布局里都落在镜像与分区之间的空地上，选址逻辑没变，变的只是分区往哪儿排。flash 卷 [06 整卡镜像布局](../flash/06_image_layout_design.md) 画过布局的全貌，咱们这里只把环境区的坐标摆进去。

板端这头就两句话，咱们照着串口核。启动横幅里应有一行 Loading Environment from MMC...，出现它，说明 4 MiB 处读到了有效环境，06 章贴过的启动日志样例里就有这行。读不到时串口会打 *** Warning - bad CRC, using default environment，环境回退到编译时的默认值，这份默认值出自板级头文件 `include/configs/mx6ull_aes_emmc.h` 的 CFG_EXTRA_ENV_SETTINGS，mmcdev、mmcpart、mmcroot 这些启动要用的变量都在里面，第二节提过第 61 行那个绑定，saveenv 覆盖的正是这一块。警告说的是存储上那份环境没通过校验，该查的是烧写，咱们别急着怀疑别的东西。

::: warning 改 ENV_OFFSET 之前量一遍镜像
后果：偏移改回去，或者镜像长得超过 4 MiB 减 1 KiB，环境区与镜像重叠，saveenv 一次就把引导镜像写坏，板子重启串口静默，看着像烧录事故，其实是选址事故。根因：镜像与环境区在介质上排在一起，全靠 CONFIG_ENV_OFFSET 一个数隔开，数错了没有任何机制拦着。咱们改这个偏移之前先算当前镜像的尺寸，烧完拿读回校验核一遍，确认环境区落在空地上。
:::

## 继续学习

- [产物验证与烧录](./04_verify_and_flash.md)：四个文件的验证与 SD、eMMC 两条烧录路的实操，本篇验收的介质从那里烧出来。
- [设备树](./08_device_tree_aes.md)：usdhc2 节点与 pinctrl 三态的完整讲法，核对位宽降级时回来对照。
- [调试命令速查](./14_debug_reference.md)：mmc 命令家族与其他调试命令的速查。旧版速查稿曾把 0 与 1 的标注写反过（0 实为 SD 卡座、1 实为 eMMC），现稿已按本篇第一节的 aliases 证据改正，速查时设备对应以此为准。
- [09 SD 卡烧录](../flash/09_sd_card_flashing.md)：SD 卡一侧的整卡烧录实测。
- [10 UUU + UMS eMMC 烧录](../flash/10_uuu_ums_emmc_flashing.md)：eMMC 的整卡烧录实测，分区表就是那时写上卡的。
