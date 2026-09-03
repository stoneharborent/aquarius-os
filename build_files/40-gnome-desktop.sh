#!/usr/bin/bash
# ==============================================================================
# STEP 4 — The desktop: a short list of GNOME, chosen on purpose
# ==============================================================================
# WHY GNOME IS HERE AT ALL
#
# The desktop AquariusOS is being built towards is our own — the Aquarius
# Desktop, a shell we write, running on the labwc compositor. That is Phase R2.
#
# GNOME is the FALLBACK, and it is permanent. The rule (standing decision 2)
# is: there is always a complete, stock, working desktop installed beside ours,
# so that a bad night's work on the Aquarius Session can never leave Royce with
# a machine he cannot log into. It is also what he approved the look of on the
# bench on 2026-08-31, so for now it is the desktop AquariusOS boots into.
#
# WHY THIS IS A LIST AND NOT `dnf group install "GNOME Desktop"`
#
# Because the group is enormous and most of it is not for this machine. It
# includes a mail client, a calendar, a chat app, a music player, a photo
# manager, a maps app, a weather app, and a games collection. On a machine whose
# job is editing video, every one of those is something to uninstall, something
# to update, and something to look at in the app grid and wonder about.
#
# So this is a hand-written list. The rule for adding to it: does the machine
# fail at something a person will actually do without this? A file manager and
# a terminal pass that test. A weather app does not.
#
# ⚠️ WHAT IS DELIBERATELY MISSING, so nobody thinks it was forgotten:
#
#   printing and scanning       Not on this machine's job list. It is one
#                               `dnf install cups` away for anyone who needs it,
#                               and CUPS pulls in a surprising amount.
#   gnome-initial-setup         The welcome wizard. The installer already asks
#                               for a name and password; running a second wizard
#                               that asks similar questions reads as a bug.
#   evolution, geary, contacts, calendar, maps, weather, photos, music, games,
#   gnome-boxes, gnome-connections, simple-scan, rhythmbox, totem
#                               All in the GNOME group. None of them are why
#                               anybody would install this operating system.
#   a shell theme               Deliberately never. See 50-aquarius-desktop.sh.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# The desktop itself
# ------------------------------------------------------------------------------
# gnome-shell is the desktop: the top bar, the overview, the app grid, the
# notifications. mutter underneath it is the compositor — the thing that
# actually draws windows on the screen. gnome-session-wayland-session is the
# small file that tells the login screen "there is a GNOME session here, and
# here is how to start it"; without it GDM shows a login screen with nothing to
# log into.
say "GNOME Shell"
aq_dnf install \
    gnome-shell \
    mutter \
    gnome-session-wayland-session \
    gnome-settings-daemon \
    gnome-keyring \
    gnome-menus \
    gsettings-desktop-schemas \
    adwaita-icon-theme \
    adwaita-cursor-theme

# ------------------------------------------------------------------------------
# Settings and system tools
# ------------------------------------------------------------------------------
# gnome-control-center is the Settings app — including the About page that the
# next step brands. gnome-tweaks is where a person finds the settings GNOME
# hides, and a machine set up for someone coming from KDE needs it on day one.
say "Settings and system tools"
aq_dnf install \
    gnome-control-center \
    gnome-tweaks \
    gnome-disk-utility \
    gnome-system-monitor \
    gnome-logs \
    dconf \
    dconf-editor \
    glib2

# ------------------------------------------------------------------------------
# Files, and the things files open in
# ------------------------------------------------------------------------------
# nautilus is the file manager. nautilus-python is what lets us add the "Make
# Editor-Ready" item to its right-click menu further down the build — without
# it the extension is a file nothing reads.
#
# gvfs is the piece that makes drives, phones, cameras and network shares appear
# in the sidebar. Each -something package is one kind of thing it can mount, and
# leaving one out means that kind silently does not appear:
#   -mtp        Android phones
#   -gphoto2    cameras plugged in over USB
#   -smb        Windows / NAS shares
#   -afc        iPhones and iPads
say "Files, drives and phones"
aq_dnf install \
    nautilus \
    nautilus-python \
    gvfs \
    gvfs-mtp \
    gvfs-gphoto2 \
    gvfs-smb \
    gvfs-afc \
    gvfs-nfs \
    gvfs-archive \
    file-roller \
    file-roller-nautilus

# ------------------------------------------------------------------------------
# The small handful of apps
# ------------------------------------------------------------------------------
# ptyxis is Fedora's terminal (it replaced GNOME Terminal as the default in
# Fedora 42 and it is container-aware, which matters on a machine built around
# toolbox and distrobox). loupe is the image viewer, papers the PDF reader —
# both are the current GNOME apps, renamed from Eye of GNOME and Evince.
say "The small handful of apps"
aq_dnf install \
    ptyxis \
    loupe \
    papers \
    gnome-text-editor \
    gnome-calculator \
    gnome-characters \
    gnome-font-viewer \
    baobab

# gnome-software is the app store. On this machine it is a Flatpak store and
# nothing else — there is no such thing as installing an RPM onto a running
# AquariusOS, because the system is an image that gets replaced wholesale.
say "The app store (Flatpak only)"
aq_dnf install gnome-software

# Firefox from Fedora's own package for now. A Flatpak Firefox is arguably the
# better long-term answer (faster updates, better sandbox) but it cannot be
# preinstalled into an image — Flatpaks install onto the machine, not into the
# picture of it. Revisit in R3 with the rest of the creator apps.
say "A web browser"
aq_dnf install firefox

# ------------------------------------------------------------------------------
# Extensions
# ------------------------------------------------------------------------------
# Four, all packaged by Fedora, none downloaded from the internet at build time.
#
#   dash-to-dock          the dock along the bottom of the screen. GNOME's own
#                         dash only exists inside the overview; Royce wants a
#                         dock on the desktop the way macOS has one.
#   appindicator          lets older apps put an icon in the top bar. Without
#                         it several creator tools lose their tray icon entirely.
#   caffeine              stops the screen sleeping. On a machine that exports
#                         video for an hour at a time this is not a nicety.
#   gsconnect             phone pairing: notifications, file send, clipboard.
#
# ⚠️ THIS IS A CHANGE FROM THE BAZZITE LINE, AND A SIMPLIFICATION.
# On Bazzite we downloaded a specific Dash to Dock release as a tarball,
# checked its fingerprint and compiled it, because Bazzite did not package it.
# Fedora 44 does package it — version 105, which declares support for GNOME
# Shell 50, which is what Fedora 44 ships — and the package puts its settings
# description in /usr/share/glib-2.0/schemas where our defaults need it. So the
# whole download-and-compile step is gone. If you go looking for
# build_files/gnome-extensions.sh, that is why it no longer exists.
#
# Also gone with Bazzite: hotedge, logomenu, add-to-steam, restartto and
# bazaar-integration. Those are packaged by Universal Blue, not by Fedora, and
# none of them exist here. The one that is a real loss is Logo Menu — the
# AquariusOS mark in the top-left corner. Getting it back is an R2 job; the OS
# still carries its identity in the About page, the login screen, the wallpaper
# and os-release.
say "GNOME Shell extensions"
aq_dnf install \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-caffeine \
    gnome-shell-extension-gsconnect

# ------------------------------------------------------------------------------
# Turn the login screen on
# ------------------------------------------------------------------------------
# Two separate things, and forgetting either one gives a machine that boots to a
# black screen or a text prompt:
#
#   set-default graphical.target   "when you start, go all the way to a desktop"
#   enable gdm                     "and the way you get there is GDM"
say "Making the machine boot to a desktop"
systemctl set-default graphical.target
systemctl enable gdm.service

# ------------------------------------------------------------------------------
# Check the desktop is really in there
# ------------------------------------------------------------------------------
say "Checking the desktop"

aq_installed \
    gnome-shell \
    mutter \
    gnome-session-wayland-session \
    gnome-control-center \
    gnome-tweaks \
    nautilus \
    nautilus-python \
    ptyxis \
    loupe \
    papers \
    gnome-text-editor \
    gnome-calculator \
    gnome-software \
    firefox \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-caffeine \
    gnome-shell-extension-gsconnect \
    gdm \
    dconf \
    glib2

# The two commands the later steps depend on. glib-compile-schemas belongs to
# glib2 (not glib2-devel — a trap worth knowing) and without it none of the
# AquariusOS defaults in the next step can be applied.
for cmd in gnome-shell gsettings glib-compile-schemas dconf; do
    if aq_have "${cmd}"; then ok "${cmd} is on the path"; else bad "${cmd} is missing"; fi
done

echo "This image has: $(gnome-shell --version)"

# The session file GDM reads. If this is missing the login screen appears and
# offers nothing to log in to — a symptom that looks like a broken graphics
# driver and is not.
AQ_SESSION_FILE="/usr/share/wayland-sessions/gnome.desktop"
if [ -r "${AQ_SESSION_FILE}" ]; then
    ok "$(basename "${AQ_SESSION_FILE}") is installed — GDM has a session to offer"
else
    bad "${AQ_SESSION_FILE} is missing — the login screen would have nothing to log into"
fi
echo "Sessions GDM can offer:"
ls -l /usr/share/wayland-sessions/ /usr/share/xsessions/ 2> /dev/null || true

# Boot target and login screen, read back rather than assumed.
AQ_DEFAULT_TARGET="$(systemctl get-default)"
if [ "${AQ_DEFAULT_TARGET}" = "graphical.target" ]; then
    ok "the machine boots to a desktop (default target is graphical.target)"
else
    bad "default target is '${AQ_DEFAULT_TARGET}' — this machine would boot to a text prompt"
fi

if systemctl is-enabled gdm.service > /dev/null 2>&1; then
    ok "GDM is switched on"
else
    bad "GDM is not switched on — nothing would draw a login screen"
fi

# All four extensions have to be where GNOME looks for them, under their own
# id. A package can install fine and put its files somewhere GNOME does not
# read, and the symptom is an extension that is simply absent with no error.
say "Checking the extensions are where GNOME looks"
for uuid in \
    dash-to-dock@micxgx.gmail.com \
    appindicatorsupport@rgcjonas.gmail.com \
    caffeine@patapon.info \
    gsconnect@andyholmes.github.io; do
    d="/usr/share/gnome-shell/extensions/${uuid}"
    if [ -r "${d}/metadata.json" ]; then
        ok "${uuid}"
    else
        bad "${uuid} is not installed at ${d}"
    fi
done

# Dash to Dock has to declare support for THIS GNOME Shell or the shell refuses
# to load it — silently, with no dock and no error message anywhere.
gnome-shell --version > /tmp/aq-shell-version.txt
AQ_SHELL_MAJOR="$(awk '{print $3}' /tmp/aq-shell-version.txt | cut -d. -f1)"
AQ_D2D_META="/usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/metadata.json"
if [ -r "${AQ_D2D_META}" ]; then
    if python3 - "${AQ_D2D_META}" "${AQ_SHELL_MAJOR}" <<'PY'; then
import json, sys
meta = json.load(open(sys.argv[1]))
versions = [str(v) for v in meta["shell-version"]]
print(f"       Dash to Dock {meta['version']} supports GNOME Shell {', '.join(versions)}")
sys.exit(0 if sys.argv[2] in versions else 1)
PY
        ok "Dash to Dock supports GNOME Shell ${AQ_SHELL_MAJOR}"
    else
        bad "Dash to Dock does not list GNOME Shell ${AQ_SHELL_MAJOR} — the dock would not appear"
    fi
fi

# Our dock defaults need the dock's settings description installed system-wide.
# If the extension keeps a private copy instead, the private copy wins and every
# AquariusOS dock default is ignored.
AQ_D2D_SCHEMA="/usr/share/glib-2.0/schemas/org.gnome.shell.extensions.dash-to-dock.gschema.xml"
if [ -r "${AQ_D2D_SCHEMA}" ]; then
    ok "the dock's settings description is installed system-wide"
else
    bad "${AQ_D2D_SCHEMA} is missing — our dock defaults would have nothing to attach to"
fi
if [ -e "/usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/schemas/gschemas.compiled" ]; then
    bad "the dock keeps a private settings copy — it would override every AquariusOS dock default"
else
    ok "the dock has no private settings copy (correct — ours win)"
fi

aq_finish "The GNOME desktop"
