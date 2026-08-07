---
title: MockedSensor 与 custom-deleter pImpl
---

# MockedSensor:把物理世界假装出来

::: info 本节你将学到
- 一个 Mock 怎么"假装"出可信的传感器数据:正弦 lux 模拟昼夜起伏,二值 ps 模拟手靠近
- C++ 的 `<random>`:为什么用 `std::mt19937` 而不是 C 的 `rand()`,随机引擎怎么复用
- light-meter 用到的一套可迁移 C++ 模式,用 `unique_ptr` 配自定义 deleter 管理一个不完整类型,也就是轻量版 pImpl,它解决了什么、为什么非这么写不可
- 逐行读懂 `mockedsensor.h` 和 `mockedsensor.cpp`
:::

::: tip 前置知识
- 第 03 章的 Sensor 抽象契约,这一章实现的就是它的第一个派生类
- 知道 `std::unique_ptr` 是个独占所有权的智能指针就行,自定义 deleter 我们从零讲
:::

## 这一章我们造一个假传感器

第 03 章我们把 `Sensor` 那份契约钉死了,但它还是个抽象类,没法直接 new 出来用。这一章要做的就是它的第一个派生类 `MockedSensor`,一个在桌面上"假装有硬件"的后端。它不碰 `/dev/ap3216c`,也不依赖任何外设,Windows 和 Linux 都能跑,数据全是它自己算出来的。

说实话,这里有个诱惑很容易把人带歪。既然是假的,为什么不直接返回个固定值,比如永远 `lux=300, ps=0`?能,但那样 UI 调起来没意思,折线是一条直线,告警和唤醒这些状态永远触发不了,你等于没法在桌面验证逻辑。一个好的 Mock 得"像"真硬件,数据得有合理的起伏,这样 UI 才能真的跑起来、状态机才能真的流转。所以 `MockedSensor` 花了点心思,让 lux 按正弦曲线模拟一天的昼夜起伏,让 ps 在"手靠近"和"手离开"两个状态下分别给出合理的量级。我们先看它的数据物理,再看支撑这套数据的两个 C++ 技巧。

## 先看数据物理:lux 怎么假装,ps 怎么假装

照度 lux 这一侧,真实世界里桌面照度一天是会起伏的,白天亮、晚上暗。`MockedSensor` 拿一条正弦曲线来模拟这个起伏,公式是 `400 + 350*sin(phase)`,中心在 400 lux、振幅 350,于是 lux 就在 50 到 750 之间来回摆。再叠一个 -30 到 +30 的随机抖动,模拟环境光的随机波动。最后用 `std::clamp` 把结果钳在 50 到 800 的区间里,防止抖动把它推出 UI 的 Y 轴范围。`phase` 这个相位由 UI 那边的采样定时器每个 tick 推进一小步(`set_phase`),lux 就跟着正弦曲线慢慢起伏,周期大概是 25 秒,这是个适合调试的节奏,不用真等一天。

接近度 ps 这一侧,真实硬件里手越靠近传感器 ps 越大。但桌面调试时没人伸手,light-meter 的办法是让 `MockedSensor` 暴露一个 `set_held` 注入口,UI 上按住空格就调 `set_held(true)` 表示"手靠近",松开调 `set_held(false)`。"手靠近"时 ps 给 800 到 840 这个量级,"手离开"时给 0 到 40。为什么挑这两个量级?因为 UI 里有个阈值 `kPsWakeThreshold=500`,`ps > 500` 就认为有接近,所以"靠近"得明显高于 500,"离开"得明显低于 500,这两个状态才能可靠区分开。

这套数据物理看起来平平无奇,但它是一个"能用的 Mock"能不能成立的命门:数据得落在合理的物理量级上,UI 状态机的所有分支都得能被它打到。Mock 要像真硬件,这是个该养成习惯的判断。

## C++ 基础:`<random>` 比 `rand()` 强在哪

抖动那一项需要一个随机数。C 程序员本能会想 `rand() % 61 - 30`,但 C++ 有更好的工具,light-meter 用的是 `<random>` 这套。先把这套讲清楚,因为它和 C 的 `rand()` 不在一个档次。

C 的 `rand()` 有几个老问题。它的随机性差,在很多平台上低位明显有规律,`rand() % N` 这种取模写法还会放大这个毛病,分布不均匀。它的状态是全局的,多线程下你得自己加锁。它的种子是 `srand(time(nullptr))`,分辨率到秒,同一秒启动的两个程序拿到一样的序列,debug 起来想骂人。

C++11 的 `<random>` 把这件事重做了,拆成两个独立的概念。一个是**随机引擎**,负责生成原始的随机比特,`std::mt19937` 是最常用的一个,基于梅森旋转算法,周期长、分布好。另一个是**分布**,负责把引擎的原始比特映射成你要的分布,`std::uniform_int_distribution<int>(min, max)` 给你指定区间里的均匀整数。两者组合用,先拿一个引擎、拿一个分布,然后 `dist(engine)` 就出一个你想要的随机数。

light-meter 把这套封装进一个 `Random` 小类:

```cpp
class Random {
public:
    Random() : m_rng(std::random_device{}()) {}
    int int_range(int min, int max) {
        std::uniform_int_distribution<int> dist(min, max);
        return dist(m_rng);
    }
private:
    std::mt19937 m_rng;
};
```

这里有几个点值得停一下。`std::random_device{}()` 是用系统的真随机源(比如 Linux 的 `/dev/urandom`)给 `mt19937` 提供种子,比 `time(nullptr)` 靠谱得多。`m_rng` 作为成员一直留着,每次 `int_range` 复用同一个引擎,这很重要,因为引擎的初始化不便宜,而且一个引擎跑起来后状态才是"热"的,你每次要随机数都新建一个引擎既慢又没意义。`uniform_int_distribution` 倒是每次调用现建,它是个轻量的无状态映射,这没问题。引擎留着复用、分布现建现用,记住这个分工,这就是 `<random>` 的标准用法。

## 重头戏:unique_ptr 配自定义 deleter 管不完整类型

接下来这一段是本章的硬核,也是 light-meter 里我个人觉得最值钱的一个 C++ 模式。你看 `mockedsensor.h` 会发现一件怪事,它在头文件里前向声明了 `LuxSource` 和 `PsSource` 两个结构体,却不给出完整定义,完整定义全藏在 `.cpp` 里。然后它用一种看起来有点怪的 `unique_ptr` 持有它们,带了一个自定义的 deleter。我们在搞清楚这到底在干什么、为什么要这么干。

先说一个直接的问题。假设你不懂这套,想当然地在头文件里写:

```cpp
// mockedsensor.h(错误示范)
class MockedSensor : public Sensor {
    std::unique_ptr<LuxSource> lux_source;   // LuxSource 在头文件里只前向声明,不完整
    // ...
};
```

这段在很多编译器上会编译失败,或者至少在你析构 `MockedSensor` 的地方失败。原因是 `std::unique_ptr<LuxSource>` 的默认 deleter 在销毁对象时要 `delete` 那个指针,而 `delete` 一个指向不完整类型的指针是未定义行为,编译器需要在 `delete` 的位置看到 `LuxSource` 的完整定义。问题是 `MockedSensor` 的析构函数(编译器默认生成的)就在头文件里,而头文件里 `LuxSource` 只有前向声明、不完整,于是析构函数没法正确生成 `delete`。

"头文件里不想暴露类的完整定义"这个需求其实很常见。你想把实现细节藏在 `.cpp` 里,头文件只暴露一个最小的接口,这样拿到头文件的人不用看见 `LuxSource` 内部长什么样,编译依赖也小(改 `LuxSource` 的成员不用重编所有 include 了这个头文件的地方)。这个套路有个名字,pImpl,pointer to implementation,指针指向实现。

要让 `unique_ptr` 持有一个不完整类型,有两条路。第一条,在头文件里声明析构函数,在 `.cpp` 里定义它,这样析构的位置(`.cpp` 里)`LuxSource` 已经完整了,默认 deleter 就能正常工作。第二条是 light-meter 用的,给 `unique_ptr` 配一个自定义 deleter,这个 deleter 的实现也放在 `.cpp` 里,同样把 `delete` 推迟到类型完整的地方。两条路都成立,light-meter 选了第二条,我们就跟着它讲。

它的写法是这样,头文件:

```cpp
// mockedsensor.h
struct LuxSource;                          // 只前向声明,不完整

struct LuxSourceDeleter {
    void operator()(LuxSource* p) const;   // 只声明,实现放 .cpp
};

class MockedSensor : public Sensor {
    std::unique_ptr<LuxSource, LuxSourceDeleter> lux_source;   // 带自定义 deleter
    // ...
};
```

`.cpp` 里:

```cpp
// mockedsensor.cpp
struct LuxSource {
    // 完整定义,只在 .cpp 里可见
    double phase {0.0};
    std::unique_ptr<Random> random_source;
    double fetch_lux() const { /* ... */ }
};

void LuxSourceDeleter::operator()(LuxSource* p) const {
    delete p;                               // 这里 LuxSource 已完整,delete 安全
}
```

关键在 `LuxSourceDeleter::operator()`,它是在 `.cpp` 里定义的,而 `.cpp` 里 `LuxSource` 的完整定义就在上面,所以这里的 `delete p` 是安全的。`unique_ptr<LuxSource, LuxSourceDeleter>` 在析构时调用的就是这个 deleter,而不是默认的 `delete`,于是"销毁时类型要完整"这个要求被推迟到了 `.cpp` 里满足,头文件那侧只靠前向声明就能过编译。

这套写法的好处,头文件 `mockedsensor.h` 里 grep 不到 `LuxSource` 的任何成员细节,它对一个 include 它的文件来说就是一个不透明的名字,改 `LuxSource` 的实现只重编 `mockedsensor.cpp`,不动其他地方。这就是轻量版 pImpl,用 `unique_ptr` + 自定义 deleter 实现。以后写库、写需要隐藏实现的类,这招直接抄走。

## 逐行读 mockedsensor.h 和 mockedsensor.cpp

原理讲透了,来读真东西。`mockedsensor.h` 的核心是这几行:

```cpp
struct LuxSource;
struct PsSource;
struct LuxSourceDeleter {
    void operator()(LuxSource* p) const;
};
struct PsSourceDeleter {
    void operator()(PsSource *p) const;
};

class MockedSensor : public Sensor {
public:
    MockedSensor();
    std::expected<void, InitError> init(bool force_reinit) override;
    std::expected<SensorData, QueryError> query_once() override;
    void set_held(bool is_held) override;
    void set_phase(double phase) override;
private:
    std::unique_ptr<LuxSource, LuxSourceDeleter> lux_source;
    std::unique_ptr<PsSource, PsSourceDeleter> ps_source;
};
```

它 `public Sensor` 继承契约类,override 了四个虚函数,两个纯虚的 `init`/`query_once` 必须实现,两个测试注入口 `set_phase`/`set_held` 它也 override 了(因为 Mock 真要用它们推进假数据)。两个成员是带自定义 deleter 的 `unique_ptr`,上面刚讲过。

`.cpp` 里先给出 `LuxSource` 和 `PsSource` 的完整定义:

```cpp
struct LuxSource {
    LuxSource() : random_source(std::make_unique<Random>()){}
    void setPhase(double phase_) { phase = phase_; }
    double fetch_lux() const {
        return std::clamp(400 + 350*std::sin(phase) +
                          random_source->int_range(-30, 30), 50.0, 800.0);
    }
private:
    double phase {0.0};
    std::unique_ptr<Random> random_source;
};
```

这就是前面那套数据物理的代码形态。`fetch_lux` 里 `400 + 350*sin(phase)` 是正弦基线,`random_source->int_range(-30, 30)` 是抖动,`std::clamp(..., 50.0, 800.0)` 是钳位。`std::clamp` 是 C++17 加进 `<algorithm>` 的,三参数版本 `clamp(v, lo, hi)`,比手写 `std::max(lo, std::min(v, hi))` 清楚得多。`PsSource` 同理,held 给 800 到 840,不 held 给 0 到 40。

接着是两个 deleter 的定义,就是上一段贴的那两行 `delete p`。然后是 `MockedSensor` 的实现:

```cpp
std::expected<void, Sensor::InitError> MockedSensor::init(bool force_reinit) {
    if(!lux_source || force_reinit) {
        lux_source = std::unique_ptr<LuxSource, LuxSourceDeleter>(new LuxSource);
    }
    if(!ps_source || force_reinit) {
        ps_source = std::unique_ptr<PsSource, PsSourceDeleter>(new PsSource);
    }
    return {};
}
```

`init` 干的事就是按需 new 出两个数据源。注意它怎么用 `unique_ptr<LuxSource, LuxSourceDeleter>(new LuxSource)` 这种带 deleter 的构造,这里 `new LuxSource` 是安全的,因为是在 `.cpp` 里,`LuxSource` 完整。`if(!lux_source || force_reinit)` 表示只有"还没建过"或者"强制重建"时才 new,避免重复。成功返回空的 `expected<void,...>`。

```cpp
std::expected<SensorData, Sensor::QueryError> MockedSensor::query_once() {
    if(!lux_source || !ps_source){
        return std::unexpected {QueryError::NotInited};
    }
    return { SensorData { .luxury = lux_source->fetch_lux(), .ps = ps_source->fetch_ps() } };
}
```

`query_once` 先检查两个数据源是否就绪,没就绪就返回 `NotInited` 错误,这是第 02 章讲的 `std::unexpected` 的用法。就绪了就把两路 fetch 的结果填进 `SensorData` 返回。`set_phase` 和 `set_held` 就是把 UI 传进来的相位和"靠近"状态转发给两个数据源,简单一行。

`MockedSensor` 到这里就全读完了。它不长,但每一行都有讲究:正弦数据物理、`<random>` 复用、自定义 deleter 的轻量 pImpl,这套东西凑在一起,撑起了一个能在桌面上假模假样跑起来的传感器。

## 上手:把两条数据通路分别验证

光读没手感,我们把两条数据通路单独验证一下,确认 lux 和 ps 是独立可注入的。还是在第 03 章那个 scratch 目录里干,你已经有 `sensor.h` 了,现在再把 `mockedsensor.h` 和 `mockedsensor.cpp` 拷过来(或者直接在 `examples/light-meter/sensor/mocked/` 里干活),写一个小 main:

```cpp
#include "mockedsensor.h"
#include <iostream>

int main() {
    MockedSensor s;
    s.init(false);

    // 推进相位,看 lux 起伏
    for (double phase = 0.0; phase < 6.28; phase += 0.5) {
        s.set_phase(phase);
        auto d = s.query_once();
        if (d) std::cout << "phase=" << phase << " luxury=" << d.value().luxury << '\n';
    }

    // 看 ps 在 held/不 held 两个状态的切换
    s.set_held(false);
    std::cout << "松手 ps=" << s.query_once().value().ps << '\n';
    s.set_held(true);
    std::cout << "按住 ps=" << s.query_once().value().ps << '\n';
}
```

编译跑一下(记得带上 `mockedsensor.cpp` 一起编,因为 `LuxSource` 的完整定义在它里面):

```bash
g++ -std=c++23 test.cpp mockedsensor.cpp sensor.cpp -o test && ./test
```

正常的话,你应该看到 lux 跟着 phase 从低到高再到低地起伏(正弦),ps 在"松手"时是个位数、在"按住"时跳到 800 多。两组数对得上,就说明这两条数据通路确实各走各的,都能被外部注入控制。

## 这一章的坑

第一个坑,自定义 deleter 写在了头文件里、而且那里类型还不完整。这样 `delete p` 的位置看不到完整类型,等于又绕回了最初的问题。deleter 的实现必须在 `.cpp` 里,跟类型的完整定义放一起。

第二个坑,每次要随机数都新建一个 `mt19937`。这既慢,又让序列失去意义(每次都从同一个种子重新跑,如果种子还是固定的,你每次拿到一样的"随机"数)。引擎作为成员留着复用,这是 `<random>` 的基本规矩。

第三个坑,把"手靠近"和"手离开"的 ps 量级设得太接近阈值。比如你 held 给 520、不 held 给 480,中间就差 40,而抖动可能有 ±40,于是状态会在阈值附近来回抖,UI 跟着反复唤醒息屏。light-meter 给的是 800+ 对 0-40,两边离 500 这个阈值都远远的,留足裕量。做任何带阈值的系统,裕量这个意识都得绷着。

第四个坑,`std::clamp` 第一个参数得是能转成那两个边界的类型,`400 + 350*std::sin(phase) + int_range(-30,30)` 这里 `int_range` 返回 int、`sin` 返回 double,混在一起算会隐式转,记得 `int_range` 的返回参与的是浮点运算,不会有截断问题,但你要是写反了把一个 int 表达式整体 clamp 进 double 区间,类型不匹配会报错。light-meter 这里的写法是对的,你照着抄不会错。

## 小结

`MockedSensor` 这个"假传感器"的核心就两件事:让数据落在合理的物理量级上,让 UI 的状态机所有分支都能被它打到。围绕这两件事,顺手把 `<random>` 的引擎复用、分布现建这套标准用法捡了起来,再把 `unique_ptr` 配自定义 deleter 管不完整类型的轻量 pImpl 走了一遍。后面那个模式,我个人觉得是 light-meter 里最值得单独拎出来记一笔的东西。

到这里,light-meter 的桌面数据源就齐了,`Sensor` 契约有了第一个能跑的实现。下一章是这套教程体量最大的一章,我们把 `MockedSensor` 接到 Qt 的 UI 上,造出 light-meter 的三态界面,运行、告警、息屏,顺便把 Qt 的信号槽、事件循环、QTimer 这些从零讲一遍。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="03_sensor_contract.md" variant="sub">← 03 Sensor 抽象契约</ChapterLink>
  <ChapterLink href="05_three_state_ui.md" variant="sub">05 三态 UI + 状态机 + 定时器编排 →</ChapterLink>
</ChapterNav>
