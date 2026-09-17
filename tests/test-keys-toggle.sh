#!/usr/bin/env bash
# ==============================================================================
# Tests for the two Mac-or-Windows switches, before anything is built
# ==============================================================================
# WHAT THESE SWITCHES ARE
#
# AquariusOS has one Mac-or-Windows choice — Mac-style keyboard shortcuts with
# the window buttons on the left, or the normal Windows ones with the buttons on
# the right — and since 2026-09-16 it has a switch on each desktop:
#
#   GNOME   an add-on of ours in the quick settings menu at the top-right of the
#           screen. Source: system_files/usr/share/gnome-shell/extensions/ .
#   KDE     a page in System Settings called "Mac or Windows".
#           Source: kcm/aquarius-keys/ .
#
# ------------------------------------------------------------------------------
# WHAT THIS FILE CAN AND CANNOT CHECK, SAID HONESTLY
# ------------------------------------------------------------------------------
# It runs on a plain checkout, with no desktop, no GNOME, no KDE and nothing
# built. So it checks the things that are true of the SOURCE and that fail
# silently if they are wrong:
#
#   * metadata.json is real JSON, and the id inside it matches the folder name —
#     if those two disagree, GNOME loads the add-on and then refuses to start it,
#     saying nothing;
#   * the add-on's code has no syntax error — a syntax error means the toggle is
#     simply absent, with the reason buried in the system log;
#   * the add-on cleans up after itself (a disable() that destroys what enable()
#     made). GNOME's own review rules require this, and a leak here happens
#     every time the screen locks;
#   * the KDE page's description is real JSON and says it belongs in Appearance;
#   * neither switch writes the settings file itself — both must run
#     `aq keys`, because that command does four things, not one;
#   * the id of the add-on is in the image's list of switched-on add-ons, or it
#     would be installed and invisible.
#
# ⚠️ IT CANNOT CHECK THAT EITHER SWITCH ACTUALLY WORKS. That needs a running
# GNOME and a running KDE Plasma, which means the bench machine. The build
# itself checks more — build_files/75-aquarius-keys.sh reads both of them back
# out of the finished image — but "it appears and it flips the setting" is a
# bench test and always will be.
# ==============================================================================

set -uo pipefail

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

EXT_UUID="aquarius-keys@stoneharborent.github.io"
EXT_DIR="${REPO}/system_files/usr/share/gnome-shell/extensions/${EXT_UUID}"
KCM_DIR="${REPO}/kcm/aquarius-keys"
OVERRIDE="${REPO}/system_files/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override"

fails=0
ok() { echo "  OK   $*"; }
bad() {
    echo "  FAIL $*" >&2
    fails=$((fails + 1))
}

# has <file> <pattern> "<what it means>"
has() {
    if [ ! -r "$1" ]; then
        bad "$3 — $1 does not exist"
        return
    fi
    if grep -Eq -- "$2" "$1"; then
        ok "$3"
    else
        bad "$3 — /$2/ is not in $1"
    fi
}

echo "== the GNOME toggle =="

if [ ! -d "${EXT_DIR}" ]; then
    bad "${EXT_DIR} does not exist"
else
    ok "the add-on's folder is named after its id"
fi

# ⚠️ THE FOLDER NAME AND THE ID INSIDE THE FILE HAVE TO MATCH EXACTLY.
if python3 - "${EXT_DIR}/metadata.json" "${EXT_UUID}" << 'PY'; then
import json
import sys

with open(sys.argv[1]) as handle:
    meta = json.load(handle)

problems = []
if meta.get("uuid") != sys.argv[2]:
    problems.append(f"uuid is {meta.get('uuid')!r}, expected {sys.argv[2]!r}")
for key in ("name", "description", "shell-version"):
    if not meta.get(key):
        problems.append(f"{key} is missing or empty")
if not all(str(v).isdigit() for v in meta.get("shell-version", [])):
    problems.append("shell-version must be a list of GNOME Shell numbers")

for problem in problems:
    print(f"       {problem}")
sys.exit(1 if problems else 0)
PY
    ok "metadata.json is valid JSON and its id matches its folder"
else
    bad "metadata.json is wrong — GNOME would refuse to start the add-on"
fi

# Is the code even parseable? gjs is what GNOME runs it with; node parses the
# same language and is on GitHub's runners. Either will do, and if neither is
# here the test says so out loud rather than quietly passing.
EXT_JS="${EXT_DIR}/extension.js"
if command -v node > /dev/null 2>&1; then
    if node --check "${EXT_JS}" 2>&1; then
        ok "extension.js has no syntax error (checked with node)"
    else
        bad "extension.js has a syntax error — the toggle would simply not appear"
    fi
elif command -v gjs > /dev/null 2>&1; then
    # -m means "read it as a module", which is what GNOME does. The file only
    # defines things, so reading it does not start anything.
    if gjs -m "${EXT_JS}" > /dev/null 2>&1; then
        ok "extension.js has no syntax error (checked with gjs)"
    else
        bad "extension.js has a syntax error — the toggle would simply not appear"
    fi
else
    bad "neither node nor gjs is here, so extension.js was NOT syntax-checked"
fi

has "${EXT_JS}" "'/usr/bin/aq'" \
    "the toggle changes the setting by running /usr/bin/aq, not by writing the file"
has "${EXT_JS}" "keys.conf" \
    "the toggle reads the same settings file aq reads"
has "${EXT_JS}" "input-keyboard-symbolic" \
    "it uses an icon every GNOME already has, rather than new artwork"

# ⚠️ AN ADD-ON THAT DOES NOT CLEAN UP LEAKS EVERY TIME THE SCREEN LOCKS, because
# GNOME switches add-ons off when it locks and on again when it unlocks.
has "${EXT_JS}" "disable\(\)" "it has a disable() — GNOME requires one"
has "${EXT_JS}" "_indicator\?\.destroy\(\)" "disable() destroys the toggle it made"
has "${EXT_JS}" "_monitor\?\.cancel\(\)" "it stops watching the settings file when it is switched off"
has "${EXT_JS}" "_cancellable\?\.cancel\(\)" "it cancels any command still running"

# Installed but not switched on is the same as not installed, and nothing says so.
has "${OVERRIDE}" "enabled-extensions=.*${EXT_UUID}" \
    "the add-on is in the image's list of switched-on add-ons"

echo
echo "== the KDE System Settings page =="

if python3 - "${KCM_DIR}/kcm_aquariuskeys.json" << 'PY'; then
import json
import sys

with open(sys.argv[1]) as handle:
    meta = json.load(handle)

problems = []
plugin = meta.get("KPlugin", {})
if plugin.get("Name") != "Mac or Windows":
    problems.append(f"the page's name is {plugin.get('Name')!r}, expected 'Mac or Windows'")
if not plugin.get("Description"):
    problems.append("the page has no one-line description")
if not plugin.get("Icon"):
    problems.append("the page has no icon")

# Where it appears. "appearance" is the id of System Settings' own
# "Appearance & Style" category — checked against the category files that
# plasma-systemsettings installs.
if meta.get("X-KDE-System-Settings-Parent-Category") != "appearance":
    problems.append("the page is not filed under Appearance & Style")

# It has to be findable by the words a person would actually type.
keywords = meta.get("X-KDE-Keywords", "").lower()
for word in ("mac", "windows", "keyboard", "window buttons"):
    if word not in keywords:
        problems.append(f"searching for {word!r} would not find the page")

for problem in problems:
    print(f"       {problem}")
sys.exit(1 if problems else 0)
PY
    ok "the page's description is valid, filed under Appearance, and findable"
else
    bad "kcm_aquariuskeys.json is wrong — the page would be missing or misplaced"
fi

has "${KCM_DIR}/kcm_aquariuskeys.cpp" '/usr/bin/aq' \
    "the page changes the setting by running /usr/bin/aq, not by writing the file"
has "${KCM_DIR}/kcm_aquariuskeys.cpp" 'keys\.conf' \
    "the page reads the same settings file aq reads"

# ⚠️ AQUARIUSOS SHIPS BOTH DESKTOPS. A menu entry for a KDE-only settings page
# would be a dead icon in GNOME's app grid, because both desktops read
# /usr/share/applications/.
has "${KCM_DIR}/CMakeLists.txt" 'DISABLE_DESKTOP_FILE_GENERATION' \
    "the page is built with no menu entry, so it cannot appear in GNOME"

# KDE's build macro bakes whatever is in the ui/ folder into the plugin, and
# only that folder. A page whose QML lives anywhere else opens empty.
if [ -r "${KCM_DIR}/ui/main.qml" ]; then
    ok "the page's interface is in the ui/ folder, where KDE's build macro looks"
else
    bad "${KCM_DIR}/ui/main.qml is missing — the page would open empty"
fi

echo
if [ "${fails}" -ne 0 ]; then
    echo "${fails} check(s) failed."
    exit 1
fi
echo "All Mac-or-Windows switch checks passed."
