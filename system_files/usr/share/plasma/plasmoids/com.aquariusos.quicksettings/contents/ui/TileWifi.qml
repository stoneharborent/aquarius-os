/*
 * AquariusOS Quick Settings — the Wi-Fi tile
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loaded by AqTileSlot.qml, never referenced directly. Read the big comment at
 * the top of that file to understand why — the short version is that if the
 * import below ever disappears, only this tile goes quiet.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM — checked against KDE's own source, not guessed
 * ============================================================================
 * Everything here was read out of the stock Plasma Wi-Fi applet, which is the
 * widget that normally lives in the system tray. Doing the same job the same
 * way is the whole point: we are re-dressing KDE's networking, not
 * reimplementing it.
 *
 *   plasma-nm, branch Plasma/6.7, file `applet/main.qml`
 *   https://invent.kde.org/plasma/plasma-nm/-/blob/Plasma/6.7/applet/main.qml
 *
 * ⚠️ Note for anyone re-checking this later: in Plasma 6 the applet's QML sits
 * at `applet/main.qml`. It is NOT at `applet/contents/ui/main.qml` — that was
 * the Plasma 5 layout, and looking for it there returns a 404 and wastes an
 * afternoon.
 *
 * The exact lines this file leans on, from that source:
 *
 *   import org.kde.plasma.networkmanagement as PlasmaNM     (main.qml, line 11)
 *   PlasmaNM.EnabledConnections  { id: enabledConnections } (main.qml, ~line 133)
 *   PlasmaNM.AvailableDevices    { id: availableDevices }
 *   PlasmaNM.Handler             { id: handler }
 *   checked: enabledConnections.wirelessEnabled             (main.qml, ~line 82)
 *   visible: enabledConnections.wirelessHwEnabled
 *              && availableDevices.wirelessDeviceAvailable
 *   onTriggered: checked => { handler.enableWireless(checked) }
 *
 * `Handler.enableWireless(bool)` is declared as a slot in plasma-nm's
 * `libs/handler.h`, so it is callable from QML.
 *
 * WHY THIS IMPORT IS ONE OF THE SAFER ONES
 *   `org.kde.plasma.networkmanagement` does NOT have `private` in its name. It
 *   is still a Plasma module rather than a Frameworks one, so it carries no
 *   formal promise, but it is the module the shipped Wi-Fi applet itself is
 *   built on — it cannot vanish without the stock applet vanishing too.
 */

import QtQuick
import org.kde.plasma.networkmanagement as PlasmaNM

AqTile {
    id: wifi

    title: i18n("Wi-Fi")

    // Is there Wi-Fi hardware at all, and is it switched on at the hardware
    // level (a laptop's aeroplane-mode switch turns `wirelessHwEnabled` off)?
    // On a desktop with no wireless card this is false and the tile greys out
    // rather than offering a switch that cannot do anything.
    available: availableDevices.wirelessDeviceAvailable
               && enabledConnections.wirelessHwEnabled

    active: enabledConnections.wirelessEnabled

    iconName: active ? "network-wireless-connected-100"
                     : "network-wireless-disconnected"

    // The small line under the title. The design shows a network name there
    // ("HarborNet 5G"), which is the interesting case, but the tile has to say
    // something sensible in the other three states too.
    subtitle: {
        if (!available) {
            return i18n("No adapter")
        }
        if (!enabledConnections.wirelessEnabled) {
            return i18n("Off")
        }
        // Empty string when associated with nothing — see the comment on
        // `wifiSSID` in plasma-nm's libs/wirelessstatus.h: "Returns the SSID of
        // the currently active wireless connection, if any, otherwise an empty
        // string".
        return wirelessStatus.wifiSSID !== ""
                    ? wirelessStatus.wifiSSID
                    : i18n("Not connected")
    }

    onToggled: handler.enableWireless(!enabledConnections.wirelessEnabled)

    // -------------------------------------------------------------------------
    // The objects that do the actual talking to NetworkManager
    // -------------------------------------------------------------------------
    // These are all plain instantiable types — none of them is a singleton — so
    // each one is declared here exactly as the stock applet declares them.

    // Which kinds of connection are switched on. Carries `wirelessEnabled`.
    PlasmaNM.EnabledConnections {
        id: enabledConnections
    }

    // What hardware exists. Carries `wirelessDeviceAvailable`.
    PlasmaNM.AvailableDevices {
        id: availableDevices
    }

    // The thing that actually changes settings. `enableWireless(bool)` is the
    // only method this tile uses.
    PlasmaNM.Handler {
        id: handler
    }

    // The name of the network we are on.
    //
    // ⚠️ WORTH KNOWING: this type is in the same public module as the three
    // above, but the stock Wi-Fi applet does not use it — the only thing in KDE
    // that does is the Hotspot settings page
    // (plasma-nm, kcms/kcm_hotspot/ui/main.qml, which declares it exactly like
    // this). So it is a slightly less well-trodden path than the rest of this
    // file, and if one line here is going to break on a future Plasma, it is
    // this one. It fails softly on its own terms: an SSID that stops arriving
    // leaves the subtitle reading "Not connected" while the toggle keeps
    // working.
    PlasmaNM.WirelessStatus {
        id: wirelessStatus
    }
}
