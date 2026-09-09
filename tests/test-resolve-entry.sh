#!/usr/bin/bash
# =============================================================================
# test-resolve-entry.sh — Resolve's app-menu entry is a real one
# =============================================================================
# WHAT THIS PROVES, AND THE FAULT IT COMES FROM
#
# ⚠️ THE BENCH FINDING OF 8 SEPTEMBER 2026. Royce installed DaVinci Resolve and
# reported: **"No Resolve icon appeared after install. After quitting, Resolve
# cannot be reopened and is not in the app search."**
#
# The exported app-menu entry was distrobox's raw output, verbatim:
#
#     Name=DaVinci Resolve (on aquarius-resolve)
#     StartupWMClass=/usr/share/applications/com.blackmagicdesign.resolve.desktop
#
# — plus no GenericName and no Categories. Three separate consequences:
#
#   * the app menu showed the container's name, which nobody using this computer
#     should ever have to know about;
#   * `StartupWMClass` was a FILE PATH. That key exists to answer one question —
#     "when this window appears, which app-menu entry does it belong to?" — and
#     the dock matches on it. Resolve's window calls itself `resolve`. A path
#     can never match a window, so the dock could never join the two, which is
#     why no icon appeared;
#   * with no Categories the entry has no shelf in the menu.
#
# The installer's repair step fixed only `Exec` and `MimeType`, and **nothing
# anywhere ever read the finished entry back**. So this test does: it writes a
# real distrobox-export file into a temporary folder, runs the repair against
# it, and checks **every key**, one at a time.
#
# ⚠️ AND THE BENCH FINDING OF 9 SEPTEMBER 2026, WHICH IS THE WORST OF THE LOT.
# Clicking the DaVinci Resolve icon in GNOME did **nothing at all** — no window,
# no error on screen. GNOME's log said exactly why:
#
#     Failed to launch "DaVinci Resolve (on aquarius-resolve)":
#     Failed to change to directory "/opt/resolve/" (No such file or directory)
#
# The entry carried `Path=/opt/resolve/`, copied out of the container.
# `Path=` is the folder the desktop steps into BEFORE it runs anything, and
# /opt/resolve exists only inside the container. So the desktop refused to start
# the app at all. Running the same Exec line by hand in a terminal worked, which
# is why nobody caught it sooner — and it is almost certainly the real cause of
# the 8 September "after quitting, Resolve cannot be reopened" as well.
#
# It also checks the two pieces of noise beside it:
#
#   * distrobox's own "Terminal entering Aquarius-resolve" entry, which is a way
#     into the container and not an app anybody launches. ⚠️ Hiding it is not as
#     simple as adding `NoDisplay=true`: distrobox writes `NoDisplay=true` near
#     the top of its file **and** `NoDisplay=false` further down, and in a
#     .desktop file the later key wins. That is exactly why Royce could see it.
#   * a stale `davincibox.desktop` from the Line 1 container, which is the same
#     shape of file for a container that no longer exists.
#
# HOW TO RUN IT
#   ./tests/test-resolve-entry.sh
#   ./tests/test-resolve-entry.sh /usr/libexec/aquarius-resolve-entry
#
# It needs python3 and a writable temporary folder. No Resolve, no container, no
# screen — which is why it can run before the image is even built.
# =============================================================================

set -uo pipefail

PROG="${1:-}"
if [ -z "${PROG}" ]; then
    PROG="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/libexec/aquarius-resolve-entry"
fi

if [ ! -r "${PROG}" ]; then
    echo "FAIL ${PROG} is not there — nothing to test." >&2
    exit 1
fi

fails=0
ok() { echo "  OK   $*"; }
bad() {
    echo "  FAIL $*" >&2
    fails=$((fails + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

run_entry() { python3 "${PROG}" "$@"; }

# key_is <file> <key> <wanted value> ["<what it is for>"]
#
# ⚠️ awk AND NOT grep. One of the keys checked here is `Name[en_US]`, and those
# square brackets are a character class to grep — `^Name[en_US]=` matches
# "NameS=" and never the key we asked about. awk's index() compares plain text.
key_is() {
    local file="$1" key="$2" want="$3" what="${4:-}" got
    got="$(awk -v k="${key}=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' \
        "${file}" 2> /dev/null || true)"
    if [ "${got}" = "${want}" ]; then
        ok "${key}=${want}${what:+ — ${what}}"
    else
        bad "${key} is '${got}', should be '${want}'${what:+ — ${what}}"
    fi
}

echo "== Resolve's app-menu entry is a real one =="
echo "   program under test: ${PROG}"

# -----------------------------------------------------------------------------
# The entry distrobox really wrote on the bench, byte for byte
# -----------------------------------------------------------------------------
# ⚠️ THIS FIXTURE IS A COPY OF A REAL FILE, from
# ~/.local/share/applications/aquarius-resolve-com.blackmagicdesign.resolve.desktop
# on the bench PC on 2026-09-08, with the Exec line as the installer leaves it
# (already pointed at our launcher). Do not "tidy" it: its oddities — the double
# space in the Exec line, the localised `Name[en_US]`, the StartupWMClass that is
# a path — are the ones the repair has to survive.
MAIN="${WORK}/aquarius-resolve-com.blackmagicdesign.resolve.desktop"
cat > "${MAIN}" <<'FIXTURE'
[Desktop Entry]
Version=1.0
Type=Application
Name=DaVinci Resolve (on aquarius-resolve)
GenericName=DaVinci Resolve (on aquarius-resolve)
Comment=Revolutionary new tools for editing, visual effects, color correction and professional audio post production, all in a single application!
Path=/opt/resolve/
Exec=/usr/libexec/aquarius-resolve-launch /opt/resolve/bin/resolve  %u
Terminal=false
MimeType=application/x-resolveproj;application/x-davinci-resolve-project;video/mp4;video/quicktime;
Icon=/home/tester/.local/share/icons/DV_Resolve.png
StartupNotify=true
Name[en_US]=DaVinci Resolve (on aquarius-resolve)
StartupWMClass=/usr/share/applications/com.blackmagicdesign.resolve.desktop
FIXTURE

# The icon the entry names has to exist for the "missing icon" note not to fire.
mkdir -p "${WORK}/icons"
: > "${WORK}/icons/DV_Resolve.png"
sed -i "s#Icon=.*#Icon=${WORK}/icons/DV_Resolve.png#" "${MAIN}"

echo ""
echo "-- the entry that starts Resolve --"

# ⚠️ BEFORE THE REPAIR: `check` has to already be unhappy about the working
# folder. THE BENCH FAULT OF 9 SEPTEMBER 2026 — clicking the DaVinci Resolve
# icon in GNOME did nothing at all, and GNOME's log said why: "Failed to change
# to directory /opt/resolve/ (No such file or directory)". `Path=` is the folder
# the desktop steps into BEFORE running the program, /opt/resolve is inside the
# container and not on this computer, so the desktop refused to start the app at
# all. If `check` cannot see that, nothing can.
if run_entry check "${MAIN}" > "${WORK}/check-before.txt" 2>&1; then
    bad "'check' passed an entry with Path=/opt/resolve/ — the very thing that made clicking the icon do nothing"
else
    if grep -q 'Path is' "${WORK}/check-before.txt"; then
        ok "'check' names the unreachable Path before the repair"
    else
        bad "'check' failed but never mentioned Path:"
        sed 's/^/       /' "${WORK}/check-before.txt" >&2
    fi
fi

if run_entry repair "${MAIN}" | sed 's/^/     /'; then
    ok "the repair ran"
else
    bad "the repair exited non-zero"
fi

# ⚠️ EVERY KEY, ONE AT A TIME. The point of this test is that nothing was ever
# read back before, so nothing here is checked in a bundle.
key_is "${MAIN}" Name "DaVinci Resolve" \
    "what a person calls it — no container name in the app menu"
key_is "${MAIN}" "Name[en_US]" "DaVinci Resolve" \
    "the localised copy too, or an English desktop shows the old one"
key_is "${MAIN}" GenericName "Video Editor" \
    "the line the menu shows underneath the name"
key_is "${MAIN}" StartupWMClass "resolve" \
    "⚠️ how the dock joins Resolve's window to this entry. THE ICON FAULT."
key_is "${MAIN}" Categories "AudioVideo;Video;" \
    "which shelf of the app menu it sits on"
key_is "${MAIN}" Type "Application"
key_is "${MAIN}" Terminal "false" \
    "it is not a terminal program"
key_is "${MAIN}" StartupNotify "true" \
    "so the pointer says something is starting"

# What must NOT have changed. The installer owns these two lines and this
# program must keep its hands off them, or two programs own one line.
if grep -q '^Exec=/usr/libexec/aquarius-resolve-launch /opt/resolve/bin/resolve  %u$' "${MAIN}"; then
    ok "Exec is untouched, including its %u — 'Open With' still works"
else
    bad "Exec was changed. It is now: $(grep -m1 '^Exec=' "${MAIN}")"
fi
if grep -q '^MimeType=application/x-resolveproj;' "${MAIN}"; then
    ok "MimeType is untouched — the installer owns it"
else
    bad "MimeType was changed"
fi
if grep -q '^Comment=Revolutionary new tools' "${MAIN}"; then
    ok "Blackmagic's own description is left alone"
else
    bad "Comment was changed — that text is Blackmagic's"
fi

# ⚠️ THE ICON IS BLACKMAGIC'S. Royce's decision, 2026-09-08 (FEATURES 008 item
# 13): brand marks stay theirs, the same as Firefox and Steam. The repair must
# never replace it.
if grep -q "^Icon=${WORK}/icons/DV_Resolve.png$" "${MAIN}"; then
    ok "the icon is still Blackmagic's own — Royce's call, never replaced"
else
    bad "the icon was changed. It is now: $(grep -m1 '^Icon=' "${MAIN}")"
fi

if grep -q '^NoDisplay=true' "${MAIN}"; then
    bad "the entry that STARTS Resolve was hidden — there would be no way to open it"
else
    ok "it is not hidden, because it is the one that opens Resolve"
fi

# ⚠️ THE WORKING FOLDER — THE BENCH FAULT OF 9 SEPTEMBER 2026. `Path=` is the
# folder the desktop steps into before it runs Exec. Blackmagic's entries name
# /opt/resolve/, which lives inside the container and has never been on this
# computer, so GNOME could not step into it and refused to start the entry at
# all: clicking the DaVinci Resolve icon did nothing whatsoever. The folder is
# not lost — aquarius-resolve-launch steps into it INSIDE the container, where
# it really is.
if grep -q '^Path=' "${MAIN}"; then
    bad "it kept $(grep -m1 '^Path=' "${MAIN}") — the desktop cannot step into that folder, so clicking the icon does nothing"
else
    ok "the unreachable working folder is gone — THE 'CLICKING THE ICON DOES NOTHING' FAULT"
fi

# It has to be a valid desktop file afterwards. If the machine running this has
# the freedesktop tool, ask it; if not, say so honestly rather than claim a
# check that did not run.
if command -v desktop-file-validate > /dev/null 2>&1; then
    if desktop-file-validate "${MAIN}" > "${WORK}/validate.txt" 2>&1; then
        ok "desktop-file-validate is happy with the repaired file"
    else
        # Warnings about unregistered categories or a missing trailing semicolon
        # in somebody else's key are not our business; errors are.
        if grep -q ': error' "${WORK}/validate.txt"; then
            bad "desktop-file-validate found errors:"
            sed 's/^/       /' "${WORK}/validate.txt" >&2
        else
            ok "desktop-file-validate found only warnings (none of them ours)"
            sed 's/^/       /' "${WORK}/validate.txt"
        fi
    fi
else
    echo "  note   desktop-file-validate is not on this machine, so the file was"
    echo "         not validated here. The build runs this again inside the image,"
    echo "         where it is."
fi

# And the program's own verdict on its own work.
if run_entry check "${MAIN}" | sed 's/^/     /'; then
    ok "'aquarius-resolve-entry check' agrees the entry is complete"
else
    bad "'aquarius-resolve-entry check' says the entry is still not right"
fi

# Running it twice must change nothing. An install and an update both run it.
before="$(cat "${MAIN}")"
run_entry repair "${MAIN}" > /dev/null
if [ "${before}" = "$(cat "${MAIN}")" ]; then
    ok "repairing an already-repaired entry changes nothing"
else
    bad "a second repair changed the file — an update would keep rewriting it"
fi

# -----------------------------------------------------------------------------
# The other exported entries — the RAW Player and friends
# -----------------------------------------------------------------------------
echo ""
echo "-- the other things Blackmagic install beside Resolve --"
OTHER="${WORK}/aquarius-resolve-com.blackmagicdesign.resolve-Panels.desktop"
cat > "${OTHER}" <<'FIXTURE'
[Desktop Entry]
Version=1.0
Type=Application
Name=DaVinci Control Panels Setup (on aquarius-resolve)
GenericName=DaVinci Control Panels Setup (on aquarius-resolve)
Path=/opt/resolve/
Exec=/usr/libexec/aquarius-resolve-launch "/opt/resolve/DaVinci Control Panels Setup/DaVinci Control Panels Setup"
Terminal=false
Icon=/home/tester/.local/share/icons/DV_Panels.png
Name[en_US]=DaVinci Control Panels Setup (on aquarius-resolve)
StartupWMClass=/usr/share/applications/com.blackmagicdesign.resolve-Panels.desktop
FIXTURE

run_entry repair "${OTHER}" | sed 's/^/     /'
key_is "${OTHER}" Name "DaVinci Control Panels Setup" \
    "the container's name is gone from this one too"
# ⚠️ NOT GIVEN A GUESSED VALUE. We do not know what that window calls itself, and
# a wrong StartupWMClass can never match anything, while no key at all lets the
# desktop fall back to matching the window itself.
if grep -q '^StartupWMClass=' "${OTHER}"; then
    bad "it kept a StartupWMClass that is a file path — it can never match a window"
else
    ok "its file-path StartupWMClass was removed rather than guessed at"
fi
if grep -q '^GenericName=Video Editor' "${OTHER}"; then
    bad "a control-panel setup tool was labelled 'Video Editor'"
else
    ok "it was not mistaken for Resolve itself"
fi
# ⚠️ AND ITS WORKING FOLDER TOO. distrobox copied `Path=/opt/resolve/` onto
# every one of these entries, not just Resolve's, so every one of them was
# equally unclickable.
if grep -q '^Path=' "${OTHER}"; then
    bad "it kept $(grep -m1 '^Path=' "${OTHER}") — the desktop cannot step into that folder either"
else
    ok "its unreachable working folder is gone as well"
fi

# -----------------------------------------------------------------------------
# ⚠️ AND A WORKING FOLDER THAT REALLY IS THERE IS LEFT ALONE
# -----------------------------------------------------------------------------
# The rule is "a folder this computer does not have", not "any Path at all". A
# Path naming a real folder is somebody's deliberate setting — the desktop can
# step into it, so it breaks nothing — and this program has no business
# deleting it.
REAL="${WORK}/aquarius-resolve-com.blackmagicdesign.rawplayer.desktop"
cat > "${REAL}" <<FIXTURE
[Desktop Entry]
Version=1.0
Type=Application
Name=Blackmagic RAW Player (on aquarius-resolve)
Path=${WORK}
Exec=/usr/libexec/aquarius-resolve-launch /opt/resolve/BlackmagicRAWPlayer/BlackmagicRAWPlayer %f
Terminal=false
Icon=${WORK}/icons/DV_Resolve.png
FIXTURE

run_entry repair "${REAL}" | sed 's/^/     /'
key_is "${REAL}" Path "${WORK}" \
    "a folder that really is on this computer is not touched"

# -----------------------------------------------------------------------------
# ⚠️ The distrobox "Terminal entering …" entries, and NoDisplay written twice
# -----------------------------------------------------------------------------
echo ""
echo "-- the container's own entries, which are not apps --"
for name in aquarius-resolve davincibox; do
    NOISE="${WORK}/${name}.desktop"
    # This is distrobox's real output, and the two NoDisplay lines are the point.
    cat > "${NOISE}" <<FIXTURE
[Desktop Entry]
NoDisplay=true
Name=${name}
GenericName=Terminal entering ${name}
Comment=Terminal entering ${name}
Categories=Distrobox;System;Utility
Exec=/usr/bin/distrobox enter  ${name}
Icon=/home/tester/.local/share/icons/distrobox/rocky.png
Keywords=distrobox;
NoDisplay=false
Terminal=true
TryExec=/usr/bin/distrobox
Type=Application
Actions=Remove;

[Desktop Action Remove]
Name=Remove ${name} from system
Exec=/usr/bin/distrobox rm  ${name}
FIXTURE

    run_entry hide "${NOISE}" | sed 's/^/     /'

    n="$(grep -c '^NoDisplay=' "${NOISE}" || true)"
    if [ "${n}" = "1" ]; then
        ok "${name}.desktop has exactly one NoDisplay line"
    else
        bad "${name}.desktop has ${n} NoDisplay lines — the later one wins, which is the bug"
    fi
    key_is "${NOISE}" NoDisplay "true" \
        "so '${name}' does not appear in the app menu"

    # The [Desktop Action Remove] group must survive: it is how somebody removes
    # the container from a graphical menu, and it is not ours to delete.
    if grep -q '^\[Desktop Action Remove\]$' "${NOISE}"; then
        ok "its 'Remove' action is still there"
    else
        bad "the [Desktop Action Remove] group was destroyed"
    fi
done

echo ""
if [ "${fails}" -ne 0 ]; then
    echo "::error::Resolve's app-menu entry is not right (${fails} check(s) failed)."
    echo "The dock would show no Resolve icon and the app search would not find it."
    echo "See docs/restart/resolve.md."
    exit 1
fi
echo "All Resolve app-menu entry checks passed."
