---
title: 三态 UI + 状态机 + 定时器编排
---

# 三态 UI:运行、告警、息屏怎么调度

::: info 本节你将学到
- Qt 程序和顺序 C 程序的根本区别在哪,事件循环是个什么东西
- QObject 这套父子所有权,Qt 怎么管内存,你为什么基本不用手 delete
- 信号和槽是怎么回事,`Q_OBJECT` 和 moc 在背后替你干了什么
- QTimer 的周期、单次、动画三种用法,light-meter 的三个定时器怎么分工
- 一个三态 UI 怎么用状态机的思路写清楚,而不是写成一锅 if
- 顺手把 CSV 导出和常驻应用的 OOM 防线讲了
:::

::: tip 前置知识
- 第 04 章的 MockedSensor,数据源已经就绪
- 第 01 章你已经弹出过一个 Qt 窗口,但没讲过它为什么能弹出来,这一章从事件循环讲起
:::

## 先打个预防针,这章最长

先把话说在前面,这一章是整套教程里最长的一章。原因没什么神秘的,Qt 的几样基础设施我们还没碰过,得从零讲一遍。到上一章为止,我们手里的零件只有 Sensor 契约和 MockedSensor,UI 这一摊是一张白纸。这次我们要把 MockedSensor 接到一个 Qt 窗口上,造出 light-meter 的三态界面:运行态正常采样,lux 跌破阈值进告警态,无接近 10 秒进息屏态。

要让这三态有条不紊地流转,得先搞清楚一件事:Qt 程序到底是怎么跑起来的,它和你写过的顺序 C 程序差在哪。

## Qt 程序和顺序 C 程序的根本区别:事件循环

你写过的 C 程序,大概都是从 main 进来,一行一行往下执行,执行完就退了。GUI 程序不能这么跑。一个窗口弹出来,它得一直待在那儿,等你点按钮、等你按键、等系统通知它"该重绘了"。你来一个事件它处理一个,没事件就等着,直到你关掉窗口程序才退。这种"反复取事件、处理事件"的循环就叫事件循环,Qt 里就是 `QApplication::exec()`。

回头看第 01 章那个 hello-qt 的 main:

```cpp
int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    QWidget window;
    window.show();
    return app.exec();   // ← 就是这一行,进入事件循环
}
```

`app.exec()` 就是事件循环本身,它不会马上返回,而是反复从 Qt 的事件队列里取事件、分发给对应的对象处理。点鼠标产生一个鼠标事件,分发给鼠标落点的那个控件;按键盘产生键盘事件,分发给有焦点的控件;窗口被遮挡再露出来,产生一个绘制事件,通知该控件重绘自己。直到你关掉窗口,`exec()` 才返回,main 才走到 return。

这件事会反过来改变你写代码的思路。顺序程序里你是"主动去拿"数据,比如 `scanf` 等用户输入。GUI 程序里你反过来,是被事件驱动的:你的代码是被事件调用的,你要做的事情变成"事件来了我该怎么响应"。light-meter 的采样就是被一个定时器事件驱动的,定时器到点了通知 UI 去 query 一次数据。这就是上一章说的"拉模型"和事件循环咬合的地方。

## QObject:Qt 的地基和它的内存管理

Qt 里绝大多数类都继承自 QObject,`QWidget`、`QTimer`、`QMainWindow` 都是。QObject 给它的子类提供了一整套能力,信号槽、事件处理、还有一套非常省心的内存管理,父子所有权。

Qt 的内存管理是这样。每个 QObject 都可以有一个 parent,你 new 一个 QObject 的时候把它的 parent 传进去,这个对象就挂到了 parent 的子列表里。当 parent 被销毁时,它会自动销毁自己所有的 children,children 再销毁各自的 children,整棵树递归销毁。所以你在 Qt 里写 `new QLabel("hi", parentWidget)`,基本不用操心这个 QLabel 什么时候 delete,parent 销毁时它跟着走。

light-meter 里 `MainWindow` 是个 QWidget,它的构造函数里 new 了一堆 QTimer、QPushButton、QLabel,都把 `this` 当 parent 传进去:

```cpp
m_sampleTimer = new QTimer(this);              // parent 是 MainWindow
m_idleTimer = new QTimer(this);
m_pauseBtn = new QPushButton(QStringLiteral("⏸ 暂停"), leftPanel);
```

所以这些控件和定时器,你都不用手动 delete,`MainWindow` 析构时它们全跟着销毁。这是 Qt 比"裸 new/delete"省心的地方。说穿了就是一条肌肉记忆:在 Qt 里 new 一个 QObject,第一反应永远是问一句"它的 parent 是谁"。

::: details 不传 parent 会怎样
你不传 parent,这个对象就成了没有归属的"孤儿",没人替它 delete,你就得自己管理它的生命周期,自己 new 自己 delete,跟普通 C++ 对象一样。light-meter 几乎所有 QObject 都挂了 parent,唯一例外是那些被智能指针管理的非 QObject 对象(比如 `unique_ptr<Sensor>`),因为 Sensor 不是 QObject,挂不进 Qt 的父子树。
:::

## 信号和槽:Qt 对象怎么对话

GUI 程序里到处都是"一件事发生了,通知另一件事去做反应"。用户点了按钮,通知业务逻辑去处理;定时器到点了,通知 UI 去刷新;数据变了,通知显示它的控件更新。Qt 给这套通知机制起了一对专门的名字,信号和槽。

信号是一个对象"发出"的通知,`emit mySignal();`,意思是"这件事发生了"。槽是一个对象里可以被调用来响应的成员函数。你用 `connect` 把一个对象的信号连到另一个对象的槽上,信号一发出,连上的槽就被调用。比如把按钮的 `clicked` 信号连到 `MainWindow` 的某个处理函数上,点按钮就触发处理。

light-meter 里这种连接到处都是:

```cpp
connect(m_sampleTimer, &QTimer::timeout, this, &MainWindow::onSampleTick);
connect(m_pauseBtn, &QPushButton::toggled, this, &MainWindow::onTogglePause);
```

第一行的意思是,`m_sampleTimer` 每次发出 `timeout` 信号,就调 `this`(也就是 MainWindow)的 `onSampleTick` 槽。第二行是按钮的 `toggled`(按钮按下/弹起)信号连到 `onTogglePause`。这种用函数指针的 `connect` 写法是现代 Qt5 起推荐的,编译期能检查信号和槽的签名,比老的字符串写法 `SIGNAL(timeout())` 安全得多。

要让一个类能用信号槽,它得满足两个条件:得继承 QObject,类定义里还得写一个 `Q_OBJECT` 宏。`Q_OBJECT` 这个宏展开后是一堆元对象声明,Qt 有个叫 moc(Meta-Object Compiler)的工具会扫描带 `Q_OBJECT` 的类,替你生成一段额外的 C++ 代码来实现信号槽的元对象机制。你在第 01 章见过的 AUTOMOC 就是让 CMake 自动跑这个 moc。light-meter 里 `MainWindow` 有 `Q_OBJECT`,`ChartView` 也有(它用了信号槽),而 `BreathingOverlay` 没有(它纯 paintEvent 不需要信号槽),这也是看一个类有没有 `Q_OBJECT` 的实际判据。

## QTimer:周期、单次、动画三件套

`QTimer` 是 Qt 里做定时和周期性任务的工具,它的工作方式是,你设好间隔、连好 `timeout` 信号、`start`,之后它每隔那个间隔就发一次 `timeout`,你连的槽就被调一次。light-meter 里用了三个 QTimer,正好对应三种典型用法,我们一个个看。

第一个是采样定时器 `m_sampleTimer`,周期性,200 毫秒一次,用来驱动数据采样:

```cpp
m_sampleTimer = new QTimer(this);
m_sampleTimer->setTimerType(Qt::PreciseTimer);
connect(m_sampleTimer, &QTimer::timeout, this, &MainWindow::onSampleTick);
m_sampleTimer->start(kSampleMs);   // 200ms
```

`setTimerType(Qt::PreciseTimer)` 是要求高精度,默认的粗精度定时器为了省电会有一点抖动,但 light-meter 要 5Hz 等间隔采样,所以开 Precise。这是周期定时器的标准用法,`start(间隔)` 之后就会一直每间隔发一次 timeout。

第二个是息屏倒计时 `m_idleTimer`,**单次**。它的特点是"启动后只响一次",用来数"无接近 10 秒就息屏":

```cpp
m_idleTimer = new QTimer(this);
m_idleTimer->setSingleShot(true);
connect(m_idleTimer, &QTimer::timeout, this, &MainWindow::enterScreenOff);
```

`setSingleShot(true)` 把它设成单次模式,`start(10000)` 之后 10 秒发一次 timeout 然后自己停。这跟周期定时器的区别很关键,周期的是"每隔",单次的是"延迟多久之后就一次"。

第三个是呼吸动画 `m_breathTimer`,又是周期性,但间隔很短(50ms),用来驱动息屏态那个慢呼吸点的动画。息屏时启动,唤醒时停掉。

这三个定时器合起来,就是 light-meter 在时间维度上的全部调度。Qt 里做定时任务,翻来覆去基本也就是这三种套路。

## 逐段读 mainwindow.cpp

概念讲够了,来读真东西。`mainwindow.cpp` 是 light-meter 最长的一个文件,我们按它的几个职责分段读。

### UI 搭建:纯代码,不用 .ui 文件

`buildUi()` 这个函数负责把界面搭出来。light-meter 选择的是**纯代码**搭 UI,不用 Qt Designer 那个 `.ui` 文件。这不是唯一选择,`.ui` 文件适合快速拖拽出复杂表单,但对 light-meter 这种控件不多、布局简单、还要精细控制样式的摆件,纯代码反而更直接,代码即界面,改起来不用在编辑器和设计器之间切。这是个权衡,不是教条。

布局用 `QSplitter` 把窗口分成左右两栏,左栏是 lux 大数字、进度条、暂停按钮、导出按钮、阈值滑杆、息屏控制这些控件,右栏是那条折线图。Qt 的布局系统,`QVBoxLayout`、`QHBoxLayout` 是垂直、水平排列,你往里 `addWidget` 控件就自动排好,窗口缩放时布局自动调整。`QSplitter` 比 `QLayout` 多了"中间一根可拖动的分隔条"。每个控件 new 出来时把父容器当 parent 传进去,挂进父子树,再 `addWidget` 进布局。

样式用 Qt 的样式表 QSS,语法接近网页的 CSS。light-meter 用了一套 Catppuccin 深色调色板:

```cpp
constexpr auto kCssWindow =
    "QMainWindow, QSplitter { background:#1e1e2e; }"
    "QSplitter::handle { background:#11111b; }";
```

`setStyleSheet` 一设,匹配的控件就变了样子。这套深色配色让摆件在床头不刺眼,也是它"产品感"的一部分。

### 三个定时器怎么编排

构造函数的后半段把三个定时器建好、连好、启动:

```cpp
m_sampleTimer = new QTimer(this);
m_sampleTimer->setTimerType(Qt::PreciseTimer);
connect(m_sampleTimer, &QTimer::timeout, this, &MainWindow::onSampleTick);
m_sampleTimer->start(kSampleMs);

m_idleTimer = new QTimer(this);
m_idleTimer->setSingleShot(true);
connect(m_idleTimer, &QTimer::timeout, this, &MainWindow::enterScreenOff);

m_breathTimer = new QTimer(this);
connect(m_breathTimer, &QTimer::timeout, this, &MainWindow::onBreathTick);
```

注意一个设计点,只有 `m_sampleTimer` 一启动就 `start`,`m_idleTimer` 和 `m_breathTimer` 都是按需启动的。`m_idleTimer` 要等"开启自动息屏且无接近"才启动数那 10 秒,`m_breathTimer` 要等进了息屏态才启动画呼吸点。这种"常驻定时器和按需定时器分开"的意识,对一个 7x24 跑的常驻应用是有意义的,没必要一开始就把所有定时器都开着。

### processSample:数据怎么流进 UI

每 200ms,`onSampleTick` 被调用一次,它推进 Mock 的相位、`query_once()` 拉一次数据,然后把数据交给 `processSample`:

```cpp
void MainWindow::onSampleTick() {
    if (m_paused) return;
    m_phase += kPhaseStep;
    m_sensor->set_phase(m_phase);
    auto res = m_sensor->query_once();
    if (!res) {
        m_sensor->init(true);
        res = m_sensor->query_once();
        if (!res) return;
    }
    processSample(res->luxury, res->ps);
}
```

这里有个细节值得学一下。`query_once` 返回 `std::expected`,失败时(比如还没初始化)这里不是直接放弃,而是先 `init(true)` 强制重新初始化,再 query 一次,二次还失败才 return。这是"失败自动重试一次"的容错写法,对一个常驻应用很合理,偶发的瞬态失败不该让整屏数据停掉。

`processSample` 把这一帧数据分发到各处,折线图追加一个点、历史记录存一份(给 CSV 用)、大数字更新、进度条更新、按 lux 判断要不要进告警态、按 ps 重置息屏倒计时:

```cpp
void MainWindow::processSample(double lux, int ps) {
    m_lastLux = lux;
    m_chart->pushSample(float(lux));
    m_history.append({QDateTime::currentMSecsSinceEpoch(), float(lux)});
    if (m_history.size() > kMaxHistory)
        m_history.remove(0, m_history.size() - kMaxHistory);
    m_clock->setText(QTime::currentTime().toString("HH:mm"));
    m_bigLux->setText(QString::number(qRound(lux)) + " lux");
    m_bar->setValue(qBound(0, int(lux / kLuxYMax * 100.0), 100));
    setAlarmMode(lux < m_threshold);
    resetIdleCountdown(ps);
}
```

### 三态状态机:运行、告警、息屏

light-meter 的三个状态,运行、告警、息屏,代码里没有用 Qt 的 `QStateMachine`(那是另一套更重的状态机框架),而是手搓的几个布尔加一段转移逻辑。这没问题,状态少的时候手搓更清楚。关键是你要把它当状态机来想,而不是一堆散乱的 if。

告警态其实是运行态的一个"着色变体",不是独立状态,代码里就是 `setAlarmMode(bool)`,lux 跌破阈值时把左侧数字卡的样式从绿底翻成红底、状态文字从"运行"变"告警":

```cpp
void MainWindow::setAlarmMode(bool alarm) {
    if (alarm) {
        m_numberCard->setStyleSheet("QFrame#numberCard { background:#c0392b; ... }");
        m_subText->setText("光线不足,建议开灯");
        m_statusLine->setText("● 告警");
    } else {
        m_numberCard->setStyleSheet("QFrame#numberCard { background:#181825; ... }");
        m_subText->setText("明亮 ✓");
        m_statusLine->setText("● 运行");
    }
}
```

息屏态是真正的独立状态,由 `m_screenOff` 这个布尔标记,进了息屏态就盖一个全屏黑遮罩、启动呼吸动画,出来就撤掉。驱动息屏状态转移的核心是 `resetIdleCountdown`:

```cpp
void MainWindow::resetIdleCountdown(int ps) {
    const bool near = ps > kPsWakeThreshold;
    if (near) {
        if (m_screenOff) exitScreenOff();
        if (m_idleTimer->isActive()) m_idleTimer->stop();
    } else {
        if (m_autoSleep && !m_idleTimer->isActive())
            m_idleTimer->start(kScreenOffMs);
    }
}
```

这一段是整个状态机的精髓,有一个反直觉的点一定要讲。看那个 `if (m_autoSleep && !m_idleTimer->isActive())`,意思是"开启了自动息屏、而且息屏倒计时当前没在跑,才启动它"。为什么要有 `!isActive()` 这个判断?因为 `resetIdleCountdown` 是每个采样 tick(200ms)都调一次的,如果手离开之后每个 tick 都无条件 `m_idleTimer->start(10000)`,那这个 10 秒倒计时就每个 tick 都被重置回 10 秒,永远到不了 0,息屏永远触发不了。加了 `!isActive()` 判断,只有第一次"手离开"时启动倒计时,之后只要它还在跑就不重启,这样 10 秒才能真的数到、触发息屏。

这是一个典型的"定时器被反复重启导致永远到不了"的坑,我自己第一次写空闲超时就是栽在这儿,盯着看半天不知道为什么死活不触发。所以但凡你看到"空闲 N 秒之后做某事"的逻辑,先确认一下:触发定时器的那段代码,会不会在等待期间被反复调用、反复 start。

反过来,手靠近时(`near` 分支),如果在息屏就 `exitScreenOff` 唤醒,如果在数息屏倒计时就 `stop` 取消它,因为人来了就不该再息屏。

### 焦点策略:让空格专属于"手靠近"

light-meter 用空格键模拟"手靠近传感器",按下空格就是手靠近、松开就是手离开。这件事在 `keyPressEvent`/`keyReleaseEvent` 里处理。但这里有个 Qt 焦点的坑,如果不管,空格根本到不了 `MainWindow` 的 keyPressEvent。

原因是,Qt 里键盘事件默认送给"有焦点的控件",而按钮、滑杆、复选框这些控件拿到焦点后,空格键会被它们自己吃掉用(按钮把空格当"点击"触发)。所以如果你点了"暂停"按钮,焦点跑到按钮上,之后按空格触发的是按钮点击,不是你的"手靠近"。

light-meter 的解法是,把所有不需要接收键盘的控件的焦点策略设成 `Qt::NoFocus`:

```cpp
m_pauseBtn->setFocusPolicy(Qt::NoFocus);
m_thresholdSlider->setFocusPolicy(Qt::NoFocus);
m_exportBtn->setFocusPolicy(Qt::NoFocus);
// ... 所有按钮、滑杆、复选框都设
```

设成 NoFocus 的控件不接收焦点,键盘事件就不会被它们吞掉,空格就能稳定地被 `MainWindow` 接到。这是一个 Qt 焦点路由的经典坑,light-meter 的注释也特意写了"不抢焦点:空格留给手靠近"。

### CSV 导出和 OOM 防线

最后两块小功能。CSV 导出是把这一段会话的历史数据存成文件:

```cpp
QTextStream s(&f);
s << "timestamp,lux\n";
for (const auto &row : m_history) {
    const QString ts = QDateTime::fromMSecsSinceEpoch(row.first).toString(Qt::ISODateWithMs);
    s << ts << ',' << QString::number(row.second, 'f', 1) << '\n';
}
```

`QFileDialog::getSaveFileName` 弹个保存对话框让用户选位置,`QTextStream` 把 `m_history` 里的时间戳和 lux 一行行写出去。`QStandardPaths::DocumentsLocation` 拿到系统的"我的文档"目录作为默认保存位置,这是跨平台拿用户目录的正确姿势,别硬写 `/home/user`。

OOM 防线是 `m_history` 那个 `if (m_history.size() > kMaxHistory) m_history.remove(0, m_history.size() - kMaxHistory)`。一个常驻摆件 7x24 跑,如果 `m_history` 无限 append,内存迟早撑爆,所以给它设了个上限 `kMaxHistory=18000`,超了就把最老的丢掉。这里要诚实说一个事,这个 `QVector::remove(0, n)` 是从头删 n 个元素,是个 O(n) 的搬移操作,**不是真正的环形缓冲**。真正的环形缓冲在下一章的 `ChartView` 里(`m_head`/`m_count` 那套),这里 `m_history` 只是为了 CSV 存全量、用截断的方式限内存,18000 条对 O(n) 搬移来说也不频繁(只在超上限时触发),所以这个取舍是合理的。但你别把它当环形缓冲抄到高频场景。

## 上手:三态全验

把第 04 章的 MockedSensor 接进 light-meter(或者直接编 `examples/light-meter` 的 Mock 配置,默认就是 Mock),跑起来。然后按这三步把三个状态都触发一遍。

三态长这样,对照着验。

启动进来就是运行态,折线每 200ms 滚动,lux 按 ~25 秒周期起伏,左侧大数字跟着变。

![运行态:绿色折线起伏,左侧 lux 大数字](/light-meter/mock-light.png)

把阈值滑杆拖到 700,等 lux 跌到 700 以下(或者拖高点让它跌破),左侧数字卡立刻翻红、状态点变"告警"、副提示变"光线不足,建议开灯"。这是告警态。拖回低值,lux 升回阈值以上,恢复绿色。

![告警态:左侧数字卡翻红、状态点变告警](/light-meter/mock-dark.png)

勾上"自动息屏"复选框,松开空格大概 10 秒,全屏变黑、中央出现一个慢慢呼吸的点,这就是息屏态。按住空格瞬间唤醒回运行态,息屏时在屏幕上点一下鼠标也能唤醒。

![息屏态:全屏黑加中央慢呼吸点](/light-meter/mock-sleep.png)

三个状态都触发一遍,Mock 数据源就被你接成了一个真会自己流转状态的桌面应用。这一步如果三态切换都顺,说明事件循环、定时器、状态机这条链路是通的,后面就可以放心画图了。

## 这一章的坑

第一个坑,类的 `Q_OBJECT` 宏忘了写,或者写了但 AUTOMOC 没开。症状是一堆 `undefined reference to vtable` 或者信号槽连不上。`Q_OBJECT` 是信号槽的前提,AUTOMOC 是自动跑 moc 的开关,第 01 章那份 CMakeLists 里 `qt_standard_project_setup()` 已经默认开了 AUTOMOC,所以你跟着走不会踩,但以后脱离这套模板自己建项目要知道。

第二个坑,跨线程的信号槽连接类型搞错。Qt 的信号槽默认是 `AutoConnection`,发送方和接收方在同一线程就直接调用,跨线程就排队。如果你手动指定了 `DirectConnection` 又用在跨线程场景,槽会在发送方线程执行,可能数据竞争。light-meter 全在主线程,没这个问题,但哪天你写多线程 Qt,这块的连接类型得心里有数。

第三个坑就是上面讲的,定时器被反复 `start` 导致倒计时永远到不了。任何"空闲 N 秒触发"的逻辑,都要判一下定时器是不是已经在跑,在跑就别重启。

第四个坑,QTimer 的精度。默认的 `CoarseTimer` 为了省电会允许几毫秒到十几毫秒的提前或延后,对 UI 动画无感,但如果你像 light-meter 采样这样要等间隔,得显式 `setTimerType(Qt::PreciseTimer)`。不过 PreciseTimer 在 Linux 下也只有毫秒级,要更准得上别的机制,这里够用。

第五个坑,样式表的 selector 写错导致不生效。QSS 的 selector 是按控件类名和 objectName 匹配的,`QFrame#numberCard` 表示"objectName 是 numberCard 的 QFrame"。你 `setObjectName` 设错了名,或者忘设,样式就匹配不上,控件保持默认外观,排查起来很费劲。

## 小结

说实话,这章信息量是真大,一气读完肯定记不住。但核心就一条主线:Qt 程序是被事件循环驱动的,你写的一切都是在回应事件。顺着这条线往下,事件循环催生了信号槽这套对话机制,信号槽又最常被 QTimer 这种周期事件触发,QObject 的父子所有权则让你不用操心这一堆对象谁先死谁后死。把这几样拼起来,light-meter 那个运行/告警/息屏的三态流转,手搓几个布尔加一段转移逻辑就写清楚了,顺手还把焦点路由、CSV 导出、内存上限这些常驻应用该有的细节都铺了一遍。

到这里 light-meter 的桌面 Mock 阶段基本齐了,就差那条折线图和息屏遮罩还没细讲。下一章我们把这两个自绘控件拆开,顺带说清楚为什么 i.MX6ULL 这种没有 GPU 的板子上,light-meter 宁可自己用 QPainter 画折线,也不用 Qt Charts。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="04_mocked_backend.md" variant="sub">← 04 MockedSensor</ChapterLink>
  <ChapterLink href="06_self_painted_chart.md" variant="sub">06 自绘 ChartView + 息屏遮罩 →</ChapterLink>
</ChapterNav>
