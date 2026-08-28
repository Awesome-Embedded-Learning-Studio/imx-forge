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
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QWidget>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    QWidget window;
    window.setWindowTitle("AES LCD + touch");
    QVBoxLayout *layout = new QVBoxLayout(&window);

    QLabel *status = new QLabel("touch me (monitor: gt911_touch X Y)");
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
    return app.exec();
}
