#!/usr/bin/bash
# ==============================================================================
# Check that our own desktop widgets have everything they need
# ==============================================================================
# WHAT THIS IS FOR
#
# AquariusOS ships its own Plasma widgets — at the moment one of them, the clock
# in the top bar, whose popup is the notifications panel. They are written in
# QML, which means they are not compiled and nothing catches a missing piece
# until somebody logs in and finds a hole in their top bar.
#
# Two kinds of missing piece are worth catching here, at build time:
#
#   1. WE FORGOT TO SHIP A FILE.  The widget is a folder of files with fixed
#      names; leave one out and Plasma refuses to load the widget.
#
#   2. KDE MOVED SOMETHING OUT FROM UNDER US.  Our widgets are built on two KDE
#      QML libraries — the notification library and the clock library. They ship
#      with Plasma today. AquariusOS is rebuilt on top of whatever Bazzite ships,
#      and Bazzite follows Fedora's KDE, so one day a rebase could arrive with a
#      library renamed, moved or dropped.
#
#      This is the exact risk the Tier 2 research told us to guard:
#      docs/v2-shell-tier2-research.md, "Plasmoid shipping (verified)" —
#      "add a CI grep-level presence check for the private plugin dirs so a
#      rebase that drops one fails loudly."
#
#      So we check, here, inside the finished image. If a library has gone, THIS
#      BUILD FAILS and nobody ever installs the broken image. The previous image
#      keeps working and rolls back cleanly, which is the whole point of building
#      the OS this way.
#
# WHAT WE DO **NOT** DO HERE
#   We do not run qmllint. Checking QML properly needs a running Qt with all the
#   modules loaded, which is a much bigger job than this script is for. The
#   cheap checks that CAN be done without Qt — is the metadata readable, are the
#   braces balanced — run on every pull request instead, in
#   tests/test-aquarius-plasmoid.sh, minutes after a push rather than an hour.
# ==============================================================================

set -eoux pipefail

say() { echo "$@"; }

die() {
    echo ""
    echo "::error::$1"
    shift
    for line in "$@"; do echo "        $line"; done
    exit 1
}

say ""
say "=== Checking the AquariusOS desktop widgets ==="

# ------------------------------------------------------------------------------
# 1. Our own widget files are all present
# ------------------------------------------------------------------------------
# Plasma looks for these names exactly. metadata.json is what makes the folder a
# widget at all; ui/main.qml is the file it starts. The rest are the pieces
# main.qml pulls in — a Loader that cannot find its file fails at the moment the
# user clicks, which is the worst time to find out.

AQ_PLASMOID_DIR="/usr/share/plasma/plasmoids/com.aquariusos.clock"

for aq_file in \
    "${AQ_PLASMOID_DIR}/metadata.json" \
    "${AQ_PLASMOID_DIR}/contents/ui/main.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/CompactClock.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/AlignedClock.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/TickingClock.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/NotificationsSource.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/NotificationsPanel.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/NotificationRow.qml" \
    "${AQ_PLASMOID_DIR}/contents/ui/PanelUnavailable.qml"
do
    [ -f "${aq_file}" ] || die "${aq_file} is missing from the image." \
        "" \
        "The clock widget cannot load without it. It should have been copied in" \
        "by the system_files step at the top of build.sh — check that the file" \
        "exists in the repo at system_files${aq_file}."
    say "  OK  ${aq_file##*/}"
done

# ------------------------------------------------------------------------------
# 2. The layout script really does ask for our widget
# ------------------------------------------------------------------------------
# The widget existing and the desktop actually placing it are two different
# statements. A rename in one file and not the other would leave a top bar with
# no clock on it and nothing else to explain why.

AQ_LAYOUT="/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"

[ -f "${AQ_LAYOUT}" ] || die "The desktop layout script is missing from the image." \
    "Expected it at ${AQ_LAYOUT}."

grep -q 'addWidget("com.aquariusos.clock")' "${AQ_LAYOUT}" \
    || die "The desktop layout script does not add the AquariusOS clock." \
        "" \
        "The widget is installed but nothing puts it on the top bar. Look for" \
        "addWidget(\"com.aquariusos.clock\") in:" \
        "  ${AQ_LAYOUT}"
say "  OK  the layout script places com.aquariusos.clock"

# ------------------------------------------------------------------------------
# 3. The KDE QML libraries our widgets import are installed
# ------------------------------------------------------------------------------
# A QML "module" is a folder under Qt's QML path whose name is the import
# spelled with slashes: `import org.kde.notificationmanager` is satisfied by a
# folder called org/kde/notificationmanager. So checking for the folder is
# checking for the import.
#
# Fedora puts these under /usr/lib64/qt6/qml, but that path is a packaging
# choice, not a promise. We look in the places Qt itself would look rather than
# hard-coding one, so a future move does not turn into a false alarm.

aq_qml_module_present() {
    # $1: the import name, e.g. org.kde.notificationmanager
    local aq_import="$1"
    local aq_relative="${aq_import//.//}"
    local aq_root
    for aq_root in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib64/qt-6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do
        if [ -d "${aq_root}/${aq_relative}" ]; then
            say "  OK  ${aq_import}  (${aq_root}/${aq_relative})"
            return 0
        fi
    done
    return 1
}

# The notification library. HARD requirement: without it the popup falls back to
# an apology, and a notifications panel that cannot show notifications is not a
# thing we ship.
aq_qml_module_present "org.kde.notificationmanager" || die \
    "The KDE notification QML library is not in this image." \
    "" \
    "Our clock widget's popup is built on 'org.kde.notificationmanager'. It" \
    "ships as part of plasma-workspace. If this has started failing after a" \
    "Bazzite rebase, KDE has moved or renamed it, and the widget needs" \
    "updating before this image can go out." \
    "" \
    "Where the widget uses it:" \
    "  system_files${AQ_PLASMOID_DIR}/contents/ui/NotificationsSource.qml"

# The clock library. SOFT requirement: the widget carries its own backup timer,
# so a missing one costs us a slightly less clever clock rather than a broken
# desktop. Worth saying out loud, not worth failing a build over.
if ! aq_qml_module_present "org.kde.plasma.clock"; then
    say "  NOTE  org.kde.plasma.clock was not found."
    say "        The clock will fall back to its own minute timer"
    say "        (contents/ui/TickingClock.qml). Nothing is broken, but this is"
    say "        worth looking at: the library arrived in Plasma 6.6 and should"
    say "        be here."
fi

say ""
say "Desktop widgets checked: com.aquariusos.clock is installed, placed, and its"
say "libraries are present."
