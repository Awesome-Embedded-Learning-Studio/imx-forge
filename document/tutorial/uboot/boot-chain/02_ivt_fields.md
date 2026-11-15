---
title: IVT 逐字段：BootROM 拿到的说明书
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# IVT 逐字段：BootROM 拿到的说明书

> 上一篇咱们跟着 Boot ROM 走到了介质开头的 1 KiB 偏移，找回 d1 开头的 32 字节索引卡，悬问也留在那里：卡上这几十个字节，每个到底替它记着什么。本篇把这张卡按源码里的结构定义逐字段过一遍，两份参考产物的真实转储当裁判，每个字段都补上 Boot ROM 拿它干的那件事。boot data 三字组与 csf 指针各占一节，下一篇再进 DCD 那份初始化清单，把每一组寄存器写入对到源文件上。

## 一、回顾与材料

Boot ROM 按次序扫介质，在选中介质开头的 0x400 偏移读回 32 字节，见到 d1 开头才认下这是一张 IVT，这件事上一篇交代完了。悬问也留在咱们手里没答：卡上这几十个字节，哪几个 Boot ROM 真会去查，查到了又拿去干什么。本篇咱们就答这一件事，把每个字段对到它的用途上，一个字都不让它空挂着。

材料咱们备好了。转储是现成的，EVK 与 AES 两份参考产物都在 /tmp 下面，xxd 一敲就有。结构定义住在源码里，mkimage 打包时照着它摆字节。笔者按 tools/imximage.h 这个想当然的路径去找过，扑了个空，报错 No such file or directory，往 include/ 里一翻就在，取证照实记在这里。芯片那头的部分文件里验不到，判读以 NXP《i.MX 6ULL Applications Processor Reference Manual》为准，IMX6ULLRM Rev.1 里 System Boot 是第 8 章，IVT 字段的权威表就住在那一章，本篇把字节证据跟手册口径对齐着讲，印不上的地方明说。

结构定义咱们拿 grep 认个脸：

```bash
# 主机 ~/imx-forge
grep -n "flash_header\|0xD1\|0x40" third_party/uboot-mainline/include/imximage.h | head -10
```

```text
28:#define FLASH_OFFSET_STANDARD	0x400
44:#define FLASH_LOADSIZE_ONENAND		0x400
50:#define IVT_HEADER_TAG			0xD1
51:#define IVT_VERSION			0x40
54:#define DCD_VERSION			0x40
124:} flash_header_v1_t;
131:	flash_header_v1_t fhdr;
179:} flash_header_v2_t;
182:	flash_header_v2_t fhdr;
191:	flash_header_v2_t fhdr;
```

0xD1 有宏名 IVT_HEADER_TAG（第 50 行），0x40 有宏名 IVT_VERSION（第 51 行），转储第一行四个字节的出处全在头文件里。本篇的主角 flash_header_v2_t 从第 170 行起，咱们整段拿出来：

```c
typedef struct {
	ivt_header_t header;
	uint32_t entry;
	uint32_t reserved1;
	uint32_t dcd_ptr;
	uint32_t boot_data_ptr;
	uint32_t self;
	uint32_t csf;
	uint32_t reserved2;
} flash_header_v2_t;
```

header 的类型又是独立一小块，咱们也拿出来看：

```c
typedef struct {
	uint8_t tag;
	uint16_t length;
	uint8_t version;
} __attribute__((packed)) ivt_header_t;
```

八组四字节整好 32，咱们数一遍就有数：header 一格塞了三个小字段，占 4 字节，后面七组每组一个 32 位字。__attribute__((packed)) 叮嘱编译器别垫空隙，一个字节都不多占，表的总长才恰好是 0x0020，也就是 32 字节，跟转储对得上。

## 二、八组字段逐个过

EVK 的转储咱们整段拿出来，128 字节一行不少。头 32 字节是 IVT 本体，0x20 起是 boot data，归第三节细看，0x2C 起是 DCD，是下一篇的主角，这里只认个门牌，头里 0x18 那格 csf 指针第四节单独拎出来讲：

```bash
# 主机 ~/imx-forge
xxd -l 128 /tmp/uboot-ref-evk/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 00b0 0600 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
00000040: ffff ffff 020c 4070 ffff ffff 020c 4074  ......@p......@t
00000050: ffff ffff 020c 4078 ffff ffff 020c 407c  ......@x......@|
00000060: ffff ffff 020c 4080 ffff ffff 020e 04b4  ......@.........
00000070: 000c 0000 020e 04ac 0000 0000 020e 027c  ...............|
```

八组字段咱们对成一张表，用途在这里立起来，字节序的讲究留在下一小节：

| 偏移 | 字段 | 转储里的字节 | 读出来的值 | Boot ROM 拿它做什么 |
| --- | --- | --- | --- | --- |
| 0x00 | header | d1 00 20 40 | tag、length、version 三个小字段 | 认格式、量长短、对代次 |
| 0x04 | entry | 00 00 80 87 | 0x87800000 | 清单执行完从这里跳进 U-Boot |
| 0x08 | reserved1 | 00 00 00 00 | 0 | 不读，占位凑格式 |
| 0x0C | dcd_ptr | 2c f4 7f 87 | 0x877ff42c | 找到初始化清单 DCD |
| 0x10 | boot_data_ptr | 20 f4 7f 87 | 0x877ff420 | 找到 boot data 三字组 |
| 0x14 | self | 00 f4 7f 87 | 0x877ff400 | IVT 自己运行时的住址 |
| 0x18 | csf | 00 00 00 00 | 0 | 签名数据落点，零表示没启用验签 |
| 0x1C | reserved2 | 00 00 00 00 | 0 | 不读，占位凑格式 |

### header：三个小字段，两种字节序

开头四个字节 d1 00 20 40，咱们按 ivt_header_t 摆开，是 tag、length、version 三个小字段。tag 就是宏表里那个 0xD1，Boot ROM 见到它才认出 IVT，往后才谈得上读其余字段。version 的 0x40 对着 IVT_VERSION，是 i.MX6 这一代头协议的代次号，Boot ROM 拿它核对格式跟自家的理解对不对得上。

length 那两字节值得咱们停一下，它的字节序跟后面所有地址不一样。转储里写的是 00 20，按小端拼 16 位数会拼出 0x2000，等于声明这张表长 8192 字节，跟事实差着两个数量级。源码给出了答案，tools/imximage.c 第 337 到 339 行，mkimage 摆这三个字段用的是这么三句：

```c
fhdr_v2->header.tag = IVT_HEADER_TAG; /* 0xD1 */
fhdr_v2->header.length = cpu_to_be16(sizeof(flash_header_v2_t));
fhdr_v2->header.version = IVT_VERSION; /* 0x40 */
```

咱们把 cpu_to_be16 那一句翻译成人话：它把 0x0020 按大端写进字节，高位在前，00 20 拼出来正好是 32，头自身的长度。本篇后面全部 32 位地址都按小端读——唯独这个长度字段反着来，咱们读转储的时候得留意这一处。0x2C 起四个字节 d2 01 e8 40 是同一副骨架，imximage.h 第 53 行的 DCD_HEADER_TAG 对着 0xD2，长度 0x01E8 同样是 cpu_to_be16 写的（imximage.c 第 297 到 298 行），那是 DCD 自己的头，下一篇的主角，这里认个门牌就过。

### entry：Boot ROM 交棒的位置

0x04 起四个字节 00 00 80 87，小端拼法咱们上一篇练过，xxd 从左往右是低地址到高地址，最右边的 87 顶到最高位，咱们把它拼起来就是 0x87800000。这就是 entry，初始化清单执行完，Boot ROM 把程序计数器拨到这个地址，控制权从此交给 U-Boot。

这个数咱们在三处碰过它。一处是上一篇 readelf 报的 Entry point address，一处是今天这四个字节，还有一处是配置，现查现证：

```bash
# 主机 ~/imx-forge
grep -n "CONFIG_TEXT_BASE" out/uboot/.config /tmp/uboot-ref-evk/.config /tmp/uboot-ref-aes/.config
```

```text
out/uboot/.config:183:CONFIG_TEXT_BASE=0x87800000
/tmp/uboot-ref-evk/.config:183:CONFIG_TEXT_BASE=0x87800000
/tmp/uboot-ref-aes/.config:183:CONFIG_TEXT_BASE=0x87800000
```

咱们把三棵构建树摆在一起看，第 183 行同值，链接脚本按它排布正文，打包命令行又把它喂给 mkimage。喂的方式咱们在 arch/arm/mach-imx/Makefile 第 172 行找到，MKIMAGEFLAGS_u-boot-dtb.imx 里有一条 -e $(CONFIG_TEXT_BASE)，mkimage 照它把 entry 填进卡里。mkimage 自己的小日志 /tmp/uboot-ref-evk/u-boot-dtb.imx.log 也报过一遍，其中 Entry Point: 87800000 跟转储一字不差，于是来历链条咱们算是走通了。

### 两个保留位：mkimage 补的零

0x08 与 0x1C 两处，转储里都是 0000 0000，来由咱们照着源码找。两个零的来由不一样。reserved1 是 set_imx_hdr_v2 显式写零的，tools/imximage.c 第 343 与 344 行连着两句 fhdr_v2->reserved1 = 0。reserved2 在非插件分支确实没有任何赋值动作，靠打包起点的 memset(imxhdr, 0, alloc_len)（第 1028 行）清零保下来。Boot ROM 不读它们，咱们可以把它们理解成格式留白，作用只是把表凑成结构定义摆出的形状，让每个指针都住在自己的格子里。

### dcd_ptr、boot_data_ptr、self：三个互相咬合的地址

剩下三组指针咱们并排看。dcd_ptr 的字节 2c f4 7f 87 拼出 0x877ff42c，boot_data_ptr 的 20 f4 7f 87 拼出 0x877ff420，self 的 00 f4 7f 87 拼出 0x877ff400，指着 IVT 自己运行时的住址。三个数跟原点的距离咱们一眼可算，0x877ff42c 高出 0x2C，0x877ff420 高出 0x20。

咬合的来由咱们顺着摆放想一遍就明白。镜像在文件里连续摆放，IVT 在文件 0 偏移，搬进内存就落在 self，文件偏移加上 self 就是内存地址，0x20 与 0x2C 两个偏移原样成立。tools/imximage.c 的打包函数 set_imx_hdr_v2 正是这么算的，以 self 为原点，boot data 与 DCD 的位置再按结构偏移补齐。Boot ROM 顺着 dcd_ptr 去找初始化清单，顺着 boot_data_ptr 找到 boot data 三字组，self 记的是这张卡自己运行时的住址，三格指针一格都不能错位。咱们改配置时看到它们三个一起动，就知道链子没断。

### AES 交叉：头 32 字节一个字不差

AES 的转储咱们也倒出来对一遍：

```bash
# 主机 ~/imx-forge
xxd -l 128 /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 0000 1a00 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
00000040: ffff ffff 020c 4070 ffff ffff 020c 4074  ......@p......@t
00000050: ffff ffff 020c 4078 ffff ffff 020c 407c  ......@x......@|
00000060: ffff ffff 020c 4080 ffff ffff 020e 04b4  ......@.........
00000070: 000c 0000 020e 04ac 0000 0000 020e 027c  ...............|
```

两份摆在一起，咱们逐字节比，头 32 字节一个字都不差。板卡不同，镜像大小差出将近四倍，卡上八组却指向同一组地址，这说明字段含义由芯片与 mkimage 之间的约定决定，不随板卡变。第一个分岔咱们在 0x24 看到，size 字段，EVK 是 00 b0 06 00，AES 是 00 00 1a 00，正是下一节的主角。

::: warning 别手改镜像里的头
有一类改法咱们见过不少：十六进制编辑器开进 .imx，发现某个地址不顺眼，直接改掉四个字节。根因是卡上的字段互相咬合，entry、dcd_ptr、boot_data_ptr、self 全部从 CONFIG_TEXT_BASE 与结构偏移推出来，mkimage 打包时一并算好，改一格其余格子全跟着错位。后果有两层：板子当场不活，跳过去取指取到的是错位字节。下次重编，mkimage 把整个头重新生成，手改的字节原样盖回去。地址要动，咱们改配置源，让 mkimage 重算全卡。
:::

## 三、boot data：镜像在内存里的户口

0x20 起十二个字节是 boot data，三字组的结构定义短得一眼看完，咱们照例拿源码对个脸：

```c
typedef struct {
	uint32_t start;
	uint32_t size;
	uint32_t plugin;
} boot_data_t;
```

咱们把三组数念出来。EVK 的转储里，start 的 00 f0 7f 87 拼出 0x877ff000，size 的 00 b0 06 00 拼出 0x0006b000，plugin 四个零拼出 0。AES 的转储里只有 size 不同，00 00 1a 00 拼出 0x001a0000。size 拿文件尺寸一核就通：

```bash
# 主机 ~/imx-forge
ls -la /tmp/uboot-ref-evk/u-boot-dtb.imx /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
-rw-r--r-- 1 charliechen charliechen 1702912 Nov 14 14:01 /tmp/uboot-ref-aes/u-boot-dtb.imx
-rw-r--r-- 1 charliechen charliechen  437248 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot-dtb.imx
```

咱们算一遍：437248 加 0x400 得 438272，正是 0x6b000，1702912 加 0x400 得 1703936，正是 0x1a0000，两个结果都恰好落在 4 KiB 的整数倍上。size 的语义按手册口径讲，记的是 Boot ROM 要从介质搬走的长度，搬运时把介质开头那 1 KiB 搜索偏移一并计入，再凑整到 4 KiB。mkimage 日志里 Data Size: 438272 Bytes 那一行跟 EVK 的 size 同值，两头互相咬住。plugin 是插件开关，零表示镜像不自带可执行插件，Boot ROM 照 DCD 清单直来直去，因为参考配置里 PLUGIN 分支没开（上一篇 diff 过两份 imximage.cfg，它包在没启用的 #ifdef CONFIG_USE_IMXIMG_PLUGIN 里），所以卡上这一格自然也是零。

start 跟 entry 的关系，咱们把算术摆开。start 是 0x877ff000，entry 是 0x87800000，相差 0x1000。上一篇验过，U-Boot 正文在文件里从 0xC00 偏移起头，前面那 0xC00 是 IVT、boot data、DCD 加上衬垫的头区。链接脚本按 CONFIG_TEXT_BASE=0x87800000 给正文排位，因为取指访存全按这个地址算，所以 Boot ROM 跳进 entry 之前必须保证正文真的落在 0x87800000。源码把这几个数推成一条链，boot data 的 start 等于 entry 减去 0x1000 的加载窗（tools/imximage.c 第 355 行，SD 档加载窗正是 imximage.h 第 40 行 FLASH_LOADSIZE_STANDARD 的 0x1000），这 0x1000 是两段拼起来的，前 0x400 是介质搜索偏移，后 0xC00 是头区。镜像烧进介质时从 0x400 这个搜索点起头，Boot ROM 搬运却从介质 0 偏移整段开始（imximage.c 第 641 到 644 行的注释原话），所以文件字节 0 的 IVT 落在 start 加 0x400，也就是 self（第 345 到 347 行正是这么算的），正文在文件 0xC00、对应介质 0x1000，落在 start 加 0x1000，恰好是 entry。

转储里 start 不是 0x87800000，比 entry 低着 0x1000，这里容易想岔，咱们把岔路的后果推一遍就清楚了。假如 start 真填了 0x87800000，整段搬运窗口跟着上移 0x1000，文件字节 0 的 IVT 落到 0x87800400，正文落到 0x87801000，entry 拨过去的 0x87800000 迎来的是介质最前面那 1 KiB 的旧字节，取指一错就跑飞，板子当场没声。根因是 start 与 entry 管着两件不同的事，start 给的是从介质 0 起算的整段搬运窗口，entry 给的是正文起跑点，中间的 0x1000 由 0x400 介质偏移加 0xC00 头区拼成，谁也替不了谁。

mkimage 的小日志上一节露过 Entry Point，里面还有一行 Load Address: 877ff420，看着像 start，其实不是。mkimage 把 boot data 自己的位置（boot_data_ptr，0x877ff420）叫作 Load Address，IVT 里 0x10 与 0x14 两格各管各的，咱们读日志的时候别拿这一行去对 start。咱们把这棵树自己编出的 mkimage 拿来重打一份，同一份预处理过的 cfgout，同一个 -e 参数，看它能不能一字不差地复现参考产物。复打件咱们放进临时的 /tmp/ivt-probe，目录先建好再打：

```bash
# 主机 ~/imx-forge
mkdir -p /tmp/ivt-probe
cd /tmp/uboot-ref-evk
./tools/mkimage -n u-boot-dtb.cfgout -T imximage -e 0x87800000 -d u-boot-dtb.bin /tmp/ivt-probe/repro.imx
cmp /tmp/ivt-probe/repro.imx /tmp/uboot-ref-evk/u-boot-dtb.imx && echo CMP_IDENTICAL
```

```text
Image Type:   Freescale IMX Boot Image
Image Ver:    2 (i.MX53/6/7 compatible)
Mode:         DCD
Data Size:    438272 Bytes = 428.00 KiB = 0.42 MiB
Load Address: 877ff420
Entry Point:  87800000
CMP_IDENTICAL
```

咱们看重打出来的文件，437248 字节，cmp 报一致，与参考产物逐字节相同。这一手有两个用处：卡上每个字段都是这棵源码树当前逻辑的确定产物，重编多少轮都不漂。哪天咱们怀疑头被工具改坏了，照这个命令复打一份跟手上的产物比对，坏在哪一字节当场现形。

## 四、csf 指针与 HAB 安全启动

0x18 起四个字节在两份转储里都是 0000 0000，咱们把这一格单独拎出来讲。csf 全称 Command Sequence File，签名校验数据块的名字。它背后的机制叫 HAB，全称 High Assurance Boot，NXP 的安全启动机制：csf 非零时指着签名数据的落点，Boot ROM 在跳 entry 之前把那段数据连同镜像交给片上的 HAB 逐条验签，验不过就不交棒，板子停在启动前一步。

咱们的链路没启用 HAB，证据咱们并排三处看：两份转储的 csf 都是零，mkimage 的日志里也没有签名相关行，源码那头 tools/imximage.c 打包无签名镜像时直接写 fhdr_v2->csf = 0（第 357 行）。真要上安全启动，钥匙表、证书链、CSF 文件怎么写，深度超出本卷，NXP 把整套流程收在应用笔记 AN4581《i.MX Secure Boot on HABv4 Supported Devices》里，步骤以 NXP 官网对应版本为准，本篇只负责认出 csf 这一格为零时的含义。

## 五、自己证一遍：拿自家镜像对表

上一篇末尾咱们在自家 out/uboot 上看过头 64 字节，本篇把窗口开到 128，逐字段对表：

```bash
# 主机 ~/imx-forge
xxd -l 128 out/uboot/u-boot-dtb.imx
out/uboot/tools/mkimage -l out/uboot/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 0000 1a00 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
00000040: ffff ffff 020c 4070 ffff ffff 020c 4074  ......@p......@t
00000050: ffff ffff 020c 4078 ffff ffff 020c 407c  ......@x......@|
00000060: ffff ffff 020c 4080 ffff ffff 020e 04b4  ......@.........
00000070: 000c 0000 020e 04ac 0000 0000 020e 027c  ...............|
Image Type:   Freescale IMX Boot Image
Image Ver:    2 (i.MX53/6/7 compatible)
Mode:         DCD
Data Size:    1703936 Bytes = 1664.00 KiB = 1.62 MiB
Load Address: 877ff420
Entry Point:  87800000
```

对表的时候咱们锚几个数。tag 字节 d1、长度两字节 00 20、版本 40，这三个不随配置动，缺哪个字头就不合格。entry 该等于自家 .config 第 183 行 CONFIG_TEXT_BASE 的值，自家产物是 0x87800000。boot data 的 start 比 self 低 0x400、比 entry 低 0x1000，self 比 entry 低 0xC00。dcd_ptr 与 boot_data_ptr 咱们分别拿 self 加 0x2C 与 0x20 去核。csf 呢，没启 HAB 就是零。size 会随配置浮动，咱们看日志里 Data Size: 1703936，换成十六进制正是 0x1a0000，跟 size 字段同值，拿文件尺寸加 0x400 再核一遍 4 KiB 整数倍，两头都通才算对上。

自家板要是换了链接地址或者上了 HAB，锚点咱们跟着 .config 与签名配置换，思路不变。entry 仍由 CONFIG_TEXT_BASE 定下来，start 仍从 entry 往回退 0x1000 的加载窗，self 在 start 之上加 0x400，dcd_ptr 与 boot_data_ptr 照结构偏移从 self 推出来，csf 则看签名配置，没启用就是零。对不上的时候咱们从 CONFIG_TEXT_BASE 与 entry 查起，接着核文件尺寸与 size 的算术，两头都对上而 tag 或版本不对，镜像多半就不是这棵树编出来的。

下一篇咱们从 0x2C 的 d2 01 e8 40 进门。EVK 清单的第一组写入已经露过脸，0x020c4068 配 0xffffffff，把外设时钟全部打开，往后 60 行 DATA 写入咱们逐条对到 imximage.cfg 上，DDR 参数怎么读怎么核，那是下一篇的活儿。

## 继续学习

- [DDR 初始化与镜像头：imximage.cfg 里写了什么](../09_ddr_imxheader.md)：DCD 清单的源头就是这份 cfg 文件，寄存器写入怎么写、DDR 参数怎么配，这一篇铺开。
- [启动链路与偏移](../../flash/04_imx6ull_boot_flow_and_offsets.md)：1 KiB 偏移与整盘布局的完整来历，要细抠就回到这一篇。
