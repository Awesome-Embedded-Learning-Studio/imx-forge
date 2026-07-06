# Rootfs Overlay

buildroot `BR2_ROOTFS_OVERLAY` 源目录。构建时本目录内容会叠加到 rootfs target(覆盖同名文件),替代原 `scripts/merge_overlay_rootfs.sh` 的运行时 cp 合并。

当前为空(预留)。后续自定义内容可放此目录,例如:

- `usr/share/fonts/` —— CJK / Emoji 字体(阶段二接入,替代 install_fonts.sh 的非 DejaVu 部分)
- `etc/` —— 自定义系统配置
- `root/` 或 `home/` —— 板端应用与脚本

> 注意:本目录替代了原 `rootfs/overlay/rootfs/`(后者从未启用,见 `.gitignore` 的 `*` 全忽略)。
