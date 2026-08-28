"""End-to-end tests: real fixtures, the real CLI, results checked with ffprobe.

This is the Milestone 1 exit test from the spec (§10) — the whole decision table, proved
against synthetic media rather than described.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import shutil
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from aq_ingest import cli, notify

from . import fixtures


def _mov(path: Path) -> bool:
    return "mov" in fixtures.ffprobe(path)["format"]["format_name"]


def _snapshot(folder: Path) -> dict:
    """Every file under a folder, with the details that change when it is rewritten."""
    out = {}
    for path in sorted(folder.rglob("*")):
        if path.is_file():
            stat = path.stat()
            out[str(path)] = (stat.st_size, stat.st_ino, stat.st_mtime)
    return out


class IngestTestCase(unittest.TestCase):
    def setUp(self) -> None:
        # .resolve() matters on macOS, where /var is a symlink to /private/var and the
        # tool reports the real path.
        self.tmp = Path(tempfile.mkdtemp(prefix="aq-ingest-test-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.work = self.tmp / "work"
        self.work.mkdir()
        self.config_home = self.tmp / "config"
        self.state_home = self.tmp / "state"
        patcher = unittest.mock.patch.dict(
            os.environ,
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
            },
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    # -- helpers ------------------------------------------------------------------

    def fixture(self, builder, name: str | None = None) -> Path:
        """Build a fixture and copy it into this test's working folder."""
        try:
            source = builder()
        except fixtures.FixtureUnavailable as exc:
            self.skipTest(str(exc))
        target = self.work / (name or source.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return target

    def run_cli(self, *args: str, expect: int = 0) -> dict:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cli.main(["--json", *args])
        self.assertEqual(
            code, expect, f"exit code {code}\nstdout:\n{out.getvalue()}\nstderr:\n{err.getvalue()}"
        )
        try:
            return json.loads(out.getvalue())
        except json.JSONDecodeError:
            return {"summary": "", "results": [], "stderr": err.getvalue()}

    def only(self, report: dict) -> dict:
        self.assertEqual(len(report["results"]), 1, report)
        return report["results"][0]

    def config(self, text: str) -> Path:
        path = self.tmp / "ingest.toml"
        path.write_text(text, encoding="utf-8")
        return path

    def assertPcmAudio(self, path: Path, expected_tracks: int | None = None) -> None:
        tracks = fixtures.stream_list(path, "audio")
        if expected_tracks is not None:
            self.assertEqual(len(tracks), expected_tracks, tracks)
        self.assertTrue(tracks, f"{path} has no sound at all")
        for track in tracks:
            self.assertEqual(track["codec_name"], "pcm_s16le")


# ---------------------------------------------------------------------------------
# Decision table, end to end
# ---------------------------------------------------------------------------------


class DecisionTableTests(IngestTestCase):
    def test_1_camera_mp4_free_resolve_is_fully_converted(self):
        source = self.fixture(fixtures.aac_mp4)
        report = self.run_cli(str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "transcoded")

        output = Path(result["output"])
        self.assertTrue(output.exists())
        self.assertEqual(output.parent.name, "EditorReady")
        self.assertTrue(_mov(output))
        video = fixtures.stream_list(output, "video")[0]
        self.assertEqual(video["codec_name"], "dnxhd")
        self.assertEqual(video["pix_fmt"], "yuv422p")
        self.assertIn("SQ", video.get("profile", "").upper())
        self.assertPcmAudio(output, expected_tracks=1)

    def test_2_camera_mp4_studio_is_rewrapped_with_an_identical_picture(self):
        source = self.fixture(fixtures.aac_mp4)
        before = fixtures.video_hash(source)

        report = self.run_cli("--resolve-edition", "studio", str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "rewrapped")

        output = Path(result["output"])
        self.assertTrue(_mov(output))
        self.assertPcmAudio(output, expected_tracks=1)
        self.assertEqual(fixtures.stream_list(output, "video")[0]["codec_name"], "h264")
        self.assertEqual(
            fixtures.video_hash(output),
            before,
            "the rewrap changed the video bitstream — it must be copied untouched",
        )

    def test_3_ac3_sound_becomes_pcm(self):
        source = self.fixture(fixtures.ac3_ts)
        report = self.run_cli("--resolve-edition", "studio", str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "rewrapped")
        output = Path(result["output"])
        self.assertTrue(_mov(output))
        self.assertPcmAudio(output, expected_tracks=1)

    def test_4_vfr_clip_is_conformed_to_a_steady_frame_rate(self):
        source = self.fixture(fixtures.vfr_mp4)
        probe_in = fixtures.stream_list(source, "video")[0]
        self.assertNotEqual(
            probe_in["r_frame_rate"], probe_in["avg_frame_rate"], "fixture is not VFR"
        )

        report = self.run_cli("--resolve-edition", "studio", str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "transcoded")
        self.assertIn("vfr-conformed", result["flags"])
        self.assertEqual(result["rule"], 3)
        self.assertIn("VFR", report["summary"])

        output = Path(result["output"])
        video = fixtures.stream_list(output, "video")[0]
        self.assertEqual(video["r_frame_rate"], "25/1")
        self.assertEqual(video["avg_frame_rate"], "25/1")
        self.assertEqual(video["codec_name"], "dnxhd")
        self.assertPcmAudio(output)

    def test_5_vp9_is_converted_even_with_studio(self):
        source = self.fixture(fixtures.vp9_webm)
        report = self.run_cli("--resolve-edition", "studio", str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "transcoded")
        self.assertEqual(result["rule"], 4)
        output = Path(result["output"])
        self.assertEqual(fixtures.stream_list(output, "video")[0]["codec_name"], "dnxhd")

    def test_6_ten_bit_source_becomes_dnxhr_hqx(self):
        source = self.fixture(fixtures.hevc10_mp4)
        report = self.run_cli(str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "transcoded")
        video = fixtures.stream_list(Path(result["output"]), "video")[0]
        self.assertEqual(video["pix_fmt"], "yuv422p10le")
        self.assertIn("HQX", video.get("profile", "").upper())

    def test_7_files_that_already_work_are_left_completely_alone(self):
        dnx = self.fixture(fixtures.dnxhr_mov)
        wav = self.fixture(fixtures.pcm_wav)
        png = self.fixture(fixtures.png_still)
        before = _snapshot(self.work)

        report = self.run_cli(str(dnx), str(wav), str(png))
        statuses = {Path(r["source"]).name: r["status"] for r in report["results"]}
        for name, status in statuses.items():
            self.assertEqual(status, "already editor-ready", name)
        self.assertFalse((self.work / "EditorReady").exists())
        self.assertEqual(_snapshot(self.work), before)
        self.assertIn("3 already editor-ready", report["summary"])

    def test_8_heic_photo_becomes_a_png(self):
        source = self.fixture(fixtures.heic_still)
        report = self.run_cli(str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "converted")
        output = Path(result["output"])
        self.assertEqual(output.suffix, ".png")
        self.assertTrue(output.exists() and output.stat().st_size > 0)
        self.assertEqual(fixtures.stream_list(output, "video")[0]["codec_name"], "png")

    def test_11_every_sound_track_survives_in_order(self):
        source = self.fixture(fixtures.two_audio_mp4)
        report = self.run_cli("--resolve-edition", "studio", str(source))
        output = Path(self.only(report)["output"])
        self.assertPcmAudio(output, expected_tracks=2)
        tracks = fixtures.stream_list(output, "audio")
        self.assertEqual(tracks[0]["channels"], 1)
        self.assertEqual(tracks[1]["channels"], 2)
        self.assertEqual(tracks[0]["sample_rate"], "48000")
        self.assertEqual(tracks[1]["sample_rate"], "44100")

    def test_an_unrecognized_file_is_reported_not_guessed_at(self):
        junk = self.work / "notes.txt"
        junk.write_text("this is not footage", encoding="utf-8")
        report = self.run_cli(str(junk))
        result = self.only(report)
        self.assertEqual(result["status"], "left alone")
        self.assertIn("unrecognized", result["message"])
        self.assertFalse((self.work / "EditorReady").exists())


# ---------------------------------------------------------------------------------
# Behaviour of the tool itself
# ---------------------------------------------------------------------------------


class BehaviourTests(IngestTestCase):
    def test_9_running_twice_does_nothing_the_second_time(self):
        source = self.fixture(fixtures.aac_mp4)
        first = self.only(self.run_cli("--resolve-edition", "studio", str(source)))
        self.assertEqual(first["status"], "rewrapped")
        after_first = _snapshot(self.work / "EditorReady")

        second = self.only(self.run_cli("--resolve-edition", "studio", str(source)))
        self.assertEqual(second["status"], "up to date")
        self.assertEqual(_snapshot(self.work / "EditorReady"), after_first)

    def test_9b_force_reprocesses(self):
        source = self.fixture(fixtures.aac_mp4)
        self.run_cli("--resolve-edition", "studio", str(source))
        before = _snapshot(self.work / "EditorReady")

        result = self.only(self.run_cli("--resolve-edition", "studio", "--force", str(source)))
        self.assertEqual(result["status"], "rewrapped")
        after = _snapshot(self.work / "EditorReady")
        self.assertEqual(set(before), set(after), "--force must not create extra files")
        self.assertNotEqual(
            [v[1] for v in before.values()],
            [v[1] for v in after.values()],
            "--force should have written a new file",
        )

    def test_10_dry_run_writes_absolutely_nothing(self):
        source = self.fixture(fixtures.aac_mp4)
        before = _snapshot(self.work)

        report = self.run_cli("--dry-run", str(source))
        result = self.only(report)
        self.assertEqual(result["status"], "planned")
        self.assertIn("Dry run", report["summary"])
        self.assertIsNone(report["log"])

        self.assertEqual(_snapshot(self.work), before)
        self.assertFalse((self.work / "EditorReady").exists())
        self.assertFalse(self.config_home.exists(), "a dry run must not create the settings file")
        self.assertFalse(self.state_home.exists(), "a dry run must not write the log")

    def test_force_transcode_upgrades_a_rewrap(self):
        source = self.fixture(fixtures.aac_mp4)
        result = self.only(
            self.run_cli("--resolve-edition", "studio", "--force-transcode", str(source))
        )
        self.assertEqual(result["status"], "transcoded")
        output = Path(result["output"])
        self.assertEqual(fixtures.stream_list(output, "video")[0]["codec_name"], "dnxhd")

    def test_a_folder_is_walked_and_its_shape_mirrored(self):
        self.fixture(fixtures.aac_mp4, "A001/clip_one.mp4")
        self.fixture(fixtures.aac_mp4, "A001/DCIM/clip_two.mp4")
        report = self.run_cli("--resolve-edition", "studio", str(self.work / "A001"))
        self.assertEqual(len(report["results"]), 2)
        self.assertTrue((self.work / "A001/EditorReady/clip_one.mov").exists())
        self.assertTrue((self.work / "A001/EditorReady/DCIM/clip_two.mov").exists())

        # A second pass must not treat its own output as new footage.
        again = self.run_cli("--resolve-edition", "studio", str(self.work / "A001"))
        self.assertEqual(len(again["results"]), 2)
        self.assertTrue(all(r["status"] == "up to date" for r in again["results"]))

    def test_suffix_output_mode_from_the_settings_file(self):
        source = self.fixture(fixtures.aac_mp4)
        config = self.config('resolve_edition = "studio"\noutput = "suffix"\n')
        result = self.only(self.run_cli("--config", str(config), str(source)))
        self.assertEqual(result["status"], "rewrapped")
        self.assertEqual(Path(result["output"]), self.work / "camera_clip_editready.mov")
        self.assertFalse((self.work / "EditorReady").exists())

    def test_the_settings_file_is_created_on_the_first_real_run(self):
        source = self.fixture(fixtures.pcm_wav)
        expected = self.config_home / "aquarius" / "ingest.toml"
        self.assertFalse(expected.exists())
        self.run_cli(str(source))
        self.assertTrue(expected.exists())
        self.assertIn("resolve_edition", expected.read_text(encoding="utf-8"))

    def test_a_broken_settings_file_stops_the_run_with_a_clear_message(self):
        source = self.fixture(fixtures.pcm_wav)
        config = self.config('resolve_edition = "premium"\n')
        report = self.run_cli("--config", str(config), str(source), expect=2)
        self.assertIn("resolve_edition", report.get("stderr", ""))
        self.assertIn("free, studio", report.get("stderr", ""))

    def test_the_run_is_recorded_in_the_log(self):
        source = self.fixture(fixtures.aac_mp4)
        report = self.run_cli("--resolve-edition", "studio", str(source))
        log = Path(report["log"])
        self.assertEqual(log, self.state_home / "aquarius" / "ingest.log")
        text = log.read_text(encoding="utf-8")
        self.assertIn("rewrapped", text)
        self.assertIn(str(source), text)

    def test_a_failure_is_reported_honestly_and_leaves_no_debris(self):
        source = self.fixture(fixtures.aac_mp4)
        # Something is already sitting where the copy needs to go, and it cannot be replaced.
        blocked = self.work / "EditorReady" / "camera_clip.mov"
        (blocked / "in-the-way").mkdir(parents=True)

        report = self.run_cli("--resolve-edition", "studio", str(source), expect=1)
        result = self.only(report)
        self.assertEqual(result["status"], "failed")
        self.assertIn("1 failed", report["summary"])
        self.assertIsNone(result["output"], "a failed file must not be reported as written")

        leftovers = [p.name for p in (self.work / "EditorReady").iterdir()]
        self.assertEqual(leftovers, ["camera_clip.mov"], "a part-file was left behind")
        self.assertTrue(source.exists(), "the original must survive a failure")

    def test_a_missing_path_is_reported_and_fails(self):
        report = self.run_cli(str(self.work / "nope.mp4"), expect=2)
        self.assertIn("nope.mp4", report.get("stderr", ""))


# ---------------------------------------------------------------------------------
# Milestone 2 — what the right-click menu actually triggers
# ---------------------------------------------------------------------------------


class RecordingNotifier:
    """A Notifier that writes down what it was told instead of talking to a desktop."""

    def __init__(self, dry_run: bool = False) -> None:
        self.dry_run = dry_run
        self.started: list[int] = []
        self.progress_calls: list[tuple[int, int, str]] = []
        self.finished: list[tuple[list, str]] = []
        self.failures: list[str] = []

    active = True

    def start(self, total):
        self.started.append(total)

    def progress(self, done, total, name):
        self.progress_calls.append((done, total, name))

    def finish(self, results, summary, log_file=None):
        self.finished.append((results, summary))

    def failure(self, message):
        self.failures.append(message)


class NotificationTests(IngestTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.notifier = RecordingNotifier()

        def fake_factory(args):
            # Stand in for the real factory, but keep its one decision: --notify or not.
            self.notifier.dry_run = args.dry_run
            return self.notifier if args.notify else notify.Notifier(enabled=False)

        patcher = unittest.mock.patch.object(cli, "make_notifier", fake_factory)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_the_right_click_run_reports_start_and_finish(self):
        source = self.fixture(fixtures.aac_mp4)
        report = self.run_cli("--notify", "--resolve-edition", "studio", str(source))
        self.assertEqual(self.only(report)["status"], "rewrapped")

        self.assertEqual(self.notifier.started, [1])
        self.assertEqual(len(self.notifier.finished), 1)
        results, summary = self.notifier.finished[0]
        self.assertEqual(summary, report["summary"])
        self.assertEqual([r.status for r in results], ["rewrapped"])
        self.assertEqual(self.notifier.failures, [])

    def test_a_folder_run_reports_progress_for_each_file(self):
        self.fixture(fixtures.aac_mp4, "A001/one.mp4")
        self.fixture(fixtures.aac_mp4, "A001/two.mp4")
        self.run_cli("--notify", "--resolve-edition", "studio", str(self.work / "A001"))
        self.assertEqual([c[0] for c in self.notifier.progress_calls], [1, 2])
        self.assertEqual({c[1] for c in self.notifier.progress_calls}, {2})

    def test_a_problem_before_any_work_becomes_a_notification_not_silence(self):
        self.run_cli("--notify", str(self.work / "nope.mp4"), expect=2)
        self.assertEqual(self.notifier.started, [], "nothing was started, so say nothing started")
        self.assertEqual(len(self.notifier.failures), 1)
        self.assertIn("nope.mp4", self.notifier.failures[0])

    def test_a_broken_settings_file_becomes_a_notification_too(self):
        source = self.fixture(fixtures.pcm_wav)
        config = self.config('resolve_edition = "premium"\n')
        self.run_cli("--notify", "--config", str(config), str(source), expect=2)
        self.assertEqual(len(self.notifier.failures), 1)
        self.assertIn("resolve_edition", self.notifier.failures[0])

    def test_the_normal_terminal_run_is_untouched_by_all_this(self):
        source = self.fixture(fixtures.aac_mp4)
        report = self.run_cli("--resolve-edition", "studio", str(source))
        self.assertEqual(self.only(report)["status"], "rewrapped")
        self.assertEqual(self.notifier.started, [], "no --notify means no notifications")
        self.assertEqual(self.notifier.finished, [])


if __name__ == "__main__":
    unittest.main()
