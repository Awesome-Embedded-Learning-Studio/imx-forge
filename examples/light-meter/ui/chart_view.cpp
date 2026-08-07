#include "chart_view.h"

#include <QPainter>
#include <QPainterPath>
#include <QPen>

namespace {
// 配色(深色护眼): 背景、网格、文本、正常绿、告警红、阈值虚线
constexpr auto kBg        = "#1e1e2e";
constexpr auto kGridLine  = "#313244";
constexpr auto kAxisText  = "#9399b2";
constexpr auto kGreen     = "#27ae60";
constexpr auto kRed       = "#c0392b";
constexpr auto kThreshold = "#7f8c8d";
} // namespace

ChartView::ChartView(QWidget *parent) : QWidget(parent) {
    m_buf.resize(kCapacity);
    setMinimumSize(360, 220);
}

void ChartView::pushSample(float lux) {
    m_buf[m_head] = lux;
    m_head = (m_head + 1) % kCapacity;
    if (m_count < kCapacity) ++m_count;
    update();   // 只刷自身矩形
}

void ChartView::setThreshold(float threshold) {
    m_threshold = threshold;
    update();
}

void ChartView::clear() {
    m_head = 0;
    m_count = 0;
    update();
}

float ChartView::mappedY(float lux, int top, int height) const {
    const double v = (lux < 0.0) ? 0.0 : (lux > m_yMax ? double(m_yMax) : double(lux));
    return float(top + height - int(v / m_yMax * height));
}

void ChartView::paintEvent(QPaintEvent * /*event*/) {
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing, true);

    p.fillRect(rect(), QColor(kBg));

    // 绘图区: 左留 40px 给 Y 轴刻度, 右/上 12px, 下留 28px 给 X 轴
    const QRect plot = rect().adjusted(40, 12, -12, -28);

    // Y 轴刻度 + 横向网格 (0,200,...,800)
    for (int v = 0; v <= 800; v += 200) {
        const int y = int(mappedY(float(v), plot.top(), plot.height()));
        p.setPen(QPen(QColor(kGridLine), 1, Qt::DotLine));
        p.drawLine(plot.left(), y, plot.right(), y);
        p.setPen(QColor(kAxisText));
        p.drawText(QRect(plot.left() - 38, y - 8, 34, 16),
                   Qt::AlignRight | Qt::AlignVCenter, QString::number(v));
    }

    // 阈值虚线
    const int ty = int(mappedY(m_threshold, plot.top(), plot.height()));
    p.setPen(QPen(QColor(kThreshold), 1, Qt::DashLine));
    p.drawLine(plot.left(), ty, plot.right(), ty);
    p.setPen(QColor(kAxisText));
    p.drawText(QRect(plot.left(), ty - 16, plot.width(), 14),
               Qt::AlignRight, QStringLiteral("阈值 %1").arg(int(m_threshold)));

    // 折线 + 面积(右对齐: 最新点恒在 now=最右, 早期数据从右向左滚动填满)
    const int n = qMin(m_count, kCapacity);
    if (n >= 1) {
        const float lastLux = m_buf[(m_head - 1 + kCapacity) % kCapacity];
        const QColor lineColor = (lastLux < m_threshold) ? QColor(kRed) : QColor(kGreen);

        QPainterPath line;
        QPainterPath fill;
        double lastX = 0.0, lastY = 0.0;
        for (int i = 0; i < n; ++i) {
            const int idx = (m_head - n + i + kCapacity) % kCapacity;
            const float lux = m_buf[idx];
            const double x = plot.left()
                             + double(i + (kCapacity - n)) / (kCapacity - 1) * plot.width();
            const double y = mappedY(lux, plot.top(), plot.height());
            if (i == 0) {
                line.moveTo(x, y);
                fill.moveTo(x, plot.bottom());   // 面积左侧从底部垂直升起
                fill.lineTo(x, y);
            } else {
                line.lineTo(x, y);
                fill.lineTo(x, y);
            }
            lastX = x; lastY = y;
        }
        // 面积在最末点垂直落到底再闭合 → 只填曲线正下方, 不拉到空数据区的右下角。
        fill.lineTo(lastX, plot.bottom());
        fill.closeSubpath();

        // 曲线下半透明填充
        QColor fc = lineColor; fc.setAlpha(48);
        p.fillPath(fill, fc);

        if (n >= 2) {
            p.setPen(QPen(lineColor, 2));
            p.setBrush(Qt::NoBrush);
            p.drawPath(line);
        }

        // 当前点(now, 最右)
        p.setBrush(lineColor);
        p.setPen(Qt::NoPen);
        p.drawEllipse(QPointF(lastX, lastY), 4.5, 4.5);
    }

    // X 轴标签
    p.setPen(QColor(kAxisText));
    p.drawText(QRect(plot.left(), plot.bottom() + 6, plot.width(), 16),
               Qt::AlignLeft, QStringLiteral("-30s"));
    p.drawText(QRect(plot.left(), plot.bottom() + 6, plot.width(), 16),
               Qt::AlignRight, QStringLiteral("now"));
}
