"""Finding and running the outside programs aq-ingest depends on.

Everything that touches a subprocess funnels through here so error messages stay
plain-language and consistent (spec §9).
"""

from __future__ import annotations

import shutil
import subprocess


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
