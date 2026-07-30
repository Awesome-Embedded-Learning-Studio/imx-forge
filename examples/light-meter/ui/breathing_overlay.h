#ifndef BREATHING_OVERLAY_H
#define BREATHING_OVERLAY_H

#include <QWidget>

/**
 * @brief 息屏遮罩: 全屏黑底 + 中央慢呼吸点。
 *
 * 纯 paintEvent, 无信号/槽, 故不需要 Q_OBJECT。由 MainWindow 在息屏态
 * show()/raise() 铺满整窗; 按空格唤醒时 hide()。
 */
class BreathingOverlay : public QWidget {
  public:
    explicit BreathingOverlay(QWidget *parent = nullptr);

    /// 设置呼吸相位 t(任意单调浮点, 内部取正弦映射到 0..1 亮度)。
    void setBreath(float t);

  protected:
    void paintEvent(QPaintEvent *event) override;

  private:
    float m_t = 0.0f;
};

#endif // BREATHING_OVERLAY_H
