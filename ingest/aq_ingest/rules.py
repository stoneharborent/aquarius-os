"""The decision engine (spec §5).

PURE MODULE — no subprocess calls, no disk access, no printing. Probe data goes in,
a :class:`Plan` comes out. AquariusTransfer will import this module later to reuse the
same decisions, so keep it free of side effects.

The caller (``probe.py``) is responsible for producing the probe dictionary::

    {
        "path":         "/cards/A001/C001.MP4",   # str
        "ext":          "mp4",                    # lower case, no dot
        "ffprobe":      {"format": {...}, "streams": [...]} or None,
        "frame_timing": {"sampled": 120, "deltas_vary": True} or None,
    }

``ffprobe`` is ``None`` when ffprobe could not identify the file at all.
``frame_timing`` is ``None`` when no packet-timing scan was performed; ask
:func:`needs_frame_timing_scan` whether one is worth doing.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction

from .config import Settings

# --------------------------------------------------------------------------------------
# Codec / extension tables
# --------------------------------------------------------------------------------------

#: Camera formats ffmpeg cannot open but Resolve reads natively. Never probed, never touched.
CAMERA_RAW_EXTS = frozenset({"braw", "r3d", "ari", "arx", "arriraw", "ocn", "crm"})

#: If ffprobe cannot identify the file but the extension is one of these, it is still a
#: professional camera format Resolve handles on its own — report it as ready, don't guess.
NATIVE_IF_UNREADABLE_EXTS = CAMERA_RAW_EXTS | frozenset({"mxf", "dng", "cdng", "cine"})

HEIC_EXTS = frozenset({"heic", "heif", "hif"})
STILL_EXTS = frozenset({"png", "jpg", "jpeg", "jpe", "tif", "tiff", "exr", "dpx"})

#: Video codecs Resolve on Linux decodes in every edition.
PASS_THROUGH_VIDEO_CODECS = frozenset({"prores", "dnxhd"})
#: Decoded by Resolve STUDIO only (licensing) — see docs/codec-research.md.
LICENSED_VIDEO_CODECS = frozenset({"h264", "hevc"})
#: Resolve decodes these on no platform at all.
UNSUPPORTED_VIDEO_CODECS = frozenset({"vp8", "vp9"})
AV1_VIDEO_CODECS = frozenset({"av1"})

STILL_IMAGE_CODECS = frozenset(
    {"png", "mjpeg", "tiff", "exr", "dpx", "jpeg2000", "ppm", "bmp", "gif"}
)

#: Audio Resolve plays fine.
PASS_THROUGH_AUDIO_CODECS = frozenset({"mp3", "flac"})
#: Audio that imports SILENT — the classic Linux complaint.
SILENT_AUDIO_CODECS = frozenset({"aac", "ac3", "eac3", "dts", "truehd", "mlp"})

#: Frame rates an NLE expects (spec §5.1 rule 3).
STANDARD_FRAME_RATES: tuple[tuple[str, float], ...] = (
    ("24000/1001", 24000 / 1001),
    ("24/1", 24.0),
    ("25/1", 25.0),
    ("30000/1001", 30000 / 1001),
    ("30/1", 30.0),
    ("50/1", 50.0),
    ("60000/1001", 60000 / 1001),
    ("60/1", 60.0),
)

#: r_frame_rate vs avg_frame_rate must differ by more than this to even consider VFR.
VFR_RATE_TOLERANCE = 0.005  # 0.5 %

# Actions
PASS_THROUGH = "pass_through"
REWRAP = "rewrap"
TRANSCODE = "transcode"
STILL_CONVERT = "still_convert"
LEAVE_ALONE = "leave_alone"


@dataclass(frozen=True)
class Plan:
    """What we intend to do with one file. Produced by :func:`decide`."""

    action: str
    reason: str
    rule: int = 0
    output_suffix: str | None = None
    dnxhr_profile: str | None = None
    pix_fmt: str | None = None
    conform_fps: str | None = None
    flags: tuple[str, ...] = field(default_factory=tuple)

    @property
    def writes_a_file(self) -> bool:
        return self.action in (REWRAP, TRANSCODE, STILL_CONVERT)


# --------------------------------------------------------------------------------------
# Small helpers (public — tests and AquariusTransfer use them)
# --------------------------------------------------------------------------------------


def parse_rate(value: object) -> float | None:
    """Turn an ffprobe rate string like ``"30000/1001"`` into a float."""
    if value is None:
        return None
    try:
        rate = float(Fraction(str(value)))
    except (ValueError, ZeroDivisionError):
        return None
    return rate if rate > 0 else None


def nearest_standard_rate(fps: float | None) -> str:
    """Nearest broadcast-standard frame rate, as an ffmpeg fraction string."""
    if not fps or fps <= 0:
        return "25/1"
    return min(STANDARD_FRAME_RATES, key=lambda item: abs(item[1] - fps))[0]


def video_streams(ffprobe: dict | None) -> list[dict]:
    if not ffprobe:
        return []
    return [s for s in ffprobe.get("streams", []) if s.get("codec_type") == "video"]


def audio_streams(ffprobe: dict | None) -> list[dict]:
    if not ffprobe:
        return []
    return [s for s in ffprobe.get("streams", []) if s.get("codec_type") == "audio"]


def bit_depth(stream: dict) -> int:
    """Best-effort bit depth of a video stream (ffprobe often omits it for HEVC)."""
    raw = stream.get("bits_per_raw_sample")
    try:
        depth = int(raw)
        if depth > 0:
            return depth
    except (TypeError, ValueError):
        pass
    pix_fmt = str(stream.get("pix_fmt") or "")
    for candidate in (16, 14, 12, 10):
        if f"p{candidate}" in pix_fmt or f"{candidate}le" in pix_fmt or f"{candidate}be" in pix_fmt:
            return candidate
    return 8


def is_still_image(probe: dict) -> bool:
    """True for a photo rather than a clip."""
    ext = (probe.get("ext") or "").lower()
    if ext in STILL_EXTS or ext in HEIC_EXTS:
        return True
    ffprobe = probe.get("ffprobe")
    if not ffprobe:
        return False
    if audio_streams(ffprobe):
        return False
    vids = video_streams(ffprobe)
    if len(vids) != 1:
        return False
    stream = vids[0]
    if stream.get("codec_name") in STILL_IMAGE_CODECS:
        frames = stream.get("nb_frames")
        return frames in (None, "1", 1) or str(
            ffprobe.get("format", {}).get("format_name", "")
        ).startswith("image2")
    return False


def is_heic(probe: dict) -> bool:
    ext = (probe.get("ext") or "").lower()
    if ext in HEIC_EXTS:
        return True
    ffprobe = probe.get("ffprobe") or {}
    fmt = str(ffprobe.get("format", {}).get("format_name", ""))
    return "heif" in fmt or "heic" in fmt


def needs_frame_timing_scan(probe: dict) -> bool:
    """Is a packet-timing scan worth running? (spec §5.3, first half of the test)"""
    if is_still_image(probe):
        return False
    vids = video_streams(probe.get("ffprobe"))
    if not vids:
        return False
    stream = vids[0]
    r_rate = parse_rate(stream.get("r_frame_rate"))
    avg_rate = parse_rate(stream.get("avg_frame_rate"))
    if not r_rate or not avg_rate:
        return False
    return abs(r_rate - avg_rate) / max(r_rate, avg_rate) > VFR_RATE_TOLERANCE


def is_vfr(probe: dict) -> bool:
    """Variable frame rate? Needs BOTH halves of the spec §5.3 test to agree.

    When in doubt we answer False: a needless re-encode costs minutes, a missed rewrap
    costs seconds to redo.
    """
    if not needs_frame_timing_scan(probe):
        return False
    timing = probe.get("frame_timing")
    if not timing:
        return False
    return bool(timing.get("deltas_vary"))


def timecode_of(ffprobe: dict | None) -> str | None:
    """The reel timecode, if the file carries one, so we can put it on the copy."""
    if not ffprobe:
        return None
    candidates = [ffprobe.get("format", {}).get("tags", {})]
    candidates += [s.get("tags", {}) or {} for s in ffprobe.get("streams", [])]
    for tags in candidates:
        value = (tags or {}).get("timecode")
        if isinstance(value, str) and value.count(":") + value.count(";") == 3:
            return value
    return None


# --------------------------------------------------------------------------------------
# The decision table (spec §5.1)
# --------------------------------------------------------------------------------------


def _dnxhr_settings(stream: dict, settings: Settings) -> tuple[str, str]:
    """(profile, pixel format) for the DNxHR recipe (spec §5.2)."""
    choice = settings.dnxhr_profile
    if choice == "auto":
        choice = "hqx" if bit_depth(stream) >= 10 else "sq"
    pix_fmt = "yuv422p10le" if choice == "hqx" else "yuv422p"
    return f"dnxhr_{choice}", pix_fmt


def _transcode_plan(
    probe: dict, settings: Settings, *, rule: int, reason: str, conform: bool = False
) -> Plan:
    vids = video_streams(probe.get("ffprobe"))
    stream = vids[0] if vids else {}
    profile, pix_fmt = _dnxhr_settings(stream, settings)
    conform_fps = None
    flags: tuple[str, ...] = ()
    if conform:
        conform_fps = nearest_standard_rate(parse_rate(stream.get("avg_frame_rate")))
        flags = ("vfr-conformed",)
    return Plan(
        action=TRANSCODE,
        reason=reason,
        rule=rule,
        output_suffix=".mov",
        dnxhr_profile=profile,
        pix_fmt=pix_fmt,
        conform_fps=conform_fps,
        flags=flags,
    )


def _audio_is_fine(ffprobe: dict) -> bool:
    for stream in audio_streams(ffprobe):
        codec = str(stream.get("codec_name") or "")
        if codec.startswith("pcm_") or codec in PASS_THROUGH_AUDIO_CODECS:
            continue
        return False
    return True


def _audio_is_silent_in_resolve(ffprobe: dict) -> bool:
    return any(
        str(s.get("codec_name") or "") in SILENT_AUDIO_CODECS for s in audio_streams(ffprobe)
    )


def _supported_video_codecs(settings: Settings) -> frozenset[str]:
    if settings.resolve_edition == "studio":
        return PASS_THROUGH_VIDEO_CODECS | LICENSED_VIDEO_CODECS
    return PASS_THROUGH_VIDEO_CODECS


def decide(probe: dict, settings: Settings, *, force_transcode: bool = False) -> Plan:
    """Pick exactly one action for one file. Top to bottom, first match wins."""
    plan = _decide_base(probe, settings)

    if force_transcode and plan.action in (PASS_THROUGH, REWRAP, LEAVE_ALONE):
        # --force-transcode upgrades anything with a real, decodable video stream.
        # Photos and audio-only files are left as they are: there is nothing to transcode.
        if video_streams(probe.get("ffprobe")) and not is_still_image(probe):
            return _transcode_plan(
                probe,
                settings,
                rule=plan.rule,
                reason="fully converted because you asked for --force-transcode",
                conform=is_vfr(probe),
            )
    return plan


def _decide_base(probe: dict, settings: Settings) -> Plan:
    ext = (probe.get("ext") or "").lower()
    ffprobe = probe.get("ffprobe")

    # Rule 1a — professional camera formats. ffmpeg cannot open them; Resolve can.
    if ext in CAMERA_RAW_EXTS:
        return Plan(PASS_THROUGH, "already editor-ready (professional camera format)", rule=1)

    # Rule 2 — iPhone photos.
    if is_heic(probe):
        suffix = settings.still_suffix
        target = "PNG" if settings.still_format == "png" else "JPEG"
        return Plan(
            STILL_CONVERT,
            f"iPhone photo converted to {target} (editors cannot read HEIC)",
            rule=2,
            output_suffix=suffix,
        )

    if ffprobe is None:
        if ext in NATIVE_IF_UNREADABLE_EXTS:
            return Plan(
                PASS_THROUGH, "already editor-ready (professional camera format)", rule=1
            )
        return Plan(LEAVE_ALONE, "unrecognized — left alone", rule=8)

    vids = video_streams(ffprobe)
    auds = audio_streams(ffprobe)

    # Rule 1b — stills and audio-only files that already work.
    if is_still_image(probe):
        codec = str(vids[0].get("codec_name") or "") if vids else ""
        if ext in STILL_EXTS or codec in STILL_IMAGE_CODECS:
            return Plan(PASS_THROUGH, "already editor-ready (photo)", rule=1)
        return Plan(LEAVE_ALONE, "unrecognized — left alone", rule=8)

    if not vids:
        if auds and _audio_is_fine(ffprobe):
            return Plan(PASS_THROUGH, "already editor-ready (audio)", rule=1)
        if auds:
            # Audio-only file (an .m4a voice memo, an AC-3 mixdown). A WAV is the friendliest
            # thing to hand an editor, so audio-only rewraps land as .wav rather than .mov.
            return Plan(
                REWRAP,
                "sound converted so editors can hear it",
                rule=6,
                output_suffix=".wav",
            )
        return Plan(LEAVE_ALONE, "unrecognized — left alone", rule=8)

    video_codec = str(vids[0].get("codec_name") or "")

    # Rule 3 — variable frame rate. A container swap cannot fix timing; only a re-encode can.
    if is_vfr(probe):
        return _transcode_plan(
            probe,
            settings,
            rule=3,
            reason="fully converted and locked to a steady frame rate (the phone recorded a "
            "changing one, which makes sound drift out of sync)",
            conform=True,
        )

    # Rule 4 — codecs Resolve cannot decode anywhere.
    if video_codec in UNSUPPORTED_VIDEO_CODECS:
        return _transcode_plan(
            probe,
            settings,
            rule=4,
            reason="fully converted (Resolve cannot open this video format on any computer)",
        )

    # Rule 5 — free Resolve cannot decode H.264/H.265 at all.
    if video_codec in LICENSED_VIDEO_CODECS and settings.resolve_edition == "free":
        return _transcode_plan(
            probe,
            settings,
            rule=5,
            reason="fully converted (the free DaVinci Resolve cannot open normal camera video)",
        )

    supported = _supported_video_codecs(settings)

    if video_codec in supported:
        # Rule 6 — the classic silent-audio fix, plus containers Resolve misreads.
        if _audio_is_silent_in_resolve(ffprobe):
            return Plan(
                REWRAP,
                "sound converted so editors can hear it (picture untouched)",
                rule=6,
                output_suffix=".mov",
            )
        if not auds and ext not in ("mov", "mxf"):
            return Plan(
                REWRAP,
                "repacked into a MOV that editors read reliably (picture untouched)",
                rule=6,
                output_suffix=".mov",
            )
        if _audio_is_fine(ffprobe):
            return Plan(PASS_THROUGH, "already editor-ready", rule=1)
        # Some other audio codec (Opus, Vorbis…) riding along with supported video.
        return Plan(
            REWRAP,
            "sound converted so editors can hear it (picture untouched)",
            rule=6,
            output_suffix=".mov",
        )

    # Rule 7 — AV1: supported, but only on the right hardware. Don't burn an hour guessing.
    if video_codec in AV1_VIDEO_CODECS:
        return Plan(
            LEAVE_ALONE,
            "left alone — AV1 needs Resolve 18.5+ and a graphics card that decodes it. "
            "If it will not import, run aq-ingest again with --force-transcode",
            rule=7,
        )

    # Rule 8 — honesty over magic.
    return Plan(LEAVE_ALONE, "unrecognized — left alone", rule=8)
