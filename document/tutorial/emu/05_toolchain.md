# 05 — 三件套封装:run-qemu.sh 与防陈旧的自动重建

::: info 本节你将学到
- 三件套脚本的分工与依赖顺序:rootfs 镜像 → 变体 dtb → 启动
- 防陈旧自动重建的实现:`find -newer` 扫树判新鲜度,为什么顶层目录的 mtime 不可信
- 冒烟模式(`--smoke`)的判定语义:超时为什么算成功、串口关键字链怎么给 CI 消费
- 交互模式长什么样:登录、跑命令、干净关机,以及模拟环境眼下还有哪些东西没有戏
:::

## 陈旧产物这颗哑巴雷

第四章结束时,正确的命令散落在 shell 历史里,更要命的是产物新鲜度没人管:改了 dtsi,`out/qemu/` 里的 dtb 还是旧的;重跑了 Buildroot,rootfs 镜像还是旧的。拿着旧产物启动,QEMU 不报任何错,跑的是一个「你以为改了、其实没改」的系统。笔者就中过一次招:调设备树调了半天,行为纹丝不动,最后发现根本没重编 dtb。报错的问题好排查,静默的旧产物才难缠。

所以封装要干两件事:固化命令,管好重建时机。`scripts/qemu_helper/` 三件套按依赖排:`make-rootfs-img.sh` 管第三章的镜像,`make-qemu-dtb.sh` 管第四章的变体编译,`run-qemu.sh` 是唯一入口,启动前自检产物、拼参数,交互和冒烟两种模式都在它身上。

## 交互模式:一次真实的会话

日常就是一条命令:

```bash
scripts/qemu_helper/run-qemu.sh
```

串口落在当前终端。下面这份是实打实的会话记录(收在本卷 `assets/session-login.log`,输入的命令是咱们敲的,输出是系统给的):

```text
buildroot login: root
# uname -a
Linux buildroot 7.1.0-dirty #1 Wed Jul 8 17:35:29 CST 2026 armv7l GNU/Linux
# cat /proc/cpuinfo | grep -E "model|MHz" | head -3
model name	: ARMv7 Processor rev 5 (v7l)
# ls /dev/mmc*
/dev/mmcblk1
# poweroff -f
[   44.515451] reboot: Power down
```

用户名和密码都是 `root`,`uname` 报 armv7l,CPU 是 Cortex-A7 的翻译执行,12 秒左右到登录提示(TCG 的速度,对这个体量的系统完全够用)。`poweroff -f` 这条有讲头:它会走到 SNVS 的 poweroff 模型,QEMU 干净退场,退出码 0——第三章见过的「下次启动没有 EXT4 恢复流程」,干净关机的功劳就在这。退出的另一条路是终端里 `Ctrl-A X`,直接杀 QEMU,效果等同于拔电源,偶尔用用没关系,养成习惯就等着收 journal 回放吧。

## 自动重建:判定谁比谁旧

启动前的自检在 `run-qemu.sh` 里,dtb 这路拿变体 dts 和内核树的整个 dtsi 目录,跟现有 dtb 比 mtime:

```bash
newer="$(find "${dts}" "${imx_dtsi_dir}" \
    \( -name '*.dts' -o -name '*.dtsi' \) \
    -newer "${DTB}" -print -quit 2>/dev/null)"
if [[ -n "${newer}" ]]; then
    log "dtb stale (newer: ${newer#"${PROJECT_ROOT}/"}), rebuilding"
    "${SCRIPT_DIR}/make-qemu-dtb.sh" || die "make-qemu-dtb.sh failed"
fi
```

`-print -quit` 的意思:找到第一个比 dtb 新的文件就停,不扫全树——判定只要「有没有」,多少无所谓。扫的对象是整个 `nxp/imx/` 目录而非只有变体 include 的那几个文件,因为 include 关系脚本不追踪,宁可多编:dtc 亚秒级,多编一次的代价可以忽略,漏编一次就是笔者上面吃过的哑巴亏。

rootfs 镜像这路结构相同,扫的对象换成 `out/release-latest/rootfs/` 整棵树。这里有个容易想当然的地方:只看顶层目录的 mtime 行不行?不行。Buildroot 更新 rootfs 是原地覆写,`cp` 覆盖一个已有文件时,父目录的 mtime 纹丝不动,只有文件自己变新。所以必须钻进树里逐文件比——这行代码扫的是几万个文件,在一块现代 SSD 上耗不到两秒,换来的是「Buildroot 跑完、镜像必新」。

三条边界,各有各的道理。显式传了 `--dtb=` 或 `--rootfs-img=` 的产物不参与重建——指名要这个文件就尊重它,哪怕它是旧的;`--no-build` 模式下产物缺失直接报错退出,实测的报错长这样:

```text
[run-qemu] error: rootfs image not found: out/qemu/rootfs.ext4 (run make-rootfs-img.sh)
```

不偷偷补建,这是给 CI 缓存场景的——流水线里「意外触发十分钟重构建」比报错麻烦一个量级。内核 zImage 也排除在自动重建之外,理由是量级:dtb 和镜像是秒级重建,交给脚本;重编内核是分钟级的重活,该由人显式发起,脚本替人跑这种活,越权了。

## 冒烟模式:给 CI 的判定语义

`--smoke` 面向无人值守,核心是回答「怎么算启动成功」。实现朴素:QEMU 挂在 `timeout` 下跑,串口重定向进日志,结束后拿关键字去 grep:

```bash
timeout --foreground "${TIMEOUT}" qemu-system-arm ... -nographic -no-reboot \
    >"${LOG_PATH}" 2>&1
QEMU_RC=$?
case "${QEMU_RC}" in
    0|124) ;;   # 正常结束或超时杀掉,都进入关键字判定
    *) die "QEMU exited with rc=${QEMU_RC}" ;;
esac
for pat in "${EXPECTS[@]}"; do
    grep -qE -- "${pat}" "${LOG_PATH}" || FAILED=1
done
```

两个语义选择都有讲究。超时杀掉(`rc=124`)归入正常路径,因为一次成功的启动会停在登录提示符前永远等输入,QEMU 自己不会退——把「到了 login 但没人输密码」判成失败,这个测试就永远是红的;真正的判定交给关键字,默认期望 `buildroot login:`,`--expect` 可以重复传正则,做「内核版本号 + 登录提示」的链式断言。这套做法抄的是 QEMU 官方 functional test 和 Buildroot runtime test 的惯例,那边用 `U-Boot` → `Starting kernel` → `login:` 的链,每一环都是启动链往前走了一步的证据。本机验证一次:

```text
$ scripts/qemu_helper/run-qemu.sh --smoke --timeout=240
[run-qemu] smoke test: timeout 240s, expecting: buildroot login:
[run-qemu] PASS: matched 'buildroot login:'
```

退出码 0/1 直接给 CI 步骤消费,`uart.log` 存档,失败时第四章那套读法随时能上。把它挂进 `ci-build.yml` 的 mainline job、给 docker 镜像补 `qemu-system-arm`,是下一阶段的活。

## 边界:模拟器里什么没有戏

收尾把当前环境的边界交代清楚,免得朋友们撞了墙怀疑自己。I2C 总线上,ap3216c(光照)、wm8960(音频 codec)、gt9147(触摸)全部超时:

```text
[    1.341817] wm8960 0-001a: Failed to issue reset
[    1.343121] wm8960 0-001a: probe with driver wm8960 failed with error -110
```

控制器是真模型,总线上没挂任何器件,驱动发地址等 ACK,等到 `-110` 超时。真板上缺器件更多见 `-6`(`-ENXIO`,从机秒拒),QEMU 这边控制器等满超时才放弃——同一个「没器件」,两种错误码,排查时别混淆。FlexCAN 的 `-110` 第二章讲过,桩上读零。温度传感器这条有点冤:

```text
[   12.832517] platform 20c8000.anatop:tempmon: deferred probe pending: imx_thermal: failed to init from nvmem
```

它要 OCOTP 熔丝盒里的校准数据,而 OCOTP 是咱们自己在第四章关掉的第一批地鼠之一——自己关的门,把温度传感器也关在了外面。FEC 那两条 deferred(`reason unknown`)还没破案:驱动编在内核里,`fec_probe` 符号都在,就是没人绑上来,笔者怀疑是 `phy-supply` 引的那颗 regulator-fixed(挂在 gpio5 上)永远不 ready,没查透,记在这,下一阶段收拾。

这些边界排开,后面阶段的路线也就顺出来了:CAN 和触摸要写 QEMU 器件模型,FEC 的 defer 要啃设备树供应链,显示等 QEMU 11.1,U-Boot 链等 Bin Meng 那个系列进 release。每一样都够再折腾一章。

::: tip 卷尾
五章走完:一份按版本意识维护的设备树变体、一套防陈旧的三件套、一条验证过的直启链路,外加「串口死寂 → earlycon → 三路读 panic」的排障手法。下一块拼图是 CI——让每次内核提交自动回答「能不能开机」。
:::
