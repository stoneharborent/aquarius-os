/*
 * AquariusOS Quick Settings — a tile slot with a safety net
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ============================================================================
 * WHY THIS FILE EXISTS — the most important idea in this widget
 * ============================================================================
 * Every tile in the panel has to talk to a different part of KDE: Wi-Fi goes
 * through plasma-nm, Bluetooth through bluez-qt, Focus through the notification
 * manager, and so on. Each of those is a QML "module" that our code imports.
 *
 * THE PROBLEM
 *   Some of those modules — the ones whose names contain `org.kde.plasma.private`
 *   — carry no compatibility promise whatsoever. KDE is explicitly allowed to
 *   rename or delete them in any release, and AquariusOS does not control when
 *   that happens: we inherit KDE from Bazzite, and a Bazzite rebase can move
 *   Plasma under us overnight. This is not hypothetical. The research note for
 *   this work records a real case where a private module being removed broke a
 *   third-party dock's jump lists.
 *
 *   And QML fails hard here. If a file says `import org.kde.plasma.private.volume`
 *   and that module is gone, the ENTIRE file fails to load — not just the volume
 *   slider. If all the tiles lived in one file, one deleted module upstream would
 *   turn the whole Quick Settings panel into an empty rectangle.
 *
 * THE FIX, AND WHY IT WORKS
 *   Each tile lives in its OWN file, and those files are never referenced
 *   directly. They are pulled in at runtime by a `Loader`, which is QML's way of
 *   saying "try to load this, and tell me how it went."
 *
 *   A Loader that fails does not take its parent down with it. It reports
 *   `status === Loader.Error`, and everything around it carries on. So when a
 *   module disappears, exactly one tile goes quiet and the other three, both
 *   sliders and the battery line keep working.
 *
 *   This file is that wrapper: it tries the real tile, and if the real tile
 *   cannot load it puts a dimmed placeholder in the same space so the 2x2 grid
 *   keeps its shape instead of collapsing.
 *
 * THIS IS A SAFETY NET, NOT A REASON TO RELAX
 *   A quietly dead tile is still a broken feature — it is just not a broken
 *   desktop. The build is supposed to catch this long before a user does:
 *   build_files/quick-settings-check.sh fails the image build if any of the QML
 *   modules this widget depends on is missing from the image, which turns a
 *   silent tile into a red build. Read that script alongside this comment.
 * ============================================================================
 */

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: slot

    // The file to try, e.g. "TileWifi.qml". A plain filename is resolved
    // relative to this folder.
    property string tileSource: ""

    // What the placeholder says if `tileSource` will not load. Keep it the same
    // wording as the real tile's title, so a person reading a dead tile still
    // knows which one it was.
    property string fallbackTitle: ""
    property string fallbackIconName: ""

    // A tile is 52px tall at the default font; AqTile works that out for itself,
    // so the slot just follows whatever it loaded, and falls back to the
    // placeholder's height when there is nothing loaded.
    implicitHeight: loader.status === Loader.Ready && loader.item
                        ? loader.item.implicitHeight
                        : placeholder.implicitHeight

    Loader {
        id: loader
        anchors.fill: parent
        source: slot.tileSource

        // `asynchronous: false` is deliberate. These tiles are tiny and the
        // panel is only built when somebody opens it, so there is nothing to
        // gain from loading them in the background — and doing so would make the
        // grid visibly assemble itself one square at a time.
        asynchronous: false

        onStatusChanged: {
            if (status === Loader.Error) {
                // Printed so the reason is in the journal for whoever
                // investigates. QML has already logged the specific import that
                // failed on the line above this one; this adds the context of
                // WHICH tile died, which the raw QML error does not say.
                console.warn("AquariusOS Quick Settings: the tile", slot.tileSource,
                             "could not be loaded, so it is being shown as",
                             "unavailable. This usually means the KDE QML module",
                             "it needs is not installed in this image. See",
                             "docs/quick-settings-widget.md.")
            }
        }
    }

    // The placeholder. Shown only when the real tile failed — NOT while it is
    // still loading, which would make it flicker on every open.
    AqTile {
        id: placeholder
        anchors.fill: parent
        visible: loader.status === Loader.Error
        title: slot.fallbackTitle
        iconName: slot.fallbackIconName
        subtitle: i18n("Unavailable")
        active: false
        available: false        // dims it and stops it accepting clicks
    }
}
