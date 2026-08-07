---
title: C++23 + 中文源码
---

# C++23 + 中文源码:`/utf-8` 与 `std::expected` 的第一口

::: info 本节你将学到
- 为什么 light-meter 的源码里满是中文,在 MSVC 上却不会乱码,`/utf-8` 这个开关到底改了什么
- 源字符集和执行字符集是两件事,搞混了就是你那一屏的问号和方块
- `std::expected<T, E>` 解决的是什么问题,它比异常、返回码、`std::optional`、`std::variant` 好在哪
- 怎么读一个 `expected`、怎么构造一个错误、`.value()` 在错误时会发生什么
- 如果你暂时升不到 C++23,用 C++17 的 `std::variant` 怎么近似
:::

::: tip 前置知识
- 第 01 章:你已经能在桌面 cmake 配置加编译一个 Qt 程序,弹出过窗口
- 知道 C 里函数怎么返回错误,返回码、errno,这就够了。异常和现代 C++ 的错误处理我们从零讲
:::

## 两件看起来不搭的事,被同一份 CMakeLists 串着

你翻 light-meter 的 `CMakeLists.txt`,会看到两处乍看没关系、其实都跟"C++23"挂钩的设置。一处是 `set(CMAKE_CXX_STANDARD 23)`,这是我们用 `std::expected` 的前提,第 01 章讲过。另一处在结尾那几行:

```cmake
# 源文件为 UTF-8(无 BOM), 含中文; 告知 MSVC 以 UTF-8 解释源与执行字符集。
if(MSVC)
    target_compile_options(light-meter PRIVATE /utf-8)
endif()
```

这五行注释已经把答案写在脸上了,但没说清楚"源字符集""执行字符集"到底是个啥、为什么只有 MSVC 要管、不加会怎样。所以我们先把这件事讲透,再借着 C++23 这个由头,把 `std::expected` 这个贯穿 light-meter 全代码的错误处理类型,从零讲到你能用得顺手。这两件事看着不搭,共同点其实就一条:它们都是你写第一行 light-meter 代码之前,就得先在 CMake 里配好的基础设施,所以放一起讲顺。

## 中文源码为什么在 MSVC 上会乱码

light-meter 的界面文本几乎全是中文,"桌面照度"、"光线不足,建议开灯"、"已导出"。这些字符串字面量直接写在 `.cpp` 里,而 `.cpp` 文件本身是用 UTF-8 存的。在 GCC 和 Clang 上你什么都不用做,它们默认就按 UTF-8 读你的源码、字符串字面量也按 UTF-8 编进二进制。但 MSVC 不是,这里有个坑。

要理解这个坑,得先把两个概念分清楚,它们是两件事,但名字像,初学者经常混。

源字符集,是编译器**读你那份 `.cpp` 文件**时,把里面的字节当什么编码来解释。你用 VS Code、用 Vim,默认都把文件存成 UTF-8,所以源字符集理想情况下就该是 UTF-8。

执行字符集,是编译器把你写下的字符串字面量,**编进最终二进制里**时用的编码。运行时 `QString`、`std::string` 拿到的字节,就是这个编码的产物。

MSVC 的历史默认行为,是把这俩都设成系统区域设置的代码页,简体中文 Windows 上就是 GBK(代码页 936)。可你的源文件明明是 UTF-8 的。于是 MSVC 按 GBK 去读你那份 UTF-8 的源文件,中文字节就对不上号,轻则报一个 C4819 警告告诉你"源文件里有当前代码页无法表示的字符",重则默默把字符串字面量编成一堆乱码字节,程序跑起来界面全是问号和方块。GCC 和 Clang 默认就按 UTF-8 读源码,所以同一份代码在它们上面没事,这就是为什么这个坑是 MSVC 专属的。

解法就是 `/utf-8` 这个开关。它等价于同时设了 `/source-charset:utf-8` 和 `/execution-charset:utf-8`,也就是告诉 MSVC,源文件按 UTF-8 读,字符串字面量也按 UTF-8 编进二进制。两个都钉死成 UTF-8,中文就老实了。light-meter 的 CMakeLists 里就是用这几行做的:

```cmake
if(MSVC)
    target_compile_options(light-meter PRIVATE /utf-8)
endif()
```

`if(MSVC)` 这个守卫保证这个选项只在 MSVC 上加。GCC 和 Clang 根本不认 `/utf-8`,加了反而报错。这是跨平台 CMake 的常见写法,平台相关的编译选项都用 `if(MSVC)` / `if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")` 这种判断包起来。

### 上手:亲手制造一次乱码

纸上谈兵不如自己撞一次。打开你第 01 章那个 hello-qt,把窗口标题改成中文:

```cpp
window.setWindowTitle("你好 Qt");
```

然后在 `CMakeLists.txt` 里加上上面那段 `/utf-8` 的设置,先确保它**在**。重新编译,标题栏正常显示"你好 Qt"。

接下来这一步有点贱:把 `if(MSVC) ... endif()` 整段**注释掉**,重新编译。如果你在 Windows 上用 MSVC,大概率会看到两种结果之一,要么编译时蹦一个 C4819 警告,要么编译过了但运行起来标题栏是乱码。把那段加回来,重新编译,又好了。这一趟走下来,"源字符集/执行字符集"这件事就从概念变成肌肉记忆了。GCC 和 Clang 用户做这个实验会发现自己怎么改都正常,这本身就说明了那个 `if(MSVC)` 守卫为什么有必要存在。

::: tip 一个常见误区
有人发现乱码后,跑去把 `.cpp` 文件"另存为 GBK 编码"。这能让你在 MSVC 上不报错,但代价是这份源文件在 Linux/macOS 上、在别人那、在 CI 上全变成乱码,git 里 diff 也跟着乱。正确做法永远是保持源文件 UTF-8,然后让 MSVC 按 UTF-8 读,也就是 `/utf-8`。
:::

## std::expected:把错误从返回值里救出来

中文的事解决了,接下来是 C++23 真正的主角,`std::expected`。light-meter 里凡是可能失败的操作,`Sensor::init`、`Sensor::query_once`,返回类型全是 `std::expected<...>`,所以这个东西你必须吃透,不然后面读 sensor 那一层会一脸懵。

先说它要解决的问题。一个函数除了返回正常结果,还可能失败,失败的时候得把错误信息告诉调用者。这件事 C 和老 C++ 有好几种做法,每一种都有代价。

返回码是最朴素的,函数返回 0 表示成功、非 0 表示错误,错误细节塞 errno 或者 out 参数。问题是你太容易忘了检查返回码,编译器不会帮你,于是错误一路被忽略,最后在奇怪的地方炸。异常是 C++ 的"高级"方案,失败就 throw,沿调用栈往上找人接。好处是错误处理和正常逻辑分开了,坏处是控制流隐式、性能有代价,而且嵌入式和实时场景经常禁用异常。`std::optional<T>` 表示"可能有值也可能没有",但它只能告诉你"没有",说不出来"为什么没有",错误信息丢了。`std::variant<T, Error>` 能同时装值和错误,但用起来啰嗦,`std::get`、`std::holds_alternative` 一长串。

`std::expected<T, E>` 就是来填这个坑的。它表示"要么是一个 T 类型的正常值,要么是一个 E 类型的错误",而且把这个意图写进了类型签名里。函数签名 `std::expected<int, ParseErr> parse(...)` 一眼就告诉你:成功给 int,失败给 ParseErr,而且你必须面对错误这个分支,因为它在类型里。

### 它长什么样,怎么用

读一个 `expected` 最基本的方式,是先判它有没有值,再决定取值还是取错误。`expected` 可以隐式转成 bool(有值为 true),也可以调 `.has_value()`。有值时 `.value()` 取出值,出错时 `.error()` 取出错误。还有一个 `.value_or(default)`,出错就用你给的默认值,省得你自己写判断。

构造一个"出错"的 `expected`,得用 `std::unexpected{...}` 把错误包一层。这是因为光写一个错误值进去,编译器分不清你是要存值还是存错误。构造一个"成功"的 `expected` 就简单多了,直接返回那个值就行。

一个最小的例子,一个不会除零的除法:

```cpp
#include <expected>
#include <iostream>

enum class DivErr { DivByZero };

std::expected<double, DivErr> safe_divide(double a, double b) {
    if (b == 0.0) return std::unexpected{DivErr::DivByZero};   // 失败:包一层 unexpected
    return a / b;                                              // 成功:直接返回值
}

int main() {
    auto r = safe_divide(10.0, 0.0);
    if (r) {
        std::cout << "结果: " << r.value() << '\n';
    } else {
        std::cout << "出错: 除零\n";
    }
}
```

`safe_divide` 的签名已经把契约写死了:成功给你 double,失败给你 DivErr。调用者拿到返回值,先 `if (r)` 判一下。这条路其实是绕不开的,因为错误就在类型里,你不处理它就过不了编译(你总得决定是取 value 还是取 error)。这就是 `expected` 比返回码强的地方,编译器逼着你面对失败。

这里有个坑一定要提前讲。`.value()` 在 `expected` 处于错误状态时会**抛异常**,抛的是 `std::bad_expected_access<E>`。也就是说,你不判就直接 `.value()`,出错时程序不会安安静静返回个垃圾值,而是会抛。说实话这其实是好事,比返回码那种"默默继续跑出诡异结果"安全得多,但你要知道它会发生。想完全不抛,就用 `.value_or()`,或者老老实实先 `if (r)` 判一下。

还有一组更高级的链式操作,`and_then`、`or_else`、`transform`,能让你像写管道一样把多个可能失败的调用串起来,不用层层 `if` 嵌套。light-meter 里暂时没用到这套,你先记住 `.value()`、`.error()`、`.value_or()`、`if (r)` 这四样就够读和写了,链式的那套等真需要了再翻 cppreference。

### 为什么 light-meter 到处用它

往后翻一眼 light-meter 的 `sensor/sensor.h`,你会看到这两个签名:

```cpp
virtual std::expected<void, InitError> init(bool force_reinit = false) = 0;
virtual std::expected<SensorData, QueryError> query_once() = 0;
```

`init` 可能打开设备失败,所以返回 `expected<void, InitError>`,注意值类型是 `void`,意思是"成功了不带值,只告诉你成功没成功,失败了给你一个 InitError"。`query_once` 成功带一个 `SensorData`,失败带一个 `QueryError`。这正是 `expected` 最典型的用法:把"正常值"和"错误"都塞进返回类型,逼调用者面对失败。第 03 章我们会把这两个签名掰开揉碎讲,这里你只要建立"`expected` 就是 light-meter 错误处理的通用语言"这个印象就行。

`InitError` 和 `QueryError` 都是 `enum class`,这是 C++11 引入的作用域枚举,值不会污染外层命名空间,具体下一章讲。

## 如果你只有 C++17:用 variant 近似

有的读者手头编译器确实升不到能稳定用 `<expected>` 的版本,但又想跟着 light-meter 走。`std::expected` 是 C++23 才标准化的,但它的核心能力,C++17 的 `std::variant` 能近似,只是写起来啰嗦些。把上面那个 safe_divide 用 variant 改写一下,你就能直观感到差别:

```cpp
#include <variant>
#include <iostream>

enum class DivErr { DivByZero };

std::variant<double, DivErr> safe_divide_v17(double a, double b) {
    if (b == 0.0) return DivErr::DivByZero;
    return a / b;
}

int main() {
    auto r = safe_divide_v17(10.0, 0.0);
    if (std::holds_alternative<double>(r)) {
        std::cout << "结果: " << std::get<double>(r) << '\n';
    } else {
        std::cout << "出错\n";
    }
}
```

`std::variant<double, DivErr>` 表示这个值要么是 double 要么是 DivErr,跟 `expected` 的语义其实一样。但你往读取那一侧看,`std::holds_alternative<double>(r)` 判断、`std::get<double>(r)` 取值,这一长串比 `if (r) r.value()` 啰嗦多了。而且 `variant` 不会在类型里区分谁是"值"谁是"错误",纯靠你记着"第一个模板参数是值、第二个是错误"这种约定。`expected` 的好处就是把这条约定写进了类型,读和写都更顺。所以主线还是推荐 C++23 的 `expected`,实在升不动再用 variant 顶上。

## 这一章的坑

第一个坑,直接 `.value()` 不判断。`expected` 在错误状态下 `.value()` 会抛 `bad_expected_access`,你以为它返回个默认值,结果是程序崩在异常上。要么先 `if (r)`,要么用 `.value_or()`。

第二个坑,把 `expected<T, E>` 和 `optional<T>` 搞混。`optional` 只有"有没有值",`expected` 是"有值还是有错误"。如果你需要知道失败的原因,就用 `expected`;失败就是失败、不关心原因,才用 `optional`。light-meter 全用 `expected`,因为它要区分设备没初始化、设备不可用这些不同错误。

第三个坑还是回到中文,源文件存成了 UTF-8 **带 BOM** 的。MSVC 对带 BOM 的文件会自动识别成 UTF-8,这本来是好事,但有些工具链、有些旧编译器对 BOM 处理不一致,会报奇怪的错误。light-meter 的注释里特意写了"无 BOM",就是让你存成 UTF-8 但不要带 BOM。VS Code 右下角状态栏点编码,选"通过编码保存 UTF-8"而不是"UTF-8 with BOM"。

第四个坑,`enum class` 的错误值忘了用 `std::unexpected` 包。`return DivErr::DivByZero;` 直接返回一个错误值,编译器会以为你要构造的是值类型那个分支,类型对不上就报错。错误必须 `return std::unexpected{DivErr::DivByZero};` 这样包一层。

## 小结

MSVC 上中文不乱,靠的就是 `/utf-8` 把源字符集和执行字符集都钉死成 UTF-8,再用 `if(MSVC)` 守住,只在 MSVC 上加。`std::expected<T, E>` 则是 light-meter 错误处理那套话的语法,它把"值或错误"塞进类型,编译器逼着你面对失败那条路,比返回码安全、比异常轻、写起来也比 variant 顺。这俩都是 light-meter 反复用到的基础设施,后面读代码你会一直撞见它们。

下一章我们正式动 light-meter 的第一份代码,`sensor/sensor.h`,那个被 `std::expected` 撑起来的 Sensor 抽象契约。到时候你会发现,刚学的 `expected` 正好就是它返回类型的语言,而 `enum class` 这种 C++ 基础也会一并从零讲起。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="01_setup_qt6_toolchain.md" variant="sub">← 01 装好 Qt6 与 C++23 工具链</ChapterLink>
  <ChapterLink href="03_sensor_contract.md" variant="sub">03 Sensor 抽象契约 →</ChapterLink>
</ChapterNav>
