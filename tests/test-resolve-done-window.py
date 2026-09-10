#!/usr/bin/env python3
"""Check the real Resolve completion page with a newly exported app icon.

Uses the Installer's invisible-desktop harness. No installation is started.
Set AQ_RESOLVE_TEST_ICON to an existing local icon for visual QA; the default
fixture is a plain square, not bundled Blackmagic artwork.
"""
import importlib.util
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import time
from unittest.mock import patch


def check(root):
    spec = importlib.util.spec_from_file_location(
        "aquarius_ui", root / "usr/lib/aquarius/python/aquarius_ui.py")
    ui = importlib.util.module_from_spec(spec)
    sys.modules["aquarius_ui"] = ui
    spec.loader.exec_module(ui)
    module = runpy.run_path(str(root / "usr/libexec/aquarius-resolve-installer"),
                            run_name="resolve_done_test")
    from gi.repository import Adw, Gio, GLib

    app = Adw.Application(application_id="org.aquariusos.ResolveDoneTest",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.register(None)
    with patch.dict(module["InstallerWindow"].__init__.__globals__,
                    {"cli_query": lambda *_args: ""}):
        window = module["InstallerWindow"](app, dry_run=True)
    assert window.done_logo.get_icon_name() == "video-x-generic-symbolic"
    data = Path(os.environ["XDG_DATA_HOME"])
    entries = data / "applications"
    entries.mkdir(parents=True)
    icon = data / "resolve.svg"
    if os.environ.get("AQ_RESOLVE_TEST_ICON"):
        source = Path(os.environ["AQ_RESOLVE_TEST_ICON"])
        icon = data / ("resolve" + source.suffix)
        shutil.copyfile(source, icon)
    else:
        icon.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96">'
                        '<rect width="96" height="96" fill="blue"/></svg>')
    (entries / "aquarius-resolve-com.blackmagicdesign.resolve.desktop").write_text(
        '[Desktop Entry]\nType=Application\nName=DaVinci Resolve\n'
        'Exec=/bin/true\nIcon=' + str(icon) + '\n')
    window.finished = True
    window._process_exited(0)
    assert window.done_logo.get_gicon().get_file().get_path() == str(icon)
    window.present()
    until = time.monotonic() + 1
    while time.monotonic() < until:
        GLib.MainContext.default().iteration(False)
        time.sleep(0.005)
    assert window.done_logo.get_mapped()
    if os.environ.get("AQ_RESOLVE_TEST_SCREENSHOT"):
        subprocess.run(["grim", os.environ["AQ_RESOLVE_TEST_SCREENSHOT"]], check=True)
    icon.unlink()
    window._refresh_done_logo()
    assert window.done_logo.get_icon_name() == "video-x-generic-symbolic"
    window.destroy()
    app.quit()
    print("PASS: completion page loads newly exported icon; missing icon has visible fallback")


if __name__ == "__main__":
    harness = runpy.run_path(str(Path(__file__).with_name("test-installer-window.py")))
    harness["main"](check)
