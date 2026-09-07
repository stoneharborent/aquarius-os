#!/usr/bin/env bash
# ==============================================================================
# Draw the pictures for the AquariusOS boot animation (Plymouth)
# ==============================================================================
# WHEN YOU NEED THIS
#   Only when you want to CHANGE the boot animation — the shapes, the timing, the
#   colours, or the little bits of furniture on the update and password screens.
#   The finished pictures are already committed, so a normal OS build never runs
#   this script.
#
# HOW TO RUN IT (on the Mac, from anywhere):
#   npm --prefix branding/icons install     # once, ever — see WHAT IT NEEDS
#   bash branding/render-plymouth-assets.sh
#
#   It takes about four minutes. Then look at the pictures it wrote, and
#   commit them:
#   git add system_files/usr/share/plymouth/themes/aquarius && git commit
#
# ------------------------------------------------------------------------------
# WHAT THE BOOT ANIMATION IS
# ------------------------------------------------------------------------------
# It is the screen you see for the few seconds between choosing AquariusOS in the
# boot menu and the login screen appearing, and again for the couple of seconds
# after you choose Shut Down. The program that draws it is called Plymouth, and
# Plymouth draws whatever a "theme" gives it. Ours is called `aquarius` and lives
# at /usr/share/plymouth/themes/aquarius/ on the finished machine.
#
# THE ANIMATION ITSELF is a stack of still pictures played one after another, 30
# a second — the same way any moving picture works. This script's main job is to
# draw those stills:
#
#   boot-0001.png … boot-0066.png       THE POUR. 2.2 seconds. A stream of water
#                                       falls from above the screen, the "A" is
#                                       poured out of it, and the word
#                                       "AquariusOS" fades in underneath.
#
#   hold.png                            What stays on screen after the pour has
#                                       finished, until the login screen takes
#                                       over. It is the pour's last frame — and
#                                       this script proves the two files are
#                                       identical, because a hold that is even
#                                       one pixel different from the frame before
#                                       it shows up as a flicker.
#
#   shutdown-0001.png … shutdown-0057.png
#                                       THE WIND. 1.9 seconds. The word fades,
#                                       then the wind takes the mark apart and
#                                       blows it off to the right in drops.
#
# The SHAPES in those frames are not decided here. They come from
# branding/pour.mjs, which is the animation itself written down as arithmetic —
# read that file's header if you want to know what happens when. This script's
# job is to turn each of its frames into a picture file.
#
# THE FURNITURE is the other four pictures, and they are plain shapes rather than
# animation:
#
#   box.png         the 420x48 rounded box you type a disk password into
#   bullet.png      one dot, one per character you type
#   bar-track.png   the empty progress bar on the "installing updates" screen
#   bar-fill.png    the blue that fills it (the boot screen's own script
#                   squeezes this one narrower to show how far along it is)
#
# ------------------------------------------------------------------------------
# WHY THESE SIZES, AND WHY THERE IS NO SECOND, LARGER SET
# ------------------------------------------------------------------------------
# Plymouth draws a theme's pictures at their own pixel size. It does not scale
# them up to fill a big screen, and it does not shrink them to fit a small one.
#
# That was worth checking rather than assuming, because Plymouth DOES know about
# high-density screens in general — it works out a "device scale" of 2 on a very
# dense panel. So the question was whether we owed it a second set of pictures at
# twice the size. Reading Plymouth 24.004.60's own source code (the version
# Fedora 44 ships), the answer is no, twice over:
#
#   * The plug-in that draws our theme — the `script` plug-in — never touches
#     device scale at all. The words do not appear anywhere in its source.
#   * There is no way to give it two sets even if we wanted to. A picture is
#     loaded by file name and drawn; there is no "and use this one on a dense
#     screen" anywhere in the interface it offers.
#
# So: one set, at one-times, and the numbers below are a compromise that has to
# read correctly on both ends of the range Royce actually uses:
#
#   1280 x 800   a small laptop panel
#   3840 x 2160  the 4K monitor on the bench machine
#
# A 288-pixel-wide frame is a confident, centred mark on the small screen and a
# modest one on the big screen. Both look deliberate.
#
# ------------------------------------------------------------------------------
# WHAT IT NEEDS
# ------------------------------------------------------------------------------
# Two things, both already on the Mac.
#
#   Google Chrome   is what turns a drawing into a picture file. Same tool, for
#                   the same reason, as branding/render-about-logo.sh: it is the
#                   only thing on this machine that reliably draws SVG and
#                   screenshots the result.
#
#   Node            runs branding/pour.mjs, which works out the shapes. It needs
#                   one small library, `fontkit`, to read the Sora font file and
#                   turn the word "AquariusOS" into an outline — so that the
#                   finished pictures contain a SHAPE and nothing at boot time
#                   ever has to go looking for a font. Install it once with:
#
#                       npm --prefix branding/icons install
#
#                   The downloaded folder is not committed; the lock file is.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POUR_MJS="$REPO_ROOT/branding/pour.mjs"
FONT_TTF="$REPO_ROOT/system_files/usr/share/fonts/sora-fonts/Sora[wght].ttf"
COLOUR_TOOL="$REPO_ROOT/branding/png-colours.py"
OUT_DIR="$REPO_ROOT/system_files/usr/share/plymouth/themes/aquarius"

# ------------------------------------------------------------------------------
# The numbers. All of them, in one place.
# ------------------------------------------------------------------------------
# ⚠️ THESE MUST MATCH THREE OTHER FILES: branding/pour.mjs (which draws the
# frames), the boot screen's own script in
# system_files/usr/share/plymouth/themes/aquarius/aquarius.script (which plays
# them), and the checks in build_files/80-boot-branding.sh. Change one, change
# all four. Every one of them says so.
FRAME_W=288
FRAME_H=389
BOOT_FRAMES=66      # 2.2 seconds at 30 pictures a second
WIND_FRAMES=57      # 1.9 seconds

# The furniture, from the approved design.
BOX_W=420           # the disk-password box
BOX_H=48
BOX_RADIUS=12
BULLET_PX=18        # one dot per typed character, and the space it sits in
DOT_PX=8            # how big the dot inside it is
BAR_W=320           # the progress bar on the update screen
BAR_H=3

# ------------------------------------------------------------------------------
# The colours, copied out of branding/tokens.md — the MIDNIGHT column
# ------------------------------------------------------------------------------
# The boot screen is a dark screen, so it uses the Midnight half of the palette,
# the same one the desktop shows in dark mode. Never picked by eye.
#
# (The frames themselves get their colours from branding/pour.mjs, which has its
# own copy of the same list. These four are only for the furniture below.)
SURFACE="#121C2E"       # Midnight `surface` — the inside of the password box
HAIRLINE="rgba(220,243,255,.16)"  # the one-pixel line around it
SURFACE_ALT="#1B2940"   # Midnight `surfaceAlt` — the empty part of the bar
ACCENT="#00BFFF"        # Midnight `aquariusBlue` — the filled part
INK="#DCE9F4"           # Midnight `ink` — the typed dots

# Colours that have been RETIRED from the palette. No picture this script writes
# may contain any of them. See branding/tokens.md.
RETIRED="8AB4FF,5B4BE0,E6DDB8,06070C"

# ------------------------------------------------------------------------------
# Check the tools are here before doing anything
# ------------------------------------------------------------------------------
for f in "$POUR_MJS" "$FONT_TTF" "$COLOUR_TOOL"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f is missing — cannot draw the boot animation without it." >&2
        exit 1
    fi
done

if ! command -v node > /dev/null 2>&1; then
    echo "ERROR: Node is not installed. It works out the shapes of the frames." >&2
    echo "       Install it from https://nodejs.org (the LTS version)." >&2
    exit 1
fi

if [ ! -d "$REPO_ROOT/branding/icons/node_modules/fontkit" ]; then
    echo "ERROR: the fontkit library is not downloaded yet. It is what reads the" >&2
    echo "       Sora font file and turns the word 'AquariusOS' into a shape." >&2
    echo "       Run this once, then try again:" >&2
    echo "           npm --prefix branding/icons install" >&2
    exit 1
fi

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$chrome" ]; then
    chrome="$(command -v google-chrome || command -v chromium || true)"
fi
if [ -z "$chrome" ] || [ ! -x "$chrome" ]; then
    echo "ERROR: Google Chrome was not found. It is what draws the pictures." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ------------------------------------------------------------------------------
# shoot <page.html> <out.png> <width> <height>
# ------------------------------------------------------------------------------
# --default-background-color=00000000 is what keeps the picture TRANSPARENT.
# Without it Chrome paints white behind the page, and every frame of the
# animation would have a white rectangle around it — the boot screen paints its
# own Midnight ground behind these, so they must have none of their own.
#
# ⚠️ ONE PICTURE AT A TIME, ON PURPOSE. Chrome takes about two seconds to start
# up and a fraction of a second to do the actual work, so running several at once
# is tempting — but several headless copies of Chrome on one Mac get in each
# other's way and hang, which was tried on 2026-09-06 and abandoned. Two seconds
# times a hundred and twenty-four pictures is about four minutes, once, on a
# script that is run perhaps twice a year.
shoot() {
    local page="$1" out="$2" w="$3" h="$4"
    "$chrome" --headless --disable-gpu --hide-scrollbars \
        --default-background-color=00000000 \
        --force-device-scale-factor=1 --virtual-time-budget=1000 \
        --window-size="${w},${h}" \
        --screenshot="$out" "file://${page}" > /dev/null 2>&1
    if [ ! -s "$out" ]; then
        echo "ERROR: Chrome did not write $out." >&2
        exit 1
    fi
}

# ==============================================================================
# 1. THE ANIMATION FRAMES
# ==============================================================================
echo "Working out the shape of every frame…"
node "$POUR_MJS" --out "$tmp/frames" --size "$FRAME_W"

echo
echo "Drawing $((BOOT_FRAMES + WIND_FRAMES + 1)) frames with Chrome, one at a time."
echo "This is the slow part — about four minutes. A dot is one frame."

rm -f "$OUT_DIR"/boot-*.png "$OUT_DIR"/shutdown-*.png "$OUT_DIR"/hold.png
# The old two-step theme's pictures. They are not used by the animation and
# leaving them behind would put dead weight in the boot ramdisk.
rm -f "$OUT_DIR"/throbber-*.png "$OUT_DIR"/watermark.png

shoot_frame() {   # shoot_frame <name-without-extension>
    shoot "$tmp/frames/$1.html" "$OUT_DIR/$1.png" "$FRAME_W" "$FRAME_H"
    printf '.'
}

for i in $(seq 1 "$BOOT_FRAMES"); do
    shoot_frame "$(printf 'boot-%04d' "$i")"
done
echo " the pour"
for i in $(seq 1 "$WIND_FRAMES"); do
    shoot_frame "$(printf 'shutdown-%04d' "$i")"
done
echo " the wind"
shoot_frame hold
echo " the hold"

# ==============================================================================
# 2. THE FURNITURE
# ==============================================================================
# Four plain shapes. They are drawn with a web page rather than by hand because
# a rounded corner and a one-pixel semi-transparent line are both things a
# browser gets exactly right and arithmetic gets nearly right.
echo
echo "Drawing the password box, the typed dot and the progress bar…"

cat > "$tmp/box.html" << HTML
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;overflow:hidden;background:transparent}
  .box{
    width:$((BOX_W - 2))px; height:$((BOX_H - 2))px;
    border-radius:${BOX_RADIUS}px;
    background:${SURFACE};
    border:1px solid ${HAIRLINE};
    box-sizing:content-box;
  }
</style>
<div class="box"></div>
HTML
shoot "$tmp/box.html" "$OUT_DIR/box.png" "$BOX_W" "$BOX_H"

cat > "$tmp/bullet.html" << HTML
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;overflow:hidden;background:transparent}
  .slot{width:${BULLET_PX}px;height:${BULLET_PX}px;display:flex;align-items:center;justify-content:center}
  .dot{width:${DOT_PX}px;height:${DOT_PX}px;border-radius:50%;background:${INK}}
</style>
<div class="slot"><span class="dot"></span></div>
HTML
shoot "$tmp/bullet.html" "$OUT_DIR/bullet.png" "$BULLET_PX" "$BULLET_PX"

# The two halves of the progress bar. Both are the FULL width: the boot screen's
# own script squeezes the blue one narrower every time the percentage changes,
# which is how a bar fills up when there is no way to draw a rectangle at run
# time.
for pair in "bar-track:${SURFACE_ALT}" "bar-fill:${ACCENT}"; do
    name="${pair%%:*}"
    colour="${pair##*:}"
    cat > "$tmp/${name}.html" << HTML
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;overflow:hidden;background:transparent}
  .bar{width:${BAR_W}px;height:${BAR_H}px;background:${colour}}
</style>
<div class="bar"></div>
HTML
    shoot "$tmp/${name}.html" "$OUT_DIR/${name}.png" "$BAR_W" "$BAR_H"
done

# ==============================================================================
# 3. PROVE THE PICTURES ARE WHAT THEY HAVE TO BE
# ==============================================================================
# A picture of the wrong size is not a crash. It is a slightly wrong-looking boot
# screen, which is exactly the kind of thing nobody notices — so everything below
# is read back out of the finished files rather than assumed.
echo
echo "== Checking the finished pictures =="

python3 - "$OUT_DIR" "$FRAME_W" "$FRAME_H" "$BOOT_FRAMES" "$WIND_FRAMES" \
    "$BOX_W" "$BOX_H" "$BULLET_PX" "$BAR_W" "$BAR_H" << 'PY'
import glob
import os
import struct
import sys

(out_dir, frame_w, frame_h, boot_frames, wind_frames,
 box_w, box_h, bullet_px, bar_w, bar_h) = (
    sys.argv[1], *(int(a) for a in sys.argv[2:11]))


def size(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"ERROR: {path} is not a PNG.")
    return (*struct.unpack(">II", data[16:24]), len(data))


def check_run(prefix, count):
    """Every frame present, numbered with no gaps, all the same size."""
    found = sorted(glob.glob(os.path.join(out_dir, f"{prefix}-*.png")))
    if len(found) != count:
        sys.exit(f"ERROR: {len(found)} {prefix} frames on disk, expected {count}.")
    total = 0
    for i, path in enumerate(found, start=1):
        want = f"{prefix}-{i:04d}.png"
        if os.path.basename(path) != want:
            sys.exit(f"ERROR: expected {want}, found {os.path.basename(path)}. "
                     "The frames must be numbered with no gaps — the boot "
                     "screen's script counts up from 0001 and a missing number "
                     "is a picture that never appears.")
        w, h, n = size(path)
        if (w, h) != (frame_w, frame_h):
            sys.exit(f"ERROR: {want} is {w}x{h}, expected {frame_w}x{frame_h}.")
        total += n
    print(f"OK: {count} {prefix} frames, all {frame_w}x{frame_h} ({total:,} bytes total)")


check_run("boot", boot_frames)
check_run("shutdown", wind_frames)

# The hold. It has to be the pour's last frame EXACTLY — a hold that differs by
# one pixel is a visible flicker at the moment the animation stops.
last = os.path.join(out_dir, f"boot-{boot_frames:04d}.png")
hold = os.path.join(out_dir, "hold.png")
if open(hold, "rb").read() != open(last, "rb").read():
    sys.exit(f"ERROR: hold.png is not byte-for-byte the same as "
             f"boot-{boot_frames:04d}.png. The animation would flicker when it "
             "stops. Both are drawn from the same moment in branding/pour.mjs, "
             "so a difference means Chrome did not draw the same thing twice.")
print(f"OK: hold.png is byte-for-byte boot-{boot_frames:04d}.png (no flicker at the end)")

for name, want_w, want_h in [
    ("box.png", box_w, box_h),
    ("bullet.png", bullet_px, bullet_px),
    ("bar-track.png", bar_w, bar_h),
    ("bar-fill.png", bar_w, bar_h),
]:
    w, h, n = size(os.path.join(out_dir, name))
    if (w, h) != (want_w, want_h):
        sys.exit(f"ERROR: {name} is {w}x{h}, expected {want_w}x{want_h}.")
    print(f"OK: {name} is {w}x{h} ({n} bytes)")

# Nothing from the old two-step theme may be left behind.
for stale in glob.glob(os.path.join(out_dir, "throbber-*.png")) + \
             glob.glob(os.path.join(out_dir, "watermark.png")):
    sys.exit(f"ERROR: {stale} is left over from the old boot screen. Delete it.")
print("OK: none of the old boot screen's pictures are left in the folder")
PY

# ------------------------------------------------------------------------------
# The colours in the pictures — read out of the pixels, not out of this file
# ------------------------------------------------------------------------------
# This is the check that a settings file cannot do. When a colour is retired from
# the palette it has to disappear from the PICTURES as well, and the only way to
# know is to open them and look. branding/png-colours.py does exactly that.
echo
echo "== Checking the colours in the pixels =="
if python3 "$COLOUR_TOOL" --forbid "$RETIRED" "$OUT_DIR"/boot-*.png "$OUT_DIR"/shutdown-*.png "$OUT_DIR"/hold.png; then
    echo "OK: no retired colour appears in any of the $((BOOT_FRAMES + WIND_FRAMES + 1)) frames"
else
    echo "ERROR: a retired colour is still in the animation (see above)." >&2
    exit 1
fi

# And the two colours that MUST be there, proved the same way round. A progress
# bar drawn in nearly-the-right blue looks fine and is wrong.
python3 "$COLOUR_TOOL" --require "$ACCENT" "$OUT_DIR/bar-fill.png"
python3 "$COLOUR_TOOL" --require "$SURFACE_ALT" "$OUT_DIR/bar-track.png"
python3 "$COLOUR_TOOL" --require "$SURFACE" "$OUT_DIR/box.png"
echo "OK: the bar and the box really are the Midnight colours they are meant to be"

echo
echo "Wrote into ${OUT_DIR}:"
echo "  ${BOOT_FRAMES} pour frames, ${WIND_FRAMES} wind frames, 1 hold frame"
echo "  box.png, bullet.png, bar-track.png, bar-fill.png"
echo
echo "Next: look at a few of them, then"
echo "      git add system_files/usr/share/plymouth/themes/aquarius && git commit"
echo
echo "To watch the animation before committing, open the frames in Preview and"
echo "hold the down arrow — or just push and watch it on the bench."
