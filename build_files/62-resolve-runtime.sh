#!/usr/bin/bash
# ==============================================================================
# 62 — DaVinci Resolve: everything except Resolve
# ==============================================================================
# PLAIN ENGLISH
#
# DaVinci Resolve is the professional video editor AquariusOS is built around,
# and it is the flagship reason this operating system exists rather than being
# "Fedora with a nice theme". This step puts in place everything needed to run
# it — and deliberately does NOT put in Resolve itself.
#
# WHY RESOLVE IS NOT IN THE IMAGE
# Blackmagic's licence does not allow anybody else to distribute their
# installer. Not us, not Fedora, not anyone. So the user downloads it from
# Blackmagic and AquariusOS installs it into a container on their own machine.
# Nothing licensed is ever published by us, and that is not negotiable.
#
# WHY RESOLVE RUNS IN A CONTAINER AND NOT ON THE DESKTOP
# Resolve carries its own copy of a library called GLib from 2021. On a modern
# Linux, the system's text-drawing library is built against a much newer GLib,
# asks Resolve's old copy for something that does not exist in it, and Resolve
# dies before its window appears. It is the most common "Resolve does not work
# on Linux" story and it recurs every time a distribution moves GLib forward.
#
# Enterprise Linux 9 — Rocky — is still on the same GLib series Resolve bundles.
# In there the clash is not worked around; it cannot happen. That container is
# built by resolve-runtime/Containerfile in this repository and downloaded onto
# a machine the first time somebody sets Resolve up.
#
# WHAT THIS STEP ACTUALLY DOES
#   1. Checks the container machinery (podman, distrobox) is here — step 30 put
#      it there; this is the step that would notice if it ever stopped.
#   2. On the NVIDIA image, checks the graphics-card-into-container plumbing.
#   3. Switches on the safety-net service that describes the graphics card to
#      containers, for the driver builds that do not ship NVIDIA's own.
#   4. Checks every file this feature is made of arrived, and that each script
#      is valid shell.
#
# The files themselves came in at step 50 with the rest of system_files/. This
# step owns none of them; it owns the QUESTION "did they all get here, and are
# they right?".
#
# The beginner-facing guide is docs/restart/resolve.md.
# ==============================================================================

set -euo pipefail
# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

NVIDIA="${NVIDIA:-0}"

say "DaVinci Resolve — the container machinery"

# ------------------------------------------------------------------------------
# 1. The container machinery
# ------------------------------------------------------------------------------
# distrobox is what runs the Rocky Linux; podman is the engine underneath it.
# Both were installed by step 30 — this is a read-back, not an install, so that
# a change to step 30 that dropped one of them fails HERE, in a step whose name
# says why they matter.
aq_installed podman distrobox

for cmd in podman distrobox distrobox-create distrobox-enter; do
    if aq_have "${cmd}"; then
        ok "${cmd} is on the path"
    else
        bad "${cmd} is missing — the Resolve container could not be built on a real machine"
    fi
done

# ------------------------------------------------------------------------------
# 2. Getting the graphics card into the container (NVIDIA image only)
# ------------------------------------------------------------------------------
# THE DECISION, WRITTEN DOWN HERE BECAUSE THIS IS WHERE SOMEBODY WILL LOOK:
#
# There are two ways to let a container use the graphics card, and AquariusOS
# prefers the first:
#
#   (a) CDI, the Container Device Interface. NVIDIA's own supported mechanism. A
#       file on the machine describes the card and its driver libraries and
#       podman reads it. `nvidia-container-toolkit` provides the tool that
#       writes it, and — in current driver builds — a service called
#       `nvidia-cdi-refresh` that writes it at every boot and after every driver
#       change. Step 60 installs the toolkit and switches that service on.
#
#   (b) `distrobox create --nvidia`, which copies the host's driver files into
#       the container itself. No toolkit needed. It is distrobox's own best
#       guess rather than NVIDIA's description of the hardware, and distrobox's
#       documentation is explicit that it needs a recent glibc distribution in
#       the container to work.
#
# WHY (a) IS THE RIGHT ANSWER ON THIS OPERATING SYSTEM SPECIFICALLY:
# AquariusOS updates by replacing the whole system, driver included. The
# description names driver library files by their exact version, so anything
# generated when the IMAGE was built would name a driver that no longer existed
# after the first update — the machine would work, then silently stop seeing the
# graphics card. Generated at boot by the driver that is actually installed, it
# cannot go stale. (And there is no graphics card in the machine that builds the
# image, so there would be nothing true to generate anyway.)
#
# The installer on the machine picks (a) when the file exists and falls back to
# (b) when it does not, so a driver build without the refresh service still
# works. Neither is a guess made at build time.
if [ "${NVIDIA}" = "1" ]; then
    say "DaVinci Resolve — the NVIDIA graphics-card passthrough"

    aq_installed nvidia-container-toolkit

    if aq_have nvidia-ctk; then
        ok "nvidia-ctk is on the path (the tool that describes the card to containers)"
    else
        bad "nvidia-ctk is missing — nothing could describe the graphics card to a container"
    fi

    # Whether NVIDIA's own refresh service is in this driver build. Both answers
    # are fine; what matters is that exactly one thing writes the file, which is
    # what the safety-net unit's Condition lines guarantee.
    if [ -f /usr/lib/systemd/system/nvidia-cdi-refresh.service ]; then
        ok "NVIDIA's own nvidia-cdi-refresh service is in this driver build (step 60 enables it)"
        echo "       The AquariusOS safety-net unit will therefore stay dormant, by design."
    else
        echo "  NOTE this driver build has no nvidia-cdi-refresh service."
        echo "       The AquariusOS safety-net unit below is what will write the file."
    fi

    say "The safety-net service"
    AQ_CDI_UNIT=/usr/lib/systemd/system/aquarius-resolve-cdi.service
    if [ ! -f "${AQ_CDI_UNIT}" ]; then
        bad "${AQ_CDI_UNIT} is missing — it should have arrived with system_files at step 50"
    else
        # The two Conditions are the whole safety of this unit: without the
        # second one it would fight NVIDIA's own service for the same file.
        aq_file_has "${AQ_CDI_UNIT}" \
            '^ConditionPathExists=!/usr/lib/systemd/system/nvidia-cdi-refresh\.service$' \
            "it stands down when NVIDIA's own service is present"
        aq_file_has "${AQ_CDI_UNIT}" \
            '^ConditionPathExists=/proc/driver/nvidia/version$' \
            "it only runs on a machine with the NVIDIA driver loaded"
        aq_file_has "${AQ_CDI_UNIT}" \
            'nvidia-ctk cdi generate' \
            "it runs NVIDIA's own tool"

        if systemctl enable aquarius-resolve-cdi.service; then
            ok "the safety-net service is switched on"
        else
            bad "could not switch on aquarius-resolve-cdi.service"
        fi
    fi
else
    say "DaVinci Resolve — graphics card"
    echo "  NOTE this is the AMD/Intel image, so there is no NVIDIA passthrough to set up."
    echo "       Resolve on AMD needs ROCm's OpenCL, which is not in the runtime"
    echo "       container yet — the installer says so plainly rather than letting"
    echo "       somebody find out from Resolve. See docs/restart/resolve.md."

    # The safety-net unit ships in both images because system_files is one tree,
    # but it must never run on a machine with no NVIDIA driver. Its own
    # Condition covers that; leaving it switched off here is the second lock.
    if systemctl is-enabled aquarius-resolve-cdi.service > /dev/null 2>&1; then
        bad "the NVIDIA safety-net service is switched on in the AMD/Intel image"
    else
        ok "the NVIDIA safety-net service is correctly left switched off"
    fi
fi

# ------------------------------------------------------------------------------
# 2b. What the installer WINDOW is built out of
# ------------------------------------------------------------------------------
# "Install DaVinci Resolve" in the app grid opens a real application window
# (/usr/libexec/aquarius-resolve-installer), not a terminal. It is written in
# Python against GTK 4 and libadwaita, which means three things have to be in
# the image, and a missing one shows up as an icon that does nothing when
# clicked — the worst possible failure for the feature this OS is built around.
#
#   gtk4         the toolkit, and the Gtk-4.0 typelib that lets Python call it
#   libadwaita   GNOME's own widgets, and the Adw-1 typelib. Also where the
#                automatic light/dark behaviour comes from, which is why the
#                window needs no colours of its own.
#   python3-gobject
#                the bridge between Python and the two above.
#
# ⚠️ ALL THREE ARE ALREADY IN THIS IMAGE — AND THAT IS EXACTLY WHY THEY ARE
# NAMED HERE. Nothing asked for any of them on purpose. gtk4 and libadwaita
# come in with GNOME at step 40, and python3-gobject arrives as a dependency of
# GDM's own transaction at step 30. So the size this line adds today is zero,
# and what it buys instead is a DECLARATION: the flagship feature of this
# operating system currently rests on three packages that are here by accident,
# and an accident can be undone by a change to a completely different step. Ask
# for them by name and that change fails here, in the step whose name says why
# they matter, instead of on somebody's desk.
say "DaVinci Resolve — what the installer window is built out of"
aq_dnf install python3-gobject gtk4 libadwaita
aq_installed python3-gobject gtk4 libadwaita

# The import is the real test. A package can install perfectly and still leave
# Python unable to reach it, because what Python actually loads is the typelib
# file, which lives in a different package to the library on some systems. No
# screen is needed to find out — importing does not open a window.
if python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1"); from gi.repository import Gtk, Adw'; then
    ok "Python can reach GTK 4 and libadwaita — the installer window can be drawn"
else
    bad "Python cannot import GTK 4 and libadwaita — 'Install DaVinci Resolve' would open nothing at all"
fi

# ------------------------------------------------------------------------------
# 3. Every file the feature is made of
# ------------------------------------------------------------------------------
say "DaVinci Resolve — the files"

for f in /usr/libexec/aquarius-resolve-install \
    /usr/libexec/aquarius-resolve-launch \
    /usr/libexec/aquarius-resolve-update-notify; do
    if [ ! -f "${f}" ]; then
        bad "${f} is missing"
        continue
    fi
    # An executable bit that did not survive the copy is a silent failure: the
    # icon is there, the click does nothing.
    chmod 0755 "${f}"
    if [ -x "${f}" ]; then
        ok "$(basename "${f}") is present and runnable"
    else
        bad "${f} is not runnable"
    fi
    # Valid shell. `bash -n` reads the file and checks it parses without running
    # a single line of it — the cheapest possible way to catch a typo that would
    # otherwise be discovered by a person clicking an icon.
    if bash -n "${f}"; then
        ok "$(basename "${f}") is valid shell"
    else
        bad "${f} has a syntax error"
    fi
done

# ------------------------------------------------------------------------------
# The shared window pieces
# ------------------------------------------------------------------------------
# Three windows — the creator-apps chooser, the Resolve installer and the
# Resolve uninstaller — are built out of the same step rows, the same Details
# log and the same Aquarius mark. Those used to be three copies of two hundred
# lines. Since 2026-09-04 they are one file, and all three IMPORT it, which
# means a fault in it breaks all three at once. So it is checked first, and it
# is checked by importing it exactly the way they do.
say "DaVinci Resolve — the shared window pieces"
AQ_UI=/usr/lib/aquarius/python/aquarius_ui.py
if [ ! -r "${AQ_UI}" ]; then
    bad "${AQ_UI} is missing — all three AquariusOS windows would fail to start"
else
    ok "aquarius_ui.py is here"
    if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-ui-check.pyc", doraise=True)' "${AQ_UI}"; then
        ok "aquarius_ui.py is valid Python"
    else
        bad "${AQ_UI} has a syntax error"
    fi
    # The real question: can it be IMPORTED, from the path the windows add?
    # Importing pulls GTK in, which needs no screen, and it is the check that
    # catches a missing typelib or a bad name at the top of the file.
    if python3 -c 'import sys; sys.path.insert(0, "/usr/lib/aquarius/python"); import aquarius_ui; print("  StepRow, LogPane, %d shared pieces" % len([n for n in dir(aquarius_ui) if not n.startswith("_")]))'; then
        ok "aquarius_ui imports cleanly on this image"
    else
        bad "aquarius_ui cannot be imported — every AquariusOS window would fail to open"
    fi
fi
rm -f /tmp/aq-ui-check.pyc

# The two windows. Same idea as the scripts above, different language:
# py_compile parses them and writes byte-code without running a line.
for AQ_GUI in /usr/libexec/aquarius-resolve-installer \
    /usr/libexec/aquarius-resolve-uninstaller \
    /usr/libexec/aquarius-resolve-updater; do
    if [ ! -f "${AQ_GUI}" ]; then
        bad "${AQ_GUI} is missing — the app-grid entry would do nothing"
        continue
    fi
    chmod 0755 "${AQ_GUI}"
    if [ -x "${AQ_GUI}" ]; then
        ok "$(basename "${AQ_GUI}") is present and runnable"
    else
        bad "${AQ_GUI} is not runnable"
    fi
    # Compiled to a throwaway path on purpose: `python3 -m py_compile` would
    # leave a __pycache__ folder beside the script, and that folder would then
    # be baked into /usr/libexec in the finished operating system.
    if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-gui-check.pyc", doraise=True)' "${AQ_GUI}"; then
        ok "$(basename "${AQ_GUI}") is valid Python"
    else
        bad "${AQ_GUI} has a syntax error"
    fi
    # ⚠️ AND IT MUST SAY WHERE THE SHARED PIECES ARE. Without this line the
    # window imports nothing, fails on its first widget, and the icon does
    # nothing when clicked.
    aq_file_has "${AQ_GUI}" 'sys\.path\.insert\(0, "/usr/lib/aquarius/python"\)' \
        "$(basename "${AQ_GUI}") knows where the shared window pieces live"
done
rm -f /tmp/aq-gui-check.pyc

# ------------------------------------------------------------------------------
# Every page of both windows carries the Aquarius mark
# ------------------------------------------------------------------------------
# ⚠️ THE 2026-09-04 BENCH FAULT, AND IT HAPPENED THREE TIMES. All three
# AquariusOS windows finished on an Adw.StatusPage — a widget that draws a small
# system symbol, its own heading and its own description, and that CANNOT be
# given the Aquarius mark. So the page a person landed on after a fifteen-minute
# install was blank at the top while every page before it carried the logo. It
# read as a page that had failed to load. The creator-apps window was fixed
# first; these two had the identical page for the identical reason.
#
# The fix is one helper — aquarius_ui.hero() — used by every page of all three
# windows. These are text checks, and that is a deliberate limit: drawing a GTK
# window needs a screen and a build container has none, so the only question a
# build can ask is "is it still written the way we fixed it". It is worth
# asking, because Adw.StatusPage is the obvious widget to reach for here and
# somebody will reach for it again.
say "DaVinci Resolve — every page of all three windows carries the Aquarius mark"
aq_file_has "${AQ_UI}" 'def hero\(' \
    "the shared window pieces own the hero helper (the mark, the heading, the line under it)"
aq_file_has "${AQ_UI}" 'def status_glyph\(' \
    "and the small tick/warning glyph that goes beside a heading"
for AQ_GUI in /usr/libexec/aquarius-resolve-installer \
    /usr/libexec/aquarius-resolve-uninstaller \
    /usr/libexec/aquarius-resolve-updater; do
    [ -r "${AQ_GUI}" ] || continue
    AQ_NAME="$(basename "${AQ_GUI}")"
    # Looking for the CALL — "Adw.StatusPage(" with its bracket — and not for
    # the bare name, because the comments in these files explain at length why
    # the page is not one any more.
    if grep -q 'Adw\.StatusPage(' "${AQ_GUI}"; then
        bad "${AQ_NAME} builds an Adw.StatusPage again — that page cannot show the Aquarius mark"
    else
        ok "${AQ_NAME} builds no Adw.StatusPage anywhere"
    fi
    aq_file_has "${AQ_GUI}" 'mark, self\.done_title, self\.done_blurb = aquarius_ui\.hero\(' \
        "${AQ_NAME}'s last page is built from the shared hero, so the mark is on it"
    aq_file_has "${AQ_GUI}" 'mark, title, blurb = aquarius_ui\.hero\(' \
        "so is its first page, which is what makes them match"
    # The page a failed or cancelled run is left on is the working page — the
    # Details log is there and taking it away at that moment would be wrong. So
    # it is a page a person can be left looking at, and it gets the mark too.
    aq_file_has "${AQ_GUI}" 'mark, self\.working_title, self\.working_blurb = aquarius_ui\.hero\(' \
        "and so does the page a failed or cancelled run is left on"
    # The glyph says how it went. On the last page it starts as a tick; on the
    # working page it is hidden until there is an outcome to report.
    aq_file_has "${AQ_GUI}" 'aquarius_ui\.set_status_glyph\(self\.done_status, ok=True\)' \
        "${AQ_NAME} puts a tick beside the heading when it worked"
    aq_file_has "${AQ_GUI}" 'aquarius_ui\.set_status_glyph\(self\.working_status, ok=False\)' \
        "and a warning beside it when it did not"
    aq_file_has "${AQ_GUI}" 'aquarius_ui\.heading_row\(' \
        "the glyph sits on the heading line, not as a second picture under the mark"
done

# ------------------------------------------------------------------------------
# Nothing a person reads may name another Linux
# ------------------------------------------------------------------------------
# ⚠️ ROYCE'S RULE, 2026-09-04. A person installing a video editor is not helped
# by being told which distribution is inside the box — it tells them nothing
# they can act on and gives them something new to worry about. The comments in
# these files still say Rocky, because whoever maintains them needs to know.
# Anything a USER reads says "environment".
#
# So this looks at the printable strings only: every line that is not a comment.
say "DaVinci Resolve — no other Linux is named where a person can see it"
AQ_LEAK=0
for f in /usr/libexec/aquarius-resolve-install \
    /usr/libexec/aquarius-resolve-installer \
    /usr/libexec/aquarius-resolve-uninstaller \
    /usr/libexec/aquarius-resolve-updater \
    /usr/libexec/aquarius-resolve-check \
    /usr/libexec/aquarius-resolve-update-notify \
    /usr/share/applications/aquarius-install-resolve.desktop \
    /usr/share/applications/aquarius-remove-resolve.desktop \
    /usr/share/applications/aquarius-update-resolve.desktop; do
    [ -r "${f}" ] || continue
    if grep -vE '^[[:space:]]*#' "${f}" | grep -qi 'rocky'; then
        bad "$(basename "${f}") names Rocky Linux in something a person reads:"
        grep -vE '^[[:space:]]*#' "${f}" | grep -i 'rocky' | sed 's/^/       /' >&2
        AQ_LEAK=1
    fi
done
[ "${AQ_LEAK}" -eq 0 ] && ok "nothing a person reads names another Linux"

# The window and the script have to agree on the progress lines, and the only
# way to know they still do is to run them. --dry-run walks all seven steps and
# installs nothing, so this is safe in a build container with no graphics card,
# no download and no network.
say "DaVinci Resolve — the progress channel between the two"
if /usr/libexec/aquarius-resolve-install --dry-run --progress-fd 3 \
    3> /tmp/aq-progress.txt > /tmp/aq-dryrun.txt 2>&1; then
    ok "the rehearsal ran"
else
    bad "'aquarius-resolve-install --dry-run' does not run"
    cat /tmp/aq-dryrun.txt
fi
echo "  What it said on the progress channel:"
sed 's/^/       /' /tmp/aq-progress.txt
EXPECTED_STEPS="$(grep -c '^STEP ' /tmp/aq-progress.txt || true)"
if [ "${EXPECTED_STEPS}" = "7" ]; then
    ok "all seven steps were announced"
else
    bad "the rehearsal announced ${EXPECTED_STEPS} steps, not 7 — the window's list would not match"
fi
# ⚠️ THE LAST ONE BY NAME. Step 7 is Royce's 2026-09-08 requirement — that the
# new version comes up at the screen's proper size — and it is the step most
# likely to be quietly dropped by somebody tidying the flow, because everything
# still installs without it.
aq_file_has /tmp/aq-progress.txt '^STEP 7/7 Matching Resolve to your screen$' \
    "the flow ends by checking Resolve still opens at the size of your screen"
if [ "$(tail -1 /tmp/aq-progress.txt)" = "DONE" ]; then
    ok "it finished with DONE, which is what moves the window to its last page"
else
    bad "the rehearsal did not end with DONE — the window would never say it had finished"
fi
if grep -q '^PERCENT ' /tmp/aq-progress.txt; then
    ok "PERCENT lines are being sent"
else
    bad "no PERCENT line was sent — the progress bar would never fill"
fi
# ------------------------------------------------------------------------------
# Is there a newer Resolve? — the checker, proved against a saved feed
# ------------------------------------------------------------------------------
# ⚠️ WHY THIS IS TESTED AGAINST A FILE AND NOT AGAINST BLACKMAGIC. A build that
# reached out to somebody else's website would fail whenever their site was
# having a bad day, which is a build that teaches people to ignore red ticks.
# /usr/share/aquarius/resolve/feed-sample.json is a small committed cut of their
# real list — both editions, a few versions, and one clearly-marked invented
# beta — so the PARSING is proved on every build with no network involved.
#
# What the network part does is checked by the bench, once, by unplugging it.
say "DaVinci Resolve — is there a newer one? (the update check)"
AQ_CHECK=/usr/libexec/aquarius-resolve-check
AQ_FEED=/usr/share/aquarius/resolve/feed-sample.json

if [ ! -f "${AQ_CHECK}" ]; then
    bad "${AQ_CHECK} is missing — nothing would ever notice a new Resolve"
else
    chmod 0755 "${AQ_CHECK}"
    if [ -x "${AQ_CHECK}" ]; then
        ok "aquarius-resolve-check is present and runnable"
    else
        bad "${AQ_CHECK} is not runnable"
    fi
    if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-check.pyc", doraise=True)' "${AQ_CHECK}"; then
        ok "aquarius-resolve-check is valid Python"
    else
        bad "${AQ_CHECK} has a syntax error"
    fi
fi
rm -f /tmp/aq-check.pyc

if [ ! -r "${AQ_FEED}" ]; then
    bad "${AQ_FEED} is missing — the update check could not be tested, and --dry-run would fail"
else
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("  %d entries in the saved feed" % len(d["downloads"]))' "${AQ_FEED}"; then
        ok "the saved copy of Blackmagic's release list is valid JSON"
    else
        bad "${AQ_FEED} is not valid JSON"
    fi
fi

if [ -x "${AQ_CHECK}" ] && [ -r "${AQ_FEED}" ]; then
    # THE THREE QUESTIONS THAT MATTER, asked with the edition and the installed
    # version supplied, so no machine state is involved and the answers are the
    # same on every build for ever.
    #
    #   1. An out-of-date Studio is told about the newest STUDIO.
    #   2. An up-to-date one is told it is up to date — and exits 0, which is
    #      what stops the timer sending a notification.
    #   3. A free copy is told about the newest FREE one, never Studio.
    #
    # And in every case the invented 21.2 BETA in the saved feed must be
    # ignored: an operating system does not put somebody on a beta on a Tuesday.
    # ⚠️ `|| AQ_CHECK_RC=$?` IS NOT OPTIONAL. These scripts run under `set -e`,
    # and this program exits 10 on purpose when there is something newer — which
    # is the answer we are testing for. Written the obvious way, the build would
    # stop dead on the line that proves the feature works.
    AQ_CHECK_RC=0
    AQ_CHECK_OUT="$("${AQ_CHECK}" --feed "${AQ_FEED}" --edition studio --installed-version 21.0.4)" \
        || AQ_CHECK_RC=$?
    echo "  studio 21.0.4 -> ${AQ_CHECK_OUT} (exit ${AQ_CHECK_RC})"
    if [ "${AQ_CHECK_RC}" = "10" ] \
        && printf '%s' "${AQ_CHECK_OUT}" | grep -q 'DaVinci Resolve Studio 21.1 is available'; then
        ok "an out-of-date Studio is offered Studio 21.1, and it exits 10 so the timer knows"
    else
        bad "the check did not offer Studio 21.1 to a Studio 21.0.4 machine"
    fi

    AQ_CHECK_RC=0
    AQ_CHECK_OUT="$("${AQ_CHECK}" --feed "${AQ_FEED}" --edition studio --installed-version 21.1)" \
        || AQ_CHECK_RC=$?
    echo "  studio 21.1   -> ${AQ_CHECK_OUT} (exit ${AQ_CHECK_RC})"
    if [ "${AQ_CHECK_RC}" = "0" ] \
        && printf '%s' "${AQ_CHECK_OUT}" | grep -q 'newest DaVinci Resolve Studio'; then
        ok "an up-to-date machine is told so, and exits 0 so nothing is announced"
    else
        bad "the check did not say an up-to-date Studio machine was up to date"
    fi

    AQ_CHECK_RC=0
    AQ_CHECK_OUT="$("${AQ_CHECK}" --feed "${AQ_FEED}" --edition free --installed-version 20.3.3)" \
        || AQ_CHECK_RC=$?
    echo "  free 20.3.3   -> ${AQ_CHECK_OUT}"
    if printf '%s' "${AQ_CHECK_OUT}" | grep -q '^DaVinci Resolve 21\.1 is available'; then
        ok "a free copy is offered the free 21.1 — never Studio, which is a different licence"
    else
        bad "the check offered a free copy something other than the newest free Resolve"
    fi

    # The beta, named explicitly. The saved feed contains a 21.2 beta for BOTH
    # editions, so if betas were ever counted, every answer above would say 21.2.
    if printf '%s' "${AQ_CHECK_OUT}" | grep -q '21\.2'; then
        bad "the check offered the 21.2 BETA in the saved feed — betas must be ignored"
    else
        ok "the 21.2 beta in the saved feed is ignored, as it must be"
    fi

    # --dry-run must work with no arguments at all and no network: it is what
    # the once-a-day job runs in a rehearsal, and what a person on the bench can
    # run with the network unplugged.
    if "${AQ_CHECK}" --dry-run > /tmp/aq-check-dry.txt 2>&1; then
        ok "'aquarius-resolve-check --dry-run' runs with no network at all"
        sed 's/^/       /' /tmp/aq-check-dry.txt
    else
        bad "'aquarius-resolve-check --dry-run' failed:"
        sed 's/^/       /' /tmp/aq-check-dry.txt
    fi
    rm -f /tmp/aq-check-dry.txt
fi

# The once-a-day job that turns that answer into one notification.
say "DaVinci Resolve — the once-a-day check and its notification"
AQ_NOTIFY=/usr/libexec/aquarius-resolve-update-notify
if [ ! -x "${AQ_NOTIFY}" ]; then
    bad "${AQ_NOTIFY} is missing or not runnable — nobody would ever be told about a new Resolve"
else
    # In a build container nothing is installed, so the rehearsal must say so
    # and stop. That is also the state of every machine that never uses Resolve.
    if "${AQ_NOTIFY}" --dry-run > /tmp/aq-notify-dry.txt 2>&1; then
        ok "'aquarius-resolve-update-notify --dry-run' runs"
        sed 's/^/       /' /tmp/aq-notify-dry.txt
    else
        bad "'aquarius-resolve-update-notify --dry-run' failed:"
        sed 's/^/       /' /tmp/aq-notify-dry.txt
    fi
    aq_file_has /tmp/aq-notify-dry.txt 'not set up on this computer' \
        "with no Resolve installed it says so and sends nothing"
    rm -f /tmp/aq-notify-dry.txt
    aq_file_has "${AQ_NOTIFY}" 'ANNOUNCED=' \
        "it remembers the version it announced, so nobody is told twice about one release"
fi
# notify-send is what sends it. It comes from libnotify, which step 55 installs
# for the session; named here so that dropping it there fails in the step whose
# name says why it matters.
aq_installed libnotify

AQ_TIMER=/usr/lib/systemd/user/aquarius-resolve-update-check.timer
AQ_TIMER_SVC=/usr/lib/systemd/user/aquarius-resolve-update-check.service
AQ_TIMER_LINK=/usr/lib/systemd/user/timers.target.wants/aquarius-resolve-update-check.timer
for unit in "${AQ_TIMER}" "${AQ_TIMER_SVC}"; do
    if [ -r "${unit}" ]; then
        ok "$(basename "${unit}") is installed"
    else
        bad "${unit} is missing — the daily check would never run"
    fi
done
aq_file_has "${AQ_TIMER_SVC}" '^ExecStart=/usr/libexec/aquarius-resolve-update-notify$' \
    "the service runs the check-and-notify job"
aq_file_has "${AQ_TIMER_SVC}" '^ConditionPathExists=%h/\.local/share/aquarius/resolve/installed\.env$' \
    "it does not even start on a machine that has never set Resolve up"
aq_file_has "${AQ_TIMER}" '^OnUnitActiveSec=1d$' \
    "it asks about once a day, not more"
aq_file_has "${AQ_TIMER}" '^RandomizedDelaySec=' \
    "with a random delay, so every AquariusOS does not knock on Blackmagic's door at once"
aq_file_has "${AQ_TIMER}" '^Persistent=true$' \
    "a machine that was switched off catches up rather than waiting another day"
aq_file_has "${AQ_TIMER}" '^WantedBy=timers\.target$' \
    "the timer belongs to timers.target, which every user session reaches"

# ⚠️ SWITCHED ON FROM /usr, NOT /etc. The long version is in aq-lib.sh next to
# aq_unit_is_on_from_usr: a link in /etc can be deleted by a local `disable`,
# and this kind of operating system then preserves that deletion for ever.
if [ -L "${AQ_TIMER_LINK}" ]; then
    echo "  ${AQ_TIMER_LINK} -> $(readlink "${AQ_TIMER_LINK}")"
    if [ -e "${AQ_TIMER_LINK}" ]; then
        ok "the daily check is switched on from /usr, so an update always restores it"
    else
        bad "the 'switched on' link for the daily check is dangling — it points at nothing"
    fi
else
    bad "${AQ_TIMER_LINK} is missing — the timer would be installed but never start"
fi
if [ -e /etc/systemd/user/timers.target.wants/aquarius-resolve-update-check.timer ]; then
    bad "the daily check is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "nothing switches the daily check on through /etc (an update could lose that)"
fi

# systemd's own reader, where the build stage has it. Advisory: it complains
# about things that are true only on a running machine, so only a parse failure
# is worth failing a build over, and that shows up as a line saying so.
if aq_have systemd-analyze; then
    systemd-analyze verify --user "${AQ_TIMER}" > /tmp/aq-timer-check.txt 2>&1 || true
    if [ -s /tmp/aq-timer-check.txt ]; then
        echo "  NOTE: systemd-analyze had something to say about the timer:"
        sed 's/^/         /' /tmp/aq-timer-check.txt
    else
        ok "systemd is happy with aquarius-resolve-update-check.timer"
    fi
    rm -f /tmp/aq-timer-check.txt
fi

# ------------------------------------------------------------------------------
# The update flow walks the same channel
# ------------------------------------------------------------------------------
# `aq resolve update` is the same script in a different mode, so the window that
# reads it can be the same shape. Seven steps, in order, ending in DONE — a
# window drawing seven rows against a script sending six is a bar that never
# finishes.
say "DaVinci Resolve — the update flow's side of the progress channel"
if /usr/libexec/aquarius-resolve-install --update --dry-run --progress-fd 3 \
    3> /tmp/aq-update-progress.txt > /tmp/aq-update-dryrun.txt 2>&1; then
    ok "the update rehearsal ran"
else
    bad "'aquarius-resolve-install --update --dry-run' does not run"
    cat /tmp/aq-update-dryrun.txt
fi
echo "  What it said on the progress channel:"
sed 's/^/       /' /tmp/aq-update-progress.txt
AQ_UPDATE_N=0
while IFS= read -r line; do
    case "${line}" in
        "STEP "*)
            AQ_UPDATE_N=$((AQ_UPDATE_N + 1))
            case "${line}" in
                "STEP ${AQ_UPDATE_N}/7 "*) : ;;
                *) bad "expected a line starting 'STEP ${AQ_UPDATE_N}/7 ' and got: ${line}" ;;
            esac
            ;;
    esac
done < /tmp/aq-update-progress.txt
if [ "${AQ_UPDATE_N}" = "7" ]; then
    ok "the update announced all seven steps, in order"
else
    bad "the update rehearsal announced ${AQ_UPDATE_N} steps, not 7"
fi
if [ "$(tail -1 /tmp/aq-update-progress.txt)" = "DONE" ]; then
    ok "it finished with DONE, which is what moves the window to its last page"
else
    bad "the update rehearsal did not end with DONE"
fi
aq_file_has /tmp/aq-update-progress.txt '^STEP 7/7 Matching Resolve to your screen$' \
    "an update ends by checking Resolve still opens at the size of your screen"
# The rehearsal really asks the update check (offline, against the saved feed),
# so this proves the two programs still fit together.
aq_file_has /tmp/aq-update-dryrun.txt 'What the update check says' \
    "the update rehearsal really asks the update check, rather than pretending to"
rm -f /tmp/aq-update-progress.txt /tmp/aq-update-dryrun.txt

# ------------------------------------------------------------------------------
# The removing side of the same channel
# ------------------------------------------------------------------------------
# "Remove DaVinci Resolve" is a window too now, and it reads the same STEP /
# DONE lines from the same script. Three steps rather than six, so it is checked
# separately — a window drawing three rows against a script sending six is a
# progress bar that never finishes.
say "DaVinci Resolve — the removing side of the progress channel"
if /usr/libexec/aquarius-resolve-install --remove --dry-run --progress-fd 3 \
    3> /tmp/aq-remove-progress.txt > /tmp/aq-remove-dryrun.txt 2>&1; then
    ok "the removal rehearsal ran"
else
    bad "'aquarius-resolve-install --remove --dry-run' does not run"
    cat /tmp/aq-remove-dryrun.txt
fi
echo "  What it said on the progress channel:"
sed 's/^/       /' /tmp/aq-remove-progress.txt
AQ_REMOVE_STEPS="$(grep -c '^STEP ' /tmp/aq-remove-progress.txt || true)"
if [ "${AQ_REMOVE_STEPS}" = "3" ]; then
    ok "all three removal steps were announced"
else
    bad "the removal rehearsal announced ${AQ_REMOVE_STEPS} steps, not 3"
fi
if [ "$(tail -1 /tmp/aq-remove-progress.txt)" = "DONE" ]; then
    ok "it finished with DONE"
else
    bad "the removal rehearsal did not end with DONE — the window would never say it had finished"
fi
# ⚠️ THE ONE THAT MATTERS MOST. Without --purge the person's project database
# must be KEPT, and the step must say so. A removal that quietly deleted
# somebody's project library would be the worst bug in this operating system.
aq_file_has /tmp/aq-remove-progress.txt '^STEP 3/3 Keeping your projects and settings$' \
    "by default the third step KEEPS your projects and settings"
if /usr/libexec/aquarius-resolve-install --remove --purge --dry-run --progress-fd 3 \
    3> /tmp/aq-purge-progress.txt > /dev/null 2>&1; then
    aq_file_has /tmp/aq-purge-progress.txt '^STEP 3/3 Deleting your Resolve settings and project database$' \
        "and --purge, which nothing ticks by default, deletes them instead"
else
    bad "'--remove --purge --dry-run' does not run"
fi
rm -f /tmp/aq-remove-progress.txt /tmp/aq-remove-dryrun.txt /tmp/aq-purge-progress.txt

# ------------------------------------------------------------------------------
# Resolve comes up the right size, with the right pointer
# ------------------------------------------------------------------------------
# ⚠️ THE 2026-09-04 BENCH REPORT: "apps resolution and appearing smaller", and
# the pointer changing shape inside Resolve. Both have the same cause — Resolve
# is an X11 program, XWayland tells X11 programs the screen is at 100% whatever
# it is really at, and the container has neither your scale nor your cursor
# theme. The launcher carries all of it in. These check the lines are still
# there, because a launcher that silently stops passing them looks exactly like
# a launcher that is working.
say "DaVinci Resolve — the size and the pointer"
AQ_LAUNCH=/usr/libexec/aquarius-resolve-launch
aq_file_has "${AQ_LAUNCH}" 'QT_AUTO_SCREEN_SCALE_FACTOR=0' \
    "Qt is stopped from asking XWayland how dense the screen is (it always answers 96 dpi)"
aq_file_has "${AQ_LAUNCH}" 'QT_SCALE_FACTOR=\$\{SCALE\}' \
    "the session's scale is handed to Resolve"
aq_file_has "${AQ_LAUNCH}" 'QT_DEVICE_PIXEL_RATIO=\$\{SCALE\}' \
    "and the other Qt 5 variable is reachable for the bench to compare"
aq_file_has "${AQ_LAUNCH}" 'aquarius-display-scale --effective-scale' \
    "the scale is asked of the same helper 'aq display' asks"
aq_file_has "${AQ_LAUNCH}" 'XCURSOR_THEME=' "your cursor theme is carried in"
aq_file_has "${AQ_LAUNCH}" 'XCURSOR_SIZE=' "so is its size"
aq_file_has "${AQ_LAUNCH}" 'XCURSOR_PATH=' "and where to find the theme from inside"

# ⚠️ AND IT HAS TO BE ABLE TO SAY WHAT IT WOULD DO WITHOUT DOING IT. --report
# is what the last step of every install and update ("Matching Resolve to your
# screen") asks, and what a person on the bench can run to see the answer. It
# must work on a machine with no Resolve and no screen, which is exactly what a
# build container is — if it ever needed the container to exist, that step would
# quietly stop checking anything.
aq_file_has "${AQ_LAUNCH}" 'REPORT_ONLY' \
    "the launcher can report its size and pointer without starting Resolve"
AQ_REPORT="$("${AQ_LAUNCH}" --report 2>&1 || true)"
echo "  What it says it would hand Resolve: ${AQ_REPORT}"
if printf '%s' "${AQ_REPORT}" | grep -q 'interface at'; then
    ok "'aquarius-resolve-launch --report' answers, on a machine with no Resolve at all"
else
    bad "'--report' did not print its scale line, so the 'Matching Resolve to your screen' step would have nothing to ask"
fi

# And the step itself, in the installer, by name. Grepped rather than run,
# because the running of it needs an app-menu entry and a container.
aq_file_has /usr/libexec/aquarius-resolve-install 'step 7 "Matching Resolve to your screen"' \
    "the installer really has the step that checks Resolve against your screen"
aq_file_has /usr/libexec/aquarius-resolve-install 'aquarius-resolve-launch --report' \
    "that step asks the launcher what size it would use"
aq_file_has /usr/libexec/aquarius-resolve-install 'conf_fingerprint' \
    "and checks your own size setting was not touched, by its contents rather than its clock"

# The helper has to actually answer, with a number, on a machine with no screen
# at all — which is what a build container is, and what running Resolve from
# GNOME or over SSH looks like too.
AQ_EFFECTIVE="$(/usr/libexec/aquarius-display-scale --effective-scale 2>&1 || true)"
echo "  --effective-scale on this machine (no screens at all): '${AQ_EFFECTIVE}'"
case "${AQ_EFFECTIVE}" in
    '' | *[!0-9.]*)
        bad "'--effective-scale' did not print a plain number, so the launcher would have nothing to hand Resolve"
        ;;
    *) ok "'--effective-scale' answers with a number even where there are no screens" ;;
esac

# ------------------------------------------------------------------------------
# And the window fits the screen — the labwc rule
# ------------------------------------------------------------------------------
# ⚠️ THE FAULT THIS ENDS, from docs/restart/resolve.md §"The window is bigger
# than the screen": Resolve sizes its own window and on a 4K display sometimes
# opened one whose edges, close button included, were off the screen.
#
# The fix is a window rule in the Aquarius Desktop's labwc configuration, and it
# is the ONLY rule in that file that names an application. It is checked here,
# in the Resolve step, rather than in the desktop step, because it is a Resolve
# feature that happens to be written in a desktop file — somebody tidying
# rc.xml would have no reason to know it mattered.
#
# READ AS XML, not grepped for. A reworded comment, a different indentation or a
# line break in a different place must not be able to make this pass or fail.
# The same rule must be in the aquarius-shell repository's copy of rc.xml;
# build_files/check-labwc-drift.sh is what proves that, in CI.
say "DaVinci Resolve — the window fits the screen"
AQ_RC=/usr/share/aquarius/labwc/rc.xml
if [ ! -r "${AQ_RC}" ]; then
    bad "${AQ_RC} is missing — the Aquarius Desktop would have no window rules at all"
else
    if AQ_RULE="$(python3 - "${AQ_RC}" << 'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
for rule in root.findall("./windowRules/windowRule"):
    if (rule.get("identifier") or "").lower() == "resolve":
        print(",".join((action.get("name") or "") for action in rule.findall("action")))
        sys.exit(0)
sys.exit(1)
PY
    )"; then
        echo "  The rule for Resolve runs: ${AQ_RULE}"
        case ",${AQ_RULE}," in
            *,FitToOutput,*) ok "a window bigger than the screen is shrunk to the screen (FitToOutput)" ;;
            *) bad "the Resolve window rule has no FitToOutput — a window larger than the screen would stay larger than the screen" ;;
        esac
        case ",${AQ_RULE}," in
            *,Maximize,*) ok "and Resolve then fills the screen it opened on (Maximize)" ;;
            *) bad "the Resolve window rule has no Maximize — Resolve would not open at the size of the screen" ;;
        esac
    else
        bad "rc.xml has no <windowRule identifier=\"resolve\"> — Resolve could open with its edges off a 4K screen again"
    fi
fi

# ------------------------------------------------------------------------------
# Your drives are in the same places inside
# ------------------------------------------------------------------------------
# ⚠️ WHY THIS IS A BUILD CHECK AND NOT ONLY A BENCH ONE. A Resolve project
# stores the FULL PATH of every clip. If an external drive is at
# /run/media/royce/SHOOT-2026 outside the container and nowhere inside it, then
# dragging media in from Files does nothing, "Open With → DaVinci Resolve"
# opens an empty Resolve, and yesterday's project comes up with its media
# offline. None of those say why, and all three look like Resolve being broken.
#
# There are no drives on a build machine and no container to ask, so the two
# facts the check needs are handed to it instead — that is what the two
# AQ_RESOLVE_FAKE_DRIVES variables are for, and they are documented beside
# report_drives in the installer. What is proved here is the WORDING and the
# ARITHMETIC for all three outcomes, which is the part that can silently rot.
say "DaVinci Resolve — your drives are in the same places inside"

aq_drives() { # aq_drives <host-list> <inside-list>
    AQ_RESOLVE_FAKE_DRIVES="$1" AQ_RESOLVE_FAKE_DRIVES_INSIDE="$2" \
        /usr/libexec/aquarius-resolve-install --drives 2>&1
}

# No drives at all: the state of a laptop with nothing plugged in, and of this
# build machine. It must be a calm sentence, never a warning.
AQ_DRIVES_NONE="$(aq_drives "" "")"
echo "  With no drives plugged in:"
printf '%s\n' "${AQ_DRIVES_NONE}" | sed 's/^/    /'
if printf '%s' "${AQ_DRIVES_NONE}" | grep -q 'No extra drives are plugged in'; then
    ok "a machine with no drives is told so plainly, with no warning"
else
    bad "the drives check does not handle a machine with no drives"
fi
if printf '%s' "${AQ_DRIVES_NONE}" | grep -q 'cannot be reached'; then
    bad "a machine with no drives is warned about drives it does not have"
else
    ok "and it warns about nothing"
fi

# One drive, visible inside. The everyday answer.
AQ_DRIVES_OK="$(aq_drives "/run/media/tester/SHOOT" "/run/media/tester/SHOOT")"
echo "  With one drive that IS visible inside:"
printf '%s\n' "${AQ_DRIVES_OK}" | sed 's/^/    /'
if printf '%s' "${AQ_DRIVES_OK}" | grep -q 'is visible inside Resolve at the same path'; then
    ok "one drive that lines up is reported as lining up"
else
    bad "the drives check does not say a drive is visible when it is"
fi

# One drive of two, missing. The fault this whole check exists for. It has to
# NAME the drive and say what to do, not merely disapprove.
AQ_DRIVES_BAD="$(aq_drives "/run/media/tester/A:/run/media/tester/B" "/run/media/tester/A")"
echo "  With one drive of two missing inside:"
printf '%s\n' "${AQ_DRIVES_BAD}" | sed 's/^/    /'
if printf '%s' "${AQ_DRIVES_BAD}" | grep -q '1 of your 2 drives cannot be reached'; then
    ok "a missing drive is counted correctly against the ones that are there"
else
    bad "the drives check miscounts, or does not notice, a drive that is missing inside"
fi
if printf '%s' "${AQ_DRIVES_BAD}" | grep -q '/run/media/tester/B'; then
    ok "and it names the drive, rather than saying something is wrong somewhere"
else
    bad "the drives check does not name the drive that is missing"
fi
if printf '%s' "${AQ_DRIVES_BAD}" | grep -q 'aq resolve install'; then
    ok "and it ends with what to do about it"
else
    bad "the drives check names a problem and no way out of it"
fi

# And the step really carries it. Grepped in the rehearsal's own output, which
# is the copy a person would see.
aq_file_has /tmp/aq-dryrun.txt '^  Your drives, inside and out$' \
    "step 7 of every install and update asks about your drives"
aq_file_has /usr/bin/aq 'AQ_RESOLVE_INSTALLER\}" --drives' \
    "'aq resolve status' asks the same question of the same script, rather than working out its own answer"

# And the front door for changing it by hand.
if /usr/bin/aq resolve scale > /tmp/aq-resolve-scale.txt 2>&1; then
    ok "'aq resolve scale' runs"
    sed 's/^/       /' /tmp/aq-resolve-scale.txt
else
    bad "'aq resolve scale' does not run"
    cat /tmp/aq-resolve-scale.txt
fi
rm -f /tmp/aq-resolve-scale.txt

# The two questions the window asks before it starts anything.
#
# Captured into a variable rather than piped into grep. `grep -q` stops at the
# first match, and with `set -o pipefail` a producer killed writing into a pipe
# nobody is reading any more reports the whole pipeline as failed — the trap
# written up at the top of aq-lib.sh.
AQ_GPU_LINE="$(/usr/libexec/aquarius-resolve-install --gpu-summary || true)"
echo "  What it says about this machine's graphics: ${AQ_GPU_LINE}"
if printf '%s' "${AQ_GPU_LINE}" | grep -Eq "^(ok|warn|none)$(printf '\t')"; then
    ok "'--gpu-summary' answers in the shape the window reads (a word, a tab, a sentence)"
else
    bad "'--gpu-summary' does not answer in the shape the window reads"
fi
# --find-installer exits 1 when there is no download, which is the state of
# every build container, so a zero exit here would mean it had found something
# that cannot possibly exist.
if /usr/libexec/aquarius-resolve-install --find-installer > /dev/null 2>&1; then
    bad "'--find-installer' claims to have found a Resolve download in the build container"
else
    ok "'--find-installer' correctly finds nothing in a machine with no download"
fi

# The one place the runtime container image is named.
AQ_RUNTIME_ENV=/usr/share/aquarius/resolve/runtime.env
if [ ! -r "${AQ_RUNTIME_ENV}" ]; then
    bad "${AQ_RUNTIME_ENV} is missing — nothing would know which container to download"
else
    aq_file_has "${AQ_RUNTIME_ENV}" \
        '^AQ_RESOLVE_RUNTIME_IMAGE=ghcr\.io/[a-z0-9-]+/aquarius-resolve-runtime$' \
        "the runtime container image is named"
    aq_file_has "${AQ_RUNTIME_ENV}" \
        '^AQ_RESOLVE_RUNTIME_TAG=[0-9]+$' \
        "it is pinned to an Enterprise Linux release, not a moving 'latest' tag"
    aq_file_has "${AQ_RUNTIME_ENV}" \
        '^AQ_RESOLVE_CONTAINER=[a-z0-9-]+$' \
        "the container has a fixed name"
    echo "  The runtime this image will pull:"
    grep -E '^AQ_RESOLVE' "${AQ_RUNTIME_ENV}" | sed 's/^/       /'
fi

# The app-grid entry — the zero-terminal way in.
AQ_DESKTOP=/usr/share/applications/aquarius-install-resolve.desktop
if [ ! -r "${AQ_DESKTOP}" ]; then
    bad "${AQ_DESKTOP} is missing — there would be no way to start this without a terminal"
else
    aq_file_has "${AQ_DESKTOP}" '^Exec=/usr/libexec/aquarius-resolve-installer$' \
        "the app-grid entry points at the installer window"
    aq_file_has "${AQ_DESKTOP}" '^Terminal=false$' \
        "it opens its own window rather than expecting a terminal"
    # The window sets this same name as its application id. Without the match,
    # a running installer shows up in the dock as a nameless generic window
    # instead of as "Install DaVinci Resolve" with the Aquarius mark on it.
    aq_file_has "${AQ_DESKTOP}" '^StartupWMClass=org\.aquariusos\.ResolveInstaller$' \
        "the desktop knows which window belongs to this entry"
    # Since 2026-09-06 this has its OWN icon — "DR" with a gold plus — instead
    # of the general Aquarius mark. The icon itself, and the fact that both
    # themes contain it, are checked in build_files/56-aquarius-icons.sh; this
    # line only checks that the entry asks for the right name.
    aq_file_has "${AQ_DESKTOP}" '^Icon=aquarius-install-resolve$' \
        "it wears its own 'DR +' icon"
    # desktop-file-validate is the freedesktop project's own checker. A .desktop
    # file with a bad line is silently ignored by the app grid — the entry
    # simply never appears — so this is worth a package.
    if ! aq_have desktop-file-validate; then
        aq_dnf install desktop-file-utils
    fi
    if desktop-file-validate "${AQ_DESKTOP}"; then
        ok "the app-grid entry passes freedesktop's own validator"
    else
        bad "${AQ_DESKTOP} is not a valid desktop entry — it would never appear in the app grid"
    fi
fi

# The way out, which is a window too now. An operating system with a friendly
# way in and a terminal command for the way out has said something it did not
# mean to.
AQ_DESKTOP_RM=/usr/share/applications/aquarius-remove-resolve.desktop
if [ ! -r "${AQ_DESKTOP_RM}" ]; then
    bad "${AQ_DESKTOP_RM} is missing — there would be no way to remove Resolve without a terminal"
else
    aq_file_has "${AQ_DESKTOP_RM}" '^Exec=/usr/libexec/aquarius-resolve-uninstaller$' \
        "the Remove entry points at the uninstaller window"
    aq_file_has "${AQ_DESKTOP_RM}" '^Terminal=false$' \
        "it opens its own window rather than expecting a terminal"
    aq_file_has "${AQ_DESKTOP_RM}" '^StartupWMClass=org\.aquariusos\.ResolveUninstaller$' \
        "the desktop knows which window belongs to this entry"
    if desktop-file-validate "${AQ_DESKTOP_RM}"; then
        ok "the Remove entry passes freedesktop's own validator"
    else
        bad "${AQ_DESKTOP_RM} is not a valid desktop entry — it would never appear in the app grid"
    fi
fi

# The way to update it, which is a window too. An operating system that can be
# updated only by remembering a command has said something it did not mean to.
AQ_DESKTOP_UP=/usr/share/applications/aquarius-update-resolve.desktop
if [ ! -r "${AQ_DESKTOP_UP}" ]; then
    bad "${AQ_DESKTOP_UP} is missing — there would be no way to update Resolve without a terminal"
else
    aq_file_has "${AQ_DESKTOP_UP}" '^Exec=/usr/libexec/aquarius-resolve-updater$' \
        "the Update entry points at the update window"
    aq_file_has "${AQ_DESKTOP_UP}" '^Terminal=false$' \
        "it opens its own window rather than expecting a terminal"
    aq_file_has "${AQ_DESKTOP_UP}" '^StartupWMClass=org\.aquariusos\.ResolveUpdater$' \
        "the desktop knows which window belongs to this entry"
    # It wears the Aquarius mark. Install and Remove have their own drawn "DR +"
    # and "DR −" icons; a third drawing is a design decision for Royce, not one
    # to invent in a build script, so this asks for the mark the image already
    # installs and says so out loud rather than leaving a mystery.
    aq_file_has "${AQ_DESKTOP_UP}" '^Icon=aquarius-logo$' \
        "it wears the Aquarius mark"
    if desktop-file-validate "${AQ_DESKTOP_UP}"; then
        ok "the Update entry passes freedesktop's own validator"
    else
        bad "${AQ_DESKTOP_UP} is not a valid desktop entry — it would never appear in the app grid"
    fi
fi

# The USB rules for licence dongles and control panels. These have to be on the
# host: Resolve's own installer writes them inside the container, where they
# apply to nothing, and AquariusOS's system folder is read-only so nothing can
# add them afterwards. Shipping them in the image is the only way.
AQ_UDEV=/usr/lib/udev/rules.d/75-aquarius-resolve.rules
if [ ! -r "${AQ_UDEV}" ]; then
    bad "${AQ_UDEV} is missing — a Resolve Studio licence dongle would not be seen"
else
    aq_file_has "${AQ_UDEV}" 'idVendor}=="1edb"' \
        "Blackmagic Design hardware (control panels) has a rule"
    aq_file_has "${AQ_UDEV}" 'idVendor}=="096e"' \
        "the Resolve Studio USB licence dongle has a rule"
    echo "  The rules, in full:"
    grep -v '^#' "${AQ_UDEV}" | grep -v '^$' | sed 's/^/       /'
fi

# ------------------------------------------------------------------------------
# 4. The `aq resolve` command
# ------------------------------------------------------------------------------
say "DaVinci Resolve — the aq resolve command"

if [ ! -x /usr/bin/aq ]; then
    bad "/usr/bin/aq is missing"
else
    aq_file_has /usr/bin/aq '^    resolve\)' "aq knows the 'resolve' subcommand"
    aq_file_has /usr/bin/aq 'AQ_RESOLVE_INSTALLER_GUI=/usr/libexec/aquarius-resolve-installer' \
        "'aq resolve install --gui' knows where the window is"
    aq_file_has /usr/bin/aq 'AQ_RESOLVE_UNINSTALLER_GUI=/usr/libexec/aquarius-resolve-uninstaller' \
        "'aq resolve remove --gui' knows where its window is"
    aq_file_has /usr/bin/aq 'AQ_RESOLVE_UPDATER_GUI=/usr/libexec/aquarius-resolve-updater' \
        "'aq resolve update --gui' knows where its window is"
    aq_file_has /usr/bin/aq 'AQ_RESOLVE_CHECK=/usr/libexec/aquarius-resolve-check' \
        "'aq resolve check' knows where the checker is"
    # Run it. A machine with no Resolve installed must be told so calmly and
    # exit 0 — this is the state of every build container and of every machine
    # that has not set Resolve up, so it is the answer most people will see.
    if /usr/bin/aq resolve check > /tmp/aq-resolve-check.txt 2>&1; then
        ok "'aq resolve check' runs on a machine with nothing installed"
        sed 's/^/       /' /tmp/aq-resolve-check.txt
    else
        bad "'aq resolve check' failed where Resolve is not installed — it must be quiet, not alarming"
        cat /tmp/aq-resolve-check.txt
    fi
    rm -f /tmp/aq-resolve-check.txt
    # Run it for real. A help screen that crashes is a help screen nobody can
    # read at the moment they most need it.
    if /usr/bin/aq resolve --help > /tmp/aq-resolve-help.txt 2>&1; then
        ok "'aq resolve --help' runs"
        # ⚠️ `head` FIRST, THEN `sed`. The other way round — `sed file | head` —
        # is the broken-pipe trap written up at the top of aq-lib.sh: `head`
        # stops after 20 lines, whatever is upstream is killed writing to a pipe
        # nobody is reading, and `set -o pipefail` reports the whole pipeline as
        # failed.
        #
        # Being precise, because a half-understood rule is worse than none: with
        # 46 lines of help text this particular pipeline would probably NOT have
        # failed, because all of it fits in the pipe's buffer and `sed` finishes
        # before `head` closes anything. It is a latent bug, not a certain one —
        # it would start failing the day somebody added enough help text to
        # exceed 64 KB, and would then look like a change to a different file
        # breaking this one. Writing it the safe way round costs nothing.
        head -20 /tmp/aq-resolve-help.txt | sed 's/^/       /'
        # A command nobody can discover is a command nobody uses.
        aq_file_has /tmp/aq-resolve-help.txt 'aq resolve check' \
            "the help text tells people 'aq resolve check' exists"
        aq_file_has /tmp/aq-resolve-help.txt 'aq resolve update' \
            "and 'aq resolve update'"
    else
        bad "'aq resolve --help' does not run"
        cat /tmp/aq-resolve-help.txt
    fi
    rm -f /tmp/aq-resolve-help.txt
fi

# ------------------------------------------------------------------------------
# 5. What this step deliberately does NOT do
# ------------------------------------------------------------------------------
# It does not download the Rocky Linux runtime. That would add about a gigabyte
# to an operating system image that everyone downloads, for a feature not
# everyone uses. It arrives on first use instead, which is the whole reason it
# is a separate image with its own build.
say "Not downloaded on purpose"
echo "  The Rocky Linux runtime is NOT baked into this image."
echo "  It is about a gigabyte and it is fetched the first time somebody sets"
echo "  Resolve up. Baking it in would make every AquariusOS download bigger"
echo "  for a feature not everybody uses."

aq_finish "DaVinci Resolve"
