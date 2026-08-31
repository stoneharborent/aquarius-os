/*
 * AquariusOS Quick Settings — the panel itself
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This is what drops down when you click the Quick Settings icon in the top
 * bar: a 2x2 grid of toggles, two sliders, and a battery line with a link to
 * the full Settings app.
 *
 * Design source: branding/design-system/"AquariusOS Shell Quick Settings.html",
 * which is a one-line file that opens "AquariusOS Desktop Shell.html" at its
 * `ovTray` overlay — that overlay is where the real markup lives.
 *
 * ============================================================================
 * WHY THIS PANEL DRAWS NO BACKGROUND OF ITS OWN
 * ============================================================================
 * The design's CSS gives the panel a background of rgba(13,15,24,.76) with a
 * blur behind it. Do NOT copy that here, and do not add any translucency.
 *
 * AquariusOS surfaces are solid as of 2026-08-30. The blur that was supposed to
 * sit behind the see-through parts never rendered on this Plasma, so what a
 * person actually saw through a popup was the wallpaper and other windows'
 * text, straight through the words they were trying to read. The transparency
 * came out and every surface went opaque. The full story is in
 * docs/plasma-style.md, "Glass removed — 2026-08-30", and the investigation is
 * docs/blur-known-issue.md.
 *
 * The upshot for this file: the popup's background, its 16px corners, its
 * hairline border and its shadow are all drawn by the Plasma style, from
 * system_files/usr/share/plasma/desktoptheme/aquarius/dialogs/background.svg —
 * the same one drawing of a popup that every tray popup, the calendar and the
 * search box share. This file draws only its contents. Painting a rectangle
 * here would put a second surface on top of that one and the two would not
 * match.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: panel

    readonly property real aqScale: Kirigami.Units.gridUnit / 18
    function dp(px) { return Math.round(px * aqScale) }

    // -------------------------------------------------------------------------
    // SIZE
    // -------------------------------------------------------------------------
    // The design says 330px wide. Pinning minimum, preferred AND maximum to the
    // same number is what actually holds it there — set only `preferred` and
    // Plasma will happily stretch the popup to fit its contents.
    //
    // ⚠️ This width is only honoured because this widget goes in the panel on
    // its OWN, not inside the system tray. Applets hosted by the system tray
    // get a popup whose size is fixed by the tray, and a `preferredWidth` from
    // the applet is ignored. That is the whole reason the layout script adds
    // this widget beside the tray rather than into it — see the comment there.
    readonly property int designWidth: dp(330)

    Layout.minimumWidth: designWidth
    Layout.preferredWidth: designWidth
    Layout.maximumWidth: designWidth

    implicitWidth: designWidth
    implicitHeight: content.implicitHeight + (contentPadding * 2)

    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    // design: padding:16px on the panel.
    readonly property int contentPadding: dp(16)

    // Which file fills the fourth square in the grid. Worked out at runtime, not
    // when the image is built — see AqPlatform.qml for the reasoning and the
    // test it uses.
    AqPlatform {
        id: platform
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: panel.contentPadding
        spacing: 0

        // ---------------------------------------------------------------------
        // 1. THE FOUR TOGGLES
        // ---------------------------------------------------------------------
        // design: display:grid; grid-template-columns:1fr 1fr; gap:10px
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: panel.dp(10)
            rowSpacing: panel.dp(10)

            AqTileSlot {
                Layout.fillWidth: true
                tileSource: "TileWifi.qml"
                fallbackTitle: i18n("Wi-Fi")
                fallbackIconName: "network-wireless-off"
            }

            AqTileSlot {
                Layout.fillWidth: true
                tileSource: "TileBluetooth.qml"
                fallbackTitle: i18n("Bluetooth")
                fallbackIconName: "network-bluetooth-inactive-symbolic"
            }

            AqTileSlot {
                Layout.fillWidth: true
                tileSource: "TileFocus.qml"
                fallbackTitle: i18n("Focus")
                fallbackIconName: "notification-inactive-symbolic"
            }

            // The adaptive one. On a handheld this is Game Mode; on a desktop it
            // is the power profile. `platform` decides which, at runtime.
            AqTileSlot {
                Layout.fillWidth: true
                tileSource: platform.fourthTileSource
                fallbackTitle: platform.fourthTileFallbackTitle
                fallbackIconName: platform.fourthTileFallbackIcon
            }
        }

        // ---------------------------------------------------------------------
        // 2. THE SLIDERS
        // ---------------------------------------------------------------------
        // design: margin-top:16px, then the two rows 14px apart.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: panel.dp(16)
            spacing: panel.dp(14)

            // Plain Loaders, not AqTileSlots. A tile that fails has to leave a
            // placeholder behind so the 2x2 grid keeps its shape; a slider that
            // fails can simply not be there, and the panel just gets shorter.
            // Nothing is misaligned by its absence.
            Loader {
                Layout.fillWidth: true
                source: "SliderSound.qml"
            }

            Loader {
                Layout.fillWidth: true
                source: "SliderBrightness.qml"
            }
        }

        // ---------------------------------------------------------------------
        // 3. THE BATTERY LINE AND THE WAY OUT
        // ---------------------------------------------------------------------
        // design: margin-top:14px; padding-top:12px; border-top:1px solid var(--border-1)
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: panel.dp(14)
            height: 1

            // design: border-1 is rgba(237,239,247,.08) — the text colour at 8%.
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.08)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: panel.dp(12)
            spacing: panel.dp(8)

            // Hides itself on a machine with no battery, and the link below
            // slides left to take the space.
            Loader {
                Layout.fillWidth: true
                source: "BatteryLine.qml"
            }

            // design: <a href="…">All settings</a>, 11.5px, in the accent colour.
            Text {
                id: allSettings

                text: i18n("All settings")
                color: settingsMouse.containsMouse
                            ? Kirigami.Theme.linkColor.lighter(115)
                            : Kirigami.Theme.linkColor
                font.family: Kirigami.Theme.defaultFont.family
                font.pixelSize: panel.dp(11.5)
                font.underline: settingsMouse.containsMouse

                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: platform.openSystemSettings()
                }
            }
        }
    }
}
