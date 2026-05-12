# 主线内核与 imx 内核的差异对比

## 前言：为什么要对比两个内核

我们在整个教程中一直提到两个内核：主线内核（third_party/linux_mainline）和 NXP imx 内核（third_party/linux-imx）。你可能会问：为什么需要两个内核？它们有什么区别？

这一章我们来对比这两个内核在 pinctrl 和 GPIO 子系统上的差异，看看这些差异对我们有什么影响。

## 两个内核的定位

### 主线内核（Mainline）

主线内核是 Linux 官方发布的内核，由 Linus Torvalds 和维护者社区管理。它的特点是：

- **通用性强**：支持各种架构和各种厂商的芯片
- **更新快**：每 2-3 个月发布一个大版本
- **质量高**：经过严格的代码审查和测试
- **文档完整**：有完整的设备树绑定文档

对于 i.MX 6ULL，主线内核的 pinctrl 和 GPIO 驱动位于：

```
drivers/pinctrl/freescale/pinctrl-imx.c
drivers/gpio/gpio-mxc.c
```

### NXP imx 内核

NXP imx 内核是 NXP 公司维护的内核，基于主线内核，但添加了 NXP 特有的功能和支持。它的特点是：

- **芯片特定**：专注于 NXP i.MX 系列芯片
- **功能更全**：可能包含一些主线内核还没有的功能
- **更新慢**：跟随主线内核，但有延迟
- **私有补丁**：可能包含一些 NXP 私有的补丁

## Pinctrl 子系统差异

### 代码量对比

```
主线内核 pinctrl-imx.c:  21982 字节
imx 内核 pinctrl-imx.c:   21982 字节
```

文件大小完全一样，说明核心实现是同步的。

### API 差异

两个内核的 pinctrl API 完全兼容。核心数据结构和函数签名都是一样的。

主要的差异可能在于：

1. **SCU 支持**：imx 内核对 SCU（System Controller Unit）的支持可能更完善。SCU 是某些 i.MX 芯片特有的功能，用于管理芯片级的资源。

2. **错误处理**：主线内核可能有更严格的错误检查。

### 设备树绑定差异

主线内核的设备树绑定文档正在从 `.txt` 格式迁移到 `.yaml` 格式：

```
主线内核：Documentation/devicetree/bindings/pinctrl/fsl,imx-pinctrl.yaml
imx 内核： Documentation/devicetree/bindings/pinctrl/fsl,imx-pinctrl.txt
```

`.yaml` 格式的好处是可以用工具验证设备树的正确性，而 `.txt` 格式只能人工检查。

### 芯片支持差异

两个内核支持的芯片列表可能略有不同。主线内核倾向于支持所有芯片，而 imx 内核专注于 NXP 的芯片。

查看支持的芯片：

```bash
# 主线内核
grep -r "fsl,imx" drivers/pinctrl/freescale/ | grep compatible

# imx 内核
grep -r "fsl,imx" drivers/pinctrl/freescale/ | grep compatible
```

## GPIO 子系统差异

### 代码量对比

```
主线内核 gpio-mxc.c:  733 行
imx 内核 gpio-mxc.c:   739 行
```

只差 6 行，说明 GPIO 驱动已经相当稳定了。

### API 差异

两个内核的 GPIO API 完全兼容。`of_get_named_gpio`、`gpio_direction_output`、`gpio_set_value` 这些函数在两个内核中的行为是一致的。

### 设备树绑定差异

和 pinctrl 类似，主线内核的设备树绑定文档是 `.yaml` 格式，而 imx 内核是 `.txt` 格式：

```
主线内核：Documentation/devicetree/bindings/gpio/fsl-imx-gpio.yaml
imx 内核： Documentation/devicetree/bindings/gpio/fsl-imx-gpio.txt
```

## 实际影响

### 对驱动开发的影响

好消息是：对于大多数驱动开发者来说，这两个内核的差异可以忽略。你的驱动代码在两个内核上都能正常工作。

需要注意的是：

1. **设备树格式**：如果你参考主线内核的文档，要注意设备树绑定可能已经是 `.yaml` 格式了。
2. **SCU 功能**：如果你的芯片需要使用 SCU 功能，可能需要使用 imx 内核。
3. **私有补丁**：NXP 可能有一些私有补丁，只在 imx 内核中存在。

### 对移植的影响

如果你需要从 imx 内核迁移到主线内核（或反之），需要注意：

1. **检查设备树兼容性**：确保设备树中的 compatible 字符串在目标内核中存在。
2. **检查驱动支持**：确保目标内核中有你需要的驱动。
3. **测试功能**：特别要测试那些 NXP 特有的功能。

## 选择建议

### 什么时候用主线内核

- 你需要最新的内核特性
- 你需要最稳定的质量保证
- 你的应用不需要 NXP 特有的功能
- 你希望代码更容易 upstream

### 什么时候用 imx 内核

- 你需要使用 NXP 特有的功能（如 SCU）
- 你需要 NXP 的技术支持
- 你的应用已经在 imx 内核上验证过
- 你需要使用 NXP 的私有补丁

## 未来趋势

主线内核和 imx 内核的差异正在逐渐缩小。NXP 正在努力把更多功能 upstream 到主线内核，而主线内核也在不断增强对 ARM 嵌入式的支持。

长期来看，主线内核会是更好的选择，因为它有更大的社区支持、更快的更新速度、更严格的质量控制。

但短期内，对于一些 NXP 特有的功能，你可能还是需要使用 imx 内核。

## 小结

两个内核在 pinctrl 和 GPIO 子系统上的差异很小，主要是在一些边缘功能和文档格式上。

对于我们的 LED 驱动来说，两个内核完全兼容。你可以用同一份代码、同一个设备树，在两个内核上都能正常工作。

说实话，内核选择是一个很实际的问题。如果你在做产品开发，建议优先考虑主线内核，因为它的质量更可靠、社区更活跃。如果你在做一些 NXP 特有的功能开发，可能需要使用 imx 内核。

---

**教程总结**

到这里，我们的 pinctrl + GPIO 教程就结束了。让我们回顾一下我们走过的路：

1. **第一章**：从寄存器到子系统，理解为什么需要子系统
2. **第二章**：硬件原理，理解 IOMUXC 和 GPIO 模块是怎么工作的
3. **第三章**：pinctrl 子系统架构，理解它的核心数据结构和实现
4. **第四章**：设备树 pinctrl 配置，学会怎么写 pinctrl 配置
5. **第五章**：GPIO 子系统架构，理解它的分层设计
6. **第六章**：设备树 GPIO 配置，学会怎么引用 GPIO
7. **第七章**：完整驱动实现，看真实的驱动代码
8. **第八章**：编译测试，上板验证
9. **第九章**：内核对比，了解两个内核的差异

如果你跟着教程一步步走过来，现在你应该能够：

- 理解 pinctrl 和 GPIO 子系统的工作原理
- 能够在设备树中正确配置 pinctrl 和 GPIO
- 能够编写使用 pinctrl 和 GPIO 子系统的驱动代码
- 能够编译、部署和测试驱动

说实话，pinctrl 和 GPIO 子系统确实是 Linux 驱动开发里非常基础但也非常重要的部分。掌握了这两个子系统，你就掌握了驱动开发的"基本功"。

继续加油！

---

**相关阅读**

- [字符设备驱动基础](../00_chardev_base/01_introduction.md)
- [设备树基础](../01_device_tree_base/01_device_tree_introduction.md)
- [内存映射 I/O](../00_chardev_base/08_memory_mapped_io.md)
