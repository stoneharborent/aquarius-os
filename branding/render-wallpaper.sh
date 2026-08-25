#!/usr/bin/env bash
# ==============================================================================
# Re-render the AquariusOS wallpaper PNGs from the SVG source
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when you have changed branding/wallpapers/the-pour.svg. The finished
#   PNGs are already committed, so a normal OS build never runs this.
#
# HOW TO RUN IT (on the Mac, from anywhere):
#   bash branding/render-wallpaper.sh
#
# WHAT IT DOES
#   Takes the one SVG source file and writes out the picture at every screen
#   size AquariusOS ships, straight into the place the OS reads them from:
#   system_files/usr/share/wallpapers/AquariusThePour/contents/images/
#
#   Then `git add` those PNGs and push — that is what makes them ship.
#
# WHAT IT NEEDS
#   Google Chrome (already on the Mac), OR rsvg-convert (`brew install librsvg`).
#   It prefers rsvg-convert if it finds it, because it is faster; otherwise it
#   quietly uses Chrome. You do not have to install anything.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/branding/wallpapers/the-pour.svg"
OUT="$REPO_ROOT/system_files/usr/share/wallpapers/AquariusThePour/contents"

# The sizes AquariusOS ships. 16:9 for normal monitors, 1280x800 for 16:10
# laptops and handhelds. The artwork runs off the edge of the frame on purpose,
# so cropping to a different shape never leaves a blank strip.
SIZES=("3840x2160" "1920x1080" "1280x800")

mkdir -p "$OUT/images"

render_rsvg() { # $1=w $2=h $3=outfile
  rsvg-convert --width="$1" --height="$2" --keep-aspect-ratio=false \
    --background-color="#06070C" --format=png --output="$3" "$SRC"
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
  cat > "$tmp/wrap.html" <<'HTML'
<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:#06070C;width:100%;height:100%}
img{display:block;width:100vw;height:100vh}</style>
<img src="art.svg">
HTML
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --virtual-time-budget=4000 \
    --window-size="$1,$2" --screenshot="$3" "file://$tmp/wrap.html" >/dev/null 2>&1
  rm -rf "$tmp"
}

render() {
  if command -v rsvg-convert >/dev/null 2>&1; then render_rsvg "$@"; else render_chrome "$@"; fi
}

for size in "${SIZES[@]}"; do
  w="${size%x*}"; h="${size#*x}"
  echo "rendering ${size} ..."
  render "$w" "$h" "$OUT/images/${size}.png"
done

# The little preview thumbnail KDE shows in the wallpaper picker.
echo "rendering preview thumbnail ..."
render 960 540 "$OUT/screenshot.png"

echo
echo "Done. Files written to:"
ls -la "$OUT/images" "$OUT/screenshot.png"
echo
echo "Next: git add system_files/usr/share/wallpapers && git commit && git push"
