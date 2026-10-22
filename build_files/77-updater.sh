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
# ⚠️ SINCE 2026-10-21 GNOME SOFTWARE IS THE ONE PLACE UPDATES COME FROM.
# "Check for Update" now opens Software's Updates page; `aq update apply` uses
# the same engine Software uses (`rpm-ostree upgrade`, through the system's one
# update service), so the two queue instead of fighting over the update lock.
# And Fedora's own auto-update timer — which downloads AND REBOOTS without
# asking — is switched off here (section 0). Nothing restarts the computer by
# itself.
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
# WHY THERE IS NO SEPARATE "aquarius-update" SCRIPT LIKE RESOLVE HAS
# The Resolve installer is a Python window driving a big bash installer, so it
# is two files. Updating is one short command (`rpm-ostree upgrade`), so the window
# and the terminal logic live in the one Python file, and `aq update` just calls
# it. That keeps the "one updater, two faces" rule with less machinery.
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
# 0. Nothing updates AND restarts the computer by itself
# ------------------------------------------------------------------------------
# ⚠️ 2026-10-21 (bench). Fedora's bootc base switches on
# bootc-fetch-apply-updates.timer, which runs `bootc upgrade --apply --quiet`:
# download a new system, then REBOOT, with no question asked. On the bench it
# also sat for 46 hours waiting behind a stuck GNOME Software job, holding the
# update lock the whole time. Updates on AquariusOS come from Software, which
# downloads quietly and then asks you to restart when it suits you.
#
# Two layers, because each one reaches machines the other cannot:
#   * the preset file /usr/lib/systemd/system-preset/10-aquarius-updates.preset
#     says "disable" — that is what a fresh install reads;
#   * a MASK, written here into the image's /etc. A mask is a link to /dev/null
#     that beats every "switched on" link anywhere. A machine installed before
#     today already has Fedora's "switched on" link in its own /etc; the update
#     adds the mask beside it, and the mask wins. (`sudo systemctl unmask` is
#     the off switch for this off switch, if anyone ever wants Fedora's
#     behaviour back.)
say "Fedora's update-and-reboot timer is switched off"
AQ_AUTO_UNITS="bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service"
for aq_unit in ${AQ_AUTO_UNITS}; do
    rm -f "/etc/systemd/system/timers.target.wants/${aq_unit}"
    ln -sfn /dev/null "/etc/systemd/system/${aq_unit}"
done
for aq_unit in ${AQ_AUTO_UNITS}; do
    if [ "$(readlink "/etc/systemd/system/${aq_unit}")" = "/dev/null" ]; then
        ok "${aq_unit} is masked — it can never run, so it can never reboot the machine"
    else
        bad "${aq_unit} is not masked — Fedora's timer could update and reboot without asking"
    fi
    for aq_wants in /etc/systemd/system/timers.target.wants /usr/lib/systemd/system/timers.target.wants; do
        if [ -e "${aq_wants}/${aq_unit}" ] || [ -L "${aq_wants}/${aq_unit}" ]; then
            bad "${aq_wants}/${aq_unit} still switches it on"
        fi
    done
    if aq_have systemctl; then
        echo "  (for information) systemctl is-enabled ${aq_unit}: $(systemctl is-enabled "${aq_unit}" 2> /dev/null || echo "no answer")"
    fi
done
aq_file_has /usr/lib/systemd/system-preset/10-aquarius-updates.preset \
    '^disable bootc-fetch-apply-updates.timer$' \
    "the preset a fresh install reads says the timer is off"

# ------------------------------------------------------------------------------
# 0b. GNOME Software downloads quietly, then says "Restart to update"
# ------------------------------------------------------------------------------
# The settings live in zz1-aquarius-50-software.gschema.override (compiled at
# step 50). Asked back the way a brand-new account would ask: GSETTINGS_BACKEND
# =memory reads the compiled defaults with no desktop running.
say "GNOME Software's update settings"
if [ -x /usr/bin/gnome-software ]; then
    ok "/usr/bin/gnome-software is present — 'Check for Update' has a page to open"
else
    bad "/usr/bin/gnome-software is missing — 'Check for Update' would fall back to the old window"
fi
for aq_pair in allow-updates=true download-updates=true download-updates-notify=true refresh-when-metered=false; do
    aq_key="${aq_pair%%=*}"
    aq_want="${aq_pair#*=}"
    aq_got="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.software "${aq_key}" 2> /dev/null || echo "unreadable")"
    if [ "${aq_got}" = "${aq_want}" ]; then
        ok "org.gnome.software ${aq_key} is ${aq_got}"
    else
        bad "org.gnome.software ${aq_key} is '${aq_got}', not ${aq_want} — check zz1-aquarius-50-software.gschema.override"
    fi
done

# ------------------------------------------------------------------------------
# 1. bootc — the base the system is built on — is here
# ------------------------------------------------------------------------------
# bootc is no longer what `aq update apply` runs (rpm-ostree is, section 1b),
# but it is still the base the whole system stands on.
say "The system's own update tooling"
if [ -x /usr/bin/bootc ]; then
    ok "/usr/bin/bootc is present ($(/usr/bin/bootc --version 2>/dev/null || echo 'version unavailable in build'))"
else
    bad "/usr/bin/bootc is missing — nothing could actually update the system"
fi

# ------------------------------------------------------------------------------
# 1b. The two tools the CHECK uses — and neither of them needs a password
# ------------------------------------------------------------------------------
# ⚠️ 2026-09-13 (bench finding U1). The check used to run `bootc upgrade
# --check`, which refuses to run unless you are the administrator; the refusal
# came out of the window as "check your internet", on a machine that was online.
# Checking must never need a password, so it now asks two questions any ordinary
# account is allowed to ask:
#   rpm-ostree  — what did this machine boot? (it answers over the system's own
#                 message bus, so no password and no administrator)
#   skopeo      — what is the newest published image? (a read of a public image
#                 store; it is a small tool, added here for exactly this)
say "The two tools the check reads its answers from"
aq_dnf install skopeo
aq_installed skopeo
if [ -x /usr/bin/rpm-ostree ]; then
    ok "/usr/bin/rpm-ostree is present — the check can read what this machine booted, and 'apply' can update it"
else
    bad "/usr/bin/rpm-ostree is missing — the check could not read the current image, and nothing could update"
fi
if [ -x /usr/bin/skopeo ]; then
    ok "/usr/bin/skopeo is present — the check can read the published version"
else
    bad "/usr/bin/skopeo is missing — the check could never see a new version"
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
aq_file_has /tmp/aq-updater-dry.txt 'without asking for a password' \
    "the rehearsal states that checking needs no password"
aq_file_has /tmp/aq-updater-dry.txt 'pkexec rpm-ostree upgrade' \
    "the rehearsal states how it elevates — through the same engine as Software"
aq_file_has /tmp/aq-updater-dry.txt 'gnome-software --mode=updates' \
    "the rehearsal states that 'Check for Update' opens Software's Updates page"
if grep -q 'bootc upgrade' /tmp/aq-updater-dry.txt; then
    bad "the rehearsal still mentions 'bootc upgrade' — a second engine that fights Software"
else
    ok "the rehearsal never runs 'bootc upgrade'"
fi
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

# ------------------------------------------------------------------------------
# 8. The check's own test — the decision, against canned answers
# ------------------------------------------------------------------------------
# The same pattern step 65 uses for the installer's sorter: run the test against
# the copy of the program that is IN THIS IMAGE, not the one on the build
# runner. It feeds the decision canned copies of the two answers it reads and
# proves it never calls an unreadable check "up to date", and never calls a
# permission problem "no internet" — which is the fault this whole step exists
# to keep from coming back.
say "The check's own test, against the copy in this image"
if [ -r /ctx/tests/test-updater.py ]; then
    if python3 /ctx/tests/test-updater.py "${UPDATER}"; then
        ok "the update-check test passed against the installed updater"
    else
        bad "the update-check test FAILED against the installed updater"
    fi
else
    bad "/ctx/tests/test-updater.py is missing from the build context"
fi

aq_finish "Check for Update window"
