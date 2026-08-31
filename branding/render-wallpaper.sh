#!/usr/bin/env bash
# ==============================================================================
# Re-render the AquariusOS wallpaper PNGs from their SVG sources
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when you have changed one of the SVG files in branding/wallpapers/.
#   The finished PNGs are already committed, so a normal OS build never runs
#   this.
#
# HOW TO RUN IT (on the Mac, from anywhere):
#   bash branding/render-wallpaper.sh          both lines
#   bash branding/render-wallpaper.sh gnome    only the GNOME wallpapers
#   bash branding/render-wallpaper.sh kde      only the KDE wallpaper
#
#   ⚠️ USE THE "gnome" ARGUMENT UNLESS YOU MEAN OTHERWISE. The KDE line is
#   frozen: its images are still published, but nothing about them is supposed
#   to change. Re-rendering its wallpaper would produce a byte-different PNG
#   from a picture nobody edited, which is exactly the kind of accidental drift
#   "frozen" is meant to prevent. Only pass "kde" if you have deliberately
#   changed the-pour.svg.
#
# WHAT IT DOES
#   Takes each SVG source and writes out the picture at every screen size that
#   line ships, straight into the place the OS reads them from. Then `git add`
#   those PNGs and commit — that is what makes them ship.
#
# WHAT IT NEEDS
#   Google Chrome (already on the Mac), OR rsvg-convert (`brew install librsvg`).
#   It prefers rsvg-convert if it finds it, because it is faster; otherwise it
#   quietly uses Chrome. You do not have to install anything.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/branding/wallpapers"

WHICH="${1:-all}"
case "$WHICH" in
  all | kde | gnome) : ;;
  *)
    echo "Usage: bash branding/render-wallpaper.sh [all|kde|gnome]" >&2
    exit 1
    ;;
esac

# ------------------------------------------------------------------------------
# The two ways of turning an SVG into a PNG
# ------------------------------------------------------------------------------
# Both take the same four things: width, height, the file to write, and the
# colour to paint behind the picture. The background colour matters because the
# artwork is drawn over its own filled rectangle — if a filter ever leaves a
# transparent pixel at the very edge, this is what shows through, and it should
# be the wallpaper's own ground rather than white or black.
SRC=""       # set per wallpaper, just before rendering
BGCOLOR=""   # set per wallpaper, just before rendering

render_rsvg() { # $1=w $2=h $3=outfile
  rsvg-convert --width="$1" --height="$2" --keep-aspect-ratio=false \
    --background-color="$BGCOLOR" --format=png --output="$3" "$SRC"
}

render_chrome() { # $1=w $2=h $3=outfile
  local chrome tmp
  chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$chrome" ] || chrome="$(command -v google-chrome || command -v chromium || true)"
  if [ -z "$chrome" ] || [ ! -x "$chrome" ]; then
    echo "ERROR: no Google Chrome and no rsvg-convert. Install one and re-run." >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  cp "$SRC" "$tmp/art.svg"
  cat > "$tmp/wrap.html" <<HTML
<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:${BGCOLOR};width:100%;height:100%}
img{display:block;width:100vw;height:100vh}</style>
<img src="art.svg">
HTML
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --virtual-time-budget=4000 \
    --window-size="$1,$2" --screenshot="$3" "file://$tmp/wrap.html" > /dev/null 2>&1
  rm -rf "$tmp"
}

render() {
  if command -v rsvg-convert > /dev/null 2>&1; then render_rsvg "$@"; else render_chrome "$@"; fi
}

# ==============================================================================
# The KDE line — one wallpaper, three sizes, plus a picker thumbnail
# ==============================================================================
# 16:9 for normal monitors, 1280x800 for 16:10 laptops and handhelds. The
# artwork runs off the edge of the frame on purpose, so cropping to a different
# shape never leaves a blank strip.
#
# KDE wants a whole folder with a fixed layout ("a wallpaper package"), which is
# why these land under /usr/share/wallpapers/AquariusThePour/ and why there is a
# screenshot.png next to them for the wallpaper picker.
# ------------------------------------------------------------------------------
render_kde() {
  SRC="$SRC_DIR/the-pour.svg"
  BGCOLOR="#06070C"
  local out="$REPO_ROOT/system_files/usr/share/wallpapers/AquariusThePour/contents"
  mkdir -p "$out/images"

  for size in 3840x2160 1920x1080 1280x800; do
    echo "rendering KDE ${size} ..."
    render "${size%x*}" "${size#*x}" "$out/images/${size}.png"
  done

  echo "rendering KDE preview thumbnail ..."
  render 960 540 "$out/screenshot.png"
}

# ==============================================================================
# The GNOME line — two colourways, one size each
# ==============================================================================
# GNOME does not use wallpaper packages. It reads a plain picture file from a
# path written into a settings file, and it wants exactly two of them: one for
# the light appearance and one for the dark. Those two paths are in
# system_files/usr/share/glib-2.0/schemas/zz1-aquarius-10-look.gschema.override
# and in system_files/usr/share/gnome-background-properties/aquarius.xml.
#
# ⚠️ IF YOU RENAME A FILE HERE, RENAME IT IN BOTH OF THOSE TOO. The build checks
# that they agree (build_files/gnome-desktop.sh), so a half-done rename is a
# failed build rather than a desktop that comes up a flat colour.
#
# ONE SIZE, NOT THREE, AND THAT IS DELIBERATE. GNOME scales a wallpaper to fit
# whatever screen it finds, and it does it well. Shipping 4K only means one file
# per colourway instead of three, which keeps the image smaller, and a 4K source
# scaled down always looks better than a 1080p source scaled up.
# ------------------------------------------------------------------------------
render_gnome() {
  local out="$REPO_ROOT/system_files/usr/share/backgrounds/aquarius"
  mkdir -p "$out"

  SRC="$SRC_DIR/the-pour-ice.svg"
  BGCOLOR="#EAF1F8"
  echo "rendering GNOME Ice (light) 3840x2160 ..."
  render 3840 2160 "$out/the-pour-ice-3840x2160.png"

  SRC="$SRC_DIR/the-pour-midnight.svg"
  BGCOLOR="#0B1220"
  echo "rendering GNOME Midnight (dark) 3840x2160 ..."
  render 3840 2160 "$out/the-pour-midnight-3840x2160.png"
}

case "$WHICH" in
  kde) render_kde ;;
  gnome) render_gnome ;;
  all)
    render_kde
    render_gnome
    ;;
esac

echo
echo "Done."
echo "Next: git add system_files/usr/share/wallpapers system_files/usr/share/backgrounds && git commit"
