#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QTime>

#include <memory>

#include "ui/chart_view.h"
#include "mocked/mockedsensor.h"

QT_BEGIN_NAMESPACE
class QCheckBox;
class QFrame;
class QLabel;
class QProgressBar;
class QPushButton;
class QSlider;
class QTimer;
QT_END_NAMESPACE

class BreathingOverlay;

/// 三态: 运行 / 告警(运行态着色变体) / 息屏。ps(接近度)只在幕后驱动唤醒/息屏。
class MainWindow : public QMainWindow {
    Q_OBJECT

  public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

  protected:
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

  private slots:
    void onSampleTick();
    void onTogglePause(bool checked);
    void onExportCsv();
    void onThresholdChanged(int value);
    void onBreathTick();
    void onAutoSleepToggled(bool checked);
    void onManualSleep();

  private:
    void buildUi();
    void applyStyles();

    void processSample(double lux, int ps);
    void setAlarmMode(bool alarm);
    void enterScreenOff();
    void exitScreenOff();
    void resetIdleCountdown(int ps);

    // 集中可调参数(见 tasks.md §10 ✅)
    static constexpr int    kSampleMs       = 200;     // 采样周期
    static constexpr double kLuxYMax        = 800.0;   // Y 轴上界
    static constexpr double kPhaseStep      = 0.05;    // 每 tick 正弦相位步进(~25s 周期)
    static constexpr int    kPsWakeThreshold = 500;    // ps>500 视为"有接近"
    static constexpr int    kScreenOffMs    = 10000;   // 无接近 10s → 息屏
    static constexpr int    kMaxHistory     = 18000;   // CSV 历史上限(~1h @5Hz), 防 OOM

    std::unique_ptr<MockedSensor> m_sensor;

    ChartView  *m_chart          = nullptr;
    QTimer     *m_sampleTimer    = nullptr;   // 200ms 周期采样
    QTimer     *m_idleTimer      = nullptr;   // 单次: 无接近 10s → 息屏
    QTimer     *m_breathTimer    = nullptr;   // 息屏呼吸动画

    // 左栏控件
    QFrame     *m_numberCard     = nullptr;
    QLabel     *m_clock          = nullptr;
    QLabel     *m_statusLine     = nullptr;
    QLabel     *m_bigLux         = nullptr;
    QProgressBar *m_bar          = nullptr;
    QLabel     *m_subText        = nullptr;
    QPushButton *m_pauseBtn      = nullptr;
    QPushButton *m_exportBtn     = nullptr;
    QPushButton *m_sleepBtn      = nullptr;
    QCheckBox  *m_autoSleepCheck = nullptr;
    QSlider    *m_thresholdSlider = nullptr;
    QLabel     *m_thresholdValue = nullptr;

    BreathingOverlay *m_overlay  = nullptr;   // 息屏全屏黑 + 呼吸点

    double m_phase       = 0.0;
    double m_threshold   = 300.0;             // 告警阈值(可由滑杆改)
    bool   m_paused      = false;
    bool   m_screenOff   = false;
    bool   m_autoSleep   = false;   // 自动息屏开关(默认关; 开启后无接近 10s 自动息屏)
    double m_lastLux     = kLuxYMax;
    double m_breathPhase = 0.0;

    // 完整会话历史(用于 CSV 导出): { 毫秒时间戳, lux }
    QVector<QPair<qint64, float>> m_history;
};

#endif // MAINWINDOW_H
