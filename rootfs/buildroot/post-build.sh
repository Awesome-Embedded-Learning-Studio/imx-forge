#!/bin/bash
#
# post-build.sh — buildroot BR2_ROOTFS_POST_BUILD_SCRIPT
#
# buildroot 在 `make` 过程中、rootfs 打包前调用本脚本,$1 = TARGET_DIR(buildroot rootfs
# target 目录,即 output/target)。
#
# 职责(替代原 varified_rootfs_ok.sh 的构造部分):
#   ① 补 linuxrc -> bin/busybox 软链(buildroot skeleton 默认不建,NFS/老式 init 兼容);
#   ② 跑 varified_rootfs_ok.sh 校验闸门(issue #76:rootfs 必须完整,否则中止构建)。
#
# 注:目录骨架、fstab/inittab/rcS、busybox、第三方库均由 buildroot(skeleton + packages +
#     overlay)接管,本脚本不再生成这些 —— 只补 linuxrc 这个 buildroot 默认缺失的兼容项。

set -e

TARGET_DIR="${1:?TARGET_DIR (buildroot post-build \$1) required}"

# 定位项目根(post-build.sh 在 rootfs/buildroot/,回退两级)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ① linuxrc 软链(仅当 busybox 已装且 linuxrc 不存在)
if [[ -x "${TARGET_DIR}/bin/busybox" && ! -e "${TARGET_DIR}/linuxrc" ]]; then
    echo "[post-build] Creating linuxrc -> bin/busybox"
    ln -sf bin/busybox "${TARGET_DIR}/linuxrc"
fi

# ② 补建 buildroot skeleton 不保证、但项目 varified_rootfs_ok.sh 期望的目录
#    (buildroot 用 root/ 作用户家,不建 home/;此处补齐)
mkdir -p "${TARGET_DIR}/home"

# ②-bis /etc/securetty:项目 busybox.config 带 CONFIG_FEATURE_SECURETTY=y,login 要求
#     该文件列出允许 root 登录的 tty;buildroot skeleton 不建它 → root 登录被全拒。
#     补全常用串口/控制台(ttymxc0 是 imx6ull 调试串口)。
if [[ ! -f "${TARGET_DIR}/etc/securetty" ]]; then
    printf '%s\n' console tty1 tty2 tty3 tty4 tty5 tty6 \
        ttyS0 ttyS1 ttymxc0 ttymxc1 ttymxc2 ttyAMA0 ttyUSB0 \
        > "${TARGET_DIR}/etc/securetty"
fi

# ③ i.MX SDMA 固件:SDMA 驱动(音频 dma 等)运行时需要,从 armbian firmware 仓库下载。
#    替代 install_firmwares.sh。缓存到 out/.firmware-cache 实现幂等。下载失败仅告警
#    (网络问题不应阻塞 rootfs 构建;SDMA 驱动会报缺固件但不影响 rootfs 完整性)。
IMX_FW_DIR="${TARGET_DIR}/lib/firmware/imx/sdma"
FW_CACHE="${PROJECT_ROOT}/out/.firmware-cache"
mkdir -p "${IMX_FW_DIR}" "${FW_CACHE}"
if [[ ! -s "${FW_CACHE}/sdma-imx6q.bin" ]]; then
    echo "[post-build] Downloading sdma-imx6q.bin..."
    if ! curl -fL --retry 3 --connect-timeout 30 -o "${FW_CACHE}/sdma-imx6q.bin" \
        "https://github.com/armbian/firmware/raw/master/imx/sdma/sdma-imx6q.bin"; then
        echo "[post-build] WARN: sdma-imx6q.bin 下载失败(网络/代理?),rootfs 将不含 SDMA 固件" >&2
        rm -f "${FW_CACHE}/sdma-imx6q.bin"
    fi
fi
[[ -s "${FW_CACHE}/sdma-imx6q.bin" ]] && cp -a "${FW_CACHE}/sdma-imx6q.bin" "${IMX_FW_DIR}/"

# ③-bis Noto CJK + Emoji 字体:仅当 rootfs 含 Qt6 时下载(Qt GUI 才需;最小 rootfs
#      无 Qt6 → 跳过省 ~30MB)。DejaVu 由 buildroot dejavu 包装(随 Qt6 fragment)。
if [[ -f "${TARGET_DIR}/usr/lib/libQt6Core.so" ]]; then
FONTS_DIR="${TARGET_DIR}/usr/share/fonts"
FONTS_CACHE="${PROJECT_ROOT}/out/.fonts-cache"
mkdir -p "${FONTS_DIR}" "${FONTS_CACHE}"
# Noto Sans CJK Regular(中文;zip 含 7 个分权重 ttc,只取 Regular 省 volume,~18MB)
if [[ ! -s "${FONTS_CACHE}/NotoSansCJK-Regular.ttc" ]]; then
    echo "[post-build] Downloading Noto Sans CJK..."
    if curl -fL --retry 3 --connect-timeout 30 -o "${FONTS_CACHE}/03_NotoSansCJK-OTC.zip" \
        "https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/03_NotoSansCJK-OTC.zip"; then
        unzip -o "${FONTS_CACHE}/03_NotoSansCJK-OTC.zip" "NotoSansCJK-Regular.ttc" -d "${FONTS_CACHE}/" 2>/dev/null
    else
        echo "[post-build] WARN: Noto CJK 下载失败(网络?),rootfs 不含中文字体" >&2
    fi
fi
[[ -s "${FONTS_CACHE}/NotoSansCJK-Regular.ttc" ]] && cp -a "${FONTS_CACHE}/NotoSansCJK-Regular.ttc" "${FONTS_DIR}/"
# Noto Color Emoji(表情,直接 ttf,~9MB)
if [[ ! -s "${FONTS_CACHE}/NotoColorEmoji.ttf" ]]; then
    echo "[post-build] Downloading Noto Color Emoji..."
    curl -fL --retry 3 --connect-timeout 30 -o "${FONTS_CACHE}/NotoColorEmoji.ttf" \
        "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf" \
        || echo "[post-build] WARN: Noto Emoji 下载失败" >&2
fi
[[ -s "${FONTS_CACHE}/NotoColorEmoji.ttf" ]] && cp -a "${FONTS_CACHE}/NotoColorEmoji.ttf" "${FONTS_DIR}/"
else
    echo "[post-build] Qt6 not in rootfs — 跳过 CJK/Emoji 字体(最小 rootfs)"
fi

# ④ 校验闸门(致命;失败则 buildroot make 中止)
echo "[post-build] Running rootfs verification gate..."
bash "${PROJECT_ROOT}/scripts/varified_rootfs_ok.sh" --rootfs-dir="${TARGET_DIR}"
