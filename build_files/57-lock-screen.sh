#!/usr/bin/bash
# ==============================================================================
# BUILD STEP — the lock screen
# ==============================================================================
# WHAT THE LOCK SCREEN IS
#
# Press Super+L, pick "Lock Screen" from the Aquarius menu, or walk away from
# the machine for ten minutes, and every screen is covered. A clock on a frosted
# picture of the wallpaper; start typing and a card appears with your name and a
# password box.
#
# The drawing of it is the Aquarius Shell's, in the shell repository's lock/
# folder, and it arrives with everything else at step 5.5. This step is the
# OPERATING SYSTEM's half of it, which is three things:
#
#   1. /etc/pam.d/aquarius-lock  — the rules that let the lock screen ask
#                                  "is this really you". Without this file
#                                  nobody can unlock the machine.
#   2. the sleep service         — lock the screen before the machine suspends,
#                                  so closing a laptop lid is safe.
#   3. wlopm                     — the little program that turns the monitor off
#                                  after fifteen minutes.
#
# and then reading all of it back, because a lock screen that cannot let you in
# is the most expensive kind of broken this project can ship.
#
# ------------------------------------------------------------------------------
# ⚠️ WHY THE PASSWORD CHECK IS NOT OURS, AND WHY THAT IS THE POINT
# ------------------------------------------------------------------------------
# The Aquarius Shell never checks a password. It is not allowed to: a program
# that could check a password by itself could also be argued into saying yes.
#
# What happens instead, in four steps:
#
#   1. The shell hands the typed text to Quickshell's PamContext, which FORKS A
#      SEPARATE SMALL PROCESS. The whole conversation happens in there, in C,
#      against libpam, over a pipe. That is Quickshell's code, not ours.
#   2. That process asks PAM to authenticate using the rules named
#      "aquarius-lock" — the file this step installs.
#   3. Those rules say `include login`: use whatever this machine's ordinary
#      login rules are. A fingerprint reader, a smart card or a password policy
#      added to the machine reaches the lock screen for free.
#   4. PAM's pam_unix cannot read /etc/shadow either, because it is running as
#      you. It hands off to /usr/bin/unix_chkpwd — Fedora's own tiny setuid
#      helper, which will only ever check the password of the person who ran it.
#
# Nothing AquariusOS ships is setuid. Nothing of ours reads a password file.
# swaylock, hyprlock and gtklock all work exactly this way on Fedora, down to
# the one-line pam.d file.
#
# ------------------------------------------------------------------------------
# WHAT THIS STEP CANNOT CHECK
# ------------------------------------------------------------------------------
# Whether a password is actually accepted. There is no account, no password and
# no session inside a build container, and inventing one to test against would
# be testing our own invention. The bench is where that is answered — the test
# list is in docs/restart/desktop-identity.md.
#
# What CAN be checked here is everything that would make the answer impossible:
# a missing rules file, a rules file naming a module that is not installed, the
# QML not being in the image, the shell asking for a different rules file from
# the one we ship, the blur's Qt module missing, and the key binding not being
# bound.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AQ_PAM_FILE="/etc/pam.d/aquarius-lock"
AQ_SHELL_DIR="/usr/share/aquarius/shell"
AQ_LOCK_DIR="${AQ_SHELL_DIR}/lock"
AQ_SLEEP_UNIT="/usr/lib/systemd/system/aquarius-lock-on-sleep.service"
AQ_SLEEP_LINK="/usr/lib/systemd/system/sleep.target.wants/aquarius-lock-on-sleep.service"
AQ_SLEEP_HELPER="/usr/libexec/aquarius-lock-on-sleep"
AQ_LABWC_RC="/usr/share/aquarius/labwc/rc.xml"

# ==============================================================================
# 1. The one program the lock screen runs
# ==============================================================================
# After fifteen minutes the monitor should turn off. There is no Quickshell type
# for that, so the shell runs `wlopm`, which speaks the standard
# wlr-output-power-management protocol that labwc implements.
#
# ⚠️ NOT `wlr-randr --output X --off`, which is already in this image and looks
# like it would do the same thing. labwc's own documentation warns against it
# for this purpose: turning an output off that way makes the compositor
# re-arrange every window, and they do not all come back where they were.
say "The program that turns the monitor off"
aq_dnf install wlopm
aq_installed wlopm

if aq_have wlopm; then
    ok "wlopm is on the path"
else
    bad "wlopm is missing — the screen would never turn off after fifteen minutes"
fi

# ==============================================================================
# 2. Permissions on the files step 5 copied in
# ==============================================================================
# /usr is read-only on this operating system and a writable file there is a
# security hole. The pam.d file is read by a program deciding whether to let
# somebody in, so it is read-only to everyone but root, and it must NOT be
# executable — a pam.d file is a list, never a program.
say "Permissions"

# Guarded with `if` rather than `&&`, because this script runs under `set -e`
# and a bare `[ -e … ] && chmod …` whose test fails is a failing command at the
# top level — which would stop the build with no message at all. The checks
# below are what report a missing file, in words.
if [ -e "${AQ_PAM_FILE}" ]; then chmod 0644 "${AQ_PAM_FILE}"; fi
if [ -e "${AQ_SLEEP_UNIT}" ]; then chmod 0644 "${AQ_SLEEP_UNIT}"; fi
if [ -e "${AQ_SLEEP_HELPER}" ]; then chmod 0755 "${AQ_SLEEP_HELPER}"; fi

for aq_f in "${AQ_PAM_FILE}" "${AQ_SLEEP_UNIT}" "${AQ_SLEEP_HELPER}"; do
    if [ -e "${aq_f}" ]; then
        echo "       $(stat -c '%A %U:%G %n' "${aq_f}")"
    else
        echo "       (missing) ${aq_f}"
    fi
done

# ==============================================================================
# 3. The rules that let the lock screen ask "is this really you"
# ==============================================================================
say "The lock screen's PAM rules"

if [ -r "${AQ_PAM_FILE}" ]; then
    ok "${AQ_PAM_FILE} exists"
else
    bad "${AQ_PAM_FILE} is missing — NOBODY COULD UNLOCK THIS MACHINE. The shell asks PAM for a configuration by that exact name (lock/LockState.qml, config: \"aquarius-lock\") and PamContext refuses to start when the file is not there."
fi

# The one line that does the work. Written as three separate checks rather than
# one, so that a failure says WHICH part changed.
aq_file_has "${AQ_PAM_FILE}" '^auth[[:space:]]+include[[:space:]]+login$' \
    "it inherits this machine's ordinary login rules (auth include login)"

# A pam.d file that declared account/password/session rules would be doing more
# than asking one question about somebody already logged in — it would be
# opening a session, with SELinux contexts and a login audit id and a private
# /tmp. That is not what a lock screen does and would be a real fault.
if grep -qE '^[[:space:]]*(account|password|session)[[:space:]]' "${AQ_PAM_FILE}"; then
    bad "${AQ_PAM_FILE} declares account/password/session rules. A lock screen only ever asks the auth question; the rest belongs to opening a session, which this is not doing."
else
    ok "it declares only the auth question, which is the only one a lock screen asks"
fi

# `include login` is worth nothing if /etc/pam.d/login is not there.
if [ -r /etc/pam.d/login ]; then
    ok "/etc/pam.d/login exists for it to include"
    echo "       what it inherits (the auth half of /etc/pam.d/login):"
    grep -E '^auth' /etc/pam.d/login | sed 's/^/         /'
else
    bad "/etc/pam.d/login is missing, so 'include login' would resolve to nothing and no password would ever be accepted"
fi

# The bottom of the chain: the one thing in the whole path that IS privileged,
# and it is Fedora's, not ours.
say "The one privileged piece, and it is Fedora's"

if [ -u /usr/bin/unix_chkpwd ]; then
    ok "/usr/bin/unix_chkpwd is present and setuid — $(stat -c '%A %U:%G' /usr/bin/unix_chkpwd)"
    echo "       This is the ONLY thing in the chain allowed to read /etc/shadow,"
    echo "       it comes from Fedora's pam package, and it will only ever check"
    echo "       the password of the person who ran it."
else
    bad "/usr/bin/unix_chkpwd is missing or is not setuid. pam_unix hands the password check to it because nothing else in the chain can read /etc/shadow; without it, a correct password would be rejected."
fi

# And ours is not privileged, which is the other half of the same statement.
if [ -u "${AQ_SLEEP_HELPER}" ] || [ -g "${AQ_SLEEP_HELPER}" ]; then
    bad "${AQ_SLEEP_HELPER} is setuid or setgid. Nothing AquariusOS ships in this path may be — the whole design is that Fedora's unix_chkpwd is the only privileged step."
else
    ok "aquarius-lock-on-sleep has no special powers, as intended"
fi

# ==============================================================================
# 4. The lock screen itself — is it actually in the image?
# ==============================================================================
# The QML comes from the shell repository. If the shell could not be fetched at
# all, that is a warning and not a failure — the same rule step 5.5 applies, and
# for the same reason — but if the shell IS here and its lock folder is not,
# something changed in that repository and this image would ship a Super+L that
# does nothing.
say "The lock screen's own files"

if [ ! -s "${AQ_SHELL_DIR}/shell.qml" ]; then
    echo "  NOTE   the Aquarius Shell is not in this image, so there is no lock"
    echo "         screen either. Everything above still applies the day it"
    echo "         arrives. See /usr/share/aquarius/shell-build.txt."
else
    for aq_f in qmldir LockState.qml LockLayer.qml LockSurface.qml LockCard.qml \
        LockField.qml LockVeil.qml LockBlur.qml LockIdle.qml lock.qml; do
        if [ -s "${AQ_LOCK_DIR}/${aq_f}" ]; then
            ok "lock/${aq_f}"
        else
            bad "${AQ_LOCK_DIR}/${aq_f} is missing — Super+L would do nothing"
        fi
    done

    # ⚠️ THE TWO REPOSITORIES HAVE TO AGREE ON ONE NAME.
    # The shell asks PAM for a configuration called "aquarius-lock"; this image
    # installs /etc/pam.d/aquarius-lock. If either side is renamed on its own,
    # PamContext refuses to start and the card says the computer cannot check
    # passwords — which is honest, and still means nobody gets in.
    aq_file_has "${AQ_LOCK_DIR}/LockState.qml" 'config: "aquarius-lock"' \
        "the shell asks for the rules this image installs"

    # And the other direction of the same contract: the key binding runs a
    # command, and the shell has to answer to it.
    aq_file_has "${AQ_LOCK_DIR}/LockLayer.qml" 'target: "lock"' \
        "the shell answers to the IPC target the key binding calls"

    # ⚠️ THE BLUR'S Qt MODULE. lock/LockBlur.qml is the only file in the shell
    # that imports QtQuick.Effects, and it is deliberately alone behind a Loader
    # so that a missing module costs a slightly plainer veil rather than a lock
    # screen that will not load. This checks the module is really here anyway,
    # because the fallback is a safety net and not a plan.
    if [ -d /usr/lib64/qt6/qml/QtQuick/Effects ]; then
        ok "QtQuick.Effects is installed, so the veil gets its real blur"
    else
        bad "/usr/lib64/qt6/qml/QtQuick/Effects is missing. The lock screen would still work — LockBlur.qml is quarantined behind a Loader for exactly this — but the veil would fall back to the plain wallpaper under a heavier wash. It comes with qt6-qtdeclarative, which step 5.5 installs."
    fi
fi

# ==============================================================================
# 5. Super+L
# ==============================================================================
# The key binding lives in the window manager's configuration, which this image
# ships its own copy of. build_files/check-labwc-drift.sh keeps that copy and
# the shell's identical; this checks the INSTALLED file, which is the one a
# person's keyboard actually reaches.
say "The lock key bindings: Ctrl+Cmd+Q (Mac keys) and Win+L (Windows keys)"

if [ -r "${AQ_LABWC_RC}" ]; then
    if python3 - "${AQ_LABWC_RC}" <<'PYTHON'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
# Two keys, one per keyboard style (Royce, 2026-09-07): C-W-q is Ctrl+Cmd+Q in
# Mac mode, W-l is Win+L in Windows mode. Cmd+L cannot be the lock — Aquarius
# Keys turns it into Ctrl+L for the address bar before labwc ever sees it.
wanted = {'C-W-q', 'W-l'}
bound = set()
for keybind in root.iter('keybind'):
    key = keybind.get('key')
    if key not in wanted:
        continue
    for action in keybind:
        if action.get('name') == 'Execute' \
                and action.get('command') == 'qs ipc call lock lock':
            bound.add(key)
missing = sorted(wanted - bound)
if missing:
    sys.stderr.write('not bound to `qs ipc call lock lock`: %s\n' % ', '.join(missing))
    sys.exit(1)
sys.exit(0)
PYTHON
    then
        ok "Ctrl+Cmd+Q (C-W-q) and Win+L (W-l) both run 'qs ipc call lock lock'"
    else
        bad "${AQ_LABWC_RC} does not bind both lock keys (see the line above). It needs keybinds on C-W-q and on W-l, each with an Execute action running: qs ipc call lock lock"
    fi
else
    bad "${AQ_LABWC_RC} is missing"
fi

# ==============================================================================
# 6. Locking before the machine sleeps
# ==============================================================================
# A laptop lid closing, the Sleep row in the Aquarius menu, the Sleep word on
# the lock screen's own card, and the machine suspending on its own all end up
# at systemd's sleep.target. The service below is hooked onto it.
say "Locking the screen before the machine sleeps"

if [ -r "${AQ_SLEEP_UNIT}" ]; then
    ok "${AQ_SLEEP_UNIT} exists"
else
    bad "${AQ_SLEEP_UNIT} is missing — closing a laptop lid would leave the desktop unlocked on the other side of a suspend"
fi

# Both lines matter and they are not the same line. WantedBy says "run when the
# machine is about to sleep"; Before says "and finish before it actually does".
# Without the second, systemd may suspend while the lock is still on its way.
aq_file_has "${AQ_SLEEP_UNIT}" '^Before=sleep\.target$' \
    "the lock finishes BEFORE the machine suspends, not alongside it"
aq_file_has "${AQ_SLEEP_UNIT}" '^WantedBy=sleep\.target$' \
    "it is hooked onto sleeping at all"
aq_file_has "${AQ_SLEEP_UNIT}" '^Type=oneshot$' \
    "it is a oneshot, which is what gives Before= something to wait for"
aq_file_has "${AQ_SLEEP_UNIT}" "^ExecStart=${AQ_SLEEP_HELPER}\$" \
    "it runs the helper this image installs"

# Switched on by a link shipped inside the read-only half of the system, so an
# update always restores it. Same arrangement as every other Aquarius service —
# see the long note beside aq_unit_is_on_from_usr in aq-lib.sh.
if [ -L "${AQ_SLEEP_LINK}" ]; then
    ok "it is switched on ($(readlink "${AQ_SLEEP_LINK}"))"
else
    bad "${AQ_SLEEP_LINK} is missing, so the service is installed and would never run"
fi

if [ -e "/etc/systemd/system/sleep.target.wants/aquarius-lock-on-sleep.service" ]; then
    bad "aquarius-lock-on-sleep is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "it is switched on from /usr only, so an update cannot lose it"
fi

if [ -x "${AQ_SLEEP_HELPER}" ]; then
    ok "${AQ_SLEEP_HELPER} is present and runnable"
else
    bad "${AQ_SLEEP_HELPER} is missing or not executable"
fi

# It is a shell script that runs as root during a suspend. Reading it for syntax
# costs nothing and a syntax error in it would be found at the worst moment.
if bash -n "${AQ_SLEEP_HELPER}"; then
    ok "the helper is valid bash"
else
    bad "${AQ_SLEEP_HELPER} does not parse as bash"
fi

# The one line it exists to run has to be the same line the key binding runs.
aq_file_has "${AQ_SLEEP_HELPER}" 'qs ipc call lock lock' \
    "it sends the same message Super+L does"

# runuser is what drops from root to the person whose session is being locked.
# It comes with util-linux and is always here, but "always" is what this file is
# for.
if aq_have runuser; then
    ok "runuser is on the path, so the helper can drop to the person's account"
else
    bad "runuser is missing — the helper runs as root and has no way to speak to a person's shell"
fi

aq_finish "The lock screen"
