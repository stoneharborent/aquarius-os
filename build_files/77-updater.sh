#!/usr/bin/bash
# ==============================================================================
# STEP 77 — "Check for Update": the window the Aquarius logo menu opens
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# AquariusOS updates itself as one sealed image (bootc underneath). The command
# that does it is a wall of text; this is the small window that puts a friendly
# face on it — current version, "is there a newer one?", one Update button, and
# an offer to restart. It is what the Aquarius logo menu's "Check for Update"
# launches, and it is also `aq update` on the command line.
#
# It is three plain files, all copied in at step 50:
#
#   /usr/libexec/aquarius-updater                 the window AND the headless
#                                                 check/apply, in one program
#   /usr/share/applications/aquarius-updater.desktop  its launcher entry
#   the `aq update` subcommand, inside /usr/bin/aq
#
# This step CHECKS them, because a "Check for Update" that does nothing when
# clicked is the kind of fault nobody notices until an update is waiting.
#
# THE WINDOW AND ITS FIXED SYSTEM HELPER
# Both checking and updating need administrator permission. The window and
# `aq update` call /usr/libexec/aquarius-update-system through pkexec. That helper
# accepts only check/apply and reads bootc status; the GUI stays the normal user.
#
# Plain-English guide: docs/restart/updater.md
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

UPDATER="/usr/libexec/aquarius-updater"
DESKTOP="/usr/share/applications/aquarius-updater.desktop"
AQ_CLI="/usr/bin/aq"
IMAGE_INFO="/usr/share/aquarius/image-info.json"

# ------------------------------------------------------------------------------
# 1. bootc — the thing that actually updates the OS — is here
# ------------------------------------------------------------------------------
# The window is a face on bootc. Without bootc there is nothing to put a face on.
# It comes from the Fedora bootc base image, so this is a confirmation, not an
# install.
say "The update engine underneath the window"
if [ -x /usr/bin/bootc ]; then
    ok "/usr/bin/bootc is present ($(/usr/bin/bootc --version 2>/dev/null || echo 'version unavailable in build'))"
else
    bad "/usr/bin/bootc is missing — nothing could actually update the system"
fi

# The window reads the current version out of this file (written by step 70).
aq_file_has "${IMAGE_INFO}" '"version-pretty"' \
    "the image records a version for the window to show (image-info.json)"

# ------------------------------------------------------------------------------
# 2. The program — present, valid Python, runnable
# ------------------------------------------------------------------------------
say "The updater program"
if [ -x "${UPDATER}" ]; then
    ok "${UPDATER} is present and runnable"
else
    bad "${UPDATER} is missing or not runnable — 'Check for Update' would do nothing"
fi

if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-updater.pyc", doraise=True)' "${UPDATER}" 2> /tmp/aq-updater-py.txt; then
    ok "the updater is valid Python"
else
    bad "the updater has a syntax error:"
    sed 's/^/       /' /tmp/aq-updater-py.txt
fi
rm -f /tmp/aq-updater.pyc /tmp/aq-updater-py.txt

# ------------------------------------------------------------------------------
# 3. The window can actually be drawn — GTK 4 and libadwaita
# ------------------------------------------------------------------------------
# The same import check the Resolve window has: it catches a missing
# python3-gobject, gtk4 or libadwaita, any of which turns the logo-menu entry
# into a button that does nothing. Importing needs no screen.
say "The window's toolkit"
if python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1"); from gi.repository import Gtk, Adw' 2> /tmp/aq-gi.txt; then
    ok "Python can reach GTK 4 and libadwaita"
else
    bad "Python cannot import GTK 4 and libadwaita — the updater window could not be drawn"
    sed 's/^/       /' /tmp/aq-gi.txt
fi
rm -f /tmp/aq-gi.txt
aq_installed python3-gobject gtk4 libadwaita

# The shared window pieces the updater is built from. If aquarius_ui cannot be
# imported, this window (and every other one) fails to open.
if python3 -c 'import sys; sys.path.insert(0, "/usr/lib/aquarius/python"); import aquarius_ui' 2> /tmp/aq-ui.txt; then
    ok "the shared window pieces (aquarius_ui) import cleanly"
else
    bad "aquarius_ui cannot be imported — the updater window would fail to open"
    sed 's/^/       /' /tmp/aq-ui.txt
fi
rm -f /tmp/aq-ui.txt

# ------------------------------------------------------------------------------
# 4. Every page has the Aquarius mark — the 2026-09-04 rule
# ------------------------------------------------------------------------------
# Three earlier windows each shipped a last page built on an Adw.StatusPage,
# which cannot carry the Aquarius mark, so the page you landed on was blank at
# the top. aquarius_ui.hero() is the one blessed way to draw the top of a page.
# This window must follow the same rule.
say "The mark is on every page"
if grep -q 'Adw\.StatusPage(' "${UPDATER}"; then
    bad "the updater builds an Adw.StatusPage — that page cannot show the Aquarius mark"
else
    ok "the updater builds no Adw.StatusPage anywhere"
fi
if grep -qF 'aquarius_ui.hero(' "${UPDATER}"; then
    ok "the updater draws its pages with aquarius_ui.hero()"
else
    bad "the updater does not use aquarius_ui.hero() — its pages would have no mark"
fi

# ------------------------------------------------------------------------------
# 5. The rehearsal (--dry-run) — no window, no network, prints the version
# ------------------------------------------------------------------------------
# --dry-run is what proves the program loads on a machine with no screen and no
# real system to update — which is exactly this build container. It must print
# the current version and describe the check, and change nothing.
say "The updater's rehearsal (--dry-run)"
if "${UPDATER}" --dry-run > /tmp/aq-updater-dry.txt 2>&1; then
    ok "'aquarius-updater --dry-run' runs and changes nothing"
    sed 's/^/       /' /tmp/aq-updater-dry.txt
else
    bad "'aquarius-updater --dry-run' failed — the updater cannot load in this image:"
    sed 's/^/       /' /tmp/aq-updater-dry.txt
fi
aq_file_has /tmp/aq-updater-dry.txt 'Current version:' \
    "the rehearsal prints the current version"
aq_file_has /tmp/aq-updater-dry.txt 'bootc upgrade --check' \
    "the rehearsal states the check it runs"
aq_file_has /tmp/aq-updater-dry.txt 'pkexec /usr/libexec/aquarius-update-system apply' \
    "the rehearsal states how it elevates to do the update"
rm -f /tmp/aq-updater-dry.txt

# ------------------------------------------------------------------------------
# 6. The launcher entry — valid, and pointed at the program
# ------------------------------------------------------------------------------
say "The launcher entry the logo menu uses"
if [ -r "${DESKTOP}" ]; then
    ok "${DESKTOP} is installed"
else
    bad "${DESKTOP} is missing — the logo menu would have nothing to launch"
fi
aq_file_has "${DESKTOP}" '^Exec=/usr/libexec/aquarius-updater$' \
    "the launcher runs the updater"
aq_file_has "${DESKTOP}" '^NoDisplay=true$' \
    "it is hidden from the app grid — the logo menu launches it, not an app icon"

# desktop-file-validate is a build-time tool; it may not be in the finished
# image, so guard it and say honestly which happened rather than a green tick
# nobody earned.
if aq_have desktop-file-validate; then
    if desktop-file-validate "${DESKTOP}" 2> /tmp/aq-dfv.txt; then
        ok "desktop-file-validate accepts the launcher entry"
    else
        bad "desktop-file-validate rejects the launcher entry:"
        sed 's/^/       /' /tmp/aq-dfv.txt
    fi
    rm -f /tmp/aq-dfv.txt
else
    echo "  note   desktop-file-validate is not in this build stage; the CI verify"
    echo "         step runs it against the finished image."
fi

# ------------------------------------------------------------------------------
# 7. `aq update` is wired in
# ------------------------------------------------------------------------------
say "The 'aq update' command"
if bash -n "${AQ_CLI}" 2> /tmp/aq-syn.txt; then
    ok "aq is still valid shell after adding 'update'"
else
    bad "aq has a syntax error:"
    sed 's/^/       /' /tmp/aq-syn.txt
fi
rm -f /tmp/aq-syn.txt
aq_file_has "${AQ_CLI}" 'AQ_UPDATER="/usr/libexec/aquarius-updater"' \
    "aq knows where the updater is"
aq_file_has "${AQ_CLI}" 'aq update' \
    "'aq --help' mentions update, so people can find it"
# It must actually dispatch, not just be documented.
if "${AQ_CLI}" update --help > /dev/null 2>&1; then
    ok "'aq update --help' works"
else
    bad "'aq update --help' failed — the subcommand is not wired up"
fi


# The privileged front door has fixed arguments and isolated Python imports.
test -x /usr/libexec/aquarius-update-system
python3 -B -c 'import ast; ast.parse(open("/usr/libexec/aquarius-update-system").read())'
/usr/bin/bootc status --help | grep -q -- '--format-version'

aq_finish "Check for Update window"
