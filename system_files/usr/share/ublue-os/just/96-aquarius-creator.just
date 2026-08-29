# vim: set ft=make :
#
# ==============================================================================
# AquariusOS — creator app recipes
# ==============================================================================
# Plain English: these are the jobs you get by typing `ujust` in a terminal.
# Each one is a single task written to be run by somebody who has never used
# Linux before: it explains what it is about to do, it asks before doing
# anything big, and it says what happened.
#
# This file is added to the `ujust` menu by build_files/creator-apps.sh.
# The beginner write-up of all of it lives with the OS source, in
# docs/creator-apps.md at https://github.com/stoneharborent/aquarius-os
# ==============================================================================

# ==============================================================================
# DAVINCI RESOLVE — and why our recipe is NOT called `install-resolve`
# ==============================================================================
# The walkthrough itself is a real script:
#
#     /usr/libexec/aquarius-install-resolve
#
# and the recipe below only calls it. It moved out of this file on 2026-08-28,
# after a bench test on real hardware, and the reason is worth knowing before
# anybody "tidies" the obvious name back in.
#
# WHAT HAPPENED
# The tester ran `ujust install-resolve` and got a walkthrough that opened
# Blackmagic's download page and then, a second later, said:
#
#     Installer not found
#     Please place the file DaVinci_Resolve_*_Linux.run in /home/… or /home/…/Downloads
#
# and quit — the exact failure ours exists to prevent. That message is not ours.
# It comes from
#
#     /usr/share/ublue-os/just/30-distrobox.just
#
# which is part of the `ublue-os-just` package that every Universal Blue image
# installs, AquariusOS included. (Bazzite used to have its own copy and deleted
# it in September 2024, precisely because upstream now provides it — which is
# why grepping the Bazzite repo for it finds nothing.)
#
# WHY OURS LOST, AND WHY IT ALWAYS WILL
# `ujust` runs one big justfile that imports every recipe file in number order,
# with `set allow-duplicate-recipes := true`, so a repeated name is not an error
# — it is silently resolved. And `just`'s rule for two imports at the same depth
# is (from the just manual, "Imports"):
#
#     "the one from the earlier import will override the one from the later
#      import"
#
# — which the manual itself calls a bug it cannot fix without breaking
# compatibility (casey/just#2540). `30-distrobox.just` is imported around nine
# lines before our `96-…` file. This is not a coin toss we sometimes lose. From
# number 96 we can NEVER win. So there is no point defining `install-resolve`
# here at all, and it is deliberately not defined.
#
# WHAT WE DO INSTEAD
# Nothing AquariusOS puts in front of a user goes through `ujust` for this:
#
#   the first-login tick-box window  → /usr/libexec/aquarius-install-resolve
#   the app grid entry               → /usr/libexec/aquarius-install-resolve
#   the terminal                     → `ujust aquarius-resolve`, below
#
# `ujust install-resolve` still exists and still runs upstream's version. It is
# not broken, it is just not ours and not as gentle. Our documentation says
# `aquarius-resolve`.
#
# ⚠️ IF YOU ARE TEMPTED TO FIGHT FOR THE NAME, READ THIS FIRST.
# There are ways to win it — importing this file before 30-distrobox, or
# appending the recipe to the top level of /usr/share/ublue-os/justfile, which
# does override imports. Both were considered and rejected: they mean editing a
# file the base image owns, on every build, and a base-image change to import
# order becomes a silent regression.
#
# ⚠️ AND NEVER USE THESE THREE NAMES: `install-davinci`, `install-davinci-resolve`,
# `install-resolve-studio`. Upstream defines them as ALIASES, and a recipe whose
# name collides with an alias is a HARD ERROR that `allow-duplicate-recipes`
# does not cover — it would take down the ENTIRE `ujust` menu on the shipped
# image, not just that one recipe.
# ==============================================================================

# Set up DaVinci Resolve, the professional video editor (walks you through it)
[group('AquariusOS')]
aquarius-resolve:
    #!/usr/bin/bash
    exec /usr/libexec/aquarius-install-resolve

# Add the community AAC audio plug-in to DaVinci Resolve STUDIO (not the free one)
[group('AquariusOS')]
install-resolve-aac-plugin:
    #!/usr/bin/bash
    set -uo pipefail

    # The pinned release we install, and the fingerprint it must match. Both are
    # written down here on purpose: nothing is downloaded and run without being
    # checked against a value a human put in this file.
    PLUGIN_URL="https://github.com/Toxblh/davinci-linux-aac-codec/releases/download/v1.0.1/aac_encoder_plugin-linux-bundle.tar.gz"
    PLUGIN_SHA="fc0ef6af76f33b3d2a8d4b03385837e8f014a35dbd2afb311a82c5d57c59136f"

    echo ""
    echo "=================================================================="
    echo " The AAC audio plug-in for DaVinci Resolve Studio"
    echo "=================================================================="
    echo ""
    echo "The problem it fixes: on Linux, DaVinci Resolve cannot handle AAC"
    echo "audio — the kind almost every phone and camera records. Even the paid"
    echo "Studio version imports those clips with silent audio and cannot export"
    echo "normal MP4s. That is Blackmagic's licensing and no operating system"
    echo "can change it from the outside."
    echo ""
    echo "What this does: installs a free community plug-in that teaches Resolve"
    echo "AAC by way of ffmpeg."
    echo ""
    echo "Read this part before saying yes:"
    echo ""
    echo "  * It only works in Resolve STUDIO. The free version cannot load"
    echo "    plug-ins at all, so this will do nothing for you."
    echo "  * It is written by a third party, Toxblh, and is published with no"
    echo "    licence attached. AquariusOS therefore does NOT ship it. If you"
    echo "    say yes, YOUR computer downloads it from GitHub, and the download"
    echo "    is checked against a known fingerprint before anything is used."
    echo "  * Source: https://github.com/Toxblh/davinci-linux-aac-codec"
    echo ""
    read -r -p "Download and install it? [y/N] " reply
    case "${reply}" in
        [yY]*) ;;
        *) echo "Nothing was downloaded."; exit 0 ;;
    esac

    if ! podman container exists davincibox 2>/dev/null; then
        echo ""
        echo "DaVinci Resolve does not appear to be set up yet on this machine."
        echo "Run this first:   ujust aquarius-resolve"
        exit 1
    fi

    WORK="$(mktemp -d -t resolve-aac-XXXXXX)"
    trap 'rm -rf "${WORK}"' EXIT

    echo "Downloading..."
    if ! curl --retry 3 -fsSL -o "${WORK}/plugin.tar.gz" "${PLUGIN_URL}"; then
        echo "The download failed. Check your internet connection and try again."
        exit 1
    fi

    GOT="$(sha256sum "${WORK}/plugin.tar.gz" | cut -d' ' -f1)"
    if [ "${GOT}" != "${PLUGIN_SHA}" ]; then
        echo ""
        echo "STOPPED: the downloaded file is not the one this recipe expects."
        echo "  expected ${PLUGIN_SHA}"
        echo "  actual   ${GOT}"
        echo ""
        echo "Nothing has been installed. This usually means the project"
        echo "published a new version; do not work around it by hand."
        exit 1
    fi
    echo "Fingerprint checked — this is the expected file."

    tar -xzf "${WORK}/plugin.tar.gz" -C "${WORK}"
    BUNDLE="${WORK}/aac_encoder_plugin.dvcp.bundle"
    if [ ! -d "${BUNDLE}" ]; then
        echo "The download did not contain the plug-in. Nothing was installed."
        exit 1
    fi

    # Resolve looks for plug-ins in /opt/resolve/IOPlugins, and Resolve lives
    # inside the davincibox environment, so the file has to be copied in there.
    # We copy the one file ourselves rather than running the project's installer
    # script — same result, and nothing of theirs executes on your machine.
    echo "Installing the plug-in into DaVinci Resolve..."
    if ! distrobox enter davincibox -- bash -c 'sudo mkdir -p /opt/resolve/IOPlugins'; then
        echo "Could not prepare Resolve's plug-in folder."
        exit 1
    fi
    if ! distrobox enter davincibox -- bash -c "sudo cp -r '${BUNDLE}' /opt/resolve/IOPlugins/"; then
        echo "Could not copy the plug-in into place."
        exit 1
    fi

    # The plug-in leans on ffmpeg's libraries. They are normally already in the
    # environment; if not, this puts them there.
    distrobox enter davincibox -- bash -c 'command -v ffmpeg >/dev/null 2>&1 || sudo dnf install -y ffmpeg-free' || true

    echo ""
    echo "Done. Close DaVinci Resolve completely and open it again."
    echo "AAC should now appear as an audio option when you export."
    echo ""

# Pick which creator apps to add (OBS, Audacity, Blender, DaVinci Resolve)
[group('AquariusOS')]
install-creator-apps:
    #!/usr/bin/bash
    set -uo pipefail

    # This is the same tick-box window AquariusOS shows on the first login, and
    # it is deliberately the SAME script rather than a copy of what it does —
    # one place to fix, one behaviour to explain. "--again" tells it to ignore
    # the note recording that the question was already asked.
    #
    # It puts a window on screen, so it needs a desktop. Run from a text-only
    # login there is nothing sensible it could do, and saying so is kinder than
    # a Qt error.
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        echo "This one opens a window, so it needs to be run from the desktop."
        echo "Log in normally and look for \"Install Creator Apps\" in your apps."
        exit 1
    fi

    exec /usr/libexec/aquarius-creator-apps-offer --again
