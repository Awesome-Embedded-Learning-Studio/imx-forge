# show_device_tree.sh - 设备树查看脚本

## 概述

`show_device_tree.sh` 是驱动开发基建里的设备树预览工具：把 `.dtb`（编译后的二进制设备树）或 `.dts`（设备树源码）读进来，反编译成 DTS 文本，再以树形结构打印出来，高亮 `compatible`、`status` 这些最常关心的属性。

最典型的场景是**部署前预览**：`build_driver.sh` 刚编出来的 dtb 到底长什么样？自己加的节点进没进去？`status` 是不是 `okay`？跑一下这个脚本确认无误，再交给 `deploy_driver.sh` 上板。调试设备树问题时，也可以用它搜索特定节点、翻看完整源码。

它只依赖一个外部工具：

```
show_device_tree.sh
    └─ dtc（设备树编译器）
```

没有 dtc 会直接报错退出，安装方法见[常见问题](#常见问题)。

## 语法与参数

```bash
./scripts/driver_helper/show_device_tree.sh <设备树文件> [选项]
```

### 位置参数

| 参数 | 说明 | 必需 |
|------|------|------|
| 设备树文件 | `.dtb` 或 `.dts` 文件路径 | 是 |

### 选项

| 选项 | 说明 |
|------|------|
| `--all, -a` | 在树形结构之后追加显示完整 DTS 源码 |
| `--search, -s <关键词>` | 搜索节点或属性，先打搜索结果，再照常打树形结构 |
| `--detailed, -d` | 显示统计信息（节点数、属性数、节点清单），再照常打树形结构 |
| `--help, -h` | 显示帮助信息 |

注意 `--search` 和 `--detailed` 不是"替换默认输出"，而是"在默认树形输出**前面**追加一块内容"。这是脚本的实际行为，第一次用容易误以为加了选项就只看搜索结果。

## 默认用法：树形结构解析

不带选项运行，输出文件信息加一棵"节点树"，树里只列节点名和 `compatible` / `status` 两类属性：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb
```

真实输出（内容较长，开头和结尾各截一段，中间约两百行省略）：

```
🌳 设备树节点结构
═════════════════════════════════════════════════════

📁 文件: out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb
📏 大小: 36K

🌲 节点树结构

   ✦ compatible = "fsl,imx6ull-14x14-evk fsl,imx6ull"
├──chosen
├──aliases
├──cpus
   ✦ compatible = "arm,cortex-a7"
├──timer
   ✦ compatible = "arm,armv7-timer"
   ✦ status = "disabled"
   ✦ compatible = "fixed-clock"
   ✦ compatible = "fixed-clock"
   ✦ compatible = "fixed-clock"
   ✦ compatible = "fixed-clock"
├──pmu
   ✦ compatible = "arm,cortex-a7-pmu"
├──soc
   ✦ compatible = "simple-bus"
   ...（中间省略：soc 下每个外设的 compatible/status 各占一行，
       包括 ECSPI、UART、SAI、PWM、CAN、GPIO、FEC、USDHC、I2C 等）...
│  ├──mdio
│     ✦ compatible = "ethernet-phy-id0022.1560"
│  ├──uart1grp
│  ├──uart2grp
│  ├──usdhc1grp
│  ├──usdhc2grp
   ...（省略）...
   ✦ compatible = "fake,i2c-device"
   ✦ status = "disabled"
   ✦ compatible = "fake,spi-device"
   ✦ status = "disabled"
   ✦ compatible = "fake,gpio-device"
   ✦ status = "disabled"
   ✦ compatible = "fake,platform-device"
   ✦ status = "disabled"

═════════════════════════════════════════════════════

✅ 显示完成
```

怎么读这份输出：`├──` 开头的行是节点名，`✦` 开头的行是该节点下面打出来的 `compatible` 或 `status`。扫一遍 `status = "okay"` 还是 `"disabled"`，就能确认外设开关状态；扫一遍 compatible 列表，就能确认自己的节点在不在编译产物里。

有一个一眼就能看出来的特点：这棵"树"基本是压扁的，绝大多数行都顶格，只有 `mdio`、`uart1grp` 这类嵌套较深的节点才带 `│  ` 前缀；而且像 `cpu@0`、`serial@2020000` 这种带 `@` 单元地址的节点名根本不显示，只剩它们的属性行。这是脚本解析逻辑的已知局限，不影响"查 compatible、查 status"的主用途，根因见文末[脚本内部机制](#脚本内部机制)的走读。

## --all：连完整 DTS 源码一起看

`--all` 在树形结构之后追加"完整DTS内容"一节，把 dtc 反编译出来的整个 DTS 源码原样打印，适合逐行核对属性：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --all
```

真实输出（树形部分同上省略，完整 DTS 约 1600 行，这里只截开头）：

```
   ...（前面是树形结构，同默认用法，省略）...

═════════════════════════════════════════════════════

📄 完整DTS内容

/dts-v1/;

/ {
	#address-cells = <0x01>;
	#size-cells = <0x01>;
	model = "Awesome Embedded Studio IMX6ULL Example Driver";
	compatible = "fsl,imx6ull-14x14-evk\0fsl,imx6ull";

	chosen {
		stdout-path = "/soc/bus@2000000/spba-bus@2000000/serial@2020000";
	};

	aliases {
		ethernet0 = "/soc/bus@2100000/ethernet@2188000";
		ethernet1 = "/soc/bus@2000000/ethernet@20b4000";
		gpio0 = "/soc/bus@2000000/gpio@209c000";
		...（省略）...
	};

	cpus {
		#address-cells = <0x01>;
		#size-cells = <0x00>;

		cpu@0 {
			compatible = "arm,cortex-a7";
			device_type = "cpu";
			reg = <0x00>;
   ...（省略）...
```

两个细节：compatible 里的 `\0` 是 dtc 表示字符串列表分隔符的写法，源码里对应的就是 `compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";`；数值都是十六进制（`<0x01>`），也是 dtc 反编译的风格，跟手写源码里的十进制是一回事。

## --search：搜索节点或属性

`--search` 在整份反编译 DTS 里做不区分大小写的搜索，带行号显示命中行。搜索结果打完后，默认的树形结构照常输出：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --search "backlight"
```

真实输出（搜索结果部分；后面还跟着约 240 行树形输出，省略）：

```
🔍 搜索: backlight
═════════════════════════════════════════════════════

行 1442: 	backlight-display {
行 1443: 		compatible = "pwm-backlight";
行 1453: 		backlight = <0x42>;

   ...（后面是完整的树形结构输出，省略）...
```

关键词搜不到时输出"未找到匹配项"，然后树形结构照样打。比如在这份 dtb 里搜 `alpha-led`：

```
🔍 搜索: alpha-led
═════════════════════════════════════════════════════

未找到匹配项

   ...（后面是完整的树形结构输出，省略）...
```

搜索命中最多列 20 行（`head -20`），设备树很大、关键词太宽（比如直接搜 `compatible`）时后面的命中会被截掉，把关键词收窄一点就行。

## --detailed：看统计信息和节点清单

`--detailed` 在树形输出前追加一块统计：节点数量、属性数量、所有节点名清单。统计打完后，树形结构照常输出：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --detailed
```

真实输出（统计部分；节点清单和后面的树形输出省略）：

```
🔍 设备树详细信息
═════════════════════════════════════════════════════

📊 统计信息:
  节点数量: 49
  属性数量: 585
  Compatible属性: 0

🌲 所有节点:
  - chosen
  - aliases
  - cpus
  - timer
  - pmu
  - soc
  - mdio
  - tempmon
   ...（省略，共 49 项）...
  - pxp_v4l2

🔗 Compatible属性:

   ...（后面是完整的树形结构输出，省略）...
```

两个要心里有数的点：

1. **"Compatible属性"统计恒为 0，清单恒为空**。这是脚本里的统计 bug（grep 的模式少写了一个空格，永远匹配不上），不是这份设备树真没有 compatible。想数 compatible，用 `--search "compatible"` 或者直接 `dtc -I dtb -O dts xxx.dtb | grep compatible`。
2. **节点数量 49 少于实际的节点总数**。统计的正则同样只认"纯字母数字下划线的节点名"，带 `@`、`-` 的节点（恰恰是大多数外设节点）没被数进去。这个数当参考就好，别当权威计数。

## 组合使用

选项可以叠加，输出顺序固定为：搜索结果 → 详细统计 → 树形结构 → （`--all` 时的）完整 DTS。

```bash
# 先看统计，再搜自己的节点，最后照常看树
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --detailed --search "fake"

# 树形结构加完整源码一次看全
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --all
```

## 输入用 .dtb 还是 .dts

两种文件都能喂，但功能可用性不一样：

| 功能 | `.dtb` | `.dts` |
|------|--------|--------|
| 树形结构（默认） | 可用（dtc 反编译后解析） | 可用（直接读源码文本） |
| `--all` 完整源码 | 可用（反编译输出） | 可用（原样打印源码） |
| `--search` 搜索 | 可用 | **不可用**，恒显示"未找到匹配项" |
| `--detailed` 统计 | 可用 | **不可用**，统计恒为 0 |

原因：`--search` 和 `--detailed` 这两个函数内部写死了 `dtc -I dtb`（按二进制 dtb 读入），喂文本格式的 `.dts` 时 dtc 直接报错、输出为空。所以要搜索或看统计，请先用 `build_driver.sh` 编出 dtb 再操作。

`.dts` 源文件直接看树是这样的（这是 example-driver 的源码薄壳，只有 1.4K，`#include` 进来的 dtsi 内容不在里面）：

```bash
./scripts/driver_helper/show_device_tree.sh driver/device_tree/alpha-board/example-driver/imx6ull-aes-example-driver.dts
```

```
🌳 设备树节点结构
═════════════════════════════════════════════════════

📁 文件: driver/device_tree/alpha-board/example-driver/imx6ull-aes-example-driver.dts
📏 大小: 1.4K

🌲 节点树结构

   ✦ compatible = "fsl,imx6ull-14x14-evk, fsl,imx6ull"
   ✦ compatible = "fake,i2c-device"
   ✦ status = "disabled"
   ✦ compatible = "fake,spi-device"
   ✦ status = "disabled"
   ✦ compatible = "fake,gpio-device"
   ✦ status = "disabled"
   ✦ compatible = "fake,platform-device"
   ✦ status = "disabled"

═════════════════════════════════════════════════════

✅ 显示完成
```

顺带能看到一个现象：源码里明明有 `fake_i2c_device: fake-i2c@50 {` 这样的节点，输出里却只剩属性行。带标签（`label:`）、带 `@`、带 `-` 的节点名都不符合脚本的节点识别规则，所以不显示——这也是上面 `.dtb` 输出里 `cpu@0` 们"消失"的同一个原因。

## 显示图例：颜色和符号

脚本在终端里用 ANSI 颜色区分内容（重定向到文件时颜色码会以转义序列形式保留，内容不受影响）：

| 颜色 | 用途 |
|------|------|
| 蓝色 | 树形前缀 `│  ├──`、分隔线 `═══` |
| 绿色 | 节点名、`status = "okay"`、结尾的"显示完成" |
| 青色 | 各节标题、文件信息、属性名 |
| 黄色 | 属性值、`status = "disabled"`、搜索未命中提示 |
| 洋红 | 属性标记 `✦` |
| 红色 | 错误信息 |

符号含义：

| 符号 | 含义 |
|------|------|
| `├──` | 节点，后面跟节点名 |
| `│` | 垂直连线（嵌套较深的节点才有） |
| `✦` | 属性行，后面跟 `属性名 = "值"` |

`status` 的值 `okay` 显示为绿色、`disabled` 显示为黄色，扫一眼颜色就能看出哪些外设开着、哪些关着。

## 和其他脚本怎么配合

一套完整的"改 dts → 编译 → 预览 → 上板"流程：

```bash
# 1. 改设备树源码
vim driver/device_tree/alpha-board/example-driver/imx6ull-aes-example-driver.dts

# 2. 重新构建（产物落在 out/driver_artifacts/<驱动名>/alpha-board/）
./scripts/driver_helper/build_driver.sh example-driver

# 3. 预览确认：节点在不在、status 对不对
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --search "fake"

# 4. 确认无误后部署上板
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

提交代码审查前，也可以先用 `--all` 把完整内容过一遍，再跑 `./scripts/driver_helper/review_driver.sh example-driver`。

## 高级用法

批量预览所有构建出来的设备树：

```bash
for dtb in out/driver_artifacts/*/*/imx6ull-aes-*.dtb; do
    echo "=== $dtb ==="
    ./scripts/driver_helper/show_device_tree.sh "$dtb"
done
```

比较两个设备树的差异（比如改 dts 前后各存一份）：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --all > /tmp/dtb_old.txt
# ...修改 dts 并重新构建...
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --all > /tmp/dtb_new.txt
diff /tmp/dtb_old.txt /tmp/dtb_new.txt
```

提取所有 compatible 值（`-F'"'` 按引号切字段，第二段就是值）：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --search "compatible" | awk -F'"' 'NF>1 {print $2}'
```

生成设备树参考文档：

```bash
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb --all > device_tree_reference.txt
```

## 常见问题

### 1. dtc 工具未安装

```
❌ 错误: dtc工具不可用
请安装设备树编译器: sudo apt-get install device-tree-compiler
```

解决：

```bash
sudo apt-get install device-tree-compiler
dtc --version   # 验证安装
```

### 2. 文件不存在

```
❌ 错误: 文件不存在: example.dtb
```

解决：检查路径是否正确。用相对路径时要从项目根目录执行，或者直接用绝对路径。构建产物统一在 `out/driver_artifacts/<驱动名>/alpha-board/` 下面，先 `ls` 确认文件名。

### 3. 文件格式不支持

```
❌ 错误: 不支持的文件格式
```

解决：只支持 `.dtb` 和 `.dts` 两种扩展名，别的扩展名直接拒绝。

### 4. 无法读取设备树文件

```
❌ 错误: 无法读取设备树文件
```

原因：文件存在但内容读不出来——通常是 dtb 损坏，或者 `.dts` 里有语法错误导致输出为空。排查：

```bash
# 用 dtc 直接验证文件是否有效
dtc -I dtb -O dts out/driver_artifacts/example-driver/alpha-board/imx6ull-aes-example-driver.dtb

# dtb 有问题就重新构建
./scripts/driver_helper/build_driver.sh example-driver
```

## 注意事项

1. **树形视图是"压扁"的**：脚本按"每 4 个空白字符算一层"折算缩进，而 dtc 反编译输出是一个层级一个 tab，所以浅层节点几乎全部折到顶格；带 `@`、`-`、`label:` 的节点名则整个不显示。查 compatible、查 status 不受影响，想看真正的层级结构用 `--all` 看完整源码的缩进。
2. **`--search` / `--detailed` 只对 `.dtb` 有效**：喂 `.dts` 源文件时这两个功能恒为空，详见[输入用 .dtb 还是 .dts](#输入用-dtb-还是-dts)。
3. **搜索最多显示 20 行命中**，关键词太宽会被截断。
4. **`--detailed` 的 Compatible 统计恒为 0**，是脚本 bug，别被它误导。
5. **输出里的颜色是 ANSI 转义序列**：直接在终端看没问题；重定向到文件再打开会看到 `[0;36m` 这类乱码一样的码，属正常现象，`sed 's/\x1b\[[0-9;]*m//g'` 可以滤掉。
6. **用相对路径时从项目根目录执行**，文档里的示例命令都按这个约定写。

## 脚本内部机制

日常使用看到上面就够了；想知道脚本内部怎么跑、为什么树是压扁的，点开下面两节。

::: details 执行流程：一次调用经历了什么

脚本结构很朴素：`main()` 解析完参数后，按固定顺序调三个显示函数，树形输出永远在最后。

```
┌────────────────────────────────────────────┐
│ 参数验证                                   │
│ - 检查文件参数是否存在                      │
│ - 检查文件是否存在（-f）                    │
│ - check_dtc()：dtc 装没装                  │
└────────────────────────────────────────────┘
                     ↓
┌────────────────────────────────────────────┐
│ 按顺序追加输出（main() 末尾的三个 if）       │
│ - 有 --search：先调 search_node()           │
│ - 有 --detailed：再调 print_device_tree_detailed() │
│ - 无条件：调 print_device_tree()            │
│   （--all 时在树后面追加完整 DTS）           │
└────────────────────────────────────────────┘
```

所以 `--search`、`--detailed` 是"在树形输出前面追加内容"，而不是"换一种输出"——这就是正文里反复强调的那一点。

参数解析是一个 `while shift` 循环：`--help` 打帮助退出；`--search` 吃掉下一个参数当关键词；`--all` / `--detailed` 置布尔标志；其他 `-*` 当未知选项报错；剩下的第一个非选项参数当设备树文件路径。
:::

::: details print_device_tree() 怎么解析 DTS：为什么树是压扁的

`print_device_tree()` 拿到文件后，`.dtb` 走 `dtc -I dtb -O dts` 反编译成文本，`.dts` 直接 `cat`，然后逐行做三类正则匹配：

1. **节点行**：`^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\{`——节点名只允许字母、数字、下划线，后面紧跟空白和 `{`。于是三种常见的节点行全都匹配不上：带单元地址的 `cpu@0 {`（有 `@`）、带连字符的 `fake-gpio-device {`（有 `-`）、带标签的 `fake_i2c_device: fake-i2c@50 {`（有 `:`）。这些节点就不显示，但它们下面的 `compatible` / `status` 属性行照打——这就是输出里"只见属性不见节点名"的原因。
2. **属性行**：`[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=`——同样只认纯字母数字下划线的属性名。匹配上之后只有 `compatible` 和 `status` 两种会打印，其余属性一律忽略。
3. **缩进折算**：`缩进层级 = 行首空白字符数 / 4`。脚本是按"4 个空格一层"的源码风格写的，而 dtc 反编译输出是 **tab 缩进、一层一个 tab**：1~3 个 tab 的节点全折成第 0 层（顶格 `├──`），4 个 tab 的节点才算第 1 层（带 `│  ` 前缀），5~7 个 tab 又折回第 1 层……层数越深偏差越大。这就是整棵树看起来被压扁、只有 `mdio`、`uart1grp` 这类第 4 层节点偶尔带前缀的根因。树形前缀里的 `│  ` 也是按折算后的层级循环拼出来的。

知道这三条，就能解释输出里所有的"怪现象"；也说明这份树形视图的定位就是**快速扫 compatible / status 的清单**，真正的结构分析请用 `--all` 看完整源码，或者直接读 dts。
:::

::: details search_node() 与 print_device_tree_detailed() 的两个坑

**search_node()**：`dtc -I dtb -O dts` 反编译后 `grep -i -n 关键词 | head -20`，按 `行号: 内容` 格式打印，命中为空时打"未找到匹配项"。两个坑：

- 它**无条件按 dtb 反编译**，不看扩展名。喂 `.dts` 文本时 dtc 报错、输出为空，于是恒显示"未找到匹配项"。
- `head -20` 截断命中，宽关键词看不到全部结果。

**print_device_tree_detailed()**：同样无条件 `dtc -I dtb`（所以 `.dts` 输入统计恒 0），统计用三个 grep：

- 节点数量：`grep -c "^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*{"`——还是不认 `@` / `-` / 标签，所以 49 是"纯字母名节点"的数量，远小于实际节点总数。
- 属性数量：`grep -c "^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*="`——同样只数"干净名字"的属性行。
- Compatible 数量：`grep -c "compatible="`——**模式里 `=` 前没有空格**，而 dtc 输出是 `compatible = "..."`（等号两边有空格），所以永远匹配 0 次。这就是"Compatible属性: 0"和空清单的来源。
:::

## 相关文档

- [build_driver.md](./build_driver.md) - 驱动构建脚本
- [deploy_driver.md](./deploy_driver.md) - 驱动部署脚本
- [review_driver.md](./review_driver.md) - 驱动审查脚本
- [configuration.md](./configuration.md) - 配置文件说明
- [driver_buildlib.md](../lib/driver_buildlib.md) - 构建库说明
