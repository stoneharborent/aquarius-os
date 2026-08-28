"""Desktop notifications (spec §4, §6) — Milestone 2.

When aq-ingest is started from the Dolphin right-click menu there is no terminal for it
to talk to, so it talks to the desktop instead: one notification when it starts, the same
notification updated as files finish, and a final one with the counts and an "Open folder"
button.

Two rules shape everything in here:

  * **Notifications are never load-bearing.** If ``notify-send`` is missing, or the
    notification daemon is not running, or anything at all goes wrong sending one, the
    ingest run carries on exactly as it would have. Nothing in this module raises.
  * **Never claim success that did not happen** (Spark doctrine). The final notification
    counts failures, names the files that failed, and turns red (critical urgency) when
    anything went wrong.

The message-building functions at the top are pure — text in, text out, no subprocesses —
so the wording is testable without a desktop.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from . import runner

#: What the notification says it is. Shown by KDE next to the message.
APP_NAME = "AquariusOS"

#: Icon name, from the AquariusOS logo we ship at
#: /usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg
ICON = "aquarius-logo"

#: The key notify-send prints on stdout when the "Open folder" button is clicked.
OPEN_ACTION = "open"
OPEN_ACTION_LABEL = "Open folder"

#: Statuses that mean a new file was actually written.
_WROTE_SOMETHING = (runner.REWRAPPED, runner.TRANSCODED, runner.CONVERTED)

#: How many failing file names to name before saying "and N more".
_MAX_NAMED_FAILURES = 4

#: Longest file name we put in a notification before shortening the middle.
_MAX_NAME = 48

#: Don't redraw the progress notification more often than this (seconds).
PROGRESS_INTERVAL = 1.0

#: Give up waiting for someone to click "Open folder" after this long (seconds).
_ACTION_TIMEOUT = 3600


# --------------------------------------------------------------------------------------
# Wording — pure functions, no desktop required
# --------------------------------------------------------------------------------------


def escape(text: str) -> str:
    """Make text safe for notification bodies.

    Most notification daemons (KDE's included) read the body as a small subset of HTML, so
    an ampersand or an angle bracket in a file name can swallow the rest of the message.
    """
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def shorten(name: str, limit: int = _MAX_NAME) -> str:
    """Shorten a long file name from the middle, keeping the start and the extension."""
    if len(name) <= limit:
        return name
    keep = limit - 1  # room for the ellipsis
    head = keep // 2
    tail = keep - head
    return f"{name[:head]}…{name[-tail:]}"


def _plural(count: int, singular: str, plural: str | None = None) -> str:
    return f"{count} {singular if count == 1 else (plural or singular + 's')}"


def start_title(dry_run: bool = False) -> str:
    return "Checking your files" if dry_run else "Making your files editor-ready"


def start_body(total: int, dry_run: bool = False) -> str:
    what = _plural(total, "file")
    if dry_run:
        return f"Looking at {what}. Nothing will be changed."
    return f"Working through {what}. Your originals are not changed."


def progress_body(done: int, total: int, name: str, dry_run: bool = False) -> str:
    verb = "Looked at" if dry_run else "Finished"
    return f"{verb} {done} of {total} — {escape(shorten(name))}"


def failed(results: list[runner.Result]) -> list[runner.Result]:
    return [r for r in results if r.status == runner.FAILED]


def wrote_anything(results: list[runner.Result]) -> bool:
    return any(r.status in _WROTE_SOMETHING for r in results)


def output_folders(results: list[runner.Result]) -> list[Path]:
    """Folders that actually received a fixed copy, in the order they were first used."""
    folders: list[Path] = []
    for result in results:
        if result.output and result.status in _WROTE_SOMETHING:
            folder = result.output.parent
            if folder not in folders:
                folders.append(folder)
    return folders


def is_urgent(results: list[runner.Result]) -> bool:
    return bool(failed(results))


def finish_title(results: list[runner.Result], dry_run: bool = False) -> str:
    problems = failed(results)
    if problems:
        return f"{_plural(len(problems), 'file')} could not be made editor-ready"
    if dry_run:
        return "Preview only — nothing was changed"
    if wrote_anything(results):
        return "Your files are editor-ready"
    return "Nothing needed changing"


def finish_body(
    results: list[runner.Result],
    summary: str,
    log_file: Path | None = None,
    dry_run: bool = False,
) -> str:
    lines = [escape(summary)]

    problems = failed(results)
    if problems:
        named = [shorten(r.source.name) for r in problems[:_MAX_NAMED_FAILURES]]
        rest = len(problems) - len(named)
        listed = ", ".join(escape(n) for n in named)
        if rest:
            listed += f", and {rest} more"
        lines.append(f"Could not do: {listed}")
        lines.append("Your originals are untouched.")

    folders = output_folders(results)
    if folders and not dry_run:
        lines.append(f"Fixed copies are in: {escape(str(folders[0]))}")
        if len(folders) > 1:
            lines.append(f"…and {len(folders) - 1} more folder(s).")

    if log_file and problems:
        lines.append(f"Full record: {escape(str(log_file))}")

    return "\n".join(lines)


def failure_title() -> str:
    return "aq-ingest could not run"


# --------------------------------------------------------------------------------------
# Sending — everything below touches the desktop
# --------------------------------------------------------------------------------------


def _run(argv: list[str], *, timeout: int) -> subprocess.CompletedProcess | None:
    """Run a command and never raise. Returns None if it could not be run at all."""
    try:
        return subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None


#: "Nobody told us where notify-send is, so go and look for it." Distinct from being told
#: it is None, which means "there isn't one".
_LOOK_IT_UP = object()


class Notifier:
    """Sends the run's notifications. Silently does nothing when it cannot.

    ``sender`` and ``opener`` exist so the tests can watch what would be sent without a
    desktop anywhere in sight.
    """

    def __init__(
        self,
        *,
        enabled: bool = True,
        dry_run: bool = False,
        sender=None,
        opener=None,
        clock=None,
        program: str | None | object = _LOOK_IT_UP,
        help_text: str | None = None,
    ) -> None:
        self.dry_run = dry_run
        self._sender = sender or _run
        self._opener = opener or self._open_folder
        if clock is None:
            import time

            clock = time.monotonic
        self._clock = clock

        if not enabled:
            self.program: str | None = None
        elif program is _LOOK_IT_UP:
            self.program = shutil.which("notify-send")
        else:
            self.program = program  # type: ignore[assignment]

        self._help_text = help_text
        self._notification_id: str | None = None
        self._last_progress = 0.0

    # -- capability ---------------------------------------------------------------

    @property
    def active(self) -> bool:
        return bool(self.program)

    def supports_actions(self) -> bool:
        """Does this notify-send have --action? (libnotify 0.8 and newer.)

        Without it there is no clickable "Open folder" button — the notification still
        appears, it just has no button.
        """
        if not self.active:
            return False
        if self._help_text is None:
            proc = self._dispatch([self.program, "--help"], timeout=10)
            self._help_text = "" if proc is None else f"{proc.stdout or ''}{proc.stderr or ''}"
        return "--action" in self._help_text

    # -- the three moments in a run -----------------------------------------------

    def start(self, total: int) -> None:
        if not self.active or total <= 0:
            return
        argv = self._base_argv(
            start_title(self.dry_run),
            start_body(total, self.dry_run),
            urgency="low",
            extra=["--print-id"],
        )
        proc = self._dispatch(argv, timeout=15)
        self._notification_id = self._read_id(proc)
        self._last_progress = self._clock()

    def progress(self, done: int, total: int, name: str) -> None:
        """Update the notification in place. Throttled, and skipped for single files."""
        if not self.active or total < 2 or done >= total:
            return
        now = self._clock()
        if now - self._last_progress < PROGRESS_INTERVAL:
            return
        self._last_progress = now
        argv = self._base_argv(
            start_title(self.dry_run),
            progress_body(done, total, name, self.dry_run),
            urgency="low",
        )
        self._dispatch(argv, timeout=15)

    def finish(
        self,
        results: list[runner.Result],
        summary: str,
        log_file: Path | None = None,
    ) -> None:
        if not self.active or not results:
            return

        folders = output_folders(results)
        title = finish_title(results, self.dry_run)
        body = finish_body(results, summary, log_file, self.dry_run)
        urgency = "critical" if is_urgent(results) else "normal"

        offer_open = bool(folders) and not self.dry_run and self.supports_actions()
        if offer_open:
            argv = self._base_argv(
                title,
                body,
                urgency=urgency,
                extra=[f"--action={OPEN_ACTION}={OPEN_ACTION_LABEL}"],
            )
            # --action implies --wait: notify-send stays alive until the notification is
            # closed, then prints the clicked action's name. That is fine — by this point
            # the work is done and this process is only holding a message on screen.
            proc = self._dispatch(argv, timeout=_ACTION_TIMEOUT)
            if proc is not None and OPEN_ACTION in (proc.stdout or "").split():
                try:
                    self._opener(folders[0])
                except Exception:  # noqa: BLE001 — opening a folder is a nicety, not the job
                    pass
            return

        self._dispatch(self._base_argv(title, body, urgency=urgency), timeout=15)

    def failure(self, message: str) -> None:
        """The run could not start, or had to stop. Always critical, never silent."""
        if not self.active:
            return
        argv = self._base_argv(
            failure_title(),
            escape(message.strip()),
            urgency="critical",
        )
        self._dispatch(argv, timeout=15)

    # -- plumbing -------------------------------------------------------------------

    def _dispatch(self, argv: list[str], *, timeout: int):
        """Every call out of this class goes through here, so none of them can raise.

        A notification is a courtesy. Nothing about it — a missing notification daemon, a
        notify-send that changed its flags, a broken D-Bus session — is ever allowed to
        interfere with the ingest run itself.
        """
        try:
            return self._sender(argv, timeout=timeout)
        except Exception:  # noqa: BLE001 — deliberate: see the docstring
            return None

    def _base_argv(
        self, title: str, body: str, *, urgency: str, extra: list[str] | None = None
    ) -> list[str]:
        """Build a notify-send command line. The title and body always come last."""
        argv = [
            self.program,
            "--app-name",
            APP_NAME,
            "--icon",
            ICON,
            "--urgency",
            urgency,
        ]
        if self._notification_id:
            argv += ["--replace-id", self._notification_id]
        argv += extra or []
        argv += [title, body]
        return argv

    @staticmethod
    def _read_id(proc: subprocess.CompletedProcess | None) -> str | None:
        if proc is None or proc.returncode != 0:
            return None
        for line in (proc.stdout or "").splitlines():
            token = line.strip()
            if token.isdigit():
                return token
        return None

    @staticmethod
    def _open_folder(folder: Path) -> None:
        opener = shutil.which("xdg-open")
        if not opener:
            return
        _run([opener, str(folder)], timeout=30)
