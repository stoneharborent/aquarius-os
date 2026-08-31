/*
 * AquariusOS Quick Settings — the Game Mode tile (handhelds only)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This is the fourth square in the grid on the handheld image. On every other
 * machine that square is the Performance tile instead. AqPlatform.qml decides
 * which, and explains why the tile adapts at all.
 *
 * ============================================================================
 * WHAT "GAME MODE" MEANS AND WHAT THIS TILE ACTUALLY DOES
 * ============================================================================
 * A Bazzite handheld has two ways to run: the Steam big-picture session it
 * boots into ("Game Mode", which is gamescope, its own compositor), and the KDE
 * desktop you drop out to. This panel only exists on the desktop side, so Game
 * Mode is by definition never running while somebody is looking at this tile.
 *
 * That makes this the one tile in the panel that is not really a switch. It is
 * a door. It always shows as off, and pressing it leaves.
 *
 * ============================================================================
 * ⚠️ PRESSING THIS ENDS THE DESKTOP SESSION — a real risk, flagged on purpose
 * ============================================================================
 * Switching to Game Mode closes the desktop session, and anything open with
 * unsaved work goes with it. There is no confirmation step below.
 *
 * That is a deliberate match to two things rather than an oversight:
 *   - the V2 design, which draws this as an ordinary toggle with no dialog; and
 *   - Bazzite itself, whose "Return to Gaming Mode" desktop launcher does the
 *     same thing on one double-click with no prompt.
 *
 * But a desktop icon takes a deliberate double-click, and this is a single
 * click in a panel a person opened to change the volume. The two are not
 * equally easy to hit by accident. **This needs a decision on the bench** —
 * either it stays as it is, or it grows a confirmation. It is written up as an
 * open question in docs/quick-settings-widget.md rather than being settled
 * unilaterally here.
 *
 * ============================================================================
 * WHERE THE COMMAND COMES FROM
 * ============================================================================
 *   ublue-os/bazzite, system_files/deck/shared/usr/bin/return-to-gamemode
 *
 * That script is Bazzite's own, it ships only on the handheld image, and its
 * entire body is:
 *
 *     steamosctl switch-to-game-mode
 *
 * ⚠️ THREE THINGS THAT LOOK RIGHT AND ARE WRONG, all checked against Bazzite's
 * source. Any of them would produce a tile that does nothing:
 *
 *   1. `steamos-session-select` is a SteamOS command. **Bazzite does not ship
 *      it at all.** Its nearest equivalent, /usr/libexec/os-session-select, is
 *      marked deprecated in its own first three lines and is not on the PATH.
 *
 *   2. The subcommand is `switch-to-game-mode`, with a hyphen before "mode".
 *      `steamosctl switch-to-gamemode` is not a command.
 *
 *   3. Calling `steamosctl` directly would skip Bazzite's wrapper. The wrapper
 *      is what Bazzite's own desktop launcher runs, and going through it means
 *      that if Bazzite ever changes how the switch works, this tile follows
 *      automatically instead of breaking.
 *
 * So: run the wrapper, by its full path, and nothing else.
 */

import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

AqTile {
    id: gameMode

    title: i18n("Game Mode")

    // Always off — see the note above about this being a door, not a switch.
    active: false

    iconName: "input-gamepad-symbolic"

    // The design's own subtitle for this tile.
    //
    // ⚠️ "input-gamepad-symbolic" is the right name and "input-gaming" is not:
    // the latter exists only as a 64px full-colour illustration, so it would
    // put a glossy picture in a 32px monochrome chip. (Despite its filename,
    // input-gamepad at small sizes draws a proper controller in a single
    // colour.)
    subtitle: i18n("Off")

    // This tile is only ever loaded on the handheld image, where Bazzite ships
    // the command. If the command were somehow missing the click would fail
    // quietly and AqRunner would log the non-zero exit, which is the right
    // amount of noise for something this rare.
    available: true

    onToggled: runner.run("/usr/bin/return-to-gamemode")

    // The command runner. Unlike the panel's other users of it, this tile
    // imports it directly rather than through a Loader — it does not need the
    // extra layer, because the tile is ALREADY inside a Loader (every tile is;
    // see AqTileSlot.qml). If plasma5support were missing, this whole file
    // would fail to load and the slot would show a dimmed Game Mode
    // placeholder, which is exactly the behaviour wanted.
    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            const exitCode = data["exit code"]
            if (exitCode !== undefined && exitCode !== 0) {
                console.warn("AquariusOS Quick Settings: switching to Game Mode failed.",
                             source, "exited with", exitCode,
                             "-", (data["stderr"] || "").trim())
            }
            // Mandatory. Connecting to a command that is still connected is a
            // silent no-op, so without this line the tile would work exactly
            // once per login. (Plasma5Support::DataSource::connectSource
            // returns early when the source is already in the list.)
            disconnectSource(source)
        }

        function run(command) {
            disconnectSource(command)
            connectSource(command)
        }
    }
}
