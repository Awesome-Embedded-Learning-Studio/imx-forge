#ifndef CHART_VIEW_H
#define CHART_VIEW_H

#include <QWidget>

/**
 * @brief 自绘 lux 折线图(不依赖 Qt Charts)。
 *
 * 环形缓冲,容量 150 点(= 30s @ 200ms)。pushSample() 仅触发自身矩形重绘,
 * 对 linuxfb / 局部刷新友好。Mock 与真机阶段共用同一组件。
 */
class ChartView : public QWidget {
    Q_OBJECT
  public:
    explicit ChartView(QWidget *parent = nullptr);

    /// 追加一个采样点并刷新。
    void pushSample(float lux);
    /// 设置告警阈值(画虚线),lux 低于此值折线/当前点染红。
    void setThreshold(float threshold);
    /// 清空历史。
    void clear();

    QSize sizeHint() const override { return {520, 320}; }

  protected:
    void paintEvent(QPaintEvent *event) override;

  private:
    float mappedY(float lux, int top, int height) const;

    static constexpr int kCapacity = 150;   ///< 30s @ 200ms
    QVector<float> m_buf;                   ///< 环形缓冲
    int   m_head   = 0;                     ///< 下一个写入位置
    int   m_count  = 0;                     ///< 已有有效点数(<= kCapacity)
    float m_threshold = 300.0f;             ///< 告警阈值
    float m_yMax = 800.0f;                  ///< Y 轴上界(固定)
};

#endif // CHART_VIEW_H
