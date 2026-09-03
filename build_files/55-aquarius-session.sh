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
# greetd is a small modern login manager, and it is where the Aquarius Desktop
# is eventually going — a login screen drawn by our own shell. It is INSTALLED
# by this step and DISABLED. GDM stays the login screen, because GDM is what has
# been proven on the bench and because the GNOME fallback expects it.
#
# Switching over is two commands, documented in docs/restart/aquarius-session.md
# and printed at the bottom of this script's log. Switching back is two more.
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
aq_dnf install \
    xdg-desktop-portal-wlr \
    swaybg \
    slurp \
    wlr-randr \
    brightnessctl \
    zenity \
    libnotify

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
# greetd — an alternative login screen for AquariusOS
# =============================================================================
# THIS IS NOT SWITCHED ON. AquariusOS uses GDM, the GNOME login screen. This
# file is here, configured and ready, for the day the Aquarius Desktop has a
# login screen of its own.
#
# To switch to greetd (and back), see docs/restart/aquarius-session.md. It is
# two commands each way and both are reversible.
#
# WHAT IT WOULD DO IF SWITCHED ON
#   greetd itself draws nothing. It starts one program, on one virtual terminal,
#   and that program asks for the password. The program named below is tuigreet,
#   a text login screen that lists the sessions it finds and lets you pick one
#   with the arrow keys. It is not pretty, and it is not meant to be — a
#   graphical greeter drawn by the Aquarius Shell is the eventual answer, and
#   this is the honest interim.
# =============================================================================

[terminal]
# Which virtual terminal the login screen appears on. 1 is the one a PC shows
# after boot.
vt = 1

[default_session]
# --remember          fill in the last username automatically
# --remember-session  and the session they last chose
# --asterisks         show * as the password is typed, so a person can see that
#                     the keyboard is working at all
# --time              a clock, which is the cheapest possible signal that the
#                     machine is alive
# --sessions          where to find the things that can be logged into. Both
#                     "Aquarius Desktop" and "GNOME" live in the first folder;
#                     the second is where a hand-installed session would go.
command = "tuigreet --remember --remember-session --asterisks --time --sessions /usr/share/wayland-sessions:/usr/local/share/wayland-sessions"

# greetd runs the login screen as its own unprivileged user, so a bug in the
# greeter is not a bug running as root. The greetd package creates this user.
user = "greetd"
AQ_GREETD_CONF
chmod 0644 /etc/greetd/config.toml

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
chmod 0755 "${AQ_LAUNCHER}" /usr/libexec/aquarius-shell-start
chmod 0644 "${AQ_SESSION_ENTRY}" "${AQ_PORTAL_CONF}"
chmod 0644 "${AQ_LABWC_DIR}"/*
chmod 0755 "${AQ_LABWC_DIR}"

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

say "The window manager's configuration"
for aq_f in rc.xml autostart shutdown environment; do
    if [ -s "${AQ_LABWC_DIR}/${aq_f}" ]; then
        ok "${AQ_LABWC_DIR}/${aq_f}"
    else
        bad "${AQ_LABWC_DIR}/${aq_f} is missing"
    fi
done

# rc.xml is XML, and labwc will not tell you politely if it is malformed — it
# starts with no key bindings at all, which looks like a shell problem.
if aq_have xmllint; then
    if xmllint --noout "${AQ_LABWC_DIR}/rc.xml"; then
        ok "rc.xml is well-formed XML"
    else
        bad "rc.xml is not valid XML — labwc would start with no key bindings"
    fi
else
    echo "  note   xmllint is not in this image; rc.xml is checked in CI instead"
fi

aq_file_has "${AQ_LABWC_DIR}/rc.xml" 'qs ipc call search toggle' \
    "Super+Space summons the search palette (and does NOT pass a config name, which was the bench's correction)"
aq_file_has "${AQ_LABWC_DIR}/rc.xml" '<action name="Exit" />' \
    "Super+Shift+E leaves the session"
aq_file_has "${AQ_LABWC_DIR}/autostart" 'aquarius-shell-start' \
    "the window manager starts the shell through the helper that reports failures"

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
if python3 -m py_compile "${AQ_DISPLAY_HELPER}" 2> /dev/null; then
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
    ok "wlr-randr is installed ($(wlr-randr --version 2>&1 | head -1))"
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
# 8. Nothing in this session may fight the shell
# ==============================================================================
# The Aquarius Shell IS the notification service and IS the permission-prompt
# agent for this session. A second one of either would race it for the same
# D-Bus name, and whichever lost would be the one whose notifications never
# appear — intermittently, differently on each boot.
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
echo "  To switch this machine to greetd later:"
echo "    sudo systemctl disable gdm && sudo systemctl enable greetd && sudo systemctl reboot"
echo "  And back again:"
echo "    sudo systemctl disable greetd && sudo systemctl enable gdm && sudo systemctl reboot"

aq_finish "The Aquarius Desktop"
