---
title: 把阈值调成你的:按环境标定
---

# 把阈值调成你的:把默认占位值标定到你的环境

::: info 本节你将学到
- 为什么真机翻完开关后,默认常量得按你自己的板子调一调,这不是修坑,是任何涉及物理量换算的产品都要做的常规最后一步
- als raw 计数和物理量 lux 是两件事,`lux_coeff` 这个换算系数怎么用手机粗标
- ps 的唤醒阈值在真机上怎么定,怎么参考 driver/08 的实测数据
- 每个可调常量分别住在哪个文件哪一行,运行时能调的和要重编的分别怎么改
- 一个小增强,把 `lux_coeff` 做成环境变量可调,改参数不用每次重编
:::

::: tip 前置知识
- 第 07 章的接缝机制,你已经能编出真机二进制
- 第 09 章的 `Ap3216cSensor` 在下一章细讲,但这一章会引用它的 `lux_coeff` 参数;标定这件事本身在桌面就能理解,真机验证等下一章接上
:::

## 翻完开关,默认值是按我们的板子调的

第 07 章你翻完 `USE_REAL_SENSOR=ON`,真机二进制能在板子上跑出真实数据了,真机行为我们这边验过、跑通过,这件事可以放心。但有件事得先跟你交个底:light-meter 源码里那些默认常量,`lux_coeff`、告警阈值、唤醒阈值,是按我们这块板子、我们这个测试环境调好的。你的板子镜头透光率未必一样、AP3216C 焊的位置也未必一样、你房间的照度更不可能跟我的一样,这些都会让"同一份代码、换一个物理环境"读出来的数不一样。

所以下面要讲的不是修坑,是任何涉及物理量换算的产品都要做的最后一步:标定。把那些写着 1.0 的占位值、写着默认数的阈值,按你自己的环境调到位。light-meter 故意把这一步留给你,占位值只是"能跑",标定过的值才是"在你这边准"。温湿度、气压、距离,凡是带物理量换算的传感器,这步都躲不掉。

## als raw 不是 lux:lux_coeff 标定

标定里头最要紧的一件事,是先把 als raw 和 lux 这两个概念分清楚。AP3216C 的环境光通道给你的不是一个物理量 lux,而是一个 raw 计数,叫 als raw,它大致正比于光强,但比例系数受镜头透光率、安装位置、传感器个体差异影响。driver/08 那篇实测数据里,正常室内光下 als raw 大概 80 上下,注意这个 80 不是 80 lux,它只是个计数。

物理量 lux 是有国标定义的照度单位,GB 50034 规定书桌阅读要 300 lux 以上。light-meter 的告警逻辑、"明亮/不足"的判断,都是冲着物理量 lux 去的,所以必须把 als raw 换算成 lux,这个换算系数就是 `lux_coeff`。看 `Ap3216cSensor` 的查询逻辑,`db[1] * m_lux_coeff` 就是这一步:

```cpp
return SensorData{
    .luxury = db[1] * m_lux_coeff,   // als → luxury(lux)
    .ps     = static_cast<int>(db[2])
};
```

`lux_coeff` 在构造函数里默认是 1.0,这是个诚实的占位,意思就是"还没标定",这时候显示的"lux"其实就是 als raw,室内读个 80。标定,说白了,就是把这个 1.0 换成你环境的真值。

朴素的办法是拿一个已知 lux 的参考。你手机上装一个照度计 App(它用手机的前置光感估算 lux,精度一般,但够粗标),把手机和 AP3216C 摆在同一束光下,同时读,App 显示 X lux、板子读到 als raw = Y,那 `lux_coeff = X / Y`。举例,App 读 300 lux、板子 als raw 是 80,那 `lux_coeff = 300 / 80 = 3.75`。把这个值填进去,以后 `luxury = als_raw * 3.75`,light-meter 显示的 lux 就和手机 App 在 ±15% 内对得上。

±15% 是个诚实的容差,手机照度计 App 本身误差就不小,这套是"粗标定",比 1.0 强得多、让告警逻辑真的有意义,但它不是计量级的。要实验室精度,得上标准光源和照度计,那是另一回事,light-meter 这个摆件用不着。

系数填哪。在 `mainwindow.cpp` 那个真机工厂分支,默认是 `std::make_unique<Ap3216cSensor>()`,用的是构造函数的默认 `lux_coeff=1.0`。你可以显式传:

```cpp
#ifdef USE_REAL_SENSOR
    m_sensor = std::make_unique<Ap3216cSensor>("/dev/ap3216c", 3.75);   // 你标定出的系数
#else
    m_sensor = std::make_unique<MockedSensor>();
#endif
```

## ps 唤醒阈值:参考 driver/08 的实测

ps 这一路比 lux 简单,不用换算物理量,但有个阈值要定。`kPsWakeThreshold` 是"ps 多大算有接近",默认 500。这个 500 是按 Mock 后端调的,Mock 在"手靠近"时给 800 到 840,远远超过 500。但真机呢?

答案在 driver/08 的实测数据里。板子上,手离开、正常室内,ps 大概在 430 到 450 这个量级;手指慢慢靠近、贴近传感器,ps 上升到峰值大概 502。所以真机 ps 的有效范围跟 Mock 完全是两回事:Mock 是 0-40 对 800-840,真机是 ~440 对 ~502。`kPsWakeThreshold=500` 意味着只有手指**几乎贴上**传感器(ps 到 502)才会触发唤醒,"手在前面晃晃"是到不了 500 的。

你要的体验是哪种,阈值就定在哪。想"手指贴近才唤醒"(省电、防误触),500 合适。想"手伸到前面就唤醒"(灵敏、像床头感应),那 500 太高,得降到 470 左右,给离 idle 的 440 留点裕量。这个值没有标准答案,按你想要的体感试。改的位置是 `mainwindow.h` 里 `static constexpr int kPsWakeThreshold = 500;` 这一行,改完重编。

说一句,阈值离 idle 噪声太近会抖。你要是把阈值定在 445,而 idle 本身在 430 到 450 之间漂,那没人靠近的时候 ps 也会偶尔过 445,屏幕反复唤醒息屏,体验很糟。idle 和阈值之间留够裕量,这是上一章讲 Mock 时提过的"裕量意识",搬到真机标定一样成立。

## 阈值滑杆:运行时就能调告警线

`lux_coeff` 和 `kPsWakeThreshold` 是要重编才能改的(下面那个增强会改掉 lux_coeff 这一条)。但告警阈值 `m_threshold` 不用,light-meter 给它配了个运行时滑杆,左下角那个"阈值"滑条,拖一下就实时改告警线,折线图上的虚线跟着移动,告警着色也立刻重评估。

```cpp
void MainWindow::onThresholdChanged(int value) {
    m_threshold = double(value);
    m_thresholdValue->setText(QString::number(value));
    m_chart->setThreshold(float(m_threshold));
    setAlarmMode(m_lastLux < m_threshold);   // 即时重评估告警
}
```

滑杆范围 100 到 700,默认 300,正好是国标 GB 50034 的书桌阅读下限。接上真机后,不用重编,直接拖滑杆就能找到你环境下"明亮/不足"的分界点,这是体验调参最快的方式。等你用滑杆摸到合适的阈值,再回头把它写进 `mainwindow.h` 里 `m_threshold` 的默认值,下次启动就是新值。

先用界面找到值、再固化进配置,这是个挺顺手的工程习惯。

## 一个小增强:lux_coeff 走环境变量

每次标定完都要改源码、重编,有点烦,尤其标定本身就是要反复试的。这里我带你做一个小增强,把 `lux_coeff` 做成环境变量可调,改系数只要重启程序、不用重编。改动很小,但能让标定过程顺很多,也顺带把"配置外置"这点小思路过一遍。

改动在 `mainwindow.cpp` 的真机工厂分支,读一个环境变量 `LIGHTMETER_LUX_COEFF`,解析成 double,传给构造函数,没设就退回默认 1.0:

```cpp
#ifdef USE_REAL_SENSOR
{
    double coeff = 1.0;   // 默认占位
    if (const char* env = std::getenv("LIGHTMETER_LUX_COEFF")) {
        bool ok = false;
        double parsed = QString::fromLocal8Bit(env).toDouble(&ok);
        if (ok) coeff = parsed;
    }
    m_sensor = std::make_unique<Ap3216cSensor>("/dev/ap3216c", coeff);
}
#else
    m_sensor = std::make_unique<MockedSensor>();
#endif
```

记得在文件顶部 include `<cstdlib>` 拿 `std::getenv`。改完之后,标定流程就变成:板子上跑 `LIGHTMETER_LUX_COEFF=3.75 ./light-meter`,看 lux 对不对得上手机,不对就改数重跑,全程不编译。定下来之后,你可以把这个值固化进启动脚本、或者 systemd service 的 Environment,也可以回头写进源码默认值,看你怎么舒服。

`std::getenv` 返回 `const char*`,可能为空(变量没设),`QString::fromLocal8Bit(env).toDouble(&ok)` 把字符串转 double,`ok` 表示转换成不成功,这两层保护让你在环境变量写错(比如写了个字母)时不崩、退回默认。处理外部输入就该这么写:校验、失败就退回安全默认,别图省事直接 `atof(env)` 不管成败。

这个小增强你不一定要做,light-meter 主线用源码默认值也跑得好。但如果你打算顺滑地标定,或者哪天想把 light-meter 部署到几块不同的板子上、每块板系数都不一样,这套外置配置就方便了。

## 上手:用手机粗标 lux_coeff

这步要等第 09 章你能在板子上读到真实 als raw 之后才能完整做,这里先把流程过一遍,等你接上 `Ap3216cSensor` 照着走就行。

手机装个照度计 App,把手机和板子的 AP3216C 摆在同一束室内光下,手机读一个参考 lux,记下来,比如 300。

接着在板子上读 AP3216C 的 als raw,这个用第 09 章那个 5 行独立 main 最方便,跑一下打印 als,比如读到 80。

然后算 `lux_coeff = 300 / 80 = 3.75`,用上面那个环境变量增强跑 `LIGHTMETER_LUX_COEFF=3.75 ./light-meter`,看界面上显示的 lux 和手机 App 读数差多少。理想是 ±15% 以内。

差得多的话,换个光强(比如开个台灯)再来一次,两点标定取平均更稳。定下来之后,把系数写进启动脚本或源码默认值。

顺手把 ps 唤醒阈值也定一下,按你想要的"贴近唤醒"还是"伸手唤醒",改 `kPsWakeThreshold`,重编、试。

## 这一章的坑

第一个坑,拿手机 App 当照度标准却期待计量级精度。手机前置光感本身误差就不小,不同手机读数能差 20%。这套就是个"粗标定",±15% 容差,够摆件用,要计量级请上标准光源。

第二个坑,在不具代表性的光环境下标定。比如你标的时候拉了窗帘、桌面上很暗,als raw 读 30,你算出 coeff 把这个值焊死,结果白天一开窗全偏了。标定选你实际使用的典型环境,或者多点标定取平均。

第三个坑,ps 阈值定得太贴 idle 噪声,导致反复唤醒息屏。idle 和阈值之间留够裕量,真机 idle ~440 有漂动,阈值别定在 445 这种贴边的位置。

第四个坑,环境变量增强里图省事 `atof(env)` 不判失败。env 没设时 `getenv` 返回 nullptr,`atof(nullptr)` 是未定义行为;env 写了个非数字,`atof` 默默返回 0,你的 lux 全变 0。用 `toDouble(&ok)` 判一下,失败退回默认,稳。

## 小结

als raw 不是 lux,这一件最容易想错的事讲完了,`lux_coeff` 就是那个把计数换成物理量的系数,手机粗标、±15% 容差收着用。ps 唤醒阈值参考 driver/08 实测的 ~440 idle / ~502 touch,贴近唤醒还是伸手唤醒,看你想要的灵敏度。运行时滑杆先把合适的告警线摸出来,再写回编译期默认值。再就是那个把系数外置到环境变量的小增强,顺带把"外部输入要校验、失败退回安全默认"这件事也提了。

讲到这里,light-meter 的"翻开关、调参数"这一段就齐了。下一章我们正式读那个真机后端 `Ap3216cSensor`,看它怎么用 POSIX 的 `open`/`read` 把 `/dev/ap3216c` 的数据读出来,以及 `{ir, als, ps}` 这个三路数据的顺序,为什么是驱动和应用两端必须共享的同一份契约。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="07_cmake_seam.md" variant="sub">← 07 THE 接缝:一行 CMake 切后端</ChapterLink>
  <ChapterLink href="09_ap3216c_client.md" variant="sub">09 POSIX 字符设备客户端 →</ChapterLink>
</ChapterNav>
