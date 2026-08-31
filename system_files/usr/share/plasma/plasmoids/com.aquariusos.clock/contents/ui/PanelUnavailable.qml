/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// What the popup says when there is no notification library to talk to
// =============================================================================
// You should never see this. It appears only if `org.kde.notificationmanager`
// is not installed — which would mean a Plasma update moved or dropped it. The
// image build checks for it (build_files/shell-widgets.sh), so that ought to be
// caught long before an image ships.
//
// It exists anyway because the alternative is worse. Without it, the missing
// import would take the whole widget down and the top bar would have a hole in
// it where the clock used to be, with nothing on screen to explain why. This
// way the clock keeps working and the popup tells the truth.
//
// It carries `now` and `feed` properties it never uses, only so main.qml can set
// them on whichever of the two panels loaded without having to check first.
// =============================================================================
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: unavailable

    property date now: new Date()
    property var feed: null

    readonly property int designWidth: Math.round(Kirigami.Units.gridUnit * 19.5)
    readonly property int designPadding: Kirigami.Units.largeSpacing

    implicitWidth: unavailable.designWidth
    implicitHeight: message.implicitHeight + unavailable.designPadding * 2

    Layout.minimumWidth: unavailable.designWidth
    Layout.preferredWidth: unavailable.designWidth
    Layout.maximumWidth: unavailable.designWidth
    Layout.preferredHeight: unavailable.implicitHeight

    ColumnLayout {
        id: message
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: unavailable.designPadding
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            width: Kirigami.Units.iconSizes.medium
            height: width
            source: "dialog-warning-symbolic"
            color: Kirigami.Theme.disabledTextColor
            isMask: true
            opacity: 0.7
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            font.weight: Font.DemiBold
            text: i18n("Notifications are unavailable")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("This version of the desktop does not provide the notification service"
                     + " this panel is built on. The clock is unaffected.")
        }
    }
}
