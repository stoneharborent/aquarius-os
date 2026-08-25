"""Synthetic test media, built with ffmpeg on demand and cached for the whole test run.

Nothing here needs real camera footage: testsrc2 makes the picture, sine makes the sound.
Each fixture is a deliberate reproduction of one row of the spec's decision table.
"""

from __future__ import annotations

import atexit
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

SIZE = "320x240"
DURATION = "2"

_root: Path | None = None
_built: dict[str, Path] = {}
_encoders: set[str] | None = None


class FixtureUnavailable(Exception):
    """This machine's ffmpeg cannot build the fixture — the test should skip, loudly."""


def root() -> Path:
    global _root
    if _root is None:
        _root = Path(tempfile.mkdtemp(prefix="aq-ingest-fixtures-"))
        atexit.register(shutil.rmtree, _root, True)
    return _root


def _run(argv: list[str]) -> None:
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = "\n".join((proc.stderr or "").strip().splitlines()[-8:])
        raise FixtureUnavailable(f"{argv[0]} failed building a fixture:\n{tail}")


def encoders() -> set[str]:
    global _encoders
    if _encoders is None:
        proc = subprocess.run(
            ["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True
        )
        found = set()
        for line in proc.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2 and len(parts[0]) == 6:
                found.add(parts[1])
        _encoders = found
    return _encoders


def require_encoders(*names: str) -> None:
    missing = [n for n in names if n not in encoders()]
    if missing:
        raise FixtureUnavailable(
            f"this ffmpeg has no {', '.join(missing)} encoder, so the fixture cannot be built"
        )


def has_program(name: str) -> bool:
    return shutil.which(name) is not None


def ffprobe(path: Path, *, streams: bool = True) -> dict:
    argv = [
        "ffprobe", "-v", "error", "-print_format", "json", "-show_format",
    ]
    if streams:
        argv.append("-show_streams")
    argv.append(str(path))
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssertionError(f"ffprobe could not read {path}:\n{proc.stderr}")
    return json.loads(proc.stdout)


def stream_list(path: Path, kind: str | None = None) -> list[dict]:
    data = ffprobe(path)
    streams = data.get("streams", [])
    if kind:
        streams = [s for s in streams if s.get("codec_type") == kind]
    return streams


def video_hash(path: Path) -> str:
    """Hash of the video packets only — proves a rewrap did not touch the picture."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:v:0", "-c", "copy", "-f", "hash", "-"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise AssertionError(f"could not hash {path}:\n{proc.stderr}")
    return proc.stdout.strip()


def _cached(name: str, builder) -> Path:
    if name not in _built:
        target = root() / name
        builder(target)
        if not target.exists():
            raise FixtureUnavailable(f"fixture {name} was not produced")
        _built[name] = target
    return _built[name]


def _base_video(extra_input: list[str] | None = None) -> list[str]:
    argv = [
        "ffmpeg", "-y", "-v", "error",
        "-f", "lavfi", "-i", f"testsrc2=size={SIZE}:rate=25:duration={DURATION}",
        "-f", "lavfi", "-i", f"sine=frequency=440:duration={DURATION}",
    ]
    return argv + (extra_input or [])


# ---------------------------------------------------------------------------- fixtures


def aac_mp4() -> Path:
    """Row 5/6: an ordinary camera/phone clip — H.264 picture, AAC sound."""

    def build(target: Path) -> None:
        require_encoders("libx264", "aac")
        _run(_base_video() + [
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(target),
        ])

    return _cached("camera_clip.mp4", build)


def two_audio_mp4() -> Path:
    """Spec §5.4: several sound tracks, which must survive in the same order."""

    def build(target: Path) -> None:
        require_encoders("libx264", "aac")
        _run([
            "ffmpeg", "-y", "-v", "error",
            "-f", "lavfi", "-i", f"testsrc2=size={SIZE}:rate=25:duration={DURATION}",
            "-f", "lavfi", "-i", f"sine=frequency=440:duration={DURATION}",
            "-f", "lavfi", "-i", f"sine=frequency=880:duration={DURATION}",
            "-map", "0:v", "-map", "1:a", "-map", "2:a",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-ac:a:0", "1", "-ar:a:0", "48000",
            "-ac:a:1", "2", "-ar:a:1", "44100",
            "-shortest", str(target),
        ])

    return _cached("two_tracks.mp4", build)


def vfr_mp4() -> Path:
    """Row 3: a phone-style clip whose frames arrive at uneven intervals.

    Built by keeping 2 frames out of every 4 from a 50 fps source, with the original
    timestamps preserved: gaps alternate 0.02s / 0.06s and the average lands near 25.
    """

    def build(target: Path) -> None:
        require_encoders("libx264", "aac")
        _run([
            "ffmpeg", "-y", "-v", "error",
            "-f", "lavfi", "-i", f"testsrc2=size={SIZE}:rate=50:duration=4",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
            "-vf", "select='lt(mod(n,4),2)'",
            "-fps_mode", "passthrough",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(target),
        ])

    return _cached("phone_vfr.mp4", build)


def ac3_ts() -> Path:
    """Row 6: an AVCHD-style camcorder file — H.264 picture, AC-3 sound, MPEG-TS."""

    def build(target: Path) -> None:
        require_encoders("libx264", "ac3")
        _run(_base_video() + [
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "ac3", "-shortest", str(target),
        ])

    return _cached("camcorder.ts", build)


def vp9_webm() -> Path:
    """Row 4: VP9 — a format Resolve cannot open on any computer, in any edition."""

    def build(target: Path) -> None:
        require_encoders("libvpx-vp9")
        audio = ["-c:a", "libopus"] if "libopus" in encoders() else ["-an"]
        _run(_base_video() + [
            "-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8",
            "-pix_fmt", "yuv420p", *audio, "-shortest", str(target),
        ])

    return _cached("web_clip.webm", build)


def hevc10_mp4() -> Path:
    """Spec §5.2: a 10-bit source, which must come out as DNxHR HQX."""

    def build(target: Path) -> None:
        require_encoders("libx265", "aac")
        _run(_base_video() + [
            "-c:v", "libx265", "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1",
            "-x265-params", "log-level=none",
            "-c:a", "aac", "-shortest", str(target),
        ])

    return _cached("mirrorless_10bit.mp4", build)


def dnxhr_mov() -> Path:
    """Row 1: already editor-ready — DNxHR picture with PCM sound."""

    def build(target: Path) -> None:
        require_encoders("dnxhd", "pcm_s16le")
        _run(_base_video() + [
            "-c:v", "dnxhd", "-profile:v", "dnxhr_sq", "-pix_fmt", "yuv422p",
            "-c:a", "pcm_s16le", "-shortest", str(target),
        ])

    return _cached("already_ready.mov", build)


def pcm_wav() -> Path:
    """Row 1: already editor-ready — plain PCM audio."""

    def build(target: Path) -> None:
        _run([
            "ffmpeg", "-y", "-v", "error",
            "-f", "lavfi", "-i", f"sine=frequency=440:duration={DURATION}",
            "-c:a", "pcm_s16le", str(target),
        ])

    return _cached("scratch_audio.wav", build)


def png_still() -> Path:
    """Row 1: a photo that already works."""

    def build(target: Path) -> None:
        _run([
            "ffmpeg", "-y", "-v", "error",
            "-f", "lavfi", "-i", f"testsrc2=size={SIZE}:rate=1:duration=1",
            "-frames:v", "1", str(target),
        ])

    return _cached("photo.png", build)


def heic_still() -> Path:
    """Row 2: an iPhone-style HEIC photo. Needs libheif's heif-enc to build."""

    def build(target: Path) -> None:
        if not has_program("heif-enc"):
            raise FixtureUnavailable(
                "heif-enc is not installed on this machine, so a HEIC fixture cannot be "
                "created (install libheif-examples / libheif-tools). CI covers this case."
            )
        source = png_still()
        attempts = [
            ["heif-enc", str(source), "-o", str(target)],
            ["heif-enc", "-o", str(target), str(source)],
        ]
        last: Exception | None = None
        for argv in attempts:
            try:
                _run(argv)
                if target.exists():
                    return
            except FixtureUnavailable as exc:
                last = exc
        raise FixtureUnavailable(f"heif-enc could not build the HEIC fixture: {last}")

    return _cached("iphone_photo.heic", build)
