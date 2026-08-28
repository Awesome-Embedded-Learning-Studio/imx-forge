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
 * Touch injection from the QEMU monitor:
 *   (qemu) gt911_touch 100 120   # presses whatever is at that point
 *   (qemu) gt911_release
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
