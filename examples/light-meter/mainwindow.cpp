#include "mainwindow.h"
#include "ui/breathing_overlay.h"

#ifdef USE_REAL_SENSOR
#include "ap3216c/ap3216c_sensor.h"
#else
#include "mocked/mockedsensor.h"
#endif

#include <QCheckBox>
#include <QDateTime>
#include <QDir>
#include <QFileDialog>
#include <QFrame>
#include <QHBoxLayout>
#include <QKeyEvent>
#include <QLabel>
#include <QMessageBox>
#include <QProgressBar>
#include <QPushButton>
#include <QResizeEvent>
#include <QSlider>
#include <QSplitter>
#include <QStandardPaths>
#include <QStatusBar>
#include <QTextStream>
#include <QTimer>
#include <QVBoxLayout>

// ─────────────────────────────────────────────────────────────────────────────
namespace {
constexpr auto kCssWindow =
    "QMainWindow, QSplitter { background:#1e1e2e; }"
    "QSplitter::handle { background:#11111b; }";

constexpr auto kCssLeftPanel =
    "QWidget#left_panel { background:#1e1e2e; }"
    "QLabel { color:#cdd6f4; }"
    "QCheckBox { color:#cdd6f4; spacing:6px; }"
    "QPushButton { background:#313244; color:#cdd6f4; border:1px solid #45475a;"
    "  border-radius:6px; padding:8px; font-size:13px; }"
    "QPushButton:hover { background:#45475a; }"
    "QPushButton:pressed { background:#181825; }"
    "QSlider::groove:horizontal { height:6px; background:#313244; border-radius:3px; }"
    "QSlider::handle:horizontal { width:16px; margin:-6px 0; background:#cdd6f4; border-radius:8px; }"
    "QProgressBar { background:#313244; border:none; border-radius:5px; height:12px; }"
    "QProgressBar::chunk { background:#27ae60; border-radius:5px; }";
} // namespace

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent) {
    setWindowTitle(QStringLiteral("桌面照度 · light-meter"));
    resize(1024, 600);

    // 数据源(pull 模型): 先 init, 之后由 200ms 定时器 query_once。
    // 后端由编译开关切换: MockedSensor(主机) / Ap3216cSensor(板子, /dev/ap3216c)。
#ifdef USE_REAL_SENSOR
    m_sensor = std::make_unique<Ap3216cSensor>();
#else
    m_sensor = std::make_unique<MockedSensor>();
#endif
    m_sensor->init(false);   // 注: override 不继承基类默认参数, 显式传 false

    buildUi();
    applyStyles();

    // 采样定时器(200ms)
    m_sampleTimer = new QTimer(this);
    m_sampleTimer->setTimerType(Qt::PreciseTimer);
    connect(m_sampleTimer, &QTimer::timeout, this, &MainWindow::onSampleTick);
    m_sampleTimer->start(kSampleMs);

    // 息屏倒计时(单次)
    m_idleTimer = new QTimer(this);
    m_idleTimer->setSingleShot(true);
    connect(m_idleTimer, &QTimer::timeout, this, &MainWindow::enterScreenOff);

    // 呼吸动画(~50ms)
    m_breathTimer = new QTimer(this);
    connect(m_breathTimer, &QTimer::timeout, this, &MainWindow::onBreathTick);

    // 息屏遮罩(铺满整个窗口, 盖住菜单栏/状态栏); 任意鼠标点击即唤醒
    m_overlay = new BreathingOverlay(this);
    m_overlay->installEventFilter(this);
}

MainWindow::~MainWindow() = default;

// ── UI 搭建 ──────────────────────────────────────────────────────────────────
void MainWindow::buildUi() {
    // 左右分栏: 左 ~330(数字+控制, 低频), 右栏折线(唯一高频刷新区)
    auto *splitter = new QSplitter(Qt::Horizontal, this);
    splitter->setChildrenCollapsible(false);
    auto *leftPanel = new QWidget(splitter);
    leftPanel->setObjectName("left_panel");
    auto *rightPanel = new QWidget(splitter);
    rightPanel->setObjectName("right_lux_widget");
    splitter->setSizes({330, 694});
    setCentralWidget(splitter);

    // ── 左栏 ──
    auto *left = new QVBoxLayout(leftPanel);
    left->setContentsMargins(16, 16, 16, 16);
    left->setSpacing(10);

    m_clock = new QLabel(QStringLiteral("桌面照度"), leftPanel);
    QFont f = m_clock->font(); f.setPointSize(13); m_clock->setFont(f);
    left->addWidget(m_clock);

    m_statusLine = new QLabel(QStringLiteral("● 运行"), leftPanel);
    left->addWidget(m_statusLine);

    // 数字卡片(lux 大数字 + 进度条 + 副提示), 运行/告警态靠它翻色
    m_numberCard = new QFrame(leftPanel);
    m_numberCard->setObjectName("numberCard");
    auto *cardLay = new QVBoxLayout(m_numberCard);
    cardLay->setContentsMargins(14, 14, 14, 14);
    cardLay->setSpacing(8);

    m_bigLux = new QLabel(QStringLiteral("— lux"), m_numberCard);
    QFont bf = m_bigLux->font(); bf.setPointSize(40); bf.setBold(true);
    m_bigLux->setFont(bf);
    m_bigLux->setAlignment(Qt::AlignCenter);
    cardLay->addWidget(m_bigLux);

    m_bar = new QProgressBar(m_numberCard);
    m_bar->setRange(0, 100);
    m_bar->setTextVisible(false);
    cardLay->addWidget(m_bar);

    m_subText = new QLabel(QStringLiteral("明亮 ✓"), m_numberCard);
    m_subText->setAlignment(Qt::AlignCenter);
    QFont sf = m_subText->font(); sf.setPointSize(12);
    m_subText->setFont(sf);
    cardLay->addWidget(m_subText);

    left->addWidget(m_numberCard);

    m_pauseBtn = new QPushButton(QStringLiteral("⏸ 暂停"), leftPanel);
    m_pauseBtn->setCheckable(true);
    m_pauseBtn->setFocusPolicy(Qt::NoFocus);   // 不抢焦点: 空格留给"手靠近"
    connect(m_pauseBtn, &QPushButton::toggled, this, &MainWindow::onTogglePause);
    left->addWidget(m_pauseBtn);

    m_exportBtn = new QPushButton(QStringLiteral("📁 导出 CSV"), leftPanel);
    m_exportBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_exportBtn, &QPushButton::clicked, this, &MainWindow::onExportCsv);
    left->addWidget(m_exportBtn);

    // 阈值滑杆行
    auto *thrRow = new QHBoxLayout;
    thrRow->setSpacing(8);
    auto *thrLabel = new QLabel(QStringLiteral("阈值"), leftPanel);
    m_thresholdSlider = new QSlider(Qt::Horizontal, leftPanel);
    m_thresholdSlider->setFocusPolicy(Qt::NoFocus);
    m_thresholdSlider->setRange(100, 700);
    m_thresholdSlider->setValue(int(m_threshold));
    m_thresholdValue = new QLabel(QString::number(int(m_threshold)), leftPanel);
    m_thresholdValue->setMinimumWidth(28);
    thrRow->addWidget(thrLabel);
    thrRow->addWidget(m_thresholdSlider);
    thrRow->addWidget(m_thresholdValue);
    left->addLayout(thrRow);
    connect(m_thresholdSlider, &QSlider::valueChanged, this, &MainWindow::onThresholdChanged);

    // 息屏控制: 自动息屏开关(默认关) + 手动息屏
    auto *sleepRow = new QHBoxLayout;
    sleepRow->setSpacing(8);
    m_autoSleepCheck = new QCheckBox(QStringLiteral("自动息屏"), leftPanel);
    m_autoSleepCheck->setFocusPolicy(Qt::NoFocus);
    m_autoSleepCheck->setToolTip(QStringLiteral("开启后: 手离开 ~10s 自动息屏(默认关闭)"));
    m_sleepBtn = new QPushButton(QStringLiteral("🌙 息屏"), leftPanel);
    m_sleepBtn->setFocusPolicy(Qt::NoFocus);
    sleepRow->addWidget(m_autoSleepCheck);
    sleepRow->addWidget(m_sleepBtn);
    left->addLayout(sleepRow);
    connect(m_autoSleepCheck, &QCheckBox::toggled, this, &MainWindow::onAutoSleepToggled);
    connect(m_sleepBtn, &QPushButton::clicked, this, &MainWindow::onManualSleep);

    left->addStretch(1);

    auto *hint = new QLabel(QStringLiteral("按住 空格 = 手靠近\n息屏后: 按空格 或 鼠标点击 唤醒"),
                           leftPanel);
    hint->setStyleSheet("color:#7f8c8d; font-size:11px;");
    left->addWidget(hint);

    // ── 右栏: 折线图 ──
    auto *right = new QVBoxLayout(rightPanel);
    right->setContentsMargins(8, 8, 8, 8);
    m_chart = new ChartView(rightPanel);
    m_chart->setThreshold(float(m_threshold));
    right->addWidget(m_chart);
}

void MainWindow::applyStyles() {
    setStyleSheet(QString(kCssWindow) + kCssLeftPanel);
    // 数字卡片默认态(绿)
    m_numberCard->setStyleSheet(
        "QFrame#numberCard { background:#181825; border:1px solid #313244; border-radius:10px; }"
        "QLabel { color:#a6e3a1; }");
}

// ── 采样 ─────────────────────────────────────────────────────────────────────
void MainWindow::onSampleTick() {
    if (m_paused) return;   // 暂停: 不采样(空格的唤醒/息屏由键盘事件独立处理)

    // 推进 Mock 的昼夜相位, 再拉一次数据
    m_phase += kPhaseStep;
    m_sensor->set_phase(m_phase);

    auto res = m_sensor->query_once();
    if (!res) {
        // 极少情况下 NotInited: 尝试重初始化一次
        m_sensor->init(true);
        res = m_sensor->query_once();
        if (!res) return;
    }
    processSample(res->luxury, res->ps);
}

void MainWindow::processSample(double lux, int ps) {
    m_lastLux = lux;
    m_chart->pushSample(float(lux));
    m_history.append({QDateTime::currentMSecsSinceEpoch(), float(lux)});
    if (m_history.size() > kMaxHistory)   // 常驻应用: 限制 CSV 历史内存
        m_history.remove(0, m_history.size() - kMaxHistory);

    // 时钟
    m_clock->setText(QTime::currentTime().toString(QStringLiteral("HH:mm")));

    // 大数字 + 进度条
    m_bigLux->setText(QString::number(qRound(lux)) + QStringLiteral(" lux"));
    m_bar->setValue(qBound(0, int(lux / kLuxYMax * 100.0), 100));

    // 告警着色变体
    setAlarmMode(lux < m_threshold);

    // ps 只驱动唤醒/息屏
    resetIdleCountdown(ps);
}

void MainWindow::setAlarmMode(bool alarm) {
    if (alarm) {
        m_numberCard->setStyleSheet(
            "QFrame#numberCard { background:#c0392b; border:1px solid #e74c3c; border-radius:10px; }"
            "QLabel { color:#ffffff; }");
        m_subText->setText(QStringLiteral("光线不足,建议开灯"));
        m_statusLine->setText(QStringLiteral("● 告警"));
        m_statusLine->setStyleSheet("color:#e74c3c;");
    } else {
        m_numberCard->setStyleSheet(
            "QFrame#numberCard { background:#181825; border:1px solid #313244; border-radius:10px; }"
            "QLabel { color:#a6e3a1; }");
        m_subText->setText(QStringLiteral("明亮 ✓"));
        m_statusLine->setText(QStringLiteral("● 运行"));
        m_statusLine->setStyleSheet("color:#a6e3a1;");
    }
}

// ── 接近/息屏状态机 ─────────────────────────────────────────────────────────
void MainWindow::resetIdleCountdown(int ps) {
    const bool near = ps > kPsWakeThreshold;
    if (near) {
        if (m_screenOff) exitScreenOff();
        if (m_idleTimer->isActive()) m_idleTimer->stop();
    } else {
        // 开启"自动息屏"后: 无接近即启动 10s 倒计时(含刚启动的头 10s)。
        // 已在计时则不重启, 否则每个 tick(200ms)都重置, 永远到不了 10s。
        if (m_autoSleep && !m_idleTimer->isActive())
            m_idleTimer->start(kScreenOffMs);
    }
}

void MainWindow::enterScreenOff() {
    if (m_screenOff) return;
    m_screenOff = true;
    m_statusLine->setText(QStringLiteral("● 息屏"));
    m_overlay->setGeometry(rect());   // 盖住整窗(含菜单栏/状态栏)
    m_overlay->raise();
    m_overlay->show();
    m_breathPhase = 0.0;
    m_breathTimer->start(50);
}

void MainWindow::exitScreenOff() {
    if (!m_screenOff) return;
    m_screenOff = false;
    m_breathTimer->stop();
    m_overlay->hide();
    // 恢复运行/告警标签
    setAlarmMode(m_lastLux < m_threshold);
}

void MainWindow::onBreathTick() {
    m_breathPhase += 0.02;   // ~2.5s 一个呼吸周期
    m_overlay->setBreath(float(m_breathPhase));
}

// ── 键盘: 空格模拟"手靠近" ─────────────────────────────────────────────────
void MainWindow::keyPressEvent(QKeyEvent *event) {
    if (event->key() == Qt::Key_Space && !event->isAutoRepeat()) {
        m_sensor->set_held(true);          // 按下 = 手靠近
        if (m_screenOff) exitScreenOff();  // 瞬间唤醒
        if (m_idleTimer->isActive()) m_idleTimer->stop();   // 不必等下一个 tick
    }
    QMainWindow::keyPressEvent(event);
}

void MainWindow::keyReleaseEvent(QKeyEvent *event) {
    if (event->key() == Qt::Key_Space && !event->isAutoRepeat()) {
        m_sensor->set_held(false);         // 松开 = 手离开
        // 开启"自动息屏"时: 松开(即便暂停)直接启动 10s 倒计时 → 到点息屏。
        if (m_autoSleep && !m_idleTimer->isActive()) m_idleTimer->start(kScreenOffMs);
    }
    QMainWindow::keyReleaseEvent(event);
}

void MainWindow::resizeEvent(QResizeEvent *event) {
    QMainWindow::resizeEvent(event);
    if (m_overlay && m_overlay->isVisible())
        m_overlay->setGeometry(rect());
}

bool MainWindow::eventFilter(QObject *watched, QEvent *event) {
    // 息屏态: 任意鼠标点击 → 无条件唤醒(不区分按键/位置)
    if (watched == m_overlay && event->type() == QEvent::MouseButtonPress) {
        exitScreenOff();
        return true;   // 事件到此为止, 不再下发
    }
    return QMainWindow::eventFilter(watched, event);
}

// ── 暂停 / 阈值 / 导出 ──────────────────────────────────────────────────────
void MainWindow::onTogglePause(bool checked) {
    m_paused = checked;
    m_pauseBtn->setText(checked ? QStringLiteral("▶ 继续") : QStringLiteral("⏸ 暂停"));
    if (checked) {
        m_statusLine->setText(QStringLiteral("● 已暂停"));
    } else if (!m_screenOff) {
        setAlarmMode(m_lastLux < m_threshold);   // 立即恢复运行/告警标签
    }
}

void MainWindow::onThresholdChanged(int value) {
    m_threshold = double(value);
    m_thresholdValue->setText(QString::number(value));
    m_chart->setThreshold(float(m_threshold));
    setAlarmMode(m_lastLux < m_threshold);   // 即时重评估告警
}

void MainWindow::onAutoSleepToggled(bool checked) {
    m_autoSleep = checked;
    if (!checked && m_idleTimer->isActive())
        m_idleTimer->stop();   // 关闭自动息屏: 取消进行中的倒计时
}

void MainWindow::onManualSleep() {
    enterScreenOff();   // 立即进入息屏态(按空格唤醒)
}

void MainWindow::onExportCsv() {
    if (m_history.isEmpty()) {
        statusBar()->showMessage(QStringLiteral("暂无数据可导出"), 3000);
        return;
    }
    const QString docs =
        QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    const QString stamp = QDateTime::currentDateTime()
                              .toString(QStringLiteral("yyyyMMdd_HHmmss"));
    const QString def =
        QDir(docs).filePath(QStringLiteral("lightmeter_%1.csv").arg(stamp));

    const QString path =
        QFileDialog::getSaveFileName(this, QStringLiteral("导出 CSV"), def,
                                     QStringLiteral("CSV (*.csv)"));
    if (path.isEmpty()) return;

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        QMessageBox::warning(this, QStringLiteral("导出失败"),
                             QStringLiteral("无法写入文件:\n%1").arg(path));
        return;
    }
    QTextStream s(&f);
    s << "timestamp,lux\n";
    for (const auto &row : m_history) {
        const QString ts = QDateTime::fromMSecsSinceEpoch(row.first)
                               .toString(Qt::ISODateWithMs);
        s << ts << ',' << QString::number(row.second, 'f', 1) << '\n';
    }
    s.flush();
    f.close();

    statusBar()->showMessage(
        QStringLiteral("已导出 %1 条 → %2").arg(m_history.size()).arg(path), 5000);
}
