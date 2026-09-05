"""How far along the conversion is, and how much longer it will take.

Royce asked for this on the bench on 2026-09-04: *"when Make Editor-Ready converts a clip,
the notification should show a progress bar and how long it will take."*

Converting a card of footage takes minutes. Before this file existed the only thing on
screen was "Finished 2 of 12", which tells you nothing at all while the file you are
actually waiting for is being written. This module turns ffmpeg's own running commentary
into two numbers a person can use: **a percentage** and **a plain-English time left**.

Everything in here is pure arithmetic and string building — no subprocesses, no desktop,
no clock of its own (the clock is passed in). That is what makes it testable on a Mac.

--------------------------------------------------------------------------------------
HOW WE KNOW HOW FAR ALONG FFMPEG IS
--------------------------------------------------------------------------------------
ffmpeg will report its own progress if you ask it to, with ``-progress pipe:1 -nostats``.
It then prints a small block of ``key=value`` lines, once every half second or so, like:

    frame=241
    fps=48.20
    out_time_us=10041667
    out_time=00:00:10.041667
    speed=2.01x
    progress=continue

...and one last block ending ``progress=end``. The number that matters is
``out_time_us``: **how many microseconds of the finished file have been written so far.**
Divide that by how long the source clip is (ffprobe already told us, back in probe.py)
and you have a fraction between 0 and 1.

⚠️ ``out_time_ms`` IS NOT MILLISECONDS. It is a long-standing wart in ffmpeg: the key
called ``out_time_ms`` carries *microseconds*, exactly like ``out_time_us``. Reading it as
milliseconds makes every conversion look 1000x further along than it is. We prefer
``out_time_us``, fall back to parsing the human ``out_time`` timestamp, and only then read
``out_time_ms`` — as microseconds, deliberately.
"""

from __future__ import annotations

from dataclasses import dataclass

# --------------------------------------------------------------------------------------
# Tuning
# --------------------------------------------------------------------------------------

#: Don't guess at a time remaining until the job has been running at least this long.
#: A guess made half a second in is wrong by minutes and looks broken.
MIN_ELAPSED_FOR_ETA = 2.0

#: ...and until at least this much of the work is done, for the same reason.
MIN_FRACTION_FOR_ETA = 0.01

#: How much a new estimate is allowed to move the shown one. 0.3 means "nudge towards the
#: new number", which stops the time left from jumping around when ffmpeg speeds up or
#: slows down for a few seconds.
ETA_SMOOTHING = 0.3


# --------------------------------------------------------------------------------------
# Reading ffmpeg's progress lines
# --------------------------------------------------------------------------------------


def parse_progress_line(line: str) -> tuple[str, str] | None:
    """Split one ``key=value`` line from ``ffmpeg -progress``. None if it is not one."""
    text = line.strip()
    if not text or "=" not in text:
        return None
    key, _, value = text.partition("=")
    key = key.strip()
    value = value.strip()
    if not key:
        return None
    return key, value


def parse_timestamp(text: str) -> float | None:
    """Turn ffmpeg's ``HH:MM:SS.ffffff`` into seconds. None if it is not a timestamp.

    ffmpeg prints ``N/A`` before the first frame is written, and a negative time while it
    is priming a filter chain. Both mean "no useful answer yet".
    """
    parts = text.split(":")
    if not 1 <= len(parts) <= 3:
        return None
    total = 0.0
    for part in parts:
        try:
            total = total * 60 + float(part)
        except ValueError:
            return None
    return total if total >= 0 else None


def _micros(text: str) -> float | None:
    try:
        value = float(text)
    except ValueError:
        return None
    return value / 1_000_000.0 if value >= 0 else None


class FfmpegProgress:
    """Feed it ffmpeg's ``-progress`` lines; ask it how many seconds have been written.

    It is deliberately forgiving. Any line it does not understand is ignored, and a run
    where ffmpeg prints nothing useful simply never reports a position — which the layer
    above shows as a job with no percentage rather than as a failure.
    """

    def __init__(self) -> None:
        #: Seconds of output written so far, or None if ffmpeg has not said yet.
        self.seconds: float | None = None
        #: True once ffmpeg has printed its final ``progress=end`` block.
        self.finished = False

    def feed(self, line: str) -> bool:
        """Take one line. Returns True if the position moved (so the caller can redraw)."""
        parsed = parse_progress_line(line)
        if parsed is None:
            return False
        key, value = parsed

        if key == "progress":
            if value == "end":
                self.finished = True
            return False

        if key == "out_time_us":
            seconds = _micros(value)
        elif key == "out_time":
            seconds = parse_timestamp(value)
        elif key == "out_time_ms":
            # See the module docstring: this key holds MICROseconds, not milliseconds.
            seconds = _micros(value)
        else:
            return False

        if seconds is None:
            return False
        # Never let the position walk backwards; some encoders reorder their reporting.
        if self.seconds is not None and seconds <= self.seconds:
            return False
        self.seconds = seconds
        return True

    def fraction_of(self, duration: float | None) -> float | None:
        """How far through a clip of ``duration`` seconds we are, 0.0–1.0."""
        if self.seconds is None or not duration or duration <= 0:
            return None
        return max(0.0, min(1.0, self.seconds / duration))


def duration_from_probe(probe: dict | None) -> float | None:
    """How long the source clip is, in seconds, from what ffprobe already told us.

    probe.py runs ffprobe once per file and keeps the answer, so this costs nothing —
    no second pass over the media just to draw a progress bar.

    ``format.duration`` is the usual answer. Some camera containers leave it out and put
    the length on the video stream instead, so that is checked too. A still photo has no
    duration at all, and neither does a stream that is still being written; both come back
    as None, which means "show progress without a percentage".
    """
    if not probe:
        return None
    data = probe.get("ffprobe") if "ffprobe" in probe else probe
    if not isinstance(data, dict):
        return None

    candidates: list[object] = []
    fmt = data.get("format")
    if isinstance(fmt, dict):
        candidates.append(fmt.get("duration"))
    for stream in data.get("streams") or []:
        if isinstance(stream, dict) and stream.get("codec_type") == "video":
            candidates.append(stream.get("duration"))

    for candidate in candidates:
        if candidate in (None, "", "N/A"):
            continue
        try:
            seconds = float(candidate)
        except (TypeError, ValueError):
            continue
        if seconds > 0:
            return seconds
    return None


# --------------------------------------------------------------------------------------
# The whole job, not just one file
# --------------------------------------------------------------------------------------


def format_time_left(seconds: float | None) -> str:
    """Plain English, deliberately vague. Nobody wants "4 minutes 12 seconds left".

    Vague is also *honest*: the number underneath is an estimate that moves, and rounding
    it to the nearest minute is a fair description of how much we really know.
    """
    if seconds is None or seconds < 0:
        return ""
    if seconds < 45:
        return "less than a minute left"
    if seconds < 90:
        return "about a minute left"
    minutes = int(round(seconds / 60.0))
    if minutes < 90:
        return f"about {minutes} min left"
    hours = int(round(seconds / 3600.0))
    return f"about {hours} hours left"


@dataclass
class Snapshot:
    """What the notification and the terminal line are both drawn from."""

    percent: int
    files_done: int
    total: int
    name: str
    time_left: str

    @property
    def file_number(self) -> int:
        """Which file is being worked on, counting from 1. Never runs past the total."""
        return min(self.files_done + 1, self.total)


class JobProgress:
    """Tracks one whole ``aq-ingest`` run: N files, one of them in flight.

    **Every file counts the same.** A ten-second clip and a ten-minute clip each move the
    bar by 1/N. Weighting by length would need every file probed before the first one
    starts, which on a card of 200 clips is a minute of nothing happening — a worse
    experience than a bar that moves unevenly. The smoothing on the time-left estimate is
    what keeps that from showing.
    """

    def __init__(self, total: int, *, clock=None) -> None:
        if clock is None:
            import time

            clock = time.monotonic
        self._clock = clock
        self.total = max(0, total)
        self.files_done = 0
        self.name = ""
        self._fraction = 0.0
        self._percent = 0
        self._eta: float | None = None
        self._started = self._clock()

    # -- being told what is happening ------------------------------------------------

    def start_file(self, name: str) -> None:
        self.name = name
        self._fraction = 0.0

    def update_file(self, fraction: float | None) -> None:
        """How far through the current file we are. None means "no idea" — hold still."""
        if fraction is None:
            return
        self._fraction = max(0.0, min(1.0, fraction))

    def finish_file(self) -> None:
        self.files_done = min(self.files_done + 1, self.total)
        self._fraction = 0.0
        # The name is deliberately KEPT. There is a moment between one file
        # finishing and the next one starting — and, at the end of a run, between
        # the last file finishing and the final message replacing the bar — where
        # something still has to be drawn. Clearing the name here made that moment
        # read "Converting your file · 100%", which is a small lie about a file we
        # can perfectly well name.

    # -- what it works out ------------------------------------------------------------

    @property
    def fraction(self) -> float:
        if self.total <= 0:
            return 0.0
        return max(0.0, min(1.0, (self.files_done + self._fraction) / self.total))

    @property
    def percent(self) -> int:
        """0–100, and it never goes down.

        A bar that slips backwards reads as a bug even when the arithmetic behind it is
        defensible, so the shown number is the highest one we have reached.
        """
        computed = int(self.fraction * 100)
        self._percent = max(self._percent, max(0, min(100, computed)))
        return self._percent

    @property
    def seconds_left(self) -> float | None:
        """How much longer, smoothed. None while it is too early to have any idea."""
        elapsed = self._clock() - self._started
        fraction = self.fraction
        if elapsed < MIN_ELAPSED_FOR_ETA or fraction < MIN_FRACTION_FOR_ETA:
            return None
        raw = elapsed * (1.0 - fraction) / fraction
        if self._eta is None:
            self._eta = raw
        else:
            self._eta = ETA_SMOOTHING * raw + (1.0 - ETA_SMOOTHING) * self._eta
        return self._eta

    def snapshot(self) -> Snapshot:
        return Snapshot(
            percent=self.percent,
            files_done=self.files_done,
            total=self.total,
            name=self.name,
            time_left=format_time_left(self.seconds_left),
        )
