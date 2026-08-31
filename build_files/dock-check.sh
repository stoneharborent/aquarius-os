#!/usr/bin/bash
# ==============================================================================
# Check that the Aquarius Dock will actually load before we ship the image
# ==============================================================================
# WHAT THIS IS GUARDING
#
# The dock in AquariusOS is our own widget:
#     /usr/share/plasma/plasmoids/com.aquariusos.dock/
#
# It is KDE's icons-only task manager, copied, with three things added that the
# design asks for and KDE has no setting for — the hover lift, the dot under a
# running app, and the dashed "+" tile. The full story is in docs/aquarius-dock.md
# and in FORK-NOTES.md inside the widget's own folder.
#
# Copying KDE's code has one specific danger, and this script exists for it.
#
# THE DANGER: A WIDGET THAT VANISHES INSTEAD OF COMPLAINING
#
# A Plasma widget is a folder of QML files. QML files start with `import` lines
# naming the pieces of KDE they need. Our copied files import twenty-odd of them
# — the window list, the volume control, the media-player bridge, and so on.
#
# Those pieces come from Bazzite, not from us. When Bazzite moves to a newer
# Plasma, any one of them can be renamed, merged into something else, or dropped.
# When that happens the widget does not show an error. Plasma simply cannot build
# it, and THE DOCK IS NOT THERE when the machine boots. No dock, no message, and
# nothing in the build log to explain it — because the build succeeded. The image
# was fine. The widget was fine. The thing it leans on had moved.
#
# That failure would land on Royce, on hardware, after a twenty-minute build and
# a reinstall. So we check for it here instead, where it costs seconds.
#
# WHAT IT ACTUALLY CHECKS
#
#   1. The widget folder is in the image at all, with the two files Plasma
#      insists on: metadata.json, and contents/ui/main.qml.
#
#   2. metadata.json is valid JSON and its Id is exactly "com.aquariusos.dock".
#      That Id is the name the layout script asks for by hand when it builds the
#      dock. If the two ever drift apart the dock is empty, so they are compared
#      here rather than trusted.
#
#   3. Every `import` line in the widget resolves to something installed. The
#      list is not typed out below — it is read out of the widget's own files
#      every build. Add an import to the QML and this check covers it the same
#      day, with nobody having to remember to update a list.
#
#   4. Nothing in the widget imports `plasma.applet.*`. That one deserves its own
#      check: it is how KDE's own copy of this code reaches its C++ half, it only
#      works for a widget compiled into Plasma, and it silently does nothing for
#      a widget shipped as a folder like ours. If it ever reappears — most likely
#      by someone pasting fresh code in from upstream — the dock loses its right-
#      click menu and its layout maths on the machine, not here. FORK-NOTES.md
#      explains what we put in its place.
#
# WHAT IT DELIBERATELY DOES NOT CHECK
#
# Whether the QML is CORRECT. Nothing here runs Plasma, so a typo inside a file
# still gets through. Checking that needs `qmllint` against the real Plasma, and
# the honest place to catch it is the bench checklist at the bottom of
# docs/aquarius-dock.md. This script only answers "are the pieces it needs here",
# which is the failure that actually happens on a Bazzite rebase.
#
# WHERE THIS IS CALLED FROM
#
#   build_files/build.sh   (one line, near the end)
#
# HOW TO RUN IT BY HAND, inside a built image
#
#   /ctx/dock-check.sh
# ==============================================================================

set -euo pipefail

PACKAGE_DIR="/usr/share/plasma/plasmoids/com.aquariusos.dock"
EXPECTED_ID="com.aquariusos.dock"

say() {
    echo "dock-check: $*"
}

die() {
    echo "" >&2
    echo "==============================================================" >&2
    echo "BUILD STOPPED: the Aquarius Dock would not load." >&2
    echo "==============================================================" >&2
    for line in "$@"; do
        echo "$line" >&2
    done
    echo "" >&2
    echo "Background: docs/aquarius-dock.md, and FORK-NOTES.md inside" >&2
    echo "${PACKAGE_DIR}/" >&2
    echo "" >&2
    exit 1
}

# ------------------------------------------------------------------------------
# 1. Is the widget in the image, with the files Plasma requires?
# ------------------------------------------------------------------------------
[ -d "$PACKAGE_DIR" ] || die \
    "The dock widget folder is missing from the image:" \
    "    ${PACKAGE_DIR}" \
    "" \
    "It should have been copied in by the Containerfile's 'COPY system_files /'." \
    "Check that the folder still exists in the repo under" \
    "    system_files/usr/share/plasma/plasmoids/com.aquariusos.dock/"

for required in "metadata.json" "contents/ui/main.qml"; do
    [ -f "${PACKAGE_DIR}/${required}" ] || die \
        "The dock widget is missing a file Plasma will not start without:" \
        "    ${PACKAGE_DIR}/${required}" \
        "" \
        "Plasma needs both metadata.json (which names the widget) and" \
        "contents/ui/main.qml (which draws it). Without either one the dock" \
        "does not appear and Plasma says nothing about why."
done

say "widget folder and required files are present."

# ------------------------------------------------------------------------------
# 2. Does metadata.json parse, and does its Id match what the layout asks for?
# ------------------------------------------------------------------------------
python3 -c "import json,sys; json.load(open(sys.argv[1]))" \
    "${PACKAGE_DIR}/metadata.json" 2>/dev/null || die \
    "The dock's metadata.json is not valid JSON:" \
    "    ${PACKAGE_DIR}/metadata.json" \
    "" \
    "Plasma reads this file to find out the widget exists. If it cannot be" \
    "read, the widget is invisible to Plasma — it will not even show up in" \
    "the 'Add Widgets' list. A stray comma is the usual cause."

ACTUAL_ID="$(python3 -c \
    "import json,sys; print(json.load(open(sys.argv[1]))['KPlugin']['Id'])" \
    "${PACKAGE_DIR}/metadata.json")"

[ "$ACTUAL_ID" = "$EXPECTED_ID" ] || die \
    "The dock widget's Id is not what the desktop layout asks for." \
    "" \
    "    metadata.json says:  ${ACTUAL_ID}" \
    "    the layout wants:    ${EXPECTED_ID}" \
    "" \
    "The layout script adds the dock by name, in this line:" \
    "    system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/" \
    "      contents/layouts/org.kde.plasma.desktop-layout.js" \
    "        var tasks = dock.addWidget(\"${EXPECTED_ID}\");" \
    "" \
    "If the two disagree, a new machine boots with an empty dock panel."

say "metadata.json parses, Id is ${ACTUAL_ID}."

# ------------------------------------------------------------------------------
# 3. Nobody has pasted the compiled-only import back in
# ------------------------------------------------------------------------------
# Comments are stripped before looking. Several files EXPLAIN this import at
# length — that is the whole point of the notes — and the check must not trip
# over the explanation of the thing it is checking for. A real import line never
# contains "//", so stripping comments cannot hide one.
OFFENDERS=""
while IFS= read -r qml_file; do
    if sed 's://.*::' "$qml_file" | grep -q "plasma\.applet\."; then
        OFFENDERS="${OFFENDERS}    ${qml_file}
"
    fi
done <<EOF
$(find "${PACKAGE_DIR}/contents" -type f \( -name '*.qml' -o -name '*.js' \))
EOF

if [ -n "$OFFENDERS" ]; then
    die \
        "The dock's QML imports 'plasma.applet.*', which cannot work here." \
        "" \
        "Found in:" \
        "${OFFENDERS}" \
        "" \
        "That import is how KDE's own copy of this code reaches its C++ half." \
        "It only resolves for a widget compiled into Plasma. Ours is shipped as" \
        "a folder of QML files, so the import quietly resolves to nothing and" \
        "the dock loses its right-click menu and its sizing maths — on the" \
        "machine, not here." \
        "" \
        "This almost always means fresh code was pasted in from upstream." \
        "FORK-NOTES.md lists what we use instead: contents/ui/AquariusBackend.qml," \
        "and the two files in contents/ui/code/."
fi

say "no compiled-only 'plasma.applet.*' imports."

# ------------------------------------------------------------------------------
# 4. Is every piece of KDE the widget imports actually installed?
# ------------------------------------------------------------------------------
# Qt looks for a module named  org.kde.taskmanager  in a folder named
#     <qml root>/org/kde/taskmanager
# so the check is: turn each import's dots into slashes, and see if that folder
# is there under any of Qt's QML roots.
QML_ROOTS=""
for root in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib64/qt6/qml/ ; do
    [ -d "$root" ] && QML_ROOTS="${QML_ROOTS} ${root}"
done

[ -n "$QML_ROOTS" ] || die \
    "Could not find Qt's QML folder in this image." \
    "" \
    "Looked for /usr/lib64/qt6/qml and /usr/lib/qt6/qml and found neither." \
    "Either Qt moved, or this script is running somewhere it should not be."

# Read the import list straight out of the widget, so it can never go stale.
IMPORTS="$(grep -rhE '^[[:space:]]*(import|\.import)[[:space:]]+[A-Za-z]' \
        "${PACKAGE_DIR}/contents" \
    | sed -E 's/^[[:space:]]*\.?import[[:space:]]+//; s/[[:space:]]+as[[:space:]]+.*//; s/[[:space:]]*$//' \
    | sort -u)"

[ -n "$IMPORTS" ] || die \
    "Read no import lines at all out of the dock's QML." \
    "" \
    "That should be impossible for a working widget, so something is wrong" \
    "with the copy in the image rather than with Plasma."

MISSING=""
CHECKED=0

for module in $IMPORTS; do
    CHECKED=$((CHECKED + 1))
    relative="$(echo "$module" | tr '.' '/')"
    found="no"
    for root in $QML_ROOTS; do
        if [ -d "${root}/${relative}" ]; then
            found="yes"
            break
        fi
    done
    if [ "$found" = "no" ]; then
        MISSING="${MISSING}    ${module}  (looked for .../${relative})
"
    fi
done

if [ -n "$MISSING" ]; then
    die \
        "The dock needs pieces of KDE that are not in this image." \
        "" \
        "Missing:" \
        "${MISSING}" \
        "This is what a Bazzite move to a newer Plasma looks like: something" \
        "the task manager code leans on has been renamed, merged away, or" \
        "dropped. The dock would be MISSING on the booted machine, with no" \
        "error anywhere to explain it. That is why the build stops here." \
        "" \
        "What to do:" \
        "  1. Find where that module went in the new Plasma — its KDE source" \
        "     repo will have a commit renaming or removing it." \
        "  2. If it was renamed, update the import in the dock's QML." \
        "  3. If it is gone for good, the code that used it has to go too." \
        "     Note the change in FORK-NOTES.md so the next re-sync knows." \
        "" \
        "The re-sync procedure is written out in docs/aquarius-dock.md."
fi

say "all ${CHECKED} imported modules are installed."
say "OK — the Aquarius Dock has everything it needs."
