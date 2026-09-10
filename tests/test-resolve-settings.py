#!/usr/bin/python3
"""Map real display controls and exercise safe settings actions in isolation."""
import importlib.util
import os
from pathlib import Path
import runpy
import subprocess
import sys
import time
from unittest.mock import patch


def check(root):
    spec = importlib.util.spec_from_file_location('aquarius_ui', root/'usr/lib/aquarius/python/aquarius_ui.py')
    ui = importlib.util.module_from_spec(spec)
    sys.modules['aquarius_ui'] = ui
    spec.loader.exec_module(ui)
    config = Path(os.environ['XDG_CONFIG_HOME'])/'aquarius/resolve.conf'
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text('# keep this note\nfuture_option=yes\nscale=1.5\nscale=\n')
    m = runpy.run_path(str(root/'usr/libexec/aquarius-resolve-settings'), run_name='resolve_settings_test')
    from gi.repository import Adw, Gio, GLib, Gtk
    Gtk.Settings.get_default().set_property("gtk-decoration-layout", "close,minimize,maximize:")
    assert m['read_scale']() == ''
    app = Adw.Application(application_id='org.aquariusos.ResolveSettingsTest', flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.register(None)
    w = m['SettingsWindow'](app)
    w.present()
    until = time.monotonic()+.4
    while time.monotonic()<until:
        GLib.MainContext.default().iteration(False)
        time.sleep(.005)
    assert w.get_mapped() and w.size.get_mapped()
    if os.environ.get('AQ_RESOLVE_SETTINGS_SCREENSHOT'):
        capture = subprocess.Popen(['grim', os.environ['AQ_RESOLVE_SETTINGS_SCREENSHOT']])
        until = time.monotonic()+3
        while capture.poll() is None and time.monotonic()<until:
            GLib.MainContext.default().iteration(False)
            time.sleep(.005)
        assert capture.wait(timeout=1) == 0
    with patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
        w.size.set_selected(2)
        assert run.call_args.args[0] == ['/usr/bin/aq', 'resolve', 'scale', '1.25']
        assert 'Saved.' in w.status.get_label()
    with patch.object(subprocess, 'Popen') as launch, patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as request:
        w.reset_position()
        assert request.call_args.args[0] == ['/usr/libexec/aquarius-resolve-window', '--request-reset']
        assert launch.call_args.args[0] == ['/usr/libexec/aquarius-resolve-window']
    with patch.object(subprocess, 'Popen') as launch, patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
        w.reset_position()
        assert 'Could not reset' in w.status.get_label()
        launch.assert_not_called()
    with patch.object(subprocess, 'run', side_effect=OSError('test refusal')):
        w.size.set_selected(1)
        assert 'Could not save' in w.status.get_label()
        assert w.size.get_selected() == 2
    for value in ('1.25', 'auto'):
        subprocess.run(['bash', str(root/'usr/bin/aq'), 'resolve', 'scale', value], check=True, capture_output=True)
        assert '# keep this note' in config.read_text() and 'future_option=yes' in config.read_text()
    assert 'scale=' not in config.read_text()
    w.destroy()
    app.quit()
    print('PASS: real GTK display controls map; scale, reset and failure actions work')


if __name__ == '__main__':
    runpy.run_path(str(Path(__file__).with_name('test-installer-window.py')))['main'](check)
