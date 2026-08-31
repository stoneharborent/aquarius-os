/*
 * AquariusOS Quick Settings — the Bluetooth tile
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loaded by AqTileSlot.qml. See that file for why every tile is loaded rather
 * than written straight into the panel.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM
 * ============================================================================
 * Read out of the stock Bluetooth applet:
 *
 *   bluedevil, branch Plasma/6.7, file `src/applet/qml/main.qml`
 *   https://invent.kde.org/plasma/bluedevil/-/blob/Plasma/6.7/src/applet/qml/main.qml
 *
 * ⚠️ THIS IS THE BEST-BEHAVED IMPORT IN THE WHOLE WIDGET, and it is worth
 * knowing why. `org.kde.bluezqt` is not a Plasma module at all — it lives in
 * KDE **Frameworks** (frameworks/bluez-qt), which is the tier of KDE that comes
 * with actual source and binary compatibility promises. It is the same
 * guarantee level as Qt itself.
 *
 * The Plasma-private Bluetooth module DOES exist — `org.kde.plasma.private.bluetooth`
 * — and this file deliberately does NOT import it. All it provides is the
 * pairing-wizard launcher and a couple of proxy models for the stock applet's
 * device list, none of which a simple on/off tile needs. Leaving it out removes
 * the one genuinely fragile dependency this tile could have had.
 *
 * The exact lines this file leans on, from that source:
 *
 *   import org.kde.bluezqt as BluezQt                        (main.qml)
 *   checked: BluezQt.Manager.bluetoothOperational            (main.qml, ~line 114)
 *   if (BluezQt.Manager.adapters.length === 0) { … }         (main.qml, ~line 58)
 *   BluezQt.Manager.connectedDevices.length                  (main.qml, ~line 91)
 *
 *   function setBluetoothEnabled(enable: bool): void {       (main.qml, ~line 99)
 *       BluezQt.Manager.bluetoothBlocked = !enable;
 *       BluezQt.Manager.adapters.forEach(adapter => { adapter.powered = enable; });
 *   }
 */

import QtQuick
import org.kde.bluezqt as BluezQt

AqTile {
    id: bluetooth

    title: i18n("Bluetooth")

    // -------------------------------------------------------------------------
    // `Manager` is a SINGLETON — note there is no `BluezQt.Manager { }` block
    // -------------------------------------------------------------------------
    // Unlike the NetworkManager objects in TileWifi.qml, which are created one
    // per user, bluez-qt's Manager is registered with QML_SINGLETON (see
    // bluez-qt's src/imports/declarativemanager.h). There is exactly one of them
    // for the whole session and it is referenced directly. Trying to declare one
    // is an error, not a style choice.

    // No adapter means no Bluetooth chip in the machine — common on desktops.
    // The stock applet tests the same thing the same way.
    available: BluezQt.Manager.adapters.length > 0

    // `bluetoothOperational` is bluez-qt's own summary of "is Bluetooth actually
    // usable right now" — it accounts for the adapter being present, powered,
    // and not blocked by rfkill. Cheaper and more correct than checking those
    // three separately, which is why the stock applet uses it too.
    active: BluezQt.Manager.bluetoothOperational

    iconName: active ? "preferences-system-bluetooth"
                     : "preferences-system-bluetooth-inactive"

    // The design shows the connected devices ("Pad · Buds"). Listing their real
    // names is nicer than a count, so that is what this does, with a count as
    // the overflow case so a person with five things paired does not get a
    // subtitle three times the width of the tile.
    subtitle: {
        if (!available) {
            return i18n("No adapter")
        }
        if (!BluezQt.Manager.bluetoothOperational) {
            return i18n("Off")
        }

        const devices = BluezQt.Manager.connectedDevices
        if (devices.length === 0) {
            return i18n("On")
        }
        if (devices.length <= 2) {
            // The interpunct is the separator the design uses.
            const names = []
            for (let i = 0; i < devices.length; ++i) {
                names.push(devices[i].name)
            }
            return names.join(" · ")
        }
        return i18np("%1 device", "%1 devices", devices.length)
    }

    // Switching Bluetooth on is TWO operations, not one, and doing only half of
    // it is a bug that looks like it works.
    //
    //   `bluetoothBlocked` is the rfkill soft-block — the same switch as a
    //   laptop's aeroplane mode. While it is set, powering an adapter on is
    //   refused.
    //   `adapter.powered` is the per-adapter switch, and a machine can have
    //   more than one adapter (a built-in one plus a USB dongle), so every
    //   adapter gets the same treatment.
    //
    // Unblocking without powering leaves Bluetooth off; powering without
    // unblocking silently fails. This is copied from the stock applet's
    // `setBluetoothEnabled` for exactly that reason.
    onToggled: {
        const enable = !BluezQt.Manager.bluetoothOperational
        BluezQt.Manager.bluetoothBlocked = !enable
        BluezQt.Manager.adapters.forEach(adapter => {
            adapter.powered = enable
        })
    }
}
