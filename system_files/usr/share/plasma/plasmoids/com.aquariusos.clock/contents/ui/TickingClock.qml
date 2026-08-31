/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// The backup clock tick
// =============================================================================
// Used only if AlignedClock.qml could not load — that is, if the Plasma we are
// running on does not have `org.kde.plasma.clock`. (It arrived in Plasma 6.6;
// every Plasma we ship on has it, so in practice this file never runs. It exists
// so that a surprise rebase costs us a slightly dumber clock instead of a hole
// in the top bar.)
//
// It is still NOT a once-a-second poll. It works out how many milliseconds are
// left until the top of the next minute, sleeps exactly that long, redraws, and
// then works it out again. So it wakes up once a minute, at the moment the
// displayed time actually changes, which is also why the clock flips over on
// time rather than up to a second late.
//
// What this backup loses compared with the real thing: it does not follow the
// system clock being changed underneath it (a time-zone change, a resume from
// sleep, an NTP correction) until its next tick. Up to one minute stale, then
// correct again. That is an acceptable price for a path that should never run.
// =============================================================================
import QtQuick

Item {
    id: backupClock

    // The one thing main.qml reads. Same name as AlignedClock.qml exposes.
    property date dateTime: new Date()

    // How long until the display would become wrong, in milliseconds.
    // Never less than a second, so a clock jump cannot spin us.
    function millisecondsUntilNextMinute(): int {
        const d = new Date();
        return Math.max(1000, 60000 - (d.getSeconds() * 1000 + d.getMilliseconds()));
    }

    function rearm(): void {
        tick.interval = backupClock.millisecondsUntilNextMinute();
        tick.restart();
    }

    Timer {
        id: tick
        repeat: false
        onTriggered: {
            backupClock.dateTime = new Date();
            backupClock.rearm();
        }
    }

    Component.onCompleted: rearm()
}
