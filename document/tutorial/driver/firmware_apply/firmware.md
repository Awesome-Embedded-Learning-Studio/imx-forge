---
title: 固件安装指南
---

# i.MX6ULL 固件安装完全指南：SDMA 与 regulatory.db 实战排查

> **适用平台**：i.MX6ULL / i.MX6UL  
> **内核版本**：Linux 6.x（自编译）  
> **根文件系统**：NFS 挂载 or eMMC  
> **作者**：CharlieChen114514

---

## 前言

在自编译 i.MX6ULL Linux 内核时，启动日志中经常出现两类令人头疼的固件缺失报错：

```
imx-sdma: Direct firmware load for imx/sdma/sdma-imx6q.bin failed with error -2
imx-sdma: external firmware not found, using ROM firmware

platform regulatory.0: Direct firmware load for regulatory.db failed with error -2
cfg80211: failed to load regulatory.db
```

本文记录了从现象到根因、再到自动化修复脚本的完整排查过程，并深入解释了两种不同的固件部署策略，帮助读者彻底搞清楚嵌入式 Linux 固件加载机制。

---

## 一、固件加载机制简介

Linux 内核加载外部固件有两个阶段：

```
阶段一（早期启动）：Direct firmware load
  → 内核直接从已挂载的文件系统读取 /lib/firmware/
  → 若此时 rootfs 尚未挂载（如 NFS 场景），必然失败

阶段二（fallback）：Falling back to sysfs fallback
  → 交由 udev 处理，从用户空间重新尝试加载
  → 依赖 udev 规则和完整的 rootfs
```

**NFS 根文件系统的特殊性：** 内核在网络初始化完成、NFS 挂载之前就会触发固件加载请求，此时 `/lib/firmware/` 根本不存在，直接加载必然失败。这是 NFS 场景下固件问题的核心原因。

---

## 二、SDMA 固件问题

### 2.1 问题现象

```
[   64.518650] imx-sdma 20ec000.dma-controller: Direct firmware load for imx/sdma/sdma-imx6q.bin failed
[   64.529509] imx-sdma 20ec000.dma-controller: Falling back to sysfs fallback for: imx/sdma/sdma-imx6q.bin
[  125.924807] imx-sdma 20ec000.dma-controller: external firmware not found, using ROM firmware
```

**影响**：SDMA 降级为片内 ROM 固件运行，性能受限，部分 DMA 功能（如音频 DMA、UART DMA）可能工作异常。

### 2.2 获取固件

```bash
# 方式一：apt 安装（最简单，推荐）
sudo apt-get install linux-firmware

# 固件路径
ls /lib/firmware/imx/sdma/sdma-imx6q.bin
```

### 2.3 部署到 rootfs

```bash
mkdir -p /your/rootfs/lib/firmware/imx/sdma
cp /lib/firmware/imx/sdma/sdma-imx6q.bin \
   /your/rootfs/lib/firmware/imx/sdma/
```

### 2.4 验证成功

重启后 dmesg 应显示：

```
imx-sdma 20ec000.dma-controller: firmware found.
imx-sdma 20ec000.dma-controller: loaded firmware 3.3
```

---

## 三、regulatory.db 问题（重点）

### 3.1 问题现象

```
platform regulatory.0: Direct firmware load for regulatory.db failed with error -2
platform regulatory.0: Falling back to sysfs fallback for: regulatory.db
cfg80211: failed to load regulatory.db
```

**影响**：
- Wi-Fi 回退到最保守的默认频率限制
- 发射功率和可用信道受限，部分 5GHz DFS 信道无法使用
- `iw reg set CN` 等国家码设置可能不生效
- 生产环境存在无线合规问题

### 3.2 根因一：加载时序问题（NFS 场景）

对比日志时间戳，可以发现关键的时序问题：

```
[    7.521]  regulatory.db: Direct firmware load failed   ← 此时 NFS 还没挂载！
[   17.016]  VFS: Mounted root (nfs filesystem)           ← NFS 才在这里挂载
[   69.604]  cfg80211: failed to load regulatory.db       ← 最终失败
```

文件系统挂载前固件不可达，这是 NFS 场景的必然结果。

### 3.3 根因二：固件签名不匹配（更隐蔽！）

即使把文件放对了位置，还可能遇到：

```
cfg80211: loaded regulatory.db is malformed or signature is missing/invalid
```

原因在于，`CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=y` 时，内核会用**编译时内置的公钥**验证 `regulatory.db.p7s` 的签名。

标准内核内置的是这两个证书：

```
sforshee: 00b28ddf47aef9cea7         ← 官方 sforshee 公钥
wens: 61c038651aabdcf94bd0ac7ff06c7248db18c600
```

如果你的 `regulatory.db.p7s` 来自 robertfoss 的 fork：

```bash
# ❌ 错误来源（fork 仓库，用自己的私钥签名）
wget https://raw.githubusercontent.com/robertfoss/wireless-regdb/master/regulatory.db.p7s
```

就会出现这样的密钥不匹配：

```
robertfoss 私钥签出的 .p7s
        ✗ 无法通过验证
sforshee 公钥（内嵌进内核）
```

**正确做法**：从官方仓库获取配对文件：

```bash
# ✅ 正确来源：官方 wireless-regdb
git clone https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git

# 或通过 apt
sudo apt-get install wireless-regdb
# 文件位置：/lib/firmware/regulatory.db 和 /lib/firmware/regulatory.db.p7s
```

---

## 四、两种部署策略

### 策略 A：运行时加载（放入 rootfs）

适合 eMMC 根文件系统，文件放在板子的 `/lib/firmware/` 下：

```bash
mkdir -p /your/rootfs/lib/firmware
cp /lib/firmware/regulatory.db     /your/rootfs/lib/firmware/
cp /lib/firmware/regulatory.db.p7s /your/rootfs/lib/firmware/
```

| 优点 | 缺点 |
|------|------|
| 无需重新编译内核 | NFS 场景下时序问题依然存在 |
| 更新方便，直接替换文件 | 需要完整的 udev 支持 |

### 策略 B：编译进内核（EXTRA_FIRMWARE）

适合 **NFS 场景或追求零依赖**的生产环境，固件直接打包进 zImage：

```makefile
CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"
CONFIG_EXTRA_FIRMWARE_DIR="/path/to/wireless-regdb"   # 编译机上的路径
```

> ⚠️ **重要区分**：`CONFIG_EXTRA_FIRMWARE_DIR` 指向的是**编译主机**上的路径，
> 与目标板 rootfs 的 `/lib/firmware/` 完全无关。
> 编译完成后，固件已嵌入 zImage，目标板 rootfs 无需有这两个文件。

| 优点 | 缺点 |
|------|------|
| 彻底规避时序问题 | 路径硬编码，需脚本动态注入 |
| rootfs 无需携带固件文件 | 更新固件必须重新编译内核 |
| 适合批量自动化生产 | |

---

## 五、自动化构建脚本

对于批量生产场景，不能依赖 menuconfig 手动配置。以下脚本在每次构建时动态 patch defconfig，彻底解决路径硬编码和重复配置问题：

```bash
#!/bin/bash
# patch_defconfig_firmware.sh
# 在 make defconfig 之后、make zImage 之前调用

set -e

LINUX_SRC_DIR="/home/charliechen/imx-forge/linux"
DEFCONFIG="your_imx6ull_defconfig"
ROOTFS_DIR="/home/charliechen/imx-forge/rootfs/nfs"

# wireless-regdb 官方仓库路径（编译机上）
REGDB_DIR="/home/charliechen/wireless-regdb"

patch_defconfig_firmware() {
    local DEFCONFIG_FILE="${LINUX_SRC_DIR}/arch/arm/configs/${DEFCONFIG}"
    local SDMA_DIR="${ROOTFS_DIR}/lib/firmware/imx/sdma"

    echo "[INFO] Patching firmware config..."

    # ── 检查固件文件 ─────────────────────────────────────────
    if [ ! -f "${REGDB_DIR}/regulatory.db" ] || \
       [ ! -f "${REGDB_DIR}/regulatory.db.p7s" ]; then
        echo "[ERROR] regulatory.db or .p7s not found in ${REGDB_DIR}"
        echo "        Run: git clone https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git"
        exit 1
    fi

    if [ ! -f "${SDMA_DIR}/sdma-imx6q.bin" ]; then
        echo "[ERROR] sdma-imx6q.bin not found in ${SDMA_DIR}"
        echo "        Run: sudo apt install linux-firmware && cp /lib/firmware/imx/sdma/sdma-imx6q.bin ${SDMA_DIR}/"
        exit 1
    fi

    # ── 清除旧配置，避免重复追加 ──────────────────────────────
    sed -i '/^CONFIG_EXTRA_FIRMWARE=/d'                "$DEFCONFIG_FILE"
    sed -i '/^CONFIG_EXTRA_FIRMWARE_DIR=/d'            "$DEFCONFIG_FILE"
    sed -i '/^CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=/d' "$DEFCONFIG_FILE"

    # ── 写入新配置 ────────────────────────────────────────────
    # 注意：EXTRA_FIRMWARE_DIR 指向编译机路径，不是 rootfs！
    echo 'CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"' >> "$DEFCONFIG_FILE"
    echo "CONFIG_EXTRA_FIRMWARE_DIR=\"${REGDB_DIR}\""              >> "$DEFCONFIG_FILE"
    echo 'CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=n'                  >> "$DEFCONFIG_FILE"

    echo "[INFO] Patched config:"
    grep -E "EXTRA_FIRMWARE|SIGNED_REGDB" "$DEFCONFIG_FILE"
    echo "[INFO] Firmware patch done."
}

patch_defconfig_firmware
```

### 关键设计原则

```
1. 每次从干净的 defconfig 开始构建          ✅
2. 先 sed -i 删除旧配置，再追加新配置       ✅ 避免重复
3. 路径通过变量传入，不硬编码               ✅ 多机通用
4. 构建前校验固件文件存在                   ✅ 快速失败
5. EXTRA_FIRMWARE_DIR 与 rootfs 路径分离    ✅ 概念清晰
```

---

## 六、关闭签名验证 vs 保留签名验证

| 场景 | 推荐配置 | 说明 |
|------|----------|------|
| 开发调试 | `CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=n` | 最快解决，无需关心签名 |
| 生产发布 | `=y` + 使用官方配对文件 | 保证无线频率合规性 |

---

## 七、验证清单

### 上位机验证（编译后）

```bash
# 确认 regulatory.db 已编入 zImage
strings arch/arm/boot/zImage | grep -q "regulatory.db" \
    && echo "✅ regulatory.db 已编入 zImage" \
    || echo "❌ 未找到"
```

### 板子验证（启动后）

```bash
# SDMA 固件
dmesg | grep sdma
# ✅ 期望：imx-sdma: loaded firmware 3.3

# regulatory.db
dmesg | grep -i regulatory
# ✅ 期望：cfg80211: Regulatory database loaded
# ❌ 不应出现：failed to load / malformed / signature
```

---

## 八、问题排查速查表

| 报错信息 | 根本原因 | 解决方案 |
|----------|----------|----------|
| `failed with error -2` | 文件不存在 | 检查文件是否在正确路径 |
| `using ROM firmware` | SDMA 固件未找到 | 复制 `sdma-imx6q.bin` 到 rootfs |
| `failed to load regulatory.db` | 时序问题（NFS）| 用 `EXTRA_FIRMWARE` 编进内核 |
| `malformed or signature invalid` | 签名不匹配（用了 fork 仓库）| 换用官方 sforshee 仓库的文件 |
| `cfg80211: failed to load` | `.p7s` 未找到或签名校验失败 | 关闭 `REQUIRE_SIGNED_REGDB` 或换正确来源 |

---

## 总结

1. **SDMA 固件**：从 `linux-firmware` 包获取，放入 rootfs 的 `/lib/firmware/imx/sdma/` 即可。

2. **regulatory.db**：有两个坑——**时序问题**和**签名来源问题**。NFS 场景必须用 `EXTRA_FIRMWARE` 编进内核；签名文件必须来自官方 `sforshee/wireless-regdb` 仓库，不能用第三方 fork。

3. **自动化**：在构建脚本中动态 patch defconfig，`EXTRA_FIRMWARE_DIR` 填写编译机上的路径，与 rootfs 路径完全无关。每次从干净环境重建内核，配置始终正确。