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
    from gi.repository import Adw, GLib, Gtk

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
            # A Windows download has a genuine handoff page, without an Open
            # button pretending a Windows app has already been installed.
            with tempfile.TemporaryDirectory() as downloads:
                exe = Path(downloads) / "Windows setup.EXE"
                exe.write_bytes(b"MZ" + b"\0" * 64)
                window.take_file(str(exe))
                draw("file")
                assert window.install_button.get_label() == "Continue in Bottles"
                assert window.install_button.get_visible()
                assert "first-run" in window.file_note.get_label()
                page = window.stack.get_child_by_name("file")
                adjustment = page.get_vadjustment()
                adjustment.set_value(adjustment.get_upper() - adjustment.get_page_size())
                draw("file")
                assert window.install_button.get_mapped()
                with patch.object(window_module["threading"], "Thread") as worker:
                    window._on_install(None)
                    worker.return_value.start.assert_called_once()
                assert window.working_title.get_label() == "Preparing Windows setup"
                assert len(window.step_rows) == 3
                window._progress("STEP 3/3 Opening Windows setup")
                window._progress("HANDOFF " + core.BOTTLES_ID)
                assert window.step_rows[3].state == ui.DONE
                window._finished(True, core.WINDOWS_NEXT, "handoff")
                draw("done")
                assert window.done_title.get_label() == "Continue in Bottles"
                assert not window.open_button.get_visible()
                window._finished(False, "Bottles setup was cancelled.", "failed")
                assert "cancelled" in window.done_blurb.get_label()
                assert not window.open_button.get_visible()
                linux = Path(downloads) / "Linux.AppImage"
                linux.write_bytes(b"dummy fixture")
                window.take_file(str(linux))
                draw("file")
                assert window.install_button.get_label() == "Install"
            # -- Cancel really stops, and a late answer cannot undo it ------
            # ⚠️ THE FAULT OF 2026-09-13: Cancel only changed the page, the
            # install carried on, and its answer dragged the person onto "All
            # set." for something they had stopped.
            window._start_working("Cancel test", ["Working"])
            window._on_cancel(None)
            assert window.cancel_requested
            assert window.cancel_event.is_set(), "the worker was not told to stop"
            assert os.path.isfile(window.cancel_file), \
                "the app helper was not told to stop"
            assert not window.cancel_button.get_sensitive()
            assert window.stack.get_visible_child_name() == "working", \
                "Cancel left the working page before the worker had stopped"
            assert "finishes first" in window.working_blurb.get_label(), \
                "Cancel promises more than the app helper can do"
            window._finished(True, "Installed after all")
            draw("done")
            assert window.done_title.get_label() == "Stopped."
            assert not window.open_button.get_visible()

            # ⚠️ AND THE HONEST HALF OF THE SAME STORY. The app helper stops
            # only BETWEEN apps, so one already downloading finishes. "Stopped.
            # Nothing was left behind." would be a lie, and the app the person
            # now has would have no button to open it.
            window._start_working("Late cancel", ["Working"])
            window._on_cancel(None)
            assert not window.helper_cancelled
            late = window_module["helper_ending"](True, False, 0, "OBS Studio")
            window._finished(*late)
            draw("done")
            assert window.done_title.get_label() == "Stopped."
            assert "already finished installing" in window.done_blurb.get_label()
            assert window.open_button.get_visible(), \
                "the app really is installed and must be openable"
            # ...and a helper that did stop still says nothing was left behind.
            window._start_working("On-time cancel", ["Working"])
            window._on_cancel(None)
            window._progress("CANCELLED")
            assert window.helper_cancelled
            window._finished(*window_module["helper_ending"](True, True, 0,
                                                             "OBS Studio"))
            draw("done")
            assert window.done_blurb.get_label() == core.SAY["cancelled"]
            assert not window.open_button.get_visible()

            # -- Open presses what was written, not a name it guessed -------
            window._start_working("Open test", ["Working"])
            with tempfile.TemporaryDirectory() as entries:
                entry = Path(entries) / "openapp.desktop"
                entry.write_text("[Desktop Entry]\nType=Application\n"
                                 "Name=Open App\n")
                window.open_entry = str(entry)
                with patch.object(subprocess, "Popen") as launch:
                    window._on_open(None)
                    launch.assert_called_once_with(
                        ["gio", "launch", str(entry)], start_new_session=True)

            # -- the Editor has a Remove button and Aquarius Writer does not -
            def buttons(row):
                found, queue = [], [row]
                while queue:
                    widget = queue.pop()
                    if isinstance(widget, Gtk.Button):
                        found.append(widget.get_label())
                    child = widget.get_first_child()
                    while child is not None:
                        queue.append(child)
                        child = child.get_next_sibling()
                return [label for label in found if label]

            editor = core.Row("aquarius-editor", "Aquarius Editor", "1.0",
                              core.ROUTE_APPIMAGE, removable=True, managed=True,
                              note="updates with %s" % core.OS_NAME)
            part_of_os = core.Row("aquarius-writer", "Aquarius Writer", "1.0",
                                  core.ROUTE_APPIMAGE, removable=False,
                                  note="part of %s" % core.OS_NAME)
            assert "Remove" in buttons(window._installed_row(editor)), \
                "the window offers no Remove where the terminal removes it"
            assert "Remove" not in buttons(window._installed_row(part_of_os)), \
                "a part of the operating system must have no buttons"

            # -- the search bar asks nothing slow on the drawing thread -----
            with patch.object(core, "flatpak_updates",
                              side_effect=AssertionError("asked per keystroke")), \
                    patch.object(core, "flathub_search", return_value=[]):
                window.search.set_text("ob")
                window.refresh()
                window.search.set_text("")
                if window.search_timer:
                    GLib.source_remove(window.search_timer)
                    window.search_timer = 0

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
    print("PASS: real Installer window mapped all four pages; progress, failure, success and Windows handoff work")


def main(check=check_window):
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        check(Path(sys.argv[2]))
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
                                str(Path(sys.argv[0]).resolve()), "--worker", str(root)],
                               env=env, check=True, timeout=30)
            finally:
                compositor.terminate()
                compositor.wait(timeout=5)


if __name__ == "__main__":
    main()
