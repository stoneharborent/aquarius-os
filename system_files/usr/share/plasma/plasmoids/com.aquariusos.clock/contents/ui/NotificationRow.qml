/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// One notification, as one row in the panel
// =============================================================================
// The design (branding/design-system/AquariusOS Desktop Shell.html, class
// "notif") is a soft rounded slab holding four things:
//
//     ┌──────┐  Screenshot saved                            now
//     │ icon │  Added to Pictures. Click to open.
//     └──────┘
//
//   icon chip   34x34, 9px corners, a quiet box with the app's icon in it
//   title       the notification's one-line summary, in the bright text colour
//   body        the detail, in the quieter text colour, up to three lines
//   age         "now", "5 m", "2 h", "3 d" — in the monospace face, quietest
//
// This file knows nothing about KDE's notification library. Everything it draws
// arrives as a plain property, set by the list in NotificationsPanel.qml.
//
// NOTHING HERE IS SEE-THROUGH. The row tint and the icon chip are washes of the
// text colour painted on top of an opaque popup — not window transparency. The
// popups stopped being glass on 2026-08-30; see docs/plasma-style.md, "Glass
// removed".
// =============================================================================
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: row

    // --- what to draw (set by the list) -------------------------------------
    property string title: ""
    property string bodyText: ""
    property string iconSource: ""

    // When the notification arrived, and what "now" is. Both are set by the
    // list; `reference` ticks once a minute, which is what re-runs the age sum
    // at the bottom of this file, so a row's age creeps up on its own while the
    // panel is open.
    property date time: new Date()
    property date reference: new Date()

    // --- what to do ---------------------------------------------------------
    signal activated()
    signal closeRequested()
    property bool activatable: false
    property bool dismissable: false

    // --- measurements from the design ---------------------------------------
    readonly property int slabRadius: 12
    readonly property int slabPadding: 12
    readonly property int chipSize: 34
    readonly property int chipRadius: 9

    implicitHeight: content.implicitHeight + row.slabPadding * 2

    // The slab. Design: rgba(237,239,247,.06) — 6% of the light text colour.
    // Written against the theme's own text colour so it inverts correctly if
    // somebody runs a light colour scheme.
    Rectangle {
        anchors.fill: parent
        radius: row.slabRadius
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b,
                       hover.hovered ? 0.10 : 0.06)

        Behavior on color {
            ColorAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: row.activatable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: row.activatable
        onTapped: row.activated()
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: row.slabPadding
        spacing: row.slabPadding

        // The icon chip.
        Rectangle {
            Layout.preferredWidth: row.chipSize
            Layout.preferredHeight: row.chipSize
            Layout.alignment: Qt.AlignTop
            radius: row.chipRadius
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b,
                           0.08)

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.small
                height: width
                source: row.iconSource
                // The design draws these icons in the accent blue. `highlightColor`
                // is the colour scheme's accent, which on AquariusOS is starlight
                // (#8AB4FF) — see branding/tokens.md, "Where these tokens actually
                // land in the OS".
                color: Kirigami.Theme.highlightColor
                isMask: true
            }
        }

        // Title and body.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.title
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.bodyText
                // Notification bodies may carry a little markup (bold, links).
                // StyledText is the narrow subset Qt renders without becoming a
                // web browser, which is the right amount of trust to extend to
                // text that arrived from any application on the machine.
                textFormat: Text.StyledText
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 3
                visible: text.length > 0
            }
        }

        // The age, or — while the pointer is over the row — a close button in
        // its place.
        //
        // WHY A HOVER-REVEALED CLOSE BUTTON, WHEN THE DESIGN DRAWS NONE
        //   "Clear all" can only clear the HISTORY (see NotificationsSource.qml).
        //   Without a per-row control there would be no way at all to dismiss a
        //   notification that is still live. Hiding the button until the pointer
        //   arrives means the panel at rest looks exactly like the mock.
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Math.max(ageLabel.implicitWidth, closeButton.width)
            Layout.preferredHeight: Math.max(ageLabel.implicitHeight, closeButton.height)

            PlasmaComponents3.Label {
                id: ageLabel
                anchors.right: parent.right
                text: row.ageText
                textFormat: Text.PlainText
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.75
                font.family: Kirigami.Theme.fixedWidthFont.family
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                visible: !closeButton.visible
            }

            PlasmaComponents3.ToolButton {
                id: closeButton
                anchors.right: parent.right
                anchors.top: parent.top
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                padding: 0
                icon.name: "window-close-symbolic"
                // No `text` on purpose — a label would push the row wider. The
                // name a screen reader announces is set below instead.
                Accessible.name: i18n("Dismiss this notification")
                visible: row.dismissable && hover.hovered
                onClicked: row.closeRequested()
            }
        }
    }

    // --- "now", "5 m", "2 h", "3 d" -----------------------------------------
    // Written here rather than borrowed from KCoreAddons.Format, which produces
    // sentences ("2 hours ago"). The design wants the short, mono, glanceable
    // form, and the popup is 350px wide.
    readonly property string ageText: {
        const seconds = Math.max(0, Math.floor((row.reference.getTime() - row.time.getTime()) / 1000));
        if (seconds < 60) {
            return i18nc("A notification that arrived moments ago", "now");
        }
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60) {
            return i18nc("Age of a notification, in minutes", "%1 m", minutes);
        }
        const hours = Math.floor(minutes / 60);
        if (hours < 24) {
            return i18nc("Age of a notification, in hours", "%1 h", hours);
        }
        return i18nc("Age of a notification, in days", "%1 d", Math.floor(hours / 24));
    }
}
