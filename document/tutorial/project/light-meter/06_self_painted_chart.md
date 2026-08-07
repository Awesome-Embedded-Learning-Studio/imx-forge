---
title: 自绘 ChartView + 息屏遮罩
---

# 自绘 ChartView:为什么这条折线要自己画

::: info 本节你将学到
- 为什么 light-meter 不用 Qt Charts,宁可自己用 QPainter 画一条折线,以及"库就在 rootfs 里,但不一定非得用"这种判断
- QPainter 自绘的基本套路:`paintEvent` 在哪触发、`QPainter` 怎么用、屏幕坐标系为什么 Y 轴朝下
- 一个**真正的**环形缓冲怎么写,`m_head`/`m_count` 那套,和上一章 `m_history` 那个 O(n) 截断的区别
- `update()` 的真相:它刷新的是整个控件,不是某个矩形,以及为什么 light-meter 这样写也不卡
- 息屏遮罩 `BreathingOverlay`:纯 `paintEvent` 怎么写,以及那个 `M_PI` 的跨平台坑
:::

::: tip 前置知识
- 第 05 章,Qt 的事件循环、QWidget、信号槽,这一章的 ChartView 是个 QWidget 子类
:::

## 为什么这条折线要自己画

你大概知道 Qt 有个 Qt Charts 模块,专门画各种图表,折线、饼图、柱状,开箱即用。而且我们的 rootfs 里其实编了它(第 10 章上板时你会看到 buildroot 的 qt6 fragment 开了 `QT6CHARTS`)。那 light-meter 为什么不用它,反而自己用 `QPainter` 画一条折线,多写一百多行代码。

这事得从 i.MX6ULL 没有 GPU 说起,但不是说 Qt Charts 在没 GPU 的板子上完全跑不了。Qt Charts 的 widgets 版本理论上是能用软件光栅渲染跑起来的,它不强制要 OpenGL。真正因为没 GPU 而被否决的是 EGLFS 和 Qt Quick 那套走 OpenGL 的渲染路径,那是 buildroot/11 那篇讲的事,Qt Charts 不在这个硬否决的范围里。

所以 light-meter 还是自己画,是个主动的工程取舍,不是被逼的。原因说穿了也朴素。这个折线的需求其实就那么大点,一个 150 点的滚动窗口、一条线、一个阈值虚线、一个当前点,Qt Charts 那套带坐标轴、图例、动画、主题的完整框架对它来说是杀鸡用牛刀,引入它你就得跟一整套它定义的对象模型打交道。更现实的是样式控制,Catppuccin 配色、lux 跌破阈值时折线和当前点翻红、当前点的呼吸感,这些细节自己画一目了然,改 Qt Charts 反而别扭。再加上自绘只依赖 `QPainter`,走的是软件光栅引擎,直接 blit 到 framebuffer,在 no-GPU 的 linuxfb 上稳得一批,没有"某个平台插件加载失败"那种玄学隐患。顺带,应用层不 link Qt Charts,二进制更小、启动也更快。

把上面这段念叨念叨,其实就一句话:库存在不等于你得用。一个简单需求,自己写一百行可控、轻量、稳;引入一个大库省下那一百行,代价是跟它的整套抽象绑死,而且往往为了用它还得按它的方式组织代码。哪条划算,看需求复杂度,light-meter 这种简单折线,自己画划算。

## QPainter 自绘的基本套路

Qt 里所有自绘都遵循一个套路,控件收到绘制事件时,`paintEvent` 被调,你在里面创建一个 `QPainter`、用它的 API 画,函数返回画面就上屏。`QPainter` 是那支"画笔",它有 `drawLine`、`drawRect`、`drawEllipse`、`drawText`、`fillRect` 这些方法,你设好画笔 `QPen`(描边颜色、线宽、线型)和画刷 `QBrush`(填充颜色),它就按你说的画。

有一个坐标系的事必须先讲,不然你画出来的东西是反的。QWidget 的坐标系,原点在**左上角**,X 轴向右增长,Y 轴**向下**增长。这跟数学里 Y 轴向上相反。所以画折线图时,lux 越大你希望点越靠上,但屏幕上"靠上"是 Y 值小,这就需要一个映射把 lux 翻一下。`ChartView` 里 `mappedY` 就是干这个的,等会儿逐行读。

一个最小的 paintEvent 长这样,画一条对角线:

```cpp
void MyWidget::paintEvent(QPaintEvent*) {
    QPainter p(this);                 // 在这个控件上作画
    p.setPen(QPen(Qt::green, 2));     // 绿色、2 像素宽的画笔
    p.drawLine(0, 0, width(), height());
}
```

`QPainter p(this)` 这一句把 painter 绑定到当前控件,它的绘制坐标都是相对于这个控件的左上角。至于什么时候 `paintEvent` 被调,无外乎两种。一种是 Qt 觉得这个控件需要重绘了,比如窗口刚从被遮挡中露出来。另一种是你主动调了 `update()`,这是告诉 Qt"我这个控件内容变了,麻烦安排一次重绘"。`update()` 不是立刻重绘,它是把一个重绘请求排进事件队列,Qt 会在下一轮事件循环里合并多个 `update()` 一起重绘,这样你一帧里多次改数据只触发一次 paint。

## 真环形缓冲:m_head 加 m_count

上一章我们说 `m_history` 那个 `QVector` 用 `remove` 截断来限内存,是 O(n) 的,不是真环形。这一章的 `ChartView` 才是真正的环形缓冲,而且它用环形是有道理的,因为折线图每帧都要把整个缓冲从头读到尾画出来,读取必须快,不能像 `QVector::remove` 那样每次写入都搬移。

环形缓冲的核心是两个游标加一个定长数组。数组 `m_buf` 固定大小 `kCapacity`(150,正好 30 秒的窗口、200ms 一个点),`m_head` 是"下一个该写入的位置",`m_count` 是"目前存了多少个有效点"(不超过 kCapacity)。写入一个新值:

```cpp
void ChartView::pushSample(float lux) {
    m_buf[m_head] = lux;
    m_head = (m_head + 1) % kCapacity;
    if (m_count < kCapacity) ++m_count;
    update();
}
```

`m_buf[m_head] = lux` 写到当前位置,`m_head = (m_head+1) % kCapacity` 把写指针往前推一格、到尾了绕回头,这就是"环"的来源,`% kCapacity` 让指针在 0 到 149 之间循环。前 150 次写入,`m_count` 一路加到 150,之后数组满了,新的写入会覆盖最老的点,`m_count` 就不再加,永远停在 150。没有搬移,写入是 O(1),这是它比 `QVector::remove` 强的地方。

读取时,因为数据是绕着环写的,"最老的点"不在下标 0 而在 `m_head` 当前位置(满了的话),最新的点是 `m_head-1`。paintEvent 里要按时间从老到新遍历,下标算术是这样:

```cpp
const int idx = (m_head - n + i + kCapacity) % kCapacity;
```

`i` 从 0 到 n-1,算出来的 `idx` 就是从最老到最新地走遍有效点。这个 `(m_head - n + i + kCapacity) % kCapacity` 的写法是环形缓冲读取的标准技巧,加一个 `kCapacity` 是为了防止 `m_head - n` 变负数(取模在 C++ 里对负数的行为不直观),先把正数加回来再模。这套下标算术你写两遍就会熟,是环形缓冲的肌肉记忆。

## mappedY:把 lux 映射到像素

数据是 lux 浮点数,屏幕是像素坐标,两者之间要有一个映射。`mappedY` 干这件事:

```cpp
float ChartView::mappedY(float lux, int top, int height) const {
    const double v = (lux < 0.0) ? 0.0 : (lux > m_yMax ? double(m_yMax) : double(lux));
    return float(top + height - int(v / m_yMax * height));
}
```

先 `clamp` 一下,把 lux 限制在 0 到 `m_yMax`(800)之间,防止异常值画出绘图区。然后 `v / m_yMax * height` 算出这个值占绘图区高度的比例,转成像素偏移。关键是最后那个 `top + height - ...`,因为屏幕 Y 向下、我们想要 lux 越大越靠上,所以用绘图区底部的 Y(`top + height`)减去偏移,把方向翻过来。lux=0 映射到 `top+height`(底部),lux=yMax 映射到 `top`(顶部)。这个"减一下翻 Y 轴"是所有自己画图表的代码都会有的套路。

## update() 的真相

代码里那个注释差点误导人,这一步值得多花点笔墨讲清楚。你看 `pushSample` 最后一行 `update();`,旁边注释写着"只刷自身矩形"。这句话描述的是**效果**,但它描述得容易让人以为机制是"只重绘某个矩形"。实际上 `QWidget::update()` 不带参数时,调度的是**整个控件**的重绘,不是某个矩形。那个"只刷自身矩形"的效果,真正的来源是 `ChartView` 是一个**独立的小 QWidget**,它的"整个控件"本来就只有右栏那块折线区域那么大,所以重绘它的整个控件,等价于只刷那一小块矩形。

事情为什么要讲这么细。因为如果你把这个 `update()` 抄到一个**大控件**里,比如一个铺满整个窗口的 widget,那你每次 `pushSample` 都会触发整个大控件重绘,性能就崩了。light-meter 这么写没事,是因为 ChartView 被设计成一个独立的小 widget,它的"全部"就是那条折线,重绘整个它成本很低。真正能做矩形级局部刷新的 API 是 `update(QRect)`,但 light-meter 没用,因为它不需要,小控件全量重绘已经够快。

说白了,自绘控件的性能,一半取决于你画得简不简,另一半取决于你**把控件切得够小**。把高频刷新的区域单独做成一个小 QWidget,它的全量重绘就天然只影响那一小块,这比在一个大 widget 里费劲算 dirty rect 简单也可靠。light-meter 把折线单独抽成 ChartView,就是这个道理。

## 逐行读 paintEvent

`paintEvent` 是 ChartView 最长的方法,但逻辑是线性的,我们顺着读。开头:

```cpp
QPainter p(this);
p.setRenderHint(QPainter::Antialiasing, true);
p.fillRect(rect(), QColor(kBg));
```

建 painter,开抗锯齿(折线会平滑很多,代价是一点 CPU,对这个刷新量完全负担得起),填背景色。

接着算绘图区,`rect().adjusted(40, 12, -12, -28)`,左边让出 40 像素给 Y 轴刻度文字,上下右各留点边,得到真正画折线的矩形 `plot`。

然后画 Y 轴网格和刻度,0、200、400、600、800 各一条横向虚线加一个数字标签:

```cpp
for (int v = 0; v <= 800; v += 200) {
    const int y = int(mappedY(float(v), plot.top(), plot.height()));
    p.setPen(QPen(QColor(kGridLine), 1, Qt::DotLine));
    p.drawLine(plot.left(), y, plot.right(), y);
    p.setPen(QColor(kAxisText));
    p.drawText(QRect(plot.left() - 38, y - 8, 34, 16),
               Qt::AlignRight | Qt::AlignVCenter, QString::number(v));
}
```

阈值虚线同理,`m_threshold` 那个位置画一条 `Qt::DashLine` 长虚线,标个"阈值 N"。

折线本体用 `QPainterPath` 拼,从最老到最新逐个 `lineTo`,同时拼一个"曲线下面积"的 path 用于半透明填充。x 坐标的算法让最新点恒在最右、老数据从右往左滚:

```cpp
const double x = plot.left()
                 + double(i + (kCapacity - n)) / (kCapacity - 1) * plot.width();
```

`(kCapacity - n)` 那一项是关键,数据还没填满 150 个点时(n<kCapacity),它让最早的点从左边合适的位置起,而不是总从最左起,这样折线是"从右向左填满"的视觉效果。

颜色根据**最新点**的 lux 决定,lux 低于阈值整条线和当前点都翻红,否则绿色:

```cpp
const float lastLux = m_buf[(m_head - 1 + kCapacity) % kCapacity];
const QColor lineColor = (lastLux < m_threshold) ? QColor(kRed) : QColor(kGreen);
```

最后画当前点,一个半径 4.5 的实心圆,在最新点位置。X 轴底下标 `-30s` 和 `now`。整个 paintEvent 就是这么个流程,没有花活。

## BreathingOverlay:纯 paintEvent 加 M_PI 的坑

息屏遮罩 `BreathingOverlay` 比 ChartView 简单得多,全屏黑底加中央一个慢呼吸的圆点。它的实现几乎只有 `paintEvent`:

```cpp
void BreathingOverlay::paintEvent(QPaintEvent* /*event*/) {
    QPainter p(this);
    p.fillRect(rect(), QColor(0, 0, 0));

    constexpr float kTwoPi = 6.28318530717958647692f;   // 不用非标准 M_PI(MSVC 下未定义)
    const float a = (std::sin(m_t * kTwoPi) + 1.0f) * 0.5f;   // 0..1
    const int r = int(5 + 7 * a);
    const int alpha = int(70 + 185 * a);

    p.setBrush(QColor(180, 200, 255, alpha));
    p.setPen(Qt::NoPen);
    p.drawEllipse(rect().center(), r, r);
}
```

`m_t` 是个随时间推进的相位,`MainWindow` 的呼吸定时器每个 tick 给它加一点。`(sin + 1) * 0.5` 把正弦的 -1 到 1 映射到 0 到 1,用这个 `a` 同时调圆点半径和透明度,于是圆点就慢慢变大变亮、再变小变暗,周期性"呼吸"。`(sin+1)*0.5` 这个把正弦塞进 0 到 1 的小技巧,凡是周期性起伏的动画都吃这一套,记住它没坏处。

这里有个跨平台的坑值得专门讲。你看那行注释"不用非标准 M_PI(MSVC 下未定义)"。很多人写涉及圆周率的代码,本能写 `M_PI`,这个宏在 `<cmath>` 里。问题是 `M_PI` 压根不是 C/C++ 标准的一部分,它是 POSIX 的扩展,GCC 和 Clang 默认提供,但 MSVC 默认不定义它,你得在 include 前定义 `_USE_MATH_DEFINES` 才有。所以同一份用了 `M_PI` 的代码,在 Linux 上编得好好的,拿到 Windows MSVC 上就报"`M_PI` 未定义"。light-meter 的办法是干脆自己写一个 `constexpr float kTwoPi = 6.2831...`,把圆周率的两倍直接写死成字面量,不依赖任何平台宏,哪个编译器都认。这事儿踩一次就长记性,跨平台 C++ 别图省事用非标准扩展。

还有几个小点。`BreathingOverlay` **没有 `Q_OBJECT` 宏**,因为它不发出也不接收信号槽,纯 paintEvent 就够了,省掉 moc 那套。它的构造函数里 `setAttribute(Qt::WA_NoSystemBackground, true)` 让它不画系统背景、避免闪一下白。它自己不 `raise`、不设几何,这些是 `MainWindow` 在进息屏态时干的,`m_overlay->setGeometry(rect())` 把它铺满整个窗口、`raise()` 顶到最上层、`show()` 显示,出息屏态时 `hide()`。

## 上手:看折线滚 60 秒,再踩一下 M_PI 的坑

跑起 light-meter 的 Mock 配置,盯着折线看 60 秒。它应该平滑地滚动,30 秒后填满整个绘图区,早期数据从右边一路滚到左边消失,永不越界。lux 跌破阈值时(拖阈值滑杆到 700 强制触发),整条线和当前点翻红。这一步过了,环形缓冲和颜色翻转就算都对上了。

第二个小实验,把 `breathing_overlay.cpp` 里那个 `kTwoPi` 临时换成 `M_PI * 2`,在 Linux 上能编,但拿到 Windows MSVC 上(如果你有环境)就会报 `M_PI` 未定义。改回 `kTwoPi` 就好。没 Windows 环境也没关系,记住这个坑就行。

## 这一章的坑

先说最大的那个,就是上面讲过的,误以为 `update()` 是矩形级局部刷新。它是整个控件重绘,light-meter 不卡是因为 ChartView 小。你把高频自绘放在一个大 widget 里,就得自己用 `update(QRect)` 或更精细的脏区管理。

然后是 `QPainter` 的画笔画刷状态会"渗透"。你 `setPen` 画了一个东西,忘了复位,下一段绘制就接着用上一段的 pen。`ChartView` 里每画一种东西都显式 `setPen`/`setBrush`,这是个好习惯,别依赖默认状态。

抗锯齿在大面积填充上很贵。`setRenderHint(Antialiasing)` 开着画折线和圆点没事,但你要是拿它 `fillRect` 整个背景就大可不必,大面积填色抗锯齿帮不上忙还费 CPU。ChartView 是先 `fillRect` 背景(此时还没开抗锯齿的事,fillRect 本身不走抗锯齿路径),再开抗锯齿画线。

环形缓冲的下标算术差一也容易翻车。`(m_head - n + i + kCapacity) % kCapacity` 那个 `+ kCapacity` 漏了,或者 `n` 用错了(比如直接用 `kCapacity` 而不是 `qMin(m_count, kCapacity)`),你画出来的折线就会错位、或者画出没初始化的点。写环形缓冲一定拿笔画一遍下标,别凭感觉。

跨平台用 `M_PI` 那个前面已经讲过,不再重复,自己写 constexpr 字面量最稳。

## 小结

回头看,这一章其实就是把"自己画折线"这件事从动机一路拆到实现:Qt Charts 在 rootfs 里但 light-meter 没用它,是算过账的取舍;QPainter + paintEvent 的自绘套路,屏幕坐标系 Y 轴朝下逼出来的那套映射翻转;真正的环形缓冲长什么样、为什么写入能是 O(1);还有 `update()` 的真相和那个差点骗人的注释。`M_PI` 的坑算个赠品。

light-meter 的桌面 Mock 阶段到这里就讲完了。运行、告警、息屏三态,数据从 MockedSensor 流到 ChartView 自绘的折线,整条软件链路在桌面上跑得明明白白。接下来问题来了:下一章是整个系列的转折点,我们要翻那个 CMake 开关,把 Mock 后端换成真机后端,看看"契约先行"这件事到底扛不扛得住迁移。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="05_three_state_ui.md" variant="sub">← 05 三态 UI + 状态机</ChapterLink>
  <ChapterLink href="07_cmake_seam.md" variant="sub">07 THE 接缝:一行 CMake 切后端 →</ChapterLink>
</ChapterNav>
