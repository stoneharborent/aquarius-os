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

# Set up DaVinci Resolve, the professional video editor (walks you through it)
[group('AquariusOS')]
install-resolve:
    #!/usr/bin/bash
    set -uo pipefail

    echo ""
    echo "=================================================================="
    echo " Setting up DaVinci Resolve on AquariusOS"
    echo "=================================================================="
    echo ""
    echo "DaVinci Resolve is made by Blackmagic Design. Their licence does not"
    echo "allow anyone else to hand out the installer, so AquariusOS cannot"
    echo "include it. You download it from them; this script does the rest."
    echo ""
    echo "What is about to happen, in plain terms:"
    echo ""
    echo "  1. A web page opens. Fill in Blackmagic's form and download the"
    echo "     FREE Linux version. Put it in your Downloads folder."
    echo "  2. This script builds a small, sealed-off Linux environment on"
    echo "     your machine that has everything Resolve needs. Nothing about"
    echo "     your actual system is changed."
    echo "  3. Resolve is installed inside that environment and appears in"
    echo "     your apps like any other program."
    echo ""
    echo "It takes roughly fifteen minutes, nearly all of it downloading."
    echo "You can stop at any time with Ctrl+C and nothing will be left broken."
    echo ""
    read -r -p "Carry on? [y/N] " reply
    case "${reply}" in
        [yY]*) ;;
        *) echo "No problem — nothing was changed."; exit 0 ;;
    esac

    # -- the tools we need ----------------------------------------------------
    # These all ship with AquariusOS. Checking is a courtesy, so that a missing
    # one produces a sentence instead of "command not found".
    for tool in podman distrobox lshw; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            echo ""
            echo "This needs '${tool}', which is missing from this system."
            echo "That should not be possible on AquariusOS — please report it."
            exit 1
        fi
    done

    # -- which graphics card? -------------------------------------------------
    # NVIDIA cards and everyone else need different builds of the environment.
    # NVIDIA uses its own compute libraries; AMD and Intel use OpenCL.
    if lshw -c video 2>/dev/null | grep -qi "driver=nvidia"; then
        echo ""
        echo "NVIDIA graphics detected — using the NVIDIA build."
        DBOX_IMAGE="ghcr.io/zelikos/davincibox:latest"
        DBOX_FLAGS="--device nvidia.com/gpu=all"
    else
        echo ""
        echo "AMD or Intel graphics detected — using the OpenCL build."
        DBOX_IMAGE="ghcr.io/zelikos/davincibox-opencl:latest"
        DBOX_FLAGS=""
    fi

    # -- permission to talk to the graphics card ------------------------------
    # Resolve needs your account to be in the 'render' and 'video' groups. Most
    # accounts already are; if not, this adds them, and the change only takes
    # effect after a restart.
    NEEDS_RESTART=0
    for grp in render video; do
        if ! id -nG "${USER}" | tr ' ' '\n' | grep -qx "${grp}"; then
            echo "Adding you to the '${grp}' group (Resolve needs it)..."
            sudo usermod -aG "${grp}" "${USER}" || true
            NEEDS_RESTART=1
        fi
    done

    # -- get the installer from Blackmagic ------------------------------------
    DOWNLOADS="${HOME}/Downloads"
    mkdir -p "${DOWNLOADS}"

    find_installer() {
        find "${DOWNLOADS}" -maxdepth 2 \
            \( -iname 'DaVinci_Resolve_*_Linux.run' -o -iname 'DaVinci_Resolve_*Linux*.zip' \) \
            -print 2>/dev/null | sort | tail -1
    }

    INSTALLER="$(find_installer)"
    if [ -z "${INSTALLER}" ]; then
        echo ""
        echo "------------------------------------------------------------------"
        echo " Now download DaVinci Resolve"
        echo "------------------------------------------------------------------"
        echo "Opening Blackmagic's download page in your browser."
        echo ""
        echo "  * Choose DaVinci Resolve (the FREE one, not Studio) for LINUX."
        echo "  * Fill in their form — they ask for a name and email."
        echo "  * Save the file into your Downloads folder."
        echo ""
        xdg-open "https://www.blackmagicdesign.com/products/davinciresolve" >/dev/null 2>&1 &
        echo "When the download has finished, come back here and press Enter."
        read -r _
        INSTALLER="$(find_installer)"
    fi

    if [ -z "${INSTALLER}" ]; then
        echo ""
        echo "No DaVinci Resolve installer was found in ${DOWNLOADS}."
        echo "If you saved it somewhere else, move it there and run this again:"
        echo "    ujust install-resolve"
        exit 1
    fi
    echo ""
    echo "Found: ${INSTALLER}"

    # -- unpack it ------------------------------------------------------------
    # Blackmagic hand out a .zip with a .run file inside. The .run file is
    # itself an archive, and it knows how to unpack itself.
    WORK="$(mktemp -d -t resolve-setup-XXXXXX)"
    trap 'rm -rf "${WORK}"' EXIT
    cd "${WORK}" || exit 1

    case "${INSTALLER}" in
        *.zip)
            echo "Unzipping..."
            if command -v unzip >/dev/null 2>&1; then
                unzip -q "${INSTALLER}" -d "${WORK}"
            else
                python3 -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "${INSTALLER}" "${WORK}"
            fi
            RUNFILE="$(find "${WORK}" -maxdepth 2 -iname '*_Linux.run' | head -1)"
            ;;
        *)
            RUNFILE="${INSTALLER}"
            ;;
    esac

    if [ -z "${RUNFILE:-}" ] || [ ! -f "${RUNFILE}" ]; then
        echo "Could not find the Linux installer inside ${INSTALLER}."
        echo "It may be a Windows or Mac download by mistake."
        exit 1
    fi

    echo "Unpacking the installer (this takes a minute)..."
    chmod +x "${RUNFILE}"
    if ! "${RUNFILE}" --appimage-extract >/dev/null 2>&1; then
        echo "The installer would not unpack. It may have downloaded incompletely."
        echo "Delete it from ${DOWNLOADS} and try again."
        exit 1
    fi

    # -- build the sealed-off environment -------------------------------------
    # 'distrobox' makes a container that shares your home folder but has its own
    # system libraries. davincibox is a well-maintained community image whose
    # whole purpose is holding what Resolve needs on Linux.
    echo ""
    echo "Building the environment Resolve runs in..."
    echo "(This downloads roughly 2 GB the first time.)"
    if podman container exists davincibox 2>/dev/null; then
        echo "An environment called 'davincibox' already exists — reusing it."
    else
        # shellcheck disable=SC2086
        if ! distrobox create -i "${DBOX_IMAGE}" ${DBOX_FLAGS} -n davincibox -Y; then
            echo "Could not create the environment. Check your internet connection."
            exit 1
        fi
    fi

    # -- install Resolve into it ----------------------------------------------
    echo ""
    echo "Installing DaVinci Resolve. This is the long part."
    if ! distrobox enter davincibox -- setup-davinci "${WORK}/squashfs-root/AppRun" distrobox; then
        echo ""
        echo "The install did not finish. Nothing on your real system was changed."
        echo "You can safely try again with: ujust install-resolve"
        exit 1
    fi

    echo ""
    echo "=================================================================="
    echo " Done. 'DaVinci Resolve' is now in your apps."
    echo "=================================================================="
    if [ "${NEEDS_RESTART}" -eq 1 ]; then
        echo ""
        echo "One thing left: RESTART THE COMPUTER before opening Resolve."
        echo "Your account was just given permission to use the graphics card,"
        echo "and that only takes effect after a restart."
    fi
    echo ""
    echo "Two things worth knowing about Resolve on Linux:"
    echo ""
    echo "  * The FREE version cannot open ordinary phone/camera MP4 files."
    echo "    That is Blackmagic's licensing, not AquariusOS. The AquariusOS"
    echo "    ingest helper converts those files so they import cleanly."
    echo "  * Even Resolve STUDIO imports MP4s with SILENT AUDIO on Linux."
    echo "    If you own Studio, there is a community plug-in that fixes it:"
    echo "        ujust install-resolve-aac-plugin"
    echo ""

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
        echo "Run this first:   ujust install-resolve"
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

# Fetch the AquariusOS creator apps again if any failed to install
[group('AquariusOS')]
install-creator-apps:
    #!/usr/bin/bash
    set -uo pipefail

    echo ""
    echo "AquariusOS normally installs OBS Studio, Audacity, Firefox and Google"
    echo "Chrome by itself the first time this computer is online. This runs"
    echo "that same job again — useful if you were offline at the time, or if"
    echo "one of them failed."
    echo ""
    echo "Anything you deliberately uninstalled will come back. That is the"
    echo "only thing this can do that you might not want."
    echo ""
    read -r -p "Go ahead? [y/N] " reply
    case "${reply}" in
        [yY]*) ;;
        *) echo "Nothing was changed."; exit 0 ;;
    esac

    sudo rm -f /etc/aquarius/flatpak-preinstall-version
    sudo /usr/libexec/aquarius-flatpak-preinstall
