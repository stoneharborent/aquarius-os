/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// The good clock tick
// =============================================================================
// HOW A CLOCK WIDGET SHOULD KEEP TIME, AND WHY WE DID NOT WRITE OUR OWN
//
// The lazy way to build a clock is "wake up every second and look at the time".
// On a laptop or a handheld that is a wasteful thing to do: every wake-up costs
// battery, and 59 out of 60 of them change nothing on screen, because we do not
// show seconds.
//
// KDE already solved this properly, so we use their solution rather than
// re-inventing a worse one. `Clock` comes from plasma-workspace's own libclock:
//
//   plasma-workspace/libclock/CMakeLists.txt
//       ecm_add_qml_module(clockplugin URI "org.kde.plasma.clock" ...)
//       — that line is where the import name below comes from.
//
//   plasma-workspace/libclock/clock.h
//       "Clock represents a time on a given timezone. Underneath Clock operates
//        on a shared timer that is aligned to update exactly on the second or
//        minute (as appropriate) tracking skews and offsets."
//       It publishes `dateTime` (what we read), `trackSeconds` and `timeZone`.
//
//   plasma-workspace/libclock/alignedtimer.h
//       AlignedTimer::getMinuteTimer() — ONE timer, shared by every clock on the
//       desktop, built on a kernel timer file descriptor rather than a polling
//       loop. So our widget adds no extra wake-ups at all: it rides the same
//       tick KDE's own digital clock rides.
//
//   plasma-workspace/applets/digital-clock/DigitalClock.qml
//       is where we saw it used: `Clock { trackSeconds: ... }` plus
//       `onDateTimeChanged`.
//
// `trackSeconds` is left at its default of false because we never draw seconds,
// which is what puts us on the once-a-minute timer instead of the once-a-second
// one.
//
// This file is loaded through a Loader (see main.qml) purely so that the import
// on the next line cannot take the whole widget down if it ever disappears.
// =============================================================================
import QtQuick

import org.kde.plasma.clock

Item {
    // The one thing main.qml reads.
    readonly property date dateTime: sharedClock.dateTime

    // No timeZone set on purpose: unset means "the system time zone", which is
    // whatever the user chose during setup. Same default as KDE's clock.
    Clock {
        id: sharedClock
    }
}
