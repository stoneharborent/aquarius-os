#!/usr/bin/python3
# ==============================================================================
# aq-game-mode-icon.py — put the controller badge on Steam's icon
# ==============================================================================
# Run by build_files/71-game-mode.sh, inside the image build, never by hand on
# the finished machine.
#
# WHAT IT MAKES
#   /usr/share/icons/hicolor/<N>x<N>/apps/aquarius-game-mode.png
# at every standard size up to the largest picture Valve ships: Steam's own icon
# with branding/icons/game-mode-badge.png in its bottom-right corner — the way
# SteamOS's "Return to Gaming Mode" wears Steam's icon with a small arrow. The
# Game Mode launcher (aquarius-game-mode.desktop) asks for `aquarius-game-mode`
# and both Aquarius icon themes fall through to hicolor for it.
#
# ⚠️ WHY THIS PICTURE IS MADE DURING THE BUILD, WHEN NO OTHER ONE IS
# Every other picture in AquariusOS is drawn on the Mac, looked at, and
# committed (the long argument is in branding/render-app-icons.sh). This one
# cannot be: half of it is Steam's icon, which is Valve's, and it lives only in
# the steam package on the machine — this repository does not, and should not,
# carry a copy. So the badge is committed and reviewable (game-mode-badge.svg,
# .png), and the one thing done here is to lay it over Valve's picture. No
# drawing program is installed for it: GdkPixbuf is already in every image for
# GNOME itself.
#
# Never upscales. If the largest steam.png is 256 pixels, the 512 icon is not
# made; a blurry big icon is worse than none, and the desktop scales the 256
# one itself.
#
# USAGE   aq-game-mode-icon.py <badge.png> <icons root, normally /usr/share/icons>
# Prints one OK/BAD line per size; exits non-zero if nothing could be made.
# ==============================================================================
import glob
import os
import re
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf  # noqa: E402

SIZES = [16, 24, 32, 48, 64, 128, 256, 512]
BADGE_SHARE = 0.44   # the badge's width as a share of the icon's
BADGE_INSET = 0.02   # gap between the badge and the icon's edge
NAME = "aquarius-game-mode"

badge_path, icons_root = sys.argv[1], sys.argv[2]

# Every steam.png Valve ships, by size. The scalable SVG counts as "any size"
# when the package has one (RPM Fusion's does not, today).
sources = {}
for path in glob.glob(f"{icons_root}/hicolor/*/apps/steam.png"):
    m = re.search(r"/(\d+)x\1/apps/", path)
    if m:
        sources[int(m.group(1))] = path
svg = f"{icons_root}/hicolor/scalable/apps/steam.svg"
largest = max(sources) if sources else 0
if os.path.exists(svg):
    largest = SIZES[-1]
if not largest:
    print(f"BAD no steam.png under {icons_root}/hicolor — is the steam package installed?")
    sys.exit(1)

badge = GdkPixbuf.Pixbuf.new_from_file(badge_path)
made = 0
for n in SIZES:
    if n > largest:
        print(f"SKIP {n}x{n}: Valve's largest icon is {largest}px and we never upscale it")
        continue
    src = sources.get(n) or (svg if os.path.exists(svg) else sources[largest])
    base = GdkPixbuf.Pixbuf.new_from_file_at_scale(src, n, n, True)

    # A transparent n×n canvas, Steam's icon centred on it, so a non-square
    # source could never shift the badge off the corner.
    canvas = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, n, n)
    canvas.fill(0x00000000)
    bx = (n - base.get_width()) // 2
    by = (n - base.get_height()) // 2
    base.composite(canvas, bx, by, base.get_width(), base.get_height(),
                   bx, by, 1, 1, GdkPixbuf.InterpType.NEAREST, 255)

    b = max(int(round(n * BADGE_SHARE)), 6)
    inset = int(round(n * BADGE_INSET))
    x = n - b - inset
    y = n - b - inset
    small = badge.scale_simple(b, b, GdkPixbuf.InterpType.HYPER)
    small.composite(canvas, x, y, b, b, x, y, 1, 1, GdkPixbuf.InterpType.NEAREST, 255)

    out_dir = f"{icons_root}/hicolor/{n}x{n}/apps"
    os.makedirs(out_dir, exist_ok=True)
    out = f"{out_dir}/{NAME}.png"
    canvas.savev(out, "png", [], [])
    made += 1
    print(f"OK {out}: Steam's {os.path.relpath(src, icons_root)} with a {b}px badge")

sys.exit(0 if made else 1)
