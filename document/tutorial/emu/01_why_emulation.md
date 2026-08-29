# 01 — 为什么要给开发板找替身:QEMU、Renode 与生态位

::: info 本节你将学到
- CI 的「开机验证」缺口长什么样:咱们亲手读 `ci-build.yml` 里那行唯一的运行时检查
- 「QEMU 上游没有 6ULL 机器」怎么自己验证:几组命令,全程可复现
- `compatible` 字符串、内核机器描述符、QEMU 机器模型三方各管什么,为什么 6UL 机器能跑 6ULL 内核
- Renode 出局的证据从哪来,百问网 2021 年那套方案停在哪里
:::

## CI 的绿灯能保证什么

咱们先干一件有点羞辱性的事:把 CI 的「验证」环节翻出来看。`.github/workflows/ci-build.yml` 里,内核产物在构建完成之后经过的全部运行时检查,就这一行:

```yaml
file out/mainline/linux/arch/arm/boot/zImage | grep -q ARM
```

`file` 认出这是个 ARM 镜像,检查通过;dtb 那边查的是「文件存在」。一个把启动路径改挂的提交——比如设备树里写错一个时钟引用——照样拿绿灯,直到有人烧到板子上对着串口发呆。产物在,和产物能开机,中间隔着一整条启动链,这条链在今天的项目里靠人肉把关。

另一边是没法参与的朋友。驱动教程看到第十章,想试试 `insmod` 的手感,第一道门槛就是几百块的板子加几天快递。咱们在 light-meter 照度摆件项目里做过一版桌面 Mock 后端:传感器数据是假的,Qt 界面和业务代码是真的,主机上直接跑。顺着这个思路往下问一层——应用层能 Mock,内核层拿什么 Mock?答案是假板子:内核、驱动、rootfs 全是真的,底下垫着的 DDR 颗粒和 PHY 芯片,换成一段二进制翻译器。本卷干的就是这件事。

## 「6UL 机器能不能跑 6ULL 内核」,自己验

选型遇到的头一个事实就有点意外:QEMU 上游没有 i.MX6ULL 的机器。这话不用信笔者,敲一条命令就知道:

```console
$ qemu-system-arm -machine help | grep -i imx
imx25-pdk            ARM i.MX25 PDK board (ARM926)
mcimx6ul-evk         Freescale i.MX6UL Evaluation Kit (Cortex-A7)
mcimx7d-sabre        Freescale i.MX7 DUAL SABRE (Cortex-A7)
```

i.MX 全家就三台,离咱们最近的是 `mcimx6ul-evk`——6UL,少一个 L。

那把 6ULL 的内核塞给 6UL 的机器,谁认谁?先看根节点,拿 `fdtget` 把两份 dtb 的 `compatible` 抠出来对比:

```console
$ fdtget imx6ull-aes.dtb / compatible
fsl,imx6ull-14x14-evk fsl,imx6ull
$ fdtget imx6ul-14x14-evk.dtb / compatible
fsl,imx6ul-14x14-evk fsl,imx6ul
```

根节点这层各认各的,6ull 对 6ul,没有交集。再看外设节点,咱们板上的串口:

```console
$ fdtget imx6ull-aes.dtb /soc/bus@2000000/spba-bus@2000000/serial@2020000 compatible
fsl,imx6ul-uart fsl,imx6q-uart
```

`imx6ull.dtsi` 里外设节点的 `compatible` 列表,第一项就是 `fsl,imx6ul-uart`。内核驱动按列表从前往后匹配,`drivers/tty/serial/imx.c` 的设备表里有这一条——外设这层,6ULL 的设备树本来就在按 6UL 的硬件描述自己。

内核那一头呢?启动日志里有现成证据(借第四章某次 panic 的现场一用):

```text
Hardware name: Freescale i.MX6 Ultralite (Device Tree)
```

内核的 ARM 子系统靠机器描述符(`machine_desc`)认识板子,每个描述符带一张 `dt_compat` 兼容串表;mainline 的 imx6ul 描述符,那张表同时收 `fsl,imx6ull-*`。所以内核拿着咱们的 dtb,匹配到 6UL 的描述符,把自己当一台 i.MX6 Ultralite 跑。QEMU 那头更省事,它根本不读 `compatible`:机器模型是焊死的硬件,dtb 只是「内核读的说明书」,说明书里写了不存在的器件,它按自己的家底回应——家底长什么样,第二章整个拿来讲。

外设兼容串和机器描述符都对上,QEMU 又只认自己的固定模型,「6UL 机器 + 6ULL dtb」这条路就通了。CSDN 上有人单独这么跑过;把设备树变体、rootfs 镜像、CI 冒烟整套做齐的,笔者还没搜到第二家。

## Renode:查了仓库才知道是误传

Renode(Antmicro 的开源仿真框架)在调研名单上排第二。它的卖点单独看都很戳教学场景:多板 CAN 互联、Robot Framework 关键字测试、C# 写外设模型还能热加载。笔者一度也以为它有现成的 i.MX6ULL 平台,网上确实这么传。

动手查证的方式很土:把 renode 仓库拉下来,枚举 `platforms/` 目录,再翻 git 历史。结果:`platforms/cpus/` 下 120 个文件,imx 系只有 i.MX8M Plus 和 RT 系列 MCU;历史挖到 2017 年,`imx6ull.repl` 从未存在过。流传说法的出处也找到了——Antmicro Designer 的商业服务目录页,那是「付费可定制」的货架清单,和开源版能跑什么,两回事。真要走这条路,就得从 GICv2 加 Cortex-A7 开始自建整板平台,外设还缺 EPIT、SNVS、eLCDIF、SAI 一大片,估两到四周,而且 6ULL 在 Renode 社区是无人区,遇坑没得搜。完整的证据链(目录枚举、issue 区搜索为零、官方 supported-boards 页)收在开发笔记《QEMU 板级模拟调研》里,结论:Renode 不做主轴,留到哪天要做 CAN 双板实验再请回来。

至于中文教学圈的同行:正点原子(咱们板子的原型厂)和野火官方都没有仿真方案,官网上给的是编译虚拟机。做得最深的是百问网(韦东山团队),他们的 qemu fork 给 6UL 加了假 LCD(往窗口贴板子照片,LED 亮灭画在照片上)、GPIO 按键、固定地址假寄存器式触摸。2021 年的作品:内核 4.9.88,QEMU 4.x,不走 U-Boot,音频 CAN PWM ADC 全空。它证明教学向模拟这条河能蹚,也把它停下的地方标了出来。咱们从那里接着走:内核换 mainline v7.1,QEMU 用发行版原版不维护 fork,再把验证链挂进 CI。

::: tip 下一章
方案定了,下一章咱们把 `mcimx6ul-evk` 拆开看家底——用一个 QEMU 自带的监控命令,五分钟把「这台机器里什么是真的、什么是纸糊的、哪里是空气」全部打印出来。这几条命令,以后拿到任何陌生 QEMU 机器都照样能用。
:::
