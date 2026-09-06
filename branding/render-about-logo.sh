#!/usr/bin/env bash
# ==============================================================================
# Re-render the two AquariusOS "About" logos
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when you have changed branding/logo.svg, the wordmark text, or the
#   colours below. The finished PNGs are already committed, so a normal OS build
#   never runs this.
#
# HOW TO RUN IT (on the Mac, from anywhere):
#   bash branding/render-about-logo.sh
#
# WHAT THESE TWO PICTURES ARE FOR
#   GNOME's Settings > System > About page shows one big picture at the top. On
#   the first bench boot (2026-08-31) that picture said BAZZITE, even though the
#   line underneath it correctly said "Operating System: AquariusOS".
#
#   The reason is that on Fedora, the About page does NOT look the logo up by
#   name. Fedora compiles gnome-control-center with two FIXED FILE PATHS baked
#   into the program (see docs/gnome-variants.md for the full write-up):
#
#       light mode  →  /usr/share/pixmaps/fedora_logo_med.png
#       dark  mode  →  /usr/share/pixmaps/fedora_whitelogo_med.png
#
#   Bazzite brands its About page by replacing those two files with its own
#   artwork. We do exactly the same thing with ours, in build_files/gnome-desktop.sh.
#   This script draws the two pictures that get copied over them.
#
#   "White" in the filename describes THE INK, not the mode — same wording
#   Fedora uses. The white-ink one is the one you see in dark mode.
#
# WHICH MARK GOES ON WHICH PICTURE (decided 2026-09-06)
#   The About page does exactly one thing with these two files: it shows the
#   first one in light mode and the second one in dark mode. It does not tint
#   them, mask them, or ask them to be single-colour — it just picks one.
#
#   So the -white file is simply "the dark-mode picture", and the right thing to
#   put on it is the FULL-COLOUR MIDNIGHT MARK, not a flat white stamp of the
#   mark. Midnight is the colourway AquariusOS itself uses in dark mode: the
#   brighter blue (#00BFFF) and the brighter gold (#E6B947), drawn exactly so
#   they still carry on a dark ground. A white silhouette would be the one place
#   in the whole system where the logo loses its colour for no reason.
#
#   Only the WORD stays white on that picture — white text on a dark panel is
#   just legible text, and Sora has no colourway of its own.
#
#   The light picture gets the Ice mark and the word in Ice's ink, #16273A —
#   the same deep navy the desktop writes text in, which is what makes the
#   lockup look like it belongs to the rest of the interface rather than being
#   a black-and-blue sticker on it.
#
#   Before this, the script kept ONE dark-theme drawing and search-and-replaced
#   three hex codes in it to make the light one. That is gone: the mark now
#   ships as two finished drawings (branding/logo-ice.svg and
#   branding/logo-midnight.svg) and this script just picks the right one.
#
# WHY 279 x 80 PIXELS, WHICH LOOKS SMALL
#   Two reasons, and both are worth knowing before anybody "improves" it:
#
#   1. It is the exact size of the file we are replacing. Bazzite's is 279x80
#      and it renders correctly on the bench machine. Matching it means the
#      About page cannot suddenly lay out differently.
#   2. GNOME's About page is built as `Picture { can-shrink: false }` inside a
#      clamp 192 pixels tall. `can-shrink: false` means the picture DEMANDS at
#      least its own pixel size — so a wider picture would set a wider minimum
#      width for the whole Settings window, and Settings is meant to narrow down
#      to phone width. A tall one would fight the 192-pixel clamp.
#
#   So the picture is deliberately not high-resolution, and on a 4K screen it
#   will be as soft as Bazzite's and Fedora's are. That is a limitation of the
#   About page, not of our artwork. Do not "fix" it by shipping a bigger file.
#
# WHAT IT NEEDS
#   Google Chrome (already on the Mac). Same requirement as
#   branding/render-wallpaper.sh, for the same reason: Chrome is the only thing
#   on this machine that can draw text in a specific font file and screenshot it.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Two drawings of the same mark, one per colourway. Since 2026-09-06 the mark
# ships already coloured for both — there is no recolouring step here any more.
# See the note under "WHICH MARK GOES ON WHICH PICTURE" below.
MARK_ICE="$REPO_ROOT/branding/logo-ice.svg"
MARK_MIDNIGHT="$REPO_ROOT/branding/logo-midnight.svg"
FONT_TTF="$REPO_ROOT/system_files/usr/share/fonts/sora-fonts/Sora[wght].ttf"
OUT_DIR="$REPO_ROOT/system_files/usr/share/aquarius/branding"

# The finished picture size. See the long note above before changing these.
WIDTH=279
HEIGHT=80

# The wordmark. Sora is the AquariusOS display font (branding/tokens.md), and
# the font file itself ships in this repo, so the text below is drawn in exactly
# the same letterforms the OS uses everywhere else.
WORDMARK="AquariusOS"

for f in "$MARK_ICE" "$MARK_MIDNIGHT" "$FONT_TTF"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f is missing — cannot draw the logo without it." >&2
    exit 1
  fi
done

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$chrome" ]; then
  chrome="$(command -v google-chrome || command -v chromium || true)"
fi
if [ -z "$chrome" ] || [ ! -x "$chrome" ]; then
  echo "ERROR: Google Chrome was not found. It is what draws the text." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The font has to be reachable from inside the page, and its filename contains
# square brackets, which are awkward in a URL. Copying it next to the page under
# a plain name sidesteps the whole question.
cp "$FONT_TTF" "$tmp/Sora.ttf"

# ------------------------------------------------------------------------------
# render <output-png> <mark-svg-file> <ink-colour>
# ------------------------------------------------------------------------------
# The layout is done by the browser rather than by hand-placed coordinates. The
# mark and the word sit in one centred flex row, so the lockup is always
# perfectly centred no matter how wide the word turns out to be — which is the
# part you cannot work out on paper, because it depends on the font.
render() {
  local out="$1" mark="$2" ink="$3"

  cp "$mark" "$tmp/mark.svg"

  cat > "$tmp/page.html" <<HTML
<!doctype html><meta charset="utf-8">
<style>
  @font-face {
    font-family: "Sora";
    src: url("Sora.ttf") format("truetype");
    font-weight: 100 800;
  }
  html, body { margin:0; padding:0; overflow:hidden; background:transparent; }
  .row {
    width: ${WIDTH}px; height: ${HEIGHT}px;
    display: flex; align-items: center; justify-content: center;
    gap: 12px;
  }
  .row img { width: 58px; height: 58px; display:block; }
  .word {
    font-family: "Sora", sans-serif;
    font-weight: 600;
    font-size: 30px;
    letter-spacing: -0.02em;
    color: ${ink};
    line-height: 1;
    /* Sora's descenders ("q") sit below the baseline; nudging the word up by a
       hair optically centres it against the mark, which has none. */
    transform: translateY(-1px);
    white-space: nowrap;
  }
</style>
<div class="row"><img src="mark.svg"><span class="word">${WORDMARK}</span></div>
HTML

  # --default-background-color=00000000 is what keeps the picture transparent.
  # Without it Chrome paints white behind the page and the dark-mode About panel
  # would show a white rectangle around the logo.
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --default-background-color=00000000 \
    --force-device-scale-factor=1 --virtual-time-budget=6000 \
    --window-size="${WIDTH},${HEIGHT}" \
    --screenshot="$out" "file://$tmp/page.html" > /dev/null 2>&1

  if [ ! -s "$out" ]; then
    echo "ERROR: Chrome did not write $out." >&2
    exit 1
  fi
}

# The dark-mode picture: the Midnight mark, and the word in white.
render "$OUT_DIR/aquarius-about-logo-white.png" "$MARK_MIDNIGHT" "#FFFFFF"

# The light-mode picture: the Ice mark, and the word in Ice's own ink.
render "$OUT_DIR/aquarius-about-logo.png" "$MARK_ICE" "#16273A"

# Prove the two files really came out at the size the About page expects. A PNG
# of the wrong size is not a crash, it is a slightly wrong-looking page, which
# is exactly the kind of thing nobody notices.
python3 - "$WIDTH" "$HEIGHT" \
  "$OUT_DIR/aquarius-about-logo.png" \
  "$OUT_DIR/aquarius-about-logo-white.png" <<'PY'
import struct, sys

want_w, want_h = int(sys.argv[1]), int(sys.argv[2])
for path in sys.argv[3:]:
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"ERROR: {path} is not a PNG.")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (want_w, want_h):
        sys.exit(f"ERROR: {path} is {width}x{height}, expected {want_w}x{want_h}.")
    print(f"OK: {path} is {width}x{height} ({len(data)} bytes)")
PY

echo
echo "Next: look at both PNGs, then"
echo "      git add system_files/usr/share/aquarius/branding && git commit"
