#!/usr/bin/env bash
# ==============================================================================
# Draw the pictures for the AquariusOS boot splash (Plymouth)
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when you want to CHANGE the boot splash — the logo, the word, the
#   colours, or the little row of dots. The finished pictures are already
#   committed, so a normal OS build never runs this script.
#
# HOW TO RUN IT (on the Mac, from anywhere):
#   bash branding/render-plymouth-assets.sh
#
#   Then look at the pictures it wrote, and commit them:
#   git add system_files/usr/share/plymouth/themes/aquarius && git commit
#
# ------------------------------------------------------------------------------
# WHAT THE BOOT SPLASH IS
# ------------------------------------------------------------------------------
# It is the screen you see for the few seconds between choosing AquariusOS in
# the boot menu and the login screen appearing. The program that draws it is
# called Plymouth, and Plymouth draws whatever pictures its "theme" gives it.
#
# Our theme is called `aquarius` and it lives at
# /usr/share/plymouth/themes/aquarius/ on the finished machine. This script
# draws the two kinds of picture that go in it:
#
#   watermark.png          the AquariusOS mark with the word "AquariusOS"
#                          underneath it. This is the still picture in the
#                          middle of the screen. ONE file — if you only want to
#                          change what the boot screen looks like, change this.
#
#   throbber-0001.png      thirty-six frames of three dots, with a soft pulse
#   … throbber-0036.png    travelling left to right. Plymouth plays them in a
#                          loop underneath the mark, so the screen is visibly
#                          alive while the machine starts.
#
# The design this follows is the "Boot to desktop · one journey" strip in
# branding/design-system/AquariusOS Core Identity.html, step 02: the mark
# centred on near-black with a soft glow, and three dots below it. Royce also
# asked, in as many words, that the boot screen SAY Aquarius — so the word is
# part of the picture rather than the mark on its own.
#
# ------------------------------------------------------------------------------
# WHY THESE SIZES
# ------------------------------------------------------------------------------
# Plymouth draws a theme's pictures at their own pixel size. It does not scale
# them up to fill a big screen, and it does not shrink them to fit a small one.
# So the size below is a compromise that has to read correctly on both ends of
# the range Royce actually uses:
#
#   1280 x 800   a handheld or a small laptop panel
#   3840 x 2160  the 4K monitor on the bench machine
#
# A 640-pixel-wide picture is half the width of the small screen and a sixth of
# the width of the 4K one. On the small screen that is a confident, centred
# logo; on the 4K screen it is a modest one. Both look deliberate. Going much
# bigger would crowd the small screen, and going smaller would vanish on the
# big one.
#
# (Plymouth does know about high-density screens — it sets a "device scale" of 2
# on very large panels, which doubles the effective size of everything — so in
# practice the 4K result sits between those two numbers. There is no way to give
# it two different pictures for two different screens, which is why one
# compromise size is the whole answer.)
#
# ------------------------------------------------------------------------------
# WHAT IT NEEDS
# ------------------------------------------------------------------------------
# Google Chrome (already on the Mac). Same requirement, for the same reason, as
# branding/render-about-logo.sh: Chrome is the only thing on this machine that
# can draw text in a specific font file and screenshot the result. The dots are
# drawn by Chrome too, so that this whole script needs exactly one tool.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARK_SVG="$REPO_ROOT/branding/logo.svg"
FONT_TTF="$REPO_ROOT/system_files/usr/share/fonts/sora-fonts/Sora[wght].ttf"
OUT_DIR="$REPO_ROOT/system_files/usr/share/plymouth/themes/aquarius"

# ------------------------------------------------------------------------------
# The numbers. All of them, in one place.
# ------------------------------------------------------------------------------
# The still picture in the middle of the screen.
LOCKUP_W=640
LOCKUP_H=288
MARK_PX=176   # how tall the mark is drawn
WORD_PX=46    # how tall the word "AquariusOS" is drawn
WORDMARK="AquariusOS"

# The row of dots. They are deliberately bigger than the design sketch: on the
# sketch they are 4 pixels on a 200-pixel-wide artboard, but on a real 1280-wide
# screen 4 pixels is invisible. 12 across, 44 apart reads as "something is
# happening" from a normal sitting distance without ever shouting.
DOTS_W=120
DOTS_H=20
DOT_PX=12     # diameter of one dot
DOT_GAP=44    # centre-to-centre distance between dots
FRAMES=36     # how many pictures make one loop

# Colours, copied out of branding/tokens.md. Never picked by eye.
INK="#FFFFFF"        # text-1 — the word, on a near-black screen
STARLIGHT="#8AB4FF"  # the accent, and the colour of the dots
GLOW="rgba(138,180,255,.45)"

for f in "$MARK_SVG" "$FONT_TTF"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f is missing — cannot draw the boot splash without it." >&2
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

# The font file's name has square brackets in it, which are awkward inside a
# URL. Copying it next to the page under a plain name sidesteps the question.
cp "$FONT_TTF" "$tmp/Sora.ttf"
cp "$MARK_SVG" "$tmp/mark.svg"

# ------------------------------------------------------------------------------
# shoot <page.html> <out.png> <width> <height>
# ------------------------------------------------------------------------------
# --default-background-color=00000000 is what keeps the picture transparent.
# Without it Chrome paints white behind the page, and the boot screen would show
# a white rectangle around the logo.
shoot() {
    local page="$1" out="$2" w="$3" h="$4"
    "$chrome" --headless --disable-gpu --hide-scrollbars \
        --default-background-color=00000000 \
        --force-device-scale-factor=1 --virtual-time-budget=6000 \
        --window-size="${w},${h}" \
        --screenshot="$out" "file://${page}" > /dev/null 2>&1
    if [ ! -s "$out" ]; then
        echo "ERROR: Chrome did not write $out." >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 1. The still picture: the mark, and the word under it
# ------------------------------------------------------------------------------
# The layout is done by the browser rather than by hand-placed coordinates, so
# the lockup stays centred no matter how wide the word turns out to be — which
# is the part you cannot work out on paper, because it depends on the font.
echo "Drawing the mark and the word…"

cat > "$tmp/lockup.html" << HTML
<!doctype html><meta charset="utf-8">
<style>
  @font-face {
    font-family: "Sora";
    src: url("Sora.ttf") format("truetype");
    font-weight: 100 800;
  }
  html, body { margin:0; padding:0; overflow:hidden; background:transparent; }
  .stack {
    width: ${LOCKUP_W}px; height: ${LOCKUP_H}px;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 22px;
  }
  /* The glow is the "accent glow" token from branding/tokens.md, opened up a
     little because it has to survive being drawn on a near-black screen rather
     than on a panel. */
  .stack img {
    width: ${MARK_PX}px; height: ${MARK_PX}px; display:block;
    filter: drop-shadow(0 0 28px ${GLOW});
  }
  .word {
    font-family: "Sora", sans-serif;
    font-weight: 600;
    font-size: ${WORD_PX}px;
    letter-spacing: -0.02em;
    color: ${INK};
    line-height: 1;
    white-space: nowrap;
  }
</style>
<div class="stack"><img src="mark.svg"><span class="word">${WORDMARK}</span></div>
HTML

shoot "$tmp/lockup.html" "$OUT_DIR/watermark.png" "$LOCKUP_W" "$LOCKUP_H"

# ------------------------------------------------------------------------------
# 2. The dots
# ------------------------------------------------------------------------------
# One picture per frame. Each dot's brightness follows a smooth wave, and the
# three waves are a third of a cycle apart, so the bright spot appears to travel
# from left to right and then start again. Nothing blinks on or off; it is a
# pulse, not a flash, which is the "quick and calm" rule in tokens.md.
echo "Drawing ${FRAMES} frames of dots…"

rm -f "$OUT_DIR"/throbber-*.png

# Work out every frame's three opacities in one go, because bash cannot do
# decimals. cos(...) raised to a power makes the bright spot narrow and the dim
# tail long, which reads as travelling rather than as flickering. One line per
# frame, three numbers on it.
python3 - "$FRAMES" > "$tmp/opacities.txt" << 'PY'
import math
import sys

frames = int(sys.argv[1])
for frame in range(1, frames + 1):
    phase = (frame - 1) / frames
    row = []
    for dot in range(3):
        lit = max(0.0, math.cos(2 * math.pi * (phase - dot / 3.0))) ** 2.2
        row.append(f"{0.20 + 0.80 * lit:.4f}")
    print(" ".join(row))
PY

i=0
while read -r o1 o2 o3; do
    i=$((i + 1))

    cat > "$tmp/dots.html" << HTML
<!doctype html><meta charset="utf-8">
<style>
  html, body { margin:0; padding:0; overflow:hidden; background:transparent; }
  .row {
    width: ${DOTS_W}px; height: ${DOTS_H}px;
    display: flex; align-items: center; justify-content: center;
    gap: $((DOT_GAP - DOT_PX))px;
  }
  .row span {
    width: ${DOT_PX}px; height: ${DOT_PX}px;
    border-radius: 50%;
    background: ${STARLIGHT};
    display: block;
  }
</style>
<div class="row">
  <span style="opacity:${o1}"></span>
  <span style="opacity:${o2}"></span>
  <span style="opacity:${o3}"></span>
</div>
HTML

    # ⚠️ The four-digit numbering matters. Plymouth looks for throbber-0001,
    # then throbber-0002, and stops at the first one it cannot find — so a
    # differently-padded name silently shortens the loop.
    frame_name="$(printf 'throbber-%04d.png' "$i")"
    shoot "$tmp/dots.html" "$OUT_DIR/${frame_name}" "$DOTS_W" "$DOTS_H"
done < "$tmp/opacities.txt"

# ------------------------------------------------------------------------------
# 3. Prove the pictures came out at the sizes the theme expects
# ------------------------------------------------------------------------------
# A picture of the wrong size is not a crash. It is a slightly wrong-looking
# boot screen, which is exactly the kind of thing nobody notices — so the sizes
# are read back out of the finished files rather than assumed.
echo
python3 - "$OUT_DIR" "$LOCKUP_W" "$LOCKUP_H" "$DOTS_W" "$DOTS_H" "$FRAMES" << 'PY'
import glob
import os
import struct
import sys

out_dir, lw, lh, dw, dh, frames = sys.argv[1], *(int(a) for a in sys.argv[2:7])


def size(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"ERROR: {path} is not a PNG.")
    return (*struct.unpack(">II", data[16:24]), len(data))


w, h, n = size(os.path.join(out_dir, "watermark.png"))
if (w, h) != (lw, lh):
    sys.exit(f"ERROR: watermark.png is {w}x{h}, expected {lw}x{lh}.")
print(f"OK: watermark.png is {w}x{h} ({n} bytes)")

found = sorted(glob.glob(os.path.join(out_dir, "throbber-*.png")))
if len(found) != frames:
    sys.exit(f"ERROR: {len(found)} throbber frames on disk, expected {frames}.")
total = 0
for i, path in enumerate(found, start=1):
    want = f"throbber-{i:04d}.png"
    if os.path.basename(path) != want:
        sys.exit(f"ERROR: expected {want}, found {os.path.basename(path)}. "
                 "The frames must be numbered with no gaps or Plymouth stops "
                 "the loop at the first missing one.")
    w, h, n = size(path)
    if (w, h) != (dw, dh):
        sys.exit(f"ERROR: {want} is {w}x{h}, expected {dw}x{dh}.")
    total += n
print(f"OK: {len(found)} throbber frames, all {dw}x{dh} ({total} bytes total)")
PY

echo
echo "Wrote:"
ls -la "$OUT_DIR"/watermark.png
echo "  … and $(find "$OUT_DIR" -name 'throbber-*.png' | wc -l | tr -d ' ') throbber frames"
echo
echo "Next: look at watermark.png, then"
echo "      git add system_files/usr/share/plymouth/themes/aquarius && git commit"
