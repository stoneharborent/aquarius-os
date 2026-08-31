/*
 * AquariusOS Quick Settings — one toggle tile
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHAT THIS IS
 *   One of the four squares in the 2x2 grid at the top of the Quick Settings
 *   panel: a round icon chip, a bold title, and a small grey subtitle under it.
 *   Wi-Fi, Bluetooth, Focus and the fourth (Game Mode / Performance) tile are
 *   all THIS file with different words and a different icon plugged in.
 *
 *   It knows nothing about Wi-Fi or Bluetooth. It draws a tile and reports
 *   clicks. Everything that actually talks to the system lives in the separate
 *   Tile*.qml files, and each of those is loaded behind a safety net — see the
 *   long comment in FullRepresentation.qml.
 *
 * WHERE THE NUMBERS COME FROM
 *   The V2 design, branding/design-system/"AquariusOS Desktop Shell.html", the
 *   `.qs-toggle` rules. They are written here as the same numbers the design
 *   uses, so the two can be compared line by line. `aqScale` (below) is what
 *   keeps them from being literally hardcoded.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: tile

    // --- what the caller sets ------------------------------------------------

    // The bold line. "Wi-Fi", "Bluetooth", "Focus", "Game Mode".
    property string title: ""

    // The small line underneath: the network name, how many devices, "Off".
    property string subtitle: ""

    // A name from the icon theme, e.g. "network-wireless-symbolic". Icon THEME
    // names, not image files, so the tile follows whatever icon set the user
    // has chosen and can never point at a missing file.
    property string iconName: ""

    // Is the thing switched on? This is the only input to the "lit up" look.
    property bool active: false

    // Set false when the hardware or the software behind this tile is missing
    // (no Bluetooth adapter in the machine, for instance). The tile still draws
    // — so the grid keeps its shape — but it is dimmed and ignores clicks.
    property bool available: true

    // Emitted on click. The caller decides what a click means.
    signal toggled()

    // -------------------------------------------------------------------------
    // SIZING — why there is a multiplier instead of plain numbers
    // -------------------------------------------------------------------------
    // The design is drawn at one size: 12px text, a 32px icon chip, 12px
    // corners. Writing those numbers straight into the file would be fine on a
    // default machine and wrong for anybody who has turned their interface font
    // up — the text would grow, the chip and the padding would not, and the
    // labels would spill out of the tile.
    //
    // `Kirigami.Units.gridUnit` is the height of one line of the interface font.
    // With the default font it measures 18. So dividing by 18 gives 1.0 on a
    // default machine and, say, 1.33 for somebody running a bigger font — and
    // every number below scales by exactly as much as the text does.
    //
    // (This is the same reasoning, and the same trick, as the panel heights in
    // the desktop layout script. See its "A NOTE ON gridUnit" comment.)
    readonly property real aqScale: Kirigami.Units.gridUnit / 18

    // Round to whole pixels. Half-pixel edges look soft and slightly grubby.
    function dp(px) { return Math.round(px * aqScale) }

    implicitHeight: dp(52)          // 10px padding + 32px chip + 10px padding
    radius: dp(12)                  // design: border-radius:12px

    // -------------------------------------------------------------------------
    // COLOUR — taken from the user's colour scheme, not from fixed hex codes
    // -------------------------------------------------------------------------
    // The design names exact colours: the active tile is rgba(138,180,255,.16),
    // which is the `starlight` token at 16% opacity, and the active chip is
    // solid `starlight` with near-black `on-accent` on top.
    //
    // Rather than write 138,180,255 here, this file asks the colour scheme for
    // its highlight colour. On a normal AquariusOS machine that IS 138,180,255,
    // because our own scheme sets it — see the [Colors:Selection] block in
    // system_files/usr/share/color-schemes/AquariusDark.colors, where
    // BackgroundNormal is 138,180,255 (starlight) and ForegroundNormal is
    // 8,11,20 (on-accent). So the panel matches the design exactly out of the
    // box.
    //
    // The difference is what happens when somebody changes their accent colour
    // in System Settings, which KDE users very much do: with hardcoded hex the
    // panel would be the one blue thing left on a green desktop. This way it
    // follows them. Same reasoning as the "defaults, never forced" rule the
    // rest of the image is built on.
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    readonly property color aqAccent: Kirigami.Theme.highlightColor
    readonly property color aqText: Kirigami.Theme.textColor

    // A soft wash of the text colour, used for the inactive tile and chip. The
    // design writes these as rgba(255,255,255,.07) and rgba(255,255,255,.12) —
    // white being the text colour on our dark scheme. Deriving them from the
    // text colour instead of hardcoding white means they stay sensible if the
    // user switches to a light scheme, where white-on-white would vanish.
    function aqWash(alpha) {
        return Qt.rgba(aqText.r, aqText.g, aqText.b, alpha)
    }
    function aqAccentWash(alpha) {
        return Qt.rgba(aqAccent.r, aqAccent.g, aqAccent.b, alpha)
    }

    color: !available        ? aqWash(0.03)     // dimmed: the tile is a placeholder
         : active            ? aqAccentWash(mouse.containsMouse ? 0.22 : 0.16)
         : mouse.containsMouse ? aqWash(0.11)
                              : aqWash(0.07)    // design: rgba(255,255,255,.07)

    border.width: 1
    border.color: aqWash(0.10)                  // design: rgba(237,239,247,.1)

    opacity: available ? 1.0 : 0.45

    // A short fade so toggling feels like a switch rather than a redraw.
    Behavior on color {
        ColorAnimation { duration: Kirigami.Units.shortDuration }
    }

    // -------------------------------------------------------------------------
    // CONTENTS
    // -------------------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: tile.dp(12)         // design: padding:10px 12px
        anchors.rightMargin: tile.dp(12)
        anchors.topMargin: tile.dp(10)
        anchors.bottomMargin: tile.dp(10)
        spacing: tile.dp(10)                    // design: gap:10px

        // The round icon chip.
        Rectangle {
            Layout.preferredWidth: tile.dp(32)
            Layout.preferredHeight: tile.dp(32)
            Layout.alignment: Qt.AlignVCenter
            radius: width / 2                   // design: border-radius:50%

            color: tile.active ? tile.aqAccent   // design: background:var(--starlight)
                               : tile.aqWash(0.12)

            Behavior on color {
                ColorAnimation { duration: Kirigami.Units.shortDuration }
            }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: tile.dp(15)
                height: width
                source: tile.iconName

                // On the lit chip the icon sits on bright blue, so it has to be
                // the near-black `on-accent`. That is exactly what the colour
                // scheme calls "the text colour that goes on a highlight", so
                // we ask for it by that name instead of writing #080B14.
                color: tile.active ? Kirigami.Theme.highlightedTextColor
                                   : tile.aqText

                // `isMask` recolours a symbolic icon with the colour above.
                // Without it the icon keeps its own colours and the `color`
                // line silently does nothing.
                isMask: true
            }
        }

        // The two lines of text.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            // Title — design: font:600 12px
            Text {
                Layout.fillWidth: true
                text: tile.title
                color: tile.aqText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Kirigami.Theme.defaultFont.family
                font.pixelSize: tile.dp(12)
                font.weight: Font.DemiBold
            }

            // Subtitle — design: font:400 10.5px, colour rgba(255,255,255,.72).
            //
            // The design's secondary text token is #B4BACD, and the colour
            // scheme does carry that as ForegroundInactive. But the design does
            // NOT use it here: it asks for the primary colour at 72% opacity,
            // which on a tinted active tile reads better than a flat grey.
            // Following the design, so this is opacity rather than a colour
            // role. (KDE's own applets do the same thing — the research note
            // calls this out: a colour scheme has one foreground per group, so
            // second-tier text is conventionally an opacity trick.)
            Text {
                Layout.fillWidth: true
                text: tile.subtitle
                visible: text.length > 0
                color: tile.aqText
                opacity: 0.72
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Kirigami.Theme.defaultFont.family
                font.pixelSize: tile.dp(10.5)
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: tile.available
        cursorShape: tile.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: tile.toggled()
    }
}
