// Resolve's main menu uses Qt widgets while much of its interface uses a custom
// style engine. Local Qt stylesheets hide its menu labels. Change only the main
// menu's font and minimum height, preserving the application's renderer, colors,
// dropdowns, editing controls and global scale. Uses Qt 5 public ABI only.
#include <QAction>
#include <QApplication>
#include <QEvent>
#include <QFontInfo>
#include <QMenuBar>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {
// The launcher preloads this library only into Resolve. Remove our entry before
// Resolve can start browser bridges or helper processes; preserve other entries.
__attribute__((constructor)) void stopPreloadInheritance() {
    const char *preload = std::getenv("LD_PRELOAD");
    Dl_info info{};
    if (!preload || !dladdr(reinterpret_cast<void *>(&stopPreloadInheritance), &info)
        || !info.dli_fname) return;
    char *copy = strdup(preload);
    if (!copy) return;
    std::string remaining;
    char *state = nullptr;
    for (char *entry = strtok_r(copy, " :", &state); entry;
         entry = strtok_r(nullptr, " :", &state)) {
        if (std::strcmp(entry, info.dli_fname) == 0) continue;
        if (!remaining.empty()) remaining += ' ';
        remaining += entry;
    }
    if (remaining.empty()) unsetenv("LD_PRELOAD");
    else setenv("LD_PRELOAD", remaining.c_str(), 1);
    free(copy);
}

QFont readableFont(QFont font) {
    // Respect an already larger user/app font, including a point-sized font.
    if (QFontInfo(font).pixelSize() < 14) font.setPixelSize(14);
    return font;
}

class MenuFilter final : public QObject {
    bool applying = false;
public:
    explicit MenuFilter(QObject *parent) : QObject(parent) {}
    void apply(QMenuBar *bar) {
        if (applying || !bar) return;
        applying = true;
        const auto font = readableFont(bar->font());
        if (font != bar->font()) bar->setFont(font);
        if (bar->minimumHeight() < 32) bar->setMinimumHeight(32);
        for (auto action : bar->actions()) {
            const auto actionFont = readableFont(action->font());
            if (actionFont != action->font()) action->setFont(actionFont);
        }
        applying = false;
    }
protected:
    bool eventFilter(QObject *object, QEvent *event) override {
        if (event->type() == QEvent::Show || event->type() == QEvent::Polish
            || event->type() == QEvent::FontChange)
            apply(qobject_cast<QMenuBar *>(object));
        return false;
    }
};
}

int QApplication::exec() {
    using Exec = int (*)();
    const auto original = reinterpret_cast<Exec>(dlsym(RTLD_NEXT, "_ZN12QApplication4execEv"));
    auto filter = new MenuFilter(qApp);
    qApp->installEventFilter(filter);
    for (auto widget : QApplication::allWidgets())
        filter->apply(qobject_cast<QMenuBar *>(widget));
    // Keep launching even if symbol lookup changes in a future Qt build.
    return original ? original() : QCoreApplication::exec();
}
