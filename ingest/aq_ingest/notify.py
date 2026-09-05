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

--------------------------------------------------------------------------------------
THE PROGRESS BAR (added 2026-09-04, Royce's bench request)
--------------------------------------------------------------------------------------
Converting a card of footage takes minutes, and "it started" followed by silence is not
enough to know whether to go and make a coffee. So the one notification a run puts on
screen now carries **a filling bar and a plain time left**, and is redrawn in place as the
work proceeds:

    ┌──────────────────────────────────────────────┐
    │ ⬤  Making your files editor-ready          × │
    │    Converting A001_C003.MP4 · 42% ·           │
    │    about 2 min left                           │
    │    ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░                     │
    └──────────────────────────────────────────────┘

**Why it is still `notify-send` and not a D-Bus client of our own.** Everything the bar
needs is already on this command line and already proven on Royce's bench machine:

  * ``--print-id`` / ``--replace-id`` are how one notification is updated instead of a
    hundred piling up. They have been in libnotify since 0.8 (Fedora 44 ships 0.8.x) and
    this module has been using them since Milestone 2 — the start → finish replacement was
    confirmed working on the bench on 2026-08-28.
  * ``--hint=int:value:NN`` is the standard progress hint, understood by KDE, our own
    Aquarius shell, and every daemon descended from Ubuntu's. It has been in notify-send
    far longer than ``--action``, which we already probe for.
  * The alternative — talking to ``org.freedesktop.Notifications`` through
    ``gi.repository.Gio`` — would put **python3-gobject** on aq-ingest's critical path.
    The spec's rule for this tool is *Python 3, standard library only, shelling out to
    ffmpeg*, and taking on a GObject dependency so that a courtesy message can be drawn
    would be the wrong way round. Notifications are never load-bearing; their transport
    should not be either.

**GNOME renders the same information.** GNOME Shell ignores the ``value`` hint entirely —
it has no progress bar in its notification — but it honours ``replaces_id``, so the one
notification updates in place, and the percentage and the time left are in the **body
text**, which it does draw. That is why the numbers are words as well as a hint: a desktop
that cannot show a bar still shows the progress.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from . import runner
from .progress import Snapshot

#: What the notification says it is. Shown by KDE next to the message.
APP_NAME = "AquariusOS"

#: Icon name, from the AquariusOS logo we ship at
#: /usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg
ICON = "aquarius-logo"

#: The key notify-send prints on stdout when the button on the final message is clicked.
OPEN_ACTION = "open"

#: What that button says. "Show in Files" names the actual application it opens — Files is
#: the file manager in both the Aquarius Session and the GNOME fallback — which is more
#: use to somebody new to Linux than the generic "Open folder" this used to say.
OPEN_ACTION_LABEL = "Show in Files"

#: The progress hint. An int from 0 to 100; daemons that understand it draw a bar.
#: https://specifications.freedesktop.org/notification-spec/latest/hints.html
VALUE_HINT = "value"

#: The "this message replaces the last one with the same tag" hint. Belt and braces
#: alongside --replace-id: a daemon that honours one or the other still ends up with a
#: single notification rather than a stack of them.
SYNCHRONOUS_HINT = "x-canonical-private-synchronous"
SYNCHRONOUS_TAG = "aq-ingest"

#: notify-send's spelling of "do not take this off the screen by yourself". The progress
#: message uses it so a long conversion is not represented by a toast that vanished four
#: minutes ago; the final message carries no such request and goes away on its own.
NEVER_EXPIRE = "0"

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


#: The separator between the parts of the working message. A middle dot rather than a
#: comma, because two of the three parts already contain commas' worth of words.
_DOT = " · "


def working_body(snapshot: Snapshot) -> str:
    """The line under the title while a conversion is running.

    One file:      ``Converting clip.MP4 · 42% · about 2 min left``
    Several:       ``Converting 3 files · 1 of 3 · 38% · about 5 min left``

    The time left is left off entirely until there is one worth printing — for the first
    couple of seconds of a run any estimate is nonsense, and printing a nonsense one is
    worse than printing none.

    The word is "files", not "clips", because a run can contain iPhone photos as well as
    footage and this message must be true of both.
    """
    parts: list[str] = []
    if snapshot.total <= 1:
        name = escape(shorten(snapshot.name)) if snapshot.name else "your file"
        parts.append(f"Converting {name}")
    else:
        parts.append(f"Converting {_plural(snapshot.total, 'file')}")
        parts.append(f"{snapshot.file_number} of {snapshot.total}")
    parts.append(f"{snapshot.percent}%")
    if snapshot.time_left:
        parts.append(snapshot.time_left)
    return _DOT.join(parts)


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


def written(results: list[runner.Result]) -> list[runner.Result]:
    """The files that actually got a new copy written for them."""
    return [r for r in results if r.status in _WROTE_SOMETHING]


def finish_title(results: list[runner.Result], dry_run: bool = False) -> str:
    problems = failed(results)
    if problems:
        return f"{_plural(len(problems), 'file')} could not be made editor-ready"
    if dry_run:
        return "Preview only — nothing was changed"

    made = written(results)
    # Right-clicking ONE clip is the commonest way this tool is used, and in that case
    # naming the file is far more use than "your files": it says which of the four things
    # you set going a minute ago has just finished.
    if len(made) == 1:
        return f"{shorten(made[0].source.name)} is editor-ready"
    if made:
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
        one = len(written(results)) == 1
        label = "The fixed copy is in" if one else "Fixed copies are in"
        lines.append(f"{label}: {escape(str(folders[0]))}")
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
        self._last_percent = -1

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
        return "--action" in self._help()

    def supports_hints(self) -> bool:
        """Does this notify-send have --hint? (Every libnotify since 0.4 does.)

        Probed rather than assumed for the same reason --action is: a notify-send that
        does not have the flag would refuse the whole command line, and losing the message
        entirely to gain a progress bar would be a bad trade. Without it the bar is
        missing and the percentage in the body text still says everything.
        """
        if not self.active:
            return False
        return "--hint" in self._help()

    def _help(self) -> str:
        """notify-send's own --help output, asked for once and remembered."""
        if self._help_text is None:
            proc = self._dispatch([self.program, "--help"], timeout=10)
            self._help_text = "" if proc is None else f"{proc.stdout or ''}{proc.stderr or ''}"
        return self._help_text

    # -- the three moments in a run -----------------------------------------------

    def start(self, total: int) -> None:
        if not self.active or total <= 0:
            return
        argv = self._base_argv(
            start_title(self.dry_run),
            start_body(total, self.dry_run),
            urgency="low",
            # A run can take twenty minutes. Asking the desktop not to take this off the
            # screen by itself is what stops the progress bar disappearing four minutes in
            # and leaving the person with no idea whether anything is still happening.
            # The final message replaces this one and does NOT ask for that, so it behaves
            # like any other notification and goes away on its own.
            expire=None if self.dry_run else NEVER_EXPIRE,
            progress=0 if not self.dry_run else None,
            extra=["--print-id"],
        )
        proc = self._dispatch(argv, timeout=15)
        self._notification_id = self._read_id(proc)
        self._last_progress = self._clock()
        self._last_percent = 0

    def working(self, snapshot: Snapshot) -> None:
        """Redraw the notification with the bar and the time left.

        Called as often as ffmpeg reports — twice a second or so — and deliberately
        ignores almost all of them. A notification redrawn thirty times a second is a
        notification that flickers, and on some daemons it is also one that re-triggers a
        sound. So: at most once a second, and only when the percentage has actually moved.
        """
        if not self.active or self.dry_run or snapshot.total <= 0:
            return
        if snapshot.percent == self._last_percent:
            return
        now = self._clock()
        if now - self._last_progress < PROGRESS_INTERVAL:
            return
        self._last_progress = now
        self._last_percent = snapshot.percent

        argv = self._base_argv(
            start_title(self.dry_run),
            working_body(snapshot),
            urgency="low",
            expire=NEVER_EXPIRE,
            progress=snapshot.percent,
        )
        self._dispatch(argv, timeout=15)

    def progress(self, done: int, total: int, name: str) -> None:
        """The dry-run counter: "Looked at 3 of 12".

        A dry run runs no ffmpeg, so there is nothing to measure and no bar to draw — it
        only walks the files and says what it would do. Counting them is the whole of the
        progress there is.
        """
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
        self,
        title: str,
        body: str,
        *,
        urgency: str,
        extra: list[str] | None = None,
        expire: str | None = None,
        progress: int | None = None,
    ) -> list[str]:
        """Build a notify-send command line. The title and body always come last.

        ``progress`` is the 0–100 the desktop draws as a bar. Passing it also tags the
        message, so a daemon that replaces by tag rather than by id still shows one
        notification rather than a growing stack.

        No ``desktop-entry`` hint is sent, on purpose. That hint names a ``.desktop`` file
        so the desktop can look up an icon and group by application — and aq-ingest has no
        ``.desktop`` file of its own (it is reached from the Files right-click menu, not
        from the app grid). Naming one that does not exist would be a small lie that buys
        nothing: ``--app-name AquariusOS`` already groups every message from this tool
        together, and ``--icon`` already supplies the icon.
        """
        argv = [
            self.program,
            "--app-name",
            APP_NAME,
            "--icon",
            ICON,
            "--urgency",
            urgency,
        ]
        if expire is not None:
            argv += ["--expire-time", expire]
        if progress is not None and self.supports_hints():
            argv += [
                f"--hint=int:{VALUE_HINT}:{max(0, min(100, int(progress)))}",
                f"--hint=string:{SYNCHRONOUS_HINT}:{SYNCHRONOUS_TAG}",
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
