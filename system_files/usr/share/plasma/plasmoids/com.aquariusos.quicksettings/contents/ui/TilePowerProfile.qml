/*
 * AquariusOS Quick Settings — the Performance tile (desktops and laptops)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This is the fourth square in the grid on every machine EXCEPT a handheld.
 * On a handheld that square is Game Mode instead — AqPlatform.qml decides which,
 * and explains the whole choice.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM
 * ============================================================================
 *   powerdevil, branch Plasma/6.7
 *   applets/batterymonitor/main.qml, PopupDialog.qml, PowerProfileItem.qml
 *   applets/batterymonitor/plugin/powerprofilescontrol.h
 *   https://invent.kde.org/plasma/powerdevil/-/tree/Plasma/6.7/applets/batterymonitor
 *
 * ⚠️ CORRECTIONS to names that were guessed before the source was read:
 *   - There is NO `org.kde.plasma.private.powerprofiles` module, and no
 *     `org.kde.plasma.private.powerdevil` module either. Power profiles come
 *     from `org.kde.plasma.private.batterymonitor`.
 *   - The type is `PowerProfilesControl`. There is no `PowerProfileMonitor`.
 *
 * Verbatim from powerprofilescontrol.h:
 *
 *   Q_PROPERTY(bool isPowerProfileDaemonInstalled ...)
 *   Q_PROPERTY(QStringList profiles ...)
 *   Q_PROPERTY(QString configuredProfile ...)
 *   Q_PROPERTY(QString activeProfile ...)
 *   Q_PROPERTY(bool isTlpInstalled ...)
 *   Q_INVOKABLE void setProfile(const QString &reason);
 *
 * and the three profile names, from PowerProfileItem.qml:
 *   "power-saver", "balanced", "performance"
 */

import QtQuick
import org.kde.plasma.private.batterymonitor

AqTile {
    id: powerProfile

    title: i18n("Performance")

    // -------------------------------------------------------------------------
    // WHEN THIS TILE CAN DO ANYTHING
    // -------------------------------------------------------------------------
    // Three separate things have to be true, and all three are common enough to
    // be worth testing rather than assuming:
    //
    //   1. power-profiles-daemon has to be running. It is on Fedora and so on
    //      Bazzite, but it is a package and packages can be absent.
    //
    //   2. The machine has to actually offer profiles. On a desktop with no
    //      supported CPU scaling driver the daemon loads a placeholder and
    //      offers "balanced" only — a switch with nothing to switch to.
    //
    //   3. TLP must not be in charge. If somebody has installed TLP it manages
    //      power itself and power-profiles-daemon's settings are ignored; the
    //      stock applet detects exactly this and disables its own control
    //      rather than offering one that does nothing.
    readonly property bool hasPerformance:
        powerProfilesControl.profiles.indexOf("performance") !== -1

    available: powerProfilesControl.isPowerProfileDaemonInstalled
               && powerProfilesControl.profiles.length > 0
               && hasPerformance
               && !powerProfilesControl.isTlpInstalled

    active: powerProfilesControl.activeProfile === "performance"

    // "battery-profile-performance-symbolic" and "speedometer" are the two the
    // stock battery applet uses for these states (its CompactRepresentation.qml
    // picks between them and the powersave one).
    iconName: active ? "battery-profile-performance-symbolic"
                     : "speedometer-symbolic"

    // The design's fourth tile just says "Off" when it is off. Naming the
    // actual profile is more useful here, because "not performance" has two
    // different meanings — balanced and power-saver — and which one you are in
    // matters if you are chasing battery life.
    subtitle: {
        if (!available) {
            if (powerProfilesControl.isTlpInstalled) {
                return i18n("Managed by TLP")
            }
            return i18n("Unavailable")
        }
        switch (powerProfilesControl.activeProfile) {
        case "performance":  return i18n("On")
        case "power-saver":  return i18n("Power saver")
        case "balanced":     return i18n("Balanced")
        default:             return i18n("Balanced")
        }
    }

    onToggled: {
        if (!available) {
            return
        }

        if (active) {
            // Going back to whatever this machine considers normal. Using the
            // user's own configured default rather than hardcoding "balanced"
            // matters for anybody who has set power-saver as their normal
            // state: hardcoding would quietly promote them to balanced every
            // time they used this tile. `configuredProfile` can be empty, hence
            // the fallback, which is the same fallback the stock applet uses.
            const normal = powerProfilesControl.configuredProfile !== ""
                            ? powerProfilesControl.configuredProfile
                            : "balanced"
            powerProfilesControl.setProfile(normal)
        } else {
            powerProfilesControl.setProfile("performance")
        }
    }

    PowerProfilesControl {
        id: powerProfilesControl

        // Suppresses PowerDevil's own full-screen "Performance mode" overlay.
        // The tile lighting up is the feedback; the overlay on top of the panel
        // the user is looking at would be a second announcement of the same
        // thing. The stock applet sets this the same way while its popup is
        // open.
        isSilent: true
    }
}
