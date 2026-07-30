#include "breathing_overlay.h"

#include <QPainter>

#include <cmath>

BreathingOverlay::BreathingOverlay(QWidget *parent) : QWidget(parent) {
    setAttribute(Qt::WA_NoSystemBackground, true);
    setAttribute(Qt::WA_TransparentForMouseEvents, false);
    setFocusPolicy(Qt::NoFocus);
    hide();
}

void BreathingOverlay::setBreath(float t) {
    m_t = t;
    update();   // 只刷自身矩形
}

void BreathingOverlay::paintEvent(QPaintEvent * /*event*/) {
    QPainter p(this);
    p.fillRect(rect(), QColor(0, 0, 0));

    constexpr float kTwoPi = 6.28318530717958647692f;   // 不用非标准 M_PI(MSVC 下未定义)
    const float a = (std::sin(m_t * kTwoPi) + 1.0f) * 0.5f;   // 0..1
    const int r = int(5 + 7 * a);
    const int alpha = int(70 + 185 * a);

    p.setBrush(QColor(180, 200, 255, alpha));
    p.setPen(Qt::NoPen);
    p.drawEllipse(rect().center(), r, r);
}
