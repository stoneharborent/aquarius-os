#!/bin/bash
# ==============================================================================
# AquariusOS — does the Quick Settings widget have everything it needs?
# ==============================================================================
# WHAT THIS FILE DOES, IN ONE SENTENCE
#   It reads the Quick Settings widget's own QML, works out every piece of KDE
#   that widget depends on, and checks each one is really in the image. If any
#   is missing the OS build goes red and nothing is published.
#
# WHY IT EXISTS — the failure it is here to prevent
#   The widget is built out of KDE's own plumbing: the Wi-Fi tile drives the
#   same code as the stock Wi-Fi applet, the sound slider drives the same code
#   as the stock volume applet, and so on. Those pieces are "QML modules", and
#   several of them have the word `private` in their name.
#
#   `private` is KDE saying: this is our internal wiring, we may rename or
#   delete it in any release, and we owe you no warning. AquariusOS does not
#   choose when that happens — we inherit KDE from Bazzite, and a Bazzite
#   rebase can move Plasma underneath us overnight.
#
#   The nasty part is how it would fail without this file. A QML file that
#   imports a module that is not there does not crash and does not log anything
#   a person would see. It just does not load. The widget has a safety net for
#   that (see AqTileSlot.qml), so the panel would still open — with one tile
#   quietly greyed out and nobody any the wiser until a user noticed weeks
#   later that Bluetooth had stopped working.
#
#   This check turns that silent, slow failure into a loud, immediate one. A
#   Plasma update that removes something we use breaks the BUILD, on the day it
#   happens, while the previous image keeps working for everybody. That is the
#   same bargain the KWin effects build makes, and for the same reason — see the
#   long note at the top of build_files/kwin-effects.sh.
#
# WHY IT READS THE QML INSTEAD OF HAVING A LIST IN IT
#   A hardcoded list of modules would be correct on the day it was written and
#   wrong the first time somebody added a tile and forgot to update it — and a
#   check that silently stops covering things is worse than no check, because it
#   still reports success.
#
#   So there is no list. The script greps the import lines out of the widget's
#   own QML files and checks whatever it finds. Add a tile that imports
#   something new and it is covered automatically; delete one and the check
#   stops asking for it. The only way to be wrong is to write an import the grep
#   cannot see, which is why the sanity check at the end insists on finding a
#   minimum number of modules — a grep that matched nothing would otherwise
#   "pass".
#
# WHERE IT RUNS
#   Inside the image build, from build_files/build.sh, AFTER the system_files
#   copy has put the widget into /usr/share/plasma/plasmoids/.
# ==============================================================================

set -euo pipefail

die() {
    echo ""
    echo "=============================================================="
    echo "AquariusOS Quick Settings check FAILED"
    echo "--------------------------------------------------------------"
    printf '%s\n' "$@"
    echo "=============================================================="
    echo ""
    exit 1
}

say() { echo ">> $*"; }

AQ_WIDGET_ID="com.aquariusos.quicksettings"
AQ_WIDGET_DIR="/usr/share/plasma/plasmoids/${AQ_WIDGET_ID}"
AQ_LAYOUT="/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"

# Where Qt keeps QML modules. Both spellings are checked because a 64-bit
# Fedora uses /usr/lib64 while some packages land in /usr/lib, and which one a
# given KDE module uses is not something to guess at.
AQ_QML_DIRS=(
    "/usr/lib64/qt6/qml"
    "/usr/lib/qt6/qml"
)

say ""
say "=============================================================="
say "Quick Settings widget — checking the image has what it needs"
say "=============================================================="

# ==============================================================================
# STEP 1 — the widget itself is installed and looks like a widget
# ==============================================================================
# Plasma will only load a folder as a widget if it has these two files with
# these exact names. A typo in either is a widget that never appears, with no
# error anywhere.

say ""
say "=== The widget's own files ==="

[ -d "${AQ_WIDGET_DIR}" ] || die \
    "The widget is not installed at ${AQ_WIDGET_DIR}." \
    "" \
    "It should have been copied there by the system_files step at the top of" \
    "build_files/build.sh. Here is what IS in the plasmoids folder:" \
    "$(ls -1 /usr/share/plasma/plasmoids/ 2>/dev/null || echo '  (the folder does not exist)')"

for aq_required in "metadata.json" "contents/ui/main.qml"; do
    [ -f "${AQ_WIDGET_DIR}/${aq_required}" ] || die \
        "${AQ_WIDGET_DIR}/${aq_required} is missing." \
        "" \
        "Plasma requires both metadata.json and contents/ui/main.qml, at" \
        "exactly those paths. A widget missing either is silently ignored."
    say "  OK  ${aq_required}"
done

# The id inside metadata.json has to match the folder name. When they disagree,
# Plasma indexes the widget under one name and the layout script asks for the
# other, so the bar comes up without it — and nothing anywhere says why.
AQ_META_ID="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['KPlugin']['Id'])" \
                "${AQ_WIDGET_DIR}/metadata.json" 2>/dev/null || true)"

[ -n "${AQ_META_ID}" ] || die \
    "Could not read KPlugin.Id out of ${AQ_WIDGET_DIR}/metadata.json." \
    "Either the file is not valid JSON or it has no KPlugin.Id."

[ "${AQ_META_ID}" = "${AQ_WIDGET_ID}" ] || die \
    "The widget's id and its folder name disagree." \
    "" \
    "  folder name        ${AQ_WIDGET_ID}" \
    "  KPlugin.Id         ${AQ_META_ID}" \
    "" \
    "These must be identical. Plasma finds the widget by folder and then" \
    "identifies it by id; when they differ the layout script's request for" \
    "'${AQ_WIDGET_ID}' matches nothing and the widget never appears."
say "  OK  metadata.json declares id ${AQ_META_ID}"

# And the layout script has to actually add it, by that same name.
if [ -f "${AQ_LAYOUT}" ]; then
    grep -q "\"${AQ_WIDGET_ID}\"" "${AQ_LAYOUT}" || die \
        "The desktop layout script never adds the widget." \
        "" \
        "Looked for \"${AQ_WIDGET_ID}\" in:" \
        "  ${AQ_LAYOUT}" \
        "" \
        "Without that line the widget is installed but nothing puts it in the" \
        "top bar, so a new user would never see it."
    say "  OK  the layout script adds it to the top bar"
else
    say "  --  no layout script at ${AQ_LAYOUT} (skipped)"
fi

# ==============================================================================
# STEP 2 — every KDE module the widget imports is present
# ==============================================================================
# The grep looks for lines like
#     import org.kde.plasma.private.volume
#     import org.kde.bluezqt as BluezQt
# and keeps the URI. Only `org.kde.*` is checked: QtQuick and friends come with
# Qt itself, and if those were missing nothing on the desktop would start.
#
# Turning a URI into a folder is a plain substitution — dots become slashes —
# because that is exactly how Qt itself looks a module up.

say ""
say "=== The KDE modules the widget imports ==="

AQ_MODULES="$(grep -rhoE '^[[:space:]]*import[[:space:]]+org\.kde\.[A-Za-z0-9_.]+' \
                "${AQ_WIDGET_DIR}/contents/ui/" \
              | awk '{print $2}' \
              | sort -u)"

[ -n "${AQ_MODULES}" ] || die \
    "No 'import org.kde.…' lines were found in the widget's QML at all." \
    "" \
    "That is almost certainly a fault in this script rather than in the" \
    "widget — the QML is there, so the grep should have matched something." \
    "Check that ${AQ_WIDGET_DIR}/contents/ui/ contains .qml files."

aq_missing=0
aq_found=0

while read -r aq_uri; do
    [ -n "${aq_uri}" ] || continue

    # org.kde.plasma.private.volume  ->  org/kde/plasma/private/volume
    aq_path="${aq_uri//.//}"

    aq_hit=""
    for aq_root in "${AQ_QML_DIRS[@]}"; do
        # `qmldir` is the file Qt reads to learn what a module contains. A
        # folder without one is not a loadable module, so that is the file to
        # test for rather than just the directory.
        if [ -f "${aq_root}/${aq_path}/qmldir" ]; then
            aq_hit="${aq_root}/${aq_path}"
            break
        fi
    done

    if [ -n "${aq_hit}" ]; then
        say "  OK  ${aq_uri}"
        say "        ${aq_hit}"
        aq_found=$((aq_found + 1))
    else
        echo "  MISSING  ${aq_uri}"
        echo "           looked for ${aq_path}/qmldir under:"
        for aq_root in "${AQ_QML_DIRS[@]}"; do
            echo "             ${aq_root}"
        done
        # Say which of our files wanted it — that is the first thing anybody
        # investigating will want to know.
        echo "           imported by:"
        grep -rlE "^[[:space:]]*import[[:space:]]+${aq_uri//./\\.}([[:space:]]|$)" \
            "${AQ_WIDGET_DIR}/contents/ui/" 2>/dev/null \
            | sed 's|^|             |' || true
        aq_missing=$((aq_missing + 1))
    fi
done <<< "${AQ_MODULES}"

# ==============================================================================
# STEP 3 — the verdict
# ==============================================================================

if [ "${aq_missing}" -ne 0 ]; then
    die "${aq_missing} QML module(s) the Quick Settings widget needs are not in this image." \
        "" \
        "WHAT THIS PROBABLY MEANS" \
        "  Bazzite moved to a newer Plasma, and KDE renamed or removed one of" \
        "  the modules the widget is built on. The ones with 'private' in the" \
        "  name are allowed to do that without warning; that is what the word" \
        "  means." \
        "" \
        "HOW TO FIX IT" \
        "  1. Find what the module was renamed to, by looking at how the" \
        "     matching stock applet does the same job in the new Plasma." \
        "     Each of our tile files names the upstream file it was written" \
        "     from, at the top, so start there." \
        "  2. Update the import and the API in that one tile file." \
        "  3. Update the module's row in docs/quick-settings-widget.md." \
        "" \
        "WHAT NOT TO DO" \
        "  Do not delete the import to make the build pass. The widget would" \
        "  build, ship, and quietly show a dead tile — which is the exact" \
        "  failure this check exists to prevent."
fi

say ""
say "  All ${aq_found} module(s) present."

# The sanity floor. If the grep above ever breaks — a change to how the imports
# are written, a path that stops matching — it would find nothing, every loop
# would be skipped, and this script would cheerfully report success while
# checking absolutely nothing. This line makes that impossible: the widget has
# well over this many KDE imports, so anything under it means the check itself
# is broken, not that the image is fine.
AQ_MINIMUM_MODULES=6
if [ "${aq_found}" -lt "${AQ_MINIMUM_MODULES}" ]; then
    die "Only ${aq_found} KDE module(s) were found to check, and at least ${AQ_MINIMUM_MODULES} were expected." \
        "" \
        "This is a fault in build_files/quick-settings-check.sh, not in the" \
        "image. The widget imports more modules than that, so the grep that" \
        "collects them has stopped matching — which would make this whole" \
        "check pass while testing nothing." \
        "" \
        "Modules it did find:" \
        "${AQ_MODULES}"
fi

say ""
say "=== Quick Settings widget: everything it needs is in the image ==="
say ""
