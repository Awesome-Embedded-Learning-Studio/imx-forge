# make-qemu-dtb.sh - 给 QEMU 编真板同源 dtb（真机 dts 直编 + fdtput 补 MAC）

## 脚本概述

`make-qemu-dtb.sh` 编译 QEMU 启动用的板级 dtb：直接拿内核树里的真板 dts
`third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dts` 编成
`out/qemu/imx6ull-aes.dtb`，不做任何「QEMU 变体」——QEMU 和真机启动的是
同一棵设备树，逐字节一致。唯一的改动是用 `fdtput` 往编好的 blob 里补两个
网口的 `local-mac-address`，干的正是真机上 U-Boot 在 `bootz` 之前干的那件事。

一句话记住这个脚本的立场（等价性原则）：**QEMU 拉的就是真板那棵树，唯一
的差异是 bootloader 本来就会做的那部分修整，而且就在 bootloader 动手的
位置（编译出来的 blob）上做**。dts/dtsi 保持单一来源，在 QEMU 里验证过的
结论对真机成立，反过来也一样。

### 为什么只补 MAC、别的什么都不改

板级 `imx6ull-aes.dtsi` 里 `&fec1`/`&fec2` 都没写 `local-mac-address`，
MAC 走的是 `imx6ul.dtsi` 里挂在 ocotp（eFuse）上的 nvmem cell
（`fec1_mac_addr: mac-addr@88` / `fec2_mac_addr: mac-addr@8e`）。真机启动
时 U-Boot 会把 `ethaddr`/`eth1addr` 环境变量盖进 dtb 再 `bootz`；而 QEMU
这条链是 `-kernel` 直启、中间没有 U-Boot，没人干这个活——内核的
`of_get_mac_address()` 于是一直等那个 nvmem cell，两个 FEC 全卡在
deferred probe，网络起不来（e2e 的 net-dhcp-ping 断言就过不去）。

所以脚本在 dtc 编完之后补两条 `fdtput`，等于替 U-Boot 做了 ethaddr fixup：

| 写入的节点（blob 里的完整路径） | dtsi 里的 label | 写入的 MAC |
|---|---|---|
| `/soc/bus@2000000/ethernet@20b4000` | `&fec2` | `00:11:22:33:44:01` |
| `/soc/bus@2100000/ethernet@2188000` | `&fec1` | `00:11:22:33:44:02` |

> 脚本里的变量名叫 `FEC1_MAC`/`FEC2_MAC`，但按 dtsi 的 label 对不上号
> （`FEC1_MAC` 实际写进的是 `&fec2` 那个节点）。对表认路径就行，别认
> 变量名。

### 在开发工作流中的位置

QEMU 模拟链路三件套的第二步（见 `make-rootfs-img.sh.md`）：

```text
make-rootfs-img.sh   →  out/qemu/rootfs.ext4      （第 1 步）
make-qemu-dtb.sh     →  out/qemu/imx6ull-aes.dtb  （本脚本）
run-qemu.sh          →  交互 / --smoke 冒烟        （第 3 步）
```

平时不用手动跑：`run-qemu.sh` 默认启动前自检——dtb 不存在，或内核树
`nxp/imx/` 下的真板 dts/dtsi 比现有 dtb 新（真机单源，改了 dts/dtsi 重跑
就生效），就自动调本脚本重建；`e2e-test.sh` 也是借 `run-qemu.sh` 刷新
产物。手动跑的场景主要是想单独检查编译产物，或第一次排障。

## 用法示例

```bash
# 默认：内核树真板 dts → out/qemu/imx6ull-aes.dtb（run-qemu.sh 默认使用）
scripts/qemu_helper/make-qemu-dtb.sh

# 指定输出路径
scripts/qemu_helper/make-qemu-dtb.sh --output=out/qemu/my.dtb
```

## 参数与环境变量

| 项 | 默认 | 说明 |
|---|---|---|
| `--output=PATH` | `out/qemu/imx6ull-aes.dtb` | 输出 dtb 路径 |
| `-h`, `--help` | — | 打印用法（头注释只提取到 Usage 一行，完整参数以本表为准） |
| `PROJECT_ROOT` | 自动探测（脚本上两级目录） | 仓库根目录 |
| `LINUX_SRC` | `third_party/linux_mainline` | 内核源码树，须已初始化 submodule 并打好板级补丁 |
| `OUT_BUILD` | `out/linux` | 内核 `O=` 构建树，脚本从里面取 `scripts/dtc/dtc`。单跑 `build-linux.sh` 就是默认值；走 `release-all.sh`（如 CI）时内核在 `out/release-latest/linux`，要显式 `export OUT_BUILD=$PWD/out/release-latest/linux` |

## 关键实现细节

- **前置检查三条**：真板 dts 存在（否则报「submodule 初始化 + 打补丁了
  吗」）；内核 dtc 已编出来（`${OUT_BUILD}/scripts/dtc/dtc`，没编过先跑
  一次 `build-linux.sh`）；系统里有 `fdtput`（没有就
  `apt install device-tree-compiler`）。缺哪个直接报错退出，不硬撑。
- **cpp 预处理**：内核构建对 dts 是先过一遍 `cpp -x assembler-with-cpp`
  展开 `#include`/`#define` 再交 dtc（dtc 本身不认这些，见内核
  `scripts/Makefile.dtbs` 里的 dtc 规则）；脚本照抄这套做法，`-I` 依次指到
  `arch/arm/boot/dts/nxp/imx/`
  （v7.1 里 i.MX dtsi 的实际位置）、`arch/arm/boot/dts/` 及其 `include/`、
  内核 `include/`、以及 `O=` 构建树下的 `arch/arm/boot/dts/`。预处理中间
  产物是 `*.pp.dts`（与输出同目录同名），dtc 编完就删，失败时留着方便
  看卡在哪。
- **用内核自带 dtc**：`${OUT_BUILD}/scripts/dtc/dtc` 与内核构建同版本，
  避开系统 dtc 和内核 dtc 的语法差异。`-@` 把 label 编成 `__symbols__`
  符号表；`-Wno-unit_address_vs_reg` 屏蔽一条已知无伤告警；`-i` 给 dtc
  补 include 搜索路径。
- **退出码判定不靠管道**：dtc 输出经 `grep -v '^WARNING'` 过滤后，用
  `PIPESTATUS[0]` 取真实退出码——只看管道尾的话，一次干净编译（输出全被
  过滤光、grep 无匹配）会被误判成失败。
- **fdtput 只动 blob**：两条 `fdtput -t bx`（`-t bx` 表示按十六进制字节
  序列写入）在编译产物上落 MAC，落点就是 bootloader 修整 dtb 的位置；
  dts/dtsi 一个字符都不动，真机的构建链不受影响。

## 常见问题

- **报 board dts not found**：submodule 没初始化或板级补丁没打。板级
  dts 是随补丁打进内核树的，先按构建流程把 `third_party/linux_mainline`
  备好再跑。
- **报 kernel dtc not built**：没跑过 `build-linux.sh`；或走了
  `release-all.sh` 却忘了把 `OUT_BUILD` 指到 `out/release-latest/linux`。
- **改了 dtsi 但 QEMU 行为没变**：确认改的是内核树
  `arch/arm/boot/dts/nxp/imx/` 下那份 dts/dtsi（别改到别处的副本），然后
  让 `run-qemu.sh` 自动重建，或手动重跑本脚本。
