/*
 * AquariusOS Quick Settings — one labelled slider
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHAT THIS IS
 *   A row of small text ("Sound" on the left, "64%" on the right) with a slim
 *   track underneath. Both the sound slider and the brightness slider are this
 *   file; like AqTile.qml it knows nothing about what it is controlling.
 *
 * WHY IT IS BUILT ON QtQuick.Controls.Slider AND NOT DRAWN FROM SCRATCH
 *   The design is just a bar and a dot, and drawing that with a MouseArea would
 *   be about ten lines. It would also be a slider that ignores the arrow keys,
 *   ignores Page Up, cannot be reached by Tab, does not respond to the scroll
 *   wheel, and is invisible to a screen reader.
 *
 *   Controls.Slider brings all of that with it, and lets us replace only the two
 *   pieces the design actually changes — the track and the handle. So the look
 *   is ours and the behaviour is Qt's.
 *
 * WHERE THE NUMBERS COME FROM
 *   branding/design-system/"AquariusOS Desktop Shell.html", the `.slider` rules
 *   and the label row above them. See AqTile.qml for what `dp()` is doing.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    // --- what the caller sets ------------------------------------------------

    // The left-hand word: "Sound", "Brightness".
    property string label: ""

    // 0.0 to 1.0. The caller keeps this in step with the real volume/brightness.
    property real value: 0

    // Set false when there is nothing to control (no backlight on a desktop
    // monitor, no sound card). The row hides itself entirely rather than
    // offering a slider that does nothing.
    property bool available: true

    // How many steps a keypress or one notch of the scroll wheel moves. 5% is
    // what KDE's own volume and brightness controls use.
    property real stepSize: 0.05

    // Emitted while dragging AND on every keypress. The caller applies it.
    signal moved(real newValue)

    readonly property real aqScale: Kirigami.Units.gridUnit / 18
    function dp(px) { return Math.round(px * aqScale) }

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    visible: available
    spacing: dp(8)                              // design: margin-bottom:8px

    // -------------------------------------------------------------------------
    // The label row
    // -------------------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: 0

        // design: font:500 11px, colour #FFFFFF
        Text {
            text: root.label
            color: Kirigami.Theme.textColor
            font.family: Kirigami.Theme.defaultFont.family
            font.pixelSize: root.dp(11)
            font.weight: Font.Medium
        }

        Item { Layout.fillWidth: true }

        // The percentage, in the mono face — design: font-family:var(--font-mono).
        //
        // The image ships JetBrains Mono (branding/tokens.md, "Typography"), and
        // `font.families` is a list so "monospace" catches the case where the
        // font did not install: fontconfig always resolves that name to
        // SOMETHING, so the number can never fall back to an invisible font.
        Text {
            text: i18nc("@label a percentage, e.g. 64%", "%1%", Math.round(root.value * 100))
            color: Kirigami.Theme.textColor
            font.families: ["JetBrains Mono", "monospace"]
            font.pixelSize: root.dp(11)
            font.weight: Font.Medium
        }
    }

    // -------------------------------------------------------------------------
    // The track
    // -------------------------------------------------------------------------
    QQC2.Slider {
        id: slider

        Layout.fillWidth: true
        from: 0
        to: 1
        stepSize: root.stepSize

        // `!pressed` is the important half of this line. Without it, the binding
        // fights the drag: the caller sets the real volume, that comes back in
        // as `root.value`, and the handle jumps back under the finger. While the
        // handle is held the slider owns its own position, and the binding takes
        // over again the moment it is let go.
        value: !pressed ? root.value : value

        onMoved: root.moved(value)

        // The whole row is only as tall as the design's 16px handle.
        implicitHeight: root.dp(16)

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: root.dp(6)                  // design: height:6px
            radius: height / 2                  // design: border-radius:3px

            // design: background:rgba(237,239,247,.12) — the text colour at 12%,
            // derived rather than hardcoded for the same reason as AqTile's
            // washes: it has to stay visible if the user picks a light scheme.
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.12)

            // The filled part, left of the handle — design: background:var(--starlight).
            // `highlightColor` is starlight on our scheme and the user's own
            // accent if they changed it. Same choice as AqTile; the reasoning is
            // written out there.
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: Kirigami.Theme.highlightColor
            }
        }

        // design: 16px white circle with a soft drop shadow.
        //
        // The shadow is drawn as a second, slightly larger, very faint circle
        // behind the handle rather than with a real blur. A blur would mean
        // pulling in QtQuick.Effects and paying for an offscreen render pass on
        // a dot this size; at 16px the fake reads the same.
        handle: Item {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: root.dp(16)
            implicitHeight: root.dp(16)

            Rectangle {
                anchors.centerIn: parent
                width: parent.width + root.dp(2)
                height: width
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.35)   // design: 0 1px 4px rgba(0,0,0,.5)
                y: parent.y + root.dp(1)
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2

                // The design's handle is flat #FFFFFF. On our dark scheme the
                // text colour IS white, so this matches; on a light scheme it
                // becomes near-black, which is what a light theme wants anyway.
                color: Kirigami.Theme.textColor

                scale: slider.pressed ? 1.1 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }
            }
        }
    }
}
