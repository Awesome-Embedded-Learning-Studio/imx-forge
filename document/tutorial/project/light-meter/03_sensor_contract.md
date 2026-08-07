---
title: Sensor 抽象契约
---

# Sensor 抽象契约:为什么先把接口钉死,再写任何 UI

::: info 本节你将学到
- 为什么 light-meter 第一份动笔的代码不是 UI,而是一个什么都不干、只定义接口的抽象类
- C++ 的虚函数、纯虚函数、抽象类到底解决了什么,以及为什么多态基类的析构函数必须是虚的
- `enum class` 比 C 的 `enum` 安全在哪
- 逐行读懂 `sensor/sensor.h`,包括那个被全代码消费、却拼错了的字段名 `luxury`
- 拉模型(应用主动 query)为什么比推模型(回调)更适合 Qt 的事件循环
:::

::: tip 前置知识
- 第 02 章的 `std::expected`,这一章的 `sensor.h` 返回类型全是它
- 听说过"面向对象"和"继承"这两个词就行,虚函数我们从零讲
:::

## 为什么先写一个什么都不干的抽象类

你可能以为,做一个照度摆件,第一份代码应该是那个 lux 大数字或者那条折线。light-meter 不是。它第一份动笔的代码是 `sensor/sensor.h`,一个**不能被实例化、不带任何实现、只声明"一个传感器该长什么样"**的抽象类。这顺序听着反直觉,但它会在第 07 章"翻一个 CMake 开关就换后端"那一招里给你兑现回报。我们慢慢说为什么。

先想个反例。假设你不写这个抽象基类,直接在 `MainWindow` 里 `#include "ap3216c_sensor.h"`,直接 `Ap3216cSensor sensor;` 然后 `sensor.query_once()`。看起来省事,可你立刻背上两个负担。一是 UI 代码跟真机驱动后端焊死了,想在桌面上跑(没有 `/dev/ap3216c`)调试 UI 根本不可能,你每次都得插板子;二是哪天想换一颗传感器、或者想喂假数据做测试,得把 UI 里所有调 `sensor` 的地方挨个翻一遍。

抽象基类 `Sensor` 就是来解这件事的。它定义一个**契约**:任何一个想被 UI 当作数据源用的东西,都得提供 `init` 和 `query_once` 这两个操作,签名就是这样。UI 只持有一个 `Sensor*` 指针,它不关心底下到底是 MockedSensor 还是 Ap3216cSensor。这么一来,UI 代码只跟契约打交道,后端是可插拔的,桌面调试时插 Mock、上板时插真机。"先定契约再写实现"这个判断,说实话,比任何花哨的设计模式都顶用。

要把这个契约在 C++ 里落地,得先把虚函数这个 C++ 基础从零讲清楚。

## 从 C 到 C++:虚函数到底解决了什么

假设你在 C 里想做"同一类东西有不同实现"这件事。比如你有几种传感器,都想叫 `sensor_read`,但每种读法不一样。C 的做法是函数指针:定义一个结构体,里面塞一个 `int (*read)(void*, int*)` 函数指针,不同的传感器给这个指针赋不同的函数。能用,但啰嗦,而且调用的时候你得手动传那个 `void*` 上下文。

C++ 给了一个更顺滑的机制,虚函数。你在基类里把一个函数标成 `virtual`,派生类可以重写它,然后你通过基类指针调用时,**实际跑的是派生类那个版本**,不是基类的。这就是多态。它的底层实现是一张函数指针表,叫 vtable,每个有多态对象的类一张,每个对象头部藏一个指针指向它。你通过基类指针调虚函数时,编译器生成的代码是"读对象的 vptr、查表、调对应的函数指针",所以运行时能找到正确的派生实现。这些细节你不用记,有个心智模型就够:虚函数是"通过基类指针调用、运行时决定跑哪个版本"的函数,这就是它能模拟"同一接口、不同实现"的根。

把虚函数推到极致,就是**纯虚函数**。在声明后面加 `= 0`,这个函数在基类里就没有实现,派生类必须提供实现。一个有纯虚函数的类叫**抽象类**,它自己**不能被实例化**,你写 `Sensor s;` 直接编译报错。抽象类的意义就是当契约用:我规定了接口长这样,实现交给派生类。light-meter 的 `Sensor` 就是抽象类,它的 `init` 和 `query_once` 都是纯虚的。

### 虚析构:多态基类不可省的一行

这里有一个 C++ 经典坑,所有讲虚函数的教程都会强调,我们也强调。一个类如果打算被当作多态基类用,也就是你会通过基类指针 `delete` 一个派生类对象,那它的**析构函数必须是虚的**。看个反例:

```cpp
class Bad {
public:
    ~Bad() {}            // 不是虚的
    virtual void f() = 0;
};

class Derived : public Bad {
    int* data;
public:
    Derived() : data(new int[100]) {}
    ~Derived() { delete[] data; }   // 有资源要释放
};

Bad* p = new Derived;
delete p;   // 未定义行为:只调用了 Bad::~Bad(),Derived 的析构没跑,data 泄漏
```

这里 `delete p` 因为 `p` 的静态类型是 `Bad*`,而 `Bad` 的析构不是虚的,编译器就只生成"调用 `Bad::~Bad()`"的代码,`Derived` 的析构函数被跳过,那 100 个 int 泄漏了。更糟的情况是基类没析构、派生类有需要释放的资源时,直接是未定义行为,程序可能崩。

解法就一行,把析构标成虚的:

```cpp
class Good {
public:
    virtual ~Good() = default;   // 虚析构,=default 让编译器生成默认实现
    virtual void f() = 0;
};
```

`virtual ~Sensor() = default;` 这一行,`virtual` 保证 `delete` 基类指针时析构链能正确走到派生类,`= default` 表示"我不要自定义析构逻辑,你给我生成默认的就行"。light-meter 的 `sensor.h` 就有这一行,任何一个想被多态使用的基类都不能省它,这一步不改一定炸。

### enum class:比 C 的 enum 安全在哪

`sensor.h` 里还有两个枚举,`InitError` 和 `QueryError`,它们用的是 `enum class` 而不是 C 里那种 `enum`。区别值得花两句讲。C 的 `enum`(`enum Color { RED, GREEN, BLUE };`)的值会污染外层命名空间,你能直接写 `RED`,而且它会隐式转成 `int`,你拿一个 `Color` 去当整数用、拿一个整数去当 `Color` 用,编译器都不拦你,bug 就藏在里面。

`enum class`(`enum class Color { Red, Green, Blue };`)是 C++11 引入的作用域枚举。它的值必须带前缀用,`Color::Red`,不会跟别的 `Red` 撞;而且它不会隐式转成 int,你想转得显式 `static_cast<int>(Color::Red)`,编译器能在编译期挡掉一堆类型混用的错误。light-meter 的错误类型用 `enum class`,所以 `InitError::DeviceUnavailable` 这种写法既清楚又不会跟别的枚举撞名。

## 逐行读 sensor.h

概念讲够了,来读真东西。下面是 `examples/light-meter/sensor/sensor.h` 的全部内容,我们一段段拆:

```cpp
#ifndef SENSOR_H
#define SENSOR_H

#include <expected>

struct SensorData {
    double luxury; // light luxury
    int ps; // how hand close to the sensor
};
```

先是 `SensorData`,一个普通的结构体,装一次采样的结果。它有两个字段,一个是照度,一个是接近度。这里有个事得诚实告诉你,字段名是 `luxury`,不是 `lux`。lux 照度,被写成了 luxury 奢华,上面那行注释 `// light luxury` 大概是想写 `light lux` 又写岔了。这事问就是手滑写错了,本来想改,结果一翻代码,UI、折线图、CSV 导出全代码都在用 `res->luxury`、`.luxury = ...`,这字段名已经是 public 契约的一部分了,动一下得改整个项目。索性不改,逃。后面章节你看到 `luxury`,知道它就是 lux 就行,别被这个 luxury 带偏。接口一旦发布出去,拼写错了也得维持稳定,这是契约的代价,跟现实里给变量起错名一样,改不动就只能认。

```cpp
class Sensor {
  public:
    enum class InitError {
        Ok, GeneralFailed, DeviceUnavailable
    };

    enum class QueryError {
        Ok, NotInited, DeviceUnavailable
    };
```

接着是 `Sensor` 类本体,开头两个 `enum class` 嵌在类里面,这意味着它们的完整名字是 `Sensor::InitError`、`Sensor::QueryError`,在类外面用得带前缀,在类的成员函数里可以直接写 `InitError`。`InitError` 装的是初始化可能的三种结果,成功、一般失败、设备不可用;`QueryError` 装的是查询可能的三种结果,成功、还没初始化、设备不可用。注意这两个枚举里都有 `Ok`,但它们是不同的类型,`InitError::Ok` 和 `QueryError::Ok` 不会混,这就是 `enum class` 作用域的好处。

```cpp
    Sensor() = default;
    virtual ~Sensor() = default;   // 多态基类: 经基类指针 delete 需 virtual 析构
```

构造函数 `= default` 表示让编译器生成默认的,我们不需要自定义。析构函数上一节讲过,`virtual ... = default` 是多态基类的标配,不可省。

```cpp
    virtual std::expected<void, InitError> init(bool force_reinit = false) = 0;

    virtual std::expected<SensorData, QueryError> query_once() = 0;
```

这两行就是契约的核心。`init` 是纯虚函数,返回 `std::expected<void, InitError>`,第 02 章讲过,值类型是 `void` 表示"成功不带值,失败带一个 InitError",它带一个 `bool force_reinit` 参数,默认 false,意思是"如果已经初始化过,要不要强制重新来一遍"。`query_once` 也是纯虚,返回 `std::expected<SensorData, QueryError>`,成功带一个采样数据,失败带一个 QueryError。这两个 `= 0` 让 `Sensor` 成了抽象类,谁想当数据源,就得实现这两个操作。

```cpp
    /// 测试数据注入(Mock 用);真机后端忽略(no-op)。
    /// 留在基类以便 UI 层无差别调用 —— 切换后端时不需改 MainWindow 的调用点。
    virtual void set_phase(double /*phase*/) {}
    virtual void set_held(bool /*is_held*/) {}
};
```

最后这两个 `set_phase` 和 `set_held` 值得停下来想一想。它们是虚函数,但**不是纯虚**,带一个默认的空实现 `{}`。用途是给 Mock 后端"注入测试数据",`set_phase` 推进假数据的相位,`set_held` 模拟"手靠近"。问题来了,真机后端根本不需要这两个操作,它的数据来自真硬件。

那为什么不把它们放在 MockedSensor 里当私有方法,而要放进基类?注释里那两行说得明白,放在基类、给个空实现,是为了让 UI 层可以**无差别地调用**。`MainWindow` 里 `m_sensor->set_phase(...)`、`m_sensor->set_held(...)` 这些调用,在 Mock 后端时真的推进假数据,在真机后端时走基类的空实现、什么也不发生。这样切换后端的时候,UI 的调用点一行都不用改。换个说法,如果这俩方法是 Mock 私有的,UI 切真机时就得把所有 `set_phase` 调用删掉或者加判断,那"翻一个开关就换后端"的干净就破坏了。把测试注入口放基类、用空实现兜底,代价是基类多俩没用方法,换回来的是切换后端零改动,这笔账怎么算都值。

## 拉模型 vs 推模型:为什么是 init 加 query_once

你可能注意到,`Sensor` 的接口是"应用主动去 query 一次",而不是"传感器有数据了回调通知应用"。前者叫拉模型,pull,后者叫推模型,push,带回调或者信号。两种都能用,light-meter 选拉模型是有理由的,这个理由跟 Qt 的事件循环有关。

Qt 的 GUI 程序跑在一个事件循环里,主线程不停地从队列取事件、处理、再取下一个。light-meter 的采样节奏是由一个 200ms 的 `QTimer` 控制的(第 05 章细讲),timer 到点了,主循环就去 `query_once()` 拉一次数据、刷新 UI。这种"应用主动按自己的节奏拉"的方式,跟事件循环天然咬合,采样频率完全由应用说了算,不依赖传感器那边什么时候主动推。推模型在异步、事件驱动的传感器上有它的价值,但 light-meter 想要的是"5Hz 的等间隔采样",拉模型简单得多,也顺手避开了回调线程跟 UI 线程之间那堆同步麻烦。这件事第 05 章接上 QTimer 之后你会体会得更深,这里先记住"拉模型是 light-meter 主动选的"就行。

## 上手:写一个 FakeSensor 验证契约

光读不练,契约到底能不能被满足、满足起来别不别扭,你心里是没底的。我们来写一个最小的 `FakeSensor`,只 override 那两个纯虚函数,返回固定数据,然后通过 `unique_ptr<Sensor>` 持有它、调用它。这一段不需要 Qt,纯 C++,你 `g++ -std=c++23` 就能编。

新建一个目录,放一个 `sensor.h`(把上面那份完整内容贴进去,或者直接从 `examples/light-meter/sensor/sensor.h` 拷一份),再写一个 `test.cpp`:

```cpp
#include "sensor.h"

#include <iostream>
#include <memory>

// 一个假的传感器,只为验证 Sensor 契约能被满足
class FakeSensor : public Sensor {
public:
    std::expected<void, InitError> init(bool /*force_reinit*/) override {
        return {};                 // 成功,什么都不干
    }

    std::expected<SensorData, QueryError> query_once() override {
        return SensorData{ .luxury = 300.0, .ps = 0 };   // 永远返回 300 lux、无人靠近
    }
};

int main() {
    std::unique_ptr<Sensor> sensor = std::make_unique<FakeSensor>();
    auto init_res = sensor->init(false);
    if (!init_res) {
        std::cout << "init 失败\n";
        return 1;
    }

    auto data = sensor->query_once();
    if (data) {
        std::cout << "luxury=" << data.value().luxury << " ps=" << data.value().ps << '\n';
    }
}
```

编译运行:

```bash
g++ -std=c++23 test.cpp -o test && ./test
# 期望输出: luxury=300 ps=0
```

这里有几个值得停一下的点。`std::unique_ptr<Sensor>` 持有一个基类指针,实际指向一个 `FakeSensor` 对象,这正是上一节讲的多态用法,而因为有虚析构,`unique_ptr` 析构时能正确调到 `FakeSensor` 的析构(虽然这里它没资源要释放)。`override` 这个关键字是 C++11 的好东西,它告诉编译器"我这个函数是想重写基类的虚函数",你签名要是写错了,比如参数类型对不上,编译器当场就报错。我的习惯是永远写 `override`,抓"以为重写了其实没重写"这种 bug,靠它最稳。`SensorData{ .luxury = 300.0, .ps = 0 }` 这种写法叫指定初始化,C++20 起的语法,按字段名赋值,可读性比按位置好。

跑出来 `luxury=300 ps=0`,契约就被一个具体类满足了,而且满足起来不别扭。这意味着,后面不管 MockedSensor 还是 Ap3216cSensor,只要实现了 `init` 和 `query_once`,UI 就能无差别地用它们。

## 这一章的坑

第一个坑,基类忘了写虚析构。症状通常是"程序大多数时候正常,偶尔崩在退出的时候",因为 UB 不保证每次都炸,这种偶发崩溃最折磨人。任何要被多态使用的基类,`virtual ~ClassName() = default;` 这一行就是肌肉记忆,写之前先写它。

第二个坑,override 不继承基类的默认参数。这是 C++ 一个出了名的反直觉点。`Sensor::init` 的声明是 `init(bool force_reinit = false)`,有默认参数。但派生类 override 它时,默认参数**不会**继承,而且默认参数是按**静态类型**决定的,跟虚函数的动态派发是两套机制。light-meter 的 `mainwindow.cpp` 里 `m_sensor->init(false)` 是显式把 false 传进去的,旁边注释也特意写了"override 不继承基类默认参数, 显式传 false"。你自己调的时候,要么显式传,要么确认基类那份默认参数就是你想要的,别指望它在派生类里也生效。

第三个坑,在构造函数或析构函数里调虚函数。这时候虚函数不会表现出多态行为,它只会调当前类(构造/析构正在进行的那一层)的版本,因为派生部分还没构造好或已经销毁了。这个坑 light-meter 没踩到,但写多态代码大概率会撞上,先记着。

第四个坑,对象切片。如果你把一个派生类对象**按值**赋给一个基类对象,`Derived d; Base b = d;`,派生类特有的部分会被切掉,`b` 就是个纯基类对象,虚函数也派发不到派生版本。这就是为什么多态必须通过**指针或引用**用,light-meter 用 `unique_ptr<Sensor>` 就是这个道理。

## 小结

虚函数、纯虚函数、抽象类的心智模型,加上多态基类必须虚析构这条铁律,是这一章第一个落点。`enum class` 比 C 的 enum 安全在哪,是顺手带过的第二个。剩下的篇幅都在拆 `sensor.h` 那份契约,从拼错的 `luxury`,到把测试注入口放基类这步设计,再到为什么选拉模型,你都过了一遍。

回头看你手里这份 `sensor.h`,它现在不该再是一段陌生代码了,该是一份你能逐行解释、能照着写出新后端的契约。下一章我们就实现第一个后端,`MockedSensor`,它在桌面上"假装有硬件",让你不插板子也能把数据喂给 UI。顺带会讲 light-meter 用到的另一个 C++ 模式,用 `unique_ptr` 配自定义 deleter 管理一个不完整类型,也就是轻量版 pImpl。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="02_cpp23_utf8_expected.md" variant="sub">← 02 C++23 + 中文源码</ChapterLink>
  <ChapterLink href="04_mocked_backend.md" variant="sub">04 MockedSensor 与 custom-deleter pImpl →</ChapterLink>
</ChapterNav>
