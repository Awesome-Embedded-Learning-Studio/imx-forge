# Example

这个文件夹放的是例子相关的程序，为了解耦合，确保花式的依赖都能测试，这里的example就单独进行维护，Fork了本IMX-Forge做自己依赖测试的朋友可以利用这里的程序测试自己的包是否正常。因为Example是单独维护，不会放到scripts/下做自动化，而是反过来，在这里做自动化脚本，按照需求运行。

目前按照大纲，主要是分为三个部分：
1. system，纯Linux系统依赖App（任何无依赖Or轻依赖的App）
2. Qt（任何QtApp）
3. driver（跟设备驱动联动的测试）
4. 和一个复合的，如果是多方面的project（较大型的项目工程）

## qemu-hello：模拟板上的第一个驱动 + 应用

[qemu-hello/](qemu-hello/) 是「自写内核模块 + 自写应用」在 QEMU 模拟板上跑通的最小完整示例，也是无板用户上手模拟开发的标准入口——一个 misc 字符设备模块（每次 read 返回带内核 uptime 的一行问候）加一个配套静态应用，走完「编写 → 交叉编译 → TFTP 投递 → insmod → 运行 → 卸载」的完整开发循环：

```bash
cd examples/qemu-hello
export PATH=/opt/arm-gnu-toolchain/bin:$PATH
make install          # 编译两件产物并投递到 ~/tftp（与真机 netboot 共用）
scripts/qemu_helper/run-qemu.sh   # 另开终端启动模拟板，root/root 登录
# guest 内：
#   udhcpc -i eth1 && tftp -g -r hello_mod.ko 10.0.2.2 && insmod hello_mod.ko
#   tftp -g -r hello_app 10.0.2.2 && chmod +x hello_app && ./hello_app
#   cat /dev/hello && rmmod hello_mod
```

坑位记录（写模块前值得一看）：32 位 ARM 内核模块里 u64 除法会引入 libgcc 的 `__aeabi_uldivmod` 符号导致 modpost 报 undefined，用内核原生 `do_div()`；外挂模块的 `O=` 树是 `out/mainline/linux`（不是 `out/mainline`）。

