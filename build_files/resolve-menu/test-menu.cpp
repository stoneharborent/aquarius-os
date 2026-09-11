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
#include <cstdio>

static int failures = 0;
static void check(bool passed, const char *message) {
    if (!passed) { std::fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}

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
    const QFont dropdownFont = file->font();
    const QFont dropdownActionFont = action->font();
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
        check(QFontInfo(bar->font()).pixelSize() >= 16, "menu font is readable");
        check(bar->minimumHeight() >= 32 && bar->height() >= 32, "menu row has readable height");
        check(QFontInfo(bar->actions().first()->font()).pixelSize() >= 16, "top menu action font is readable");
        check(body->font() == bodyFont, "body label font unchanged");
        check(button->font() == buttonFont, "body button font unchanged");
        check(file->font() == dropdownFont, "dropdown font unchanged");
        check(action->font() == dropdownActionFont, "dropdown action font unchanged");
        check(app.styleSheet() == sheet && bar->styleSheet() == barSheet, "original stylesheets unchanged");
        check(large.font() == originalLargeFont && QFontInfo(large.font()).pixelSize() == 24 && large.minimumHeight() == 48, "larger font and height preserved");
        check(large.actions().first()->font() == originalLargeActionFont, "larger action font preserved");
        action->trigger();
        check(triggered, "menu actions still emit their callback");
        auto late = new QMenuBar;
        late->setFont(small);
        late->addMenu("Created after startup");
        late->show();
        QTimer::singleShot(0, [&, late] {
            check(QFontInfo(late->font()).pixelSize() >= 16 && late->minimumHeight() >= 32,
                  "menu created after event loop receives adjustment");
            check(QFontInfo(late->actions().first()->font()).pixelSize() >= 16,
                  "late menu action receives adjustment");
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
