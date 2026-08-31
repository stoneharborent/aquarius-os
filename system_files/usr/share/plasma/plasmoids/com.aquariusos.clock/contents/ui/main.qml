/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// AquariusOS clock + notifications
// =============================================================================
// This is the thing at the right-hand end of the top bar. It does two jobs:
//
//   1. IT IS THE CLOCK.  "Sat Aug 30  21:47" — date first, then the time, on one
//      line, with the date drawn in the dimmer text colour. That last part is
//      the whole reason this widget exists: KDE's own clock paints the date and
//      the time in the SAME colour and offers no setting for it, which is
//      written down as honest gap #3 in ../docs/v2-shell-tier2-research.md. A
//      widget can do what a setting cannot, so here we are.
//
//   2. CLICK IT AND YOU GET THE NOTIFICATIONS PANEL.  Not a calendar — the
//      designed 350px notifications panel, with a big clock and a "Focus until
//      morning" button along the bottom. The calendar we deliberately did not
//      ship is discussed in docs/clock-notifications-widget.md.
//
// WHERE THE FILES ARE
//   main.qml                the wiring (this file)
//   CompactClock.qml        what you see in the bar
//   NotificationsSource.qml the data — the ONLY file that talks to KDE's
//                           notification library
//   NotificationsPanel.qml  the popup's looks. Pure drawing; it asks the source
//                           above for everything.
//   NotificationRow.qml     one line in that popup
//   PanelUnavailable.qml    a polite message shown instead, if the library is
//                           missing
//   AlignedClock.qml        the good clock tick (needs KDE's clock library)
//   TickingClock.qml        a plain timer, used if the good one is missing
//
// WHY TWO OF THOSE ARE LOADED INDIRECTLY (the "fail-soft" rule)
//   NotificationsSource.qml and AlignedClock.qml each open with an `import` of a
//   KDE library that ships with Plasma today but is not promised forever — a
//   Bazzite rebase could in principle move or drop one. In QML, an import that
//   cannot be resolved kills the WHOLE file it is written in. So each risky
//   import is quarantined in its own small file and pulled in through a Loader.
//   A Loader that fails just reports an error; it does not take the widget down
//   with it. Worst case is "the clock still ticks, the popup says the service is
//   unavailable" instead of a blank gap in the top bar. Plasma itself uses this
//   trick — see the optional PulseAudio.qml Loader in
//   plasma-workspace/applets/notifications/global/Globals.qml.
//
//   The build also checks, inside the finished image, that both libraries really
//   are installed: build_files/shell-widgets.sh. If a rebase drops one, the
//   image build fails loudly rather than a user finding out.
// =============================================================================
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // -------------------------------------------------------------------------
    // The current time, shared by the bar label and the popup's big clock.
    // -------------------------------------------------------------------------
    // Whichever clock source loaded, it exposes one thing: `dateTime`. Before
    // the Loader has finished (a fraction of a second at login) we read the
    // clock once ourselves, so nothing is ever blank.
    readonly property date now: clockSource.item ? clockSource.item.dateTime : new Date()

    // The notification data, or null if KDE's notification library is missing.
    readonly property var notifications: notificationSource.item
    readonly property bool notificationsAvailable: notificationSource.status === Loader.Ready

    Loader {
        id: clockSource

        // Try the shared, minute-aligned clock KDE's own digital clock uses.
        source: "AlignedClock.qml"

        onStatusChanged: {
            if (status === Loader.Error && String(source).endsWith("AlignedClock.qml")) {
                console.warn("com.aquariusos.clock: org.kde.plasma.clock is not available on this"
                           + " Plasma; falling back to a plain minute timer.");
                source = "TickingClock.qml";
            }
        }
    }

    Loader {
        id: notificationSource

        source: "NotificationsSource.qml"

        // The source needs the ticking clock too: it is what makes "Focus until
        // morning" switch itself off, visibly, the minute 06:00 goes past.
        onLoaded: item.now = Qt.binding(() => root.now)

        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("com.aquariusos.clock: org.kde.notificationmanager is not available"
                           + " on this Plasma. The clock still works; the popup will say so.");
            }
        }
    }

    // -------------------------------------------------------------------------
    // What you see in the bar.
    // -------------------------------------------------------------------------
    // preferredRepresentation says "even if there is loads of room, stay small
    // and open a popup when clicked" — the same line KDE's digital clock uses
    // (plasma-workspace/applets/digital-clock/main.qml). Without it, dropping
    // this widget on the desktop would show the popup's contents inline.
    preferredRepresentation: compactRepresentation

    compactRepresentation: CompactClock {
        now: root.now
        appletExpanded: root.expanded
        onToggleRequested: wasOpen => root.expanded = !wasOpen
    }

    // -------------------------------------------------------------------------
    // The popup.
    // -------------------------------------------------------------------------
    fullRepresentation: Loader {
        id: popup

        source: root.notificationsAvailable ? "NotificationsPanel.qml" : "PanelUnavailable.qml"

        // A Loader with no size of its own takes the size of what it loaded, so
        // these forward the panel's own idea of how big it should be out to the
        // popup window. Without them the popup would be free to stretch, and the
        // design's 350px is not a suggestion.
        Layout.minimumWidth: popup.implicitWidth
        Layout.preferredWidth: popup.implicitWidth
        Layout.maximumWidth: popup.implicitWidth
        Layout.minimumHeight: popup.implicitHeight
        Layout.preferredHeight: popup.implicitHeight

        // Both possible children have a `now` property, so this is safe either
        // way. Qt.binding keeps it live rather than freezing the time the popup
        // was first opened.
        onLoaded: {
            item.now = Qt.binding(() => root.now);
            if (root.notificationsAvailable) {
                item.feed = root.notifications;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Housekeeping when the popup opens and closes.
    // -------------------------------------------------------------------------
    // Opening the panel is the moment the user has SEEN what is in it, so
    // everything in the list stops counting as unread; closing it moves the
    // "everything before this is old news" mark to now. KDE's own applet does
    // the same two things in the same two places
    // (plasma-workspace/applets/notifications/main.qml, onExpandedChanged, and
    // FullRepresentation.qml's Connections block).
    onExpandedChanged: {
        if (!root.notifications) {
            return;
        }
        if (root.expanded) {
            root.notifications.markEverythingRead();
        } else {
            root.notifications.resetLastRead();
        }
    }

    // -------------------------------------------------------------------------
    // The hover tooltip.
    // -------------------------------------------------------------------------
    // The bar shows a short date; the tooltip spells it out and says whether
    // anything is waiting. Deliberately small — the popup is the real UI.
    toolTipMainText: Qt.locale().toString(root.now, Locale.LongFormat)
    toolTipSubText: {
        if (!root.notificationsAvailable) {
            return i18n("The notification service is not available");
        }
        if (root.notifications.focusActive) {
            return i18n("Focus is on — notifications are being held back");
        }
        const unread = root.notifications.unreadCount;
        if (unread > 0) {
            return i18np("%1 unread notification", "%1 unread notifications", unread);
        }
        return i18n("No new notifications");
    }
}
