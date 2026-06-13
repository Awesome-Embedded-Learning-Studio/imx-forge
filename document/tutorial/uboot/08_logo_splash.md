# Logo和启动画面

## 一、前言：那些年我们一起追过的Logo

说个真事儿。笔者第一次调试i.MX6ULL的LCD时，屏幕亮了，背光也亮了，但就是黑屏一片。那时候真是慌了——难道LCD驱动有问题？难道时序配错了？难道RGB线接反了？

折腾了半天才发现，原来我有个参数没配置，U-Boot压根就认为不能显示Logo。这就像你家客厅装好了电视，但是没有插上电，你再怎么按遥控器，他都会露出黑黑的脸，“哥们，你不告诉我在哪啊”

这事儿让我意识到一个道理：**Logo显示是嵌入式Linux系统中最容易被忽视的环节之一**。用户上电后第一眼看到的就是Logo，它直接影响产品的"开箱体验"。一个好的Logo显示方案应该是：

1. 上电后立即显示（不要让用户盯着黑屏发呆）
2. 尺寸和位置合适（别被边框切掉，也别缩成一团）
3. 色彩正确（RGB顺序别搞反了）
4. 过渡平滑到Linux Kernel（不要闪烁）

但现实往往很骨感。你会发现U-Boot有两种Logo方式，还有一堆环境变量要配置，再加上各种BMP格式要求，很容易就把人绕晕。别慌，我们来拆一下。

## 二、两种Logo方式：编译内置 vs 运行时加载

U-Boot支持两种Logo显示方式，它们的设计思路完全不同，适用场景也不一样。

### 2.1 编译内置Logo

**原理**：在编译U-Boot时，把Logo图片直接编译进u-boot.bin二进制文件里。

**流程**大概是这样：

```
logo.bmp
    ↓
tools/bmp_logo --gen-info
    ↓
include/bmp_logo.h (尺寸信息)
    ↓
tools/bmp_logo --gen-data
    ↓
include/bmp_logo_data.h (像素数据)
    ↓
编译进u-boot.bin
```

**优点**：

- Logo永远存在，不依赖外部存储
- 上电即可显示，不需要加载过程
- 适合资源受限的系统（比如只有NAND Flash）

**缺点**：

- 改Logo需要重新编译U-Boot
- Logo数据占用Flash空间
- 尺寸受限于编译时的配置

**典型应用场景**：产品量产后的固件，Logo基本不变。

### 2.2 运行时BMP加载（Splash Screen）

**原理**：U-Boot启动时，从外部存储（SD卡、EMMC、NAND等）加载BMP文件到内存，然后显示。

**流程**是这样的：

```
上电
    ↓
LCD初始化
    ↓
检查splashimage环境变量
    ↓
如果存在 → 加载BMP到指定地址
    ↓
调用bmp_display绘制
```

**优点**：

- 换Logo不需要重新编译U-Boot
- 可以用脚本动态切换Logo
- 支持更大的图片文件

**缺点**：

- 依赖外部存储（SD卡得插好，文件得存在）
- 需要配置加载地址和环境变量
- 上电到Logo显示会有延迟（加载时间）

**典型应用场景**：开发调试阶段，或者需要频繁更换Logo的产品。

那么问题来了：**选哪种好？**

笔者的建议是：**开发阶段用运行时加载，量产阶段用编译内置**。开发时你会频繁调整Logo尺寸、位置、色彩，用运行时加载可以快速迭代。等Logo定型了，再编译进固件，做到"开箱即见"。

## 三、编译内置Logo详解

### 3.1 BMP格式要求

bmp_logo工具对输入BMP有严格要求，不是随便找个BMP就能用的：

| 参数 | 要求 | 说明 |
|------|------|------|
| 格式 | BMP | 必须是标准BMP格式 |
| 位深 | 8位 | 256色，带调色板 |
| 压缩 | 无 | BI_RGB格式 |
| 方向 | 正常 | BMP是"上下颠倒"存储的，工具会处理 |

**重点来了**：bmp_logo只支持8位BMP！如果你扔给它一个24位或32位的BMP，它会报错或者产生错误的输出。

但别担心，我们有ImageMagick：

```bash
# 将任意格式转换为8位BMP
convert input.png -colors 256 -type ColorMap3 output.bmp
```

### 3.2 bmp_logo工具使用

bmp_logo.c位于`tools/bmp_logo.c`，编译后生成`tools/bmp_logo`。

它支持三种模式：

```bash
# 生成头文件（包含尺寸信息）
./tools/bmp_logo --gen-info logo.bmp > include/bmp_logo.h

# 生成数据（包含调色板和像素数据）
./tools/bmp_logo --gen-data logo.bmp > include/bmp_logo_data.h

# 生成完整BMP（较少使用）
./tools/bmp_logo --gen-bmp logo.bmp
```

U-Boot的Makefile会自动调用这个工具。你只需要把BMP放到正确位置：

```
tools/logos/denx.bmp  # 默认位置
```

编译时会自动生成头文件。

### 3.3 生成文件分析

生成的`include/bmp_logo.h`内容大概是这样：

```c
#ifndef __BMP_LOGO_H__
#define __BMP_LOGO_H__

#define BMP_LOGO_WIDTH		400
#define BMP_LOGO_HEIGHT		200
#define BMP_LOGO_COLORS		16
#define BMP_LOGO_OFFSET		16

extern unsigned short bmp_logo_palette[];
extern unsigned char bmp_logo_bitmap[];

#endif
```

而`include/bmp_logo_data.h`包含实际的调色板和像素数据：

```c
unsigned short bmp_logo_palette[] = {
	0x0FFF,0x0FFF,0x0FFF,
    ...
};

unsigned char bmp_logo_bitmap[] = {
	0x00,0x01,0x02,...
    ...
};
```

这些数据会被编译进u-boot.bin，你可以用`strings`命令验证：

```bash
strings u-boot | grep bmp_logo
bmp_logo_palette
bmp_logo_bitmap
```

### 3.4 CONFIG选项

要让编译内置Logo工作，需要确保这些Kconfig选项：

```
CONFIG_VIDEO=y
CONFIG_VIDEO_LOGO=y
CONFIG_BMP_8BPP=y
```

注意：**当`CONFIG_SPLASH_SCREEN=y`时，`CONFIG_VIDEO_LOGO`默认关闭**。因为它们是互斥的——要么显示内置Logo，要么显示Splash。

## 四、运行时BMP显示详解（Splash Screen）

这是更灵活的方式，也是我们推荐的开发方式。

### 4.1 splashimage环境变量

这是整个机制的"开关"。U-Boot启动时会检查这个环境变量：

```c
// common/splash.c
s = env_get("splashimage");
if (!s)
    return -EINVAL;  // 没设置，直接退出
```

如果没设置，U-Boot就跳过Splash显示，你可能只会看到默认的Logo（如果启用了`CONFIG_VIDEO_LOGO`）。

**设置方法**：

```bash
# 在U-Boot命令行
setenv splashimage 0x83800000
saveenv

# 或者编译时在配置头文件里
#define CONFIG_EXTRA_ENV_SETTINGS \
    "splashimage=0x83800000\0"
```

### 4.2 加载地址选择

splashimage的值是一个**内存地址**，不是文件路径。U-Boot会从这个地址读取BMP数据。

那么这个地址怎么选？

**原则**：

1. 不能与U-Boot代码/数据区冲突
2. 不能与设备树、内核加载地址冲突
3. 要有足够空间存放BMP文件

**i.MX6ULL内存布局**（典型）：

```
0x80000000  ─┐
             ├─ U-Boot (约1MB)
0x80100000  ─┤
             ├─ 可用
0x83800000  ─┤ ← splashimage可以放这里
             ├─ 设备树
0x83000000  ─┤
             ├─ 内核
0x80800000  ─┘
```

**笔者的建议**：

```bash
# 安全的选择（避开常用区域）
splashimage=0x83800000

# 或者用loadaddr（如果够大）
splashimage=${loadaddr}
```

### 4.3 自动加载流程

光设置地址还不够，你还得把BMP文件加载到这个地址。有三种方式：

#### 方式1：手动加载（开发调试）

```bash
# U-Boot命令行
fatload mmc 0:1 ${splashimage} logo.bmp
bmp display ${splashimage}
```

#### 方式2：bootcmd自动加载

在`bootcmd`中添加加载命令：

```bash
#define CONFIG_EXTRA_ENV_SETTINGS \
    "splashimage=0x83800000\0" \
    "load_logo=fatload mmc 0:1 ${splashimage} logo.bmp\0" \
    "bootcmd=run load_logo; bmp display ${splashimage}; " \
           "bootm ${kernel_addr}\0"
```

#### 方式3：SPLASH_SOURCE自动加载（最省心）

启用`CONFIG_SPLASH_SOURCE`后，U-Boot会自动从多个位置尝试加载：

```c
static struct splash_location default_splash_locations[] = {
    { .name = "sf",     .storage = SPLASH_STORAGE_SF },
    { .name = "mmc_fs", .storage = SPLASH_STORAGE_MMC, .flags = SPLASH_STORAGE_FS },
    { .name = "mmc_raw",.storage = SPLASH_STORAGE_MMC, .flags = SPLASH_STORAGE_RAW },
    { .name = "usb_fs", .storage = SPLASH_STORAGE_USB },
    { .name = "sata_fs",.storage = SPLASH_STORAGE_SATA },
};
```

它会依次尝试从SPI Flash、SD卡FAT分区、SD卡原始分区、USB、SATA加载`splash.bmp`文件。

### 4.4 splashpos位置控制

如果想控制Logo在屏幕上的位置，启用`CONFIG_SPLASH_SCREEN_ALIGN`：

```bash
# 居中显示
setenv splashpos m,m

# 左上角
setenv splashpos 0,0

# 自定义位置
setenv splashpos 100,50
```

第一个值是X坐标，第二个是Y坐标。`m`表示居中（middle）。

## 五、logo_helper.sh工具使用

手动用ImageMagick转换BMP太麻烦了，我们写了个脚本一键搞定。

### 5.1 工具简介

`logo_helper.sh`位于`scripts/logo_helper/`，功能：

- 自动将PNG转换为BMP
- 自动调整尺寸到指定分辨率
- 自动复制到U-Boot的logos目录
- 自动清理临时文件

### 5.2 使用方法

```bash
# 默认：转换为800x480，输出到denx.bmp
./scripts/logo_helper/logo_helper.sh

# 指定尺寸：1024x600
./scripts/logo_helper/logo_helper.sh 1024x600

# 指定输入文件
./scripts/logo_helper/logo_helper.sh 800x480 document/logo/my_logo.png

# 指定输出位置
./scripts/logo_helper/logo_helper.sh 800x480 document/logo/logo.png third_party/uboot-imx/tools/logos/custom.bmp
```

### 5.3 工作原理

脚本的核心转换命令：

```bash
convert "$INPUT_PATH" \
    -resize ${TARGET_SIZE}! \    # 强制调整尺寸
    -alpha off \                  # 去掉透明通道
    -depth 8 \                    # 8位深度
    bmp3:"$TEMP_PATH"             # 输出为BMP3格式
```

这里有个细节：`!`表示强制调整，不保持宽高比。如果你的Logo比例不对，可能会变形。

### 5.4 依赖安装

```bash
sudo apt install imagemagick
```

如果遇到"policy limits"错误，需要修改`/etc/ImageMagick-6/policy.xml`，解除权限限制。

## 六、常见Logo问题排查

笔者在调试过程中踩过不少坑，这里分享几个典型案例。

### 6.1 Logo不显示

**现象**：LCD正常工作（bdinfo显示已初始化），但就是没有Logo。

**排查步骤**：

```bash
# 1. 确认splashimage已设置
printenv splashimage
# 如果为空，说明没设置

# 2. 确认BMP已加载
md.w 0x83800000 10
# 应该看到BMP的魔数'BM' (0x4D42)

# 3. 手动显示
bmp display ${splashimage}
# 看报错信息

# 4. 检查BMP格式
bmp info ${splashimage}
# 确认位深、尺寸
```

**常见原因**：

| 问题 | 解决 |
|------|------|
| splashimage未设置 | setenv splashimage 0x83800000 |
| BMP未加载 | 在bootcmd中添加加载命令 |
| BMP格式不支持 | 转换为8位或24位BMP |
| CONFIG_SPLASH_SCREEN未启用 | 添加到defconfig |

### 6.2 Logo颜色异常

**现象**：Logo显示了，但颜色不对——蓝色变红色，或者整体偏色。

**原因**：RGB顺序问题。

i.MX6ULL的LCDIF控制器支持多种RGB格式，设备树中配置：

```dts
display0: display@0 {
    bits-per-pixel = <24>;  // 24位 = RGB888
    bus-width = <24>;
};
```

但你的BMP可能是BGR顺序（Windows标准），或者LCD接线是BGR。

**解决方案**：

1. 转换BMP时指定格式：

```bash
convert input.png -type TrueColor bmp3:output.bmp
```

2. 修改设备树的像素格式

3. 如果是接线问题，只能硬件改线或者软件转换

### 6.3 Logo位置不对

**现象**：Logo被切掉一部分，或者缩在角落。

**解决方案**：

```bash
# 启用位置控制
CONFIG_SPLASH_SCREEN_ALIGN=y

# 设置位置
setenv splashpos m,m  # 居中
```

### 6.4 Logo闪烁

**现象**：U-Boot显示Logo后，Kernel启动时屏幕会黑一下再亮。

**原因**：U-Boot的Framebuffer和Kernel的Framebuffer没有无缝衔接。

**解决方案**：

1. 确保U-Boot和Kernel使用相同的LCD参数
2. Kernel的simple-framebuffer要正确配置
3. 或者接受这个现实——很多产品都有这个"闪烁"

### 6.5 bmp display报错

**现象**：

```
There is no valid bmp file at the given address
```

**原因**：该地址没有有效的BMP数据。

**排查**：

```bash
# 检查BMP魔数
md.w ${splashimage} 1
# 应该看到 0x4D42 ('BM')

# 检查BMP信息
bmp info ${splashimage}
```

**常见错误**：

1. 加载地址不对（fatload失败）
2. BMP文件损坏
3. 地址冲突（被其他数据覆盖）

## 七、与正点原子Logo配置的对比

正点原子的教程是国内学习i.MX6ULL的权威资料，但它的Logo配置方式与我们有差异。

### 7.1 正点原子的方式

正点原子主要使用**编译内置Logo**方式：

1. 用工具将BMP转换为C数组
2. 编译进U-Boot
3. 启动时自动显示

他们的配置通常在：

```c
// board/freescale/mx6ullevk/mx6ullevk.c
#ifdef CONFIG_VIDEO_MXS
static int setup_lcd(void)
{
    // ... LCD初始化
}
#endif
```

**优点**：简单可靠，不用折腾环境变量。

**缺点**：换Logo麻烦，需要重新编译。

### 7.2 IMX-Forge的方式

我们推荐**运行时BMP加载**：

1. Logo放在SD卡FAT分区
2. U-Boot启动时加载
3. 支持热更换

配置位置：

```dts
// 设备树：LCD参数
&lcdif {
    status = "okay";
    display = <&display0>;
};

// 环境变量：加载逻辑
splashimage=0x83800000
load_logo=fatload mmc 0:1 ${splashimage} logo.bmp
bootcmd=run load_logo; bmp display ${splashimage}; ...
```

**优点**：灵活，易于调试。

**缺点**：依赖SD卡，配置稍复杂。

### 7.3 应该怎么选？

笔者的建议是：

| 阶段 | 推荐方式 | 理由 |
|------|---------|------|
| 学习调试 | 运行时加载 | 快速迭代，易于验证 |
| 产品原型 | 运行时加载 | 方便演示不同Logo |
| 小批量试产 | 运行时加载 | 可以后期定制Logo |
| 量产 | 编译内置 | 稳定可靠，开箱即用 |

正点原子的方式更适合教学和快速上手，我们的方式更适合工程实践和产品开发。

## 八、完整配置示例

最后，给一个完整的Logo配置示例，你可以直接参考。

### 8.1 设备树配置

```dts
&lcdif {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lcdif_dat &pinctrl_lcdif_ctrl>;
    display = <&display0>;
    status = "okay";

    display0: display@0 {
        bits-per-pixel = <24>;
        bus-width = <24>;

        display-timings {
            native-mode = <&timing0>;

            timing0: timing0 {
                clock-frequency = <51200000>;
                hactive = <1024>;
                vactive = <600>;
                hfront-porch = <160>;
                hback-porch = <140>;
                hsync-len = <20>;
                vback-porch = <20>;
                vfront-porch = <12>;
                vsync-len = <3>;
                hsync-active = <0>;
                vsync-active = <0>;
                de-active = <1>;
                pixelclk-active = <0>;
            };
        };
    };
};
```

### 8.2 defconfig配置

```
CONFIG_VIDEO=y
CONFIG_VIDEO_MXS=y
CONFIG_SPLASH_SCREEN=y
CONFIG_SPLASH_SCREEN_ALIGN=y
CONFIG_BMP=y
CONFIG_BMP_16BPP=y
CONFIG_BMP_24BPP=y
CONFIG_BMP_32BPP=y
```

### 8.3 环境变量配置

```bash
splashimage=0x83800000
splashpos=m,m
load_logo=if fatload mmc 0:1 ${splashimage} logo.bmp; then echo Logo loaded; else echo Logo load failed; fi
bootcmd=run load_logo; bmp display ${splashimage}; echo Booting kernel...; bootm ${kernel_addr}
```

### 8.4 Logo文件准备

```bash
# 1. 准备PNG
# 2. 转换
./scripts/logo_helper/logo_helper.sh 1024x600

# 3. 或者手动转换
convert document/logo/logo.png \
    -resize 1024x600! \
    -alpha off \
    -depth 8 \
    bmp3:third_party/uboot-imx/tools/logos/denx.bmp

# 4. 拷贝到SD卡
cp third_party/uboot-imx/tools/logos/denx.bmp /mnt/logo.bmp
```

## 九、写在最后

Logo和启动画面是嵌入式Linux系统产品化的重要环节。用户上电后第一眼看到的就是Logo，它直接影响产品的"开箱体验"。

这篇文章我们详细讲解了U-Boot的两种Logo方式——编译内置和运行时加载。编译内置适合量产阶段，稳定可靠；运行时加载适合开发阶段，灵活方便。你还学会了如何使用logo_helper.sh工具快速转换Logo，如何配置splashimage环境变量，如何排查常见的Logo显示问题。

到这一步，你的U-Boot已经具备了完整的启动能力：能从eMMC/SD卡启动，能显示LCD界面，能通过网络传输文件，还能在启动时展示你的Logo。这已经是一个功能完备的bootloader了。

下一篇文章，我们将深入U-Boot的调试命令。这些命令是你排查问题、理解系统的利器。掌握了它们，你就不再是一知半解地"照猫画虎"，而是能够快速定位问题、精准调试的工程师。