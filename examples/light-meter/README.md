# light-meter —— 桌面照度护眼摆件（Mock）

一个常驻工位的小摆件：监测桌面环境光照度 `lux`（国标 GB 50034 规定书桌阅读 ≥ **300 lux**，
低于此值界面变红提醒开灯），并用接近度 `ps` 实现「手靠近 → 唤醒亮屏；人离开 ~10s → 息屏」。

本阶段为 **Mock**：数据由 `MockedSensor` 产生（正弦波模拟昼夜波动 + 随机抖动），
**不接真硬件**，Windows + Linux 双平台原生可跑。

## 功能

| 档 | 功能 | 说明 |
|---|---|---|
| P0 | ALS 折线 + lux 大数字 | 当前 lux 大字号 + 30s 滚动折线（自绘 `ChartView`，非 Qt Charts） |
| P0 | 暗光告警 | `lux < 阈值` → 左侧数字区翻红底白字 + 「光线不足，建议开灯」 |
| P0 | 接近唤醒 / 离开息屏 | `ps > 500` → 唤醒；无接近 10s → 全黑呼吸点息屏 |
| P1 | CSV 导出 | 导出 `timestamp,lux` 全量会话到文件 |
| P2 | 暂停 / 继续 | 手动停 / 继采样 |
| P2 | 告警阈值可调 | 滑杆即时改阈值（默认 300） |

> lux 真值换算（raw ALS × 系数）属真机阶段，Mock 直接产物理量。

## 构建（Windows / Linux 相同）

```bash
# 前提：Qt6 已安装且 CMAKE_PREFIX_PATH 指向它（或 Qt 在 PATH）
cmake -B build -DCMAKE_PREFIX_PATH="<你的 Qt 路径，如 C:/Qt/6.x.x/msvc2022_64>"
cmake --build build --config Release

# Linux:   ./build/light-meter
# Windows: build\Release\light-meter.exe
```

## 键位 / 操作

| 操作 | 效果 |
|---|---|
| **按住 空格** | 模拟「手靠近」→ `ps` 升高、状态点变化；息屏时瞬间唤醒 |
| **🌙 息屏** | 手动立即进入息屏态（按空格唤醒） |
| **自动息屏（复选框）** | **默认关闭**；勾选后手离开 ~10s 自动息屏 |
| **⏸ 暂停 / ▶ 继续** | 停 / 继采样（折线停止滚动） |
| **📁 导出 CSV** | 把整段会话导出为 `timestamp,lux` |
| **阈值滑杆** | 调整告警线（100–700），即时生效 |

## 目录结构

```
light-meter/
├── CMakeLists.txt
├── main.cpp                 # Qt 入口
├── mainwindow.{h,cpp}       # 三态 UI + 键盘 + 息屏状态机 + CSV 导出(纯代码, 无 .ui)
├── ui/                      # 自绘控件(一类一文件)
│   ├── chart_view.{h,cpp}       # QPainter 折线(环形缓冲, 局部刷新)
│   └── breathing_overlay.{h,cpp}# 息屏遮罩(全黑 + 呼吸点)
├── sensor/
│   ├── sensor.{h,cpp}       # 抽象数据源契约(pull 模型, std::expected)
│   └── mocked/
│       └── mockedsensor.{h,cpp}  # Mock 数据(正弦 lux + 接近度)
└── README.md
```

## 三态如何验证

- **运行态**：启动即进入。折线每 200ms 更新，lux 按 ~25s 周期正弦起伏（绿色）。
- **告警态**：lux 自然跌破阈值时，左侧数字卡翻红；升回阈值以上恢复绿色。
- **息屏态**：点「🌙 息屏」立即息屏（全屏黑 + 中央呼吸点）；或勾「自动息屏」后松开空格约 10s 自动息屏。按空格瞬间唤醒。
