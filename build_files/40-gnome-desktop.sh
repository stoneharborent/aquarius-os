#!/usr/bin/bash
# ==============================================================================
# STEP 4 — The desktop: a short list of GNOME, chosen on purpose
# ==============================================================================
# WHY GNOME IS HERE AT ALL
#
# ⚠️ THIS ANSWER CHANGED ON 15 SEPTEMBER 2026. GNOME used to be the FALLBACK:
# a complete, stock desktop installed beside our own, so that a bad night's
# work on the Aquarius Session could never leave Royce with a machine he could
# not log into.
#
# There is no "ours" any more. Royce retired the Aquarius Session and asked for
# GNOME and KDE Plasma side by side, so he can use each one for real and pick
# (../docs/decision-2026-09-15-two-desktops.md). GNOME is now one of the two
# desktops AquariusOS ships, not a safety net for a third — and it is the one a
# brand-new account lands in, because it is the look Royce approved on the bench
# on 2026-08-31 and because every AquariusOS window is a GTK 4 window.
#
# The other desktop is step 4b, build_files/41-kde-desktop.sh, which is written
# to match this file line for line.
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
#
# The last three are AquariusOS's desktop-identity defaults (Phase R5,
# 2026-09-05). They are GNOME's own themes, named on purpose so the defaults in
# zz1-aquarius-10-look.gschema.override have a real theme to point at and the
# CI check that reads those settings back can never pass over a missing file:
#   adwaita-icon-theme        the app icons  (icon-theme='Adwaita')
#   adwaita-cursor-theme      the pointer    (cursor-theme='Adwaita')
#   sound-theme-freedesktop   the sounds     (org.gnome.desktop.sound
#                             theme-name='freedesktop')
# Why these and not a bespoke set: docs/restart/desktop-identity.md.
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
    adwaita-cursor-theme \
    sound-theme-freedesktop

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

# Work around the GTK window-icon crash seen when closing Files merge dialogs.
# Both app-menu launch and D-Bus activation must use the same launcher.
# Keep Fedora's translated entries and actions. See docs/restart/files-crash.md.
say "Protecting Files from the GTK window-icon crash"
install -Dm755 /ctx/system_files/usr/libexec/aquarius-files /usr/libexec/aquarius-files
python3 /ctx/build_files/wire-files-launchers.py \
    /usr/share/applications/org.gnome.Nautilus.desktop \
    /usr/share/dbus-1/services/org.gnome.Nautilus.service
cmp /ctx/system_files/usr/libexec/aquarius-files /usr/libexec/aquarius-files
test -x /usr/libexec/aquarius-files
python3 /ctx/tests/test-files-launchers.py

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

# ------------------------------------------------------------------------------
# The English language pack — and why a missing one BROKE AN UPDATE
# ------------------------------------------------------------------------------
# ⚠️ THIS IS THE 2026-09-04 BENCH FAULT. READ IT BEFORE REMOVING THIS.
#
# On the bench, GNOME noticed that the English language pack was not installed
# and offered — politely, in a notification — to add it. Royce said yes. GNOME
# handed the job to rpm-ostree, which added the package as a LAYER on top of the
# operating system image.
#
# On an image-based system like this one, a layered package is a modification of
# the deployment, and `bootc upgrade` refuses to touch a deployment that has
# been modified. So the machine stopped being able to update itself, and the
# message it gave — "Deployment contains local rpm-ostree modifications" — says
# nothing at all about a language pack.
#
# The fix is not to teach people that message. It is to make GNOME never ask:
# ship the language pack in the image, where it belongs.
#
#   langpacks-en       the meta-package GNOME's prompt is asking for. It pulls
#                      in the translations, the spell-checking dictionary and
#                      the locale data for English.
#   langpacks-core-en  the small half of the same thing — the locale itself.
#                      Named separately because it is a separate package and
#                      "it comes in as a dependency" is exactly the kind of
#                      accident this repository asks for by name instead.
#
# The recovery for a machine already in this state is in
# docs/restart/bench-rebase.md, under "The update refuses to run".
say "The English language pack (so GNOME never offers to layer it)"
aq_dnf install \
    langpacks-en \
    langpacks-core-en

# gnome-software is the app store. On this machine it is a Flatpak store and
# nothing else — there is no such thing as installing an RPM onto a running
# AquariusOS, because the system is an image that gets replaced wholesale.
say "The app store (Flatpak only)"
aq_dnf install gnome-software

# ------------------------------------------------------------------------------
# ...and taking the rpm-ostree plug-in straight back out again
# ------------------------------------------------------------------------------
# ⚠️ IF YOU LEAVE THIS OUT, THE MACHINE ASKS FOR A PASSWORD ROUGHLY ONCE AN HOUR,
#    FOR NOTHING. That is not a theory — it is what the bench PC did, and the
#    logs named the culprit: `gnome-software --gapplication-service` asking
#    polkit for `org.projectatomic.rpmostree1.upgrade`, ten times in five days
#    (bench finding, 2026-09-24).
#
# WHAT IS ACTUALLY GOING ON
#
# GNOME Software is built out of plug-ins, one per kind of thing it can install:
# one for Flatpaks, one for firmware, one for RPMs, and one for rpm-ostree — the
# "the whole operating system is one image" kind, which is what AquariusOS is.
# That last plug-in ships as its own little package, `gnome-software-rpm-ostree`.
#
# Nothing REQUIRES that package. It arrives because `gnome-software` merely
# *recommends* it, and dnf installs recommendations unless it is told not to.
# So it lands on the image without anybody choosing it.
#
# And then it does the wrong thing. Left switched on it periodically asks
# rpm-ostree to refresh its repositories and work out an upgrade — and both of
# those are privileged jobs, so polkit puts a password box on Royce's screen.
# He types his password, and NOTHING HAPPENS, because AquariusOS does not
# update that way. Updates here come from `bootc upgrade` through our own
# updater (/usr/libexec/aquarius-updater, build_files/77-updater.sh). The
# password box is pure cost: an interruption in exchange for no outcome.
#
# WHY REMOVING IT IS THE RIGHT FIX AND NOT A HACK
#
# The comment three lines above this block already says what this app is meant
# to be: "a Flatpak store and nothing else — there is no such thing as
# installing an RPM onto a running AquariusOS". The plug-in contradicts that
# sentence. Taking it out is not a workaround for the prompt; it is making the
# image match the decision that was already written down.
#
# The package contains exactly ONE file — the plug-in itself — so there is no
# collateral damage, and nothing on the system depends on it. GNOME Software
# keeps every other plug-in and carries on being the Flatpak store.
#
# ⚠️ DO NOT "FIX" THIS INSTEAD BY GIVING rpm-ostree A PASSWORD-FREE POLKIT RULE.
#    That would trade one prompt for a machine where anything can start an
#    operating-system upgrade with no one looking. The prompt is not the
#    problem; the useless request behind it is.
#
# `--no-autoremove` is deliberate. Without it dnf also sweeps up anything that
# was pulled in for this package and now looks unused — and the libraries under
# it are shared with rpm-ostree and bootc, which this operating system very much
# still needs. We are taking out one plug-in, not opening a question about what
# else might go with it.
say "Removing GNOME Software's rpm-ostree plug-in (it asks for a password and does nothing)"
aq_dnf remove --no-autoremove gnome-software-rpm-ostree

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
#
# ⚠️ AND A THIRD THING SINCE 15 SEPTEMBER 2026, BECAUSE THE FIRST TWO WERE NOT
# ENOUGH. Read this before removing either line below.
#
# `systemctl enable gdm.service` creates exactly one thing: the link
#
#     /etc/systemd/system/display-manager.service -> .../gdm.service
#
# which is how this computer says "the login screen here is GDM". That is what
# starts it, and it lives in /etc — which belongs to the MACHINE, not to the
# image. Every update merges the machine's own /etc onto the new image's, so a
# change somebody made by hand is kept forever.
#
# On the bench that afternoon, the machine's /etc still had that link pointing
# at greetd.service from a summer test of our old login screen. The merge kept
# it, as designed. greetd is not in this image any more, so the link named a
# service that does not exist, nothing else asked for GDM, and the computer
# booted to a text prompt with no login screen.
#
# So GDM is now switched on the same way as everything else of ours: with a
# link shipped in /usr, which is replaced whole at every update and which
# nothing local can edit. Both lines are needed and they do different jobs:
#
#   the /etc alias (systemctl enable)  NAMES the login screen. `systemctl` reads
#                                      it to answer "which one is this", and
#                                      aquarius-boot-hold and
#                                      aquarius-gdm-display say
#                                      Before=display-manager.service, which
#                                      needs this name to point somewhere real.
#   the /usr link (below)              STARTS it. graphical.target wants
#                                      gdm.service because the image says so,
#                                      whatever /etc has drifted to.
#
# The third piece of the same fix is aquarius-login-screen-alias.service, which
# repairs a drifted /etc alias once per boot. See docs/restart/login.md,
# "Booted to a text console, no login screen", and the note beside
# aq_unit_is_on_from_usr in aq-lib.sh.
say "Making the machine boot to a desktop"
systemctl set-default graphical.target
systemctl enable gdm.service
mkdir -p /usr/lib/systemd/system/graphical.target.wants
ln -sfn ../gdm.service /usr/lib/systemd/system/graphical.target.wants/gdm.service

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
    langpacks-en \
    langpacks-core-en \
    gdm \
    dconf \
    glib2 \
    adwaita-icon-theme \
    adwaita-cursor-theme \
    sound-theme-freedesktop

# The two commands the later steps depend on. glib-compile-schemas belongs to
# glib2 (not glib2-devel — a trap worth knowing) and without it none of the
# AquariusOS defaults in the next step can be applied.
for cmd in gnome-shell gsettings glib-compile-schemas dconf; do
    if aq_have "${cmd}"; then ok "${cmd} is on the path"; else bad "${cmd} is missing"; fi
done

echo "This image has: $(gnome-shell --version)"

# ------------------------------------------------------------------------------
# The app store is a Flatpak store — proved, not assumed
# ------------------------------------------------------------------------------
# Reads the finished image back for the plug-in we removed above. Two checks,
# because "the package is gone" and "the file is gone" can come apart if a
# future Fedora moves the plug-in into a different package: the file is the
# thing that actually does the asking, so the file is the thing we look for.
#
# If either of these goes red, the bench PC is back to a password box about
# once an hour that achieves nothing. The long comment beside the removal, up
# near "The app store (Flatpak only)", explains the whole story.
if rpm -q gnome-software-rpm-ostree > /dev/null 2>&1; then
    bad "gnome-software-rpm-ostree is installed — GNOME Software will ask for a password to upgrade an OS it cannot upgrade"
else
    ok "gnome-software-rpm-ostree is not installed"
fi

# ⚠️ `-print -quit` AND NOT `| head -1`. Piping find into head is the trap
# documented above aq_output_has() in aq-lib.sh: head stops after one line, find
# is killed by a broken pipe, and `set -o pipefail` then fails the whole
# assignment — which under `set -e` ends the build. find's own -quit stops it
# after the first match with no pipe and no signal. The `|| true` covers the
# ordinary case of finding nothing, which is the result we are hoping for here.
AQ_GS_OSTREE_PLUGIN="$(find /usr/lib64/gnome-software -name 'libgs_plugin_rpm-ostree.so' -print -quit 2>/dev/null || true)"
if [ -n "${AQ_GS_OSTREE_PLUGIN}" ]; then
    bad "the rpm-ostree plug-in is still in the image at ${AQ_GS_OSTREE_PLUGIN} — it is what puts the pointless password box on screen"
else
    ok "no rpm-ostree plug-in in GNOME Software — the app store cannot ask to upgrade the OS"
fi

# And the other half of the same sentence: removing the plug-in must not have
# taken the Flatpak store down with it. Without this line the two checks above
# would also pass on an image with no app store at all.
AQ_GS_FLATPAK_PLUGIN="$(find /usr/lib64/gnome-software -name 'libgs_plugin_flatpak.so' -print -quit 2>/dev/null || true)"
if [ -n "${AQ_GS_FLATPAK_PLUGIN}" ]; then
    ok "GNOME Software still has its Flatpak plug-in — the store still works"
else
    bad "GNOME Software has no Flatpak plug-in — the app store can no longer install anything"
fi

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

# ⚠️ THE 2026-09-15 FIX, READ BACK OUT OF THE FINISHED IMAGE.
#
# 1. GDM is wanted from /usr, so an update always restores it and no local
#    change to /etc can lose it. The helper also checks that NOTHING switches
#    gdm on through /etc/systemd/system/graphical.target.wants/ — `systemctl
#    enable gdm` does not create that (gdm.service has no WantedBy=, only
#    Alias=display-manager.service), so this passes, and if some future step
#    starts creating it the helper will say so.
aq_unit_is_on_from_usr gdm.service \
    "the login screen starts because the image says so, whatever /etc says"

# 2. And the name still points at GDM. At build time this link lives at
#    /etc/systemd/system/display-manager.service — the image's copy of it,
#    which the packaging tool moves to /usr/etc when it seals the image, and
#    which every machine then merges its own /etc onto. readlink -f follows the
#    whole chain and prints where it really ends up.
AQ_DM_ALIAS="/etc/systemd/system/display-manager.service"
AQ_DM_TARGET="$(readlink -f "${AQ_DM_ALIAS}" 2> /dev/null || true)"
echo "  ${AQ_DM_ALIAS} -> ${AQ_DM_TARGET:-(nothing)}"
case "${AQ_DM_TARGET}" in
    */gdm.service) ok "'the login screen' on this image means GDM" ;;
    "") bad "${AQ_DM_ALIAS} is missing or points at nothing — 'systemctl enable gdm' did not do its job" ;;
    *) bad "${AQ_DM_ALIAS} points at ${AQ_DM_TARGET}, which is not GDM" ;;
esac

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

# ------------------------------------------------------------------------------
# The desktop-identity themes point at folders that really exist
# ------------------------------------------------------------------------------
# The defaults in zz1-aquarius-10-look name a cursor theme, an icon theme and a
# sound theme. A theme is a NAMED FOLDER on disk; if the folder is missing,
# GNOME falls back to something else without a word, and the setting looks like
# it did nothing. So check the folders, not just the packages.
say "Checking the cursor, icon and sound themes are on disk"
for aq_theme_dir in \
    /usr/share/icons/Adwaita \
    /usr/share/icons/Adwaita/cursors \
    /usr/share/sounds/freedesktop; do
    if [ -d "${aq_theme_dir}" ]; then
        ok "${aq_theme_dir} exists"
    else
        bad "${aq_theme_dir} is missing — a desktop-identity default would silently fall back"
    fi
done

aq_finish "The GNOME desktop"
