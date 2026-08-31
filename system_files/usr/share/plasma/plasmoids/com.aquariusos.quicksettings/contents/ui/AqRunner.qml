/*
 * AquariusOS Quick Settings — running a command
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A widget cannot start a program by itself. This file is the one place that
 * can, and everything in the panel that needs to launch something goes through
 * it: the "All settings" link, and the Game Mode tile on a handheld.
 *
 * ============================================================================
 * WHY IT IS ITS OWN FILE
 * ============================================================================
 * It is loaded by a Loader, like the tiles are, and for the same reason. The
 * module it imports, `org.kde.plasma.plasma5support`, is a compatibility layer
 * KDE kept when Plasma 5 became Plasma 6 — it is the supported way for a QML
 * widget to run a command, and it is what community widgets use, but "kept for
 * compatibility" is not a promise to keep it forever.
 *
 * Quarantining it here means that if it ever goes away, the cost is that the
 * "All settings" link stops responding and the Game Mode tile greys out. The
 * panel still opens and every other control still works. If this import sat in
 * the panel file instead, its removal would blank the whole thing.
 *
 * ============================================================================
 * THE IDIOM BELOW IS ODD-LOOKING AND IT IS DELIBERATE
 * ============================================================================
 * This is not a "run this command" function in the normal sense. What Plasma
 * gives QML is a data source: you *connect* to a command as though you were
 * subscribing to a feed, it runs, and the output arrives as an event.
 *
 * That has one consequence worth knowing about, because it looks like a bug:
 * connecting to a command that is ALREADY connected does nothing at all. So if
 * a person clicked "All settings" twice, the second click would be silently
 * ignored forever after. Disconnecting as soon as the result arrives — which is
 * what `onNewData` does below — is what keeps the same command runnable again.
 */

import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Plasma5Support.DataSource {
    id: runner

    // "executable" is the built-in source that runs shell commands. The other
    // engines (time, weather, system monitoring) are not used here.
    engine: "executable"

    // Nothing connected to start with. Commands are added as they are run.
    connectedSources: []

    onNewData: function (source, data) {
        // `data` carries "exit code", "stdout" and "stderr". Nothing this
        // widget runs produces output worth showing a person — System Settings
        // opens a window, and the Game Mode command replaces the whole session
        // — so the result is only inspected to complain into the log when a
        // command fails. A person seeing nothing happen deserves to have the
        // reason recorded somewhere.
        const exitCode = data["exit code"]
        if (exitCode !== undefined && exitCode !== 0) {
            console.warn("AquariusOS Quick Settings: the command", source,
                         "exited with code", exitCode,
                         "-", (data["stderr"] || "").trim())
        }

        // Always disconnect, success or failure — see the note above about the
        // same command otherwise never running a second time.
        disconnectSource(source)
    }

    // The only function callers need.
    //
    // ⚠️ Everything passed here is run by a shell, so it must never be built
    // out of anything a person or a file can influence. In practice this widget
    // only ever passes fixed strings written into its own source, which is the
    // only safe way to use it.
    function run(command) {
        // Disconnect first in case a previous run of the same command is
        // somehow still connected; connecting twice is the no-op described
        // above.
        disconnectSource(command)
        connectSource(command)
    }
}
