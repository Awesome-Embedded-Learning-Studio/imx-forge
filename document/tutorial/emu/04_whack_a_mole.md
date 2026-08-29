# 04 — 如同打地鼠一般的八连挂:从串口死寂到 buildroot login

::: info 本节你将学到
- 「串口完全没输出」时内核死在哪:`console=ttymxc0` 为什么要等驱动 probe 才生效,死在更早的 panic 为什么看不见
- `earlycon` 的机制:它凭什么绕过整个驱动框架直接开口
- 一份 external abort 报告的完整读法:`PC is at` / `Register rN information` / `*pgd *pte` 三路互证,手算出物理地址
- 打地鼠的正确姿势:`fdtput` 快改快验,结论固化成设备树变体;变体的写法、label 陷阱、cpp 管线
:::

## 第一枪:什么都没有

万事俱备。zImage、`imx6ull-aes.dtb`、256MB 的 rootfs 镜像,命令敲下去:

```bash
qemu-system-arm -M mcimx6ul-evk -m 512M \
  -kernel zImage -dtb imx6ull-aes.dtb \
  -append "console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw" \
  -drive file=rootfs.ext4,if=sd,index=1,format=raw -nographic
```

串口一片死寂。连「Booting Linux」都没有,超时杀掉后日志文件里只剩 QEMU 自己的两行网卡警告。笔者当时先怀疑 dtb,换上游的 `imx6ul-14x14-evk.dtb`,死寂;再怀疑 SD 卡和网络,全拔了,死寂;参数减到最少,还是死寂。

死寂的根源得从 `console=ttymxc0` 说起。这个参数指定的控制台,要等内核里 imx-serial 驱动 probe 完 ttymxc0 这个设备才生效;驱动 probe 排在设备树展开、平台设备注册之后,时间上相当晚。内核在更早的阶段 panic 的话——比如设备树展开时某个驱动炸了——panic 信息没有可用的输出通道,printk 全憋在缓冲区里,跟着内核一起沉默。所以死寂的真相往往是:内核死了,尸体躺在咱们看不见的地方。

## earlycon:给串口装个起搏器

破局的关键词是 `earlycon`,加进 `-append` 就行。它走的是另一条路:内核在极早期(`setup_earlycon`)读设备树 `chosen` 节点里的 `stdout-path`,拿到 UART 的物理地址,绑一个「早期控制台」驱动,用最原始的「往寄存器写一个字节」的方式输出。咱们的 dtb 里这条路径是现成的:

```console
$ fdtget imx6ull-aes.dtb /chosen stdout-path
/soc/bus@2000000/spba-bus@2000000/serial@2020000
```

它不依赖任何驱动 probe,QEMU 的 UART 真模型接得住这种裸写。加上之后串口立刻开口,前几行是好消息,最后一行是死刑判决:

```text
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 7.1.0-dirty (charliechen@Charliechen) ...
[    0.000000] OF: fdt: Machine model: Awesome Embedded Studio IMX6ULL (i.mx NXP)
[    0.000000] earlycon: ec_imx6q0 at MMIO 0x02020000 (options '')
[    0.000000] printk: legacy bootconsole [ec_imx6q0] enabled
...
[    0.300767] Unhandled fault: external abort on non-linefetch (0x008) at 0xe0870018
[    0.301051] [e0870018] *pgd=8201d811, *pte=021b0653, *ppte=021b0453
[    0.303615] PC is at imx_mmdc_probe+0x80/0x31c
```

内核起来了、机器认对了(还是咱们的 AES 板)、earlycon 挂上了——然后 0.3 秒处还是挂了。

## 一份 panic 报告的完整读法

上面这三行死因报告,信息密度很高,一行一行拆。

第一行报告异常类型和虚拟地址:`external abort`(总线级错误,MMU 页表查询是成功的,炸在总线事务上)、`0x008` 是 ARM 的 fault status 编码、出事的虚拟地址 `0xe0870018`。这个地址落在 0xe0000000 起的 vmalloc 区——`ioremap` 把物理寄存器映射进来的地方,这个范围本身就提示「有驱动刚映射了某个外设」。

第二行是页表现场,可以手算出物理地址。`*pte=021b0653`,pte 的高 20 位是物理页帧号,低 12 位是属性:`0x021b0653 & 0xFFFFF000 = 0x021b0000`。再看虚拟地址的低 12 位,页内偏移 `0x018`。两者一拼,出事的物理地址就是 `0x021b0018`。第二章的 mtree 地图上,这个地址连 region 都没有——空气。QEMU 那边开着 `-d guest_errors` 的话,它会从自己的视角对同一事件做笔录:`Invalid read at addr 0x21B0018, size 4, region '(null)', reason: rejected`。两个仪器报同一个地址,这笔账就对上了。

第三行 `PC is at imx_mmdc_probe+0x80/0x31c` 给出案发函数。往下翻还有寄存器现场,其中两行特别有用:

```text
Register r0 information: 0-page vmalloc region starting at 0xe0870000
                          allocated at imx_mmdc_probe+0x78/0x31c
Register r5 information: 0-page vmalloc region starting at 0xe0870000
                          allocated at imx_mmdc_probe+0x78/0x31c
```

内核自己交代了:这个 vmalloc 区是 `imx_mmdc_probe` 在偏移 +0x78 处 `ioremap` 的。三路证据——PC 定函数、寄存器信息定映射来源、pte 手算定物理地址——合在一起,案情清楚了:MMDC 驱动 probe 时 `readl` 了 `0x21b0018`,总线上没有这个地址,external abort,没人兜底。

内核源码把这最后一环闭上。`arch/arm/mach-imx/mmdc.c:543` 起:

```c
static int imx_mmdc_probe(struct platform_device *pdev)
{
    ...
    mmdc_base = of_iomap(np, 0);
    WARN_ON(!mmdc_base);

    reg = mmdc_base + MMDC_MDMISC;
    /* Get ddr type */
    val = readl_relaxed(reg);
```

`MMDC_MDMISC` 的偏移就是 0x18,和手算的物理地址 `0x021b0000 + 0x18` 分毫不差。驱动在真硬件上毫无问题——读 DDR 类型、配自动省电,都是分内事;QEMU 8.2 的 0x21b0000 是空气,一读就炸。顺带说一句,2026 年 8 月 QEMU 那个十补丁系列里专门有一片给 MMDC 建模,上游对这坑心里有数。

还有一个容易带偏的细节:`LR is at set_ptes+0x40/0x6c`。LR 记录「从哪儿跳来」,但内联和尾调用会让它指向八竿子打不着的地方——这里它指回页表设置的尾巴,纯属编译器布局的把戏。定位案发点以 PC 为准,寄存器信息行做旁证,LR 只能当八卦听。

## 打地鼠:七种死法

mmdc 关掉(下一节讲怎么关),重启,0.49 秒死在 `imx_rngc_probe`——硬件随机数发生器,又一个空洞。再关,0.56 秒 `mxsfb_crtc_atomic_enable`,LCD 控制器,显示管线的 atomic 启用流程第一笔寄存器操作就落空。再关,0.63 秒 `fsl_qspi_default_setup`。再关,0.73 秒,这次的报告有点特殊:

```text
[    0.739191] PC is at regmap_mmio_write32le+0x34/0x40
[    0.735375] Unhandled fault: external abort on non-linefetch (0x808) at 0xe0a68008
```

PC 落在 `regmap_mmio_write32le`——regmap 框架的通用写函数,函数名里看不出是哪个设备。这种时候地址是唯一的身份证:`*pte` 手算出物理页 `0x21cc000`,到 dtsi 里 grep 这个地址,是 PXP(像素处理器)。寄存器信息里 `Register r3: vmalloc region ... allocated at __devm_ioremap_resource` 佐证了「某外设刚被 ioremap」,设备名还是得靠地址反查。再关,1.24 秒 `stmp_reset_block`——i.MX 上经典的「发软复位、轮询等自清」套路,调用者是 DCP 加密协处理器的 probe。再关,0.67 秒 `imx_ocotp_probe`,熔丝盒。

七只地鼠,死法同源(external abort),但每只都教了一点新东西:哪个驱动在 probe 阶段裸读寄存器、通用层函数怎么靠地址反查设备、轮询复位模式为什么必死。而内核的设备树展开按节点挨个 probe,咱们 dtsi 里 enable 的节点排着队一只只撞墙——不知道还剩几只,只能一只只敲。

第八次启动,`buildroot login:` 出来了。但日志里还躺着最后一个 abort,案发地点有点意外:

```text
[   11.657817] CPU: 0 UID: 0 PID: 35 Comm: kworker/u4:2 Not tainted 7.1.0-dirty
[   11.658725] Workqueue: events_unbound deferred_probe_work_func
[   11.659893] PC is at usbmisc_imx6q_init+0x2c/0x138
[   11.653032] [e0879800] *pgd=8201d811, *pte=02184653, *ppte=02184453
```

pte 手算:物理页 0x2184000,偏移 0x800——usbmisc 那块杂项寄存器。第二章埋过的「容器内的缝」就是它:0x2184000 一带 chipidea/ehci 是真模型,但模型只覆盖控制器自己的子 region,基址 +0x800 的 NXP 私货落在缝里,访问被拒。真正的新知识点在头两行:案发上下文是 PID 35 的 kworker,跑在 `deferred_probe_work_func` 工作队列里——external abort 杀死的是当前执行流,PID 1 里炸是整机 panic,worker 线程里炸就只死这个线程,所以这次 login 照样出来了。系统活着,咱们还是把 usb 三件套(usbotg1/2、usbmisc)全关了:留一个随时杀 kworker 的坑在,后面任何一个 deferred probe 都可能踩上去。

第九次启动,干净。`grep -cE 'Internal error|Kernel panic'` 数出来 0,剩下的全是软失败——I2C timeout、FlexCAN `-110`、温度传感器 deferred——第二章预告过的那批「吵」,等器件模型进场再收拾。

## 从补丁到变体

打地鼠阶段,笔者改 dtb 用的是 `fdtput`,在副本上直接改二进制节点:

```console
$ cp imx6ull-aes.dtb /tmp/demo.dtb
$ fdtput -t s /tmp/demo.dtb /soc/bus@2100000/memory-controller@21b0000 status disabled
$ fdtget /tmp/demo.dtb /soc/bus@2100000/memory-controller@21b0000 status
disabled
```

改完 `fdtget` 一验,再拿去启动,几十秒一轮,迭代很快。但它改的是产物,源码层面的结论没有沉淀,换台机器从头再来。收尾时把九轮的结论固化成一份设备树源文件 `scripts/qemu_helper/imx6ull-aes-qemu.dts`,骨架长这样:

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"     // 真机板级配置,全量继承

/ {
    model = "Awesome Embedded Studio IMX6ULL (QEMU mcimx6ul-evk)";
};

&{/soc/bus@2100000/memory-controller@21b0000} { status = "disabled"; };  // mmdc
&dcp  { status = "disabled"; };
&rngb { status = "disabled"; };
/* ...lcdif、pxp、csi、tsc、ocotp、qspi、usbotg1/2、usbmisc,每个都注明 8.2/11.1 的状态 */
```

设计思路一句话:继承全部,只关差异。LED、蜂鸣器、按键、I2C 传感器、ECSPI3、USDHC、CAN、SAI 这些真机配置一行不落从 `imx6ull-aes.dtsi` 继承——模拟器里「存在」的外设和真机叙事保持一致,QEMU 缺的那 12 个节点明确关掉,每个节点旁边注明它在 QEMU 8.2 和 11.1 里各是什么状态(比如 lcdif 在 8.2 是桩、11.1 是真模型,升级后从清单里删掉就能出画面)。dtsi 以后改动,变体重编一次自动跟上,不存在两份板级配置各自漂移。

mmdc 那行为什么写得这么长?因为它在 `imx6ul.dtsi` 里没有 label。笔者一开始写的是 `&mmdc { status = "disabled"; };`,dtc 直接拒绝:

```text
Error: /tmp/t.dts:3.1-6 Label or path mmdc not found
FATAL ERROR: Syntax error parsing input tree
```

翻开 dtsi 一看,节点定义就是光秃秃的 `memory-controller@21b0000 {`(第 989 行),没起名字。没有 label,只能用完整路径引用:`&{/soc/bus@2100000/memory-controller@21b0000}`。

还有一道编译工序容易漏:dts 里的 `#include` 要过 C 预处理器,内核构建里这活由 `scripts/Makefile.lib` 干,咱们自己编就得手动 `cpp -x assembler-with-cpp`,并且 `-I` 要指到 `arch/arm/boot/dts/nxp/imx/`——v7.1 内核把 i.MX 的 dtsi 全挪进了这个子目录,笔者第一版脚本就栽在这。dtc 也有讲究:用内核树里编出来的那份(`out/mainline/linux/scripts/dtc/dtc`),它带着内核的补丁(地址单元格检查之类),系统自带的 dtc 对某些内核 dtsi 会挑刺。

最后是纪律问题。仓库的设备树工作流要求改共享 `imx6ull-aes.dtsi` 时三处同步(patch、子模块、`driver/device_tree/` 副本)。变体不进内核树,不在三处之列;但它 include 了 dtsi,dtsi 一变它就得重编。靠人记这事迟早出事,第五章把新鲜度检查交给脚本。

回头看,这九轮有一条稳定的流程:串口死寂,先加 `earlycon`;拿到 panic,PC 定函数、寄存器信息找映射来源、pte 手算物理地址对 dtsi;`fdtput` 快改验证;结论固化回变体。流程里还欠一件本来能省下整晚的事:第二章那条 `info mtree`,打第一只地鼠之前跑一遍,八个空洞全部提前现形。笔者是打完之后才把它补进流程的——倒过来写给咱们读者,这就是第二章排在实战章前面的原因。

::: tip 下一章
启动链通了、变体固化了,最后一章把这一切封装成三条命令,外带一套防陈旧的自动重建——改了 dtsi 忘了重编、拿着旧镜像启动还以为改坏了,这类哑巴亏交给脚本堵死。
:::
