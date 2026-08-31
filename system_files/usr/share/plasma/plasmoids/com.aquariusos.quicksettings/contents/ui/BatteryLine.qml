/*
 * AquariusOS Quick Settings — the battery line along the bottom
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loaded by a Loader in FullRepresentation.qml. On a desktop with no battery
 * this loads fine and then hides itself, which is a different thing from
 * failing to load — see `visible` below.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM
 * ============================================================================
 *   plasma-workspace, branch Plasma/6.7, components/batterycontrol/batterycontrol.h
 *     — provides BatteryControlModel, via `org.kde.plasma.private.battery`
 *   powerdevil, branch Plasma/6.7, applets/batterymonitor/main.qml
 *     — how the stock applet uses it, and the wording of the time-remaining text
 *   https://invent.kde.org/plasma/powerdevil/-/blob/Plasma/6.7/applets/batterymonitor/main.qml
 *
 * ⚠️ CORRECTIONS to guesses that were made before the source was read:
 *   - It is NOT `Battery.percent`, NOT `pmSource`, NOT `batteries.state`.
 *     Plasma 5's `PlasmaCore.DataSource("powermanagement")` no longer exists.
 *   - The battery model and the battery APPLET are in two different
 *     repositories: the model is in plasma-workspace, the applet is in
 *     powerdevil. They are also two different QML modules; this file only needs
 *     the model one.
 *
 * Verbatim from batterycontrol.h — the properties this file uses:
 *
 *   Q_PROPERTY(bool hasCumulative ...)          Q_PROPERTY(int percent ...)
 *   Q_PROPERTY(bool hasBatteries ...)           Q_PROPERTY(bool pluggedIn ...)
 *   Q_PROPERTY(ChargeStateEnum state ...)
 *   Q_PROPERTY(qulonglong smoothedRemainingMsec ...)
 *
 *   enum ChargeStateEnum { NoCharge, Charging, Discharging, FullyCharged };
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.private.battery

RowLayout {
    id: batteryLine

    readonly property real aqScale: Kirigami.Units.gridUnit / 18
    function dp(px) { return Math.round(px * aqScale) }

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    // A desktop tower has no battery. Rather than print "Battery 0%" it hides
    // the whole line, and FullRepresentation lets the "All settings" link slide
    // over to fill the row. `hasCumulative` is the stock applet's own test for
    // "is there a battery worth summarising".
    visible: batteryControl.hasBatteries && batteryControl.hasCumulative

    spacing: dp(8)                              // design: gap:8px

    Kirigami.Icon {
        Layout.preferredWidth: batteryLine.dp(18)
        Layout.preferredHeight: batteryLine.dp(18)

        // Breeze draws the battery at ten-percent steps, named with a
        // three-digit number: battery-000-symbolic … battery-100-symbolic, and
        // a charging set that puts the word AFTER the number —
        // battery-080-charging-symbolic.
        //
        // ⚠️ The charging name is the easy one to get wrong. It is NOT
        // "battery-charging-080", and a bare "battery-charging" does not exist
        // either. Nor does a bare "battery": that name belongs to a large
        // full-colour illustration in icons/devices/64/, not a status glyph, so
        // using it would put a full-colour picture in the panel.
        source: {
            const bucket = Math.round(Math.max(0, Math.min(100, batteryControl.percent)) / 10) * 10
            const padded = bucket < 10 ? "00" + bucket
                         : bucket < 100 ? "0" + bucket
                                        : "100"
            return batteryControl.state === BatteryControlModel.Charging
                        ? "battery-" + padded + "-charging-symbolic"
                        : "battery-" + padded + "-symbolic"
        }

        // The design draws the battery's fill in the green `success` colour.
        // `positiveTextColor` IS that green on our scheme — the [Colors:View]
        // block of AquariusDark.colors sets ForegroundPositive to 85,214,165,
        // which is #55D6A5, the `success` token. Asking for it by role rather
        // than by number means a user's own colour scheme is respected, and it
        // lets the icon also go amber and red as the battery empties, which the
        // design's single mock could not show.
        color: batteryControl.percent <= 10 ? Kirigami.Theme.negativeTextColor
             : batteryControl.percent <= 25 ? Kirigami.Theme.neutralTextColor
                                            : Kirigami.Theme.positiveTextColor
        isMask: true
    }

    // "Battery 82% · about 6 hr left"
    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: Kirigami.Theme.textColor
        font.family: Kirigami.Theme.defaultFont.family
        font.pixelSize: batteryLine.dp(11.5)    // design: font:400 11.5px

        text: {
            const percentPart = i18nc("@info battery charge level",
                                      "Battery %1%", batteryControl.percent)

            if (batteryControl.state === BatteryControlModel.FullyCharged) {
                return i18nc("@info battery is full and on mains power",
                             "%1 · Fully charged", percentPart)
            }

            // KDE gives the time left in milliseconds and nothing else — there
            // is no ready-made "6 hr left" string anywhere. `formatDuration` is
            // the same formatter the stock applet uses, and HideSeconds is what
            // keeps it from reading "6 hr 12 min 4 s".
            //
            // Zero means "not worked out yet", which happens for a minute or so
            // after unplugging. Saying nothing is better than saying "0 min".
            if (batteryControl.smoothedRemainingMsec > 0) {
                const timeString = KCoreAddons.Format.formatDuration(
                    batteryControl.smoothedRemainingMsec,
                    KCoreAddons.FormatTypes.HideSeconds)

                return batteryControl.state === BatteryControlModel.Charging
                    ? i18nc("@info time until battery is full",
                            "%1 · %2 until full", percentPart, timeString)
                    : i18nc("@info time left on battery",
                            "%1 · %2 left", percentPart, timeString)
            }

            return batteryControl.pluggedIn
                ? i18nc("@info battery is charging, time not yet known",
                        "%1 · Charging", percentPart)
                : percentPart
        }
    }

    BatteryControlModel {
        id: batteryControl
    }
}
