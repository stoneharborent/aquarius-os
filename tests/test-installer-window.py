#!/usr/bin/env python3
"""Open the real Installer on an invisible desktop, without installing anything.

Run with python3 tests/test-installer-window.py, or append / to test the
installed image. Requires labwc, GTK 4, libadwaita and dbus-run-session.
The sorter tests cannot catch widget errors: this constructs and maps all four
pages and exercises progress and completion with the real GTK objects.
"""

import importlib.util
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch


def check_window(root):
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, GLib

    # Preload these exact copies, even when another version is installed.
    for name in ("aquarius_installer", "aquarius_ui"):
        spec = importlib.util.spec_from_file_location(
            name, root / "usr/lib/aquarius/python" / (name + ".py"))
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    core = sys.modules["aquarius_installer"]
    ui = sys.modules["aquarius_ui"]
    window_module = runpy.run_path(str(root / "usr/libexec/aquarius-installer"),
                                  run_name="aquarius_installer_window_test")
    errors = []

    def run(app, _argv):
        app.register(None)
        app.activate()
        assert not errors, errors
        window = app.get_active_window()
        assert window is not None, "Installer did not create a window"

        def draw(page):
            window.stack.set_visible_child_name(page)
            until = time.monotonic() + 0.3
            while time.monotonic() < until:
                GLib.MainContext.default().iteration(False)
                time.sleep(0.005)
            child = window.stack.get_child_by_name(page)
            assert window.get_mapped() and child.get_mapped(), page

        try:
            for page in ("browse", "file", "working", "done"):
                draw(page)
            assert window.details.widget.get_parent() is not None
            assert window.done_details.widget.get_parent() is not None
            with patch.object(subprocess, "Popen") as launch:
                window.resolve_button.emit("clicked")
                launch.assert_called_once_with(
                    ["/usr/libexec/aquarius-resolve-installer"], start_new_session=True)
            # Exercise the actual progress handlers; do not start any helper.
            window._start_working("Smoke test", ["Checking", "Finishing"])
            window._progress("STEP 1/2 Checking")
            assert window.step_rows[1].state == ui.ACTIVE
            window._progress("PERCENT 50")
            assert window.bar.get_fraction() == 0.5
            window.details.append("Test log")
            window._progress("FAIL Test failure")
            assert window.step_rows[1].state == ui.FAILED
            assert window.details.widget.get_expanded()
            window._finished(False, "Test failure")
            draw("done")
            assert window.done_details.text() == "Test log\n"
            assert window.done_details.widget.get_expanded()
            assert not window.open_button.get_visible()
            window._finished(True, "Test success")
            draw("done")
            assert window.open_button.get_visible()
            assert not window.done_details.widget.get_expanded()
            window.show_browse()
            draw("browse")
            assert not errors, errors
        finally:
            window.destroy()
            app.quit()
        return 0

    # These reads would contact the real app store. GTK itself is never mocked.
    with patch.object(core, "search", return_value={"here": [], "suggested": [], "flathub": []}), \
            patch.object(core, "flatpak_updates", return_value=[]), \
            patch.object(Adw.Application, "run", run), \
            patch.object(sys, "excepthook", lambda *exc: errors.append(str(exc[1]))):
        assert window_module["run_window"]([]) == 0
    print("PASS: real Installer window mapped all four pages; progress, failure and success work")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        check_window(Path(sys.argv[2]))
        return
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (
        Path(__file__).resolve().parent.parent / "system_files")
    with tempfile.TemporaryDirectory(prefix="aquarius-installer-window-") as temporary:
        work = Path(temporary)
        runtime = work / "runtime"
        runtime.mkdir(mode=0o700)
        config = work / "labwc"
        config.mkdir()
        (config / "rc.xml").write_text("<labwc_config/>\n")
        (config / "autostart").write_text("")
        # No desktop service activation in this private test bus: starting a
        # keyring, screencast portal or file manager is outside this test.
        bus_config = work / "bus.conf"
        bus_config.write_text(
            '<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
            '<policy context="default"><allow own="*"/>'
            '<allow send_destination="*"/><allow receive_sender="*"/>'
            '</policy></busconfig>')
        env = dict(os.environ, HOME=str(work), XDG_RUNTIME_DIR=str(runtime),
                   XDG_CONFIG_HOME=str(work / "config"), XDG_DATA_HOME=str(work / "data"),
                   XDG_CACHE_HOME=str(work / "cache"), GDK_BACKEND="wayland",
                   GSK_RENDERER="cairo", GTK_A11Y="none", GTK_USE_PORTAL="0",
                   ADW_DISABLE_PORTAL="1", GIO_USE_VFS="local", WLR_BACKENDS="headless",
                   WLR_HEADLESS_OUTPUTS="1", WLR_RENDERER="pixman")
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        with (work / "compositor.log").open("w+") as log:
            compositor = subprocess.Popen(["labwc", "-C", str(config)], env=env,
                                          stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                sockets = []
                while time.monotonic() < deadline and compositor.poll() is None:
                    sockets = [p for p in runtime.glob("wayland-*") if p.is_socket()]
                    if sockets:
                        break
                    time.sleep(0.05)
                if not sockets:
                    log.seek(0)
                    raise RuntimeError("Invisible desktop failed to start:\n" + log.read())
                env["WAYLAND_DISPLAY"] = sockets[0].name
                subprocess.run(["dbus-run-session", "--config-file", str(bus_config),
                                "--", sys.executable,
                                str(Path(__file__).resolve()), "--worker", str(root)],
                               env=env, check=True, timeout=30)
            finally:
                compositor.terminate()
                compositor.wait(timeout=5)


if __name__ == "__main__":
    main()
