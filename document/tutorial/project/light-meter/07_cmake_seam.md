---
title: THE 接缝:一行 CMake 切后端
---

# THE 接缝:一行 CMake 开关,后端就换了

::: info 本节你将学到
- light-meter 怎么靠一个 CMake `option` 在编译期切换 Mock 和真机两个后端
- CMake 的 `option` / `target_sources` / `target_compile_definitions` 三件套,以及 C++ 里的 `#ifdef` 条件编译
- 为什么这个开关放在编译期而不是运行期,host 和 target 隔离是什么意思
- 为什么这套机制能砍这么深,第 03 章那个"把注入端口放基类"的决定在这里兑现回报
- 那个 `override` 不继承默认参数的 C++ gotcha
:::

::: tip 前置知识
- 第 03 章的 Sensor 抽象契约、第 04 章的 MockedSensor,这是被切换的两个后端
- 第 01 章的 CMake 基础
:::

## 这一刀是整个桌面阶段的收口

前面六章我们做的事,可以一句话总结:在桌面上用 MockedSensor 把 light-meter 整条软件链路调到完美。UI、状态机、自绘折线、CSV 导出,全跑在一个假数据后端上,一行真硬件代码都没碰。说实话,你自己心里大概一直有个疑问:既然桌面跑的是假数据,那真机呢,翻成真机是不是要把这一堆代码重写一遍。

这一章就是回答这个问题的。答案说出来也很朴素,翻成真机,不改 UI 一行代码、不改状态机一行代码、不改折线绘制一行代码,只翻一个 CMake 开关。这个"翻开关就行"听着像魔法,但它不是凭空来的,它是第 03 章我们花一整章钉死的 Sensor 抽象契约、以及把 `set_phase`/`set_held` 放在基类当空实现那个决定,在这一刻结出来的果子。我们这一章就把这个接缝的机制拆开,看它到底怎么工作,以及为什么它能砍得这么深。

## 三件套:option / target_sources / target_compile_definitions

接缝的全部机制,在 light-meter 的 `CMakeLists.txt` 里就是这么一段:

```cmake
# 真机后端(可选): /dev/ap3216c 桥接, 仅 Linux/板子(POSIX)。默认 OFF = Mock 后端。
option(USE_REAL_SENSOR "真机后端 /dev/ap3216c(仅 Linux/板子)" OFF)
if(USE_REAL_SENSOR)
    if(WIN32 OR NOT UNIX)
        message(FATAL_ERROR "USE_REAL_SENSOR 仅 Linux/板子可用(POSIX open/read/close)")
    endif()
    target_sources(light-meter PRIVATE
        sensor/ap3216c/ap3216c_sensor.h sensor/ap3216c/ap3216c_sensor.cpp)
    target_compile_definitions(light-meter PRIVATE USE_REAL_SENSOR=1)
endif()
```

我们逐行拆。`option(USE_REAL_SENSOR "说明文字" OFF)` 定义一个 CMake 的开关变量,名字 `USE_REAL_SENSOR`,默认值 `OFF`,它会在 `cmake -B build` 配置阶段被读到。用户可以在配置时用 `-DUSE_REAL_SENSOR=ON` 把它翻成 ON。`option` 本质就是带默认值的布尔变量,但它语义上表示"这是一个用户可调的开关",比普通 `set` 更能表达意图,而且 CMake 的 GUI(cmake-gui、ccmake)会把它列进可调选项里。

`if(USE_REAL_SENSOR)` 判断这个开关有没有开。开了就进里面三行。

第一行是个平台守卫,`if(WIN32 OR NOT UNIX)` 表示"如果在 Windows 上,或者根本不是 Unix",就 `message(FATAL_ERROR ...)`。`FATAL_ERROR` 是 CMake 的一个消息级别,它会让配置过程**立刻报错中止**。为什么要这么狠,因为真机后端 `Ap3216cSensor` 用的是 POSIX 的 `open`/`read`/`close` 这套系统调用,Windows 没有这些。你硬要在 Windows 上编译它,会撞一墙的"未定义标识符 open"之类的错,而且这些错报得晚、报得散,新手根本不知道怎么回事。所以干脆在 CMake 配置阶段就拦住,直接告诉你"这个开关只能在 Linux 或板子上用",把一个会发生在编译中途的、让人困惑的失败,提前成一个清晰的配置期错误。早失败、说人话,比晚失败、说鬼话强太多了。

第二行 `target_sources` 把真机后端的两个源文件加进 light-meter 这个目标的编译列表里。注意默认情况下(开关 OFF)这两个文件**根本不参与编译**,这就是为什么你在 Windows 上能编 light-meter,因为 Windows 编译器压根没看见 `ap3216c_sensor.cpp` 里那些 POSIX 调用。开关一开,它们才进编译列表。

第三行 `target_compile_definitions(light-meter PRIVATE USE_REAL_SENSOR=1)` 给目标加一个编译期宏定义 `USE_REAL_SENSOR=1`,等价于在编译命令里加 `-DUSE_REAL_SENSOR=1`。这个宏定义是给 C++ 源码看的,源码里用 `#ifdef USE_REAL_SENSOR` 来判断当前编的是哪个后端,这正是接下来要讲的事。

这三行合起来,做的就是"开关一开,把真机源文件加进编译,再往源码里塞一个 `USE_REAL_SENSOR` 宏"。`target_sources` 管编译哪些文件,`target_compile_definitions` 管源码里能看到什么宏,CMake 控制编译产物就靠这两板斧。

## 条件编译:在 C++ 源码里读那个开关

CMake 塞进去的 `USE_REAL_SENSOR` 宏,C++ 源码怎么用。靠的是预处理器的 `#ifdef` 条件编译。看 light-meter 真正切换后端的地方,注意,它在 `mainwindow.cpp` 里,**不是** `main.cpp`。这是个容易搞错的点,很多人以为后端切换会写在程序入口 main.cpp 里,但 light-meter 把它放在了 `MainWindow` 的构造函数,因为后端是被 `MainWindow` 持有和使用的。

先看头文件包含,`mainwindow.cpp` 开头:

```cpp
#ifdef USE_REAL_SENSOR
#include "ap3216c/ap3216c_sensor.h"
#else
#include "mocked/mockedsensor.h"
#endif
```

`#ifdef USE_REAL_SENSOR` 表示"如果编译时定义了这个宏",就只包含真机后端的头文件,否则只包含 Mock 的。预处理器的 `#ifdef`/`#else`/`#endif` 是在**编译之前**就处理掉的,它 literally 地从源码里删掉不满足条件的那个分支。所以编真机版本时,`mockedsensor.h` 这一行根本不存在;编 Mock 版本时,`ap3216c_sensor.h` 这一行根本不存在。这就是为什么 Mock 版本能编译过、不报"找不到 open",因为 open 那段代码在预处理阶段就被删了。

真正的工厂分支在构造函数里:

```cpp
#ifdef USE_REAL_SENSOR
    m_sensor = std::make_unique<Ap3216cSensor>();
#else
    m_sensor = std::make_unique<MockedSensor>();
#endif
    m_sensor->init(false);   // 注: override 不继承基类默认参数, 显式传 false
```

`m_sensor` 是 `std::unique_ptr<Sensor>`,基类指针,这在第 03 章讲过。这两行 `#ifdef` 决定它实际 new 的是哪个派生类。编真机版本,它 new 一个 `Ap3216cSensor`;编 Mock 版本,new 一个 `MockedSensor`。但往下看,`m_sensor->init(false)` 之后的所有代码,`processSample`、状态机、定时器、CSV 导出,全都只通过 `Sensor*` 这个基类指针跟后端打交道,它们对"底下到底是谁"一无所知,也不关心。

这就是接缝的全部,两处 `#ifdef`,一处管 include,一处管 new 哪个对象,干净得很。`main.cpp` 全文十行,只是 `QApplication` 加 `MainWindow::show()`,它不碰后端切换,所以你以后看 light-meter 别去 main.cpp 里找开关,白找。

## 为什么是编译期开关,不是运行期

你可能想,为什么不做成运行期切换,比如读个配置文件或者命令行参数,程序启动时决定用 Mock 还是真机,这样一份二进制就能两个地方都跑。这是个合理的想法,但 light-meter 选编译期,是有理由的。

根本原因是,Mock 后端和真机后端跑在**两台不同的机器**上。Mock 在你的 Windows 或 Linux 开发机上,真机在 i.MX6ULL 板子上,这两台机器指令集都不一样(板子是 ARM,开发机是 x86),你不可能编出一份在两边都跑的二进制。所以"运行期切换"在这场景下本来就不成立,你为板子编的 ARM 二进制,在开发机上根本启动不了;反过来也一样。既然必然要为不同目标编不同的二进制,那把后端选择放在编译期是最自然的,每个目标编出来就是为那个目标定制的,真机二进制里根本没有 Mock 的代码,Mock 二进制里根本没有 POSIX 调用,各自的二进制都最精简,也没有运行期判断的开销。这就是 host(开发机)和 target(目标板)隔离的工程哲学,你给谁编,编出来就是给谁的,不掺混。

如果哪天你的需求变了,比如要在同一台机器上根据运行时条件选后端(板子上既接了真传感器又想 fallback 到 mock 测试),那时候才考虑运行期策略,比如把后端做成动态加载的插件,或者读配置。但 light-meter 不需要,编译期开关就是最简单够用的方案。**别过度设计**,够用就好,这一条对嵌入式这种"目标固定、需求收敛"的场景尤其贴。

## 为什么能砍这么深:契约先行的回报

现在你能看到第 03 章那个决定的全部回报了。回顾一下,我们在 `Sensor` 基类里做了一件当时看起来多余的事:把 `set_phase` 和 `set_held` 这两个只有 Mock 才用得上的"测试注入口",放在基类里给了空实现 `{}`,而不是放进 MockedSensor 当私有方法。

回报在哪。看 `MainWindow` 的代码,它到处调 `m_sensor->set_phase(...)`、`m_sensor->set_held(...)` 来推进 Mock 的假数据、模拟手靠近。如果这两个方法是 Mock 私有的,那 `MainWindow` 的这些调用就耦合死了 Mock,你切到真机后端时,这些调用全得删掉或者加 `if` 判断"如果现在是 Mock 就 set_phase,真机就算了",那接缝就不止两处 `#ifdef` 了,得散落得到处都是。

但因为它们在基类给了空实现,`MainWindow` 调 `m_sensor->set_phase(...)` 时,Mock 后端真的推进假数据,真机后端走基类的空实现、什么也不发生,代码一行不改。这就是第 03 章说的"留在基类以便 UI 层无差别调用,切换后端时不需改 MainWindow 的调用点"。这件事之所以只翻两处 `#ifdef` 就能换后端,根就在这里:契约先行把所有"后端差异"都吸收进了基类接口,UI 那一侧永远是干净的。

"契约先行"听着像 PPT 里的口号,但它不是。它在你切换实现、扩展功能、加测试的时候,实打实地省下重构的成本。light-meter 是个小例子,你想象一个有十个后端、上百个 UI 调用点的大项目,契约先行省下的修改量是数量级的。这种"多实现、要切换"的系统,谁先在契约上把差异吸收干净,谁后面就少掉头发。

## override 不继承默认参数:一个 C++ gotcha

`m_sensor->init(false)` 那行旁边有个注释"override 不继承基类默认参数, 显式传 false",这里顺手讲掉这个 C++ 经典坑。

第 03 章我们定义基类时,`init` 的签名是 `virtual std::expected<void, InitError> init(bool force_reinit = false) = 0;`,带一个默认参数 `false`。派生类 override 时,`MockedSensor` 和 `Ap3216cSensor` 都写成 `init(bool force_reinit)` **不带默认参数**。

C++ 的规则是,默认参数**不参与虚函数的派发**,它是按**静态类型**在编译期决定的。也就是说,你通过 `Sensor*` 指针调 `init()`,编译器看到静态类型是 `Sensor`,就用 `Sensor` 那份默认参数(false);运行时实际派发到哪个派生类的 init,是另一回事。这有两个坑:一是,如果基类没给默认参数、派生类给了,你通过基类指针调 `init()` 编译都过不了,因为基类那份没默认值;二是,默认参数在派生类里不会"继承"基类的,你得在每个 override 里显式再写一遍(如果你想要的话)。

light-meter 的做法是干脆谁都别依赖默认参数,调用处 `init(false)` 显式把值传进去,清清楚楚,不依赖静态类型是哪个。虚函数 + 默认参数是个危险组合,要么别用默认参数,要么调用处全显式传,这条记一下,"明明基类有默认参数、为什么我 override 里改了不生效"这种 bug 调起来是真的费劲。

## 上手:三路径验证

这一章的上手验证我们走三条编译路径,每条的预期行为都不同。把它当三道关卡,过一遍比看十遍文字都清楚。

第一条,默认 OFF,在你开发机上编 Mock:

```bash
cmake -B build
cmake --build build
./build/light-meter
```

跑起来就是前面几章那个桌面摆件,折线起伏、能告警、能息屏。这是基线。

第二条,在 Linux 开发机上开真机开关编:

```bash
cmake -B build-real -DUSE_REAL_SENSOR=ON
cmake --build build-real
```

它能编译通过(因为是 Linux,过得了那个 `WIN32 OR NOT UNIX` 守卫),真机后端 `ap3216c_sensor.cpp` 参与编译,二进制里编进去的是 `Ap3216cSensor`。但你在开发机上跑 `./build-real/light-meter` 会发现它启动后读不到数据、状态栏报错,因为开发机上没有 `/dev/ap3216c` 这个设备节点,`Ap3216cSensor::init` 会返回 `DeviceUnavailable`。**这是预期行为**,真机二进制本来就该在板子上跑,不是在开发机上。这条路径验证的是"编译能过、后端确实换成了真机",你看到 DeviceUnavailable 别慌,那是它在正确地报"这台上不了网"。

第三条,在 Windows 上开真机开关:

```bash
cmake -B build -DUSE_REAL_SENSOR=ON
```

它会立刻撞上那条 `message(FATAL_ERROR ...)`,CMake 配置中止,告诉你这个开关只能在 Linux 或板子上用。这条验证的是那个平台守卫在干活。

三条路径你跑下来,接缝的机制就算真在自己手上过了一遍。至于真机二进制真正在板子上跑出真实数据,那是后面第 09、10 章的事,我们这一章只管"开关本身怎么工作"。

## 这一章的坑

第一个坑,改了 `USE_REAL_SENSOR` 开关之后忘了重新跑 `cmake -B`。`option` 的值是在配置阶段读进 `CMakeCache.txt` 的,你直接 `cmake --build` 它还用着上次的旧值。改开关就重新配置一次,或者干脆 `rm -rf build` 重来,这是第 01 章讲过的"CMake 缓存会咬人"的又一例,别问我怎么记住这条的。

第二个坑,期待翻个开关、不重新编译就生效。编译期开关意味着你必须重新编译,二进制里编进去的后端才是新的。你以为翻完 `cmake -DUSE_REAL_SENSOR=ON` 就行了,忘了 `cmake --build`,跑的还是旧的 Mock 二进制,然后纳闷"怎么还是假数据"。这种事我至少干过两回。

第三个坑,Windows 上看到 `FATAL_ERROR` 以为出了什么大问题。那就是个守卫,告诉你这个开关在你的平台上不该开,关掉它继续用 Mock 就行,不是 bug。

第四个坑就是上一节的默认参数 gotcha,虚函数带默认参数时,调用处显式传值,别依赖继承来的默认。

## 小结

桌面阶段到这里收口。接缝本身其实没什么花活,就是 CMake 三板斧管编译产物、C++ 预处理器读那个 `USE_REAL_SENSOR` 宏、host 和 target 因为指令集不一样所以老老实实走编译期。真正撑起"只翻两处 `#ifdef` 就能换后端"的,是第 03 章把差异吸收进基类契约那个决定,以及那个 `override` 不继承默认参数的小坑提醒我们:虚函数 + 默认参数,老老实实显式传。

翻完开关你会看到,真机二进制在板子上的行为和桌面 Mock 并不完全一样,折线量级、告警触发、唤醒阈值,可能都得按你自己的板子重新调。这正是下一章的事,怎么把这些默认占位值,标定到位。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="06_self_painted_chart.md" variant="sub">← 06 自绘 ChartView + 息屏遮罩</ChapterLink>
  <ChapterLink href="08_calibrate_to_your_env.md" variant="sub">08 把阈值调成你的:按环境标定 →</ChapterLink>
</ChapterNav>
