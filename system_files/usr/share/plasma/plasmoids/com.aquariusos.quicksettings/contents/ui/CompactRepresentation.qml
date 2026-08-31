/*
 * AquariusOS Quick Settings — the icon in the top bar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The small thing you click. Clicking it opens FullRepresentation.qml.
 *
 * ============================================================================
 * ⚠️ WE ARE DELIBERATELY DIFFERENT FROM THE DESIGN HERE — read before "fixing"
 * ============================================================================
 * The V2 design does not draw a settings icon in the top bar. Its tray button
 * (the `toggle('tray')` element in "AquariusOS Desktop Shell.html") is TWO
 * glyphs side by side: a Wi-Fi arc and a battery, macOS-style — a little status
 * cluster that happens to also be the button.
 *
 * This file draws a single sliders icon instead. That is a deliberate choice,
 * not an oversight, and the reason is that the design and the shipping shell
 * disagree about what else is in the bar:
 *
 *   - In the design, this cluster IS the tray. There is nothing else showing
 *     Wi-Fi or battery, so putting them here is the only way to see them.
 *
 *   - In AquariusOS as it actually ships, the stock KDE system tray is still in
 *     the bar, immediately to the right of this widget (see the layout script).
 *     That tray already shows network, battery and volume icons. Drawing a
 *     Wi-Fi arc and a battery here too would show a person the same two things
 *     twice, an inch apart.
 *
 * So the design is right about the design's bar, and this is right about ours.
 * A distinct icon also makes the button's job obvious: it opens settings, it is
 * not a status readout.
 *
 * WHEN TO REVISIT
 *   If AquariusOS ever drops the stock system tray from the top bar — which the
 *   V2 design implies and which would need its own decision, because the tray
 *   is also where third-party apps put their icons — then this file should
 *   change to the design's two-glyph cluster. Doing that means reading live
 *   Wi-Fi and battery state up here, so the icon would need the same Loader
 *   safety net the panel's tiles have. Worth knowing before starting.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: compact

    // Emitted on click. main.qml turns this into "open or close the panel" —
    // this file cannot do that itself, because the property that opens the
    // popup lives on the widget's root object, not here.
    signal toggleRequested()

    // A panel widget is asked how wide it wants to be for the height it has
    // been given. Square is right for a single icon: it makes the widget take
    // exactly as much of the bar as the icon needs and no more.
    Layout.minimumWidth: Layout.minimumHeight
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    Layout.preferredWidth: height
    Layout.preferredHeight: height

    Kirigami.Icon {
        anchors.centerIn: parent

        // Square, and inset a little so the glyph is not jammed against the
        // edges of a thin bar. The stock applets use the same proportion.
        width: Math.round(Math.min(compact.width, compact.height) * 0.8)
        height: width

        // "settings-configure" is Breeze's row-of-sliders glyph — the one KDE
        // uses for "Configure". It reads as controls-you-can-adjust, which is
        // exactly what the panel is, and its thin-stroke line style sits
        // comfortably next to the design's other bar glyphs.
        source: "settings-configure"

        // Follow the bar's text colour rather than the icon's own, so the
        // button matches the clock and the menu names beside it.
        color: Kirigami.Theme.textColor
        isMask: true

        // A gentle press response. The design gives its bar items a hover
        // background; that background is drawn by the Plasma style for panel
        // widgets, so all this file adds is the nudge on click.
        scale: mouse.pressed ? 0.88 : 1.0
        Behavior on scale {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: compact.toggleRequested()
    }
}
