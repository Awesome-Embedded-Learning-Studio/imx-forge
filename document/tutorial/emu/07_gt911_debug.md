# 07 — gt911 触摸排查实录:四个真 bug 的定位之旅

::: info 本节你将学到
- 一个触摸模型从"probe 成功"到"点击可用"之间隔着多少层:GTK→input→I2C→IRQ→input 子系统→evdev→Qt evdevtouch
- 三个一层劈开问题的实测工具:Qt 应用级 eventFilter 探针、内核临时 pr_info、evdev 字节流 hexdump
- 四个真 bug 的完整定位链:寄存器窗口截断、释放语义、手指/报告状态混淆、INT 电平竞争
- 真芯片的语义为什么是模型对齐的黄金标准——"release 也是一份报告"
:::

## 从"probe 成功"到"点击可用"

第六章末尾,gt911 模型的 probe 已经成功——goodix 驱动认了 ID 911、注册了 input2、E2E 断言绿了。但把 Qt 的 lcd_button 跑起来用鼠标点,LCD 窗口里的按钮纹丝不动。这一章就是从那里开始,把中间断掉的每一层找出来。

先铺一遍链路,排查之前心里得有这条线:

```
宿主鼠标(GTK 窗口) → QEMU input 层 → gt911 handler(坐标缩放)
  → gt911_touch() → I2C FIFO 填坐标 + INT 下降沿
  → GPIO1_IO9 → 内核 goodix IRQ → I2C 读 FIFO
  → input 子系统(ABS_MT_POSITION + BTN_TOUCH)
  → evdev /dev/input/event1 → Qt evdevtouch → 按钮命中
```

七层,任何一层断都表现为同一个症状:点不动。这就是为什么需要工具先劈层,而不是逐层猜。

## 三个劈层的工具

第一个工具是 Qt 应用级探针——在 lcd_button 里给 QApplication 装 eventFilter,任何输入事件到达应用都打一行日志(对象类名 + 触摸坐标)。一次运行就能回答"事件到没到应用、坐标对不对"。这招来自一个朴素的想法:与其猜 Qt 收到什么,不如让 Qt 自己招。

第二个是内核临时 pr_info——给 goodix 驱动的 process_events 加一条打印(touch_num + 读到的十个原始字节),跑一次注入,用完回滚重编。它能看到模型和驱动的字节级交接。

第三个是 evdev 字节流 hexdump——在 guest 里 `cat /dev/input/event1 > /tmp/ev` 抓原始流,hexdump 逐字节看 input 子系统到底发了什么事件、什么值。三个工具各劈一层:Qt 层、内核驱动层、input 子系统层。

## Bug 1:寄存器窗口截断——坐标永远为零

探针显示 `TouchBegin pos=(0,0)`:事件到了 Qt,坐标是零。往内核侧打 pr_info,注入 (512,300) 后驱动读到:

```text
touch_num=1 cs=8 d0=81 d1=00 d2=00 d3=00 ... d9=00
```

d0=0x81 状态字节正确(ready + 1 触点),后面九个字节全零——坐标没进 FIFO。回头看模型代码,`gt911_read_reg` 里 `uint8_t buf[GT911_REG_END - GT911_REG_COOR]`,而头文件里 `GT911_REG_END` 写的是 0x8150:0x8150 减 0x814e 等于 **2 字节**。八字节的 contact(track id、x、y、width)被窗口整个截掉,驱动永远只看到合法的状态字节加九个零。

一行修复——窗口扩到 0x8158(状态 + 八字节 contact + key footer)。修复后 hexdump 里 input 事件精确携带 `ABS_MT_POSITION_X=0x0200(512)`、`Y=0x012c(300)`,探针的 `pos=` 也对了。

这个 bug 的教训:pr_info 看原始字节比任何推理都快——"d0 对了但后面全零"一句话就把问题钉在模型侧的窗口边界上。

## Bug 2:释放语义——TouchEnd 永远不来

坐标对了,按钮能点下去,但松开鼠标按钮卡在按下状态。探针日志里只有 Begin 没有 End。

根因在 fill_report:无触摸时状态字节返回全零——在 goodix 协议里这叫"buffer not ready"。驱动读到 not ready 会重试 20ms,然后超时放弃,**什么都不报**。于是 TouchEnd 永远到不了用户态,按钮永远弹不起来;而且被占用的 slot 顺带杀死了后续所有交互(下面的按钮全点不动)。

真 GT911 在松开时上报的是 buffer-ready 加**零个触点**(0x80)——release 本身也是一份合法报告,驱动读到后走零触点路径,正常发出 release。模型对齐这个语义,TouchEnd 立刻出现。

## Bug 3:手指和报告是两个状态

第二个 bug 修完又冒出新的:按住不放,按钮"啪"一下自己弹起来了。探针序列显示 Begin 之后没松手就来了一轮 End。

根因是模型用单一 `pending` 标志同时表示两件事:**手指物理在屏上**(该跨报告存活)和 **FIFO 里有份未读报告**(该被 0x814e 握手清掉)。驱动读完写 0x814e 清握手时,模型把手指状态也一起清了——下一轮读(INT 翻转的重入)读到零触点,报了一个幻影 release。

真芯片是两个独立状态。拆开:`finger_down` 只由 touch/release 改,跨握手存活;`report_ready` 由 touch/release/按住拖动共同置位,由握手清零。顺带把拖动也做对——鼠标按住移动时 motion 事件置 report_ready,产生流式 TouchUpdate。修完的序列:按住→拖→松 = Begin → Update×N → End,中间不再有假 End。

## Bug 4(进行中):INT 电平竞争

最后剩下的是个偶发问题:偶尔松开时 End 丢了,按钮卡住一下。方向已锁定——poll 模式重试循环的间隙里 INT 线的 idle 电平为低,双沿 assert 的两个边沿偶尔与 poll 读竞争,release 的触发被吃掉。纯电平语义(拉低保持到被读)试过不行——idle 就是低,无沿可触发。下一步是给 set_int 加电平打点,把丢失时刻的完整轨迹抓出来。

## 方法论收束

回头看这四个 bug 的定位路径,有一条稳定的流程:先用探针劈层(事件到哪层断了),再用 pr_info 看字节(模型和驱动的交接是否正确),最后用 hexdump 验证 input 事件值。三个工具各管一层,任何"点不动"都能在三步之内钉到具体某一层的具体一行。

而每个 bug 的修复方向都是同一个:**去读真芯片的语义**——窗口有多宽、release 报什么、哪些状态独立存活。模拟器的正确性来自对齐,不是来自想象。
