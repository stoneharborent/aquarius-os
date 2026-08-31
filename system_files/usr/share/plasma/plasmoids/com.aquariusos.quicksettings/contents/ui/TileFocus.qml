/*
 * AquariusOS Quick Settings — the Focus tile (Do Not Disturb)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loaded by AqTileSlot.qml.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM
 * ============================================================================
 *   plasma-workspace, branch Plasma/6.7
 *   applets/notifications/main.qml, FullRepresentation.qml, global/Globals.qml
 *   libnotificationmanager/settings.h
 *   https://invent.kde.org/plasma/plasma-workspace/-/tree/Plasma/6.7/applets/notifications
 *
 * ⚠️ Path note, again: on Plasma 6.7 the notifications applet's QML is FLAT —
 * `applets/notifications/main.qml`. The old `package/contents/ui/` folder is
 * gone. Three of the paths written down in the Tier 2 research note point at
 * the Plasma 5 layout and 404.
 *
 * `org.kde.notificationmanager` has no `private` in its name and is the module
 * the stock notifications applet is built on, so it is one of the safer imports
 * in this widget.
 *
 * ============================================================================
 * THE SURPRISING PART: "DO NOT DISTURB" IS NOT A YES/NO SETTING
 * ============================================================================
 * There is no `notificationsInhibited` boolean anywhere in KDE. It was looked
 * for and it does not exist. What exists is ONE property:
 *
 *     notificationsInhibitedUntil  — a date and time
 *
 * and the rule, quoted from the comment above it in libnotificationmanager's
 * settings.h:
 *
 *     "The date until which do not disturb mode is enabled. When invalid or in
 *      the past, do not disturb mode should be considered disabled."
 *
 * So "Focus is on" means "that date is in the future", and switching Focus on
 * "indefinitely" means writing a date far enough away that it may as well be
 * forever. KDE picks one year, and says so in its own code (Globals.qml):
 *
 *     // Effectively "in a year" is "until turned off"
 *     var d = new Date();
 *     d.setFullYear(d.getFullYear() + 1);
 *
 * This file does exactly the same thing, on purpose. If we invented our own
 * convention — a different span, or a config key of our own — then our tile and
 * KDE's own Do Not Disturb switch would disagree about whether Focus is on.
 * Copying the convention is what keeps the two in step.
 *
 * ⚠️ WHY THIS FILE REIMPLEMENTS LOGIC INSTEAD OF CALLING KDE'S
 *   The stock applet has a tidy `Globals.inhibited` property and a
 *   `Globals.revokeInhibitions()` function that do everything below. They live
 *   in `plasma.applet.org.kde.plasma.notifications` — the stock applet's OWN
 *   private QML module, which only that applet can import. A third-party widget
 *   cannot reach them, so the two functions are rebuilt here against the public
 *   Settings object. They are copies of the upstream versions, not inventions.
 *
 * DOES THE REST OF THE DESKTOP NOTICE WHEN WE CHANGE IT?
 *   Yes. Settings is backed by a config file that KDE watches with a
 *   KConfigWatcher (settings.cpp), and `Settings.live` defaults to true, so a
 *   write here reaches plasmashell immediately and a change made in KDE's own
 *   notification settings shows up here immediately. The two stay in sync
 *   without any work on our side.
 */

import QtQuick
import org.kde.notificationmanager as NotificationManager

AqTile {
    id: focus

    title: i18n("Focus")

    // The notification server not being up is the one case where this tile
    // genuinely cannot work. It is rare and usually momentary.
    available: NotificationManager.Server.valid

    // Is Focus on right now? This is KDE's own test, rewritten:
    //   - a date that exists AND is still in the future, or
    //   - some application has asked for silence (a full-screen video player,
    //     a presentation) — in which case Focus really IS on, just not because
    //     the user pressed this tile.
    //
    // `getTime()` on an unset date returns NaN, which is why the isNaN guard
    // comes first: comparing against NaN is false in a way that would quietly
    // read as "Focus is off" even in cases we want to catch.
    readonly property bool inhibited: {
        const until = notificationSettings.notificationsInhibitedUntil
        const untilActive = until !== undefined
                            && !isNaN(until.getTime())
                            && Date.now() < until.getTime()
        return untilActive || notificationSettings.notificationsInhibitedByApplication
    }

    active: inhibited

    // Both names come from the stock notifications applet
    // (plasma-workspace, applets/notifications/CompactRepresentation.qml).
    //
    // ⚠️ Note the inconsistent plural, which is upstream's and not a typo here:
    // the quiet-bell icon is "notification-inactive-symbolic" (singular) while
    // the crossed-out one is "notifications-disabled-symbolic" (plural). There
    // is no "notifications-inactive".
    iconName: active ? "notifications-disabled-symbolic"
                     : "notification-inactive-symbolic"

    // The design shows "Notifications on" under an unlit Focus tile, i.e. the
    // subtitle describes the state of your NOTIFICATIONS, not the state of the
    // tile. Kept that way round deliberately — it is the thing a person
    // actually wants to know at a glance.
    subtitle: {
        if (!available) {
            return i18n("Unavailable")
        }
        if (notificationSettings.notificationsInhibitedByApplication) {
            // Worth distinguishing: pressing the tile will NOT fix this, because
            // an app is holding it, so saying "off" alone would be misleading.
            return i18n("Paused by an app")
        }
        return active ? i18n("Notifications off") : i18n("Notifications on")
    }

    onToggled: {
        if (inhibited) {
            // --- switching Focus OFF ---
            // A copy of upstream's revokeInhibitions(). All four lines matter:
            // clearing the date alone leaves an app-held inhibition in place,
            // and the tile would appear not to respond.
            notificationSettings.notificationsInhibitedUntil = undefined
            notificationSettings.revokeApplicationInhibitions()
            notificationSettings.fullscreenFocused = false
            notificationSettings.screensMirrored = false
        } else {
            // --- switching Focus ON, until switched off ---
            // One year out, which is KDE's own spelling of "indefinitely".
            const until = new Date()
            until.setFullYear(until.getFullYear() + 1)
            notificationSettings.notificationsInhibitedUntil = until
        }

        // Nothing above is written to disk until this is called.
        notificationSettings.save()
    }

    // The settings object itself. `Settings` is an ordinary instantiable type
    // (it is QML_ELEMENT, not QML_SINGLETON), so it is declared here.
    //
    // NOTE the other type in this module, `NotificationManager.Server`, IS a
    // singleton and is read above for `.valid`. It also has an `inhibited`
    // property that looks tempting and must not be written to: that one belongs
    // to whichever process owns the notification server, and setting it from
    // here would fight plasmashell.
    NotificationManager.Settings {
        id: notificationSettings
    }
}
