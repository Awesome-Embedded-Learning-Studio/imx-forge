---
title: 串口终端：开发台的第二块屏幕
---

# 串口终端：开发台的第二块屏幕

> 上一篇咱们把编辑器搬进了开发环境（[VSCode Remote-SSH 连 WSL](02_vscode_remote_ssh.md)）；本篇补上开发台的第二块屏幕：串口。SSH 之外为什么必须再留一条串口通道、Windows 直连与 usbipd 透进 WSL 两条通道怎么选、日志归档落在哪一侧，是本篇要解决的问题。minicom 第一次跑通的入门流程在 start/04，串口日志怎么读在 debug/03，本篇只做开发台形态下的通道选型与常驻配置。

::: info 您将学到
- 为什么 SSH 与串口要当成两条独立通道配置：一条断了，另一条还在
- 通道一的配置要点：MobaXterm 的 COM 口识别、关流控与会话日志
- 通道二的完整链条：usbipd 四条命令，加上 dialout 组与 udev 规则两道权限解法
- 日志归档落在哪一侧的判断依据，以及 QEMU 场景用 run-qemu.sh --log 收串口
:::

::: tip 前置知识 · 咱们的环境
- minicom 首跑与串口参数表在 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md)；WSL2 的网络与文件系统的坑见 [WSL2 开发注意事项](01_wsl2_env_config.md)；picocom 与 tee 的实战用法出自 [启动与调试](../practical/03_boot_and_debug.md)
- 路径上下文：咱们的操作分两侧，Windows 侧的命令在 PowerShell 里跑（bind 要管理员窗口；usbipd-win 5.0 起 attach 不再要求提权，旧版仍要），WSL 侧在仓库根 ~/imx-forge（本机即 /home/charliechen/imx-forge）；本篇不碰源码树与交叉工具链，操作对象是设备节点 /dev/ttyUSB* 与 /etc/udev/rules.d/ 下的配置文件，串口终端用 picocom，虚拟机场景用 scripts/qemu_helper/run-qemu.sh
:::

## 一、串口是开发台的第二块屏幕

上一篇把编辑器搬进了 WSL，开发台还只有一半：编辑和构建在 WSL 里跑得很顺，靠的是 SSH 这条网络道。可这条道有个前提，板子的网络栈得活着。U-Boot 倒计时的时刻、内核 panic 的时刻、rootfs 挂载失败吐 VFS 报错的时刻，SSH 一个字节都送不出来——那些阶段网络压根没起来。这种时候咱们手里只剩串口：UART1 上的控制台从 U-Boot 第一行输出起就在岗，系统死到哪一步它就报到哪一步。所以串口是第二块屏幕，而且是重启都轰不走的那块；两条通道各自独立，一条断了另一条还在。

屏幕的比喻搭完，机制跟上：这块屏幕架在哪一侧，才是本篇真正要解决的问题。start/04 教的是在一台 Linux 主机上把 minicom 跑起来，那张参数表（L28 到 L32：波特率 115200、8N1、无流控）与关流控的 tip（RTS/CTS 开着板子就不出字）是权威表述，咱们照抄即可，见 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md)。咱们的开发台是 Windows 加 WSL2 的组合：USB 转串口芯片插在 Windows 看得见的口上，WSL 默认看不见它。于是通道有了两条，Windows 直连一条，usbipd 透进 WSL 一条。

往后这套开发台还会长出第三条用法：gdbserver 远程调试走网络那条道传控制流（target remote，TCP 上跑 RSP，[gdbserver 远程调试](../debug/01_gdbserver_remote_debug.md) 的主场），SSH/scp 退居辅助，只管登录板子、把程序传上去这类事，串口管现场输出。三条道各司其职，本篇先把咱们这块串口屏幕铺好。

## 二、通道一：Windows 直连串口

省事的是直连。正点原子的教程生态里 Windows 直连串口就是主流做法，MobaXterm 和 PuTTY 都能胜任，咱们不展开工具比较，只说 MobaXterm 的配置要点。建 Session 选 Serial 类型，串口号去设备管理器看：板载 USB 转串口插上后，端口列表里新冒出来的那个 COMx 就是它。Advanced serial settings 里把流控关掉（Hardware Flow Control 选 No），波特率填 115200——就是 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md) 里那张参数表的标准值。想留日志，Session settings 里有 Session logging 开关，打开并指定路径，之后每次连接自动写文件，Windows 侧就有了现成的启动记录。

::: warning 未实测标注
MobaXterm 的图形界面操作在 Windows 桌面完成，本环境是 WSL2 终端，实际跑不了 Windows GUI；上面各项参数值与 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md) 同源可信，菜单与对话框的具体名称以您本机的 MobaXterm 版本为准。
:::

## 三、通道二：usbipd 把串口透进 WSL

另一条通道手续多几步，换来的东西很实在：串口数据直接进 Linux 工具链。完整流程 docker 卷写过两遍，[Docker 基础知识](../docker/01_docker_basics.md) 的 usbipd 段（L526 到 L535）与 [IMX-Forge Docker 开发指南](../docker/02_imx_forge_docker_guide.md) 的 WSL2 USB 直通节（L525 到 L538）各有一份，咱们这里收编成串口场景的顺序，细节回那两章看。

```powershell
# Windows PowerShell（管理员）
winget install usbipd
usbipd list
usbipd bind --busid 1-1
usbipd attach --wsl --busid 1-1
```

咱们把四条命令的分工捋一下：winget 装 usbipd-win；list 列出 Windows 侧全部 USB 设备和总线号；bind 把设备登记为可共享；attach 才真正把它交给 WSL。bind 要管理员权限；usbipd-win 5.0 起 attach 不再要求提权，旧版仍要，这条口径出自微软的 [WSL USB 设备直通文档](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)（docker 卷两章引用的同一份）。busid 以 list 的实际输出为准，1-1 是开发指南文档示例里的编号。list 的输出形如（引自 [IMX-Forge Docker 开发指南](../docker/02_imx_forge_docker_guide.md) 的示例）：

```text
BUSID  DEVICE                                                        STATE
1-1    USB Serial Port (COM3)                                        Not attached
```

::: warning 未实测标注
这四条命令与上面的示例输出都出自 Windows 侧，本环境进不了 PowerShell，没法实测；命令原文与 docker 卷两章一致，界面文案以您本机的 usbipd 版本为准。
:::

attach 成功后，WSL 里会多出一个设备节点。反过来，没透进来是什么样，笔者在这台 WSL2 上实际跑过这条验证命令（这台机器默认 shell 是 zsh，glob 失配时 zsh 直接报 no matches found、连 ls 都不会执行，这里显式用 bash 跑），输出原样如下：

```bash
# WSL ~/
bash -c 'ls /dev/ttyUSB*'
```

```text
ls: cannot access '/dev/ttyUSB*': No such file or directory
```

一个节点都没有，别当成故障，WSL2 默认就是这样：它不像一台装了 Linux 的物理机那样自动接管 USB 设备，Windows 不放手，这边就看不见。attach 之后同一条命令就该列出 /dev/ttyUSB0；个别转串口芯片会识别成 ttyACM0，咱们拿 ls /dev/tty* 核对；识别成别的设备名怎么排查，[串口工具使用（minicom）](../start/04_serial_tools_minicom.md) 的常见问题表里有这一条。

节点出现后，咱们还得过权限这道门。/dev/ttyUSB0 默认归 dialout 组管，普通身份直接开 picocom 会吃权限错误。两种解法，头一种是把自己加进组，一劳永逸：

```bash
# WSL ~/
sudo usermod -aG dialout $USER
# 重新登录，或 newgrp dialout 让本会话立即生效
```

另一种是 udev 规则，把这类设备的权限放开到 0666。仓库的开发环境文档 document/development/ENVIRONMENT_SETUP.md 里有一份现成写法（L263 到 L274），笔者原样摘来：

```ini
# /etc/udev/rules.d/99-usb-serial.rules
# 摘自 document/development/ENVIRONMENT_SETUP.md；同一节还有按 idVendor/idProduct 精确匹配的写法
KERNEL=="ttyUSB*", MODE="0666"
KERNEL=="ttyACM*", MODE="0666"
```

```bash
# WSL ~/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

说到权限，笔者把这台 WSL 的现状也实测了一遍，结果有点打脸：groups 的输出里没有 dialout，/etc/udev/rules.d/ 下面也没有任何 serial 相关的规则文件。也就是说这台机器此刻直接 picocom 是开不了设备的，getent 里 dialout 组存在、成员名单却是空的。权限这一步咱们装环境时最容易漏做，这台机器的现状就是现成证据：

```bash
# WSL ~/
groups
getent group dialout
```

```text
charliechen adm cdrom sudo dip plugdev users docker
dialout:x:20:
```

权限补齐后，咱们一行命令起串口，与 [启动与调试](../practical/03_boot_and_debug.md) 同款：

```bash
# WSL ~/
picocom -b 115200 /dev/ttyUSB0
```

退出按 Ctrl+A 再 Ctrl+X。连上之后您会看到的交互输出（U-Boot 倒计时、内核日志、登录提示符）长什么样，[启动与调试](../practical/03_boot_and_debug.md) 有逐行实录，本篇不重复贴。

::: warning 未实测标注
attach 后 WSL 侧出现 /dev/ttyUSB0、picocom 连上实际的板子看到启动输出，这一段在本环境验证不了，笔者手边没有接板子；命令与 [启动与调试](../practical/03_boot_and_debug.md)、[串口工具使用（minicom）](../start/04_serial_tools_minicom.md) 两章一致，以那两章的实测记录为准。
:::

通道二用起来还有讲究。usbipd list 的清单里不只有串口，USB 声卡、鼠标、无线接收器都在列，咱们看清单时要把设备名对准；attach 错了对象，那个外设当场就从 Windows 消失（bind 只是登记，不影响它在 Windows 侧干活）。互斥是另一回事，放到下面单独说。

::: warning 未实测标注
这两条 Windows 侧行为同样超出本环境的采集范围（进不了 PowerShell）；语义与 docker 卷两章的流程注释一致——bind 登记共享、attach 附加到 WSL2，您上手时以那两章与 usbipd-win 官方文档为准。
:::

::: warning 未实测标注
两通道互斥、先断再透——这条纪律的依据分两半。设备 attach 到 WSL 期间 Windows 用不了它、要切回 Windows 得 usbipd detach（或拔插一次），这一半微软的 [WSL USB 设备直通文档](https://learn.microsoft.com/en-us/windows/wsl/connect-usb) 写明了，docker 卷两章引用的也是这份；Windows 侧 MobaXterm 开着 COM 口时 attach 会不会因此失败，这一半笔者没跑过，Windows 侧的行为在这台 WSL 里无从验证，以 usbipd-win 官方文档为准。稳妥的做法不变：切到 usbipd 通道前，把 Windows 侧的串口会话断开。
:::

## 四、日志怎么留

串口日志是出事后第一手证据，咱们得让它在两侧都能保存成文件。通道一的答案是 MobaXterm 的会话日志，第二节配过之后每次连接自动写文件，日志归 Windows 侧。通道二保存日志的手法在 [启动与调试](../practical/03_boot_and_debug.md) 有现成命令，边看边记：

```bash
# WSL ~/
picocom -b 115200 /dev/ttyUSB0 | tee boot.log
```

QEMU 场景另算：虚拟机里的串口就是 QEMU 进程的 stdout，交互跑的时候输出只在终端上滚，不产生文件。要留档，用 scripts/qemu_helper/run-qemu.sh 的 --log 参数，与 --smoke 搭配，默认落在 out/qemu/uart.log，脚本开头的用法注释写明了这一条。[串口日志阅读路线](../debug/03_serial_log_reading.md) 也把这条命令列为留档手段。它那份 qemu-e2e.log 样本则是另一条路收的：像 e2e-test.sh 那样对整段输出做重定向。笔者本机的产物可以作证：

```bash
# 主机 ~/imx-forge
ls -l out/qemu/uart.log && wc -l out/qemu/uart.log
```

```text
-rw-r--r-- 1 charliechen charliechen 19641 Aug 28 19:58 out/qemu/uart.log
280 out/qemu/uart.log
```

两边都有了手段，选哪边的判断依据一句话：日志归档在哪一侧，后续的分析工具就在哪一侧。您要是打算在 WSL 里 grep 时间戳、拿 addr2line 把 Oops 地址落回源码（整套手法 [串口日志阅读路线](../debug/03_serial_log_reading.md) 讲得完整），日志就留在 WSL 侧用 tee 接；只偶尔翻看，MobaXterm 的会话日志够用。

## 五、两条通道怎么选

串口芯片物理上只有一个，同一时刻谁占用谁负责，这是选型的第一约束。咱们团队要是都在 Windows 侧看串口，直连最省事，MobaXterm 装上就能用，一行 PowerShell 都不用碰。要的不只是看，还想让串口数据进 WSL 的工具链，比如 grep 里程碑词、tee 存日志、接进脚本做联动，那 usbipd 这套链条就值得配起来。

切换的成本也得算：bind 要管理员 PowerShell（usbipd-win 5.0 起 attach 不再要求提权，旧版仍要），两通道互斥，每切一次都得先让占用侧放手（两头的证据口径，第三节的标注框里分开写了），频次高了这套动作就是负担。笔者的建议是按用途定主通道，不来回切：日常开发把串口透进 WSL，跟着工具链走；偶尔要在 Windows 上演示、或者抓一份发给别人看的日志，临时切直连。两条通道的参数完全同源（115200、8N1、无流控），切过去不用改任何串口设置，变的只是谁握着设备。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| attach 后 /dev/ttyUSB* 仍不出现 | bind 没做，或 attach 的 busid 写错 | Windows 侧 usbipd list 核对状态，先 bind 再 attach |
| picocom 报权限错误 | 用户不在 dialout 组，也没配 0666 规则 | usermod -aG dialout，或套用 ENVIRONMENT_SETUP 的 udev 规则 |
| attach 时设备被占用 | 疑似 Windows 侧 MobaXterm 开着该 COM 口（未实测，见第三节标注框） | 稳妥起见断开 Windows 会话再 attach |
| 串口输出乱码 | 波特率或流控不对 | 核对 115200、关流控，排障表见 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md) |
| 设备名是 ttyACM0 不是 ttyUSB0 | 转串口芯片方案不同 | ls /dev/tty* 按实际名字用 |

## 继续学习

- 上一篇：[VSCode Remote-SSH 连 WSL](02_vscode_remote_ssh.md)，把编辑器搬进开发环境
- 下一篇：[clangd 交叉编译配置](04_clangd_cross_compile.md)，让 VSCode 在内核源码里跳转得准
- 深读：minicom 首跑与串口参数表见 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md)；picocom 与 tee 的实战在 [启动与调试](../practical/03_boot_and_debug.md)；日志怎么读见 [串口日志阅读路线](../debug/03_serial_log_reading.md)；usbipd 的原始流程在 [Docker 基础知识](../docker/01_docker_basics.md) 与 [IMX-Forge Docker 开发指南](../docker/02_imx_forge_docker_guide.md)
