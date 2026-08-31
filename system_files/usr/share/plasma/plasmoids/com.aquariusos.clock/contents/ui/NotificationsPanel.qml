/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// The notifications panel — what drops out of the clock
// =============================================================================
// Straight from the design: branding/design-system/AquariusOS Desktop Shell.html,
// the block with id="ovNotif" (also published on its own as "AquariusOS Shell
// Notifications.html", which just frames that same panel).
//
//     ┌─ 350px ──────────────────────────────────┐
//     │ Notifications                  Clear all │
//     │                                          │
//     │ ▢ Screenshot saved                   now │
//     │   Added to Pictures. Click to open.      │
//     │ ▢ You're up to date                  2 h │
//     │   Tonight's updates installed themselves │
//     │ ──────────────────────────────────────── │
//     │ 21:47                 [ Focus until      │
//     │ Saturday, August 30       morning ]      │
//     └──────────────────────────────────────────┘
//
// NO BACKGROUND IS PAINTED HERE, ON PURPOSE.
//   The popup's surface is drawn by the Aquarius Plasma Style
//   (system_files/usr/share/plasma/desktoptheme/aquarius/dialogs/background.svg)
//   and it is SOLID. The glass came out on 2026-08-30 — docs/plasma-style.md,
//   "Glass removed". Everything this file draws is opaque, or a tint painted on
//   top of something opaque. Do not add translucency here; it would be the one
//   see-through surface left on the desktop.
//
// NO CALENDAR, ON PURPOSE.
//   KDE's clock opens a calendar. This clock opens notifications, because that
//   is what the design draws and a calendar would push the panel to twice the
//   width. Anybody who misses it can right-click the top bar and add KDE's own
//   Digital Clock widget beside this one. Flagged for Royce in
//   docs/clock-notifications-widget.md.
//
// This file draws; it does not know how notifications work. Everything comes
// from `feed`, which is NotificationsSource.qml.
// =============================================================================
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: panel

    // --- set by main.qml -----------------------------------------------------
    property date now: new Date()
    property var feed: null

    // Read back by main.qml for the hover tooltip.
    readonly property bool focusActive: panel.feed ? panel.feed.focusActive : false
    readonly property int unreadCount: panel.feed ? panel.feed.unreadCount : 0

    // --- measurements from the design ---------------------------------------
    // The design's panel is 350px wide with 16px of padding.
    //
    // Both are written as multiples of Kirigami's grid unit rather than as flat
    // pixel counts, which is the same rule the desktop layout script follows and
    // for the same reason: gridUnit is the height of one line of interface text,
    // so a person who turns their font up gets a panel that grows with it
    // instead of a cramped one. On a standard screen with our shipped 10pt Inter
    // a grid unit is around 18px, which puts these at roughly 350 and 18 — the
    // design's numbers, near enough that nobody could pick the difference.
    readonly property int designWidth: Math.round(Kirigami.Units.gridUnit * 19.5)
    readonly property int designPadding: Kirigami.Units.largeSpacing
    readonly property int rowGap: Kirigami.Units.smallSpacing * 2

    // How tall the popup may get before the list starts scrolling.
    readonly property int maximumListHeight: Kirigami.Units.gridUnit * 20

    // The popup is exactly as wide as the design says, and exactly as tall as
    // its contents. Note that `stack` is anchored to three sides rather than
    // filled: the panel's height is worked out FROM the column, so letting the
    // column's height come back from the panel would be a circle.
    Layout.minimumWidth: panel.designWidth
    Layout.preferredWidth: panel.designWidth
    Layout.maximumWidth: panel.designWidth
    Layout.minimumHeight: panel.implicitHeight
    Layout.preferredHeight: panel.implicitHeight
    Layout.maximumHeight: panel.implicitHeight

    implicitWidth: panel.designWidth
    implicitHeight: stack.implicitHeight + panel.designPadding * 2

    ColumnLayout {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: panel.designPadding
        spacing: 0

        // ---------------------------------------------------------------------
        // Header: the word, and the way out.
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Notifications")
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
            }

            Item {
                Layout.fillWidth: true
            }

            // "Clear all" is only shown when there is something it could clear.
            // KDE's own clear-all is shown under exactly the same condition, and
            // for the same reason: the library can only clear the history, so
            // offering the button when the history is empty would be a button
            // that does nothing.
            PlasmaComponents3.Label {
                id: clearAll
                text: i18n("Clear all")
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                color: clearHover.hovered ? Kirigami.Theme.textColor
                                          : Kirigami.Theme.disabledTextColor
                visible: panel.feed !== null && panel.feed.canClear

                HoverHandler {
                    id: clearHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: panel.feed.clearAll()
                }

                Accessible.role: Accessible.Button
                Accessible.name: clearAll.text
                Accessible.onPressAction: panel.feed.clearAll()
            }
        }

        Item {
            Layout.preferredHeight: panel.rowGap + Kirigami.Units.smallSpacing
        }

        // ---------------------------------------------------------------------
        // The list.
        // ---------------------------------------------------------------------
        ListView {
            id: list

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, panel.maximumListHeight)
            visible: count > 0

            model: panel.feed ? panel.feed.model : null
            spacing: panel.rowGap
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true

            delegate: NotificationRow {
                id: notificationDelegate

                // These arrive from the model. The names are the role names of
                // NotificationManager.Notifications: KDE builds them from the
                // Roles enum by lower-casing the first letter and dropping the
                // "Role" suffix (libnotificationmanager/utils.cpp, roleNames()),
                // so SummaryRole is `summary`, BodyRole is `body`, and so on.
                required property int index
                required property string summary
                required property string body
                required property string applicationName
                required property string iconName
                required property string applicationIconName
                required property var created
                required property var updated
                required property bool closable

                width: ListView.view.width

                // The summary is the headline. A few applications send none, in
                // which case their own name is the most useful thing to show.
                title: summary.length > 0 ? summary : applicationName
                bodyText: body

                // First the notification's own icon, then the sending
                // application's, then a neutral stand-in. Picture attachments —
                // a screenshot thumbnail, an album cover — arrive on a different
                // role and are not drawn yet; see docs/clock-notifications-widget.md.
                iconSource: {
                    if (notificationDelegate.iconName.length > 0) {
                        return notificationDelegate.iconName;
                    }
                    if (notificationDelegate.applicationIconName.length > 0) {
                        return notificationDelegate.applicationIconName;
                    }
                    return "dialog-information";
                }

                // A notification that has been edited in place (a download that
                // keeps updating, say) carries an `updated` time; the rest only
                // have `created`. KDE's applet chooses between them the same way.
                time: isNaN(notificationDelegate.updated) ? notificationDelegate.created
                                                          : notificationDelegate.updated
                reference: panel.now

                dismissable: notificationDelegate.closable
                activatable: panel.feed.hasDefaultActionAt(notificationDelegate.index)

                onActivated: panel.feed.activateAt(notificationDelegate.index)
                onCloseRequested: panel.feed.closeAt(notificationDelegate.index)
            }
        }

        // ---------------------------------------------------------------------
        // Nothing to show.
        // ---------------------------------------------------------------------
        // Two different nothings, and they deserve two different sentences. An
        // empty list is good news. A notification service that is not running is
        // not — telling somebody they are "all caught up" when the machine is
        // simply not listening would be a lie.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit
            Layout.bottomMargin: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing
            visible: list.count === 0

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                width: Kirigami.Units.iconSizes.medium
                height: width
                source: (panel.feed && panel.feed.serviceAvailable) ? "checkmark-symbolic"
                                                                    : "dialog-warning-symbolic"
                color: Kirigami.Theme.disabledTextColor
                isMask: true
                opacity: 0.7
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: Kirigami.Theme.disabledTextColor
                text: (panel.feed && panel.feed.serviceAvailable)
                        ? i18n("You're all caught up.")
                        : i18n("The notification service isn't running.")
            }
        }

        // ---------------------------------------------------------------------
        // Footer: the big clock, and Focus.
        // ---------------------------------------------------------------------
        Item {
            Layout.preferredHeight: Math.round(Kirigami.Units.largeSpacing * 0.8)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            // The design's `border-1`: the light text colour at 8%. Written
            // against the theme so it inverts on a light colour scheme.
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b,
                           0.08)
        }

        Item {
            Layout.preferredHeight: panel.rowGap + Kirigami.Units.smallSpacing
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                spacing: 0

                PlasmaComponents3.Label {
                    text: Qt.formatTime(panel.now, panel.timeFormat)
                    textFormat: Text.PlainText
                    // The design's display face. Sora ships with the image at
                    // system_files/usr/share/fonts/sora-fonts/ — see
                    // branding/tokens.md, "Typography". If it were ever missing,
                    // Qt quietly falls back to the interface font and the panel
                    // still reads correctly.
                    font.family: "Sora"
                    font.pointSize: Math.round(Kirigami.Theme.defaultFont.pointSize * 1.5)
                    font.weight: Font.DemiBold
                }

                PlasmaComponents3.Label {
                    text: Qt.locale().toString(panel.now, "dddd, MMMM d")
                    textFormat: Text.PlainText
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    opacity: 0.75
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // --- the Focus pill ----------------------------------------------
            // Tapping it holds every notification back until the next 06:00.
            // Tapping it again lets them through. The state lives in KDE's own
            // notification settings, which means System Settings and this button
            // are two views of one switch — turn Focus on here and KDE's tray
            // applet shows "Do not disturb" on too.
            Rectangle {
                id: focusPill

                readonly property bool on: panel.feed !== null && panel.feed.focusActive

                Layout.preferredWidth: focusLabel.implicitWidth + Kirigami.Units.gridUnit
                Layout.preferredHeight: focusLabel.implicitHeight + Kirigami.Units.largeSpacing
                radius: 12

                // Design: white at 7% at rest, the accent at 16% when on
                // (`.qs-toggle` and `.qs-toggle.on`).
                color: focusPill.on
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                              Kirigami.Theme.highlightColor.g,
                              Kirigami.Theme.highlightColor.b,
                              0.16)
                    : Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b,
                              focusHover.hovered ? 0.12 : 0.07)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b,
                                      0.10)

                Behavior on color {
                    ColorAnimation { duration: Kirigami.Units.shortDuration }
                }

                PlasmaComponents3.Label {
                    id: focusLabel
                    anchors.centerIn: parent
                    text: i18n("Focus until morning")
                    textFormat: Text.PlainText
                    font.weight: Font.Medium
                    color: focusPill.on ? Kirigami.Theme.textColor
                                        : Kirigami.Theme.disabledTextColor
                }

                HoverHandler {
                    id: focusHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: panel.feed.toggleFocus()
                }

                Accessible.role: Accessible.Button
                Accessible.name: focusLabel.text
                Accessible.checkable: true
                Accessible.checked: focusPill.on
                Accessible.description: {
                    if (!focusPill.on) {
                        return i18n("Hold notifications back until 6 in the morning");
                    }
                    const endsAt = panel.feed.focusEndsAt;
                    if (isNaN(endsAt.getTime())) {
                        return i18n("Focus is on. Tap to let notifications through again.");
                    }
                    return i18n("Focus is on until %1. Tap to let notifications through again.",
                                Qt.formatTime(endsAt, panel.timeFormat));
                }
                Accessible.onPressAction: panel.feed.toggleFocus()
            }
        }
    }

    // -------------------------------------------------------------------------
    // 12-hour or 24-hour, exactly as the bar clock decides it.
    // -------------------------------------------------------------------------
    // The same locale-derived format CompactClock.qml works out, repeated here
    // rather than shared through a third file: it is six lines, and the two
    // clocks disagreeing would be the kind of bug nobody notices for months.
    // If this ever grows, move it into a singleton.
    readonly property string timeFormat: {
        const short = Qt.locale().timeFormat(Locale.ShortFormat);
        const match = /(hh?)(.+?)(mm)/i.exec(short);
        if (!match) {
            return short;
        }
        let result = match[1].toLowerCase() + match[2] + match[3];
        if (short.toLowerCase().indexOf("ap") !== -1) {
            result += " AP";
        }
        return result;
    }
}
