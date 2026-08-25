"""Asking ffprobe what is inside a file, and packaging the answer for rules.py.

The probe dictionary this builds is the ONLY thing :mod:`aq_ingest.rules` needs, which is
what keeps the decision engine pure and reusable.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import rules
from .tools import ToolFailed, ToolMissing, require, run

#: How many frames of packet timing to sample when checking for variable frame rate.
FRAME_SAMPLE = 500

#: Frame-to-frame gaps that wobble by more than this fraction of the typical gap mean VFR.
DELTA_TOLERANCE = 0.02  # 2 %


def _ffprobe_json(path: Path) -> dict | None:
    ffprobe = require("ffprobe")
    argv = [
        ffprobe,
        "-v", "error",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        str(path),
    ]
    try:
        proc = run(argv, timeout=120)
    except ToolFailed:
        return None
    try:
        data = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        return None
    if not data.get("streams"):
        return None
    return data


def _frame_timing(path: Path) -> dict | None:
    """Sample packet timing to see whether the gaps between frames are steady."""
    ffprobe = require("ffprobe")
    argv = [
        ffprobe,
        "-v", "error",
        "-select_streams", "v:0",
        "-print_format", "json",
        "-show_entries", "frame=best_effort_timestamp_time,pts_time,pkt_pts_time",
        "-read_intervals", f"%+#{FRAME_SAMPLE}",
        str(path),
    ]
    try:
        proc = run(argv, timeout=180)
        data = json.loads(proc.stdout or "{}")
    except (ToolFailed, json.JSONDecodeError):
        return None

    stamps: list[float] = []
    for frame in data.get("frames", []):
        for key in ("best_effort_timestamp_time", "pts_time", "pkt_pts_time"):
            value = frame.get(key)
            if value in (None, "N/A"):
                continue
            try:
                stamps.append(float(value))
            except (TypeError, ValueError):
                continue
            break

    stamps.sort()
    deltas = [b - a for a, b in zip(stamps, stamps[1:]) if b > a]
    if len(deltas) < 10:
        # Too short to judge. When in doubt, call it steady (spec §5.3).
        return {"sampled": len(stamps), "deltas_vary": False}

    deltas.sort()
    median = deltas[len(deltas) // 2]
    if median <= 0:
        return {"sampled": len(stamps), "deltas_vary": False}
    spread = (deltas[-1] - deltas[0]) / median
    return {
        "sampled": len(stamps),
        "deltas_vary": spread > DELTA_TOLERANCE,
        "spread": round(spread, 4),
    }


def probe_file(path: Path) -> dict:
    """Build the probe dictionary rules.decide() expects."""
    path = Path(path)
    ext = path.suffix.lower().lstrip(".")
    info: dict = {"path": str(path), "ext": ext, "ffprobe": None, "frame_timing": None}

    if ext in rules.CAMERA_RAW_EXTS:
        # ffmpeg cannot open these and does not need to — they pass through untouched.
        return info

    try:
        info["ffprobe"] = _ffprobe_json(path)
    except ToolMissing:
        raise

    if info["ffprobe"] and rules.needs_frame_timing_scan(info):
        info["frame_timing"] = _frame_timing(path)

    return info
