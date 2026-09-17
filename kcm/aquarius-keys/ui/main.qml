/*
    "Mac or Windows" — what the AquariusOS page in System Settings looks like.

    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later

    ---------------------------------------------------------------------------
    TWO CARDS, ONE SENTENCE EACH, NO APPLY BUTTON
    ---------------------------------------------------------------------------
    The wording here matches the two cards in the AquariusOS Welcome window on
    purpose. Somebody meeting this choice for the second time should read the
    same sentence, not a differently worded version of it that makes them
    wonder whether it is the same setting.

    There is no Apply button because there is nothing to apply: picking a card
    runs `aq keys ...` there and then, exactly as pressing Continue in the
    Welcome window does. That is why the page never sets needsSave.

    Everything is stock Breeze — Kirigami's own form layout and radio buttons.
    AquariusOS does not theme KDE's settings app.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: root

    // The size the page opens at when it is opened on its own with kcmshell6.
    // Inside System Settings the app decides, and this is ignored.
    implicitWidth: Kirigami.Units.gridUnit * 32
    implicitHeight: Kirigami.Units.gridUnit * 26

    // No Apply, no Reset: see the note at the top of this file.
    KCMUtils.ConfigModule.buttons: KCMUtils.ConfigModule.NoAdditionalButton

    // Read the setting again whenever the page comes back into view. It can be
    // changed from a terminal or from the other desktop while this window sits
    // open, and a settings page showing the wrong answer is worse than none.
    onVisibleChanged: if (visible) kcm.refresh()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("AquariusOS can type like a Mac or like Windows. This one answer sets both the keyboard shortcuts and which side of a window the close, minimise and maximise buttons sit on — one choice, not two questions.")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.RadioButton {
                Kirigami.FormData.label: i18n("Keyboard and windows:")
                text: i18n("Mac")
                checked: kcm.mode === "mac"
                enabled: !kcm.busy
                onToggled: if (checked) kcm.choose("mac")
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: i18n("Copy is ⌘C · Quit is ⌘Q · Search is ⌘Space. The key beside the space bar is Command. Window buttons on the left.")
            }

            QQC2.RadioButton {
                text: i18n("Windows")
                checked: kcm.mode === "windows"
                enabled: !kcm.busy
                onToggled: if (checked) kcm.choose("windows")
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: i18n("Copy is Ctrl+C. The normal Linux and Windows shortcuts; nothing about your keyboard is changed at all. Window buttons on the right.")
            }
        }

        // Shown only while `aq keys ...` is still working. It is usually gone
        // before anybody reads it, and that is fine — its job is to explain the
        // one second where the radio buttons will not respond.
        QQC2.Label {
            Layout.fillWidth: true
            visible: kcm.busy
            wrapMode: Text.WordWrap
            text: i18n("Changing it now…")
        }

        // Shown only when something went wrong. It carries the exact words the
        // command printed, because a made-up summary of a failure helps nobody.
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.errorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.errorMessage
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("It takes effect straight away — you do not need to log out. The same switch is in the terminal as “aq keys mac” or “aq keys windows”, and on the GNOME desktop it is in the menu at the top-right of the screen.")
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
