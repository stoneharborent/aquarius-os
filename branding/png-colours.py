#!/usr/bin/env python3
# ==============================================================================
# Read the actual colours out of a picture file
# ==============================================================================
# PLAIN ENGLISH
#
# This little tool opens PNG picture files and tells you which colours are
# really in them. Nothing else in this project can do that: every other check we
# have reads TEXT — the words in a settings file, the answer a program gives —
# and a picture has no text in it to read.
#
# It exists for one job. When a colour is retired from the AquariusOS palette,
# every place that colour appears has to go — and "every place" includes the
# hundred-odd picture files that make up the boot animation, which no amount of
# grepping can look inside. This opens them and looks.
#
# ------------------------------------------------------------------------------
# HOW TO USE IT
# ------------------------------------------------------------------------------
#   # Refuse the retired Starlight colours. Prints nothing and exits 0 if the
#   # pictures are clean; names the file, the colour and the pixel if not.
#   python3 branding/png-colours.py --forbid 8AB4FF,5B4BE0,E6DDB8,06070C  pic.png …
#
#   # Just tell me what is in this picture — the twenty commonest colours.
#   python3 branding/png-colours.py --list pic.png
#
#   # Is this exact colour in this picture at all? (Used to prove the progress
#   # bar really is the Aquarius blue and not something close to it.)
#   python3 branding/png-colours.py --require 00BFFF pic.png
#
# Colours are written as six hex digits, the same as everywhere else in the
# project, with or without a leading #.
#
# ------------------------------------------------------------------------------
# WHY IT IS WRITTEN OUT LONGHAND
# ------------------------------------------------------------------------------
# Reading a PNG normally means installing an image library. This project
# deliberately has almost no dependencies — the whole point of the boot animation
# being drawn on the Mac and committed as finished pictures is that a build
# machine needs nothing to use them. So the twenty lines it takes to unpack a
# PNG by hand are written out below rather than pulling in a library that then
# has to exist on the Mac AND on GitHub's machines.
#
# It handles the one shape of PNG this project produces — 8 bits per colour,
# with transparency, not interlaced — and says so plainly if it is handed
# anything else, rather than guessing.
# ==============================================================================
import argparse
import struct
import sys
import zlib
from collections import Counter

# Which kinds of PNG this understands. The number is PNG's own "colour type":
# 2 is red/green/blue, 6 is red/green/blue plus transparency. The value is how
# many bytes one pixel takes.
BYTES_PER_PIXEL = {2: 3, 6: 4}


def read_pixels(path):
    """Hand back (width, height, rows) where each row is a list of (r,g,b,a)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} is not a PNG file.")

    width, height = struct.unpack(">II", data[16:24])
    bit_depth, colour_type, _compression, _filter, interlace = data[24:29]

    if bit_depth != 8:
        sys.exit(f"{path}: {bit_depth} bits per colour. This tool only reads 8.")
    if colour_type not in BYTES_PER_PIXEL:
        sys.exit(f"{path}: colour type {colour_type}. This tool only reads 2 (RGB) and 6 (RGBA).")
    if interlace != 0:
        sys.exit(f"{path} is interlaced. This tool only reads plain, non-interlaced PNGs.")

    stride = BYTES_PER_PIXEL[colour_type]

    # Collect the compressed picture data. A PNG is allowed to split it over any
    # number of IDAT chunks and Chrome does exactly that, so they are joined back
    # together before anything is unpacked.
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        if kind == b"IDAT":
            compressed += data[offset + 8:offset + 8 + length]
        offset += 12 + length

    raw = zlib.decompress(bytes(compressed))

    # ------------------------------------------------------------------------
    # Undo the "filtering"
    # ------------------------------------------------------------------------
    # PNG does not store the colours directly. Each row starts with one extra
    # byte saying how that row was rewritten to make it compress better —
    # usually "each pixel is stored as the difference from the one to its left",
    # or "…from the one above". Putting the real colours back means walking the
    # rows in order and undoing whichever trick each one used. That is what the
    # five cases below are. This is the whole of PNG's cleverness and it is
    # genuinely only this much.
    rows = []
    previous = bytearray(width * stride)
    position = 0
    for _ in range(height):
        filter_kind = raw[position]
        position += 1
        line = bytearray(raw[position:position + width * stride])
        position += width * stride

        for i in range(len(line)):
            left = line[i - stride] if i >= stride else 0
            up = previous[i]
            up_left = previous[i - stride] if i >= stride else 0
            if filter_kind == 0:                       # stored as-is
                pass
            elif filter_kind == 1:                     # difference from the left
                line[i] = (line[i] + left) & 0xFF
            elif filter_kind == 2:                     # difference from above
                line[i] = (line[i] + up) & 0xFF
            elif filter_kind == 3:                     # from the average of both
                line[i] = (line[i] + ((left + up) >> 1)) & 0xFF
            elif filter_kind == 4:                     # PNG's "Paeth" predictor
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                nearest = left if (pa <= pb and pa <= pc) else (up if pb <= pc else up_left)
                line[i] = (line[i] + nearest) & 0xFF
            else:
                sys.exit(f"{path}: row filter {filter_kind} is not one PNG defines.")

        pixels = []
        for x in range(width):
            base = x * stride
            r, g, b = line[base], line[base + 1], line[base + 2]
            a = line[base + 3] if stride == 4 else 255
            pixels.append((r, g, b, a))
        rows.append(pixels)
        previous = line

    return width, height, rows


def to_hex(colour):
    return "%02X%02X%02X" % colour[:3]


def parse_colour(text):
    text = text.strip().lstrip("#").upper()
    if len(text) != 6:
        sys.exit(f"'{text}' is not six hex digits, e.g. 00BFFF.")
    return text


def main():
    parser = argparse.ArgumentParser(
        description="Read the colours that are really in a PNG picture.")
    parser.add_argument("files", nargs="+", help="the picture files to look at")
    parser.add_argument("--forbid", default="",
                        help="comma-separated colours that must NOT appear")
    parser.add_argument("--require", default="",
                        help="comma-separated colours that MUST appear in every file")
    parser.add_argument("--list", action="store_true",
                        help="print the twenty commonest colours in each file")
    parser.add_argument("--min-alpha", type=int, default=8,
                        help="ignore pixels fainter than this (0-255, default 8). "
                             "A colour at one per cent opacity is not that colour "
                             "on screen, it is the background.")
    args = parser.parse_args()

    forbidden = {parse_colour(c) for c in args.forbid.split(",") if c.strip()}
    required = {parse_colour(c) for c in args.require.split(",") if c.strip()}

    faults = 0
    for path in args.files:
        width, height, rows = read_pixels(path)
        seen = Counter()
        for y, row in enumerate(rows):
            for x, pixel in enumerate(row):
                if pixel[3] < args.min_alpha:
                    continue
                name = to_hex(pixel)
                seen[name] += 1
                if name in forbidden:
                    print(f"  FAIL {path}: retired colour #{name} at pixel {x},{y}")
                    faults = 1

        if args.list:
            print(f"  {path} ({width}x{height}) — the commonest colours in it:")
            for name, count in seen.most_common(20):
                print(f"      #{name}  {count} pixels")

        for name in required:
            if name not in seen:
                print(f"  FAIL {path}: #{name} does not appear in this picture at all")
                faults = 1

    return faults


if __name__ == "__main__":
    sys.exit(main())
