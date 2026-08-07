---
title: 装好 Qt6 与 C++23 工具链
---

# 装好 Qt6 与 C++23 工具链

::: info 本节你将学到
- 为什么 Qt 程序不能用 `g++ main.cpp` 一把梭编译,CMake 这个"构建系统生成器"到底替我们干了什么
- 一份最小 `CMakeLists.txt` 每一行在说什么,configure 和 build 两步为什么是分开的
- `find_package(Qt6)` 报"找不到"几乎一定是 `CMAKE_PREFIX_PATH` 没设对,Windows / Linux / macOS 分别填什么
- 为什么这个项目锁 C++23、`std::expected` 对编译器版本的真实门槛、怎么自查
- 亲手建一个空白 Qt 程序,看它把窗口弹出来
:::

::: tip 前置知识
会用命令行、用 `gcc` 编译过一个 Hello World,C 就够。本系列不假设你会 CMake 或现代 C++,这两样本章和后面几章会从零讲。整个第一幕都在桌面跑,不需要开发板。
:::

## 为什么不能 `g++ main.cpp` 一把梭

写 C 的人编译一个程序,大概就是 `gcc main.c -o main` 这么干脆。很多人第一次碰 C++ 和 Qt 也本能地这么干,然后收获满屏的 `undefined reference to 'QApplication::QApplication(int&, char**)'`、`cannot find -lQt6Core`。原因不复杂:Qt 不是语言的一部分,它是一坨装在你硬盘上某个角落的第三方库,编译器既不知道它的头文件在哪,也不知道它的 `.so` 或 `.dll` 在哪。要是你坚持手动编译,命令大概会长成这样:

```bash
g++ main.cpp \
    -I~/Qt/6.8.0/gcc_64/include \
    -I~/Qt/6.8.0/gcc_64/include/QtCore \
    -L~/Qt/6.8.0/gcc_64/lib \
    -lQt6Core -lQt6Widgets -lQt6Gui \
    -fPIC -std=c++23 \
    -o main
```

这还只是一个文件、三个 Qt 模块。等你的项目变成十几个 `.cpp`、用到七八个模块、还要在 Windows 上换成 `.lib` 和反斜杠路径、还要处理 Qt 那个叫 moc 的预处理步骤,手动维护这条命令就彻底不可能了,别跟自己过不去。

构建系统就是来解决这件事的。你在一个叫 `CMakeLists.txt` 的文件里用人话声明"项目叫什么、由哪些源文件组成、依赖哪些库",剩下的事交给它。C++ 世界构建系统一堆,真要打起来 CMake 是那个事实标准,Qt 官方也认它,所以这套教程从第一行起就用它,不绕弯子去讲 qmake 那种老古董。

## CMake 是个什么东西

很多人以为 CMake 是个编译器,它不是。CMake 自己不编译任何东西,它是一个构建系统的生成器:读你的 `CMakeLists.txt`,生成出一份具体的施工单,Linux 上通常是 `Makefile` 配 `make`,Windows 上可能是 Visual Studio 的 `.sln`。真正去调 `g++`、`cl.exe` 干活的,是 `make` 或 VS 这些下游工具,不是 CMake 自己。

这个分工解释了一件让新手一直困惑的事:为什么编译一个 CMake 项目永远是两条命令而不是一条。

第一步 configure,CMake 读 `CMakeLists.txt`,创建 `build/` 目录,生成施工单。这一步它还得踩一圈点,找你机器上 Qt 装在哪、编译器是什么版本、系统有哪些特性,结果缓存到 `build/CMakeCache.txt` 里。所以 configure 偏慢,但只要 `CMakeLists.txt` 不改,就不用重跑。

```bash
cmake -B build          # 这就是 configure
```

第二步 build,是把施工单交给 `make` 或 `ninja`,让它们真正调编译器,把 `.cpp` 一个个编成 `.o` 再链接成可执行文件。这步才是费 CPU 的那一步,但它是增量的,你只改了一个 `.cpp`,它就只重新编译那一个,别的复用上次的产物。

```bash
cmake --build build     # 这就是 build
```

为什么要分两步。因为"看图纸生成施工单"和"按施工单搬砖"是两件性质完全不同的事,前者是一次性的踩点,后者是高频的重复劳动。分开之后,你日常改代码只需要重跑第二步,不用每次都重新踩点,这对大项目省下来的时间相当可观。

::: details 那为什么老教程里直接 make 就行
你可能在老教程里见过直接 `make` 编一个项目。那是因为那些项目的作者事先帮你跑过 configure、把 `Makefile` 提交进了仓库,或者给了你一个 `./configure` 脚本。CMake 项目默认不提交施工单,`build/` 目录都在 `.gitignore` 里,所以你得自己先 configure 一次生成它。本质还是两步,只是老教程把第一步替你藏起来了。
:::

## 一份最小 CMakeLists.txt

下面这份是我们等会儿要亲手建的那个空白 Qt 程序的 `CMakeLists.txt`,也是 light-meter 那份 `examples/light-meter/CMakeLists.txt` 的核心骨架。light-meter 只是多了个 `USE_REAL_SENSOR` 开关,那个留到第 07 章讲。这里先把基础打牢。

```cmake
cmake_minimum_required(VERSION 3.19)
project(hello-qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Widgets)

qt_standard_project_setup()

qt_add_executable(hello-qt main.cpp)

target_link_libraries(hello-qt PRIVATE Qt6::Core Qt6::Widgets)
```

### 项目声明和 C++ 标准

头两行是项目的基本信息。`cmake_minimum_required(VERSION 3.19)` 声明这个脚本至少要 3.19 版的 CMake 才看得懂,CMake 这几年加了不少新语法,这一行是给 CMake 自己设的下限:用老 CMake 跑就直接报错,而不是用旧行为默默跑出错误结果。`project(hello-qt LANGUAGES CXX)` 给项目起名,顺便告诉 CMake 用 C++ 这门语言,于是它会在 configure 阶段去探测你机器上的 C++ 编译器,探不到就报错。

接下来两行管 C++ 标准。`set(CMAKE_CXX_STANDARD 23)` 是 CMake 设置 C++ 标准的标准做法,等价于在最终编译命令里加 `-std=c++23`(GCC/Clang)或 `/std:c++23`(MSVC)。这一行为什么这么关键我们马上讲,先看下一行。`set(CMAKE_CXX_STANDARD_REQUIRED ON)` 是配合它用的,默认情况下如果编译器不支持你要的标准,CMake 会偷偷降级,你要 23、编译器只支持到 20,它就悄悄用 20,然后你踩一晚上坑才发现自己根本没在用 C++23。加上 `STANDARD_REQUIRED ON`,编译器不支持就直接报错。新手务必加这一行,能省掉很多"为什么 `std::expected` 找不到"的深夜。

### 找到 Qt,定义目标,挂上依赖

`find_package(Qt6 6.5 REQUIRED COMPONENTS Core Widgets)` 这一行,意思是去找 Qt6,版本至少 6.5,我只要 Core 和 Widgets 这两个模块,找不到就直接停下来报错。`find_package` 是 CMake 找第三方库的统一接口,它会去找 Qt 官方提供的一个叫 `Qt6Config.cmake` 的"安装说明书",找到之后 `Qt6::Core`、`Qt6::Widgets` 这些目标就能用了。这一行是这一章最大的劝退点,我们紧接着单独开一节讲它为什么经常"找不到"。

`qt_standard_project_setup()` 是 Qt6 提供的一个便利函数,一行打开 Qt 推荐的一组默认设置,最重要的是 AUTOMOC,我们放进下面这个折叠框讲。

::: details AUTOMOC 是什么,为什么 Qt 程序需要它
Qt 有个特有的机制叫"信号与槽",第 05 章会细讲。它依赖一个叫 moc(Meta-Object Compiler)的预处理工具:你写的某些类(带 `Q_OBJECT` 宏的)得先被 moc 扫一遍、生成一段额外的 `.cpp`,才能正常编译。手动管这个预处理非常烦。AUTOMOC 就是让 CMake 自动帮你跑 moc,你正常写代码,CMake 在背后替你处理那一步。`qt_standard_project_setup()` 默认就开了 AUTOMOC,所以你不用自己写 `set(CMAKE_AUTOMOC ON)`。本章的空白程序没用 `Q_OBJECT`,但开着 AUTOMOC 无害,也省得第 05 章再回头改 CMakeLists。
:::

最后两行定义项目要编出来的东西。`qt_add_executable(hello-qt main.cpp)` 定义一个叫 `hello-qt` 的可执行目标,由 `main.cpp` 编译而来,它是 Qt6 增强版的 `add_executable`,除了编可执行文件还顺手帮你处理 Qt 特有的部署细节(Windows 上的部署脚本、macOS 的 `.app` 包)。这里有个词得先认识,target,目标。一个 CMake 项目就是由一堆 target 拼起来的,每个 target 自带一份源文件、依赖、编译选项,后面你会反复跟它打交道。`target_link_libraries(hello-qt PRIVATE Qt6::Core Qt6::Widgets)` 就是给这个 target 挂依赖,等价于在最终命令里加 `-lQt6Core -lQt6Widgets` 和对应的头文件路径。`PRIVATE` 的意思是这俩库只是我自己实现用的、不向外暴露,对一个最终可执行文件来说 PRIVATE 和 PUBLIC 其实区别不大,但养成习惯写 PRIVATE 总没错,省得以后写库的时候翻车。

把这八行连起来读,人话就是:项目叫 hello-qt,用 C++23,依赖 Qt6 的 Core 和 Widgets,把 main.cpp 编成一个可执行文件,链接上 Qt。CMake 的玩法到这就讲得差不多了,你负责声明"要什么",搬砖那部分交给它。

## find_package 找不到 Qt:这是第一章最大的劝退点

好了,你照着上面建好 `CMakeLists.txt`,信心满满跑 `cmake -B build`,大概率撞上这一条:

```
CMake Error at CMakeLists.txt:6 (find_package):
  Could not find a package configuration file provided by "Qt6" with any of
  the following names:
    Qt6Config.cmake
    qt6-config.cmake
```

这条报错劝退了至少一半第一次碰 Qt 的人。它说的不是"你没装 Qt",而是"我找不到 Qt 的安装说明书 `Qt6Config.cmake`"。区别在于,你可能装了 Qt,但 CMake 不知道它装在哪个文件夹,它不会全盘扫描你的硬盘,只在你明确告诉它的几个地方找。

那个"明确告诉它"的机制,就是 `CMAKE_PREFIX_PATH` 这个变量。它的值是一个路径,指向 Qt 的安装根目录,CMake 会在那个路径下的 `lib/cmake/Qt6/` 里找 `Qt6Config.cmake`。所以解法很朴素,把 Qt 装在哪,告诉 CMake。

具体填什么,看你的平台和 Qt 是怎么装的。

Windows 上,如果你用的是 qt.io 官方安装器的 MSVC 版,Qt 装在类似 `C:\Qt\` 下,按版本和编译器分子目录:

```bash
cmake -B build -DCMAKE_PREFIX_PATH="C:/Qt/6.8.0/msvc2022_64"
```

`6.8.0` 是你装的版本号,`msvc2022_64` 是"配合 Visual Studio 2022 的 64 位版",你装的时候选了什么编译器这里就填什么。用正斜杠,Windows 下 CMake 也认,能省掉反斜杠转义的麻烦。

Linux 上走 qt.io 官方安装器的话,默认装在 `~/Qt/`:

```bash
cmake -B build -DCMAKE_PREFIX_PATH="$HOME/Qt/6.8.0/gcc_64"
```

但 Linux 桌面开发其实有更省事的方式,就是用发行版的包管理器。Ubuntu 24.04 上 `sudo apt install qt6-base-dev` 一把下去,Qt 的 `Qt6Config.cmake` 会装在系统标准路径 `/usr/lib/cmake/Qt6/` 下,CMake 默认就会扫到,通常不用再设 `CMAKE_PREFIX_PATH`:

```bash
sudo apt install qt6-base-dev    # 一次
cmake -B build                   # 通常直接能找到
```

这里有个坑要注意,发行版仓库里的 Qt 版本可能偏老,Ubuntu 22.04 仓库里就基本拿不到能用的 Qt6。还有件事先打个预防针,板子上那套 Qt 是 Buildroot 编出来的,跟你桌面这套不是同一份,这个版本协调的麻烦事留到第 10 章上板时再细说,这里不展开。

macOS 上,qt.io 官方安装器:

```bash
cmake -B build -DCMAKE_PREFIX_PATH="$HOME/Qt/6.8.0/macos"
```

如果你不确定自己该填哪个路径,就去硬盘上找 `Qt6Config.cmake` 这个文件,把它所在路径往上回溯,去掉 `lib/cmake/Qt6/` 那一段,剩下的就是 `CMAKE_PREFIX_PATH` 该填的值。比如文件在 `~/Qt/6.8.0/gcc_64/lib/cmake/Qt6/Qt6Config.cmake`,那 `CMAKE_PREFIX_PATH` 就是 `~/Qt/6.8.0/gcc_64`。

## 为什么是 C++23,以及你的编译器够不够新

你可能注意到了,`CMakeLists.txt` 里我们写了 `set(CMAKE_CXX_STANDARD 23)`,不是 20 也不是 17。因为这个项目用了一个 C++23 才标准化的东西,`std::expected`,第 02 章会专门讲它是什么、为什么用它。它的头文件是 `<expected>`,只有 C++23 起的标准库才提供。

这就引出一个实打实的版本门槛,你的编译器得够新,标准库里才有 `<expected>`。先别急着想"我装的 GCC 应该够新吧",我们先确认一下,免得第 02 章你写 `#include <expected>` 直接报 `expected: No such file or directory`,然后怀疑人生。

各编译器对 `<expected>` 的最低可用版本大致是这样:

| 编译器 | 最低可用版本 | 自查 |
|---|---|---|
| GCC | 14 及以上最稳(12/13 部分支持,容易踩坑) | `gcc --version` |
| Clang + libc++ | 17 及以上 | `clang --version` |
| MSVC | VS 2022 17.10+(`cl` 19.40+) | VS Installer,或命令行 `cl` |

::: warning Ubuntu 22.04 用户特别注意
Ubuntu 22.04 默认仓库的 gcc 是 11,远达不到 `<expected>` 的要求,你会在第 02 章直接撞 `expected: No such file`。两条出路,升级到 Ubuntu 24.04(默认 gcc-13,仍偏旧但勉强能用),或者用 toolchain PPA 装个 gcc-14:

```bash
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update && sudo apt install gcc-14 g++-14
# 用的时候指定 g++-14 而不是 g++
```
:::

最快的确认方法其实不是查版本号,而是直接让编译器试编一段用到 `<expected>` 的代码。这招比看版本号靠谱得多,因为有些版本号够了、标准库却没跟上:

```bash
cat > /tmp/t.cpp <<'EOF'
#include <expected>
#include <iostream>
int main() {
    std::expected<int,int> v = 42;
    std::cout << *v << '\n';
}
EOF
g++ -std=c++23 /tmp/t.cpp -o /tmp/t && /tmp/t    # 期望打印 42
```

能编、能跑出 42,你这台机器就 C++23 就绪,放心往下走。报 `expected: No such file or directory` 就是编译器或标准库太旧,按上面那张表升级。

有的读者手头就是一台老机器老发行版,升 gcc 要 root、要审批,一时半会儿升不动。说实话没关系,`std::expected` 想解决的事,一个函数可能返回值、也可能返回错误、要把这两种情况都塞进类型里,用 C++17 也能近似,标准库的 `std::variant<T, Error>`,或者干脆返回一个带错误码的 struct。第 02 章会在讲完 `std::expected` 之后补一小段"如果你只有 C++17 怎么办"的 fallback 写法,不至于被工具链卡死。不过本项目主线就是 C++23,能升还是尽量升。

## 上手:建一个空白 Qt 程序,弹出窗口

讲了一堆原理,该动手了。这一章的目标很朴素,用你刚学的 CMake 知识建一个最小的 Qt 程序,在屏幕上弹出一个空白窗口。我们暂时只用 ASCII 纯英文,中文和那个 `/utf-8` 的坑留到第 02 章专门拆。

随便找个空目录,建两个文件:

```cpp
// main.cpp
#include <QApplication>
#include <QWidget>

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);   // 每个 Qt Widgets 程序都得有这一个,管事件循环
    QWidget window;                  // 一个空白窗口控件
    window.resize(400, 300);
    window.setWindowTitle("hello qt");
    window.show();                   // 控件默认不显示,要 show()
    return app.exec();               // 进入事件循环,直到关窗口才返回
}
```

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.19)
project(hello-qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Widgets)

qt_standard_project_setup()

qt_add_executable(hello-qt main.cpp)

target_link_libraries(hello-qt PRIVATE Qt6::Core Qt6::Widgets)
```

然后就是那两步,把 `CMAKE_PREFIX_PATH` 换成你那个平台的值,Linux apt 装的可以省略:

```bash
cmake -B build -DCMAKE_PREFIX_PATH="<你的 Qt 路径>"   # configure
cmake --build build                                     # build
```

跑起来:

```bash
./build/hello-qt                  # Linux
build\Debug\hello-qt.exe          # Windows,Debug 或 Release 看生成器
open build/hello-qt.app           # macOS
```

屏幕上弹出一个 400×300 的空白窗口,标题栏写着 hello qt,能关掉、能拖动。很好,工具链通了。这扇破窗口长得不咋地,但它替你证明了一件事,Qt6 装对了、C++23 编译器认了、CMake 的两步走确实把 `.cpp` 变成了能跑的程序,这一章的目的就达到了。

`main.cpp` 里那几行 Qt 代码现在看不懂很正常,`QApplication`、`QWidget`、`app.exec()` 这些是 Qt 的入门概念,留到第 05 章搭 light-meter 的 UI 时从"事件循环是什么"开始系统讲。这一章的重点是工具链和 CMake,代码只是用来验证工具链跑通的最小载体,别盯着它纠结。

## 这一章的坑

第一个坑,`Could not find Qt6`。十有八九是 `CMAKE_PREFIX_PATH` 没设或者设错,回到上面那个"不确定该填哪个路径"的办法,用 `Qt6Config.cmake` 的实际位置回溯。

第二个坑在 Linux apt 装的 Qt6 上,版本太旧或者残缺。Ubuntu 22.04 仓库的 Qt6 基本不可用,要么升发行版,要么用 qt.io 官方安装器。`apt show qt6-base-dev` 看一眼版本号就心里有数了。

Windows 上的第三个坑是生成器选错。`cmake -B build` 默认可能挑了不是你 Qt 对应的生成器,比如你装的是 MSVC 版 Qt,CMake 却默认用 MinGW 生成器。最省心的办法是用 Visual Studio 直接打开 `CMakeLists.txt`,VS 自带 CMake 支持会自动配好 MSVC 生成器;命令行党可以显式指定 `cmake -B build -G "Visual Studio 17 2022"`。

第四个坑比较阴,`CMAKE_CXX_STANDARD_REQUIRED` 没加,你以为在用 C++23 其实偷偷降到了 20,然后第 02 章 `#include <expected>` 报错,你却以为是代码写错了。我们的模板里这一行已经在了,别删。

最后一个坑会陪我们走完整个系列,就是 `build/` 目录被搞脏。你改了 `CMAKE_PREFIX_PATH` 或者换了 Qt 版本,但 `cmake --build` 还是老样子,因为 `build/CMakeCache.txt` 缓存了旧的探测结果。解法很粗暴,`rm -rf build` 删掉重来。CMake 的缓存是好东西,但它也会咬人,这个机制第 07 章讲编译开关时还会再撞上。

## 小结

你可能会想,弹个空白窗口至于讲这么多吗。说实话挺至于的。CMake 那两步走、target 这个概念、`find_package` 跟 `CMAKE_PREFIX_PATH` 怎么对上、C++ 标准号和编译器版本谁对应谁,这些不是装完就完的一次性知识,是后面每一章翻 `CMakeLists.txt` 都要默默读一遍的东西。这章把它们磨一遍,后面 light-meter 的构建脚本就不会有哪行是凭空冒出来的。

回头看 light-meter 的 `examples/light-meter/CMakeLists.txt`,你现在应该能看懂除了 `USE_REAL_SENSOR` 那一段之外的每一行。剩下的那一段是编译期切换真机和 Mock 后端的开关,留到第 07 章讲,它搭的就是你这一章学的 `option`、`target_compile_definitions` 那几个机制,逃不掉的。

下一章换口味,把源码里冒出来的中文和 `std::expected` 这个 C++23 新家伙一起讲透,期间你会亲手把 `/utf-8` 删掉、制造一次中文乱码,再加回来修好。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="./" variant="sub">← 项目总览</ChapterLink>
  <ChapterLink href="02_cpp23_utf8_expected.md" variant="sub">02 C++23 + 中文源码 →</ChapterLink>
</ChapterNav>
