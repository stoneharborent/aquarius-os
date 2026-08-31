/*
 * SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
 * SPDX-License-Identifier: Apache-2.0
 *
 * =============================================================================
 * The app name in the AquariusOS top bar
 * =============================================================================
 * WHAT YOU SEE
 *   One short piece of bold text, near the left of the top bar, between the
 *   AquariusOS logo and the File / Edit / View menus. It says the name of the
 *   app you are using right now — "Dolphin", "Firefox", "Steam" — and it
 *   changes the instant you click into a different window. When no window has
 *   focus (you clicked the desktop) it shows nothing and takes up no room.
 *
 *   That is the whole widget. It has no menu, no popup, no settings, and
 *   clicking it does nothing.
 *
 * WHY WE WROTE OUR OWN
 *   KDE ships no widget that puts the app name in a panel. The community has
 *   two that do more — antroids/application-title-bar and
 *   dhruv8sh/plasma6-window-title-applet — and both were read before this file
 *   was written. They are good, but they are window-title BARS: close/minimise/
 *   maximise buttons, per-app title rewriting rules, hover effects, several
 *   screens of settings. Adopting one meant carrying about fifty QML files, and
 *   hand-re-copying a pinned release every time it moved, in order to switch
 *   nearly all of it back off.
 *
 *   The deciding fact: they read the app name through exactly the same public
 *   KDE library this file uses, the same way — and so does a widget inside KDE
 *   itself (see below). There was no clever private trick we would be missing
 *   out on, so the "adopt it because it is more robust" argument had nothing
 *   left holding it up. The full comparison is in docs/app-name-widget.md.
 *
 * WHERE THE DATA COMES FROM
 *   `org.kde.taskmanager` — a normal published KDE library, not a `private`
 *   one, so it does not carry the "may vanish in a point release" risk the
 *   private Plasma imports do. KDE's own Task Manager imports it with this
 *   exact, unversioned line (plasma-desktop/applets/taskmanager/qml/main.qml,
 *   Plasma/6.7).
 *
 *   Better still: KDE's own "Window List" widget already asks it this exact
 *   question, in this exact shape — check `activeTask.valid`, then read the
 *   AppName role, then fall back. That is what refreshAppName() below does, and
 *   the source it was taken from is
 *     plasma-desktop/applets/window-list/main.qml   (Plasma/6.7, around line 357)
 *   The full quotation is in docs/app-name-widget.md, where a code block can
 *   hold it without fighting this comment.
 *
 *   So this is not a clever thing we invented. It is the boring, supported way,
 *   and it is maintained by KDE inside the desktop we ship.
 *
 * Design source: ../../../../../../../../branding/design-system/
 *                "AquariusOS Desktop Shell.html" — the bold "Files" label in
 *                the top bar. Tokens: ../../../../../../../../branding/tokens.md
 * Beginner-facing write-up, including how to test it: docs/app-name-widget.md
 * =============================================================================
 */

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    // -------------------------------------------------------------------------
    // The answer this widget exists to produce
    // -------------------------------------------------------------------------
    // Empty string means "no window has focus" — and an empty string is what
    // collapses the widget to nothing further down, so the top bar closes up
    // rather than leaving a gap.
    property string activeAppName: ""

    // -------------------------------------------------------------------------
    // No popup, no compact icon — this is a label and nothing else
    // -------------------------------------------------------------------------
    // A Plasma widget can draw itself two ways: "full" (the real thing) and
    // "compact" (a single icon it shrinks to when a panel is tight, which opens
    // the full thing in a popup when clicked). We never want the icon-and-popup
    // version, so we ask for the full one always. Without this line, a narrow
    // panel could silently turn our text into a mystery icon.
    //
    // Same line, same reason, as KDE's own Task Manager widget:
    //   plasma-desktop/applets/taskmanager/qml/main.qml (Plasma/6.7)
    preferredRepresentation: fullRepresentation

    // Plasma offers a hover tooltip built from the widget's name and
    // description. macOS shows nothing when you hover its app name, and neither
    // should we, so both texts are deliberately blank.
    toolTipMainText: ""
    toolTipSubText: ""

    // -------------------------------------------------------------------------
    // How much room it takes in the bar
    // -------------------------------------------------------------------------
    // The design puts 8px of clear space either side of the label
    // (branding/tokens.md, "Spacing": 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64).
    // Kirigami.Units.largeSpacing is 8 pixels, and it is a *unit* rather than a
    // hardcoded 8 so that it grows with the interface on a high-DPI screen
    // instead of getting hair-thin.
    readonly property int horizontalPadding: Kirigami.Units.largeSpacing

    // A ceiling, so that one badly-named app cannot shove the File/Edit/View
    // menus off the side of the screen. gridUnit is the height of one line of
    // the interface font, so this is "about twelve lines wide" and scales with
    // the font rather than being a pixel count that goes wrong on a 4K display.
    // Real app names are one or two words and never come near it.
    readonly property int maximumTextWidth: Kirigami.Units.gridUnit * 12

    // Exactly as wide as the text plus the padding — and exactly zero wide when
    // there is no text. Setting minimum, preferred and maximum to the same
    // number tells the panel "this is not negotiable", which stops the bar
    // reserving space for a label that is not there.
    Layout.minimumWidth: label.visible ? label.width + (horizontalPadding * 2) : 0
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: Layout.minimumWidth

    PlasmaComponents3.Label {
        id: label

        anchors.centerIn: parent
        visible: text.length > 0
        text: root.activeAppName

        // As wide as the words need, up to the ceiling set above. Past that the
        // text is cut short with an ellipsis rather than pushing the menus away.
        width: Math.min(implicitWidth, root.maximumTextWidth)
        elide: Text.ElideRight

        // TREAT THE NAME AS TEXT, NEVER AS MARKUP. A label normally guesses
        // whether what it has been given is plain text or HTML, and formats it
        // if it looks like HTML. The name here comes out of a window, and a
        // window can call itself anything at all — so guessing would let any
        // app put styled text, or a linked image, into our top bar. Say
        // "PlainText" and the guessing never happens. KDE's own clock sets this
        // for the same reason.
        textFormat: Text.PlainText

        // WHAT IS DELIBERATELY *NOT* SET HERE, and why
        //   font.family  — inheriting it is the whole point. The panel's font is
        //                  whatever the user chose in System Settings (Inter, on
        //                  a stock AquariusOS). Naming a family here would
        //                  ignore that choice and break for anyone who changes
        //                  it or needs a larger, more readable face.
        //   font.pointSize — the design draws the app name at the same size as
        //                  the File/Edit/View menus beside it. Same size means
        //                  "leave it alone".
        //   color        — PlasmaComponents3.Label already paints itself in the
        //                  theme's normal text colour, which on AquariusOS is
        //                  our AquariusDark foreground. Setting a colour here
        //                  would be the one thing in the bar that ignored a
        //                  light theme or a high-contrast scheme.
        //
        // Weight is the ONE thing we do change, and it is the whole look: the
        // design sets the app name to 600 while the menus stay at 400.
        // Font.DemiBold is Qt's name for 600.
        font.weight: Font.DemiBold
    }

    // -------------------------------------------------------------------------
    // The list of open windows, and which one has focus
    // -------------------------------------------------------------------------
    // TasksModel is KDE's own list of every open window — the same object that
    // powers the dock. We are using a tiny corner of it: its `activeTask`
    // property, which points at whichever window currently has focus.
    //
    // NO FILTERS ARE SET, on purpose. TasksModel can be told to ignore windows
    // on other screens, other virtual desktops or other activities. We want the
    // opposite: whatever window you are typing into is the app whose name
    // belongs in the bar, wherever that window happens to live. Every filter we
    // did switch on would be another way for the label to go mysteriously blank.
    TaskManager.TasksModel {
        id: tasksModel

        // Do not bundle several windows of the same app into one row. With
        // grouping on, a "row" can be a group rather than a window, which makes
        // "which window is focused" a more complicated question than it needs
        // to be. Off, every row is one window. (0 = GroupDisabled.)
        groupMode: TaskManager.TasksModel.GroupDisabled

        // WHEN TO RE-READ THE NAME. Three different things can change the
        // answer, so we listen for all three:
        //   activeTaskChanged  you clicked into a different window. This is the
        //                      normal case and KDE emits it whenever any
        //                      window's "is active" flag flips.
        //   dataChanged        the SAME window told us more about itself. This
        //                      matters at app start-up: a window can appear
        //                      before the system has worked out which
        //                      application it belongs to, so the name arrives a
        //                      moment after the window does. Without this line
        //                      the bar would sit blank until you clicked
        //                      somewhere else.
        //   countChanged       a window opened or closed.
        onActiveTaskChanged: root.refreshAppName()
        onDataChanged: root.refreshAppName()
        onCountChanged: root.refreshAppName()

        // And once at login, for the window that is already focused.
        Component.onCompleted: root.refreshAppName()
    }

    // -------------------------------------------------------------------------
    // Reading the name out of KDE's window list
    // -------------------------------------------------------------------------
    // THE IMPORTANT DISTINCTION, and the reason this function is not one line:
    // KDE offers two pieces of text for a window and they are NOT the same
    // thing.
    //
    //   display  is the window TITLE — "Documents — Dolphin", "tokens.md - VS
    //            Code". It changes every time you open a different file.
    //   AppName  is the APPLICATION name — "Dolphin", "Firefox". It comes from
    //            the app's own launcher entry and it does not move around.
    //
    // The design wants the second one. This was checked in KDE's source rather
    // than assumed: in libtaskmanager, the display role returns `window->title`
    // and the AppName role returns the application's name from its .desktop
    // file. Both citations are in docs/app-name-widget.md.
    //
    // THE FALLBACKS. AppName comes back empty when a window cannot be matched
    // to an installed app at all — some games, some hand-assembled AppImages,
    // the odd Wine program. Rather than leave a hole in the bar we try two more
    // things, in this order:
    //
    //   1. AppName   the app's proper name. Almost always this one.
    //   2. AppId     the short id the window gave itself, roughly
    //                "org.kde.dolphin" or "steam_app_570". Ugly, but short and
    //                stable, which is what this slot in the bar is for.
    //   3. display   the window title, as a last resort so that a focused
    //                window is never nameless.
    //
    // KDE's own Window List widget goes straight from 1 to 3. We put AppId in
    // between on purpose: a window title is long and changes every time you
    // open a different file, and the design wants a short bold name that stays
    // put. Rung 3 is still there underneath, so nothing is lost — the order is
    // simply "shortest honest answer first".
    function refreshAppName() {
        const active = tasksModel.activeTask;

        // No window has focus — you clicked the desktop, or the last window
        // just closed. Show nothing. (`activeTask` hands back a deliberately
        // invalid pointer in that case; KDE's own documentation for it says
        // "a null QModelIndex if no active task is found", and `.valid` is how
        // KDE's own code asks.)
        if (!active || !active.valid) {
            root.activeAppName = "";
            return;
        }

        const name = tasksModel.data(active, TaskManager.AbstractTasksModel.AppName);
        if (name) {
            root.activeAppName = name;
            return;
        }

        const id = tasksModel.data(active, TaskManager.AbstractTasksModel.AppId);
        if (id) {
            root.activeAppName = id;
            return;
        }

        // Qt.DisplayRole is the window title. (KDE's own Window List writes the
        // bare number 0 here instead, with a comment explaining that 0 means
        // the title. Same thing; the name is easier to read.)
        root.activeAppName = tasksModel.data(active, Qt.DisplayRole) || "";
    }
}
