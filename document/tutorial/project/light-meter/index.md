---
title: 照度护眼摆件 light-meter
---

<PageHeader icon="💡" title="照度护眼摆件 light-meter" description="从一份空的 CMakeLists 到一个在板子上会呼吸、会告警、会息屏的真实产品,这一套手把手教你造一个嵌入式 Qt 工程的完整方法论" />

## 前言:这一套教你造工程,不是讲产品

说实话,网上大多数嵌入式项目教程要么是一个干巴巴的功能清单,今天我们点亮一颗 LED,要么是一个跑不起来的成品堆砌,略去一万字、代码自己看。light-meter 这个系列不打算这么干。我们要做的,是把你从一份空的 `CMakeLists.txt` 一步步带到一个在 i.MX6ULL 板子上常驻运行、会按环境光告警、会按接近度唤醒和息屏、能导出 CSV 的真实产品,全程不跳步。

这一刀砍下去,你带走的不是"我又抄了一个照度计",而是一套能用到下一个项目、下 N 个项目的造工程方法论,这才是含金量所在,下一节专门讲。

关于硬件依赖只有一处要事先说明。AP3216C 的内核驱动不在本系列里重讲,它指给你本仓库的 [driver/08 AP3216C I2C 驱动](../../driver/08_i2c_ap3216c_driver/),那里手把手教你把 `/dev/ap3216c` 写出来,本系列从"用户空间怎么消费这个 `/dev/ap3216c`"接上。除此之外,C++23、Qt6、CMake、Mock、部署、标定,全在这套教程里讲够,不假设你先读过别的卷。

## 先看成品

废话不多说,这就是这套教程带你造出来的东西,完整跑起来是这样:

<video controls muted playsinline preload="metadata" poster="/imx-forge/light-meter/demo-poster.png" style="width:100%;max-width:720px;border-radius:12px;border:1px solid var(--vp-c-divider);margin:16px auto;">
  <source src="/imx-forge/light-meter/demo.mp4" type="video/mp4" />
  你的浏览器不支持 video 标签,可 <a href="/imx-forge/light-meter/demo.mp4">直接下载视频</a> 看。
</video>

桌面 Mock 阶段 Windows 和 Linux 双平台能跑,翻一个 CMake 开关接上 AP3216C,板子上就是视频里这样:折线随环境光实时起伏、跌破阈值翻红告警、手靠近唤醒、无接近 10 秒息屏。

## 这个产品是什么

一个常驻桌面或床头的照度护眼摆件。它有三种状态:运行态每 200ms 采样一次环境光,左侧大数字显示当前 lux,右侧一条 30 秒滚动的折线;告警态在 lux 跌破阈值时触发,国标 GB 50034 规定书桌阅读要 300 lux 以上,低于这个值左侧数字卡就翻红,提示"光线不足,建议开灯";息屏态是无接近 10 秒后全屏变黑、只留中央一个慢呼吸点,手靠近、按空格或者点屏幕就能瞬间唤醒。

它的两个 git commit 就是本系列的脊柱。这两个提交在 `feat/first_project` 分支上(合入主线时被压缩成了一个提交,所以在主线 `git log` 里找不到它们),用 `git log --oneline origin/feat/first_project` 能看到:`0bb4252` 是桌面 Mock 阶段的全部,Windows 和 Linux 双平台都能跑、不接硬件;`be4fb4d` 是真机后端接入,翻一个 CMake 开关就去读你板子上那颗真实的 AP3216C。本系列的章节顺序,就是沿着这两刀走的。

## 目录速览

`examples/light-meter/` 的文件树,每个文件对应本系列某一章:

```
light-meter/
├── CMakeLists.txt          # C++23/Qt6 配置 + USE_REAL_SENSOR 开关(07 章拆)
├── main.cpp                # 10 行 trivial 入口(工厂分支不在这,在 mainwindow.cpp)
├── sensor/
│   ├── sensor.h            # 抽象 Sensor 契约(03 章,字段名 luxury 是个拼写 wart，问就是手滑写错了懒得改，逃)
│   ├── mocked/             # Mock 后端 + custom-deleter pImpl(04 章)
│   └── ap3216c/            # 真机 POSIX 客户端(09 章)
├── mainwindow.{h,cpp}      # 三态状态机 + 工厂分支 + 定时器 + CSV/OOM(05 章)
└── ui/
    ├── chart_view.{h,cpp}      # 自绘折线 + 真环形缓冲(06 章)
    └── breathing_overlay.{h,cpp}  # 息屏遮罩 + 跨平台陷阱(06 章)
```

有一点要先给你提个醒,README.md 只覆盖 Mock 阶段,它明确写"本阶段为 Mock 不接真硬件",目录树里都省略了 `ap3216c/`。`USE_REAL_SENSOR` 这个开关的存在得从 `CMakeLists.txt` 里发现,这是 README 留给你的一个小坑,第 07 章会把它填上。

## 学习路径

第一幕是桌面 Mock,第 01 到 06 章,全程不需要板子。你在 Windows 或 Linux 笔记本上用一个假数据后端把整条软件链路调到完美,这一幕结束时你已经有一个会呼吸、会告警、能导出 CSV 的完整桌面应用,一行板子代码都没碰。

1. 01 装好 Qt6 与 C++23 工具链,把 `CMAKE_PREFIX_PATH` 钉死、确认编译器够新
2. 02 C++23 加中文源码,亲手删 `/utf-8` 造一次乱码再修好,顺便学 `std::expected`
3. 03 Sensor 抽象契约,为什么先把接口钉死再写 UI
4. 04 MockedSensor,正弦 lux 加一套 custom-deleter 的轻量 pImpl
5. 05 三态 UI 加状态机加定时器编排,顺带把 CSV 导出和 OOM 防线讲了
6. 06 自绘 ChartView 加息屏遮罩,为什么没有 GPU 就必须自己画

第二幕是接缝,第 07、08 两章,是整个系列的转折点。

7. 07 一行 CMake 开关切后端,以及为什么这一刀能砍这么深
8. 08 把阈值调成你的,按你自己的板子和测试环境标定 lux 系数和几个阈值

第三幕是真机,第 09 到 11 章,从这里开始需要板子上已经跑着 AP3216C 的驱动。

9. 09 POSIX 字符设备客户端,`/dev/ap3216c` 加上 `{ir,als,ps}` 的协议对齐
10. 10 上板部署,linuxfb 加 tslib 加 NFS 开发循环
11. 11 收束,画一张全栈数据流图,把造工程的方法论回顾一遍

章节随写随上,可点击的导航见下面[章节目录](#章节目录)。

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_setup_qt6_toolchain.md">装好 Qt6 与 C++23 工具链</ChapterLink>
  <ChapterLink num="02" href="02_cpp23_utf8_expected.md">C++23 + 中文源码</ChapterLink>
  <ChapterLink num="03" href="03_sensor_contract.md">Sensor 抽象契约</ChapterLink>
  <ChapterLink num="04" href="04_mocked_backend.md">MockedSensor 与 custom-deleter pImpl</ChapterLink>
  <ChapterLink num="05" href="05_three_state_ui.md">三态 UI + 状态机 + 定时器编排</ChapterLink>
  <ChapterLink num="06" href="06_self_painted_chart.md">自绘 ChartView + 息屏遮罩</ChapterLink>
  <ChapterLink num="07" href="07_cmake_seam.md">THE 接缝:一行 CMake 切后端</ChapterLink>
  <ChapterLink num="08" href="08_calibrate_to_your_env.md">把阈值调成你的:按环境标定与微调</ChapterLink>
  <ChapterLink num="09" href="09_ap3216c_client.md">POSIX 字符设备客户端</ChapterLink>
  <ChapterLink num="10" href="10_board_deploy.md">上板部署</ChapterLink>
  <ChapterLink num="11" href="11_wrap_up.md">收束:全栈数据流图与方法论回顾</ChapterLink>
</ChapterNav>

::: tip 学习目标
把"传感器抽象、mock 先行、编译期后端切换、显式状态机、无 GPU 自绘、驱动协议对齐、按环境标定"这一整套造工程的方法论,在 light-meter 这一个真实产品里走一遍。走完之后,这套招式你能直接搬到下一个嵌入式 Qt 项目。
:::

::: info 前置知识,自包含,只有一处外链
本系列自包含,不要求你先读完 buildroot 或 practical。唯一的硬依赖是硬件驱动,driver/08 AP3216C I2C 驱动是第三幕第 09 到 11 章的前置,你的板子上得有能读 `{ir,als,ps}` 的 `/dev/ap3216c`。如果你只走第一、二幕,也就是桌面 Mock 加接缝机制,暂时不需要它。另外需要一点 C++ 基础,本仓库没有 C++ 教程卷,linux-basics 是纯 C,所以第 01、02 章会把 C++23 工具链和 `std::expected` 从零讲起,不会默认你已经会现代 C++。
:::

::: details 延伸阅读
- [cppreference std::expected](https://en.cppreference.com/w/cpp/utility/expected)
- [PROJ-001 便携式环境监测站](../../../todo/projects/proj-001-env-monitor.md),light-meter 是它的光照单传感器切片,走完本系列你掌握 PROJ-001 的 Sensor 契约加 Qt 骨架约八成。
- [D3 示例路线图](../../../todo/directions/d3-examples.md)
:::

## 常见问题

### 为什么先做 Mock,不直接上板

三个理由。一是 不卡硬件,你可以在笔记本上把 UI 和状态机调到完美,不用每改一行就交叉编译加烧录。二是 双平台验证,Mock 在 Windows 和 Linux 都能跑,提前把跨平台的坑,比如 MSVC 的 `/utf-8`、`M_PI` 未定义,在桌面就踩掉。三是 契约先行,逼你先把 Sensor 抽象钉死,后端就变成可插拔的了。这一刀的回报在第 07 章兑现,翻一个 CMake 开关,UI 的调用点一行不改。

### 翻完 USE_REAL_SENSOR=ON,真机行为和 Mock 一样吗

真机我们跑通过、行为验过,放心。但要提醒一句,代码里的默认常量,`lux_coeff`、告警阈值、唤醒阈值,是按我们这块板子和测试环境调的,你的板子、你的镜头透光率、你房间的照度都和我们不一样。所以第 08 章是手把手教你怎么按自己的环境把这些值微调到位,这不是修坑,是任何涉及物理量换算的产品都要做的常规最后一步。threshold 滑杆在运行时就能拖,即时调告警线,`lux_coeff` 和几个编译期默认值则放在第 08 章标定。

### 我还没做 driver/08 驱动,能跟这套教程吗

能,但只能走到第二幕。第一幕第 01 到 06 章是纯桌面 Mock,不需要任何硬件,第二幕第 07、08 章的接缝机制和标定方法也能在桌面理解。只有第三幕第 09 到 11 章真正需要板子上已加载 `ap3216c.ko`、有可读的 `/dev/ap3216c`,那就先去跟 driver/08,回来接着走。

### 这套教程和 PROJ-001 环境监测站什么关系

light-meter 是 PROJ-001 的光照单传感器切片。PROJ-001 要加温湿度、气压、陀螺仪,加 MQTT 上云,加 Web 看板,但它的 Sensor 抽象层加 Qt UI 骨架加驱动桥接,就是你在这套教程里走一遍的那套。做完 light-meter,你离 PROJ-001 只差多加几个后端加一个网络层。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 应用项目</ChapterLink>
  <ChapterLink href="01_setup_qt6_toolchain.md" variant="sub">01 装好 Qt6 与 C++23 工具链 →</ChapterLink>
</ChapterNav>
