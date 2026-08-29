# 06 — 外设模型群:从传感器到触摸屏的自建之路

::: info 本节你将学到
- 一个教学级 QEMU 外设模型的最小骨架:Type 注册、I2C/SPI slave 类、QOM 可注入属性
- 传感器数据的三层喂食:静态默认、精确注入、噪声活性
- 自建 QEMU 的交付形态:submodule 钉上游 + 编号 patch 序列 + pin-apply 构建路径
- 本板七个自建模型各自的判据与实测结果
:::

## 为什么要自建外设模型

02 章的家底盘点说过:QEMU 上游给了 UART/I2C/SPI 控制器/USDHC/FEC/eLCDIF 这些真模型,但板上的**器件**(传感器、触摸、codec)一个都没有——教学树的 I2C/SPI 总线上是空的,驱动 probe 只能超时。要让驱动章节的闭环在模拟器里真跑,就得把器件补上。

模型全部走 `patches/qemu/` 编号序列(submodule 钉 v11.1.0,build-qemu.sh 自动 reset-apply),交付形态在 05 章的工具链上又加了一层:QEMU 组件豁免了仓库的"单 rolled patch"约定——十六个补丁的序列压成一个就再也没法 rebase 了。

## 模型骨架:以 ap3216c 为例

一个 I2C 器件模型的最小骨架约三百行:`I2CSlaveClass` 的 event/send/recv 三个回调实现寄存器语义,`TypeInfo` 注册,QOM 属性暴露可注入的数据。ap3216c(光照/接近传感器)的寄存器布局直接对着咱们 imxaes 驱动的解析代码写——IR 十位、ALS 十六位小端、PS 十位,位错一位驱动的换算就全错。

数据怎么喂,分三层。第一层是 reset 时给合理静态默认(室内光照水平);第二层是精确注入——`qom-set` 改 QOM 属性,是干净的基准值,CI 断言用;第三层是噪声活性——`noise` 属性(默认开)让数据寄存器每次读带 ±2% 抖动,重复读像真传感器在呼吸,而注入的基准不被污染。教学时三者配合:默认读活数据,课堂"手电筒"用注入,CI 用 `noise false` 锁基准。

同样的骨架复制出 icm20608(SPI,bit7 地址位组帧,ECSPI 三十二位 FIFO 字带前导 pad 的坑要用地址字节自识别化解)和 gt911(十六位寄存器寻址,第 07 章主角)。wm8960 是控制面模型——codec 驱动 probe 零 I2C 读,寄存器读写回环让 DAPM 面可探索,音频数据通路(出声)有意不模拟:fsl_sai 无条件注册 dmaengine PCM,SDMA 是要上传微码的 DSP 核,寄存器模型伪造不出诚实的 DMA。

## 非器件模型:PWM 和注入命令

PWM(hw/misc)是另一类:纯寄存器存储加可观测属性——pwm-imx27 驱动 apply 只写不回读,存储即过 probe;`enabled/duty/period` 属性让"背光亮度 60%"从 QMP 可见。`gpio_set` 是 monitor 命令(patch 0004):驱动 GPIO 输入线,按键/中断类驱动的教学不再依赖硬件。FlexCAN 是二十行接线——模型上游已有,只差接到 6UL SoC,参照 sabrelite 范式。

## 实测判据表

| 模型 | 判据 | 实测 |
|---|---|---|
| PWM×8 | `/sys/class/pwm/pwmchip0` + backlight | PASS |
| gpio_set | guest devmem 读 PSR 位翻转 | PASS |
| ap3216c | `i2cget` 读回注入值±噪声 | PASS |
| icm20608 | imxaes 驱动 insmod probe 成功 | PASS(数据字节对齐在控制器层跟进) |
| gt911 | goodix ID 911 + 触摸事件闭环 | PASS(详见 07 章) |
| wm8960 | i2cget 0x1a 应答 | PASS |
| FlexCAN | can0 netdev 注册 | PASS |

E2E 脚本把这张表固化成十五项断言,`scripts/qemu_helper/e2e-test.sh` 一键体检。

## 补丁序列的交付纪律

十六个 patch 按主题独立编号:D 档五桩(0001)、FlexCAN 接线(0002)、PWM(0003)、gpio_set(0004)、传感器三件(0005-0007)、gt911+wm8960(0008)、INT 修复系列(0009-0016)。每个 patch 的 commit message 写清验证方法和已知遗留——回溯时 patch 序列本身就是开发日志。
