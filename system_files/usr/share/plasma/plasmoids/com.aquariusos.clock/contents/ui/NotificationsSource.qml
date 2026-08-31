/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// Where the notifications come from
// =============================================================================
// This is the ONLY file in the widget that talks to KDE's notification library.
// Everything else — the popup, the rows, the Focus button — asks this file. That
// is deliberate, for two reasons:
//
//   * If the library ever goes missing, exactly one file fails to load, and
//     main.qml swaps in a message instead of the popup. Nothing else breaks.
//   * When KDE changes something, there is one place to look.
//
// WE ARE NOT FORKING KDE'S NOTIFICATIONS APPLET.
//   Tier 2 research (docs/v2-shell-tier2-research.md, Layer 3) settled this:
//   build our panel on `org.kde.notificationmanager` directly, because KDE's own
//   applet leans on a PRIVATE C++ plugin (it imports
//   `plasma.applet.org.kde.plasma.notifications`, which is where its Globals
//   singleton, its drag helper and its job aggregator live). Private plugins are
//   the things that break on a Plasma upgrade. `org.kde.notificationmanager` is
//   a proper installed QML module and is what we build on. We read KDE's applet
//   QML as documentation — it is GPL, and this widget is GPL too — but we do not
//   ship any of its code.
//
// EVERY NAME BELOW WAS CHECKED AGAINST PLASMA 6.7 SOURCE
//   The import name:
//     plasma-workspace/libnotificationmanager/CMakeLists.txt
//       ecm_add_qml_module(notificationmanager URI org.kde.notificationmanager …)
//   The model, its settings, its enums:
//     plasma-workspace/libnotificationmanager/notifications.h   (QML_ELEMENT)
//     plasma-workspace/libnotificationmanager/settings.h
//   How KDE's own applet drives them:
//     plasma-workspace/applets/notifications/main.qml
//     plasma-workspace/applets/notifications/FullRepresentation.qml
//     plasma-workspace/applets/notifications/global/Globals.qml
//   The full table is in docs/clock-notifications-widget.md.
// =============================================================================
pragma ComponentBehavior: Bound

import QtQuick

import org.kde.notificationmanager as NotificationManager

Item {
    id: feed

    // -------------------------------------------------------------------------
    // What the popup reads
    // -------------------------------------------------------------------------
    readonly property alias model: historyModel
    readonly property int count: historyModel.count
    readonly property int unreadCount: historyModel.unreadNotificationsCount

    // Is there anything a "Clear all" could actually remove? KDE's own
    // clear-all action is shown under exactly this condition
    // (applets/notifications/main.qml, the clearHistory action's `visible`).
    readonly property bool canClear: historyModel.expiredNotificationsCount > 0

    // Is the notification service running at all? If the daemon is not there,
    // the model is empty for a boring reason and we should say so rather than
    // claim the user is "all caught up".
    readonly property bool serviceAvailable: NotificationManager.Server.valid

    // -------------------------------------------------------------------------
    // Focus (KDE calls it Do Not Disturb)
    // -------------------------------------------------------------------------
    // The setting is a TIMESTAMP, not a switch: "hold notifications back until
    // this moment". So "Focus until morning" is simply that timestamp set to the
    // next 06:00. Verified in libnotificationmanager/settings.h:
    //
    //     Q_PROPERTY(QDateTime notificationsInhibitedUntil
    //                READ notificationsInhibitedUntil
    //                WRITE setNotificationsInhibitedUntil
    //                RESET resetNotificationsInhibitedUntil
    //                NOTIFY settingsChanged)
    //
    // 06:00 is also the hour KDE picked for its own "Until tomorrow morning"
    // menu entry (FullRepresentation.qml, `dndMorningHour: 6`), so a person who
    // uses both controls gets the same answer from each.
    readonly property int morningHour: 6

    // `now` is fed in from main.qml and ticks once a minute. Comparing against
    // it rather than Date.now() is what makes this line re-evaluate on its own:
    // when the clock passes 06:00, Focus visibly switches itself off.
    property date now: new Date()

    // The same test KDE performs in Globals.qml's checkInhibition(): a future
    // timestamp, or an application asking for quiet, means Focus is on.
    readonly property bool focusActive: {
        if (!feed.serviceAvailable) {
            return false;
        }
        const until = notificationSettings.notificationsInhibitedUntil;
        const untilTime = until.getTime();
        if (!isNaN(untilTime) && feed.now.getTime() < untilTime) {
            return true;
        }
        return notificationSettings.notificationsInhibitedByApplication;
    }

    // When Focus is on, when does it end? An invalid date means "not by a clock"
    // (an app asked for quiet, or nothing is set). The popup uses this for the
    // button's accessible description.
    readonly property date focusEndsAt: notificationSettings.notificationsInhibitedUntil

    // -------------------------------------------------------------------------
    // Things the popup asks this file to DO
    // -------------------------------------------------------------------------

    // "Clear all". The library offers exactly one clear flag today — the enum in
    // notifications.h is `enum ClearFlag { ClearExpired = 1 << 1, // TODO more }`
    // — so this clears the HISTORY. A notification that is still live on screen
    // is closed from its own row instead. KDE's applet has the same limitation
    // and the same one-line call.
    function clearAll(): void {
        historyModel.clear(NotificationManager.Notifications.ClearExpired);
    }

    // Close one row. `close` is Q_INVOKABLE on the model and takes the row's
    // index (notifications.h).
    function closeAt(row: int): void {
        historyModel.close(historyModel.index(row, 0));
    }

    // Click a row: do whatever the notification's default action is (open the
    // folder, focus the chat window…) and then close it. `Close` is a value of
    // the InvokeBehavior enum in notifications.h.
    function activateAt(row: int): void {
        const idx = historyModel.index(row, 0);
        if (historyModel.data(idx, NotificationManager.Notifications.HasDefaultActionRole)) {
            historyModel.invokeDefaultAction(idx, NotificationManager.Notifications.Close);
        }
    }

    function hasDefaultActionAt(row: int): bool {
        return historyModel.data(historyModel.index(row, 0),
                                 NotificationManager.Notifications.HasDefaultActionRole) === true;
    }

    // Everything in the list has now been seen.
    function markEverythingRead(): void {
        for (let i = 0; i < historyModel.count; ++i) {
            historyModel.setData(historyModel.index(i, 0), true,
                                 NotificationManager.Notifications.ReadRole);
        }
    }

    // Move the "older than this is not new" mark to right now. Assigning
    // undefined is how the model is told "reset to now" — KDE does the identical
    // assignment in applets/notifications/main.qml.
    function resetLastRead(): void {
        historyModel.lastRead = undefined;
    }

    // Turn Focus on until the next 06:00.
    //
    // Slight, deliberate difference from KDE's menu entry: KDE only offers
    // "until tomorrow morning" and skips today, so between midnight and 06:00 it
    // sends you to TOMORROW morning — 30 hours of silence. We take whichever
    // 06:00 comes next, which between midnight and 06:00 is this morning. "Until
    // morning" should mean the morning that is about to happen.
    function focusUntilMorning(): void {
        const target = new Date();
        target.setHours(feed.morningHour, 0, 0, 0);
        if (target.getTime() <= Date.now()) {
            target.setDate(target.getDate() + 1);
        }
        notificationSettings.notificationsInhibitedUntil = target;
        notificationSettings.save();
    }

    // Turn Focus off now. The three lines are lifted in shape (not in code) from
    // Globals.qml's revokeInhibitions(): clear our own timestamp, withdraw any
    // hold an application has taken, and write it out. Assigning `undefined`
    // triggers the property's RESET, which is what clears the timestamp rather
    // than setting it to some date in the past.
    function endFocus(): void {
        notificationSettings.notificationsInhibitedUntil = undefined;
        notificationSettings.revokeApplicationInhibitions();
        notificationSettings.save();
    }

    function toggleFocus(): void {
        if (feed.focusActive) {
            feed.endFocus();
        } else {
            feed.focusUntilMorning();
        }
    }

    // -------------------------------------------------------------------------
    // The two objects from KDE's library
    // -------------------------------------------------------------------------
    NotificationManager.Settings {
        id: notificationSettings
    }

    // The history model. Every assignment here matches what KDE's own applet
    // sets on its history model (applets/notifications/main.qml), except that we
    // do not wire up its job-progress extras — a file copy's percentage bar is a
    // feature of KDE's applet, not of our design, and it is the part that needs
    // the private plugin.
    NotificationManager.Notifications {
        id: historyModel

        // Keep notifications that have already timed off screen — that IS the
        // history this panel shows.
        showExpired: true
        showDismissed: true

        // Jobs (file copies, downloads) are hidden. Our panel has no progress
        // row in its design, and showing a job with no progress bar would be
        // worse than not showing it. Written down as a follow-up in
        // docs/clock-notifications-widget.md.
        showJobs: false

        // Newest first, and a FLAT list — no per-application grouping.
        //
        // KDE groups by application because its history can run to dozens of
        // items and needs folding. Our panel is the design's short, flat, newest-
        // first list of three-ish rows (branding/design-system/AquariusOS Desktop
        // Shell.html, #ovNotif), and grouping would add header rows the design
        // has no drawing for. Both enum values are from notifications.h
        // (SortByDate = 0, GroupDisabled = 0). If the list ever gets noisy in
        // real use, switching this to GroupApplicationsFlat is a one-line change
        // plus a header row — noted in docs/clock-notifications-widget.md.
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled

        // Which applications the user has silenced, straight from their KDE
        // notification settings — so the panel obeys settings they may already
        // have set in System Settings.
        blacklistedDesktopEntries: notificationSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notificationSettings.historyBlacklistedServices
        ignoreBlacklistDuringInhibition: true

        // Normal and urgent always; the low-priority chatter only if the user
        // asked for it in System Settings. Same rule as KDE's applet.
        urgencies: {
            let wanted = NotificationManager.Notifications.CriticalUrgency
                       | NotificationManager.Notifications.NormalUrgency;
            if (notificationSettings.lowPriorityHistory) {
                wanted |= NotificationManager.Notifications.LowUrgency;
            }
            return wanted;
        }
    }
}
