# e2e-test.sh - 端到端板级体检脚本详解

## 脚本概述

`e2e-test.sh` 是模拟板的一键端到端验证:启动自建 QEMU(mcimx6ul-evk)+ mainline 内核 + QEMU 变体 dtb + rootfs 镜像,登录进系统后对每个外设子系统跑一条真实断言,最后输出 PASS/FAIL 报告。它是 `run-qemu.sh --smoke`(只验「能开机」)的完全体——回答的是「外设们是否都在正常工作」。

### 覆盖的检查项

| 检查 | 判据 | 验证的外设模型 |
|------|------|----------------|
| rtc-walk | 两次 `date +%s` 差 ≥2s | SNVS LPSRTC 走时(11.1 原生) |
| net-dhcp-ping | `udhcpc` + `ping 10.0.2.2` 返回 0 | fec2 + slirp 用户网络 |
| can0 | `/sys/class/net/can0` 存在 | FlexCAN2 接线(patch 0002) |
| pwm-backlight | `pwmchip0` + `/sys/class/backlight/*` | i.MX27 PWM 模型(patch 0003) |
| display-fb | `fb0` + dmesg `Initialized mxsfb` | eLCDIF + DRM_MXSFB(11.1 原生) |
| usb-bus | dmesg `ci_hdrc` 计数 ≥1 | chipidea USB(11.1 原生) |
| sd-card | `/proc/partitions` 含 mmcblk1 | USDHC2 + SD 卡模型 |
| ap3216c-als | `i2cget` 读 ALS 值在 0x01xx 段 | ap3216c 模型(patch 0005) |
| icm20608-probe | insmod 教学驱动后 dmesg probe success | icm20608 模型(patch 0006) |
| gt911-probe | dmesg 出现 goodix ID 911 | gt911 触摸模型(0008-0016 系列) |
| wm8960-codec | `i2cget` 0x1a 有寄存器应答 | wm8960 控制面模型 |
| gpio-inject | monitor `gpio_set` 后 PSR bit18 翻转 | gpio_set HMP 命令(patch 0004) |
| deferred-list | defer 列表仅剩 sound-wm8960 | 整体启动健康度 |

音频(wm8960+SAI)按规划仍是控制面待做项,断言按「预期留在 defer 列表」处理而非失败。

### 实现要点

- **guest 算结果、host 做断言**:每条检查在 guest 里产生一行全局唯一的 `KEY=value`(如 `RTCDELTA=2`、`NETRC=0`),宿主侧对整个日志 `grep`——比按标记分段切片稳得多(串口输出与回显交错时分段极脆)
- **中途切 monitor**:gpio 注入检查用 `Ctrl-A C`(`\001c`)跳进 QEMU monitor 执行 `gpio_set`,再跳回串口读 PSR 验证
- **前置刷新**:默认先跑一遍 `run-qemu.sh --smoke`,顺路享受 dtb/rootfs 镜像的陈旧检测与自动重建(`--no-build` 跳过)

### 用法

```bash
scripts/qemu_helper/e2e-test.sh                 # 全量(先刷新产物)
scripts/qemu_helper/e2e-test.sh --no-build      # 产物已新鲜时
```

退出码 0/1 可直接给 CI 消费;完整串口日志在 `out/qemu/e2e.log`。前置依赖:icm20608 教学驱动 `.ko` 需在 rootfs 树里(`out/release-latest/rootfs/root/`),脚本会检查并提示。

### 在开发工作流中的位置

CI 里的目标形态:内核构建 → `run-qemu.sh --smoke`(启动冒烟)→ 本脚本(外设体检)。日常开发中,改了 QEMU patch 或设备树变体后跑一次,13 项报告即外设对齐状态的即时快照。
