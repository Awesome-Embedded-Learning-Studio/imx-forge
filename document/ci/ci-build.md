# Component Build

组件构建工作流，根据变更的路径智能构建相关组件。

## 文件

`.github/workflows/ci-build.yml`

## 触发条件

| 事件 | 条件 |
|------|------|
| `pull_request` | PR 打开或更新到 main 分支 |
| `push` | 推送到 main 分支 |
| `workflow_dispatch` | 手动触发 |

## 路径检测规则

| 变更路径 | 触发的构建 |
|----------|------------|
| `patches/uboot/**`、`patches/uboot-imx/**` | U-Boot |
| `scripts/build_helper/build-uboot.sh` | U-Boot |
| `patches/linux_mainline/**` | Linux (Mainline) |
| `scripts/build_helper/build-linux.sh` | Linux (Mainline) |
| `driver/**` | 驱动示例 |
| `scripts/**` | 所有构建 |
| `.github/workflows/**` | 所有构建 |

## 包含的 Jobs

### detect - 路径检测

使用 `dorny/paths-filter@v2` 检测变更路径，输出布尔值给后续 Job 使用。

### uboot - U-Boot 构建

- 超时：12 分钟
- 产物：`out/uboot/u-boot-dtb.imx`
- 保留期：7 天

### linux - Linux (Mainline) 构建

- 超时：18 分钟
- 产物：`zImage`
- 保留期：7 天
- **与 U-Boot 等其他组件 job 并行运行**

### drivers - 驱动构建

- 超时：8 分钟
- 构建驱动示例（非阻塞）

## 预计时间

| 场景 | 时间 |
|------|------|
| 单个组件 | 8-18 分钟 |
| 全部组件 | ~20 分钟 |

## 缓存策略

- Docker 层缓存：基于 `docker/Dockerfile` 的 hash
- 不缓存构建产物（保守策略）

## 并行执行

U-Boot、Linux (Mainline)、Drivers 各 job 由路径检测结果触发，相互**并行运行**，充分利用 CI 资源。内核只有 Linux (Mainline) 一个 job，没有第二个内核轨的构建。
