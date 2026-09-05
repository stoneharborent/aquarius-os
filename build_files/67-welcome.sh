#!/usr/bin/bash
# ==============================================================================
# STEP 7d-bis — the welcome ("Welcome to AquariusOS")
# ==============================================================================
# WHAT THIS IS, IN PLAIN ENGLISH
#
# Step 7d put the creator-apps window into the image. This step puts in the
# window that comes BEFORE it — the one a brand-new person actually meets first.
#
#     Step 1 of 3   How should keyboard shortcuts work?   Mac, or Windows.
#     Step 2 of 3   Your creator apps.                    (step 7d's window)
#     Step 3 of 3   You're set.                           Three tips, and out.
#
# ⚠️ THE DESIGN DECISION THIS STEP IMPLEMENTS, 2026-09-04 (roadmap Phase R5):
#    ONE FIRST-BOOT FLOW, NOT TWO WINDOWS THAT DO NOT KNOW ABOUT EACH OTHER.
#
#    And the reason step 1 exists at all: AquariusOS remaps the keyboard to
#    work like a Mac BY DEFAULT (Copy is ⌘C). That is deliberate, it is unusual,
#    and it is exactly the sort of thing an operating system must say out loud
#    on its first screen rather than let somebody discover when their Ctrl+C
#    stops working.
#
# One program is added:
#
#   /usr/libexec/aquarius-welcome
#       The window. Python, GTK 4 and libadwaita, built on the same shared
#       pieces as the chooser and the two DaVinci Resolve windows. It writes no
#       settings file of its own — step 1 runs `aq keys mac|windows`, which is
#       the same command a person would type.
#
# ...and two menu entries: the hidden one in /etc/xdg/autostart that opens it
# once at a first GNOME login, and a hidden app entry so `aq welcome` and the
# app-launching machinery can find it.
#
# ------------------------------------------------------------------------------
# WHAT THIS STEP CHECKS, AND WHY EACH CHECK IS HERE
# ------------------------------------------------------------------------------
# Every check reads CONTENT — a file's text, a command's answer — and never a
# timestamp, for the reason at the top of aq-lib.sh.
#
# The two that matter most:
#
#   * Mac is still the preselected answer. It is written down in four places in
#     this operating system (/etc/skel, aquarius-keys-run, `aq keys status`, and
#     now this window). A welcome that preselected the other one would be the
#     system disagreeing with itself on its own first screen, and no screenshot
#     would catch it because both cards look fine.
#
#   * The old first-login entries are GONE, and the two new ones exist AND RUN
#     THE SAME COMMAND. GNOME reads /etc/xdg/autostart; labwc reads exactly one
#     file and never that folder. So the same fact is written down twice, and
#     two copies of a fact is two chances for them to drift.
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

WELCOME=/usr/libexec/aquarius-welcome
CHOOSER=/usr/libexec/aquarius-creator-apps
APP_ENTRY=/usr/share/applications/aquarius-welcome.desktop
AUTOSTART=/etc/xdg/autostart/aquarius-welcome-firstrun.desktop
OLD_AUTOSTART=/etc/xdg/autostart/aquarius-creator-apps-firstrun.desktop
LABWC_AUTOSTART=/usr/share/aquarius/labwc/autostart
AQ=/usr/bin/aq

# ==============================================================================
# 1. Is it here, and can Python read it?
# ==============================================================================
# GTK 4, libadwaita and python3-gobject were all asked for by name in step 7d,
# which runs just before this one, so nothing is installed here. That is
# deliberate: this window and the chooser are built out of exactly the same
# pieces, and asking for them twice would let the two lists drift apart.
say "The welcome window"

if [ -x "${WELCOME}" ]; then
    ok "$(basename "${WELCOME}") is here and is runnable"
else
    bad "${WELCOME} is missing or is not runnable"
fi

# ⚠️ NOT `python3 -m py_compile`, which would leave a __pycache__ folder in
#    /usr/libexec forever, in the shipped image, as a souvenir of the build.
if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-welcome.pyc", doraise=True)' \
    "${WELCOME}"; then
    ok "the welcome is valid Python"
else
    bad "the welcome is not valid Python"
fi
rm -f /tmp/aq-welcome.pyc

say "It knows where the shared window pieces are"
aq_file_has "${WELCOME}" 'sys\.path\.insert\(0, "/usr/lib/aquarius/python"\)' \
    "the welcome adds the shared-window folder to its search path"
aq_file_has "${WELCOME}" 'aquarius_ui\.hero\(' \
    "every page is built on the shared hero helper, so every page carries the Aquarius mark"
# The same rule as the other three windows: the widget that cannot show our
# logo must not come back.
if grep -q 'Adw\.StatusPage(' "${WELCOME}"; then
    bad "the welcome builds an Adw.StatusPage — it cannot show the Aquarius mark"
else
    ok "no Adw.StatusPage is built anywhere in the welcome"
fi

# The real question, asked the same way step 7d asks it: can a Python program on
# THIS image reach GTK 4 and libadwaita? This catches a missing typelib, which
# is how this particular thing breaks — the packages are installed, the import
# fails, and the first person to find out is somebody logging in for the first
# time.
if python3 - <<'PY'; then
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: F401

print("Gtk %d.%d.%d, Adw %d.%d.%d"
      % (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version(),
         Adw.get_major_version(), Adw.get_minor_version(), Adw.get_micro_version()))
PY
    ok "Python can load GTK 4 and libadwaita, which is what this window is drawn with"
else
    bad "Python cannot load GTK 4 or libadwaita — the welcome would not open"
fi

# ==============================================================================
# 2. The rehearsal — the three steps, with no screen in the room
# ==============================================================================
# `--dry-run` prints the flow. The shape of its lines is a contract between this
# file and the window; the window's own `rehearse()` says so at the top of it.
say "The three steps, rehearsed"
WEL_OUT="$(mktemp)"
if "${WELCOME}" --dry-run > "${WEL_OUT}" 2>&1; then
    ok "the welcome rehearsed its flow"
else
    bad "the welcome could not rehearse its flow"
fi
sed 's/^/       /' "${WEL_OUT}"

aq_file_has "${WEL_OUT}" '^steps: 3$' \
    "a brand-new account gets three steps"
aq_file_has "${WEL_OUT}" '^step 1 of 3: keyboard — How should keyboard shortcuts work\?$' \
    "step 1 asks how the keyboard should work"
aq_file_has "${WEL_OUT}" '^step 2 of 3: apps — Your creator apps$' \
    "step 2 is the creator apps"
aq_file_has "${WEL_OUT}" "^  runs: ${CHOOSER} --embedded-flow\$" \
    "and it is the real chooser that runs, not a copy of it"
aq_file_has "${WEL_OUT}" "^step 3 of 3: done — You're set\\.\$" \
    "step 3 says you are set"
aq_file_has "${WEL_OUT}" '^tips: 3$' \
    "with three tips on it"

# ------------------------------------------------------------------------------
# ⚠️ THE CHECK THIS WHOLE FILE IS FOR.
# ------------------------------------------------------------------------------
# Mac-style shortcuts are the AquariusOS default. Four things in this operating
# system have to agree about that — /etc/skel/.config/aquarius/keys.conf,
# /usr/libexec/aquarius-keys-run, `aq keys status`, and now this window — and
# this is the one of them that a person SEES. A card that came up preselected
# the other way would look completely normal in a screenshot and would quietly
# turn off the feature FEATURES 008 exists to ship.
say "Mac is the preselected answer, as it is everywhere else in this OS"
aq_file_has "${WEL_OUT}" '^default choice: mac$' \
    "Mac is the default the window opens on"
aq_file_has "${WEL_OUT}" '^  choice mac: Mac — Copy is ⌘C  \(preselected\)$' \
    "the Mac card is the one that is preselected, and it says Copy is ⌘C"
aq_file_has "${WEL_OUT}" '^  choice windows: Windows — Copy is Ctrl\+C$' \
    "the Windows card is offered beside it, and says Copy is Ctrl+C"

# And the answer goes through `aq keys`, not through a second writer of
# keys.conf. Two programs that both write a settings file is two programs that
# can disagree about its format.
say "The keyboard answer is written by 'aq keys' and by nothing else"
aq_file_has "${WEL_OUT}" "^keyboard written by: ${AQ} keys mac\|windows\$" \
    "the window says out loud that it delegates the writing"
aq_file_has "${WELCOME}" '\[AQ, "keys", mode\]' \
    "and it really does run the command rather than writing the file itself"
if grep -qE 'mode=(mac|windows|%s)' "${WELCOME}"; then
    bad "the welcome writes the keys.conf format itself — that belongs to 'aq keys' alone"
else
    ok "the welcome contains no copy of the keys.conf file format"
fi

# ------------------------------------------------------------------------------
# The existing-account rule. Royce's account on the bench has been through the
# chooser and has never seen a welcome, because there was not one. It must get
# the keyboard question and the last page, and must NOT be asked to choose its
# apps all over again.
# ------------------------------------------------------------------------------
say "An account that already chose its apps is not asked again"
MIG_OUT="$(mktemp)"
if "${WELCOME}" --dry-run --pretend-apps-seen > "${MIG_OUT}" 2>&1; then
    ok "the welcome rehearsed the existing-account flow"
else
    bad "the welcome could not rehearse the existing-account flow"
fi
sed 's/^/       /' "${MIG_OUT}"
aq_file_has "${MIG_OUT}" '^steps: 2$' \
    "an account with apps already set up gets two steps, not three"
aq_file_has "${MIG_OUT}" '^apps step: skipped$' \
    "the apps step is the one left out"
aq_file_has "${MIG_OUT}" '^step 2 of 2: done — .*$' \
    "and the last page is step 2 of 2, so the counting is honest"
aq_file_has "${WELCOME}" 'Your apps are already set up' \
    "the window says so on screen rather than silently missing a step"
rm -f "${MIG_OUT}" "${WEL_OUT}"

# ==============================================================================
# 3. The two stamps
# ==============================================================================
# welcome-seen is this window's own; creator-apps-seen belongs to the chooser
# and existed before this window did. Reading the second is the whole basis of
# the existing-account rule above, so it is checked by name.
say "Where it remembers that you have been welcomed"
aq_file_has "${WELCOME}" '"welcome-seen"' \
    "it writes ~/.config/aquarius/welcome-seen"
aq_file_has "${WELCOME}" '"creator-apps-seen"' \
    "and it reads the chooser's own stamp to decide about the apps step"

# ==============================================================================
# 4. `aq welcome`
# ==============================================================================
say "The aq command can open it again"
if [ -x "${AQ}" ]; then
    ok "aq is here"
else
    bad "${AQ} is missing"
fi
aq_file_has "${AQ}" '^    welcome\)$' \
    "'aq welcome' is a command aq understands"
aq_file_has "${AQ}" '^AQ_WELCOME="/usr/libexec/aquarius-welcome"$' \
    "and it knows where the window is"
aq_file_has "${AQ}" '^    aq welcome          Show the AquariusOS welcome again' \
    "it is in 'aq --help', because a command nobody can discover is a command nobody uses"
if "${AQ}" welcome --help > /tmp/aq-welcome-help.txt 2>&1; then
    ok "'aq welcome --help' works"
else
    bad "'aq welcome --help' does not work"
fi
sed 's/^/       /' /tmp/aq-welcome-help.txt
aq_file_has /tmp/aq-welcome-help.txt 'aquarius-welcome — the AquariusOS welcome' \
    "and it is the window's own help that comes back, not a second copy of it"
rm -f /tmp/aq-welcome-help.txt

# ==============================================================================
# 5. The menu entries
# ==============================================================================
say "The two menu entries"
if ! aq_have desktop-file-validate; then
    echo "desktop-file-validate is not here yet; installing desktop-file-utils."
    aq_dnf install desktop-file-utils
fi
for entry in "${APP_ENTRY}" "${AUTOSTART}"; do
    if [ ! -r "${entry}" ]; then
        bad "${entry} is missing"
        continue
    fi
    if desktop-file-validate "${entry}"; then
        ok "$(basename "${entry}") is a well-formed menu entry"
    else
        bad "$(basename "${entry}") is not a well-formed menu entry"
    fi
done

# The app entry is hidden from the grid on purpose: a "Welcome" tile sitting in
# somebody's apps forever is clutter, and `aq welcome` is the way back to it.
aq_file_has "${APP_ENTRY}" '^Name=Aquarius Welcome$' \
    "the app entry is called Aquarius Welcome"
aq_file_has "${APP_ENTRY}" "^Exec=${WELCOME}\$" \
    "and it opens the welcome"
aq_file_has "${APP_ENTRY}" '^NoDisplay=true$' \
    "it is hidden from the app grid — 'aq welcome' is the way back to it"

# ⚠️ OnlyShowIn WOULD BREAK THE ONE THING THE AUTOSTART ENTRY IS FOR. GNOME
# reads /etc/xdg/autostart; a session named in OnlyShowIn would be the only one
# that ran it. There is no session name that covers both GNOME and ours, so the
# key must simply not be there.
say "The first-login entry runs in every session that reads autostart"
if grep -Eq '^(OnlyShowIn|NotShowIn)=' "${AUTOSTART}" 2> /dev/null; then
    bad "the first-login entry has OnlyShowIn/NotShowIn, which would stop it running in some sessions"
else
    ok "the first-login entry has no OnlyShowIn or NotShowIn"
fi
aq_file_has "${AUTOSTART}" '^Exec=.*aquarius-welcome --first-run$' \
    "the first-login entry asks for the once-only behaviour (--first-run)"
aq_file_has "${AUTOSTART}" '^X-GNOME-Autostart-Delay=10$' \
    "and waits ten seconds so the desktop has settled"

# ==============================================================================
# 6. The Aquarius session has to be told separately
# ==============================================================================
# ⚠️ labwc DOES NOT READ /etc/xdg/autostart. It reads exactly one file, the
# `autostart` next to its rc.xml, and that is deliberate — it is what keeps a
# dozen GNOME background programs out of the Aquarius session.
#
# The cost of that decision is this: anything that must run at login in BOTH
# sessions is written down twice, and this check is what stops the two copies
# drifting apart silently. It is the sort of fault that shows up only on the one
# session nobody tested.
say "Both sessions open the welcome, and they run the same command"
aq_file_has "${LABWC_AUTOSTART}" 'aquarius-welcome --first-run' \
    "the Aquarius session's autostart opens the welcome on a first login"

GNOME_CMD="$(sed -n 's/^Exec=//p' "${AUTOSTART}" | head -n 1)"
if grep -qF "${GNOME_CMD}" "${LABWC_AUTOSTART}"; then
    ok "both sessions run exactly the same command: ${GNOME_CMD}"
else
    bad "GNOME runs '${GNOME_CMD}' and the Aquarius session runs something else"
fi

# ==============================================================================
# 7. Nothing opens the chooser at login any more
# ==============================================================================
# Said twice on purpose — step 7d checks it too. Two windows opening ten seconds
# after somebody's very first login is the worst possible moment for a fault,
# and it is one a screenshot of a working machine would never reveal.
say "The old first-login entries are gone"
if [ -e "${OLD_AUTOSTART}" ]; then
    bad "${OLD_AUTOSTART} is still here — the chooser would open twice at a first login"
else
    ok "the chooser's own first-login entry is gone"
fi
if grep -q 'aquarius-creator-apps --first-run' "${LABWC_AUTOSTART}" 2> /dev/null; then
    bad "the Aquarius session's autostart still opens the chooser directly at login"
else
    ok "the Aquarius session's autostart does not open the chooser directly either"
fi

# But the chooser is still an ordinary app, and must stay one: this whole change
# would be a regression if "Aquarius Apps" stopped working.
say "The chooser is still an app you can open whenever you like"
if [ -x "${CHOOSER}" ] && [ -r /usr/share/applications/aquarius-creator-apps.desktop ]; then
    ok "Aquarius Apps is still in the app grid and still runnable"
else
    bad "the chooser or its app-grid entry has gone missing"
fi

# ==============================================================================
# 8. Write down how this image turned out
# ==============================================================================
say "Recording what this layer added"
install -d -m 0755 /usr/share/aquarius
{
    echo "# How the AquariusOS welcome turned out on this image."
    echo "# Written by build_files/67-welcome.sh. Read by CI and by docs."
    echo "status=present"
    echo "steps=3"
    echo "keyboard_default=mac"
    echo "apps_step=/usr/libexec/aquarius-creator-apps --embedded-flow"
    echo "stamp=~/.config/aquarius/welcome-seen"
} > /usr/share/aquarius/welcome.env
chmod 0644 /usr/share/aquarius/welcome.env
sed 's/^/       /' /usr/share/aquarius/welcome.env

aq_finish "Welcome"
