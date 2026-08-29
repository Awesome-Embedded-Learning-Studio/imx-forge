// SPDX-License-Identifier: GPL-2.0
/*
 * lcd_button.c — minimal Qt6 widget app to verify the LCD + touch pipeline
 *
 * A fullscreen window with four labeled buttons and a status label: presses
 * from the real input stack (goodix gt911 model → gpio IRQ → evdev → Qt)
 * light up the button on the real eLCDIF panel (mxsfb DRM). On the host
 * side this doubles as the "does the LCD window show anything" check via
 * run-qemu.sh --display=gtk.
 *
 * Touch input — three interchangeable channels, all through the real
 * I2C + IRQ hardware chain:
 *   1. host mouse: click anywhere in the LCD window (GTK frontend; the
 *      gt911 model registers an ABS input handler, so the mouse becomes
 *      the touchscreen — run-qemu.sh --display=gtk)
 *   2. QEMU monitor: gt911_touch X Y / gt911_release (scripted taps)
 *   3. QMP input-send-event (automation)
 *
 * IMPORTANT: the evdevtouch plugin is NOT loaded by the linuxfb platform
 * by default — QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS alone only configures
 * an already-loaded plugin. Pass it explicitly:
 *
 *   ./lcd_button -platform linuxfb -plugin evdevtouch:/dev/input/event1
 */

#include <QApplication>
#include <QEvent>
#include <QTouchEvent>
#include <QScreen>
#include <QLabel>
#include <QPushButton>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <cstdio>

/*
 * EventFilter: logs EVERY input-related event reaching the application,
 * so a single run pinpoints which layer swallowed the touch (none reach
 * the app / events arrive with broken coordinates / taps land but
 * buttons do not react). Filter is installed on the QApplication — it
 * sees events for all widgets before they are dispatched.
 */
class InputProbe : public QObject
{
public:
    explicit InputProbe(QLabel *status) : m_status(status) {}

    bool eventFilter(QObject *obj, QEvent *ev) override
    {
        switch (ev->type()) {
        case QEvent::TouchBegin: {
            QTouchEvent *te = static_cast<QTouchEvent *>(ev);
            QPointF tp = te->points().isEmpty() ? QPointF(-1, -1)
                                                : te->points().first().globalPosition();
            printf("[probe] TouchBegin obj=%s pos=(%.0f,%.0f)\n",
                   obj->metaObject()->className(), tp.x(), tp.y());
            fflush(stdout);
            m_touched = true;
            break;
        }
        case QEvent::TouchUpdate:
            logEvent(obj, ev, "TouchUpdate");
            break;
        case QEvent::TouchEnd:
            logEvent(obj, ev, "TouchEnd");
            m_touched = false;
            break;
        case QEvent::MouseButtonPress:
            logEvent(obj, ev, "MousePress");
            m_touched = true;
            break;
        case QEvent::MouseButtonRelease:
            logEvent(obj, ev, "MouseRelease");
            m_touched = false;
            break;
        default:
            break;
        }
        if (m_status) {
            m_status->setText(m_touched ? QStringLiteral("INPUT SEEN") : name);
        }
        return QObject::eventFilter(obj, ev);
    }

    void announce() const
    {
        QScreen *sc = QGuiApplication::primaryScreen();
        printf("[probe] installed; screen=%dx%d\n",
               sc ? sc->size().width() : -1,
               sc ? sc->size().height() : -1);
        fflush(stdout);
    }

private:
    void logEvent(QObject *obj, QEvent *ev, const char *kind)
    {
        printf("[probe] %s obj=%s\n", kind, obj->metaObject()->className());
        fflush(stdout);
        Q_UNUSED(ev);
    }

    QLabel *m_status = nullptr;
    bool m_touched = false;
    static const char *name;
};
const char *InputProbe::name = "waiting for input...";

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    QWidget window;
    window.setWindowTitle("AES LCD + touch");
    QVBoxLayout *layout = new QVBoxLayout(&window);

    QLabel *status = new QLabel("waiting for input...");
    status->setAlignment(Qt::AlignCenter);
    layout->addWidget(status);

    const char *names[] = { "LED", "BEEP", "CAN", "SENSOR" };
    for (int i = 0; i < 4; i++) {
        QPushButton *btn = new QPushButton(names[i], &window);
        btn->setMinimumHeight(80);
        layout->addWidget(btn);
        QObject::connect(btn, &QPushButton::clicked, [status, i]() {
            status->setText(QString("clicked: %1").arg(i));
        });
    }

    window.showFullScreen();

    InputProbe probe(status);
    app.installEventFilter(&probe);
    probe.announce();

    return app.exec();
}
