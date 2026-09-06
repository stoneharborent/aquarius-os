#!/usr/bin/env bash
# ==============================================================================
# Build the two AquariusOS icon themes from the drawings in branding/icons/
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when an icon's DRAWING changes — that is, when somebody edits
#   branding/icons/icons.mjs. The finished icons are already committed, so a
#   normal OS build never runs this script.
#
# HOW TO RUN IT (on the Mac, from anywhere)
#   npm --prefix branding/icons install     # once, ever — see below
#   bash branding/render-app-icons.sh
#
#   Then look at the icons, and commit them:
#   git add branding/icons system_files/usr/share/icons && git commit
#
#   It takes a few minutes. It draws 192 separate pictures and each one is a
#   fresh, short run of Chrome.
#
# ------------------------------------------------------------------------------
# WHAT IT MAKES
# ------------------------------------------------------------------------------
# Two complete icon themes, written straight into system_files/ — which is a
# mirror of the finished operating system's filesystem, so everything here
# lands on the machine exactly where you see it:
#
#   system_files/usr/share/icons/Aquarius-Ice/         the light set (the default)
#   system_files/usr/share/icons/Aquarius-Midnight/    the dark set
#
# and inside each one:
#
#   index.theme                what makes the folder a THEME rather than a
#                              folder of pictures. Without it nothing finds any
#                              of this.
#   scalable/apps/<name>.svg   the drawing itself, which scales to any size
#   <size>/apps/<name>.png     the same drawing as a fixed-size picture, at
#                              each of the eight sizes below
#
# ------------------------------------------------------------------------------
# WHY BOTH AN SVG AND EIGHT PNGs OF THE SAME PICTURE
# ------------------------------------------------------------------------------
# The SVG is the real icon and modern GNOME draws it directly. The PNGs are for
# everything that does not: some Qt programs, some Electron programs, anything
# reading the icon out of a window's own properties, and Flatpak apps whose
# sandbox has no SVG loader. An icon theme with only SVGs looks perfect until
# the one app that needs a bitmap shows a grey square instead, which is exactly
# the kind of fault nobody notices until Royce is filming.
#
# ------------------------------------------------------------------------------
# WHY THE PICTURES ARE MADE HERE AND COMMITTED, NOT MADE DURING THE OS BUILD
# ------------------------------------------------------------------------------
# This is the same decision — for the same reasons — as the logo
# (branding/render-logo-png.sh) and the boot splash
# (branding/render-plymouth-assets.sh), and it is worth writing down once more
# because it looks like the OS build could just do it:
#
#   1. A picture you can open and look at is reviewable. A picture made inside
#      a build is only ever seen by the build.
#   2. Making them here means the OS image does not need a drawing program in
#      it. Rasterising during the build would mean installing librsvg's tools
#      into an operating system that has no other use for them.
#   3. They change roughly never. Paying twenty minutes of build time on every
#      push to redraw pictures nobody edited is a bad trade.
#
# So: this script runs on the Mac, the results are committed, and the OS build
# just copies them (build_files/56-aquarius-icons.sh checks that it did).
#
# ------------------------------------------------------------------------------
# WHAT IT NEEDS
# ------------------------------------------------------------------------------
#   Node 20 or newer, and the one library the drawings use:
#       npm --prefix branding/icons install
#   That downloads `fontkit`, which is what turns the letters "DR" into a shape
#   for the two DaVinci Resolve icons. It is the ONLY dependency, and the
#   downloaded folder (branding/icons/node_modules) is not committed.
#
#   Google Chrome (already on the Mac), OR rsvg-convert (`brew install librsvg`).
#   Same two options, and the same preference order, as every other renderer in
#   this folder.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${REPO_ROOT}/branding/icons"
ICONS_ROOT="${REPO_ROOT}/system_files/usr/share/icons"

# ------------------------------------------------------------------------------
# The numbers. All of them, in one place.
# ------------------------------------------------------------------------------
# The eight sizes are the standard freedesktop ladder — the sizes desktops
# actually ask for. 16 is a menu, 24 a small toolbar, 32 a list, 48 the classic
# desktop icon, 64 the dock, and 128/256/512 are what a 4K screen at 200% asks
# for when it wants any of those. Changing this list means changing the
# Directories line in the index.theme below too, and the script does that for
# you — that is the whole reason index.theme is generated rather than written by
# hand.
SIZES=(16 24 32 48 64 128 256 512)

# The size the scalable SVG declares on its own tag. 64 because that is the grid
# the icons are drawn on and it is what the existing logo icon says
# (system_files/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg). The
# viewBox is what actually makes it scale; this number only decides what a
# program sees if it asks the file how big it is and then ignores the viewBox.
SCALABLE_PX=64

# theme folder  ↔  which set of colours in branding/icons/icons.mjs
THEME_DIRS=(Aquarius-Ice Aquarius-Midnight)
THEME_KEYS=(ice midnight)

# ------------------------------------------------------------------------------
# Check the tools are here before doing anything
# ------------------------------------------------------------------------------
if ! command -v node > /dev/null 2>&1; then
    echo "ERROR: Node is not installed. It is what draws the icons." >&2
    echo "       Install it with: brew install node" >&2
    exit 1
fi

if [ ! -d "${SRC_DIR}/node_modules/fontkit" ]; then
    echo "ERROR: the drawing library is not downloaded yet. Run this once:" >&2
    echo "           npm --prefix branding/icons install" >&2
    echo "       then run this script again." >&2
    exit 1
fi

RASTERISER=""
CHROME=""
if command -v rsvg-convert > /dev/null 2>&1; then
    RASTERISER="rsvg"
else
    CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [ ! -x "${CHROME}" ]; then
        CHROME="$(command -v google-chrome || command -v chromium || true)"
    fi
    if [ -z "${CHROME}" ] || [ ! -x "${CHROME}" ]; then
        echo "ERROR: no rsvg-convert and no Google Chrome. Install one and re-run." >&2
        echo "           brew install librsvg" >&2
        exit 1
    fi
    RASTERISER="chrome"
fi
echo "Drawing with: ${RASTERISER}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ==============================================================================
# 1. The master drawings
# ==============================================================================
# These are the reference copies kept in branding/icons/. They are not what the
# OS reads — they are what a person opens to look at an icon full size.
echo
echo "=== The master drawings (branding/icons/<theme>/) ==="
node "${SRC_DIR}/render.mjs" --size 1024 --out "${SRC_DIR}"

# ==============================================================================
# 2. Two more passes at the sizes the themes need
# ==============================================================================
# ⚠️ WHY A SEPARATE DRAWING PER SIZE INSTEAD OF ONE FILE SCALED UP.
# branding/render-logo-png.sh has a long note about this and it cost us a
# wrongly-placed logo: an SVG that says width="64" and is then asked for at 256
# gives the browser two answers to the same question, and what comes out is the
# drawing scaled wrong and shoved off one edge. The drawings here are a
# FUNCTION of the size, so asking for the exact size wanted removes the
# question entirely. It costs nothing — it is the same drawing, printed with a
# different number at the top.
echo
echo "=== Drawing at ${SCALABLE_PX}px (for the scalable SVGs) ==="
node "${SRC_DIR}/render.mjs" --size "${SCALABLE_PX}" --out "${tmp}/scalable"

for size in "${SIZES[@]}"; do
    node "${SRC_DIR}/render.mjs" --size "${size}" --out "${tmp}/px${size}" > /dev/null
done
echo "=== Drawn at each of: ${SIZES[*]} ==="

# ------------------------------------------------------------------------------
# rasterise <in.svg> <out.png> <pixels>
# ------------------------------------------------------------------------------
# --default-background-color=00000000 is what keeps the picture transparent.
# The icons draw their own rounded plate, so the corners outside it must be
# see-through; without this Chrome paints white behind the page and every icon
# gets white corners on a dark dock.
rasterise() {
    local in="$1" out="$2" px="$3"

    if [ "${RASTERISER}" = "rsvg" ]; then
        rsvg-convert --width="${px}" --height="${px}" --format=png --output="${out}" "${in}"
    else
        cp "${in}" "${tmp}/one.svg"
        printf '%s' '<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:transparent}img{display:block}</style>
<img src="one.svg" width="'"${px}"'" height="'"${px}"'">' > "${tmp}/one.html"
        "${CHROME}" --headless --disable-gpu --hide-scrollbars \
            --default-background-color=00000000 \
            --force-device-scale-factor=1 --virtual-time-budget=4000 \
            --window-size="${px},${px}" \
            --screenshot="${out}" "file://${tmp}/one.html" > /dev/null 2>&1
    fi

    if [ ! -s "${out}" ]; then
        echo "ERROR: nothing was written to ${out}." >&2
        exit 1
    fi
}

# ==============================================================================
# 3. Build the two themes
# ==============================================================================
for i in "${!THEME_DIRS[@]}"; do
    theme_dir="${THEME_DIRS[$i]}"
    theme_key="${THEME_KEYS[$i]}"
    dest="${ICONS_ROOT}/${theme_dir}"

    echo
    echo "=== ${theme_dir} ==="

    # Start from nothing, so an icon that was renamed or removed in icons.mjs
    # does not survive here as a file nobody meant to keep. Everything under
    # this folder is generated; there is nothing hand-made to preserve.
    rm -rf "${dest}"
    mkdir -p "${dest}/scalable/apps"

    # --------------------------------------------------------------------------
    # index.theme — the file that makes this a theme
    # --------------------------------------------------------------------------
    # Written by this script rather than by hand, so its Directories line can
    # never disagree with the folders that were actually made. (A size listed
    # here with no folder behind it, or a folder not listed here, both produce
    # an icon that silently is not found.)
    #
    #   Inherits=Adwaita,hicolor   anything we do not draw falls through to
    #                              GNOME's own icon set, and then to the
    #                              cross-desktop one. This is what stops the
    #                              theme being a desktop full of grey squares:
    #                              we only draw nine icons.
    #   Context=Applications       these are app icons, which is what tells a
    #     + Type=Scalable/Fixed    desktop it may use them for a launcher.
    {
        printf '[Icon Theme]\n'
        printf 'Name=%s\n' "${theme_dir}"
        if [ "${theme_key}" = "ice" ]; then
            printf 'Comment=%s\n' "AquariusOS app icons — Ice, the light set"
        else
            printf 'Comment=%s\n' "AquariusOS app icons — Midnight, the dark set"
        fi
        printf 'Inherits=Adwaita,hicolor\n'

        dirs="scalable/apps"
        for size in "${SIZES[@]}"; do dirs="${dirs},${size}x${size}/apps"; done
        printf 'Directories=%s\n' "${dirs}"

        printf '\n[scalable/apps]\nSize=%s\nMinSize=8\nMaxSize=512\nContext=Applications\nType=Scalable\n' "${SCALABLE_PX}"
        for size in "${SIZES[@]}"; do
            printf '\n[%sx%s/apps]\nSize=%s\nContext=Applications\nType=Fixed\n' "${size}" "${size}" "${size}"
        done
    } > "${dest}/index.theme"

    # --------------------------------------------------------------------------
    # The icons
    # --------------------------------------------------------------------------
    count=0
    for svg in "${tmp}/scalable/${theme_key}"/*.svg; do
        name="$(basename "${svg}" .svg)"
        cp "${svg}" "${dest}/scalable/apps/${name}.svg"

        for size in "${SIZES[@]}"; do
            mkdir -p "${dest}/${size}x${size}/apps"
            rasterise "${tmp}/px${size}/${theme_key}/${name}.svg" \
                "${dest}/${size}x${size}/apps/${name}.png" "${size}"
        done
        count=$((count + 1))
        echo "  ${name} — 1 SVG + ${#SIZES[@]} PNGs"
    done
    echo "  ${count} icons in ${theme_dir}"
done

# ==============================================================================
# 4. Prove what came out is what the theme says came out
# ==============================================================================
# ⚠️ CONTENTS, NEVER CLOCKS. This is the project rule (build_files/aq-lib.sh
# explains where it came from) and it applies to a picture too: "the file is
# there" is not the same as "the file is a 48-pixel-square PNG". A PNG says its
# own size in the first few bytes, so that is what gets read here.
echo
python3 - "${ICONS_ROOT}" "${THEME_DIRS[*]}" "${SIZES[*]}" "${SCALABLE_PX}" << 'PY'
import os
import struct
import sys

icons_root, themes, sizes, scalable_px = sys.argv[1], sys.argv[2].split(), [int(s) for s in sys.argv[3].split()], int(sys.argv[4])

fails = 0


def bad(msg):
    global fails
    fails += 1
    print(f"  FAIL {msg}")


def png_size(path):
    with open(path, "rb") as fh:
        data = fh.read(24)
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


for theme in themes:
    root = os.path.join(icons_root, theme)
    index = os.path.join(root, "index.theme")

    if not os.path.isfile(index):
        bad(f"{theme}/index.theme is missing — nothing would find this theme at all")
        continue
    text = open(index, encoding="utf-8").read()
    for want in (f"Name={theme}", "Inherits=Adwaita,hicolor", "scalable/apps"):
        if want not in text:
            bad(f"{theme}/index.theme does not say {want!r}")
    for size in sizes:
        if f"[{size}x{size}/apps]" not in text:
            bad(f"{theme}/index.theme does not list the {size}x{size} folder")

    names = sorted(
        f[:-4] for f in os.listdir(os.path.join(root, "scalable", "apps")) if f.endswith(".svg")
    )
    if not names:
        bad(f"{theme} has no icons in scalable/apps")
        continue

    for name in names:
        svg = os.path.join(root, "scalable", "apps", f"{name}.svg")
        head = open(svg, encoding="utf-8").read(200)
        if 'viewBox="0 0 64 64"' not in head:
            bad(f"{theme}/scalable/apps/{name}.svg is not drawn on the 64 grid")
        if f'width="{scalable_px}"' not in head:
            bad(f"{theme}/scalable/apps/{name}.svg does not declare width=\"{scalable_px}\"")

        for size in sizes:
            png = os.path.join(root, f"{size}x{size}", "apps", f"{name}.png")
            if not os.path.isfile(png):
                bad(f"{theme}/{size}x{size}/apps/{name}.png is missing")
                continue
            got = png_size(png)
            if got is None:
                bad(f"{theme}/{size}x{size}/apps/{name}.png is not a PNG file")
            elif got != (size, size):
                bad(f"{theme}/{size}x{size}/apps/{name}.png is {got[0]}x{got[1]}, expected {size}x{size}")

    total = sum(
        len(files) for _, _, files in os.walk(root)
    )
    print(f"  OK   {theme}: {len(names)} icons, {total} files "
          f"({', '.join(names)})")

if fails:
    print(f"\nERROR: {fails} problem(s) with the icons that were just written.", file=sys.stderr)
    sys.exit(1)
print("\nAll icon checks passed.")
PY

echo
echo "Next: look at a few of the icons, then"
echo "      git add branding/icons system_files/usr/share/icons && git commit"
