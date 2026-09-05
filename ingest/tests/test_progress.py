"""The progress bar and the time left (Royce's bench request, 2026-09-04).

Three layers, tested separately:

  1. **Reading ffmpeg.** Real ``-progress`` output, pasted in as a fixture, parsed.
  2. **The arithmetic.** Percentages and time-left estimates, with a clock we control, so
     "about 2 min left" is a fact this file can assert rather than something to eyeball.
  3. **The real thing.** One genuine transcode, watched, proving the numbers are not just
     internally consistent but actually arrive from ffmpeg.

None of layers 1 and 2 need ffmpeg, a desktop, or a Linux machine.
"""

from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path

from aq_ingest import actions, progress, rules, tools
from aq_ingest.config import Settings
from aq_ingest.probe import probe_file

from . import fixtures

# One real block of `ffmpeg -progress pipe:1 -nostats` output, copied from a run. ffmpeg
# prints a block like this roughly twice a second, and one final one ending `progress=end`.
PROGRESS_BLOCK = """\
frame=241
fps=48.20
stream_0_0_q=-0.0
bitrate= 145.6kbits/s
total_size=182784
out_time_us=10041667
out_time_ms=10041667
out_time=00:00:10.041667
dup_frames=0
drop_frames=0
speed=2.01x
progress=continue
"""

FINAL_BLOCK = """\
frame=480
out_time_us=20000000
out_time=00:00:20.000000
progress=end
"""


class ParsingTests(unittest.TestCase):
    def test_a_key_value_line_is_split(self):
        self.assertEqual(progress.parse_progress_line("out_time_us=123"), ("out_time_us", "123"))

    def test_ffmpegs_padded_values_are_trimmed(self):
        self.assertEqual(
            progress.parse_progress_line("bitrate= 145.6kbits/s"), ("bitrate", "145.6kbits/s")
        )

    def test_a_line_that_is_not_a_pair_is_ignored(self):
        for line in ("", "   ", "no equals sign here", "=orphan"):
            self.assertIsNone(progress.parse_progress_line(line), line)

    def test_a_whole_block_gives_the_position(self):
        reader = progress.FfmpegProgress()
        for line in PROGRESS_BLOCK.splitlines():
            reader.feed(line)
        self.assertAlmostEqual(reader.seconds, 10.041667, places=5)
        self.assertFalse(reader.finished)

    def test_the_end_block_says_it_finished(self):
        reader = progress.FfmpegProgress()
        for line in (PROGRESS_BLOCK + FINAL_BLOCK).splitlines():
            reader.feed(line)
        self.assertTrue(reader.finished)
        self.assertAlmostEqual(reader.seconds, 20.0, places=5)

    def test_out_time_ms_is_read_as_microseconds_not_milliseconds(self):
        # ffmpeg's long-standing wart. Reading it as milliseconds makes every conversion
        # look 1000x further along than it is, which means the bar hits 100% at once and
        # then sits there — the exact failure this test exists to prevent.
        reader = progress.FfmpegProgress()
        reader.feed("out_time_ms=5000000")
        self.assertAlmostEqual(reader.seconds, 5.0, places=6)

    def test_a_build_that_only_prints_the_timestamp_still_works(self):
        reader = progress.FfmpegProgress()
        reader.feed("out_time=00:01:30.500000")
        self.assertAlmostEqual(reader.seconds, 90.5, places=5)

    def test_not_available_yet_is_not_a_position(self):
        reader = progress.FfmpegProgress()
        for line in ("out_time=N/A", "out_time_us=N/A", "out_time_us=-1"):
            self.assertFalse(reader.feed(line), line)
        self.assertIsNone(reader.seconds)

    def test_the_position_never_walks_backwards(self):
        reader = progress.FfmpegProgress()
        reader.feed("out_time_us=10000000")
        self.assertFalse(reader.feed("out_time_us=4000000"))
        self.assertAlmostEqual(reader.seconds, 10.0)

    def test_a_position_becomes_a_fraction_of_the_clip(self):
        reader = progress.FfmpegProgress()
        reader.feed("out_time_us=5000000")
        self.assertAlmostEqual(reader.fraction_of(20.0), 0.25)
        # Past the end (ffmpeg pads the last frame) is still 100%, never 103%.
        reader.feed("out_time_us=21000000")
        self.assertEqual(reader.fraction_of(20.0), 1.0)

    def test_no_duration_means_no_fraction_rather_than_a_crash(self):
        reader = progress.FfmpegProgress()
        reader.feed("out_time_us=5000000")
        for duration in (None, 0.0, -1.0):
            self.assertIsNone(reader.fraction_of(duration))


class DurationTests(unittest.TestCase):
    def test_the_container_duration_is_used(self):
        probe = {"ffprobe": {"format": {"duration": "12.5"}, "streams": [{}]}}
        self.assertAlmostEqual(progress.duration_from_probe(probe), 12.5)

    def test_a_container_that_forgot_falls_back_to_the_video_stream(self):
        probe = {
            "ffprobe": {
                "format": {},
                "streams": [
                    {"codec_type": "audio", "duration": "99"},
                    {"codec_type": "video", "duration": "8.0"},
                ],
            }
        }
        self.assertAlmostEqual(progress.duration_from_probe(probe), 8.0)

    def test_a_still_photo_has_no_duration_and_that_is_fine(self):
        self.assertIsNone(progress.duration_from_probe({"ffprobe": None}))
        self.assertIsNone(progress.duration_from_probe(None))
        self.assertIsNone(
            progress.duration_from_probe({"ffprobe": {"format": {"duration": "N/A"}}})
        )


class TimeLeftWordingTests(unittest.TestCase):
    def test_nothing_is_said_when_nothing_is_known(self):
        self.assertEqual(progress.format_time_left(None), "")

    def test_under_a_minute_does_not_pretend_to_be_precise(self):
        self.assertEqual(progress.format_time_left(9), "less than a minute left")
        self.assertEqual(progress.format_time_left(44), "less than a minute left")

    def test_about_a_minute_is_words_not_a_number(self):
        self.assertEqual(progress.format_time_left(60), "about a minute left")

    def test_minutes_are_rounded(self):
        self.assertEqual(progress.format_time_left(120), "about 2 min left")
        self.assertEqual(progress.format_time_left(9 * 60 + 20), "about 9 min left")

    def test_a_very_long_job_switches_to_hours(self):
        self.assertEqual(progress.format_time_left(2 * 3600), "about 2 hours left")


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def tick(self, seconds: float) -> None:
        self.now += seconds


class JobArithmeticTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()

    def job(self, total: int) -> progress.JobProgress:
        return progress.JobProgress(total, clock=self.clock)

    def test_one_file_half_converted_is_half_the_job(self):
        job = self.job(1)
        job.start_file("clip.MP4")
        job.update_file(0.5)
        self.assertEqual(job.percent, 50)

    def test_every_file_counts_the_same(self):
        job = self.job(4)
        job.finish_file()
        self.assertEqual(job.percent, 25)
        job.start_file("two.MP4")
        job.update_file(0.5)
        self.assertEqual(job.percent, 37)

    def test_the_bar_never_slips_backwards(self):
        job = self.job(2)
        job.start_file("one.MP4")
        job.update_file(0.9)
        high = job.percent
        # A file that reports a lower position (a container reordering its packets) must
        # not make the bar go back down.
        job.update_file(0.1)
        self.assertGreaterEqual(job.percent, high)

    def test_a_file_with_no_measurable_progress_holds_the_bar_still(self):
        job = self.job(2)
        job.finish_file()
        job.start_file("photo.HEIC")
        job.update_file(None)
        self.assertEqual(job.percent, 50)

    def test_it_ends_at_a_hundred(self):
        job = self.job(3)
        for _ in range(3):
            job.finish_file()
        self.assertEqual(job.percent, 100)
        self.assertEqual(job.snapshot().file_number, 3)

    def test_no_estimate_is_offered_in_the_first_couple_of_seconds(self):
        job = self.job(1)
        job.start_file("clip.MP4")
        job.update_file(0.2)
        self.assertIsNone(job.seconds_left)
        self.assertEqual(job.snapshot().time_left, "")

    def test_a_quarter_done_in_ten_seconds_means_about_thirty_left(self):
        job = self.job(1)
        job.start_file("clip.MP4")
        self.clock.tick(10.0)
        job.update_file(0.25)
        # 10s bought 25%, so the remaining 75% is about 30s more.
        self.assertAlmostEqual(job.seconds_left, 30.0, delta=0.01)
        self.assertEqual(job.snapshot().time_left, "less than a minute left")

    def test_a_sudden_stall_only_nudges_the_estimate(self):
        # Smoothing is the whole point: a single slow second must not turn "2 min left"
        # into "20 min left" and back again a second later.
        job = self.job(1)
        job.start_file("clip.MP4")
        self.clock.tick(10.0)
        job.update_file(0.5)
        steady = job.seconds_left
        self.assertAlmostEqual(steady, 10.0, delta=0.01)

        self.clock.tick(30.0)  # thirty seconds where almost nothing happened
        job.update_file(0.51)
        stalled = job.seconds_left
        raw = 40.0 * (1 - 0.51) / 0.51  # what an unsmoothed estimate would have said
        self.assertLess(stalled, raw, "the estimate should lag the panic, not lead it")
        self.assertGreater(stalled, steady)

    def test_the_snapshot_is_what_both_screens_are_drawn_from(self):
        job = self.job(3)
        job.finish_file()
        job.start_file("two.MP4")
        self.clock.tick(10.0)
        job.update_file(0.5)
        snap = job.snapshot()
        self.assertEqual(snap.percent, 50)
        self.assertEqual(snap.total, 3)
        self.assertEqual(snap.file_number, 2)
        self.assertEqual(snap.name, "two.MP4")


class StreamingTests(unittest.TestCase):
    """Reading a program's output WHILE it runs, rather than after it has finished.

    This is the plumbing the bar rides on, and it is tested with a stand-in program rather
    than ffmpeg so that it is fast, deterministic, and provable on a Mac. What it has to
    get right is the difference between a progress bar and a hang.
    """

    def _python(self, code: str) -> list[str]:
        return [sys.executable, "-c", code]

    def test_lines_arrive_while_the_program_is_still_running(self):
        # The stand-in prints three lines a tenth of a second apart and then sleeps for
        # another half second. If we were only handed the output at the end — which is
        # what subprocess.run does, and why this function exists — the first line would
        # not reach us until after that sleep. Timing the arrival is the assertion.
        argv = self._python(
            "import time\n"
            "for i in range(1, 4):\n"
            "    print('out_time_us=%d' % (i * 1000000), flush=True)\n"
            "    time.sleep(0.1)\n"
            "time.sleep(0.5)\n"
        )
        started = time.monotonic()
        arrivals: list[tuple[str, float]] = []
        tools.run_watching(
            argv,
            lambda line: arrivals.append((line.strip(), time.monotonic() - started)),
            timeout=30,
        )
        self.assertEqual(
            [line for line, _ in arrivals],
            ["out_time_us=1000000", "out_time_us=2000000", "out_time_us=3000000"],
        )
        total = time.monotonic() - started
        self.assertLess(
            arrivals[0][1],
            total - 0.4,
            "the first line should arrive long before the program exits",
        )

    def test_a_chatty_stderr_does_not_deadlock_the_conversion(self):
        # A pipe holds about 64KB. If nobody reads stderr, a program that fills it stops
        # dead — forever, with no error anywhere. This writes far more than a pipe holds.
        argv = self._python(
            "import sys\n"
            "sys.stderr.write('x' * 400000)\n"
            "print('out_time_us=1000000')\n"
        )
        lines: list[str] = []
        tools.run_watching(argv, lines.append, timeout=60)
        self.assertEqual([line.strip() for line in lines], ["out_time_us=1000000"])

    def test_a_failure_still_quotes_what_the_program_said(self):
        argv = self._python("import sys; sys.stderr.write('Invalid data found\\n'); sys.exit(1)")
        with self.assertRaises(tools.ToolFailed) as caught:
            tools.run_watching(argv, lambda line: None, timeout=30)
        self.assertIn("Invalid data found", str(caught.exception))

    def test_a_broken_progress_bar_never_breaks_the_conversion(self):
        # on_line draws a notification. That is a courtesy, and the same rule applies to
        # it as to everything in notify.py: it may not take the run down with it.
        argv = self._python("print('out_time_us=1000000')")

        def explode(line: str) -> None:
            raise RuntimeError("the desktop went away")

        proc = tools.run_watching(argv, explode, timeout=30)
        self.assertEqual(proc.returncode, 0)

    def test_a_program_that_is_not_there_is_still_a_plain_message(self):
        with self.assertRaises(tools.ToolMissing):
            tools.run_watching(["ffmpeg-that-does-not-exist"], lambda line: None, timeout=5)


class RealFfmpegTests(unittest.TestCase):
    """Genuine conversions. This is the layer that could rot silently.

    Everything above proves our arithmetic and our plumbing. Only this proves that the
    numbers actually arrive from ffmpeg — that ``-progress pipe:1`` is still the flag,
    that ``out_time_us`` is still the key, and that adding both to a real command line
    still produces a correct file.
    """

    def transcode(self, source: Path, out: Path, **kw):
        self.addCleanup(lambda: out.unlink(missing_ok=True))
        probe = probe_file(source)
        plan = rules.Plan(
            action=rules.TRANSCODE,
            rule=3,
            reason="test",
            output_suffix=".mov",
            dnxhr_profile="dnxhr_sq",
            pix_fmt="yuv422p",
        )
        actions.execute(plan, source, out, probe, Settings(), **kw)
        return probe

    def test_a_real_transcode_reports_where_it_has_got_to(self):
        source = fixtures.vfr_mp4()
        out = Path(fixtures.root()) / "progress-check.mov"
        out.unlink(missing_ok=True)

        seen: list[float] = []
        probe = self.transcode(source, out, on_fraction=seen.append)

        self.assertTrue(out.is_file(), "the watched command must still produce the file")
        self.assertIsNotNone(progress.duration_from_probe(probe))
        self.assertTrue(seen, "ffmpeg -progress reported nothing at all")
        self.assertTrue(all(0.0 <= f <= 1.0 for f in seen), seen)
        self.assertEqual(seen, sorted(seen), "the reported position should only go forward")
        # ffmpeg prints a block every half second of wall clock plus one at the end, so a
        # fixture this small may only produce the final one. What must be true either way
        # is that the last thing it said is "finished".
        self.assertGreater(seen[-1], 0.9, seen)

    def test_the_progress_flags_are_really_on_the_command_line(self):
        # A refactor that quietly dropped these would leave a bar that never moves, and
        # the test above would still pass on the strength of its final callback.
        argv = actions._transcode_argv(
            Path("in.mp4"),
            Path("out.mov"),
            rules.Plan(action=rules.TRANSCODE, reason="test", output_suffix=".mov"),
            {"ffprobe": None},
        )
        watched = [argv[0], *actions.FFMPEG_PROGRESS, *argv[1:]]
        self.assertEqual(watched[1:4], ["-progress", "pipe:1", "-nostats"])
        self.assertNotIn("-progress", argv)

    def test_a_conversion_still_works_when_nobody_is_watching(self):
        # The no-callback path is the one the watch-folder service uses, and it must stay
        # the ordinary command it always was.
        source = fixtures.aac_mp4()
        out = Path(fixtures.root()) / "unwatched-check.mov"
        out.unlink(missing_ok=True)
        self.addCleanup(lambda: out.unlink(missing_ok=True))

        probe = probe_file(source)
        plan = rules.Plan(action=rules.REWRAP, rule=6, reason="test", output_suffix=".mov")
        actions.execute(plan, source, out, probe, Settings())
        self.assertTrue(out.is_file())

    def test_a_photo_is_converted_without_pretending_to_have_a_bar(self):
        # heif-convert has no progress to report and ffmpeg's would be over before it was
        # drawn, so a still must go down the plain path even when a callback is offered.
        # heif-enc being INSTALLED is not the same as heif-enc being able to make a
        # HEIC: on GitHub's Ubuntu runner it is there but has no HEVC encoder behind
        # it, so building the fixture fails rather than the tool being missing. Every
        # other HEIC test in this suite skips on the same exception; this one joins them.
        try:
            source = fixtures.heic_still()
        except fixtures.FixtureUnavailable as exc:
            self.skipTest(str(exc))
        out = Path(fixtures.root()) / "still-check.png"
        out.unlink(missing_ok=True)
        self.addCleanup(lambda: out.unlink(missing_ok=True))

        called: list[float] = []
        plan = rules.Plan(
            action=rules.STILL_CONVERT, rule=2, reason="test", output_suffix=".png"
        )
        actions.execute(
            plan, source, out, probe_file(source), Settings(), on_fraction=called.append
        )
        self.assertTrue(out.is_file())
        self.assertEqual(called, [])


if __name__ == "__main__":
    unittest.main()
