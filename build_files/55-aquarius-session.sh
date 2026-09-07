#!/usr/bin/bash
# ==============================================================================
# STEP 5.5 — The Aquarius Desktop: our own desktop, beside GNOME
# ==============================================================================
# WHAT THIS STEP IS
#
# Everything up to here builds a machine that runs GNOME. This step adds a
# SECOND desktop, the one AquariusOS is actually being built to have: the
# Aquarius Shell — our own bar, dock, search palette, quick settings and
# notifications — running on the labwc window manager.
#
# It appears at the login screen as "Aquarius Desktop", next to "GNOME". Picking
# one or the other is the whole switching mechanism. GNOME is untouched, stays
# installed forever, and is what a person falls back to if ours breaks. That is
# the no-burn-the-boats rule and it is not negotiable.
#
# ------------------------------------------------------------------------------
# THE PIECES, AND WHERE EACH ONE COMES FROM
# ------------------------------------------------------------------------------
#   labwc 0.20        COMPILED, by build_files/stage-labwc.sh. Fedora 44 has
#                     0.9.6 and we need the release with HDR and colour
#                     management.
#   Quickshell 0.3.x  COMPILED, by build_files/stage-quickshell.sh. Fedora's
#                     package is a 0.2.1 snapshot missing two modules the shell
#                     imports — and building it in-image is also what makes the
#                     Qt version mismatch that broke the first bench boot
#                     impossible.
#   the Aquarius      FETCHED at a pinned commit by
#   Shell             build_files/stage-aquarius-shell.sh, from
#                     github.com/stoneharborent/aquarius-shell.
#   the session       SHIPPED as files in system_files/ — the launcher, the
#   plumbing          login-screen entry, the labwc configuration, the portal
#                     configuration. Copied in by step 5.
#   everything else   INSTALLED here, from Fedora.
#
# All three compiled/fetched trees were copied in by COPY lines in the
# Containerfile immediately before this script runs. This script installs the
# libraries they need, configures the session, and then CHECKS THE RESULT by
# running the programs and reading their output — never by assuming a copy
# worked.
#
# ------------------------------------------------------------------------------
# ONE THING THAT IS DELIBERATELY NOT SWITCHED ON: greetd
# ------------------------------------------------------------------------------
# greetd is a small modern login manager, and since 2026-09-04 it has a real
# AquariusOS login screen behind it — the Aquarius Shell's own greeter, on the
# Ice wallpaper, with the Aquarius mark. It is INSTALLED, FULLY CONFIGURED, and
# SWITCHED OFF. GDM is still the login screen this image boots to.
#
# That is not caution for its own sake. Nobody has looked at the new login
# screen on real hardware yet, and the way you find out that a login screen does
# not work is by not being able to log in. So it ships ready and off, Royce
# tries it on the bench with one command, and the day he says yes the default
# moves.
#
# Switching over is ONE command now — `sudo aq login use greetd` — and switching
# back is the same command with `gdm` on the end, typed from a text console if
# it has to be. The plain-English guide is docs/restart/login.md.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AQ_SHELL_DIR="/usr/share/aquarius/shell"
AQ_LABWC_DIR="/usr/share/aquarius/labwc"
AQ_SESSION_ENTRY="/usr/share/wayland-sessions/aquarius.desktop"
AQ_LAUNCHER="/usr/bin/aquarius-session"
AQ_PORTAL_CONF="/usr/share/xdg-desktop-portal/aquarius-portals.conf"

# ==============================================================================
# 1. The libraries the two compiled programs need
# ==============================================================================
# The build stages compiled labwc and Quickshell against Fedora 44's -devel
# packages. Those packages exist only on the throwaway build machines. The
# RUNTIME halves of the same libraries have to be installed here, or the
# finished image ships two programs that cannot start.
#
# Getting this list wrong does not produce a build error. It produces a machine
# that boots, offers "Aquarius Desktop" at the login screen, and drops you back
# to the login screen the moment you pick it. So the check at the bottom of this
# file runs `ldd` over both programs and fails the build on the first library
# that cannot be found — which is the check that actually matters here.
say "The libraries labwc needs"
aq_dnf install \
    wlroots \
    libsfdo \
    librsvg2 \
    libxml2 \
    cairo \
    pango \
    libpng \
    pixman \
    libinput \
    libxkbcommon \
    libxcb \
    xcb-util-wm \
    libdrm \
    mesa-libgbm \
    libseat \
    xkeyboard-config

say "The libraries Quickshell needs"
# qt6-qtdeclarative is QML itself. qt6-qtwayland is what lets a Qt program be a
# Wayland client at all. qt6-qtsvg is why the Aquarius mark in the bar is a
# crisp shape rather than a blurry picture. jemalloc is the memory allocator
# Quickshell is built with — a shell runs for weeks and Qt fragments memory.
#
# This is the largest single addition this step makes to the image. Qt is not
# small, and this is a GTK-flavoured operating system that did not have it
# before. That cost was a known open question from the shell's design phase and
# it is answered here: it is worth it, because it is the price of having our own
# desktop at all.
aq_dnf install \
    qt6-qtbase \
    qt6-qtbase-gui \
    qt6-qtdeclarative \
    qt6-qtwayland \
    qt6-qtsvg \
    jemalloc \
    pam \
    polkit-libs

# ==============================================================================
# 2. The rest of the session
# ==============================================================================
say "The session's own programs"
# xdg-desktop-portal-wlr  screen recording. THE reason OBS works in this
#                         session. See system_files/.../aquarius-portals.conf.
# swaybg                  paints the wallpaper. A window manager on its own
#                         shows flat grey.
# slurp                   the little drag-to-pick overlay that asks which screen
#                         to record.
# wlr-randr               reads and sets monitor layout from a terminal. This is
#                         the only way to answer "what is my second monitor
#                         called" in this session until the shell has a display
#                         panel.
# brightnessctl           the shell's brightness slider shells out to this.
#                         Quickshell has no brightness service; this is the
#                         documented interim, fenced in the shell's own code.
# zenity                  draws the dialog that appears if the bar fails to
#                         start. See /usr/libexec/aquarius-shell-start.
# libnotify               notify-send, the fallback if even zenity is missing.
# procps-ng               pgrep and pkill. Named here rather than relied on as
#                         somebody else's dependency, because two pieces of the
#                         2026-09-03 keyboard fix use them: the service clears a
#                         leftover remapper out of the way with pkill before
#                         starting, and the run script asks pgrep whether GNOME
#                         Shell is really running before believing the
#                         environment that says it is.
aq_dnf install \
    xdg-desktop-portal-wlr \
    swaybg \
    slurp \
    wlr-randr \
    brightnessctl \
    zenity \
    libnotify \
    procps-ng

# ------------------------------------------------------------------------------
# The thing that asks for a password
# ------------------------------------------------------------------------------
# ⚠️ THE 2026-09-04 BENCH FAULT. Royce ticked his creator apps, pressed Install,
# and got:
#
#     Error creating textual authentication agent: Error opening current
#     controlling terminal for the process ('/dev/tty')
#
# That is `pkexec` finding that nothing in this session can ask "type your
# password". Every desktop ships a small background program for that job — a
# polkit authentication agent — and GNOME has one built into GNOME Shell. This
# session had none.
#
# WHY lxqt-policykit AND NOT ONE OF THE OTHERS
#   * It is an official Fedora package (2.4.0 in Fedora 44). hyprpolkitagent,
#     the obvious Qt6/QML alternative, is only in a COPR; polkit-gnome, which
#     the internet still recommends, is orphaned and Fedora dropped it.
#   * It is Qt 6, and this session already carries Qt 6 for Quickshell — so it
#     adds a dialog, not a second toolkit. Beyond what is here already it needs
#     polkit-qt6-1 and liblxqt and nothing else.
#   * It is one binary. It does not install LXQt, does not add a session to the
#     login screen, and does not put anything in the app grid.
#
# The runner-up was mate-polkit (GTK 3, official, but it drags in
# libappindicator and an older toolkit). The full comparison is in
# docs/restart/aquarius-session.md.
say "The thing that asks you for your password (polkit agent)"
aq_dnf install lxqt-policykit

# dbus-tools carries dbus-update-activation-environment, which is how the
# launcher hands the session's environment to systemd and D-Bus so the portals
# start with the right values. --skip-unavailable because the launcher already
# falls back to `systemctl --user import-environment` if the command is absent,
# and a name that turns out to be spelled differently should not stop a build
# over something optional.
aq_dnf install --skip-unavailable dbus-tools

# ==============================================================================
# 3. greetd — installed, configured, and switched OFF
# ==============================================================================
say "greetd (installed but NOT switched on)"
# greetd-selinux carries the security policy for greetd. Installing greetd
# without it on a machine with SELinux enforcing — which AquariusOS is — gives a
# login manager that is refused permission to start sessions, and the error
# lands in the audit log where nobody looks.
#
# tuigreet is a text login screen for greetd. Worth a note: the plan for this
# step assumed Fedora did not package it and that we would have to fall back to
# greetd's own bare `agreety`. Fedora 44 does package it (tuigreet 0.9.1,
# checked 2026-09-03), so the switch-to-greetd path gets a real login screen
# that lists the sessions instead of a login: prompt.
aq_dnf install \
    greetd \
    greetd-selinux \
    tuigreet

# greetd's own configuration file. Written here, AFTER the package is installed,
# rather than shipped in system_files/ — because the package owns this path, and
# a file already sitting there when the package arrives gets renamed to
# .rpmnew by rpm and quietly ignored.
say "Writing greetd's configuration"
install -d -m 0755 /etc/greetd
cat > /etc/greetd/config.toml <<'AQ_GREETD_CONF'
# =============================================================================
# greetd — the AquariusOS login screen
# =============================================================================
# ⚠️ THIS IS NOT SWITCHED ON. Out of the box AquariusOS boots to GDM, GNOME's
# login screen. This file is here, configured and ready, for the day the
# AquariusOS login screen has been looked at on real hardware and approved.
#
# To try it:      sudo aq login use greetd     then restart
# To go back:     sudo aq login use gdm        then restart
#
# Both commands work from a text console (Ctrl+Alt+F3) if the graphical screen
# is not cooperating, and `aq login status` says which one is switched on.
#
# WHAT HAPPENS WHEN IT IS SWITCHED ON
#   greetd itself draws nothing. It runs ONE program on one virtual terminal and
#   is the only thing on the computer that checks passwords. The program below
#   is ours: it starts a window manager, and inside it the Aquarius Shell draws
#   the login screen — the Ice wallpaper, the clock, the Aquarius mark, and a
#   password box.
#
#   If that fails for any reason, /usr/libexec/aquarius-greeter falls through to
#   a plain text login screen rather than leaving you at a black one. Read the
#   top of that file: the safety net is the most important thing in it.
# =============================================================================

[terminal]
# Which virtual terminal the login screen appears on. 1 is the one a PC shows
# after it has finished starting up.
vt = 1

[default_session]
# The whole login screen, top to bottom. Its own header draws the diagram.
command = "/usr/libexec/aquarius-greeter"

# greetd runs the login screen as an unprivileged user of its own, so a bug in
# the login screen is not a bug running as root.
#
# ⚠️ THE USER IS CALLED "greetd" ON FEDORA, NOT "greeter". Almost every guide on
# the internet says `user = "greeter"`, because that is Arch Linux's name for
# it. Fedora's package creates `greetd`, with a home folder at /var/lib/greetd.
# Putting the wrong name here gives a login screen that never starts, and the
# reason lands in the journal rather than on the screen.
user = "greetd"

# -----------------------------------------------------------------------------
# THE PLAIN TEXT LOGIN SCREEN, IF YOU WANT IT ON PURPOSE
# -----------------------------------------------------------------------------
# tuigreet is in this image and is what the line above falls back to on its own
# if the graphical screen fails. To use it deliberately — while working on the
# graphical one, say — replace the `command` line above with this and restart:
#
#   command = "tuigreet --remember --remember-session --asterisks --time --sessions /usr/share/wayland-sessions:/usr/local/share/wayland-sessions"
AQ_GREETD_CONF
chmod 0644 /etc/greetd/config.toml

# It has to be readable by the login manager and it has to parse. A broken TOML
# file here is a login screen that never appears, with the reason in a log
# nobody can reach because they cannot log in.
if python3 -c "import tomllib,sys; tomllib.load(open('/etc/greetd/config.toml','rb'))" 2> /dev/null; then
    ok "greetd's configuration is valid TOML"
else
    bad "/etc/greetd/config.toml does not parse — switching to greetd would give a machine nobody can log into"
fi
aq_file_has /etc/greetd/config.toml '^command = "/usr/libexec/aquarius-greeter"$' \
    "greetd is pointed at the AquariusOS login screen"
aq_file_has /etc/greetd/config.toml '^user = "greetd"$' \
    "it runs as the user Fedora's package actually creates (greetd, not greeter)"

# ------------------------------------------------------------------------------
# The login screen's own pieces
# ------------------------------------------------------------------------------
say "The AquariusOS login screen"

# The two launchers shipped in system_files/. Executable, or greetd runs a file
# it is not allowed to run and the machine shows a black screen.
chmod 0755 /usr/libexec/aquarius-greeter /usr/libexec/aquarius-greeter-shell
for aq_f in /usr/libexec/aquarius-greeter /usr/libexec/aquarius-greeter-shell; do
    if [ -x "${aq_f}" ]; then
        ok "$(basename "${aq_f}") is installed and executable"
    else
        bad "${aq_f} is missing or not executable"
    fi
    if bash -n "${aq_f}"; then
        ok "$(basename "${aq_f}") is valid shell"
    else
        bad "${aq_f} does not parse as shell"
    fi
done

# ------------------------------------------------------------------------------
# The greeter safety net — switch back to GDM if the greeter never draws
# ------------------------------------------------------------------------------
# ⚠️ THIS IS THE LOAD-BEARING RULE FROM THE 2026-09-05 SAGA. `aq login use
# greetd` (the R5 greeter test) trapped the bench on a black screen for days:
# greetd started labwc, the Quickshell greeter never drew, and every reboot came
# back to the same bare labwc desktop. The launcher's own text-login fallback
# (above) catches "the greeter would not START"; it cannot see "the greeter
# started and drew nothing". This watchdog can, over more than one boot: two
# failed greetd boots in a row and it switches the machine back to GDM by itself.
#
# It ships ENABLED (the symlink is in system_files) and is harmless on a default
# machine, because a default machine boots to GDM and the watchdog's first act is
# to check for that and exit. See the program's header and docs/restart/login.md.
say "The greeter safety net (aquarius-greeter-watchdog)"
chmod 0755 /usr/libexec/aquarius-greeter-watchdog
if [ -x /usr/libexec/aquarius-greeter-watchdog ]; then
    ok "aquarius-greeter-watchdog is installed and executable"
else
    bad "/usr/libexec/aquarius-greeter-watchdog is missing or not executable — a broken greeter could trap the machine"
fi
if bash -n /usr/libexec/aquarius-greeter-watchdog; then
    ok "aquarius-greeter-watchdog is valid shell"
else
    bad "aquarius-greeter-watchdog does not parse as shell"
fi
# The service file, and that it is switched on the /usr way (never through /etc —
# see aq-lib.sh). It must be enabled so that it runs on the very first greetd
# boot after somebody switches, which is exactly the boot that trapped the bench.
if [ -r /usr/lib/systemd/system/aquarius-greeter-watchdog.service ]; then
    ok "the watchdog's service file is here"
else
    bad "aquarius-greeter-watchdog.service is missing — the watchdog would never run"
fi
if [ -L /usr/lib/systemd/system/graphical.target.wants/aquarius-greeter-watchdog.service ]; then
    ok "the watchdog is switched on (the /usr way, not through /etc)"
else
    bad "the watchdog is not switched on — it would sit there and never run"
fi
# The counter must live under /var (per-machine, survives a reboot), not baked
# into the image. It is created by the watchdog and by `aq login use greetd`; the
# only thing to check here is that nothing shipped a stale copy in the image.
if [ -e /var/lib/aquarius/greeter-fails ] || [ -e /var/lib/aquarius/greeter-probation ]; then
    bad "a greeter safety-net state file is baked into the image — it belongs on the machine, under /var, written at runtime"
else
    ok "no greeter safety-net state is baked into the image (correct)"
fi

# ⚠️ The helper that lists the accounts and the desktops lives in the SHELL
# repository, beside the login screen that reads it, and is copied out to
# /usr/libexec here. That is on purpose: the QML and the program it runs are one
# feature and must never be two versions of one feature. The path is a contract
# between the two repositories and the shell's own tests check its half.
#
# ⚠️ A MISSING SHELL IS A WARNING, NOT A FAILURE — the same rule section 6
# applies further down, and for the same reason: a container build cannot read a
# private repository, and an image without the shell in it is still a usable
# image. Everything in this block is therefore skipped, loudly, if the shell is
# not here. (The greetd configuration above is still written, because the day
# the shell arrives it should already be pointed at.)
AQ_GREETER_SHELL_HERE=0
if [ -s "${AQ_SHELL_DIR}/shell.qml" ]; then
    AQ_GREETER_SHELL_HERE=1
else
    echo "  NOTE   the Aquarius Shell is not in this image, so there is no"
    echo "         login screen to install either. Switching to greetd would"
    echo "         land on the plain text login screen, which still works."
fi

AQ_GREETER_INFO_SRC="${AQ_SHELL_DIR}/greeter/aquarius-greeter-info"
if [ "${AQ_GREETER_SHELL_HERE}" -eq 0 ]; then
    :
elif [ -r "${AQ_GREETER_INFO_SRC}" ]; then
    install -D -m 0755 "${AQ_GREETER_INFO_SRC}" /usr/libexec/aquarius-greeter-info
    ok "the account-and-desktop lister was installed from the shell"
else
    bad "${AQ_GREETER_INFO_SRC} is not in the shell tree — the login screen would show no accounts at all"
fi

if [ -x /usr/libexec/aquarius-greeter-info ]; then
    # Run it. It is Python, and a missing import or a typo would otherwise only
    # show up as an empty login screen on somebody's desk.
    if /usr/libexec/aquarius-greeter-info > /tmp/aq-greeter-info.json 2>&1; then
        ok "it runs"
    else
        bad "it does not run:"
        sed 's/^/       /' /tmp/aq-greeter-info.json
    fi
    if python3 -c "
import json, sys
data = json.load(open('/tmp/aq-greeter-info.json'))
for key in ('people', 'desktops'):
    if not isinstance(data.get(key), list):
        sys.exit(1)
print('  OK   it prints %d account(s) and %d desktop(s)'
      % (len(data['people']), len(data['desktops'])))
" 2> /dev/null; then
        :
    else
        bad "what it printed is not the answer the login screen reads"
    fi
    # Inside a build container there are no accounts and there ARE two desktop
    # files, so the desktops list is the half that has a right answer here.
    if grep -q '"id": "aquarius"' /tmp/aq-greeter-info.json; then
        ok "the Aquarius Desktop is one of the desktops it offers"
    else
        bad "the Aquarius Desktop is not in the list the login screen would show"
    fi
    rm -f /tmp/aq-greeter-info.json
fi

# The login screen's own window manager configuration. Not the desktop's — see
# the long note at the top of the file itself.
chmod 0755 /usr/share/aquarius/greeter-labwc
chmod 0644 /usr/share/aquarius/greeter-labwc/*
aq_file_has /usr/share/aquarius/greeter-labwc/rc.xml '<decoration>none</decoration>' \
    "the login screen's window manager draws no title bars"
if python3 -c "import xml.etree.ElementTree as e; e.parse('/usr/share/aquarius/greeter-labwc/rc.xml')" 2> /dev/null; then
    ok "its configuration is well-formed XML"
else
    bad "/usr/share/aquarius/greeter-labwc/rc.xml is not valid XML — labwc would ignore it silently"
fi

# The QML the whole thing draws. Copied in with the rest of the shell.
if [ "${AQ_GREETER_SHELL_HERE}" -eq 1 ]; then
    for aq_f in greeter.qml greeter/qmldir greeter/GreeterState.qml \
        greeter/GreeterWindow.qml greeter/GreeterCard.qml greeter/GreeterField.qml; do
        if [ -s "${AQ_SHELL_DIR}/${aq_f}" ]; then
            ok "${aq_f}"
        else
            bad "${AQ_SHELL_DIR}/${aq_f} is missing — the login screen would not draw"
        fi
    done
fi

# ------------------------------------------------------------------------------
# Which login screen is switched on
# ------------------------------------------------------------------------------
# Exactly one may be. systemd enforces that through a link called
# display-manager.service, and two login managers both claiming it is one of the
# classic ways to end up at a black screen with no way in.
say "Making sure GDM is the login screen and greetd is not"
systemctl disable greetd.service 2> /dev/null || true
systemctl enable gdm.service

# ==============================================================================
# 4. Permissions on the files step 5 copied in
# ==============================================================================
# The launcher and the failure-dialog helper have to be executable. Git records
# the executable bit and the copy preserves it, but this project has been bitten
# before by a file arriving without it (iCloud strips the bit on sync), and the
# symptom — the login screen flashing and returning — gives no clue why.
# Setting it here costs nothing and removes the whole class of problem.
say "Permissions"
chmod 0755 "${AQ_LAUNCHER}" /usr/libexec/aquarius-shell-start \
    /usr/libexec/aquarius-session-portals
# The clean-up library is READ, not run, so it does not need to be executable —
# but it does have to be readable by everybody, because every person logging in
# reads it.
chmod 0644 /usr/libexec/aquarius-session-lib
chmod 0644 "${AQ_SESSION_ENTRY}" "${AQ_PORTAL_CONF}"
# ⚠️ NOT EVERY FILE IN THE labwc FOLDER IS A SETTINGS FILE, and this line used
# to assume they all were. `chmod 0644` over the whole folder took the
# executable bit off generate-theme — the program that builds the window frame
# out of the shell's palette — and the build then failed one step later saying
# it was "missing or not executable". That is the right failure to have had: it
# is exactly the fault the check below was written for. Five files in this
# folder are READ by labwc; one is RUN, and it needs the bit.
chmod 0644 "${AQ_LABWC_DIR}"/rc.xml "${AQ_LABWC_DIR}"/menu.xml \
    "${AQ_LABWC_DIR}"/autostart "${AQ_LABWC_DIR}"/shutdown \
    "${AQ_LABWC_DIR}"/environment
chmod 0755 "${AQ_LABWC_DIR}"/generate-theme
chmod 0755 "${AQ_LABWC_DIR}"

# Printed, because "0644 on everything in the folder" is the obvious thing for
# somebody to write here again, and a listing in the build log is how the next
# person sees at a glance that one file is deliberately different.
ls -l "${AQ_LABWC_DIR}" | sed 's/^/  /'

# ==============================================================================
# 5. Checking it — by running things, not by assuming
# ==============================================================================
say "Checking the two compiled programs actually run"

# --- labwc --------------------------------------------------------------------
if [ -x /usr/bin/labwc ]; then
    ok "labwc is installed and executable"
else
    bad "/usr/bin/labwc is missing — the COPY from the labwc build stage did not land"
fi

AQ_LABWC_SAYS="$(/usr/bin/labwc --version 2>&1 || true)"
echo "  labwc --version: ${AQ_LABWC_SAYS}"
case "${AQ_LABWC_SAYS}" in
    *0.20.*) ok "labwc is a 0.20 release (the one with HDR and colour management)" ;;
    *) bad "labwc reports '${AQ_LABWC_SAYS}' — expected 0.20.x. Fedora's own 0.9.6 may have been installed over ours." ;;
esac

# labwc lists its optional features in that same line, each with a plus or a
# minus. XWayland is the one that must never be a minus: it is what lets X11-only
# software run, and on a creator machine that means DaVinci Resolve.
#
# This is checked here, in the finished image, as well as in the build stage,
# because it went wrong once already (2026-09-03): a missing text file made the
# build print one warning nobody read and produce a window manager with XWayland
# switched off. The image built and would have published.
case "${AQ_LABWC_SAYS}" in
    *+xwayland*) ok "labwc can run X11 software (DaVinci Resolve needs this)" ;;
    *) bad "labwc was built WITHOUT XWayland — X11-only software, including DaVinci Resolve, would not start. Its report: ${AQ_LABWC_SAYS}" ;;
esac

# --- Quickshell ---------------------------------------------------------------
if [ -e /usr/bin/qs ] || [ -L /usr/bin/qs ]; then
    ok "the qs command is installed"
else
    bad "/usr/bin/qs is missing — the COPY from the Quickshell build stage did not land"
fi

# `qs --version` loads every Qt library this program will ever need and then
# prints one line. It is the single most valuable check in this file: it is the
# exact thing that failed on the bench on 2026-09-02, when a quickshell built
# against a different Qt died with a symbol lookup error and left a person
# staring at an empty desktop for eighteen minutes.
#
# A runtime directory is invented for it because a build container has none, and
# Qt complains loudly about that in a way that has nothing to do with whether
# the program works.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/aq-build-runtime}"
install -d -m 0700 "${XDG_RUNTIME_DIR}"
export QT_QPA_PLATFORM=offscreen

AQ_QS_STATUS=0
AQ_QS_SAYS="$(/usr/bin/qs --version 2>&1)" || AQ_QS_STATUS=$?
echo "  qs --version: ${AQ_QS_SAYS}"
if [ "${AQ_QS_STATUS}" -ne 0 ]; then
    bad "qs cannot start (exit ${AQ_QS_STATUS}). This is the Qt mismatch, in the image, before anybody boots it."
else
    ok "qs starts"
    case "${AQ_QS_SAYS}" in
        *0.3*) ok "Quickshell is a 0.3 release (0.2.1 is missing the Networking and Bluetooth modules the shell imports)" ;;
        *) bad "Quickshell reports '${AQ_QS_SAYS}' — expected 0.3.x" ;;
    esac
fi

# --- every library both of them need ------------------------------------------
say "Every library the two programs need is present"
for aq_bin in /usr/bin/labwc /usr/bin/quickshell; do
    if [ ! -e "${aq_bin}" ]; then
        continue
    fi
    ldd "${aq_bin}" > /tmp/aq-ldd.txt 2>&1 || true
    if grep -q "not found" /tmp/aq-ldd.txt; then
        bad "${aq_bin} is missing libraries on the finished image:"
        grep "not found" /tmp/aq-ldd.txt | sed 's/^/       /'
    else
        ok "${aq_bin} — every library resolves ($(wc -l < /tmp/aq-ldd.txt) of them)"
    fi
done
rm -f /tmp/aq-ldd.txt

# ==============================================================================
# 6. Checking the shell and the modules it imports
# ==============================================================================
say "The Aquarius Shell"

sed 's/^/       /' /usr/share/aquarius/shell-build.txt

# ⚠️ A MISSING SHELL IS A WARNING HERE, NOT A FAILURE, AND THAT IS DELIBERATE.
#
# The shell lives in its own repository. A container build has no GitHub
# account, so it can read a public repository and nothing else — and there is
# deliberately no token in this build, because a secret handed to a container
# build is recorded in the finished image's history where anybody can read it.
#
# So if that repository is private on the day this runs, the image is finished
# WITHOUT the shell. Everything else works: the window manager, the wallpaper,
# the keyboard, screen recording, the login-screen entry. Picking "Aquarius
# Desktop" gives a wallpaper and a dialog saying, in plain English, that the
# shell is not installed yet and how to get back to GNOME.
#
# That is the "R2a platform" state of the plan and it is a reasonable thing to
# ship. What would not be reasonable is shipping it silently, so it is said
# here, in the image, and on the CI run.
AQ_SHELL_PRESENT=0
if [ -s "${AQ_SHELL_DIR}/shell.qml" ]; then
    AQ_SHELL_PRESENT=1
    ok "the shell is installed at ${AQ_SHELL_DIR}"
else
    echo "::warning::This image has no Aquarius Shell. The Aquarius Desktop will start and explain itself. See /usr/share/aquarius/shell-build.txt."
    echo "  NOTE   the Aquarius Shell is NOT in this image."
    echo "         Everything else in the Aquarius Desktop is. The session"
    echo "         starts, shows the wallpaper, and puts a dialog on screen"
    echo "         explaining that the bar is not installed yet."
    echo "         The fix is to make the shell repository public and rebuild."
fi

# THE CHECK THAT CATCHES THE EXPENSIVE MISTAKE.
#
# The shell's QML says `import Quickshell.Networking`. If Quickshell was built
# with that feature switched off, the shell refuses to start — at LOGIN, on a
# screen with no bar, with the reason one line deep in a log.
#
# ⚠️ The obvious way to check does not work, and it is worth knowing why.
# Quickshell does not install its QML modules as folders on disk the way every
# other Qt application does; it compiles each one into the program itself. The
# finished install is two files. So there is no folder to look for, and looking
# for one is what failed the first build of this step on 2026-09-03.
#
# What the Quickshell build stage DOES leave behind is a record of every feature
# it was told to compile, read out of the build's own configuration:
# /usr/share/aquarius/quickshell-build.txt. This reads the shell's import lines
# and checks that record for each one. The table below is the only place the two
# vocabularies meet, and it is deliberately written out in full rather than
# guessed at from the names.
say "Every Quickshell module the shell imports was built in"

AQ_QS_RECORD="/usr/share/aquarius/quickshell-build.txt"
AQ_QS_FEATURES="$(grep -E '^features=' "${AQ_QS_RECORD}" 2> /dev/null | cut -d= -f2- || true)"
echo "  the Quickshell build record says: ${AQ_QS_FEATURES:-(nothing)}"

# import Quickshell.X  ->  the CMake feature that provides it
aq_feature_for_import() {
    case "$1" in
        Quickshell)                           echo "" ;;              # the core; always there
        Quickshell.Io)                        echo "" ;;              # core
        Quickshell.Widgets)                   echo "" ;;              # core
        Quickshell.Wayland)                   echo "WAYLAND" ;;
        Quickshell.Networking)                echo "NETWORK" ;;
        Quickshell.Bluetooth)                 echo "BLUETOOTH" ;;
        Quickshell.Services.Notifications)    echo "SERVICE_NOTIFICATIONS" ;;
        Quickshell.Services.Pipewire)         echo "SERVICE_PIPEWIRE" ;;
        Quickshell.Services.SystemTray)       echo "SERVICE_STATUS_NOTIFIER" ;;
        Quickshell.Services.UPower)           echo "SERVICE_UPOWER" ;;
        Quickshell.Services.Mpris)            echo "SERVICE_MPRIS" ;;
        Quickshell.Services.Greetd)           echo "SERVICE_GREETD" ;;
        Quickshell.Services.Pam)              echo "SERVICE_PAM" ;;
        *)                                    echo "UNKNOWN" ;;
    esac
}

if [ "${AQ_SHELL_PRESENT}" -eq 0 ]; then
    echo "  skipped — there is no shell in this image to read imports from."
    echo "  The Quickshell build stage checked its own feature list already."
else
    grep -rhoE '^import Quickshell[A-Za-z.]*' "${AQ_SHELL_DIR}" 2> /dev/null \
        | sed 's/^import //' | sort -u > /tmp/aq-imports.txt
    if [ ! -s /tmp/aq-imports.txt ]; then
        bad "no Quickshell imports found anywhere in ${AQ_SHELL_DIR} — the shell tree looks wrong"
    fi

    while read -r aq_import; do
        aq_feat="$(aq_feature_for_import "${aq_import}")"
        case "${aq_feat}" in
            "")
                ok "${aq_import} (part of Quickshell itself)"
                ;;
            UNKNOWN)
                bad "${aq_import} — the shell imports a module this build script has never heard of. Add it to the table in 55-aquarius-session.sh so it can be checked."
                ;;
            *)
                if printf '%s' "${AQ_QS_FEATURES}" | grep -q "${aq_feat}=ON"; then
                    ok "${aq_import} (built in as ${aq_feat})"
                else
                    bad "${aq_import} — Quickshell was built WITHOUT ${aq_feat}, so the shell would refuse to start"
                fi
                ;;
        esac
    done < /tmp/aq-imports.txt
    rm -f /tmp/aq-imports.txt
fi

# The external commands the shell shells out to. None of these is fatal — the
# shell fences each one — but a missing one means a slider or a menu entry that
# silently does nothing, and that should be a decision rather than a surprise.
say "The commands the shell runs"
for aq_cmd in brightnessctl loginctl systemctl gdbus; do
    if aq_have "${aq_cmd}"; then
        ok "${aq_cmd}"
    else
        bad "${aq_cmd} is missing — part of the shell will silently do nothing"
    fi
done

# ==============================================================================
# 7. Checking the session plumbing
# ==============================================================================
say "The login-screen entry"

if [ -r "${AQ_SESSION_ENTRY}" ]; then
    ok "${AQ_SESSION_ENTRY} exists"
    sed 's/^/       /' "${AQ_SESSION_ENTRY}"
else
    bad "${AQ_SESSION_ENTRY} is missing — nothing would appear at the login screen"
fi

aq_file_has "${AQ_SESSION_ENTRY}" '^Name=Aquarius Desktop$' "it is called 'Aquarius Desktop'"
aq_file_has "${AQ_SESSION_ENTRY}" '^Exec=/usr/bin/aquarius-session$' "it runs our launcher"
# Without this export Qt hands the shell an EMPTY icon theme (our desktop name
# is not GNOME or KDE), only hicolor is searched, and every Aquarius app icon
# in the dock is two grey letters. Found on the bench, 2026-09-06.
aq_file_has "${AQ_LAUNCHER}" '^export QS_ICON_THEME=' "the launcher tells the shell which icon theme to draw from"
aq_file_has /usr/libexec/aquarius-greeter '^export QS_ICON_THEME=' "the greeter tells its shell which icon theme to draw from"
aq_file_has "${AQ_SESSION_ENTRY}" '^DesktopNames=Aquarius$' "it names the desktop 'Aquarius', which is what finds the portal configuration"

# GNOME's entry must still be there. A desktop that replaces the fallback rather
# than sitting beside it is the one thing this whole design forbids.
if [ -r /usr/share/wayland-sessions/gnome.desktop ]; then
    ok "the GNOME session is still there to fall back to"
else
    bad "GNOME's session entry has disappeared — the fallback is gone"
fi

say "The launcher"
if [ -x "${AQ_LAUNCHER}" ]; then
    ok "${AQ_LAUNCHER} exists and is executable"
else
    bad "${AQ_LAUNCHER} is missing or not executable"
fi
if bash -n "${AQ_LAUNCHER}"; then
    ok "the launcher is valid shell script"
else
    bad "the launcher has a syntax error — every login would fail"
fi
if bash -n /usr/libexec/aquarius-shell-start; then
    ok "the failure-dialog helper is valid shell script"
else
    bad "/usr/libexec/aquarius-shell-start has a syntax error"
fi

# ==============================================================================
# Logging out — the 2026-09-04 fix
# ==============================================================================
# THE BUG: logging out of the Aquarius Desktop to go to GNOME bounced off the
# login screen two or three times before GNOME would start, because the session
# left its settings on the user's systemd noticeboard and left its background
# programs running for GNOME to trip over.
#
# THE FIX: /usr/libexec/aquarius-session-lib. What it does and why is written
# out at length in the file itself and in docs/restart/aquarius-session.md.
#
# THREE THINGS ARE CHECKED HERE, and each fails differently if it is skipped:
# the pieces are present, the lists inside them agree with the launcher, and the
# whole sequence behaves when it is actually run against stand-in commands.
# ==============================================================================
say "Logging out cleanly"

AQ_SESSION_LIB="/usr/libexec/aquarius-session-lib"
AQ_SESSION_PORTALS="/usr/libexec/aquarius-session-portals"

if [ -r "${AQ_SESSION_LIB}" ]; then
    ok "${AQ_SESSION_LIB} is installed"
else
    bad "${AQ_SESSION_LIB} is missing — the launcher refuses to start without it, so NOBODY could log in to the Aquarius Desktop at all"
fi

if bash -n "${AQ_SESSION_LIB}"; then
    ok "the clean-up library is valid shell script"
else
    bad "the clean-up library has a syntax error — every login would fail"
fi

if [ -x "${AQ_SESSION_PORTALS}" ]; then
    ok "${AQ_SESSION_PORTALS} is installed and executable"
else
    bad "${AQ_SESSION_PORTALS} is missing or not executable — arriving here from GNOME would leave GNOME's portals in charge and screen recording would silently show no screens"
fi

if bash -n "${AQ_SESSION_PORTALS}"; then
    ok "the portal helper is valid shell script"
else
    bad "${AQ_SESSION_PORTALS} has a syntax error"
fi

aq_file_has "${AQ_LAUNCHER}" "^trap 'aq_session_teardown' EXIT" \
    "the launcher runs the clean-up on EVERY way out of the session, including a crash"
aq_file_has "${AQ_LAUNCHER}" '^aq_session_env_reset$' \
    "and it clears the LAST desktop's screen on the way IN, so a force-killed session cannot poison the next one"
aq_file_has "${AQ_LABWC_DIR}/autostart" 'aquarius-session-portals' \
    "logging in takes the portals back from whichever desktop had them last"

# ------------------------------------------------------------------------------
# And now actually RUN it. This is the part that matters.
#
# The test replaces systemctl, pkill and dbus-update-activation-environment with
# stand-ins that write down what they were asked to do, runs the real clean-up
# against them, and then checks the transcript: the right order, the right
# units, exact-name kills limited to one person, and — the important one — that
# every `export` in the installed launcher appears in the installed library's
# list. A settings leak into the next login fails the build here rather than
# turning up on the bench in three months.
#
# It runs against the INSTALLED copies, not the ones in the repository, for the
# same reason the update-overlay tests do: those are a different question.
# ------------------------------------------------------------------------------
if [ -x /ctx/tests/test-session-teardown.sh ]; then
    say "Running tests/test-session-teardown.sh against the installed files"
    if /ctx/tests/test-session-teardown.sh "${AQ_SESSION_LIB}" "${AQ_LAUNCHER}"; then
        ok "logging out leaves the machine clean"
    else
        bad "the logout clean-up is wrong — see the failures above. Logging out of Aquarius into GNOME would bounce off the login screen, which is the bug of 2026-09-04 returning."
    fi
else
    bad "tests/test-session-teardown.sh is missing from the build context (the Containerfile gathers it with 'COPY tests /tests'). Without it the logout clean-up would ship untested."
fi

# ------------------------------------------------------------------------------
# Every user service that runs inside our session must be PART OF it.
#
# `PartOf=graphical-session.target` is what makes a service stop when the
# desktop ends. Without it, a service started at login keeps running after
# logout — which is the leftover-programs half of the bug this section is about.
#
# The rule is deliberately narrow: it applies to units that ASK to be started
# with a graphical session (WantedBy=graphical-session.target). Units started
# some other way — aq-ingest-watch.path watches a folder and is nothing to do
# with any desktop — are exempt, and correctly so.
# ------------------------------------------------------------------------------
say "Every service of ours that starts with the desktop also stops with it"

AQ_SESSION_UNIT_FAILS=0
for aq_unit in /usr/lib/systemd/user/aquarius-*.service /usr/lib/systemd/user/aq-*.service; do
    [ -r "${aq_unit}" ] || continue
    if ! grep -qE '^WantedBy=.*graphical-session\.target' "${aq_unit}"; then
        echo "  note   $(basename "${aq_unit}") does not start with the graphical session; nothing to check"
        continue
    fi
    if grep -qE '^PartOf=.*graphical-session\.target' "${aq_unit}"; then
        ok "$(basename "${aq_unit}") stops when the desktop does"
    else
        bad "$(basename "${aq_unit}") starts with the graphical session but has no 'PartOf=graphical-session.target' — it would keep running after logout and get in the way of the next desktop"
        AQ_SESSION_UNIT_FAILS=1
    fi
done
if [ "${AQ_SESSION_UNIT_FAILS}" -eq 0 ]; then
    ok "every Aquarius user service is tied to the session's lifetime"
fi

say "The window manager's configuration"
# SIX files. menu.xml joined the list on the morning of 2026-09-06, and
# generate-theme — the program that writes labwc's colours out of the shell's
# palette — replaced the hand-written themerc-override that evening. The reason
# each was missing when it was missing is the reason this loop matters: AquariusOS does not stage the shell's session/labwc folder,
# it ships its own hand-maintained copies here. A file the shell repository adds
# does NOT appear in this image until somebody adds it here by hand, and nothing
# complains in the meantime.
#
# That last sentence is now only half true, and the better half is new:
# build_files/check-labwc-drift.sh compares this image's copies against the
# shell's, at the pinned commit, and CI fails the push if they differ. This loop
# is still worth having — it reads the FINISHED IMAGE, so it also catches a file
# that exists in the repository and never got copied in — but it is no longer
# the only thing standing between us and another silent drift.
for aq_f in rc.xml menu.xml generate-theme autostart shutdown environment; do
    if [ -s "${AQ_LABWC_DIR}/${aq_f}" ]; then
        ok "${AQ_LABWC_DIR}/${aq_f}"
    else
        bad "${AQ_LABWC_DIR}/${aq_f} is missing"
    fi
done

# rc.xml and menu.xml are XML, and labwc will not tell you politely if either is
# malformed — it starts with no key bindings at all, or with its own built-in
# menu, which both look like a shell problem.
if aq_have xmllint; then
    for aq_x in rc.xml menu.xml; do
        if xmllint --noout "${AQ_LABWC_DIR}/${aq_x}"; then
            ok "${aq_x} is well-formed XML"
        else
            bad "${aq_x} is not valid XML — labwc would ignore it silently"
        fi
    done
else
    echo "  note   xmllint is not in this image; the XML is checked in CI instead"
fi

aq_file_has "${AQ_LABWC_DIR}/rc.xml" 'qs ipc call search toggle' \
    "Super+Space summons the search palette (and does NOT pass a config name, which was the bench's correction)"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<action name="Exit" />' \
    "Super+Shift+E leaves the session"

# THE APP SWITCHER'S FIVE KEYS (2026-09-06).
#
# Hold Command, tap Tab, let go, and a panel of the applications you have open
# appears in the middle of the screen. BOTH keyboard profiles are bound at once,
# on purpose:
#
#   Mac style      Aquarius Keys swaps the two keys beside the space bar, so
#                  Command+Tab arrives at labwc as W-Tab.
#   Windows style  nothing is swapped and the remapper does not even run, so
#                  Alt+Tab arrives as A-Tab.
#
# Binding both means `aq keys mac` and `aq keys windows` never have to rebind
# anything — only what the panel LISTS changes, and the shell reads that from
# ~/.config/aquarius/keys.conf itself.
#
# These were labwc's own NextWindow and PreviousWindow until 2026-09-06. They now
# send a message to the running shell, which draws its own panel: one that can
# group five windows of an editor into one application icon, which labwc's list
# of window titles cannot.
#
# The whole feature, including how the shell knows you let go of the modifier,
# is written up in the aquarius-shell repository at docs/app-switcher.md.
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<keybind key="W-Tab">' \
    "Command+Tab opens the app switcher (Mac keyboard style)"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<keybind key="W-S-Tab">' \
    "and Command+Shift+Tab walks it backwards"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<keybind key="W-grave">' \
    "Command+\` cycles one app's windows, with no panel"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<keybind key="A-Tab">' \
    "Alt+Tab opens the same switcher (Windows keyboard style)"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<keybind key="A-S-Tab">' \
    "and Alt+Shift+Tab walks it backwards"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" 'command="qs ipc call switcher next"' \
    "and they reach the shell, rather than labwc's own switcher"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<osd show="no" />' \
    "labwc's own window switcher is switched off, so there can only be one"
aq_file_has "${AQ_LABWC_DIR}/autostart" 'aquarius-shell-start' \
    "the window manager starts the shell through the helper that reports failures"

# ------------------------------------------------------------------------------
# THE FONT labwc DRAWS ITS OWN MENU AND TITLE BARS IN
# ------------------------------------------------------------------------------
# labwc splits one look across two files: colours come from a themerc, fonts
# come from rc.xml's <theme> section. Miss the <theme> section and the
# colours still land, so the desktop menu comes up in the right blue and the
# wrong typeface — a difference nobody photographs and everybody feels. There is
# no error either way; labwc simply falls back to "sans".
#
# MenuItem is the one asked about by name because it is the row of the desktop
# right-click menu, the surface this whole 2026-09-06 pass is about.
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<theme>' \
    "rc.xml has a <theme> section, which is where labwc takes its fonts from"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<font place="MenuItem">' \
    "and it names the font for a row of the desktop right-click menu"

# ------------------------------------------------------------------------------
# THE DESKTOP RIGHT-CLICK MENU — the 2026-09-06 bench photograph
# ------------------------------------------------------------------------------
# Right-clicking the wallpaper showed labwc's OWN menu: Terminal, Reconfigure,
# Exit. Not ours. The shell repository had grown a menu.xml and a Root
# mousebind, AquariusOS ships its own copies of the labwc files, and nobody
# copied either one across.
#
# Being exact about the mechanism, because it is not what it looks like: labwc's
# own defaults ALREADY send a desktop right-click to a menu called root-menu.
# Nothing in this image declared such a menu, so labwc used its built-in
# fallback. menu.xml is therefore the fix, and rc.xml's binding is written out
# so the gesture does not depend on a labwc default and so the file stays
# comparable with the shell's copy. Both halves are read back here.
aq_file_has "${AQ_LABWC_DIR}/menu.xml" 'id="root-menu"' \
    "menu.xml declares the root-menu the desktop right-click opens"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<action name="ShowMenu" menu="root-menu" />' \
    "right-clicking the desktop opens OUR menu rather than labwc's built-in one"

# Every Settings line in the menu has to carry the XDG_CURRENT_DESKTOP=GNOME
# prefix, or the menu item is there and does nothing — see the whole section
# below for why. Checked as a count, so adding a third Settings item without the
# prefix fails the build rather than shipping one dead menu entry.
#
# ⚠️ COUNT THE <command> LINES, NOT EVERY MENTION. The first version of this
# counted every line containing "gnome-control-center", which includes the six
# lines of the header comment that EXPLAIN the prefix — so a correct menu.xml
# failed the build (2026-09-06, the first run of this branch). A menu item's
# command is always inside a <command> element, and that is the only thing being
# asked about here.
AQ_MENU_CC_TOTAL="$(grep -c '<command>.*gnome-control-center' "${AQ_LABWC_DIR}/menu.xml" || true)"
AQ_MENU_CC_FIXED="$(grep -c '<command>env XDG_CURRENT_DESKTOP=GNOME gnome-control-center' "${AQ_LABWC_DIR}/menu.xml" || true)"
echo "  menu.xml Settings commands: ${AQ_MENU_CC_FIXED} of ${AQ_MENU_CC_TOTAL} carry the GNOME prefix"
if [ "${AQ_MENU_CC_TOTAL}" -ge 2 ] && [ "${AQ_MENU_CC_FIXED}" -eq "${AQ_MENU_CC_TOTAL}" ]; then
    ok "every Settings command in the menu says 'env XDG_CURRENT_DESKTOP=GNOME' first"
else
    bad "menu.xml has a gnome-control-center command without 'env XDG_CURRENT_DESKTOP=GNOME' — that menu item would do nothing at all. See the Settings section further down this script."
fi

# ⚠️ AND THE <mouse> SECTION MUST KEEP <default />.
# A <mouse> section REPLACES labwc's mouse behaviour rather than adding to it.
# Without <default /> inside it the right-click menu would work and dragging a
# window by its title bar, edge-resize, click-to-focus and alt-drag would all
# stop — a far worse desktop than the one we set out to fix. This reads the
# mouse section on its own and looks for <default /> inside THAT, because the
# <default /> in the keyboard section is a different thing and would make a
# whole-file grep pass while the mouse was broken.
#
# The section is found by looking for a line that is NOTHING BUT the tag, which
# is why rc.xml writes those two tags on lines of their own and its comments
# avoid spelling them out: a mention in prose would be matched first and this
# would read the wrong range.
if sed -n '/^ *<mouse>$/,/^ *<\/mouse>$/p' "${AQ_LABWC_DIR}/rc.xml" | grep -q '<default />'; then
    ok "the <mouse> section keeps labwc's own bindings (window dragging, resize, click to focus)"
else
    bad "rc.xml's <mouse> section has no <default /> — adding the right-click menu would have thrown away window dragging and resizing"
fi

# ==============================================================================
# THE DESKTOP'S OWN COLOURS — GENERATED, NOT TYPED OUT
# ==============================================================================
# THE BENCH NOTE THAT STARTED THIS: "the right click menu does not have a design
# yet". It did not. Two things on an Aquarius screen are drawn by labwc and not
# by the shell — the menu that opens on a right-click of the wallpaper, and the
# title bar, border and buttons around every window — and labwc was drawing them
# in its own default Openbox grey next to a shell that is entirely Ice blue.
#
# THE FIRST FIX, on the morning of 2026-09-06, was a hand-written file called
# themerc-override holding a second copy of the shell's Ice palette. It worked
# and it could never have been enough:
#
#   ONE THEME    the shell follows the machine's light/dark setting and swaps
#                between Ice and Midnight while it runs. A themerc is read once,
#                at start-up. So a dark desktop had light title bars.
#   ONE SIZE     AQ_UI_SCALE multiplies every number in the shell and reached
#                nothing labwc drew, so a scaled desktop had an unscaled menu.
#
# THE FIX THAT REPLACED IT is /usr/share/aquarius/labwc/generate-theme. It READS
# the shell's theme/Ice.qml or theme/Midnight.qml — the same two files the shell
# itself is coloured from — and writes labwc's files out. /usr/bin/aquarius-session
# runs it at login; the shell runs it again whenever the machine goes light or
# dark, and then runs `labwc --reconfigure`; `aq keys` runs it when the window
# buttons move sides.
#
# ------------------------------------------------------------------------------
# WHAT THIS SECTION CHECKS, AND WHY IT RUNS THE PROGRAM
# ------------------------------------------------------------------------------
# There is no hand-written file left to read, so reading a file would prove
# nothing. Instead the build RUNS the generator, four times — Ice and Midnight,
# at 1x and at 1.25x — and reads back what it wrote. That is the CONTENT
# read-back rule this project has had since 2026-08-31, applied to a program
# instead of to a file.
#
# Every value asserted below comes from the window-frame design sheet of
# 2026-09-06, sections 3 to 5. A number here is the design, not a preference.
#
# ⚠️ THE PALETTE IS THE SHELL'S, AND IT MAY NOT BE IN THIS IMAGE. The shell is
# fetched at a pinned commit at build time, and if that repository was private
# when the image was built there is no shell here at all — which is a case this
# script already handles everywhere else, and is not a failure. When the palette
# is missing this section says so and is skipped; the drift check in CI runs the
# same generator against a real clone of the shell and would catch anything this
# skip lets through.
say "The colours labwc draws its own menu, title bars and buttons in"

AQ_FRAME_GEN="${AQ_LABWC_DIR}/generate-theme"
AQ_PALETTE_DIR="${AQ_SHELL_DIR}/theme"

if [ ! -x "${AQ_FRAME_GEN}" ]; then
    bad "${AQ_FRAME_GEN} is missing or not executable — nothing would give labwc the Aquarius look, and the desktop menu and every title bar would be back to Openbox grey"
elif [ ! -r "${AQ_PALETTE_DIR}/Ice.qml" ] || [ ! -r "${AQ_PALETTE_DIR}/Midnight.qml" ]; then
    echo "  note   the shell's palette is not in this image, so the generated"
    echo "         theme cannot be read back here. CI checks it against a real"
    echo "         clone of the shell (build_files/check-labwc-drift.sh)."
else
    ok "${AQ_FRAME_GEN}"

    AQ_FRAME_OUT="$(mktemp -d)"
    AQ_FRAME_BUILT=1

    for aq_case in "ice 1" "ice 1.25" "midnight 1" "midnight 1.25"; do
        # shellcheck disable=SC2086
        set -- ${aq_case}
        aq_scheme="$1"
        aq_scale="$2"

        if python3 "${AQ_FRAME_GEN}" --quiet \
                --scheme "${aq_scheme}" --scale "${aq_scale}" --buttons mac \
                --palette-dir "${AQ_PALETTE_DIR}" \
                --template-dir "${AQ_LABWC_DIR}" \
                --config-out "${AQ_FRAME_OUT}/${aq_scheme}-${aq_scale}/config" \
                --theme-out "${AQ_FRAME_OUT}/${aq_scheme}-${aq_scale}/theme" \
                --gtk-out "${AQ_FRAME_OUT}/${aq_scheme}-${aq_scale}/gtk"; then
            ok "the ${aq_scheme} theme builds at ${aq_scale}x"
        else
            bad "the generator failed for ${aq_scheme} at ${aq_scale}x — an installed machine would fall back to labwc's own grey"
            AQ_FRAME_BUILT=0
        fi
    done

    if [ "${AQ_FRAME_BUILT}" -eq 1 ]; then
        # ----------------------------------------------------------------------
        # Can labwc read what it wrote?
        # ----------------------------------------------------------------------
        # ⚠️ THE TRAP IN THIS FILE FORMAT LOOKS LIKE NOTHING. labwc has no
        # end-of-line comment syntax at all: process_line() returns early only
        # when the FIRST character is '#', and everything after the first colon
        # becomes the value. So
        #     menu.width.min: 240   # the same width as the shell's menu
        # sets the width to that whole string, which is not a number, and labwc
        # discards it without a word.
        AQ_THEMERC_BAD=0
        for aq_case in ice-1 ice-1.25 midnight-1 midnight-1.25; do
            aq_t="${AQ_FRAME_OUT}/${aq_case}/config/themerc-override"
            aq_n=0
            while IFS= read -r aq_line || [ -n "${aq_line}" ]; do
                aq_line="$(printf '%s' "${aq_line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                case "${aq_line}" in '' | '#'*) continue ;; esac
                aq_n=$((aq_n + 1))

                case "${aq_line}" in
                    *:*) ;;
                    *)
                        bad "${aq_case}: '${aq_line}' is not 'key: value', so labwc ignores it"
                        AQ_THEMERC_BAD=1
                        continue
                        ;;
                esac

                aq_value="${aq_line#*:}"
                aq_value="$(printf '%s' "${aq_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                case "${aq_value}" in
                    *'#'*)
                        if ! printf '%s' "${aq_value}" | grep -Eq '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$'; then
                            bad "${aq_case}: '${aq_line}' — the value is not a plain #rrggbb or #rrggbbaa colour. Either it is malformed, or somebody wrote an explanation after it on the same line: labwc has no end-of-line comments, so that text becomes part of the value and the whole setting is thrown away in silence."
                            AQ_THEMERC_BAD=1
                        fi
                        ;;
                esac
            done < "${aq_t}"

            if [ "${aq_n}" -lt 25 ]; then
                bad "${aq_case}: only ${aq_n} settings — the design needs about thirty, so most of the desktop's look is missing"
                AQ_THEMERC_BAD=1
            fi
        done
        [ "${AQ_THEMERC_BAD}" -eq 0 ] \
            && ok "every generated setting is one labwc can actually read"

        # ----------------------------------------------------------------------
        # The design sheet's own values, read back out of the finished files
        # ----------------------------------------------------------------------
        aq_themerc_is() {
            # $1 = ice-1 / midnight-1 / …, $2 = the setting, $3 = the value,
            # $4 = what it is for, in plain words
            aq_f="${AQ_FRAME_OUT}/$1/config/themerc-override"
            if grep -qxF "$2: $3" "${aq_f}"; then
                ok "$1: $2 is $3 — $4"
            else
                bad "$1: $2 should be '$3' ($4) and is: $(grep -E "^$2:" "${aq_f}" || echo '(missing)')"
            fi
        }

        # --- section 3, the frame, Ice ---------------------------------------
        aq_themerc_is ice-1 window.active.title.bg.color "#F0F6FC" \
            "the focused title bar is the same colour as the top bar"
        aq_themerc_is ice-1 window.inactive.title.bg.color "#E4EDF6" \
            "an unfocused one steps one rung down the surface ladder"
        aq_themerc_is ice-1 window.active.label.text.color "#16273A" \
            "the focused window's title is the primary ink"
        aq_themerc_is ice-1 window.inactive.label.text.color "#7C90A4" \
            "an unfocused title is the muted ink"
        aq_themerc_is ice-1 window.active.border.color "#16273A2E" \
            "the focused border is the strong hairline (ink at 18%)"
        aq_themerc_is ice-1 window.inactive.border.color "#16273A1A" \
            "an unfocused border is the plain hairline (ink at 10%)"
        aq_themerc_is ice-1 border.width "1" \
            "one pixel, the same weight as every other rule on screen"
        aq_themerc_is ice-1 window.label.text.justify "Center" \
            "the title is centred"

        # --- section 4, the buttons ------------------------------------------
        # THE TITLE BAR'S HEIGHT IS NOT A SETTING IN labwc 0.20. `titlebar.height`
        # was removed; the height is max(font height, button height) + 2 x
        # padding. So the two numbers below ARE the 38px title bar: 20 + 9 + 9.
        aq_themerc_is ice-1 window.button.width "20" \
            "a window button's disc is 20 across"
        aq_themerc_is ice-1 window.button.height "20" \
            "and 20 tall"
        aq_themerc_is ice-1 window.button.spacing "8" \
            "with 8 between two discs"
        aq_themerc_is ice-1 window.titlebar.padding.width "12" \
            "and 12 from the window's edge to the first one"
        aq_themerc_is ice-1 window.titlebar.padding.height "9" \
            "which is what makes the title bar 20 + 9 + 9 = 38 tall"

        # --- section 5, the desktop menu -------------------------------------
        aq_themerc_is ice-1 menu.width.min "240" \
            "the desktop menu is one fixed width, like the shell's own menu"
        aq_themerc_is ice-1 menu.width.max "240" \
            "min and max together is how labwc fixes a width"
        aq_themerc_is ice-1 menu.items.bg.color "#F7FBFE" \
            "the menu card is the brightest paper"
        aq_themerc_is ice-1 menu.items.text.color "#16273A" \
            "its text is the primary ink"
        aq_themerc_is ice-1 menu.items.active.bg.color "#2C8FC429" \
            "the row under the pointer is a wash of the accent"
        aq_themerc_is ice-1 menu.title.bg.color "#E4EDF6" \
            "a menu title is a quiet band rather than labwc's startling blue"

        # --- the Midnight column of the same tables ---------------------------
        # This is the whole reason the hand-written file had to go: until now
        # there was no Midnight at all.
        aq_themerc_is midnight-1 window.active.title.bg.color "#152033" \
            "on a dark desktop the focused title bar is Midnight's panel navy"
        aq_themerc_is midnight-1 window.inactive.title.bg.color "#1B2940" \
            "and an unfocused one steps down the same way Ice does"
        aq_themerc_is midnight-1 window.active.label.text.color "#DCE9F4" \
            "the title is Midnight's ice-blue ink"
        aq_themerc_is midnight-1 window.inactive.label.text.color "#5C6E82" \
            "and an unfocused title is its muted ink"
        aq_themerc_is midnight-1 window.active.border.color "#DCF3FF29" \
            "Midnight's hairlines are tinted ice blue, not white"
        aq_themerc_is midnight-1 window.inactive.border.color "#DCF3FF14" \
            "the quieter of the two"
        aq_themerc_is midnight-1 menu.items.bg.color "#121C2E" \
            "the dark menu card"
        aq_themerc_is midnight-1 menu.items.text.color "#DCE9F4" \
            "its ice-blue text"
        aq_themerc_is midnight-1 menu.items.active.bg.color "#00BFFF1F" \
            "and its accent wash, dialled back to 12% because Midnight's blue is brighter"

        # --- the size knob really does reach the window frames ----------------
        aq_themerc_is ice-1.25 window.button.width "25" \
            "AQ_UI_SCALE reaches labwc now: a 20px button is 25px at 1.25x"
        aq_themerc_is ice-1.25 menu.items.padding.x "20" \
            "and so does the menu's own padding"

        # --- rc.xml's half of the look ----------------------------------------
        # The corner radius, the fonts and the button side are rc.xml settings,
        # not theme settings — labwc offers no themerc key for any of them.
        aq_file_has "${AQ_FRAME_OUT}/ice-1/config/rc.xml" \
            '<cornerRadius>12</cornerRadius>' \
            "a window's top corners are rounded by 12, matching libadwaita's own fixed 12"
        aq_file_has "${AQ_FRAME_OUT}/ice-1.25/config/rc.xml" \
            '<cornerRadius>15</cornerRadius>' \
            "and that follows AQ_UI_SCALE too"
        aq_file_has "${AQ_FRAME_OUT}/ice-1/config/rc.xml" \
            '<layout>close,iconify,max:</layout>' \
            "Mac style puts close, minimise and maximise on the LEFT, close outermost"
        aq_file_has "${AQ_FRAME_OUT}/ice-1/config/rc.xml" \
            '<name>Aquarius</name>' \
            "rc.xml names the theme labwc looks the button pictures up under"
        aq_file_has "${AQ_FRAME_OUT}/ice-1/config/rc.xml" \
            '<weight>medium</weight>' \
            "a window's title is drawn at weight medium, which is Pango's 500"

        # Windows style, built on its own, because this is the half of `aq keys`
        # that has nothing to do with the keyboard.
        if python3 "${AQ_FRAME_GEN}" --quiet --scheme ice --scale 1 \
                --buttons windows \
                --palette-dir "${AQ_PALETTE_DIR}" \
                --template-dir "${AQ_LABWC_DIR}" \
                --config-out "${AQ_FRAME_OUT}/windows/config" \
                --theme-out "${AQ_FRAME_OUT}/windows/theme" \
                --gtk-out "${AQ_FRAME_OUT}/windows/gtk"; then
            aq_file_has "${AQ_FRAME_OUT}/windows/config/rc.xml" \
                '<layout>:iconify,max,close</layout>' \
                "Windows style puts minimise, maximise and close on the RIGHT, close outermost"
        else
            bad "the generator failed for the Windows button layout — 'aq keys windows' would move the buttons in GNOME and not on our own desktop"
        fi

        # --- the button pictures ----------------------------------------------
        # labwc looks these up BY EXACT NAME, in a theme folder rather than
        # beside its settings. A missing one is not an error anywhere: labwc
        # falls back to a bare built-in glyph with no disc behind it, and one
        # button quietly stops matching the other two.
        AQ_BUTTONS_MISSING=""
        for aq_case in ice-1 ice-1.25 midnight-1 midnight-1.25; do
            for aq_button in close iconify max max_toggled; do
                for aq_state in "" "_hover"; do
                    for aq_focus in active inactive; do
                        aq_svg="${AQ_FRAME_OUT}/${aq_case}/theme/${aq_button}${aq_state}-${aq_focus}.svg"
                        [ -s "${aq_svg}" ] \
                            || AQ_BUTTONS_MISSING="${AQ_BUTTONS_MISSING} ${aq_case}/$(basename "${aq_svg}")"
                    done
                done
            done
        done
        if [ -z "${AQ_BUTTONS_MISSING}" ]; then
            ok "all 16 window button pictures exist for both themes, at 1x and at 1.25x"
        else
            bad "these window button pictures were not drawn:${AQ_BUTTONS_MISSING}"
        fi

        # The close button is the one that changes COLOUR rather than weight
        # when the pointer is on it, and it is the only one that does. Read back
        # by content, because a picture that exists and is the wrong colour is
        # the failure a file-exists check cannot see.
        aq_file_has "${AQ_FRAME_OUT}/ice-1/theme/close_hover-active.svg" \
            '#C8463B' \
            "the close button goes to the Ice danger red when the pointer is on it"
        aq_file_has "${AQ_FRAME_OUT}/midnight-1/theme/close_hover-active.svg" \
            '#E07B7B' \
            "and to Midnight's own softer red on a dark desktop"
        aq_file_has "${AQ_FRAME_OUT}/ice-1/theme/iconify_hover-active.svg" \
            'fill-opacity="0.160"' \
            "the other buttons only deepen their disc, from 10% to 16%"
        aq_file_has "${AQ_FRAME_OUT}/ice-1/theme/close-inactive.svg" \
            'opacity="0.450"' \
            "and a window you are not in draws its whole button at 45%"

        # --- the Midnight GTK exception ----------------------------------------
        # Two properties, dark only. See the posture note in
        # build_files/50-aquarius-desktop.sh for why this is allowed at all.
        aq_file_has "${AQ_FRAME_OUT}/midnight-1/gtk/gtk-4.0/gtk.css" \
            'background-color: #0B1220' \
            "a dark desktop paints GTK window backgrounds Midnight navy"
        aq_file_has "${AQ_FRAME_OUT}/midnight-1/gtk/gtk-4.0/gtk.css" \
            'background-color: #152033' \
            "and their header bars the panel navy"
        aq_file_has "${AQ_FRAME_OUT}/midnight-1/gtk/gtk-3.0/gtk.css" \
            'background-color: #0B1220' \
            "older GTK applications get the same two properties"
        if [ -e "${AQ_FRAME_OUT}/ice-1/gtk/gtk-4.0/gtk.css" ]; then
            bad "the Ice theme wrote a GTK colour file — those two properties are Midnight's, and on a light desktop they would paint every GTK window navy"
        else
            ok "the Ice theme writes no GTK colour file, which is correct"
        fi
        AQ_GTK_LINES="$(grep -cE '^[a-z]' "${AQ_FRAME_OUT}/midnight-1/gtk/gtk-4.0/gtk.css" || true)"
        if [ "${AQ_GTK_LINES}" -eq 2 ]; then
            ok "the GTK file is exactly two rules and nothing else"
        else
            bad "the Midnight GTK file has ${AQ_GTK_LINES} rules. It is allowed exactly TWO — the window background and the header bar. Anything more is a GTK theme, which this project does not ship (see the posture note in build_files/50-aquarius-desktop.sh)."
        fi
    fi

    rm -rf "${AQ_FRAME_OUT}"
fi

# ==============================================================================
# 5c. THE SETTINGS APP — why it refused to open, and the one-word fix
# ==============================================================================
# THE BUG, from the bench on 2026-09-06: the Settings icon in the Aquarius dock
# did nothing. No window, no error, nothing on screen. Same for every other way
# of opening Settings from our desktop.
#
# THE CAUSE, and it is in gnome-control-center's own source code
# (shell/cc-application.c, the function is_supported_desktop()). At start-up it
# reads the XDG_CURRENT_DESKTOP environment variable, splits it on colons, and
# unless one of the parts is exactly "GNOME" or "Unity" it prints
#
#     Running gnome-control-center is only supported under GNOME and Unity,
#     exiting
#
# and exits with status 1. Our session exports
#
#     XDG_CURRENT_DESKTOP="Aquarius:wlroots"
#
# so neither part matches and Settings quits before it draws a pixel. Launched
# from a dock icon there is no terminal to print that sentence into, which is
# why it looked like nothing happened at all.
#
# WHY WE DO NOT SIMPLY RENAME THE SESSION TO GNOME. That one line in
# /usr/bin/aquarius-session is load-bearing far beyond Settings. The desktop
# portals — screen recording, screenshots, file dialogs, the light/dark setting
# — choose their back end by reading XDG_CURRENT_DESKTOP and matching it against
# /usr/share/xdg-desktop-portal/aquarius-portals.conf. Calling ourselves GNOME
# would route every one of those requests to GNOME's back ends, which cannot
# record a labwc screen. OBS would show no screens again, which is the exact
# fault the portals section of this script exists to prevent. The name stays.
#
# SO THE LIE IS TOLD PER LAUNCH, TO ONE PROGRAM. `env VAR=value program` runs
# `program` with that one variable changed and changes nothing else on the
# machine. Three places need it and they are launched three different ways:
#
#   the shell's own menus       fixed in the aquarius-shell repository
#   our labwc right-click menu  fixed in menu.xml, above
#   the dock icon               fixed HERE, because the dock launches the
#                               Exec= line out of the .desktop file
#
# The dock pins org.gnome.Settings.desktop (see
# /etc/skel/.config/aquarius-shell/dock.json) and Quickshell's
# DesktopEntry.execute() runs that file's Exec= line as written. There is no
# hook, no wrapper and no place to put an environment variable in between — so
# the Exec= line itself is what has to carry it.
#
# The D-Bus service file gets the same treatment. org.gnome.Settings.desktop
# says DBusActivatable=true, so a launcher may ask D-Bus to start Settings
# rather than running the command, and the D-Bus/systemd activation environment
# on this desktop carries XDG_CURRENT_DESKTOP=Aquarius:wlroots — the same check,
# the same silent exit, by a different road.
#
# HARMLESS UNDER GNOME. In the GNOME fallback session XDG_CURRENT_DESKTOP is
# already GNOME, so the prefix sets it to the value it already had.
#
# WHY THIS IS IN STEP 5.5 AND NOT IN STEP 4 WHERE gnome-control-center IS
# INSTALLED: the reason for the change is entirely about the Aquarius session,
# it belongs beside the identical fix in menu.xml a few lines up, and this step
# runs later — so a package transaction in step 4 cannot undo it. What it does
# NOT protect against is a LATER build step upgrading gnome-control-center and
# restoring Fedora's stock file. That is why build.yml reads both files back out
# of the FINISHED image; this check here only proves the edit happened at the
# moment it ran.
#
# `env` is written as a path, /usr/bin/env, in the D-Bus file because D-Bus
# wants an absolute program there, and as a bare `env` in the .desktop file
# because that is how .desktop Exec lines are normally written and PATH always
# has /usr/bin on it.
# ==============================================================================
say "The Settings app opens from our desktop (the XDG_CURRENT_DESKTOP check)"

AQ_CC_DESKTOP="/usr/share/applications/org.gnome.Settings.desktop"
AQ_CC_DBUS="/usr/share/dbus-1/services/org.gnome.Settings.service"

if [ -w "${AQ_CC_DESKTOP}" ]; then
    # Rewrites EVERY Exec= line in the file, including the ones in the
    # [Desktop Action ...] blocks at the bottom (Fedora ships a couple), and
    # keeps whatever comes after the program name — %U and any panel argument.
    # The (/usr/bin/)? is optional because Fedora has spelled this line both
    # ways over the years.
    sed -i -E 's|^Exec=(/usr/bin/)?gnome-control-center|Exec=env XDG_CURRENT_DESKTOP=GNOME \1gnome-control-center|' \
        "${AQ_CC_DESKTOP}"
    echo "  ${AQ_CC_DESKTOP} now says:"
    grep -E '^Exec=' "${AQ_CC_DESKTOP}" | sed 's/^/       /'
    # Read it back. Two questions, because either can be wrong on its own:
    # did the prefix land, and is there any bare line left that missed it?
    aq_file_has "${AQ_CC_DESKTOP}" '^Exec=env XDG_CURRENT_DESKTOP=GNOME .*gnome-control-center' \
        "the Settings menu entry launches Settings with XDG_CURRENT_DESKTOP=GNOME"
    if grep -Eq '^Exec=(/usr/bin/)?gnome-control-center' "${AQ_CC_DESKTOP}"; then
        bad "${AQ_CC_DESKTOP} still has an Exec= line without the prefix — that way of opening Settings would still do nothing"
    else
        ok "no Exec= line in the Settings menu entry was missed"
    fi
else
    bad "${AQ_CC_DESKTOP} is missing or not writable — the dock's Settings icon could not be fixed, and it would do nothing on the Aquarius Desktop"
fi

# The D-Bus service file is optional: not every gnome-control-center build ships
# one. Absent is fine and is said out loud; present and unfixed is not.
if [ -w "${AQ_CC_DBUS}" ]; then
    sed -i -E 's|^Exec=(/usr/bin/)?gnome-control-center|Exec=/usr/bin/env XDG_CURRENT_DESKTOP=GNOME /usr/bin/gnome-control-center|' \
        "${AQ_CC_DBUS}"
    echo "  ${AQ_CC_DBUS} now says:"
    grep -E '^Exec=' "${AQ_CC_DBUS}" | sed 's/^/       /'
    aq_file_has "${AQ_CC_DBUS}" '^Exec=/usr/bin/env XDG_CURRENT_DESKTOP=GNOME /usr/bin/gnome-control-center' \
        "D-Bus starts Settings with XDG_CURRENT_DESKTOP=GNOME too"
    if grep -Eq '^Exec=(/usr/bin/)?gnome-control-center' "${AQ_CC_DBUS}"; then
        bad "${AQ_CC_DBUS} still has an Exec= line without the prefix — a D-Bus-activated Settings would still exit at once"
    else
        ok "no Exec= line in the Settings D-Bus service file was missed"
    fi
elif [ -e "${AQ_CC_DBUS}" ]; then
    bad "${AQ_CC_DBUS} exists but could not be written to"
else
    echo "  note   ${AQ_CC_DBUS} does not exist in this image; nothing to fix there"
fi

# ==============================================================================
# 6b. SCREEN SIZE — the 2026-09-03 "everything is tiny" fix
# ==============================================================================
# labwc starts every monitor at 100%, always. On Royce's 55" 4K bench monitor
# that made the whole desktop physically tiny, while GNOME on the same machine
# had been running it at 125% for weeks.
#
# /usr/libexec/aquarius-display-scale is what closes that gap: at every login it
# works out the right size and applies it with wlr-randr, taking the answer from
# the person's own setting first, then from the scale they already chose in
# GNOME, and only then from the monitor's own reported size.
#
# Everything below RUNS it. A scaling rule that is subtly wrong produces a
# desktop that is the wrong size on somebody's machine weeks later, with no
# error anywhere, so the arithmetic is exercised here against fixed examples.
say "Screen size — the display-scale helper"

AQ_DISPLAY_HELPER="/usr/libexec/aquarius-display-scale"

# It is a Python program, so ask Python whether it is even readable before
# running it. A syntax error here would mean every screen silently stays at 100%.
#
# ⚠️ NOT `python3 -m py_compile`, which is what this line used to be. That form
# WRITES: it leaves a __pycache__ folder next to the file, so every AquariusOS
# machine has been shipping /usr/libexec/__pycache__ — bytecode that nothing can
# ever use, because Python only reads __pycache__ for imported modules and never
# for a program run directly. The rest of this repo already compiles to a
# throwaway path in /tmp for exactly this reason (62-resolve-runtime.sh,
# 66-creator-apps-chooser.sh, 67-welcome.sh); this one line was missed. Found by
# the new /usr/libexec/__pycache__ check in build.yml, 2026-09-05.
if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-display-scale-check.pyc", doraise=True)' \
    "${AQ_DISPLAY_HELPER}" 2> /dev/null; then
    ok "the display-scale helper is valid Python"
else
    bad "the display-scale helper has a syntax error — every screen would stay at 100%"
fi

# The autostart file is a shell script that labwc runs at every login. A syntax
# error in it does not stop labwc; it stops everything AFTER the bad line, which
# on this file means the wallpaper, the screen size and the bar.
if bash -n "${AQ_LABWC_DIR}/autostart"; then
    ok "the window manager's autostart file is valid shell"
else
    bad "${AQ_LABWC_DIR}/autostart has a syntax error — the bar would not start"
fi

if [ -x "${AQ_DISPLAY_HELPER}" ]; then
    ok "${AQ_DISPLAY_HELPER} is installed and executable"
else
    chmod 0755 "${AQ_DISPLAY_HELPER}" 2> /dev/null || true
    if [ -x "${AQ_DISPLAY_HELPER}" ]; then
        ok "${AQ_DISPLAY_HELPER} is installed (permissions corrected here)"
    else
        bad "${AQ_DISPLAY_HELPER} is missing — every screen would stay at 100%"
    fi
fi

# wlr-randr is the ONLY way this image can change a monitor's scale. labwc has
# no monitor settings in its own configuration file, by design: it expects to be
# told over the standard wlr-output-management protocol, which is what wlr-randr
# speaks. Without it the helper decides correctly and can do nothing about it.
if aq_have wlr-randr; then
    # Deliberately NOT `wlr-randr --version`: the tool does not have that
    # option, and asking for it prints its usage and exits non-zero, which
    # would turn a passing check into a confusing one.
    ok "wlr-randr is installed at $(command -v wlr-randr)"
else
    bad "wlr-randr is missing — the helper could work out the right scale and would have no way to apply it"
fi

# The autostart file has to actually call it, and the launcher has to pass the
# shell's own size knob through. Both are one line, and both are easy to lose.
aq_file_has "${AQ_LABWC_DIR}/autostart" 'aquarius-display-scale' \
    "the window manager sets the screen size at login"
aq_file_has "${AQ_LAUNCHER}" 'AQ_UI_SCALE' \
    "the launcher passes the bar's own size setting to the shell"

# ------------------------------------------------------------------------------
# THE ARITHMETIC, RUN AGAINST FIXED EXAMPLES
# ------------------------------------------------------------------------------
# Three cases, and the middle one is the whole reason the order exists:
#
#   1. Royce's Odyssey Ark with his GNOME setting present  -> 125%
#      (his answer, inherited, without being asked twice)
#   2. The same monitor with NO saved setting              -> 100%
#      (a 55" 4K is 81 dpi — LOWER than an office monitor. The guess alone
#      would leave it at 100%, which is why the guess is asked last.)
#   3. The same monitor with his own `aq display scale`    -> 150%
#      (his own setting beats everything, including GNOME's)
say "Checking the scaling rule against real examples"

AQ_T="$(mktemp -d)"

cat > "${AQ_T}/ark.json" << 'JSON'
[{"name":"DP-1","description":"Samsung Odyssey Ark",
  "physical_size":{"width":1210,"height":680},
  "enabled":true,"scale":1.0,
  "modes":[{"width":3840,"height":2160,"refresh":59.997,"current":true}]}]
JSON

cat > "${AQ_T}/monitors.xml" << 'XML'
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x><y>0</y><scale>1.25</scale><primary>yes</primary>
      <monitor>
        <monitorspec><connector>DP-1</connector><vendor>SAM</vendor>
          <product>Odyssey Ark</product><serial>0x1</serial></monitorspec>
        <mode><width>3840</width><height>2160</height><rate>59.997</rate></mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
XML

echo "scale=1.5" > "${AQ_T}/display.conf"

aq_scale_case() { # aq_scale_case "<what>" "<monitors.xml>" "<display.conf>" "<expected>"
    local what="$1" monitors="$2" conf="$3" want="$4" got
    got="$("${AQ_DISPLAY_HELPER}" --dry-run \
        --outputs-from "${AQ_T}/ark.json" \
        --monitors-xml "${monitors}" \
        --conf "${conf}" 2>&1)"
    if printf '%s' "${got}" | grep -q -- "${want}"; then
        ok "${what}"
    else
        bad "${what} — expected '${want}' in the answer, got:"
        printf '%s\n' "${got}" | sed 's/^/       /'
    fi
}

aq_scale_case "a saved GNOME scale is inherited (125%, Royce's bench setting)" \
    "${AQ_T}/monitors.xml" /nonexistent "125%"
aq_scale_case "with nothing saved, a 55-inch 4K is left at 100% (81 dpi — the reason the guess is asked LAST)" \
    /nonexistent /nonexistent "100%"
aq_scale_case "your own 'aq display scale' beats the GNOME setting (150%)" \
    "${AQ_T}/monitors.xml" "${AQ_T}/display.conf" "150%"

# ------------------------------------------------------------------------------
# --effective-scale: one number, for the DaVinci Resolve launcher
# ------------------------------------------------------------------------------
# ⚠️ THE 2026-09-04 BENCH REPORT: Resolve "appearing smaller". Resolve is an X11
# program, XWayland tells X11 programs the screen is always at 100%, so the
# launcher has to be told separately — and this is where it asks. If this ever
# prints something that is not a number, Resolve silently opens at the wrong
# size and nothing says why.
say "The one number the DaVinci Resolve launcher reads"
aq_effective() { # aq_effective "<what>" "<monitors.xml>" "<display.conf>" "<expected>"
    local what="$1" got
    got="$("${AQ_DISPLAY_HELPER}" --effective-scale \
        --outputs-from "${AQ_T}/ark.json" \
        --monitors-xml "$2" --conf "$3" 2>&1)"
    if [ "${got}" = "$4" ]; then
        ok "${what} — it printed ${got}"
    else
        bad "${what} — expected '$4', got '${got}'"
    fi
}
aq_effective "it agrees with the GNOME scale the session inherits" \
    "${AQ_T}/monitors.xml" /nonexistent "1.25"
aq_effective "and with your own 'aq display scale'" \
    "${AQ_T}/monitors.xml" "${AQ_T}/display.conf" "1.5"

# And with no screens at all, which is what a build machine is — and what
# running Resolve from GNOME or over SSH looks like too. It must still answer.
AQ_EFF_NOSCREEN="$("${AQ_DISPLAY_HELPER}" --effective-scale 2>&1 || true)"
case "${AQ_EFF_NOSCREEN}" in
    '' | *[!0-9.]*)
        bad "with no screens it printed '${AQ_EFF_NOSCREEN}', not a number — the launcher would have nothing to hand Resolve"
        ;;
    *) ok "with no screens at all it still answers with a number (${AQ_EFF_NOSCREEN})" ;;
esac

# The other end of the ladder: a dense laptop panel must NOT be left at 100%.
cat > "${AQ_T}/laptop.json" << 'JSON'
[{"name":"eDP-1","description":"a 14-inch 2880x1800 laptop panel",
  "physical_size":{"width":302,"height":189},
  "enabled":true,"scale":1.0,
  "modes":[{"width":2880,"height":1800,"refresh":60.0,"current":true}]}]
JSON
if "${AQ_DISPLAY_HELPER}" --dry-run --outputs-from "${AQ_T}/laptop.json" \
    --monitors-xml /nonexistent --conf /nonexistent 2>&1 | grep -q "200%"; then
    ok "a dense laptop panel (242 dpi) is scaled up to 200%"
else
    bad "a dense laptop panel was not scaled up — the ladder's top end is wrong"
fi

# A monitor that does not report its size cannot be measured. It must degrade to
# something usable rather than to a crash — every virtual machine looks like this.
cat > "${AQ_T}/nosize.json" << 'JSON'
[{"name":"Virtual-1","description":"a virtual machine's screen",
  "physical_size":{"width":0,"height":0},
  "enabled":true,"scale":1.0,
  "modes":[{"width":1920,"height":1080,"refresh":60.0,"current":true}]}]
JSON
if "${AQ_DISPLAY_HELPER}" --dry-run --outputs-from "${AQ_T}/nosize.json" \
    --monitors-xml /nonexistent --conf /nonexistent 2>&1 \
    | grep -q "does not report its physical size"; then
    ok "a monitor that will not say how big it is degrades politely"
else
    bad "a monitor with no reported size did not produce the documented fallback"
fi

# And the human-readable half of wlr-randr's output, which is what an older
# version of the tool prints instead of JSON.
cat > "${AQ_T}/plain.txt" << 'TEXT'
DP-1 "Samsung Odyssey Ark 0x0001 (DP-1)"
  Physical size: 1210x680 mm
  Enabled: yes
  Modes:
    3840x2160 px, 59.996999 Hz (preferred, current)
  Position: 0,0
  Scale: 1.000000
TEXT
if "${AQ_DISPLAY_HELPER}" --dry-run --outputs-from "${AQ_T}/plain.txt" \
    --monitors-xml "${AQ_T}/monitors.xml" --conf /nonexistent 2>&1 | grep -q "125%"; then
    ok "wlr-randr's plain-text output is read as well as its JSON"
else
    bad "the plain-text reader is broken — an older wlr-randr would leave every screen at 100%"
fi

rm -rf "${AQ_T}"

say "Portals"
if [ -r "${AQ_PORTAL_CONF}" ]; then
    ok "${AQ_PORTAL_CONF} exists"
else
    bad "${AQ_PORTAL_CONF} is missing — screen recording would silently do nothing"
fi
aq_file_has "${AQ_PORTAL_CONF}" '^default=gtk$' "everything unlisted is answered by the GTK back end"
aq_file_has "${AQ_PORTAL_CONF}" '^org\.freedesktop\.impl\.portal\.ScreenCast=wlr$' "screen recording goes to the wlroots back end"
aq_file_has "${AQ_PORTAL_CONF}" '^org\.freedesktop\.impl\.portal\.Screenshot=wlr$' "screenshots go to the wlroots back end"
aq_file_has "${AQ_PORTAL_CONF}" '^org\.freedesktop\.impl\.portal\.Settings=gtk$' "light/dark follows the system setting"

# GNOME's own portal configuration has to be exactly as it was. If our file had
# been written with the wrong name it would land on top of GNOME's and break
# screen sharing in the fallback desktop — which would be a much worse bug than
# the one it was meant to fix.
if [ -r /usr/share/xdg-desktop-portal/gnome-portals.conf ]; then
    ok "GNOME's own portal configuration is untouched"
else
    echo "  note   this image ships no gnome-portals.conf; GNOME uses the built-in default"
fi

aq_file_has /etc/xdg/xdg-desktop-portal-wlr/config '^chooser_type=simple$' \
    "screen recording asks which screen, rather than guessing"
aq_file_has /etc/xdg/xdg-desktop-portal-wlr/config '^chooser_cmd=slurp' \
    "and it asks with slurp"

# ==============================================================================
# 8. The thing that asks you for your password
# ==============================================================================
# ⚠️ THIS SECTION EXISTS BECAUSE OF THE BENCH TEST, 2026-09-04. Pressing
#    "Install" in the creator-apps window failed with "Error creating textual
#    authentication agent … /dev/tty", which is `pkexec` finding that nothing in
#    this session is able to ask for a password.
#
# ⚠️ AND IT CORRECTS SOMETHING THIS FILE USED TO CLAIM. Until today the section
#    below said "the Aquarius Shell IS the permission-prompt agent for this
#    session". That was the plan, not the fact. Quickshell has a polkit module
#    and the shell's documentation mentions polkit, but the shell does not
#    register an agent, and a plan written down as a fact is how a session ships
#    without one.
#
# So the image now installs an agent and the session starts it, with a guard so
# that a shell which one day grows its own always wins. The whole arrangement,
# including why "is an agent already registered?" is a question nobody can ask,
# is in the header of /usr/libexec/aquarius-polkit-agent.
say "The polkit authentication agent"
aq_installed lxqt-policykit polkit-qt6-1

AQ_POLKIT_HELPER=/usr/libexec/aquarius-polkit-agent
AQ_POLKIT_BIN=/usr/libexec/lxqt-policykit-agent

if [ -x "${AQ_POLKIT_BIN}" ]; then
    ok "the agent itself is here: ${AQ_POLKIT_BIN}"
else
    bad "${AQ_POLKIT_BIN} is missing — nothing in the Aquarius Session could ask for a password"
fi

if [ -x "${AQ_POLKIT_HELPER}" ]; then
    ok "aquarius-polkit-agent is present and runnable"
else
    bad "${AQ_POLKIT_HELPER} is missing or not runnable"
fi
if bash -n "${AQ_POLKIT_HELPER}"; then
    ok "aquarius-polkit-agent is valid shell"
else
    bad "${AQ_POLKIT_HELPER} has a syntax error"
fi

# Run it for real, in the mode that changes nothing. This is the check that
# would have caught the fault: it proves the helper can FIND an agent on this
# image, rather than proving a package is installed and hoping.
if "${AQ_POLKIT_HELPER}" --which > /tmp/aq-polkit-which.txt 2>&1; then
    ok "the helper finds an agent on this image: $(cat /tmp/aq-polkit-which.txt)"
else
    bad "the helper cannot find any authentication agent on this image"
    cat /tmp/aq-polkit-which.txt
fi
if "${AQ_POLKIT_HELPER}" --dry-run > /tmp/aq-polkit-dry.txt 2>&1; then
    ok "the helper's rehearsal runs"
    sed 's/^/       /' /tmp/aq-polkit-dry.txt
else
    bad "the helper's rehearsal does not run"
    cat /tmp/aq-polkit-dry.txt
fi
rm -f /tmp/aq-polkit-which.txt /tmp/aq-polkit-dry.txt

# And the session has to actually start it. labwc reads one file; if the line is
# not in that file, everything above is a package nobody runs.
aq_file_has "${AQ_LABWC_DIR}/autostart" 'aquarius-polkit-agent' \
    "the Aquarius session starts the authentication agent at login"

# ------------------------------------------------------------------------------
# Switch OFF the agent's own autostart entry
# ------------------------------------------------------------------------------
# lxqt-policykit ships /etc/xdg/autostart/lxqt-policykit-agent.desktop. labwc
# never looks in that folder, so it does nothing for us — but GNOME reads it at
# every login, and GNOME already has an agent of its own inside GNOME Shell.
# Two agents in one session is a race: one registers, the other is refused, and
# which one you got is decided by timing.
#
# Hidden=true is the freedesktop way to say "ignore this entry". It switches the
# entry off in EVERY session, including ours — which is right, because ours does
# not read the folder and starts the agent deliberately, through the helper,
# with the guard.
say "The agent does not also start itself in GNOME"
AQ_POLKIT_AUTOSTART=/etc/xdg/autostart/lxqt-policykit-agent.desktop
if [ -e "${AQ_POLKIT_AUTOSTART}" ]; then
    if ! grep -q '^Hidden=true$' "${AQ_POLKIT_AUTOSTART}"; then
        printf 'Hidden=true\n' >> "${AQ_POLKIT_AUTOSTART}"
    fi
    aq_file_has "${AQ_POLKIT_AUTOSTART}" '^Hidden=true$' \
        "the agent's own autostart entry is switched off, so GNOME does not start a second agent"
else
    ok "the agent ships no autostart entry of its own — nothing to switch off"
fi

# ==============================================================================
# 8b. Nothing else in this session may fight the shell
# ==============================================================================
# The Aquarius Shell IS the notification service for this session. A second one
# would race it for the same D-Bus name, and whichever lost would be the one
# whose notifications never appear — intermittently, differently on each boot.
#
# The reason this is safe: labwc does not read /etc/xdg/autostart at all. It
# runs exactly one file, the `autostart` next to rc.xml, and that file is ours.
# So the dozens of .desktop files in /etc/xdg/autostart that GNOME processes are
# simply never seen by this session.
#
# This check is here to notice if that ever stops being true — for instance if a
# future step adds a notification daemon as a systemd USER service, which WOULD
# start, because the autostart file starts graphical-session.target.
say "Nothing else claims to be the notification service or the permission agent"
find /usr/lib/systemd/user /etc/systemd/user -name '*.service' \
    -exec grep -lE 'org\.freedesktop\.Notifications|policykit.*agent|polkit.*agent' {} + \
    2> /dev/null | sort > /tmp/aq-rivals.txt || true

if [ -s /tmp/aq-rivals.txt ]; then
    echo "  services that could claim one of those names if something started them:"
    sed 's/^/       /' /tmp/aq-rivals.txt
    # Being installed is fine. Being WANTED BY graphical-session.target is not,
    # because that is the target our autostart file starts.
    aq_wanted=0
    while read -r aq_unit; do
        if grep -qE '^(WantedBy|PartOf)=.*graphical-session\.target' "${aq_unit}"; then
            bad "$(basename "${aq_unit}") starts itself with any graphical session, including ours — it would fight the shell"
            aq_wanted=1
        fi
    done < /tmp/aq-rivals.txt
    if [ "${aq_wanted}" -eq 0 ]; then
        ok "none of them start themselves with a graphical session"
    fi
else
    ok "nothing in the image offers to be a notification service or permission agent"
fi
rm -f /tmp/aq-rivals.txt

# ==============================================================================
# 9. The login managers
# ==============================================================================
say "Login managers"
if systemctl is-enabled gdm.service > /dev/null 2>&1; then
    ok "GDM is switched on (this is the login screen AquariusOS uses)"
else
    bad "GDM is not switched on — nothing would draw a login screen"
fi

if systemctl is-enabled greetd.service > /dev/null 2>&1; then
    bad "greetd is switched on as well — two login managers is a black screen"
else
    ok "greetd is installed but switched off, as intended"
fi

aq_installed greetd greetd-selinux tuigreet xdg-desktop-portal-wlr

echo
echo "  To try the AquariusOS login screen:"
echo "    sudo aq login use greetd    then restart"
echo "  And to go back to GNOME's:"
echo "    sudo aq login use gdm       then restart"
echo "  Either command works from a text console (Ctrl+Alt+F3)."
echo "  The guide: docs/restart/login.md"

aq_finish "The Aquarius Desktop"
