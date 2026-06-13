---
title: 常见问题解答
---

# 附录：常见问题解答（Q&A）

本文档收集了 U-Boot 移植和调试过程中遇到的常见问题及其解决方案，希望能帮助你在遇到类似问题时快速找到答案。

---

## Q1：U-Boot 有背光但黑屏，Logo 不显示怎么办？

### 问题现象

```
LCD 有背光
屏幕黑屏
U-Boot 无 Logo
```

### 排查步骤

#### 第一步：确认 LCD 驱动是否初始化

在 U-Boot 命令行执行：

```bash
bdinfo
```

关键输出：

```
Video       = lcdif@21c8000 active
FB base     = 0x9ef00000
FB size     = 1024x600x32
```

如果看到类似输出，说明 LCDIF 控制器已初始化，Framebuffer 已分配。

#### 第二步：Framebuffer 写入测试

直接向 Framebuffer 写入测试数据：

```bash
mw.l 0x9ef00000 0xffffffff 100000
```

如果屏幕变白，说明 LCD 硬件和驱动都正常，只是 U-Boot 没有自动绘制 Logo。

#### 第三步：BMP 显示测试

```bash
# 加载 BMP 文件到内存
fatload mmc 0:1 0x80800000 logo.bmp

# 显示 BMP
bmp display 0x80800000
```

如果手动显示成功，说明问题出在自动显示机制上。

#### 第四步：检查 splashimage 环境变量

```bash
printenv splashimage
```

如果显示 `## Error: "splashimage" not defined`，这就是问题的根源。

### 解决方案

设置 splashimage 环境变量：

```bash
setenv splashimage 0x83800000
saveenv
```

确保 bootcmd 中包含加载和显示 Logo 的命令：

```bash
setenv bootcmd 'run load_logo; bmp display ${splashimage}; ...'
```

### 推荐的 LCD 调试流程

```
1. 确认背光亮
   ↓
2. bdinfo 确认驱动初始化
   ↓
3. mw.l 测试 Framebuffer
   ↓
4. bmp display 测试完整显示链路
   ↓
5. 设置 splashimage 实现自动显示
```

这样可以逐层定位问题，而不是一开始就陷入复杂的时序参数调优。

---

## Q2：U-Boot 在 VMware NAT 模式下无法 ping 通 Ubuntu 虚拟机

### 问题现象

```bash
=> ping ${serverip}
Using ethernet@20b4000 device
ARP Retry count exceeded; starting again
ping failed; host 192.168.60.129 is not alive
```

### 环境说明

| 角色 | 设备 / 软件 | IP 地址 |
|------|------------|---------|
| 开发板 | i.MX 系列（U-Boot） | 192.168.60.200 |
| 虚拟机 | Ubuntu（VMware NAT） | 192.168.60.129 |
| 宿主机虚拟网卡 | VMware Network Adapter VMnet8 | 192.168.60.1 |

### 排查步骤

#### 第一步：检查 U-Boot 环境变量

```bash
printenv
```

确认 `serverip` 与 Ubuntu 实际 IP 一致：

```bash
setenv serverip 192.168.60.129
setenv netmask 255.255.255.0
setenv gatewayip 192.168.60.2
saveenv
```

#### 第二步：tcpdump 抓包定位链路层问题

在 Ubuntu 上监听 ARP：

```bash
sudo tcpdump -i ens33 arp -n
```

同时在 U-Boot 执行 ping。如果 tcpdump 没有任何输出，说明是**链路层不通**。

#### 第三步：根因分析

VMware NAT 模式的网络拓扑：

```
物理开发板
    ↓（网线）
主机物理网卡（以太网）
    ↓
    ✗ 无法进入 VMnet8（NAT 是独立的虚拟网段）
        ↓
    Ubuntu VM（VMnet8 NAT）
```

NAT 模式下，VMnet8 是一个**完全独立的虚拟网段**，物理网卡的流量默认无法进入该网段。

#### 第四步：Windows 网络桥接解决方案

不需要切换 VMware 为桥接模式（避免虚拟机无法上网），在 **Windows 网络连接层面**做桥接：

1. 按 `Win + R` 输入 `ncpa.cpl` 打开网络连接
2. 按住 `Ctrl`，同时选中：
   - `VMware Network Adapter VMnet8`
   - `以太网`（连接开发板的物理网卡）
3. 右键 → **桥接连接（Bridge Connections）**
4. Windows 自动创建 **网桥（Network Bridge）**

### 验证

```bash
=> ping ${serverip}
Using ethernet@20b4000 device
host 192.168.60.129 is alive
```

### 经验总结

| 排查步骤 | 结论 |
|----------|------|
| `printenv` 检查 serverip | IP 填错，需与 Ubuntu 实际 IP 一致 |
| `tcpdump` 抓 ARP 包 | 没有任何包到达，确认是链路层问题 |
| 分析网络拓扑 | VMware NAT 隔离了物理网卡流量 |
| Windows 网络桥接 | 将物理网卡与 VMnet8 桥接，打通链路层 |

**核心要点：**

- VMware **NAT 模式**下，物理网络设备无法直接与虚拟机通信
- 不需要改变 VMware 网络模式，在 Windows 网络连接中做桥接即可
- `tcpdump` 抓 ARP 是快速判断链路层是否通的最有效手段
- Ubuntu 建议配置**静态 IP**，避免 DHCP 重新分配后地址变化

---

## Q3：网络移植中 PHY 芯片常见问题

### 问题：PHY 无法初始化或 link up 不起来

#### 排查清单

1. **PHY 地址是否正确**
   ```bash
   mii list
   mii info
   ```
   确认 PHY 地址与硬件设计一致（PHYAD 引脚配置）

2. **MDIO 总线是否通**
   ```bash
   mii read <phy_addr> 1
   ```
   应该能读到 PHY 状态寄存器

3. **PHY 复位时序是否正确**
   - 检查 `phy-reset-gpios` 配置
   - 检查 `phy-reset-duration` 和 `phy-reset-post-delay`
   - 确认复位极性（GPIO_ACTIVE_LOW vs GPIO_ACTIVE_HIGH）

4. **时钟是否正确**
   - 确认 50MHz 参考时钟源（外部晶振或内部 PLL）
   - 检查 `clocks` 和 `clock-names` 配置

### 常见错误及解决方案

| 错误现象 | 可能原因 | 解决方案 |
|----------|----------|----------|
| PHY 未检测到 | PHY 地址错误 | 检查硬件 PHYAD 引脚，修改设备树 reg 值 |
| link up 但 ping 不通 | 时钟配置错误 | 检查 Anatop 时钟配置 |
| 间歇性连接不稳定 | 复位时序不足 | 增加 phy-reset-duration 值 |
| 无法读取 PHY 寄存器 | MDIO 引脚配置错误 | 检查 pinctrl 配置 |

---

## Q4：U-Boot 编译常见错误

### 错误：missing bc / bison / flex

```bash
make: bc: Command not found
```

**解决方案：** 安装依赖包

```bash
sudo apt install build-essential bc bison flex libssl-dev \
    libgnutls28-dev libncurses-dev device-tree-compiler \
    python3-pyelftools swig
```

### 错误：架构不匹配

```bash
readelf -h u-boot | grep Machine
Machine: Intel 80386
```

**解决方案：** 检查交叉编译器

```bash
# 确认使用了正确的交叉编译器
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- ...
```

### 错误：设备树编译失败

```bash
make[1]: *** No rule to make target 'dtbs'
```

**解决方案：** 检查设备树源文件路径

```bash
# 确认设备树文件存在
ls arch/arm/dts/<your_board>.dts

# 检查 CONFIG_DEFAULT_DEVICE_TREE 配置
grep CONFIG_DEFAULT_DEVICE_TREE .config
```

---

## Q5：eMMC/SD 卡操作常见问题

### 问题：mmc dev 切换失败

```bash
=> mmc dev 1
Card did not respond to voltage select!
```

**解决方案：** 先 rescan

```bash
=> mmc rescan
=> mmc dev 1
```

### 问题：读取/写入速度慢

**解决方案：** 确认 MMC 模式

```bash
=> mmc info
Bus Speed: 52000000
Mode: MMC HS DDR
```

如果不是 HS DDR 模式，检查设备树配置：

```dts
&usdhc1 {
    no-1-8-v;
    keep-power-in-suspend;
    wakeup-source;
    status = "okay";
};
```

---

## 更多问题？

如果你在 U-Boot 移植过程中遇到其他问题，欢迎查阅主教程各章节的"常见问题排查"部分，或参考以下资源：

- [U-Boot 官方文档](https://www.denx.de/wiki/U-Boot)
- [NXP i.MX6ULL 参考手册](https://www.nxp.com/docs/en/reference-manual/IMX6ULLRM.pdf)
- [U-Boot 源码](https://source.denx.de/u-boot/u-boot)
