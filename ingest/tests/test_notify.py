"""Milestone 2 — desktop notifications.

None of this needs a desktop. The wording functions are pure, and the Notifier is given a
fake "sender" that records the notify-send command lines instead of running them.
"""

from __future__ import annotations

import io
import contextlib
import subprocess
import unittest
from pathlib import Path

from aq_ingest import cli, notify, runner


def result(status: str, name: str = "clip.MP4", output: str | None = None, **kw) -> runner.Result:
    return runner.Result(
        source=Path("/cards/A001") / name,
        status=status,
        message=kw.pop("message", status),
        output=Path(output) if output else None,
        **kw,
    )


class FakeSender:
    """Stands in for running notify-send. Records every call; answers like the real thing."""

    def __init__(self, *, help_text: str = "--action", stdout: str = "", returncode: int = 0):
        self.calls: list[list[str]] = []
        self.timeouts: list[int] = []
        self.help_text = help_text
        self.stdout = stdout
        self.returncode = returncode

    def __call__(self, argv, *, timeout):
        self.calls.append(list(argv))
        self.timeouts.append(timeout)
        if "--help" in argv:
            return subprocess.CompletedProcess(argv, 0, self.help_text, "")
        return subprocess.CompletedProcess(argv, self.returncode, self.stdout, "")

    @property
    def bodies(self) -> list[str]:
        return [call[-1] for call in self.calls if "--help" not in call]

    @property
    def titles(self) -> list[str]:
        return [call[-2] for call in self.calls if "--help" not in call]


def make(**kw) -> tuple[notify.Notifier, FakeSender]:
    sender = FakeSender(help_text=kw.pop("help_text", "--action"), stdout=kw.pop("stdout", ""))
    opened: list[Path] = []
    ticks = iter(range(0, 10_000))
    notifier = notify.Notifier(
        program="/usr/bin/notify-send",
        sender=sender,
        opener=opened.append,
        clock=lambda: next(ticks) * 10.0,
        **kw,
    )
    notifier.opened = opened  # type: ignore[attr-defined]
    return notifier, sender


# ---------------------------------------------------------------------------------
# Wording
# ---------------------------------------------------------------------------------


class WordingTests(unittest.TestCase):
    def test_a_file_name_cannot_break_the_message(self):
        self.assertEqual(notify.escape("A&B <raw>.mp4"), "A&amp;B &lt;raw&gt;.mp4")

    def test_a_very_long_name_is_shortened_from_the_middle(self):
        name = "a" * 40 + "-interview-take-three.MP4"
        short = notify.shorten(name)
        self.assertLessEqual(len(short), 48)
        self.assertTrue(short.startswith("aaaa"))
        self.assertTrue(short.endswith(".MP4"), short)
        self.assertIn("…", short)

    def test_a_short_name_is_left_alone(self):
        self.assertEqual(notify.shorten("clip.MP4"), "clip.MP4")

    def test_one_file_is_not_called_1_files(self):
        self.assertIn("1 file.", notify.start_body(1))
        self.assertIn("12 files", notify.start_body(12))

    def test_the_start_message_promises_originals_are_safe(self):
        self.assertIn("originals are not changed", notify.start_body(3))

    def test_a_dry_run_says_nothing_will_change(self):
        self.assertIn("Nothing will be changed", notify.start_body(3, dry_run=True))
        self.assertEqual(notify.start_title(dry_run=True), "Checking your files")

    def test_progress_counts_up_and_names_the_file(self):
        self.assertEqual(
            notify.progress_body(3, 12, "clip.MP4"), "Finished 3 of 12 — clip.MP4"
        )

    def test_success_says_so(self):
        results = [result(runner.REWRAPPED, output="/cards/A001/EditorReady/clip.mov")]
        self.assertEqual(notify.finish_title(results), "Your files are editor-ready")
        self.assertFalse(notify.is_urgent(results))

    def test_a_run_that_changed_nothing_does_not_claim_it_fixed_things(self):
        results = [result(runner.ALREADY_READY), result(runner.UP_TO_DATE)]
        self.assertEqual(notify.finish_title(results), "Nothing needed changing")

    def test_failures_lead_the_headline_and_turn_it_critical(self):
        results = [
            result(runner.REWRAPPED, "ok.MP4", "/cards/A001/EditorReady/ok.mov"),
            result(runner.FAILED, "bad.MP4"),
        ]
        self.assertEqual(
            notify.finish_title(results), "1 file could not be made editor-ready"
        )
        self.assertTrue(notify.is_urgent(results))

    def test_the_failing_files_are_named_and_the_rest_counted(self):
        results = [result(runner.FAILED, f"bad{i}.MP4") for i in range(7)]
        body = notify.finish_body(results, "0 rewrapped, 7 failed")
        self.assertIn("bad0.MP4", body)
        self.assertIn("bad3.MP4", body)
        self.assertNotIn("bad5.MP4", body)
        self.assertIn("and 3 more", body)
        self.assertIn("originals are untouched", body)

    def test_the_body_says_where_the_copies_went(self):
        results = [result(runner.TRANSCODED, output="/cards/A001/EditorReady/clip.mov")]
        body = notify.finish_body(results, "1 transcoded, 0 failed")
        self.assertIn("1 transcoded", body)
        self.assertIn("Fixed copies are in: /cards/A001/EditorReady", body)

    def test_several_output_folders_are_counted_not_listed_forever(self):
        results = [
            result(runner.REWRAPPED, "a.MP4", "/cards/A/EditorReady/a.mov"),
            result(runner.REWRAPPED, "b.MP4", "/cards/B/EditorReady/b.mov"),
        ]
        body = notify.finish_body(results, "2 rewrapped, 0 failed")
        self.assertIn("/cards/A/EditorReady", body)
        self.assertIn("1 more folder", body)

    def test_a_dry_run_never_points_at_a_folder_it_did_not_write(self):
        results = [result(runner.PLANNED, output="/cards/A001/EditorReady/clip.mov")]
        body = notify.finish_body(results, "1 would be processed", dry_run=True)
        self.assertNotIn("Fixed copies are in", body)
        self.assertEqual(
            notify.finish_title(results, dry_run=True), "Preview only — nothing was changed"
        )

    def test_only_written_files_count_as_output_folders(self):
        results = [result(runner.UP_TO_DATE, output="/cards/A001/EditorReady/clip.mov")]
        self.assertEqual(notify.output_folders(results), [])
        self.assertFalse(notify.wrote_anything(results))


# ---------------------------------------------------------------------------------
# Sending
# ---------------------------------------------------------------------------------


class SendingTests(unittest.TestCase):
    def test_no_notify_send_means_no_crash_and_no_calls(self):
        notifier = notify.Notifier(program=None, sender=self.fail)
        self.assertFalse(notifier.active)
        notifier.start(3)
        notifier.progress(1, 3, "a.MP4")
        notifier.finish([result(runner.REWRAPPED)], "1 rewrapped, 0 failed")
        notifier.failure("boom")

    def test_disabled_notifier_never_looks_for_notify_send(self):
        self.assertFalse(notify.Notifier(enabled=False).active)

    def test_the_start_notification_carries_our_name_and_icon(self):
        notifier, sender = make()
        notifier.start(4)
        argv = sender.calls[0]
        self.assertIn("--app-name", argv)
        self.assertIn(notify.APP_NAME, argv)
        self.assertIn(notify.ICON, argv)
        self.assertIn("--print-id", argv)
        self.assertEqual(argv[-2], "Making your files editor-ready")

    def test_later_notifications_replace_the_first_one(self):
        notifier, sender = make(stdout="41\n")
        notifier.start(4)
        notifier.progress(1, 4, "a.MP4")
        self.assertIn("--replace-id", sender.calls[1])
        self.assertIn("41", sender.calls[1])

    def test_a_notify_send_without_print_id_support_does_not_break_the_run(self):
        notifier, sender = make(stdout="not a number")
        notifier.start(4)
        notifier.progress(1, 4, "a.MP4")
        self.assertNotIn("--replace-id", sender.calls[1])

    def test_progress_is_throttled(self):
        sender = FakeSender()
        notifier = notify.Notifier(
            program="/usr/bin/notify-send", sender=sender, clock=lambda: 0.0
        )
        notifier.start(10)
        for i in range(1, 6):
            notifier.progress(i, 10, f"clip{i}.MP4")
        self.assertEqual(len(sender.calls), 1, "the clock never moved, so only start should send")

    def test_a_single_file_gets_no_progress_chatter(self):
        notifier, sender = make()
        notifier.start(1)
        notifier.progress(1, 1, "clip.MP4")
        self.assertEqual(len(sender.calls), 1)

    def test_nothing_is_sent_for_an_empty_run(self):
        notifier, sender = make()
        notifier.start(0)
        notifier.finish([], "")
        self.assertEqual(sender.calls, [])

    def test_the_finish_notification_offers_to_open_the_folder(self):
        notifier, sender = make(stdout="")
        notifier.finish(
            [result(runner.REWRAPPED, output="/cards/A001/EditorReady/clip.mov")],
            "1 rewrapped, 0 failed",
        )
        final = sender.calls[-1]
        self.assertIn(f"--action={notify.OPEN_ACTION}={notify.OPEN_ACTION_LABEL}", final)
        # --action makes notify-send wait for a click, so it must not be cut short.
        self.assertGreater(sender.timeouts[-1], 60)

    def test_clicking_open_folder_opens_the_folder(self):
        notifier, sender = make(stdout=f"{notify.OPEN_ACTION}\n")
        notifier.finish(
            [result(runner.REWRAPPED, output="/cards/A001/EditorReady/clip.mov")],
            "1 rewrapped, 0 failed",
        )
        self.assertEqual(notifier.opened, [Path("/cards/A001/EditorReady")])

    def test_not_clicking_opens_nothing(self):
        notifier, sender = make(stdout="")
        notifier.finish(
            [result(runner.REWRAPPED, output="/cards/A001/EditorReady/clip.mov")],
            "1 rewrapped, 0 failed",
        )
        self.assertEqual(notifier.opened, [])

    def test_an_old_notify_send_still_notifies_just_without_the_button(self):
        notifier, sender = make(help_text="usage: notify-send [OPTION...]", stdout="")
        notifier.finish(
            [result(runner.REWRAPPED, output="/cards/A001/EditorReady/clip.mov")],
            "1 rewrapped, 0 failed",
        )
        final = sender.calls[-1]
        self.assertFalse([a for a in final if a.startswith("--action")])
        self.assertEqual(final[-2], "Your files are editor-ready")

    def test_nothing_written_means_no_button_to_offer(self):
        notifier, sender = make()
        notifier.finish([result(runner.ALREADY_READY)], "1 already editor-ready, 0 failed")
        self.assertFalse([a for a in sender.calls[-1] if a.startswith("--action")])

    def test_a_failed_run_is_marked_critical(self):
        notifier, sender = make()
        notifier.finish([result(runner.FAILED)], "0 rewrapped, 1 failed")
        argv = sender.calls[-1]
        self.assertEqual(argv[argv.index("--urgency") + 1], "critical")

    def test_a_could_not_start_problem_is_shown_too(self):
        notifier, sender = make()
        notifier.failure("aq-ingest cannot run.\nffmpeg is missing.")
        argv = sender.calls[-1]
        self.assertEqual(argv[-2], "aq-ingest could not run")
        self.assertIn("ffmpeg is missing", argv[-1])

    def test_a_notify_send_that_explodes_does_not_take_the_run_with_it(self):
        def boom(argv, *, timeout):
            raise OSError("no dbus here")

        notifier = notify.Notifier(program="/usr/bin/notify-send", sender=boom)
        notifier.start(2)
        notifier.finish([result(runner.REWRAPPED)], "1 rewrapped, 0 failed")


# ---------------------------------------------------------------------------------
# The --notify flag on the real command line
# ---------------------------------------------------------------------------------


class CommandLineTests(unittest.TestCase):
    def parse(self, *args):
        return cli.build_parser().parse_args([*args])

    def test_notify_is_off_unless_asked_for(self):
        self.assertFalse(self.parse("clip.MP4").notify)
        self.assertTrue(self.parse("--notify", "clip.MP4").notify)

    def test_the_service_menu_command_line_parses(self):
        # Exactly what the Dolphin .desktop file runs, with %F expanded.
        args = self.parse("--notify", "/run/media/royce/CARD/DCIM", "/home/royce/a.MP4")
        self.assertTrue(args.notify)
        self.assertEqual([str(p) for p in args.paths], [
            "/run/media/royce/CARD/DCIM",
            "/home/royce/a.MP4",
        ])
        self.assertFalse(args.dry_run)

    def test_a_notifier_is_only_built_live_when_notify_is_asked_for(self):
        self.assertFalse(cli.make_notifier(self.parse("clip.MP4")).active)

    def test_the_notifier_knows_it_is_a_dry_run(self):
        self.assertTrue(cli.make_notifier(self.parse("--notify", "--dry-run", "x")).dry_run)

    def test_help_mentions_the_right_click_menu(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            with self.assertRaises(SystemExit):
                cli.main(["--help"])
        self.assertIn("Make Editor-Ready", out.getvalue())


if __name__ == "__main__":
    unittest.main()
