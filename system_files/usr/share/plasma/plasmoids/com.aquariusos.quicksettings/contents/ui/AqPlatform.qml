/*
 * AquariusOS Quick Settings — which machine is this?
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ============================================================================
 * THE PROBLEM THIS SOLVES: the design's fourth tile does not exist everywhere
 * ============================================================================
 * The V2 design's 2x2 grid is Wi-Fi, Bluetooth, Focus and **Game Mode**. Three
 * of those are on every computer. The fourth is not.
 *
 * "Game Mode" means the Steam big-picture session that a handheld boots into —
 * the thing you return to after dropping out to the desktop. It is part of
 * Bazzite's handheld image and it simply does not exist on a desktop or a
 * laptop. A Game Mode tile on Royce's workstation would be a button that
 * cannot do anything, sitting in a quarter of the panel.
 *
 * Leaving the square empty is worse: a 2x2 grid with a hole in it reads as
 * broken rather than as deliberate.
 *
 * ============================================================================
 * THE DECISION, AND WHY — worth reading before changing it
 * ============================================================================
 * The fourth tile is ADAPTIVE. It is Game Mode on a handheld, and a
 * **Performance** toggle (the power profile) on everything else.
 *
 * Performance was chosen as the stand-in because it is the closest thing a
 * desktop has to the same idea: one switch that says "stop being careful, go
 * fast." A gamer on a handheld presses Game Mode to play; a creator at a
 * workstation presses Performance before a render. The tile keeps its meaning
 * even though the mechanism is different, which is why it can share a slot
 * without the panel feeling inconsistent between machines.
 *
 * Alternatives that were considered and rejected:
 *   - Night Light / blue light. Real, and available everywhere, but it is a
 *     comfort setting rather than a "the machine is about to work hard" one,
 *     and it does not sit naturally beside Wi-Fi and Bluetooth.
 *   - Airplane mode. Duplicates the Wi-Fi and Bluetooth tiles either side of
 *     it, which is the one thing a four-tile grid cannot afford.
 *   - Just leaving three tiles on desktops. Rejected above.
 *
 * ============================================================================
 * ⚠️ THE CHOICE IS MADE WHEN THE PANEL OPENS, NOT WHEN THE IMAGE IS BUILT
 * ============================================================================
 * This matters and it is a deliberate constraint. AquariusOS builds three
 * images from ONE recipe, and the standing rule in the Containerfile is that
 * there is no per-variant branching — everything we layer is the same on all
 * three, and the handheld build needed no branch at all when it was added.
 *
 * Deciding this tile at build time would break that rule for the sake of one
 * square in one widget. So the widget ships identically everywhere and works
 * out where it is running when somebody opens it.
 */

import QtQuick

QtObject {
    id: platform

    // -------------------------------------------------------------------------
    // Is this a handheld?
    // -------------------------------------------------------------------------
    // Set once, shortly after the panel is created. Starts false so that a
    // desktop — the common case — never flickers through a Game Mode tile on
    // its way to the right answer.
    property bool isHandheld: false

    // What the fourth slot loads, and what its placeholder says if that fails.
    readonly property string fourthTileSource:
        isHandheld ? "TileGameMode.qml" : "TilePowerProfile.qml"

    readonly property string fourthTileFallbackTitle:
        isHandheld ? i18n("Game Mode") : i18n("Performance")

    readonly property string fourthTileFallbackIcon:
        isHandheld ? "input-gamepad-symbolic" : "speedometer-symbolic"

    // -------------------------------------------------------------------------
    // HOW THE TEST WORKS
    // -------------------------------------------------------------------------
    // Every Universal Blue image — which is what Bazzite is, and therefore what
    // AquariusOS is — writes a small file describing itself:
    //
    //     /usr/share/ublue-os/image-info.json
    //
    // and it contains an "image-name". Ours are "aquarius-os", "aquarius-os-nvidia"
    // and "aquarius-os-deck", so the handheld is the one with "deck" in it.
    //
    // ⚠️ This is not a convention invented here. It is the same test Bazzite
    // itself uses to decide whether a machine is a handheld — its own
    // bazzite-user-setup does `if [[ $IMAGE_NAME =~ "deck" ]]` against this
    // exact field, and that script is what puts the "Return to Gaming Mode"
    // launcher on the desktop in the first place. Matching Bazzite's test means
    // this tile appears exactly when that launcher does, which is the behaviour
    // we want.
    //
    // Reading it with XMLHttpRequest is how QML reads a local file. It looks
    // like a web request and is not one — a `file://` URL is read straight off
    // the disk.
    function detectPlatform() {
        const request = new XMLHttpRequest()

        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE) {
                return
            }

            // Anything that goes wrong here — the file missing, unreadable, or
            // not being JSON — means "assume this is not a handheld", which is
            // the safe answer: the Performance tile works on a handheld too
            // (it is a Linux machine with a power profile daemon like any
            // other), whereas a Game Mode tile on a desktop would not.
            //
            // Note there is no status check. For a `file://` URL Qt reports
            // status 0 on success rather than 200, so testing for 200 here
            // would fail on every machine. Whether the text parses is the
            // honest test.
            try {
                const info = JSON.parse(request.responseText)
                const imageName = info["image-name"] || ""
                platform.isHandheld = imageName.indexOf("deck") !== -1
            } catch (error) {
                platform.isHandheld = false
            }
        }

        try {
            request.open("GET", "file:///usr/share/ublue-os/image-info.json")
            request.send()
        } catch (error) {
            platform.isHandheld = false
        }
    }

    // -------------------------------------------------------------------------
    // Opening the full Settings app — the "All settings" link at the bottom
    // -------------------------------------------------------------------------
    function openSystemSettings() {
        if (runnerLoader.status === Loader.Ready && runnerLoader.item) {
            // `systemsettings` is the command KDE's own System Settings desktop
            // entry runs. Launching the app rather than jumping to a particular
            // settings page is what the design's "All settings" means — it is
            // the way OUT of the quick panel into the full thing.
            runnerLoader.item.run("systemsettings")
        } else {
            console.warn("AquariusOS Quick Settings: cannot open System Settings",
                         "because the command runner did not load. See AqRunner.qml.")
        }
    }

    function runCommand(command) {
        if (runnerLoader.status === Loader.Ready && runnerLoader.item) {
            runnerLoader.item.run(command)
            return true
        }
        return false
    }

    // The thing that can actually start a program, held at arm's length. See
    // the top of AqRunner.qml for why it is loaded rather than imported.
    property Loader runnerLoader: Loader {
        source: "AqRunner.qml"
    }

    Component.onCompleted: detectPlatform()
}
