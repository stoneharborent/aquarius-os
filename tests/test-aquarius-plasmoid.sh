#!/usr/bin/env bash
# ==============================================================================
# Cheap checks on the AquariusOS desktop widget, before the image is built
# ==============================================================================
# Building the OS takes the best part of an hour. These checks take a second, so
# they run on every pull request instead — the same reasoning as the app launcher
# tests next door.
#
# WHAT THIS CAN CHECK
#   * metadata.json is valid JSON, and says what it needs to say
#   * every file the widget loads by name actually exists
#   * the QML files' brackets balance
#   * nothing in the widget points at a path on somebody's laptop
#   * the desktop layout script is still valid JavaScript
#
# WHAT THIS CANNOT CHECK, AND WHY
#   Whether the QML is CORRECT. The proper tool for that is `qmllint`, which
#   ships with Qt and needs Qt, Kirigami and the Plasma QML modules installed to
#   resolve the imports. None of that exists on the macOS machine this repo is
#   written on, and installing a whole Qt on a CI runner to lint nine files is a
#   poor trade. So: brace balance here, real behaviour on real hardware. The
#   bench checklist is in docs/clock-notifications-widget.md.
#
# Run it by hand with:  ./tests/test-aquarius-plasmoid.sh
# ==============================================================================

set -euo pipefail

# Work from the repo root no matter where this was started from.
AQ_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${AQ_REPO_ROOT}"

AQ_PLASMOID="system_files/usr/share/plasma/plasmoids/com.aquariusos.clock"
AQ_LAYOUT="system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"

aq_failures=0

fail() {
    echo "  FAIL $1"
    shift
    for aq_line in "$@"; do echo "       $aq_line"; done
    aq_failures=$((aq_failures + 1))
}

pass() {
    echo "  OK   $1"
}

# ------------------------------------------------------------------------------
echo ""
echo "=== 1. metadata.json ==="
# ------------------------------------------------------------------------------
# If this file is not valid JSON, Plasma does not see a widget at all — it does
# not warn, the widget simply is not in the list. And the Id inside it has to
# match the folder name, because the folder name is what the layout script asks
# for by hand.

if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${AQ_PLASMOID}/metadata.json" 2>/dev/null; then
    pass "metadata.json is valid JSON"
else
    fail "metadata.json is not valid JSON." \
         "Plasma will not list the widget at all. Run:" \
         "  python3 -m json.tool ${AQ_PLASMOID}/metadata.json"
fi

aq_declared_id="$(python3 -c \
    "import json,sys; print(json.load(open(sys.argv[1]))['KPlugin'].get('Id',''))" \
    "${AQ_PLASMOID}/metadata.json" 2>/dev/null || true)"

if [ "${aq_declared_id}" = "com.aquariusos.clock" ]; then
    pass "KPlugin.Id matches the folder name"
else
    fail "KPlugin.Id is '${aq_declared_id}', but the folder is com.aquariusos.clock." \
         "The layout script asks for the widget by this id; they have to agree."
fi

# ------------------------------------------------------------------------------
echo ""
echo "=== 2. every file the widget loads exists ==="
# ------------------------------------------------------------------------------
# main.qml pulls four of these in through a Loader, by filename. A Loader that
# cannot find its file does not fail at startup — it fails at the moment the user
# clicks, which is the worst possible time to find out.

for aq_file in \
    main.qml \
    CompactClock.qml \
    AlignedClock.qml \
    TickingClock.qml \
    NotificationsSource.qml \
    NotificationsPanel.qml \
    NotificationRow.qml \
    PanelUnavailable.qml
do
    if [ -f "${AQ_PLASMOID}/contents/ui/${aq_file}" ]; then
        pass "${aq_file}"
    else
        fail "${AQ_PLASMOID}/contents/ui/${aq_file} is missing."
    fi
done

# ------------------------------------------------------------------------------
echo ""
echo "=== 3. the QML brackets balance ==="
# ------------------------------------------------------------------------------
# Not a substitute for qmllint — see the note at the top of this file. It is a
# substitute for nothing at all, which is what we would otherwise have. It counts
# { } ( ) and [ ] after throwing away comments and the insides of strings, so a
# brace in a comment or a message cannot confuse it.

if python3 - "${AQ_PLASMOID}/contents/ui" <<'PYTHON'
import pathlib
import sys

ui = pathlib.Path(sys.argv[1])
bad = 0

def strip(text):
    """Remove comments and string contents, keeping everything else in place."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                i += 1
            i += 2
        elif c in ('"', "'", '`'):
            quote = c
            i += 1
            while i < n and text[i] != quote:
                if text[i] == '\\':
                    i += 1
                i += 1
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

pairs = {'}': '{', ')': '(', ']': '['}
openers = set(pairs.values())

for path in sorted(ui.glob('*.qml')):
    code = strip(path.read_text(encoding='utf-8'))
    stack = []
    problem = None
    for ch in code:
        if ch in openers:
            stack.append(ch)
        elif ch in pairs:
            if not stack or stack[-1] != pairs[ch]:
                problem = "an unexpected '%s'" % ch
                break
            stack.pop()
    if problem is None and stack:
        problem = "%d bracket(s) never closed" % len(stack)
    if problem:
        print("  FAIL %s: %s" % (path.name, problem))
        bad += 1
    else:
        print("  OK   %s" % path.name)

sys.exit(1 if bad else 0)
PYTHON
then
    : # every file balanced; the per-file OK lines were printed above
else
    fail "at least one QML file has unbalanced brackets (listed above)."
fi

# ------------------------------------------------------------------------------
echo ""
echo "=== 4. nothing points at somebody's laptop ==="
# ------------------------------------------------------------------------------
# A path like /Users/... or /home/someone/... in a shipped file means the widget
# works on one machine and nowhere else. Paths under /usr are fine and expected —
# that is where the OS actually keeps things, and the layout script legitimately
# points the wallpaper at file:///usr/share/wallpapers/.

if grep -rnE '(/Users/|/home/[a-z]|/private/tmp/|/var/folders/)' \
        "${AQ_PLASMOID}" "${AQ_LAYOUT}" 2>/dev/null; then
    fail "a file above contains an absolute path to somebody's own machine." \
         "Shipped files may only refer to paths that exist on every install."
else
    pass "no machine-specific paths"
fi

# ------------------------------------------------------------------------------
echo ""
echo "=== 5. the desktop layout script is valid JavaScript ==="
# ------------------------------------------------------------------------------
# KDE runs this file through a JavaScript engine at first login. A typo in it
# means a desktop with no panels at all and no error anybody will ever see.
# `node --check` parses without running, which is exactly what we want: the file
# calls KDE functions that do not exist outside Plasma, so running it is not an
# option.

if command -v node > /dev/null 2>&1; then
    if node --check "${AQ_LAYOUT}" > /dev/null 2>&1; then
        pass "the layout script parses"
    else
        fail "the layout script is not valid JavaScript." \
             "Run:  node --check ${AQ_LAYOUT}"
    fi
else
    echo "  SKIP node is not installed; cannot parse-check the layout script."
fi

# The widget has to actually be placed, not merely shipped.
if grep -q 'addWidget("com.aquariusos.clock")' "${AQ_LAYOUT}"; then
    pass "the layout script places com.aquariusos.clock"
else
    fail "the layout script does not add com.aquariusos.clock to the top bar."
fi

# And the widget it replaced should no longer be ADDED, or we would have two
# clocks. (The name still appears in a comment there, explaining what changed —
# hence matching the addWidget call rather than the bare name.)
if grep -q 'addWidget("org.kde.plasma.digitalclock")' "${AQ_LAYOUT}"; then
    fail "the layout script still adds KDE's digital clock." \
         "com.aquariusos.clock replaced it; having both means two clocks."
else
    pass "KDE's digital clock is no longer added"
fi

# ------------------------------------------------------------------------------
echo ""
if [ "${aq_failures}" -ne 0 ]; then
    echo "::error::${aq_failures} check(s) failed."
    exit 1
fi
echo "All widget checks passed."
