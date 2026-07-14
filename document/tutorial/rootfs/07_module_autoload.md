---
title: 内核模块开机自动加载
---

# 内核模块开机自动加载

> 目标：让 `.ko` 模块在板子开机时自动加载，不用每次手动 `insmod`。

## 一、为什么需要开机加载

开发期我们手动 `insmod xxx.ko` 测试驱动。但产品形态下，板子开机就该自动加载驱动模块。Linux 提供了标准的开机加载机制。

## 二、机制：/etc/modules 与 modules-load.d

### 方式一：/etc/modules

最简单，每行一个模块名，开机时由 `modprobe` 逐个加载：

```bash
# /etc/modules
imx_aes_led
ap3216c
```

### 方式二：/etc/modules-load.d/*.conf

更规范，按配置文件组织：

```bash
# /etc/modules-load.d/drivers.conf
imx_aes_led
ap3216c
```

::: info 两种方式的区别
`/etc/modules` 是传统写法，所有模块混在一个文件；`/etc/modules-load.d/*.conf` 是 systemd 时代的标准，按功能分文件，便于管理。BusyBox/init 的 rootfs 用前者即可，二者可共存。
:::

## 三、模块放哪

`modprobe` 按模块名（不是文件名）加载，需要在模块搜索路径里找到对应的 `.ko`。标准路径：

```bash
/lib/modules/$(uname -r)/
```

把 `.ko` 放进对应内核版本的目录，并跑一次 `depmod` 生成依赖索引：

```bash
# 板上执行
mkdir -p /lib/modules/$(uname -r)
cp imx_aes_led.ko /lib/modules/$(uname -r)/
depmod -a
```

之后 `modprobe imx_aes_led`（不带 `.ko` 后缀）就能加载。

::: warning 内核版本要对上
`/lib/modules/$(uname -r)` 里的 `uname -r` 必须和当前运行的内核版本完全一致，否则 `depmod` 生成的索引对不上，`modprobe` 找不到模块。
:::

## 四、带参数加载：modprobe.d

如果模块需要传参数，用 `/etc/modprobe.d/*.conf`：

```bash
# /etc/modprobe.d/imx_aes_led.conf
options imx_aes_led default_state=1
```

## 五、Buildroot 下如何配置

IMX-Forge 的 rootfs 用 Buildroot 构建。让开机加载配置进 rootfs，有两种做法：

### 做法一：rootfs overlay（推荐，开发期）

在 overlay 里放配置文件，见 [build/03 rootfs overlay](../build/03_rootfs_overlay_guide.md)：

```text
rootfs/overlay/
└── etc/
    ├── modules
    └── modules-load.d/
        └── drivers.conf
```

Buildroot 构建时会自动把 overlay 叠进 rootfs。

### 做法二：Buildroot 包管理（正式）

Buildroot 自带 `BR2_PACKAGE_*` 机制管理模块。在 `make menuconfig` 里把模块相关的包选中，Buildroot 会自动处理 `depmod` 和 modules-load.d。详见 [buildroot/07 custom_package](../buildroot/07_custom_package.md)。

## 六、验证

```bash
# 重启板子后检查模块是否自动加载
lsmod | grep imx_aes_led
# 或看启动日志
dmesg | grep imx_aes_led
```

## 七、故障排查

| 现象 | 排查 |
|------|------|
| 开机没加载 | `/etc/modules` 或 modules-load.d 配置是否进 rootfs（`ls /etc/modules-load.d/`） |
| modprobe 找不到模块 | `.ko` 没在 `/lib/modules/$(uname -r)/` 下，或没跑 `depmod` |
| 版本不匹配 | `uname -r` 和模块路径不一致 |
| 模块加载了但设备没出来 | 检查设备树 compatible、驱动 probe 日志（`dmesg`） |

## 继续学习

- 模块构建加载：[driver/modules/02 构建加载](../driver/modules/02_module_build_and_load.md)
- rootfs overlay：[build/03 overlay 指南](../build/03_rootfs_overlay_guide.md)
- Buildroot 定制：[buildroot/06 rootfs 定制](../buildroot/06_rootfs_customization.md)
