// Exercise the preload adapter through a real Qt event loop. No Resolve install
// or display server is needed: run with QT_QPA_PLATFORM=offscreen.
#include <QAction>
#include <QApplication>
#include <QFontInfo>
#include <QLabel>
#include <QMainWindow>
#include <QMenu>
#include <QMenuBar>
#include <QProcess>
#include <QPushButton>
#include <QTimer>
#include <QPainter>
#include <QPixmap>
#include <QProxyStyle>
#include <QStyleOptionMenuItem>
#include <cstdio>

static int failures = 0;
static void check(bool passed, const char *message) {
    if (!passed) { std::fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}

// Reproduce an application style overriding the font after menu layout.
class SmallMenuStyle final : public QProxyStyle {
public:
    mutable int smallPaints = 0;
    mutable int largePaints = 0;
    void drawControl(ControlElement element, const QStyleOption *option,
                     QPainter *painter, const QWidget *widget = nullptr) const override {
        if (element == CE_MenuItem) {
            const auto menuOption = qstyleoption_cast<const QStyleOptionMenuItem *>(option);
            if (menuOption && menuOption->menuItemType != QStyleOptionMenuItem::Separator) {
                QFont font = painter->font();
                const bool large = menuOption->text.startsWith("Large");
                font.setPixelSize(large ? 24 : 10);
                font.setItalic(true);
                painter->save();
                painter->setFont(font);
                check(QFontInfo(painter->font()).pixelSize() == (large ? 24 : 14),
                      "custom menu painter uses readable font and preserves larger font");
                check(painter->font().italic(), "menu painter preserves font attributes");
                if (large) ++largePaints; else ++smallPaints;
                painter->drawText(option->rect, Qt::AlignVCenter, menuOption->text);
                painter->restore();
                return;
            }
        }
        QProxyStyle::drawControl(element, option, painter, widget);
    }
};
class BodyPainter final : public QWidget {
public:
    int paints = 0;
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        QFont font = painter.font();
        font.setPixelSize(10);
        painter.setFont(font);
        check(QFontInfo(painter.font()).pixelSize() == 10, "non-menu painter remains unchanged");
        ++paints;
    }
};

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    const QByteArray expectedPreload = argc > 1 ? QByteArray(argv[1]) : QByteArray();
    check(qgetenv("LD_PRELOAD") == expectedPreload,
          "adapter removes itself and preserves unrelated preload entries");
    QFont small = app.font();
    small.setPixelSize(10);
    app.setFont(small);
    const QString sheet = "QLabel { color: #dddddd; } QPushButton { color: #eeeeee; }";
    app.setStyleSheet(sheet);
    QMainWindow window;
    auto bar = window.menuBar();
    const QString barSheet = "QMenuBar { color: #cccccc; }";
    bar->setStyleSheet(barSheet);
    auto file = bar->addMenu("File");
    auto action = file->addAction("Example");
    bool triggered = false;
    QObject::connect(action, &QAction::triggered, [&] { triggered = true; });
    auto body = new QLabel("Editing body", &window);
    auto button = new QPushButton("Editing button", &window);
    window.setCentralWidget(body);
    window.show();
    app.processEvents();
    const QFont bodyFont = body->font();
    const QFont buttonFont = button->font();
    QMenuBar large;
    QFont larger = small; larger.setPixelSize(24);
    large.setFont(larger);
    large.setMinimumHeight(48);
    large.addAction("Large menu")->setFont(larger);
    large.show();
    app.processEvents();
    const QFont originalLargeFont = large.font();
    const QFont originalLargeActionFont = large.actions().first()->font();
    QTimer::singleShot(0, [&] {
        check(QFontInfo(bar->font()).pixelSize() >= 14, "menu font is readable");
        check(bar->minimumHeight() >= 32 && bar->height() >= 32, "menu row has readable height");
        check(QFontInfo(bar->actions().first()->font()).pixelSize() >= 14, "top menu action font is readable");
        check(body->font() == bodyFont, "body label font unchanged");
        check(button->font() == buttonFont, "body button font unchanged");
        check(QFontInfo(file->font()).pixelSize() >= 14, "dropdown font readable");
        check(QFontInfo(action->font()).pixelSize() >= 14, "dropdown action font readable");
        check(app.styleSheet() == sheet && bar->styleSheet() == barSheet, "original stylesheets unchanged");
        check(large.font() == originalLargeFont && QFontInfo(large.font()).pixelSize() == 24 && large.minimumHeight() == 48, "larger font and height preserved");
        check(large.actions().first()->font() == originalLargeActionFont, "larger action font preserved");
        action->trigger();
        check(triggered, "menu actions still emit their callback");
        auto late = new QMenuBar;
        late->setFont(small);
        late->addMenu("Created after startup");
        late->show();
        auto submenu = late->actions().first()->menu()->addMenu("Late submenu");
        submenu->setFont(small);
        auto subaction = submenu->addAction("Nested action");
        submenu->show();
        SmallMenuStyle nativeStyle;
        QMenu painted;
        painted.setStyle(&nativeStyle);
        painted.addAction("Small custom font");
        painted.addAction("Large custom font")->setFont(larger);
        painted.resize(painted.sizeHint());
        QPixmap canvas(painted.size());
        painted.render(&canvas);
        check(nativeStyle.smallPaints > 0 && nativeStyle.largePaints > 0, "custom menu painting exercised");
        BodyPainter bodyPainter;
        bodyPainter.resize(80, 30);
        QPixmap bodyCanvas(bodyPainter.size());
        bodyPainter.render(&bodyCanvas);
        check(bodyPainter.paints > 0, "body painting exercised");
        auto lateAction = new QAction("Added after show", submenu);
        lateAction->setFont(small);
        submenu->addAction(lateAction);
        QTimer::singleShot(0, [&, late, submenu, subaction, lateAction] {
            check(QFontInfo(late->font()).pixelSize() >= 14 && late->minimumHeight() >= 32,
                  "menu created after event loop receives adjustment");
            check(QFontInfo(late->actions().first()->font()).pixelSize() >= 14,
                  "late menu action receives adjustment");
            check(QFontInfo(submenu->font()).pixelSize() >= 14 && QFontInfo(subaction->font()).pixelSize() >= 14,
                  "late submenu and nested action readable");
            check(QFontInfo(lateAction->font()).pixelSize() >= 14,
                  "action added to an already visible menu receives adjustment");
            QProcess child;
            child.start("/usr/bin/env", QStringList());
            check(child.waitForFinished(5000) && child.exitCode() == 0,
                  "helper process starts normally");
            QByteArray childPreload;
            for (const auto &line : child.readAllStandardOutput().split('\n'))
                if (line.startsWith("LD_PRELOAD=")) childPreload = line.mid(11);
            check(childPreload == expectedPreload, "helper inherits unrelated preload only");
            delete late;
            app.exit(failures ? 1 : 0);
        });
    });
    const int result = app.exec();
    if (!result) std::puts("Resolve menu behavior: PASS");
    return result;
}
