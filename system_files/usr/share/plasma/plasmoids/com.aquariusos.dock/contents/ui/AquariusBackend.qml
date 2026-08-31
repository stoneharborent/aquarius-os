/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Royce Adkins <royce@stoneharborentertainment.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// AQUARIUS DEVIATION — this whole file is ours. Upstream has no equivalent.
//
// WHY THIS FILE EXISTS
// ....................
// On Plasma 6.7 the stock task manager is NOT a folder of QML files. It is a
// compiled shared library (`org.kde.plasma.taskmanager.so`) that carries its
// QML inside itself as Qt resources, plus a C++ helper class called `Backend`
// (upstream `applets/taskmanager/backend.cpp`). The QML reaches that helper by
// importing `plasma.applet.org.kde.plasma.taskmanager`.
//
// That import only resolves while that exact library is loaded. Our dock is a
// plain folder of QML files — the ordinary, stable way to ship a widget — so
// the import is not available to us and the C++ helper is not either. This file
// stands in for it: same method names, same signals, same enum, so every line
// of upstream QML that called the helper still reads the same.
//
// Some of what the C++ did cannot be done from QML at all. Those methods are
// still here so nothing crashes, but they answer "nothing". Each one says below
// exactly what is lost. The full list is also in FORK-NOTES.md next door, and
// the reasoning is in `docs/aquarius-dock.md` in the repo.

import QtQuick

QtObject {
    id: backendShim

    // Mirrors Backend::MiddleClickAction (backend.h). The numbers matter: they
    // are what `middleClickAction` stores in the config file, so they have to
    // stay in this order to keep reading a config written by the stock widget.
    enum MiddleClickAction {
        None,                   // 0
        Close,                  // 1
        NewInstance,            // 2
        ToggleMinimized,        // 3
        ToggleGrouping,         // 4
        BringToCurrentDesktop   // 5
    }

    // Emitted when something dropped on the dock should become a pinned app.
    // main.qml connects to this exactly as it does upstream. Nothing in this
    // file emits it today — upstream did not either; the C++ side raised it
    // from a code path (drag-and-drop onto a jump-list entry) that we no
    // longer have. Kept so main.qml's handler stays valid.
    signal addLauncher(url launcherUrl)

    // Upstream: raised when the user picks "All Places" inside the right-click
    // menu's Places section, to reopen the menu with the long list. We have no
    // Places section (see placesActions below), so this never fires. It still
    // has to exist — ContextMenu.qml connects and disconnects it by name.
    signal showAllPlaces()

    // ---------------------------------------------------------------------
    // Still fully working — these needed C++ only for convenience.
    // ---------------------------------------------------------------------

    // Where an icon sits on the screen, in screen pixels. The window manager
    // uses it to animate a window shrinking down to its dock icon. QML can
    // work this out on its own, so nothing is lost here.
    function globalRect(item) {
        if (!item) {
            return Qt.rect(0, 0, 0, 0);
        }
        const topLeft = item.mapToGlobal(0, 0);
        return Qt.rect(topLeft.x, topLeft.y, item.width, item.height);
    }

    // ---------------------------------------------------------------------
    // Reduced — these answer "nothing" or make a good guess. What each one
    // costs is written out; none of them can crash.
    // ---------------------------------------------------------------------

    // Upstream turned "applications:firefox.desktop" into the real path of that
    // .desktop file by asking KService. We hand back the URL untouched.
    // COST: dragging an icon OUT of the dock into another app hands that app
    // the shorthand URL instead of a file path. Reordering inside the dock, and
    // dragging apps in from elsewhere, are unaffected.
    function tryDecodeApplicationsUrl(launcherUrl) {
        return launcherUrl;
    }

    // Upstream asked KService whether a URL names an installed application.
    // We check the shape of the URL instead.
    // COST: dropping a file that merely looks like a .desktop entry could be
    // treated as an app. Plasma still refuses to pin something it cannot launch.
    function isApplication(url) {
        if (!url) {
            return false;
        }
        const asString = url.toString();
        return asString.startsWith("applications:") || asString.endsWith(".desktop");
    }

    // Upstream walked the process tree so that audio coming from a helper
    // process could be traced back to the app that started it. Reading the
    // process tree is not something QML can do.
    // COST: the little speaker badge, and mute-from-the-dock, may not appear
    // for apps that play sound from a separate process — Chromium-based
    // browsers and Electron apps are the usual ones. Apps that play their own
    // sound are unaffected. -1 means "no parent", which is what upstream
    // returns for a process it cannot trace.
    function parentPid(pid) {
        return -1;
    }

    // Upstream read the Categories= line out of an app's .desktop file.
    // COST: one thing only — a browser's tooltip will not add the media title
    // to the window title. Every other tooltip is unchanged.
    function applicationCategories(launcherUrl) {
        return [];
    }

    // ---------------------------------------------------------------------
    // Gone — the jump lists. These are the real loss of not having the C++.
    // ---------------------------------------------------------------------
    //
    // Upstream built three extra right-click sections by reading the app's
    // .desktop file and KDE's recent-documents store:
    //
    //   Places          Dolphin's bookmarked folders, under Dolphin's icon
    //   Recent Files    documents you recently opened in that app
    //   Actions         the app's own shortcuts — "New Private Window",
    //                   "Compose Message", and so on (the freedesktop
    //                   "Desktop Actions" spec)
    //
    // All three come from C++ that builds real QAction objects. QML cannot
    // build a QAction, so these return empty and those sections do not appear.
    //
    // Everything ELSE in the right-click menu is untouched, because it comes
    // from the window manager rather than from this helper: Close, Minimise,
    // Maximise, Move to Desktop, Move to Activity, Pin/Unpin, More Actions,
    // and the media-player controls.
    //
    // ContextMenu.qml already copes with an empty list — it drops a section
    // that has no entries, and it deliberately omits the "Actions" heading when
    // there is nothing else in the menu, so no empty headings are left behind.
    //
    // This is the same breakage the research note predicted for dock forks
    // (docs/v2-shell-tier2-research.md, Layer 3). Getting the jump lists back
    // means compiling the applet ourselves; docs/aquarius-dock.md explains why
    // we decided that is not worth it.

    function placesActions(launcherUrl, showAllPlaces, parent) {
        return [];
    }

    function recentDocumentActions(launcherUrl, parent) {
        return [];
    }

    function jumpListActions(launcherUrl, parent) {
        return [];
    }

    // Upstream made the virtual-desktop entries behave as one radio group, so
    // ticking one unticked the rest. Without it they are still tick boxes and
    // still work; only the automatic un-ticking is gone.
    function setActionGroup(action) {
        // Intentionally empty — needs a QActionGroup, which is C++ only.
    }
}
