"""Carrying out a plan: the ffmpeg command lines (spec §5.2 and §5.4).

Every output is written to a temporary name in the destination folder and only moved into
place once ffmpeg has finished successfully — a cancelled or failed run never leaves a
half-written file that a later run would mistake for a finished one.
"""

from __future__ import annotations

import os
from pathlib import Path

from . import rules
from .config import Settings
from .rules import Plan
from .tools import ToolFailed, ToolMissing, find, require, run

FFMPEG_BASE = ["-y", "-hide_banner", "-nostdin", "-v", "error"]


def _temp_path(destination: Path) -> Path:
    # Keep the real extension on the end: ffmpeg and heif-convert both choose the output
    # format from it. The leading dot hides the part-file from watch folders (spec §8).
    return destination.with_name(
        f".{destination.stem}.aq-ingest-part{destination.suffix}"
    )


def _finish(temp: Path, destination: Path, source: Path) -> None:
    os.replace(temp, destination)
    # Copy the original's timestamp onto the copy so media pools sort by shooting order,
    # and so a re-run can tell the copy is up to date (spec §5.2, §6).
    stat = source.stat()
    os.utime(destination, (stat.st_atime, stat.st_mtime))


def _timecode_args(probe: dict) -> list[str]:
    timecode = rules.timecode_of(probe.get("ffprobe"))
    return ["-timecode", timecode] if timecode else []


def _rewrap_argv(source: Path, temp: Path, plan: Plan, probe: dict) -> list[str]:
    ffmpeg = require("ffmpeg")
    argv = [ffmpeg, *FFMPEG_BASE, "-i", str(source)]
    if plan.output_suffix == ".wav":
        argv += ["-map", "0:a", "-c:a", "pcm_s16le"]
    else:
        argv += [
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", "copy",
            "-c:a", "pcm_s16le",
        ]
        argv += _timecode_args(probe)
    argv += ["-map_metadata", "0", str(temp)]
    return argv


def _transcode_argv(source: Path, temp: Path, plan: Plan, probe: dict) -> list[str]:
    ffmpeg = require("ffmpeg")
    argv = [
        ffmpeg,
        *FFMPEG_BASE,
        "-i", str(source),
        "-map", "0:v:0",
        "-map", "0:a?",
        "-c:v", "dnxhd",
        "-profile:v", plan.dnxhr_profile or "dnxhr_sq",
        "-pix_fmt", plan.pix_fmt or "yuv422p",
    ]
    if plan.conform_fps:
        argv += ["-fps_mode", "cfr", "-r", plan.conform_fps]
    argv += ["-c:a", "pcm_s16le"]
    argv += _timecode_args(probe)
    argv += ["-map_metadata", "0", str(temp)]
    return argv


def _still_argv(source: Path, temp: Path, settings: Settings) -> list[str]:
    """Prefer libheif's own converter; fall back to ffmpeg if it is not installed."""
    heif = find("heif-convert")
    if heif:
        argv = [heif]
        if settings.still_format == "jpeg":
            argv += ["-q", "95"]
        return argv + [str(source), str(temp)]

    ffmpeg = require("ffmpeg")
    argv = [ffmpeg, *FFMPEG_BASE, "-i", str(source)]
    if settings.still_format == "jpeg":
        argv += ["-q:v", "2"]
    return argv + [str(temp)]


def execute(plan: Plan, source: Path, destination: Path, probe: dict, settings: Settings) -> None:
    """Run one plan. Raises ToolFailed / ToolMissing with a plain-language message."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = _temp_path(destination)
    if temp.exists():
        temp.unlink()

    if plan.action == rules.REWRAP:
        argv = _rewrap_argv(source, temp, plan, probe)
    elif plan.action == rules.TRANSCODE:
        argv = _transcode_argv(source, temp, plan, probe)
    elif plan.action == rules.STILL_CONVERT:
        argv = _still_argv(source, temp, settings)
    else:
        raise ValueError(f"execute() called with nothing to do: {plan.action}")

    try:
        run(argv)
    except (ToolFailed, ToolMissing):
        if temp.exists():
            temp.unlink()
        raise

    if not temp.exists() or temp.stat().st_size == 0:
        if temp.exists():
            temp.unlink()
        raise ToolFailed(
            f"{Path(argv[0]).name} reported success but produced no usable file. "
            f"Nothing was written."
        )

    try:
        _finish(temp, destination, source)
    except OSError as exc:
        temp.unlink(missing_ok=True)
        raise ToolFailed(
            f"The copy was made but could not be saved as {destination}: "
            f"{exc.strerror or exc}.\nNothing was left behind, and your original is untouched."
        ) from exc
