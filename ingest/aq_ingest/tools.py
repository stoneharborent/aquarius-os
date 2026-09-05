"""Finding and running the outside programs aq-ingest depends on.

Everything that touches a subprocess funnels through here so error messages stay
plain-language and consistent (spec §9).
"""

from __future__ import annotations

import shutil
import subprocess
import threading


class ToolMissing(Exception):
    """A program we need is not installed. The message tells the user how to fix it."""


class ToolFailed(Exception):
    """A program ran but did not succeed. The message quotes the useful part of its output."""


INSTALL_HINTS = {
    "ffmpeg": "ffmpeg is missing. On AquariusOS it ships with the system; "
    "on another Linux install it with your package manager (for example: "
    "sudo dnf install ffmpeg, or sudo apt install ffmpeg).",
    "ffprobe": "ffprobe is missing. It comes with ffmpeg — installing ffmpeg installs it too.",
    "heif-convert": "heif-convert is missing, so iPhone HEIC photos cannot be converted. "
    "Install libheif's tools (for example: sudo dnf install libheif-tools, "
    "or sudo apt install libheif-examples).",
}


def find(program: str) -> str | None:
    return shutil.which(program)


def require(program: str) -> str:
    path = find(program)
    if not path:
        raise ToolMissing(INSTALL_HINTS.get(program, f"{program} is not installed."))
    return path


def _tail(text: str, lines: int = 12) -> str:
    useful = [line for line in (text or "").strip().splitlines() if line.strip()]
    return "\n".join(useful[-lines:])


def run(argv: list[str], *, timeout: int = 3600) -> subprocess.CompletedProcess:
    """Run a command, capturing output. Raises ToolFailed with a readable message."""
    try:
        proc = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise ToolMissing(INSTALL_HINTS.get(argv[0], f"{argv[0]} is not installed.")) from exc
    except subprocess.TimeoutExpired as exc:
        raise ToolFailed(
            f"{argv[0]} took longer than {timeout} seconds and was stopped."
        ) from exc
    if proc.returncode != 0:
        detail = _tail(proc.stderr) or _tail(proc.stdout) or "no details given"
        raise ToolFailed(f"{argv[0]} could not finish this file. It said:\n{detail}")
    return proc


def run_watching(argv: list[str], on_line, *, timeout: int = 3600) -> subprocess.CompletedProcess:
    """Like :func:`run`, but hands each line of stdout to ``on_line`` as it arrives.

    This is how the progress bar gets its numbers: ffmpeg is started with
    ``-progress pipe:1``, which makes it print its position on stdout every half second,
    and ``on_line`` turns those lines into a percentage while the conversion is still
    going. :func:`run` cannot do this — ``subprocess.run`` hands back the output only once
    the program has already finished, which for a ten-minute transcode is ten minutes too
    late.

    Two details that are easy to get wrong and expensive to debug:

    * **stderr is drained by a second thread.** A pipe holds about 64KB; if nobody reads
      it, the program filling it stops dead the moment it is full. We are busy reading
      stdout, so a chatty ffmpeg would deadlock — it would sit there forever, having
      converted nothing, with no error anywhere. The thread makes that impossible.
    * **``on_line`` is not allowed to break the conversion.** It draws a notification;
      that is a courtesy, and the same rule applies to it as to everything in notify.py.
      Anything it raises is swallowed here and the conversion carries on.
    """
    try:
        proc = subprocess.Popen(  # noqa: S603 — argv is built by us, never from user text
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # line buffered, so a progress line arrives when it is written
        )
    except FileNotFoundError as exc:
        raise ToolMissing(INSTALL_HINTS.get(argv[0], f"{argv[0]} is not installed.")) from exc
    except OSError as exc:
        raise ToolFailed(f"{argv[0]} could not be started: {exc}") from exc

    errors: list[str] = []

    def drain_errors() -> None:
        try:
            assert proc.stderr is not None
            for line in proc.stderr:
                errors.append(line)
        except (OSError, ValueError):
            pass

    watcher = threading.Thread(target=drain_errors, daemon=True)
    watcher.start()

    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            try:
                on_line(line)
            except Exception:  # noqa: BLE001 — a progress bar may never kill a conversion
                pass
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        proc.kill()
        proc.wait()
        watcher.join(timeout=5)
        raise ToolFailed(
            f"{argv[0]} took longer than {timeout} seconds and was stopped."
        ) from exc
    finally:
        watcher.join(timeout=5)
        for stream in (proc.stdout, proc.stderr):
            if stream is not None:
                try:
                    stream.close()
                except OSError:
                    pass

    stderr = "".join(errors)
    if proc.returncode != 0:
        detail = _tail(stderr) or "no details given"
        raise ToolFailed(f"{argv[0]} could not finish this file. It said:\n{detail}")
    return subprocess.CompletedProcess(argv, proc.returncode, "", stderr)
