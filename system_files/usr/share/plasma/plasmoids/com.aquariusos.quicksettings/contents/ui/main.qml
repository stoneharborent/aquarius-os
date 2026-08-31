/*
 * AquariusOS Quick Settings — the widget's root
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ============================================================================
 * WHAT THIS WIDGET IS
 * ============================================================================
 * One panel holding the four switches and two sliders a person reaches for
 * most: Wi-Fi, Bluetooth, Focus, Game Mode (or the power profile on a desktop),
 * sound and brightness — plus how much battery is left and a way into the full
 * Settings app.
 *
 * KDE has no such panel. Out of the box each of those lives in its own little
 * popup hanging off its own tray icon, so turning Bluetooth off and turning the
 * volume down are two different clicks in two different places. This widget is
 * the one drawer, as designed in
 * branding/design-system/"AquariusOS Shell Quick Settings.html".
 *
 * ============================================================================
 * HOW THE FILES FIT TOGETHER
 * ============================================================================
 *   main.qml                 this file — the two faces of the widget
 *   CompactRepresentation    the icon in the top bar
 *   FullRepresentation       the 330px panel that drops down
 *     AqTile / AqSlider      the look of one toggle and one slider
 *     AqTileSlot             the safety net that loads a tile
 *     AqPlatform             works out which machine this is, and runs commands
 *     Tile*.qml, Slider*.qml, BatteryLine.qml
 *                            one file per thing being controlled; each one
 *                            names the KDE source it was written from
 *
 * The reason there are so many small files rather than one big one is safety,
 * and it is explained properly at the top of AqTileSlot.qml. In short: a QML
 * file that imports a missing module fails completely, so each risky import is
 * quarantined in its own file and loaded at arm's length.
 *
 * ============================================================================
 * WHY THIS IS A PANEL WIDGET AND NOT A SYSTEM TRAY WIDGET
 * ============================================================================
 * It would seem natural to put this inside the system tray with the other
 * status icons. It cannot go there, and this is the single most important
 * structural fact about the widget.
 *
 * Applets hosted INSIDE the system tray do not get to choose how big their
 * popup is — the tray fixes that size, and an applet asking for a particular
 * width is ignored. The design calls for a 330px panel. A tray-hosted version
 * would be whatever width the tray felt like.
 *
 * So the layout script adds this widget to the bar in its own right, standing
 * next to the tray rather than inside it. Standalone panel widgets DO get the
 * width they ask for. See the comment where the layout script adds it.
 */

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // Always show the icon, never expand into the panel in place. Without this
    // the widget would draw the whole 330px panel inline when it is given
    // enough room — on the desktop, or in a very tall bar — which is not what
    // it is for.
    preferredRepresentation: compactRepresentation

    compactRepresentation: CompactRepresentation {
        // `root` is reachable from in here because an inline component can see
        // the ids declared around it. This is what lets the icon, which lives
        // in its own file, open a popup it knows nothing about.
        onToggleRequested: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {}

    // What the widget calls itself: in the tooltip, in the "Add Widgets" list,
    // and to a screen reader.
    Plasmoid.title: i18n("Quick Settings")
    Plasmoid.icon: "configure-symbolic"

    toolTipMainText: i18n("Quick Settings")
    toolTipSubText: i18n("Wi-Fi, Bluetooth, Focus, sound and brightness")
}
