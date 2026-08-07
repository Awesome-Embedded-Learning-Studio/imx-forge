---
title: 上板部署
---

# 上板部署:linuxfb 运行环境与 NFS 开发循环

::: info 本节你将学到
- 怎么把 light-meter 交叉编译成能在板子上跑的 ARM 二进制
- linuxfb 这套运行环境是怎么回事,`QT_QPA_PLATFORM` 那一组环境变量每个在干什么
- 怎么用 evtest 动态发现触摸屏设备,别照抄 `event0`
- 一个 NFS 开发循环,桌面改代码、交叉编译、板子上 10 秒后见效,告别每次改一行就重烧镜像
- 中文字体为什么会在板子上变方块,以及怎么解决
:::

::: tip 前置知识 · 硬前置
- 第 07 到 09 章,真机二进制能编出来、能在板子上读到真实数据
- **driver/08 和 buildroot/11 是硬前置**:板子上必须已经有可读的 `/dev/ap3216c`,而且 rootfs 必须是带 linuxfb 加 tslib 的 Qt6 rootfs(就是 buildroot/11 那篇 `--with-qt6` 编出来的)
:::

## 这一章干的两件事

到上一章为止,light-meter 的真机二进制你已经能编出来、能在板子上读到真实 `{ir,als,ps}` 了。但说实话,那还只是一个 5 行 main、在串口终端里打印数字的状态,离"做完了"差得远。这一章要把那个完整的 light-meter GUI 推到板子的屏幕上,而且要跑得不憋屈。

具体两摊事要一起办。一摊是 Qt 在板子上的运行环境,linuxfb 把界面画到 LCD、tslib 读到正确的触摸坐标,这套不配好,程序能跑但屏上什么都没有。另一摊是 NFS 开发循环,搭好之后改一行代码、交叉编译完,板子上 10 秒就能看到新效果,不用再为了一行改动重烧整个镜像。两摊事的优先级我自己排下来,NFS 循环其实更想早一点装上,因为没它的话这一章后面每改一处 UI 都得烧镜像,人会废掉。

## 交叉编译 light-meter

第 01 章我们在桌面编 light-meter 用的是主机编译器,编出来是 x86 二进制,板子跑不了。板子是 ARM,得用交叉编译。交叉编译的核心就是告诉 CMake 两件事:用哪个编译器(`arm-linux-gnueabihf-g++` 这类),还有 Qt6 库在哪个 sysroot 里。

CMake 管这件事的标准机制是工具链文件,一个 `.cmake` 文件,配置时用 `CMAKE_TOOLCHAIN_FILE` 指给它:

```bash
cmake -B build-board \
    -DCMAKE_TOOLCHAIN_FILE=<你的 toolchain.cmake 路径> \
    -DCMAKE_PREFIX_PATH=<板子 sysroot 里的 Qt6 路径> \
    -DUSE_REAL_SENSOR=ON
cmake --build build-board
```

工具链文件里大致是这几行,指定目标系统和交叉编译器:

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER   arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_FIND_ROOT_PATH <板子 sysroot>)
```

那个 sysroot 和里面的 Qt6,来自 buildroot 的产物。buildroot/11 那篇讲了怎么用 `--with-qt6` 编出一个带 Qt6 6.9.1 的 rootfs,这个 rootfs 对应的 sysroot 里就有交叉编译版的 Qt6 库和头文件,`CMAKE_PREFIX_PATH` 指到那里,`find_package(Qt6)` 才能找到**板子那一版** Qt6 而不是你桌面的。

这里有个版本协调的点要单独拎出来,我自己在这卡过。桌面开发用的 Qt6 可能是 6.8,板子 rootfs 里 buildroot 编的是 6.9.1,交叉编译 light-meter 时,一定要让它链板子那版 sysroot 里的 Qt6,别误链桌面版的。否则编出来在板子上很可能起不来,Qt 的某些插件、ABI 在小版本间不一定兼容。养成个习惯:交叉编译永远显式指 sysroot 的 Qt6 路径,别让它顺手找到桌面的。

## linuxfb 运行环境:那一组环境变量

二进制有了,直接在板子上 `./light-meter` 大概率跑不起来,因为它不知道往哪个屏幕画、从哪读触摸。Qt 在板子上靠一组环境变量来定这些,就是 buildroot/11 那篇讲的 linuxfb 加 tslib 那套。rootfs 怎么编出 Qt6 不重述,链到 buildroot/11,这里只看应用侧要配什么。

板子上跑 light-meter 之前,export 这一组:

```bash
export QT_QPA_PLATFORM=linuxfb:fb=/dev/fb0
export QT_QPA_PLATFORM_PLUGIN_PATH=/usr/lib/qt6/plugins
export QT_QPA_FB_TSLIB=1
export TSLIB_TSDEVICE=/dev/input/eventN      # N 要你自己发现,见下一节
export TSLIB_FBDEVICE=/dev/fb0
export TSLIB_PLUGINDIR=/usr/lib/ts
export TSLIB_CALIBFILE=/etc/pointercal
```

逐个说。`QT_QPA_PLATFORM=linuxfb:fb=/dev/fb0` 告诉 Qt 用 linuxfb 这个平台插件,直接画到 framebuffer,不需要 X 或 Wayland,这正合适没有 GPU 的 i.MX6ULL,并且 framebuffer 设备是 `/dev/fb0`。`QT_QPA_PLATFORM_PLUGIN_PATH` 指向 Qt 平台插件目录,板子上通常是 `/usr/lib/qt6/plugins`,不对的话以你 rootfs 实际为准。`QT_QPA_FB_TSLIB=1` 是告诉 linuxfb 插件"触摸输入从 tslib 走,别自己去读 event 设备"。

下面那一组 `TSLIB_*` 是 tslib 触摸校准的标配。tslib 是一层触摸事件过滤和校准,Qt 不直接读原始触摸 event,而是从校准后的事件流读坐标。`TSLIB_TSDEVICE` 指向触摸屏的 input 事件设备,这个特别关键,下一节专门讲怎么发现它,千万别照抄 `event0`。`TSLIB_FBDEVICE` 是 framebuffer,和上面的 fb0 一致。`TSLIB_PLUGINDIR` 是 tslib 滤镜插件目录,`TSLIB_CALIBFILE` 是校准结果存放位置。

### 别照抄 event0:动态发现触摸设备

`TSLIB_TSDEVICE` 那个 `eventN`,N 是几,取决于你的触摸控制器在内核里注册的顺序,不同板子、不同外设组合下都不一样。正点原子这块屏的 Goodix 触摸挂在 i2c-1 上,上电之后它具体落在哪个 eventN 得自己查,buildroot/11 那篇也特意警告过"别照抄"。

查的办法是用 evtest,板子上跑:

```bash
evtest
```

它会列出所有 `/dev/input/event*` 设备让你选,你逐个看,触摸屏那个会在你按屏时疯狂刷事件、名称里通常带 "Goodix" 或 "Touch"。或者更轻量的办法,`cat /proc/bus/input/devices`,看每个设备的 Name 和 Handlers,Handlers 里写着它对应 `eventN`。找到触摸屏对应的 N,填进 `TSLIB_TSDEVICE=/dev/input/eventN`。input 设备编号在嵌入式上是真不固定,所以这一步别想着抄一个数一劳永逸,得养成上来先查的习惯。

定好了设备,先校准一次再跑 light-meter:

```bash
ts_calibrate    # 屏上点五个点,结果写到 /etc/pointercal
ts_test         # 可选,拖一个图标满屏跑,验证校准准不准
```

校准完,`./light-meter` 应该就能在屏上画出来、触摸也能响应了。

## 中文字体方块:链到 buildroot/11

跑起来你可能会撞上第二个坑,界面上的中文全是方块,英文正常。这是因为板子的 rootfs 里没有中文字体。Qt 默认带的 DejaVu 字体只覆盖西文和基础符号,中文那些字形它没有,就画成方块。

这个问题的完整解法在 buildroot/11 那篇的"字体这一摊"那节,post-build 脚本会嗅探 rootfs 里有没有 `libQt6Core.so`,有就自动下 Noto CJK 中文字体进去。所以正常情况下,你用 buildroot/11 那套 `--with-qt6` 编出的 rootfs,中文字体是齐的,light-meter 的中文应该能正常显示。如果你用的是别的方式做的 rootfs、字体没齐,要么回去补 buildroot/11 那套字体逻辑,要么手工往 rootfs 的 `/usr/share/fonts/` 塞一个 Noto Sans CJK,fontconfig 启动时会自动扫到。这部分细节不重述,链到 buildroot/11。

## NFS 开发循环:改一行,10 秒见效

这是这一章真正要给自己装上的"武器"。如果每次改 light-meter 一行代码,都要重新 build rootfs、重新烧镜像到板子,一个迭代周期十几分钟,折腾两轮人就废了。NFS 开发循环能把这周期压到 10 秒。

思路是这样。开发机和板子在同一局域网里,开发机用 NFS 导出一个目录,板子把它挂载到本地,这个目录里放 light-meter 的交叉编译产物。我们在开发机上改代码、交叉编译,产物直接落进这个导出目录,板子上重新 `./light-meter` 就跑的是新版,整个过程不碰 rootfs、不烧镜像。

开发机上配导出,在 `/etc/exports` 加一行(路径按你实际改):

```
/srv/lightmeter-build  <板子IP>(rw,sync,no_root_squash,no_subtree_check)
```

`exportfs -ra` 让它生效。把 light-meter 交叉编译的输出指到这个目录,`cmake --build` 之后二进制就在 `/srv/lightmeter-build/light-meter`。

板子上挂载(板子 IP 能 ping 通开发机之后):

```bash
mount -t nfs <开发机IP>:/srv/lightmeter-build /mnt/dev
ls /mnt/dev/light-meter     # 看到二进制
```

之后开发循环就三步走:开发机上改代码、`cmake --build build-board`,板子上 `./mnt/dev/light-meter` 重跑。第二步如果是增量编译、只改了一个 `.cpp`,几秒就完事,板子上重跑也是秒级,合起来 10 秒级见效。这套循环是嵌入式 Linux 应用开发的标配,buildroot/practical 那边的 NFS 讲的是另一种用法(网络挂载整个 rootfs 切版本),这里用的是只共享应用产物目录的轻量版,两者不冲突,看你迭代的是 rootfs 还是应用,选合适的就行。

::: tip 顺带把环境变量固定下来
上面那一大坨 `QT_QPA_PLATFORM`、`TSLIB_*` 环境变量,每次手 export 太累。写个小脚本 `run-lm.sh` 放板子上,里面 export 完所有变量再 `./light-meter`,以后跑一行 `./run-lm.sh` 就行。NFS 挂载也可以写进 `/etc/fstab` 或开机脚本,板子一启动就挂上。
:::

## 上手:改一处 UI 文本,板上 10 秒见

整套环境搭起来,做个最直观的验证。开发机上把 light-meter 里某处中文改一下,比如把告警态的"光线不足,建议开灯"改成"该开灯啦"。`mainwindow.cpp` 里改这一行,然后:

```bash
# 开发机上
cmake --build build-board          # 增量编译,几秒
```

板子上重新跑:

```bash
./run-lm.sh                        # 重新启动 light-meter
```

10 秒内,板子屏幕上那个新文本"该开灯啦"就出来了,全程没动 rootfs、没烧镜像。然后用这套三态 UI 在板子上完整验一遍:折线随环境光实时动(真传感器数据)、lux 跌破阈值翻红告警、手靠近触发唤醒、无接近 10 秒息屏、触摸阈值滑杆能拖、中文不乱码。这一套都过了,light-meter 才算真在板子上活了,而不是只在桌面上活着。

## 这一章的坑

第一个坑,`TSLIB_TSDEVICE` 照抄 `event0`,结果触摸没反应。用 evtest 动态发现真实的 eventN,不同板子不一样。

第二个坑,交叉编译误链了桌面版 Qt6 而不是板子 sysroot 那版。`CMAKE_PREFIX_PATH` 一定指向板子 sysroot 的 Qt6,版本要对上板子 rootfs 的 6.9.1。编出来跑不起、报插件加载失败,十有八九是这个。

第三个坑,没跑 `ts_calibrate` 直接上,触摸点击位置是偏的。tslib 的校准数据没生成,坐标没校准,先 `ts_calibrate` 点五点。

第四个坑,NFS 挂载偶发 "stale NFS file handle"。一般是开发机那边导出目录有变动或 NFS 服务重启过,板子上 `umount` 再 `mount` 一次通常就好。长期跑可以把 mount 选项调稳。

第五个坑,中文方块,以为程序坏了。其实是字体,不是逻辑 bug,回 buildroot/11 那篇补 CJK 字体。

## 小结

交叉编译用工具链文件指 sysroot 的 Qt6,linuxfb 加 tslib 那一组环境变量让 Qt 画到 framebuffer 并读校准后的触摸,evtest 动态发现触摸设备别照抄编号。这几样凑齐,Qt 应用就能在 i.MX6ULL 板子上跑起来。但说真的,这一章最值钱的是那个 NFS 开发循环,改代码到板上见效压到 10 秒级,以后做任何板端应用,只要还在改应用而不是 rootfs,这套都直接复用。

light-meter 从桌面 Mock 到板子真机的完整闭环,到这里就闭环了。最后一章我们退一步,把这条全栈数据链路画成一张图,回顾这一路学到的造工程方法论,然后说说 light-meter 这套思路怎么衔接到更大的项目去。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="09_ap3216c_client.md" variant="sub">← 09 POSIX 字符设备客户端</ChapterLink>
  <ChapterLink href="11_wrap_up.md" variant="sub">11 收束:全栈数据流图与方法论回顾 →</ChapterLink>
</ChapterNav>
