#!/usr/bin/env bash
# ==============================================================================
# Re-render the AquariusOS logo PNG from the SVG source
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when you have changed branding/logo.svg. The finished PNG is already
#   committed, so a normal OS build never runs this.
#
# HOW TO RUN IT (on the Mac, from anywhere):
#   bash branding/render-logo-png.sh
#
# WHY A PNG AT ALL, WHEN WE ALREADY SHIP THE LOGO AS AN SVG
#   The SVG at system_files/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg
#   is the logo everything normally uses — it is an icon, in the place icons
#   live, and every app finds it by name.
#
#   GNOME's login screen is the exception. GDM's logo setting takes a PATH TO A
#   PICTURE FILE rather than the name of an icon, and it wants a bitmap. So the
#   login screen gets its own copy, as a PNG, at a path outside the icon folders:
#
#       /usr/share/aquarius/branding/aquarius-logo.png
#
#   Deliberately NOT in /usr/share/pixmaps/. That folder IS part of the icon
#   search path, so a PNG in there called aquarius-logo would compete with the
#   SVG of the same name and different apps would show different versions of the
#   logo depending on which they found first. Keeping the bitmap somewhere
#   nothing searches means there is exactly one logo icon on the machine.
#
#   Which images use it: the two GNOME DESKTOP images. The GNOME handheld uses
#   SDDM rather than GDM (build_files/gnome-desktop.sh explains), and the KDE
#   line deletes this file entirely (build_files/build.sh).
#
# WHAT IT NEEDS
#   Google Chrome (already on the Mac), OR rsvg-convert (`brew install librsvg`).
#   Same two options as branding/render-wallpaper.sh, for the same reason.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/branding/logo.svg"
OUT="$REPO_ROOT/system_files/usr/share/aquarius/branding/aquarius-logo.png"

# 256 pixels square. GDM draws the logo small — around 48 pixels tall on a
# normal screen — but it scales it down itself, and it draws it MUCH larger on a
# 4K display at 200%. 256 is comfortably above anything it will ask for, so the
# logo is never scaled up, and the file is still only a few kilobytes.
SIZE=256

mkdir -p "$(dirname "$OUT")"

# ⚠️ The background must stay TRANSPARENT. GDM draws the login screen's own
# background behind this picture, so a solid rectangle here would show up as an
# obvious box around the logo. This is the one difference from the wallpaper
# renderer, which deliberately paints a background colour.
if command -v rsvg-convert > /dev/null 2>&1; then
  rsvg-convert --width="$SIZE" --height="$SIZE" --format=png --output="$OUT" "$SRC"
else
  chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$chrome" ] || chrome="$(command -v google-chrome || command -v chromium || true)"
  if [ -z "$chrome" ] || [ ! -x "$chrome" ]; then
    echo "ERROR: no Google Chrome and no rsvg-convert. Install one and re-run." >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # ⚠️ THE SIZE HAS TO BE WRITTEN INTO THE SVG ITSELF, not just asked for in CSS.
  # branding/logo.svg declares width="64" height="64" on its opening tag.
  # Sizing the <img> in CSS and leaving those alone gives Chrome two answers to
  # the same question, and what comes out is the mark scaled wrong and shoved
  # off the right-hand edge of the picture — measured, not guessed: the drawing
  # landed at x=157..255 in a 256-wide image instead of centred. Rewriting the
  # two numbers on a throwaway copy gives one answer and a correctly centred
  # logo. The viewBox is left alone, which is what keeps the shape the shape.
  sed "s/width=\"64\" height=\"64\"/width=\"${SIZE}\" height=\"${SIZE}\"/" "$SRC" > "$tmp/logo.svg"
  if ! grep -q "width=\"${SIZE}\"" "$tmp/logo.svg"; then
    echo "ERROR: could not set the size on a copy of ${SRC}." >&2
    echo "       Its opening tag no longer says width=\"64\" height=\"64\"." >&2
    exit 1
  fi

  printf '%s' '<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:transparent}img{display:block}</style>
<img src="logo.svg" width="'"${SIZE}"'" height="'"${SIZE}"'">' > "$tmp/wrap.html"

  # --default-background-color=00000000 is what keeps the screenshot
  # transparent; without it Chrome paints white behind the page.
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --default-background-color=00000000 \
    --force-device-scale-factor=1 --virtual-time-budget=4000 \
    --window-size="$SIZE,$SIZE" --screenshot="$OUT" "file://$tmp/wrap.html" > /dev/null 2>&1
fi

echo "Wrote $OUT"
ls -la "$OUT"
echo
echo "Next: git add system_files/usr/share/aquarius/branding && git commit"
