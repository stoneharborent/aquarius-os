#!/usr/bin/bash
# ==============================================================================
# STEP 71 — Screenshots and screen recording
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# Royce asked for two buttons in the top bar — Screenshot and Record screen —
# each offering the whole screen, one app, or a dragged area, with everything
# landing in one Screenshots folder that is pinned in the Files sidebar.
# (FEATURES 017, 2026-09-13.)
#
# This step is the operating system's half of that. It puts four small programs
# on the image, checks our own capture helper is there and is valid shell,
# checks the keyboard shortcuts really point at it, and checks the login-time
# service that makes the folder. The top bar's half lives in the aquarius-shell
# repository and talks to this by running the helper — never by reaching into
# the compositor, which is the one architectural law of that repo.
#
# ------------------------------------------------------------------------------
# THE FOUR PROGRAMS, AND WHY EACH ONE
# ------------------------------------------------------------------------------
#   grim         Takes the picture. Already in the image? No — grim has been in
#                the labwc BUILDER stage since the restart (it is how the
#                decoration-colour test photographs a window), and a builder
#                stage is thrown away. Nothing put it on the finished image.
#                This step does.
#
#   slurp        Draws the dimmed overlay you drag on. ALREADY on the image
#                since 55-aquarius-session.sh, because the screen-sharing portal
#                uses it to ask "which screen?". Named here anyway, because a
#                step whose heading says "screenshots" is where a person will
#                look when the overlay does not appear — and because if the
#                portal were ever rewritten to use something else, this feature
#                must not silently lose its picker.
#
#   wl-clipboard Supplies `wl-copy`, which is how a screenshot reaches the
#                clipboard. Without it every screenshot would still be saved
#                and none of them could be pasted, which is half the feature.
#
#   wf-recorder  Films. See the next section — choosing this was the one real
#                decision in this step.
#
# ------------------------------------------------------------------------------
# WHICH RECORDER, AND WHY wf-recorder
# ------------------------------------------------------------------------------
# FEATURES 017 said: wf-recorder if Fedora 44 packages it, else wl-screenrec,
# and say which and why. Checked on 2026-09-13 against Fedora's own package
# index:
#
#   wf-recorder   0.6.0-2.fc44   in Fedora 44's ORDINARY repositories
#   wl-screenrec  not packaged for any Fedora release
#
# So it is wf-recorder, and the choice needed no new repository — which matters,
# because a third-party repository is a permanent new thing to trust and a
# permanent new way for an update to break. Everything here comes from Fedora
# itself and from RPM Fusion, both of which this image already uses.
#
# wf-recorder is also the right shape for us for two reasons beyond packaging:
# it comes from the same people as grim and reads the same Wayland protocol, and
# it hands its frames straight to ffmpeg — the FULL ffmpeg from RPM Fusion that
# 20-hardware-media.sh already installed. That is what gives us H.264 with
# hardware encoding on all three kinds of machine (NVENC on NVIDIA, VA-API on
# AMD and Intel, libx264 in software), chosen on the machine at the moment the
# person presses record. The helper's own header explains that choice at length.
#
# ------------------------------------------------------------------------------
# ⚠️ WHAT "window" MODE HONESTLY DOES, SO THAT NOBODY IS SURPRISED LATER
# ------------------------------------------------------------------------------
# It does NOT light up a window and capture exactly it, the way a Mac does, and
# it cannot today. Capturing one window needs that window's position and size,
# and the Wayland protocol every compositor publishes its window list through
# (wlr-foreign-toplevel-management) deliberately carries no geometry at all.
# sway users get window-accurate screenshots from sway's own private command
# channel; labwc has none. `wlrctl`, the obvious candidate on Fedora 44, reads
# the same protocol and therefore knows no more than we do.
#
# So "window" asks the person to drag a box round the window. One extra second,
# and truthful. When labwc grows a geometry source this changes in ONE function,
# `aq_capture_geometry` in /usr/libexec/aquarius-capture, and nowhere else.
#
# ------------------------------------------------------------------------------
# WHERE THIS STEP SITS IN THE BUILD
# ------------------------------------------------------------------------------
# After 7k (Homebrew) and before step 8 (boot branding). Step 8 rebuilds the
# boot ramdisk and nothing here touches the kernel, so this must come first; and
# nothing here needs anything Homebrew installed, so the position is simply "the
# next number".
#
# Plain-English guide: docs/restart/screenshots.md
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

HELPER="/usr/libexec/aquarius-capture"
SETUP_UNIT="/usr/lib/systemd/user/aquarius-capture-setup.service"
SETUP_LINK="/usr/lib/systemd/user/graphical-session.target.wants/aquarius-capture-setup.service"
RC_XML="/usr/share/aquarius/labwc/rc.xml"
MAC_KEYS="/usr/share/aquarius/keys/mac.yaml"
WINDOWS_KEYS="/usr/share/aquarius/keys/windows.yaml"
DOC="/ctx/docs/restart/screenshots.md"

# ==============================================================================
# 1. The four programs
# ==============================================================================
say "The screenshot and recording tools"
aq_dnf install \
    grim \
    slurp \
    wl-clipboard \
    wf-recorder

aq_installed \
    grim \
    slurp \
    wl-clipboard \
    wf-recorder

# The package being installed and the COMMAND being there are two different
# questions — a package can move a binary between releases and nothing warns
# you. The helper calls these four names and no others.
say "And each one really answers to its name"
for cmd in grim slurp wl-copy wf-recorder; do
    if aq_have "${cmd}"; then
        ok "${cmd} -> $(command -v "${cmd}")"
    else
        bad "${cmd} is not on the PATH — the capture helper calls it by that exact name"
    fi
done

# notify-send and xdg-open are the other two things the helper shells out to.
# Both arrive with earlier steps (libnotify at 55, xdg-utils with the desktop),
# so this is a guard against a future step dropping one, not an install.
for cmd in notify-send xdg-open; do
    if aq_have "${cmd}"; then
        ok "${cmd} is available (the 'Show in Files' notification needs it)"
    else
        bad "${cmd} is missing — a saved screenshot would never tell anybody about itself"
    fi
done

# ------------------------------------------------------------------------------
# The recorder can only make an MP4 anybody can open if ffmpeg has H.264 in it
# ------------------------------------------------------------------------------
# ⚠️ THIS IS THE CHECK THAT CATCHES THE SILENT VERSION OF THIS FEATURE FAILING.
# Fedora's own ffmpeg ("ffmpeg-free") has the patented encoders removed, and
# H.264 is one of them. wf-recorder links against whichever ffmpeg is on the
# machine; with the free one it installs perfectly, runs perfectly, and produces
# nothing — a recording that fails at the moment a person presses the button.
#
# 20-hardware-media.sh swaps in RPM Fusion's full ffmpeg precisely so that this
# is not the case. This reads the answer back rather than assuming that step
# stayed as it is.
say "The encoders wf-recorder will hand its frames to"
if aq_have ffmpeg; then
    ffmpeg -hide_banner -encoders > /tmp/aq-capture-encoders.txt 2>&1 || true
    if grep -q 'libx264' /tmp/aq-capture-encoders.txt; then
        ok "ffmpeg can encode H.264 in software (libx264) — the fallback every machine uses"
    else
        bad "ffmpeg has no libx264 — screen recording would fail on any machine without hardware encoding. Has 20-hardware-media.sh stopped swapping in RPM Fusion's ffmpeg?"
    fi
    # These two are the hardware paths. They are checked as INFORMATION, not as
    # pass-or-fail: whether a machine can really use them depends on the graphics
    # card in it, which an image cannot know. The helper picks at run time.
    for enc in h264_vaapi h264_nvenc; do
        if grep -q "${enc}" /tmp/aq-capture-encoders.txt; then
            echo "  (for information) ffmpeg offers ${enc} — used on machines whose graphics card has it"
        else
            echo "  (for information) ffmpeg does NOT offer ${enc} — those machines fall back to software"
        fi
    done
    rm -f /tmp/aq-capture-encoders.txt
else
    bad "ffmpeg is not in the image — wf-recorder has nothing to encode with"
fi

# ==============================================================================
# 2. Our own helper
# ==============================================================================
# It arrived with system_files at step 5. This step reads it, because a bar
# button pointing at a program that is not there is the whole feature gone.
say "The capture helper"
if [ -x "${HELPER}" ]; then
    ok "${HELPER} is present and runnable"
else
    bad "${HELPER} is missing or not executable — every button and every shortcut would do nothing"
fi

if bash -n "${HELPER}" 2> /tmp/aq-capture-syntax.txt; then
    ok "the helper is valid shell"
else
    bad "the helper has a syntax error:"
    sed 's/^/       /' /tmp/aq-capture-syntax.txt
fi
rm -f /tmp/aq-capture-syntax.txt

# ------------------------------------------------------------------------------
# The contract the top bar depends on, proved by running it
# ------------------------------------------------------------------------------
# ⚠️ THESE ARE NOT DECORATION. The shell repository's bar buttons are written
# against this exact wording: `status` returning JSON, always, exit code 0, with
# no desktop of any kind around it. A build is the only place that can prove the
# no-desktop case, because a build genuinely has no desktop.
say "The two commands the top bar calls, answered here, with no desktop at all"

# Written as a && || list on purpose: under `set -e` (which aq-lib.sh turns on)
# a plain assignment whose command substitution fails kills the script on the
# spot, with no FAIL line and no explanation. This way a non-zero exit is
# CAPTURED and reported, which is the entire point of the check.
AQ_STATUS_OUT="$(HOME=/tmp/aq-capture-probe XDG_RUNTIME_DIR=/tmp/aq-capture-probe/run "${HELPER}" status 2> /dev/null)" \
    && AQ_STATUS_RC=0 || AQ_STATUS_RC=$?
echo "  status said: ${AQ_STATUS_OUT}"
if [ "${AQ_STATUS_RC}" -eq 0 ]; then
    ok "status exits 0 with nothing recording and no session (the bar polls this once a second)"
else
    bad "status exited ${AQ_STATUS_RC} — the bar would draw a broken indicator"
fi
case "${AQ_STATUS_OUT}" in
    '{"recording":false,'*'"elapsed":0}')
        ok "status printed the agreed JSON shape"
        ;;
    *)
        bad "status did not print the agreed JSON — the bar parses this literally"
        ;;
esac

AQ_FOLDER_OUT="$(HOME=/tmp/aq-capture-probe "${HELPER}" folder 2> /dev/null || true)"
echo "  folder said: ${AQ_FOLDER_OUT}"
if [ "${AQ_FOLDER_OUT}" = "/tmp/aq-capture-probe/Screenshots" ] && [ -d "${AQ_FOLDER_OUT}" ]; then
    ok "folder prints the Screenshots path and creates it if it is not there"
else
    bad "folder did not print and create /tmp/aq-capture-probe/Screenshots"
fi
rm -rf /tmp/aq-capture-probe

# ==============================================================================
# 3. The service that makes the folder at login
# ==============================================================================
say "The login-time setup service"
if [ -r "${SETUP_UNIT}" ]; then
    ok "$(basename "${SETUP_UNIT}") is installed"
else
    bad "${SETUP_UNIT} is missing — nobody would ever get a Screenshots folder or a Files pin"
fi
aq_file_has "${SETUP_UNIT}" '^ExecStart=/usr/libexec/aquarius-capture setup' \
    "it runs the helper's setup command"
aq_file_has "${SETUP_UNIT}" '^ConditionUser=!@system' \
    "and not for the login screen's own account"

# ⚠️ SWITCHED ON FROM /usr, NEVER THROUGH /etc. The long reasoning is in
# aq-lib.sh beside aq_unit_is_on_from_usr; the short version is that an update
# merges the machine's /etc and would preserve a deletion forever. This is a
# USER service, so its link is in the user tree and aq_unit_is_on_from_usr
# (which knows only the system tree) cannot be used — the same check, written
# out.
if [ -L "${SETUP_LINK}" ]; then
    echo "  ${SETUP_LINK} -> $(readlink "${SETUP_LINK}")"
    if [ -e "${SETUP_LINK}" ]; then
        ok "the setup service is switched on from /usr, so an update always restores it"
    else
        bad "the 'switched on' link is dangling — it points at nothing"
    fi
else
    bad "${SETUP_LINK} is missing — the service would be installed but never run"
fi
if [ -e "/etc/systemd/user/graphical-session.target.wants/$(basename "${SETUP_UNIT}")" ]; then
    bad "the setup service is ALSO switched on through /etc — see the note in aq-lib.sh"
else
    ok "nothing switches it on through /etc (an update could lose that)"
fi

# ==============================================================================
# 4. The keyboard
# ==============================================================================
# Two halves, and they are easy to confuse.
#
#   labwc's rc.xml   is what actually RUNS the helper. Every shortcut, in both
#                    keyboard styles, ends up here.
#   mac.yaml         turns Command-Shift-3 into the key rc.xml is listening for.
#                    It translates; it never runs anything.
#
# So a missing line in rc.xml is a dead shortcut in both styles, and a missing
# line in mac.yaml is a dead shortcut in Mac style only.
say "The shortcuts in the Aquarius Desktop"
aq_file_has "${RC_XML}" 'aquarius-capture shot screen' \
    "rc.xml: Print Screen takes a picture of a whole monitor"
aq_file_has "${RC_XML}" 'aquarius-capture shot area' \
    "rc.xml: Shift+Print Screen, and Win+Shift+S, pick an area"
aq_file_has "${RC_XML}" 'aquarius-capture shot window' \
    "rc.xml: the window shortcut"
aq_file_has "${RC_XML}" 'aquarius-capture record area' \
    "rc.xml: Win+Alt+R starts recording an area"
aq_file_has "${RC_XML}" 'aquarius-capture record stop' \
    "rc.xml: Win+Alt+Shift+R stops it"

say "The Mac translations"
aq_file_has "${MAC_KEYS}" 'Super-Shift-3: SYSRQ' \
    "mac.yaml: Command-Shift-3 -> Print Screen (whole screen)"
aq_file_has "${MAC_KEYS}" 'Super-Shift-4: Shift-SYSRQ' \
    "mac.yaml: Command-Shift-4 -> Shift+Print Screen (an area)"
aq_file_has "${MAC_KEYS}" 'Super-Shift-5: Super-Shift-SYSRQ' \
    "mac.yaml: Command-Shift-5 -> the window shortcut"
aq_file_has "${MAC_KEYS}" 'Super-Shift-6: Super-Alt-r' \
    "mac.yaml: Command-Shift-6 -> start recording an area"
aq_file_has "${MAC_KEYS}" 'Super-Shift-7: Super-Alt-Shift-r' \
    "mac.yaml: Command-Shift-7 -> stop recording"

# ⚠️ WINDOWS MODE HAS NO TRANSLATIONS, AND THAT IS THE CORRECT ANSWER, NOT AN
# OVERSIGHT. Its keys — Print Screen, Shift+Print Screen, Win+Shift+S,
# Win+Alt+R — are already the real keys rc.xml listens for, so there is nothing
# to translate. And windows.yaml having no rules is load-bearing: the run script
# reads "no rules" as "do not start the remapper at all", which is what keeps
# anything at all from sitting between the keyboard and the computer in Windows
# mode. Adding a rule here for the sake of symmetry would switch the remapper on
# for no benefit. The file documents the keys in a comment instead; this checks
# that documentation is there, so the two never drift.
say "Windows mode: the keys are the real keys, so there is nothing to translate"
aq_file_has "${WINDOWS_KEYS}" 'Win-Alt-R' \
    "windows.yaml documents the Windows-style capture keys"
if grep -Eq '^keymap: \[\]' "${WINDOWS_KEYS}"; then
    ok "windows.yaml still has no rules, so the remapper stays out of the way"
else
    bad "windows.yaml has grown rules — that starts the keyboard remapper in Windows mode. See the note in this step."
fi

# ==============================================================================
# 5. The guide
# ==============================================================================
# Every feature of ours ships a plain-English guide in docs/restart/, and
# FEATURES 017 asked for one. The repository is mounted at /ctx during the
# build, so this reads the real file rather than trusting that somebody wrote
# it. A feature whose guide was never written is a feature nobody can use.
say "The plain-English guide"
if [ -r "${DOC}" ]; then
    ok "docs/restart/screenshots.md exists ($(wc -l < "${DOC}" | tr -d ' ') lines)"
else
    bad "${DOC} is missing — this feature ships with no explanation anywhere"
fi
aq_file_has /ctx/docs/restart/README.md 'screenshots\.md' \
    "and it is listed in the docs index, so a person can find it"

aq_finish "Screenshots and screen recording"
