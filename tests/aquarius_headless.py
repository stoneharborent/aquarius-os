#!/usr/bin/env python3
"""An invisible desktop for the window tests, on whichever one this image has.

WHAT THIS IS FOR, IN PLAIN ENGLISH
----------------------------------
Two of our tests open a REAL window — the Aquarius Installer window, and the
DaVinci Resolve geometry check. A window needs a desktop to open onto, and a
build machine has no screen. So these tests start a compositor (the program
that draws windows) with an INVISIBLE screen, open the window onto it, read
what happened, and shut it down again.

⚠️ WHY THIS FILE EXISTS AT ALL — 2026-09-15
-------------------------------------------
Both tests used to say `labwc` and nothing else, because labwc was in the image:
it was the window manager of the Aquarius Session. That desktop was retired in
favour of GNOME and KDE Plasma (../docs/decision-2026-09-15-two-desktops.md),
labwc left the image with it, and two build steps would have started failing
with "No such file or directory" — a failure that says nothing at all about
what actually changed.

So the choice of compositor is asked here, once, and both tests ask this file.

WHAT IT TRIES, IN ORDER, AND WHY
--------------------------------
  1. kwin_wayland --virtual   KDE Plasma's compositor, in the headless mode KDE
                              themselves test with. It is in every AquariusOS
                              image (build_files/41-kde-desktop.sh) and it does
                              XWayland with a wrapper we can point at software
                              rendering, which the Resolve test needs.
  2. gnome-shell --headless   GNOME's, in its own headless mode. Also in every
                              image. Heavier to start, which is why it is
                              second, but it is a real second answer rather than
                              a hope. It has no "start this program for me"
                              switch, so when one is asked for we start that
                              program ourselves once the desktop is up.
  3. labwc                    only if somebody running these tests by hand on
                              their own machine happens to have it. Never in an
                              AquariusOS image any more.

⚠️ A CANDIDATE CAN FAIL BEFORE IT EVEN STARTS — 2026-09-15
----------------------------------------------------------
Fedora ships kwin_wayland with a FILE CAPABILITY (cap_sys_nice+ep — the kernel
grants it the right to raise its own scheduling priority). A container is only
allowed to run such a program if that capability is in the container's own
bounding set. Podman's default set does not include SYS_NICE, so the kernel
refuses the program before a single line of KWin runs, and Python sees:

    PermissionError: [Errno 1] Operation not permitted: 'kwin_wayland'

That is exactly what failed build 35043434847. Two things came of it:

  * the CI steps that run these tests now pass `--cap-add=SYS_NICE` to podman
    (.github/workflows/build.yml), so KWin can be executed at all; and
  * this file now treats ANY OSError from starting a candidate — cannot be
    executed, is not there, is not a program — as "this desktop cannot run
    here", writes the reason into the attempt list, and moves to the next
    candidate. Only when every candidate has failed does it raise, with every
    attempt's reason and the whole log.

If none of them starts, this raises with every attempt's log in the message.
It never quietly skips: a window test that does not run is a window test that
passes forever.
"""

import os
import subprocess
import time


class Compositor:
    """A started compositor: .process, .wayland_display, .name, .log_path."""

    def __init__(self, process, wayland_display, name, log_path, child=None):
        self.process = process
        self.wayland_display = wayland_display
        self.name = name
        self.log_path = log_path
        # child is the run_after program when WE had to start it (GNOME Shell
        # has no switch for it). None when the compositor started it itself.
        self.child = child

    def stop(self):
        for process in (self.child, self.process):
            if process is None:
                continue
            try:
                process.terminate()
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            except OSError:  # already gone
                pass


def _candidates(runtime_dir, config_dir, xwayland_wrapper, run_after):
    """The command lines, in the order they are tried.

    Each one is (name, command, extra environment, socket name, starts_run_after).

    run_after, if given, is a program that must run once the desktop is up.
    labwc's `-s` and kwin_wayland's trailing argument do that themselves
    (starts_run_after True). GNOME Shell has no such switch, so it says False
    and start() launches the program itself once the socket appears.

    GNOME Shell is skipped when an XWayland wrapper is asked for: mutter reads
    no such variable, so it could not honour the software-rendering wrapper the
    Resolve test needs and would give a confusing pass-that-is-not-a-pass.
    """
    socket = "aq-test-%d" % os.getpid()

    kwin = ["kwin_wayland", "--virtual", "--width", "1920", "--height", "1080",
            "--socket", socket, "--no-global-shortcuts"]
    if xwayland_wrapper is not None:
        kwin.append("--xwayland")
    if run_after is not None:
        kwin.append(str(run_after))
    # KWIN_COMPOSE=Q is KWin's software (QPainter) renderer. A build machine has
    # no GPU, and on the NVIDIA image it has NVIDIA's libraries and no card,
    # which is the worst of both.
    kwin_env = {"KWIN_COMPOSE": "Q", "QT_QPA_PLATFORM": "offscreen",
                "KWIN_WAYLAND_NO_PERMISSION_CHECKS": "1"}
    if xwayland_wrapper is not None:
        kwin_env["KWIN_XWAYLAND"] = str(xwayland_wrapper)
    yield ("kwin_wayland", kwin, kwin_env, socket, True)

    if xwayland_wrapper is None:
        shell = ["gnome-shell", "--headless", "--wayland",
                 "--wayland-display", socket,
                 "--virtual-monitor", "1920x1080"]
        yield ("gnome-shell", shell, {"MUTTER_DEBUG_DUMMY_MODE_SPECS": "1920x1080"},
               socket, False)

    labwc = ["labwc", "-C", str(config_dir)]
    if run_after is not None:
        labwc += ["-s", str(run_after)]
    labwc_env = {"WLR_BACKENDS": "headless", "WLR_HEADLESS_OUTPUTS": "1",
                 "WLR_RENDERER": "pixman"}
    if xwayland_wrapper is not None:
        labwc_env["WLR_XWAYLAND"] = str(xwayland_wrapper)
    yield ("labwc", labwc, labwc_env, None, True)


def start(runtime_dir, config_dir, log, env,
          xwayland_wrapper=None, run_after=None, timeout=20):
    """Start an invisible desktop and return a Compositor.

    runtime_dir  a private XDG_RUNTIME_DIR (mode 0700) — the Wayland socket
                 appears in here, which is how we know it started
    config_dir   a scratch folder for compositors that want one
    log          an open file, in "w+" mode, that gets everything it printed
    env          the base environment; each candidate adds its own variables
    """
    attempts = []
    for name, command, extra, socket, starts_run_after in _candidates(
            runtime_dir, config_dir, xwayland_wrapper, run_after):
        if _which(command[0], env) is None:
            attempts.append("%s: not in this image" % name)
            continue

        run_env = dict(env)
        run_env.update(extra)
        run_env["XDG_RUNTIME_DIR"] = str(runtime_dir)
        if socket:
            run_env["WAYLAND_DISPLAY"] = socket
        run_env.pop("DISPLAY", None)

        log.write("== trying %s: %s\n" % (name, " ".join(command)))
        log.flush()
        try:
            process = subprocess.Popen(command, env=run_env,
                                       stdout=log, stderr=log)
        except OSError as problem:
            # The program is there but the kernel would not run it — a file
            # capability the container cannot grant (KWin's cap_sys_nice), a
            # missing shared library, a file that is not a program at all.
            # That is this desktop saying "not here", not the end of the road.
            reason = "%s: cannot be started here (%s)" % (name, problem)
            log.write("== %s\n" % reason)
            log.flush()
            attempts.append(reason)
            continue

        deadline = time.monotonic() + timeout
        found = None
        while time.monotonic() < deadline and process.poll() is None:
            sockets = [p for p in runtime_dir.glob("*")
                       if p.is_socket() and (socket is None or p.name == socket)
                       and (socket is not None or p.name.startswith("wayland-"))]
            if sockets:
                found = sockets[0].name
                break
            time.sleep(0.05)

        if found:
            log.write("== %s is up on %s\n" % (name, found))
            log.flush()
            child = None
            if run_after is not None and not starts_run_after:
                child_env = dict(run_env)
                child_env["WAYLAND_DISPLAY"] = found
                log.write("== starting %s ourselves on %s\n" % (run_after, found))
                log.flush()
                try:
                    child = subprocess.Popen([str(run_after)], env=child_env,
                                             stdout=log, stderr=log)
                except OSError as problem:
                    log.write("== could not start %s: %s\n" % (run_after, problem))
                    log.flush()
                    _stop_quietly(process)
                    attempts.append("%s: came up, but %s could not be started (%s)"
                                    % (name, run_after, problem))
                    continue
            return Compositor(process, found, name, getattr(log, "name", None),
                              child=child)

        died = process.poll()
        _stop_quietly(process)
        if died is not None:
            attempts.append("%s: stopped on its own (exit %s) before a Wayland "
                            "socket appeared" % (name, died))
        else:
            attempts.append("%s: started but no Wayland socket within %ds"
                            % (name, timeout))

    log.flush()
    log.seek(0)
    raise RuntimeError(
        "No invisible desktop could be started. Tried:\n  "
        + "\n  ".join(attempts)
        + "\n\nThe log of every attempt:\n" + log.read())


def _stop_quietly(process):
    """Stop a process we have given up on. A dead one is what we wanted."""
    try:
        process.terminate()
        process.wait(timeout=5)
    except Exception:  # noqa: BLE001
        try:
            process.kill()
            process.wait(timeout=5)
        except Exception:  # noqa: BLE001
            pass


def _which(program, env):
    path = env.get("PATH", os.environ.get("PATH", ""))
    for folder in path.split(os.pathsep):
        candidate = os.path.join(folder, program)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None
