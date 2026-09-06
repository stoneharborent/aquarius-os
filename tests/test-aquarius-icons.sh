#!/usr/bin/env bash
# ==============================================================================
# Tests for the AquariusOS app icons
# ==============================================================================
# WHAT THIS IS FOR
# ------------------------------------------------------------------------------
# AquariusOS draws eight of its own app icons — the Editor, the Writer, Files,
# Settings, the app chooser, the welcome window and the two DaVinci Resolve
# buttons — and ships them as two icon themes, Aquarius-Ice (the default) and
# Aquarius-Midnight.
#
# ⚠️ AN ICON THAT IS MISSING IS NOT AN ERROR ANYWHERE. Both themes say
# `Inherits=Adwaita,hicolor`, which means anything we fail to provide falls
# silently through to GNOME's own artwork. The machine looks completely normal.
# It is just not AquariusOS, and nothing anywhere says so. Same for a launcher
# entry asking for an icon name we do not ship: the desktop draws a blank square
# and prints nothing.
#
# So everything here is checked by READING THE ACTUAL CONTENTS — the text inside
# index.theme, the width and height a PNG states in its own first two dozen
# bytes, the Icon= line in each launcher entry. Never a file's date. (That rule,
# and the day it was learned, is in build_files/aq-lib.sh.)
#
# HOW TO RUN IT
# ------------------------------------------------------------------------------
#   ./tests/test-aquarius-icons.sh
#       tests the copies in this repo, under system_files/. This is what CI runs
#       BEFORE the twenty-minute build, so a missing icon is caught in seconds.
#
#   ./tests/test-aquarius-icons.sh /
#       tests a finished AquariusOS image from the inside, where the same files
#       live at /usr/share/... . This is what CI runs against the built image.
#
# It prints a line per check and exits with a failure if any of them is wrong.
# ==============================================================================

set -u

# Where to look. An argument wins — "/" means a real machine or a built image.
# Otherwise use this repo's system_files/, worked out relative to this script so
# it does not matter which folder you run it from.
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
ROOT="${1:-${REPO_ROOT}/system_files}"
ROOT="${ROOT%/}"   # no trailing slash, so "/usr/..." never becomes "//usr/..."

ICONS_ROOT="${ROOT}/usr/share/icons"
DEFAULT_THEME="Aquarius-Ice"
DARK_THEME="Aquarius-Midnight"

# These two lists must match branding/render-app-icons.sh and
# build_files/56-aquarius-icons.sh. They are written out here rather than read
# from anywhere so that a rename in one place fails loudly in the other.
SIZES=(16 24 32 48 64 128 256 512)
ICON_NAMES=(
    aquarius-editor
    aquarius-writer
    org.gnome.Nautilus
    aquarius-files
    org.gnome.Settings
    aquarius-settings
    aquarius-apps
    aquarius-welcome
    aquarius-install-resolve
    aquarius-remove-resolve
)

# Royce's table, 2026-09-06: which launcher entry carries which icon.
#
# ⚠️ aquarius-updater.desktop WEARS THE SETTINGS ICON ON PURPOSE. There is no
# "Check for Update" app — it is a window the Aquarius logo menu opens — and it
# borrows the Settings icon until that flow moves into System Settings. Not a
# mistake, and not a gap waiting for artwork.
DESKTOP_ICONS=(
    "usr/share/applications/aquarius-creator-apps.desktop|aquarius-apps"
    "usr/share/applications/aquarius-welcome.desktop|aquarius-welcome"
    "etc/xdg/autostart/aquarius-welcome-firstrun.desktop|aquarius-welcome"
    "usr/share/applications/aquarius-install-resolve.desktop|aquarius-install-resolve"
    "usr/share/applications/aquarius-remove-resolve.desktop|aquarius-remove-resolve"
    "usr/share/applications/aquarius-updater.desktop|org.gnome.Settings"
    "usr/share/applications/aquarius-writer.desktop|aquarius-writer"
    "usr/share/aquarius/apps/aquarius-editor.desktop.in|aquarius-editor"
)

PASSED=0
FAILED=0

pass() {
    PASSED=$((PASSED + 1))
    printf '  OK    %s\n' "$1"
}

fail() {
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' "$1"
}

# same_file <a> <b>  — are these two files byte for byte identical?
#
# `cmp` is the obvious tool and it is normally there, but it comes from the
# diffutils package and a trimmed image is not obliged to have it. Falling back
# to python3 (which this test already needs, and which every AquariusOS image
# has because aq-ingest is written in it) means this test cannot fail for a
# reason that has nothing to do with icons.
same_file() {
    if command -v cmp > /dev/null 2>&1; then
        cmp -s "$1" "$2"
    else
        python3 -c 'import filecmp,sys; sys.exit(0 if filecmp.cmp(sys.argv[1], sys.argv[2], shallow=False) else 1)' "$1" "$2"
    fi
}

# file_says <file> <extended regex> <what this proves>
file_says() {
    if [ ! -r "$1" ]; then
        fail "$3 — $1 does not exist"
        return
    fi
    if grep -Eq "$2" "$1"; then
        pass "$3"
    else
        fail "$3 — /$2/ is not in $1"
    fi
}

echo "test-aquarius-icons: reading ${ROOT}"

# ------------------------------------------------------------------------------
# 1. Each theme is a theme
# ------------------------------------------------------------------------------
# A folder of pictures is not an icon theme. index.theme is what makes it one:
# it names the theme, says what to fall back to, and lists which folder holds
# which size. Get any of that wrong and every icon inside is invisible.
echo
echo "== each theme has an index.theme that describes it =="
for theme in "${DEFAULT_THEME}" "${DARK_THEME}"; do
    index="${ICONS_ROOT}/${theme}/index.theme"
    file_says "${index}" "^Name=${theme}$" "${theme}: index.theme names itself"
    file_says "${index}" "^Comment=." "${theme}: index.theme has a description"
    file_says "${index}" "^Inherits=Adwaita,hicolor$" \
        "${theme}: falls back to GNOME's icons for the ones we do not draw"
    file_says "${index}" "^Directories=.*scalable/apps" \
        "${theme}: index.theme lists its scalable folder"
    for size in "${SIZES[@]}"; do
        file_says "${index}" "^\[${size}x${size}/apps\]$" \
            "${theme}: index.theme describes its ${size}x${size} folder"
    done
done

# ------------------------------------------------------------------------------
# 2. Every icon, at every size, and really that size
# ------------------------------------------------------------------------------
# "The file is there" is not the same as "the file is a 48-pixel square". A
# 48-pixel folder holding a 512-pixel picture produces a blurry, slow desktop
# and no error at all — so a PNG's own stated size is what gets read here.
echo
echo "== every icon exists, in both themes, at all ${#SIZES[@]} sizes =="
if ! command -v python3 > /dev/null 2>&1; then
    fail "python3 is not available, so the picture sizes could not be read"
else
    ICON_OUT="$(mktemp)"
    python3 - "${ICONS_ROOT}" "${DEFAULT_THEME} ${DARK_THEME}" "${SIZES[*]}" "${ICON_NAMES[*]}" \
        > "${ICON_OUT}" 2>&1 << 'PY'
import os
import struct
import sys

icons_root = sys.argv[1]
themes = sys.argv[2].split()
sizes = [int(s) for s in sys.argv[3].split()]
names = sys.argv[4].split()

for theme in themes:
    root = os.path.join(icons_root, theme)
    for name in names:
        svg = os.path.join(root, "scalable", "apps", f"{name}.svg")
        if not os.path.isfile(svg) or os.path.getsize(svg) == 0:
            print(f"FAIL {theme}: scalable/apps/{name}.svg is missing or empty")
        else:
            head = open(svg, encoding="utf-8", errors="replace").read(200)
            if "<svg" in head and 'viewBox="0 0 64 64"' in head:
                print(f"PASS {theme}: {name} — the drawing, on the 64 grid")
            else:
                print(f"FAIL {theme}: scalable/apps/{name}.svg is not an "
                      "Aquarius icon (no <svg> on the 64 grid)")

        wrong = []
        for size in sizes:
            png = os.path.join(root, f"{size}x{size}", "apps", f"{name}.png")
            if not os.path.isfile(png):
                wrong.append(f"{size}: missing")
                continue
            with open(png, "rb") as fh:
                header = fh.read(24)
            if header[:8] != b"\x89PNG\r\n\x1a\n":
                wrong.append(f"{size}: not a PNG")
                continue
            width, height = struct.unpack(">II", header[16:24])
            if (width, height) != (size, size):
                wrong.append(f"{size}: actually {width}x{height}")
        if wrong:
            print(f"FAIL {theme}: {name} pictures — " + "; ".join(wrong))
        else:
            print(f"PASS {theme}: {name} — {len(sizes)} pictures, each the size it claims")
PY
    while read -r verdict rest; do
        case "${verdict}" in
            PASS) pass "${rest}" ;;
            FAIL) fail "${rest}" ;;
            *) printf '  %s %s\n' "${verdict}" "${rest}" ;;
        esac
    done < "${ICON_OUT}"
    rm -f "${ICON_OUT}"
fi

# ------------------------------------------------------------------------------
# 3. GNOME's names and ours are the same picture
# ------------------------------------------------------------------------------
# GNOME's Files asks for its icon as `org.gnome.Nautilus` and GNOME's Settings
# as `org.gnome.Settings`. Neither can be persuaded to ask for anything else, so
# those are the two names that actually replace an icon on screen. Our own names
# exist so our windows and our docs can refer to the same picture without
# knowing GNOME's identifiers — which only works while they ARE the same
# picture.
echo
echo "== our names and GNOME's names are the same drawing =="
for theme in "${DEFAULT_THEME}" "${DARK_THEME}"; do
    for pair in "org.gnome.Nautilus|aquarius-files" "org.gnome.Settings|aquarius-settings"; do
        gnome_name="${pair%%|*}"
        our_name="${pair##*|}"
        a="${ICONS_ROOT}/${theme}/scalable/apps/${gnome_name}.svg"
        b="${ICONS_ROOT}/${theme}/scalable/apps/${our_name}.svg"
        if [ ! -r "${a}" ] || [ ! -r "${b}" ]; then
            fail "${theme}: ${gnome_name} or ${our_name} is missing, so they cannot be compared"
        elif same_file "${a}" "${b}"; then
            pass "${theme}: ${gnome_name} and ${our_name} are the same drawing"
        else
            fail "${theme}: ${gnome_name} and ${our_name} have drifted apart — rerun branding/render-app-icons.sh"
        fi
    done
done

# ------------------------------------------------------------------------------
# 4. Nobody left a half-made icon cache behind
# ------------------------------------------------------------------------------
# AquariusOS deliberately does not ship icon caches. The reasoning is in the
# header of build_files/56-aquarius-icons.sh; the short version is that a cache
# is a speed optimisation whose usefulness is decided by comparing file dates,
# and the tool that packages a bootable image flattens every date.
echo
echo "== no icon caches =="
for theme in "${DEFAULT_THEME}" "${DARK_THEME}"; do
    if [ -e "${ICONS_ROOT}/${theme}/icon-theme.cache" ]; then
        fail "${theme}: an icon-theme.cache is present — this project does not ship them"
    else
        pass "${theme}: no icon cache, which is what we want"
    fi
done

# ------------------------------------------------------------------------------
# 5. Aquarius-Ice is the default, in both of the places it is set
# ------------------------------------------------------------------------------
# AquariusOS is light-first. The value has to be the same for a real account and
# for the login screen, or the icons visibly change the instant you log in.
echo
echo "== the default icon theme is ${DEFAULT_THEME} =="
file_says "${ROOT}/usr/share/glib-2.0/schemas/zz1-aquarius-10-look.gschema.override" \
    "^icon-theme='${DEFAULT_THEME}'$" \
    "a new account's desktop defaults to ${DEFAULT_THEME}"

# The login screen's copy is written by a build script, so it only exists when
# this test is looking at the repo — a finished image has the built database
# instead, which build_files/50-aquarius-desktop.sh checks for itself.
GDM_SOURCE="${REPO_ROOT}/build_files/50-aquarius-desktop.sh"
if [ -r "${GDM_SOURCE}" ]; then
    file_says "${GDM_SOURCE}" "^icon-theme='${DEFAULT_THEME}'$" \
        "the login screen is given ${DEFAULT_THEME} too, so nothing changes when you log in"
fi

# ------------------------------------------------------------------------------
# 6. Every launcher asks for an icon that exists
# ------------------------------------------------------------------------------
# A launcher entry names its icon by name. Name one nothing provides and the
# desktop draws a blank square, silently.
echo
echo "== every launcher's Icon= line =="
for entry in "${DESKTOP_ICONS[@]}"; do
    file="${ROOT}/${entry%%|*}"
    want="${entry##*|}"

    file_says "${file}" "^Icon=${want}$" "$(basename "${file}") asks for ${want}"

    if [ -r "${ICONS_ROOT}/${DEFAULT_THEME}/scalable/apps/${want}.svg" ]; then
        pass "  …and ${want} is in ${DEFAULT_THEME}"
    else
        fail "  …but ${want} is NOT in ${DEFAULT_THEME} — that launcher would show a blank square"
    fi
done

# The logo is a different thing with a different job and it did not change. The
# About page, the boot screen and the logo menu all still use it.
if [ -s "${ICONS_ROOT}/hicolor/scalable/apps/aquarius-logo.svg" ]; then
    pass "aquarius-logo is still where the OS's own branding looks for it"
else
    fail "aquarius-logo.svg is missing from hicolor — the About page and boot screen use it"
fi

# ------------------------------------------------------------------------------
echo
echo "test-aquarius-icons: ${PASSED} passed, ${FAILED} failed"
if [ "${FAILED}" -ne 0 ]; then
    echo "::error::The AquariusOS app icons are not right. Scroll up for the FAIL lines."
    exit 1
fi
exit 0
