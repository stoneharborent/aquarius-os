#!/usr/bin/env python3
"""Does the invisible-desktop helper move on when a desktop cannot start?

WHAT THIS CHECKS, IN PLAIN ENGLISH
----------------------------------
tests/aquarius_headless.py tries several desktops in turn until one comes up.
Build 35043434847 showed the hole: the FIRST one on the list, KDE's
kwin_wayland, could not be executed at all inside the build container (Fedora
gives that program a file capability the container did not have), and the
helper crashed on the spot instead of trying GNOME next.

So this test hands the helper a made-up list of desktops:

  1. one that IS a program and IS executable, but whose exec is refused with
     PermissionError — exactly what the kernel did to kwin_wayland
  2. one that is not there at all
  3. one that starts and dies immediately
  4. one that works

and checks that it walks past 1, 2 and 3 and comes up on 4. Then it hands it a
list where every one fails, and checks the error names ALL of them.

Runs anywhere Python and /bin/sh do. No container, no compositor, no image.
"""

import os
import stat
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aquarius_headless as headless  # noqa: E402


def _write(path, text, executable):
    path.write_text(text)
    mode = 0o700 if executable else 0o600
    path.chmod(mode)
    assert bool(os.stat(path).st_mode & stat.S_IXUSR) is executable
    return path


class _refuse_exec:
    """Make Popen refuse one program the way the kernel refused kwin_wayland."""

    def __init__(self, marker):
        self.marker = marker
        self.real = headless.subprocess.Popen

    def __enter__(self):
        real, marker = self.real, self.marker

        def popen(command, *args, **kwargs):
            if marker in command[0]:
                raise PermissionError(1, "Operation not permitted", command[0])
            return real(command, *args, **kwargs)

        headless.subprocess.Popen = popen
        return self

    def __exit__(self, *_):
        headless.subprocess.Popen = self.real


def _fake_candidates(work, socket, include_working=True):
    """Stand-ins for the real desktop list, in the order they are tried."""
    # 1. Looks perfectly runnable — it is a program, it has the execute bit —
    #    but exec is refused. _refuse_exec() below makes the kernel's answer
    #    for it: the same PermissionError Fedora's capability-bearing
    #    kwin_wayland produced inside the build container.
    unrunnable = _write(work / "cannot-exec", "#!/bin/sh\nexit 0\n", True)
    # 3. Starts and dies at once, without ever making a socket.
    quitter = _write(work / "quits", "#!/bin/sh\nexit 3\n", True)
    # 4. Makes the Wayland socket the helper watches for, then waits.
    worker = _write(
        work / "works",
        '#!/bin/sh\npython3 -c "'
        "import socket,sys;s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1])"
        '" "%s" && sleep 60\n' % (work / "run" / socket),
        True,
    )

    def candidates(runtime_dir, config_dir, xwayland_wrapper, run_after):
        yield ("cannot-exec", [str(unrunnable)], {}, socket, True)
        yield ("not-there", [str(work / "no-such-desktop")], {}, socket, True)
        yield ("quits", [str(quitter)], {}, socket, True)
        if include_working:
            yield ("works", [str(worker)], {}, socket, True)

    return candidates


def check_falls_through_to_a_working_desktop():
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / "run").mkdir(mode=0o700)
        (work / "config").mkdir()
        socket = "aq-test-socket"
        headless._candidates = _fake_candidates(work, socket)
        with (work / "log").open("w+") as log, _refuse_exec("cannot-exec"):
            compositor = headless.start(work / "run", work / "config", log,
                                        dict(os.environ), timeout=20)
            try:
                assert compositor.name == "works", compositor.name
                assert compositor.wayland_display == socket
            finally:
                compositor.stop()
            log.flush()
            log.seek(0)
            text = log.read()
        assert "cannot be started here" in text, text
        print("PASS: an un-runnable desktop is walked past, not crashed on")
        print("PASS: came up on the first desktop that actually works")


def check_every_failure_is_reported():
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / "run").mkdir(mode=0o700)
        (work / "config").mkdir()
        headless._candidates = _fake_candidates(work, "aq-test-socket",
                                                include_working=False)
        with (work / "log").open("w+") as log, _refuse_exec("cannot-exec"):
            try:
                headless.start(work / "run", work / "config", log,
                               dict(os.environ), timeout=3)
            except RuntimeError as problem:
                message = str(problem)
            else:
                raise AssertionError("expected every desktop to fail")
    for expected in ("cannot-exec: cannot be started here",
                     "not-there: not in this image",
                     "quits: stopped on its own (exit 3)"):
        assert expected in message, "%r missing from:\n%s" % (expected, message)
    print("PASS: when every desktop fails, the error names all of them "
          "with its reason")


def check_the_real_list_still_reads_right():
    """The shipped order, and what each one promises about run_after."""
    names = [c[0] for c in headless._real_candidates(
        Path("/run"), Path("/config"), None, None)]
    assert names[0] == "kwin_wayland", names
    assert "gnome-shell" in names, names
    # With an XWayland wrapper asked for, GNOME cannot honour it and is skipped.
    with_wrapper = [c[0] for c in headless._real_candidates(
        Path("/run"), Path("/config"), Path("/wrap"), Path("/after"))]
    assert "gnome-shell" not in with_wrapper, with_wrapper
    print("PASS: shipped order is %s" % ", ".join(names))


if __name__ == "__main__":
    headless._real_candidates = headless._candidates
    check_the_real_list_still_reads_right()
    check_falls_through_to_a_working_desktop()
    check_every_failure_is_reported()
    print("All invisible-desktop helper checks passed.")
