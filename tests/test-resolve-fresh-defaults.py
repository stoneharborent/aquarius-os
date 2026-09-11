#!/usr/bin/env python3
"""Run the shipped launcher with empty user homes and an isolated runtime stub."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'system_files'
LIBEXEC = ROOT / 'usr/libexec'


class FreshResolve(unittest.TestCase):
    def test_two_new_accounts(self):
        with tempfile.TemporaryDirectory(prefix='aq-fresh-resolve-') as tmp:
            work = Path(tmp)
            bin_dir = work / 'bin'
            bin_dir.mkdir()
            outputs = work / 'outputs.json'
            outputs.write_text(json.dumps([{'name': 'HDMI-A-2', 'enabled': True,
                'scale': 1, 'physical_size': {'width': 1210, 'height': 680},
                'modes': [{'width': 3840, 'height': 2160, 'current': True}]}]))
            scripts = {
                'podman': '#!/bin/sh\nexit 0\n',
                'gsettings': "#!/bin/sh\ncase \"$3\" in cursor-theme) echo \"'Adwaita'\";; cursor-size) echo 24;; esac\n",
                'distrobox': '#!/usr/bin/python3\nimport json,os,sys\nopen(os.environ["AQ_CAPTURE"],"w").write(json.dumps(sys.argv[1:]))\n',
                'display-helper': '#!/bin/sh\nexec ' + shlex.join([
                    sys.executable, str(LIBEXEC / 'aquarius-display-scale'),
                    '--outputs-from', str(outputs), '--conf', str(work / 'absent'),
                    '--monitors-xml', str(work / 'absent')]) + ' "$@"\n',
            }
            for name, script in scripts.items():
                path = bin_dir / name
                path.write_text(script)
                path.chmod(0o755)
            launcher = work / 'launcher'
            launcher.write_text((LIBEXEC / 'aquarius-resolve-launch').read_text()
                .replace('/usr/libexec/aquarius-display-scale', str(bin_dir / 'display-helper'))
                .replace('/usr/libexec/aquarius-resolve-window', str(work / 'absent-watcher'))
                .replace('/usr/share/aquarius/resolve/runtime.env', str(work / 'absent-runtime')))
            for name in ('new-user', 'reinstalled-user'):
                home = work / name
                home.mkdir()
                capture = work / (name + '.json')
                env = {'PATH': str(bin_dir) + ':/usr/bin:/bin', 'HOME': str(home),
                       'XDG_CONFIG_HOME': str(home / '.config'),
                       'AQ_CAPTURE': str(capture), 'AQ_RESOLVE_FAKE_PORTAL_PLUGIN': 'no'}
                result = subprocess.run(['bash', str(launcher), 'Project (final).drp'],
                    env=env, text=True, capture_output=True, check=True)
                self.assertIn('interface at 1.25x', result.stderr)
                self.assertIn('pointer Adwaita at 24px', result.stderr)
                args = json.loads(capture.read_text())
                flags = shlex.split(args[args.index('--additional-flags') + 1])
                values = dict(flags[i+1].split('=', 1) for i in range(0, len(flags), 2))
                self.assertEqual(values['AQUARIUS_RESOLVE_READABLE_MENUS'], '1')
                self.assertEqual(values['QT_SCALE_FACTOR'], '1.25')
                paths = values['XCURSOR_PATH'].split(':')
                self.assertLess(paths.index('/run/host/usr/share/icons'), paths.index('/usr/share/icons'))
                self.assertEqual(args[-2:], ['/opt/resolve/bin/resolve', 'Project (final).drp'])
                script = args[args.index('-c') + 1]
                self.assertIn('/run/host/usr/libexec/aquarius-resolve-menu-run', script)
                self.assertIn('/run/host/usr/libexec/aquarius-resolve-browser/setup', script)
                self.assertFalse((home / '.config/aquarius/resolve.conf').exists())

    def test_packaged_components(self):
        for name in ('aquarius-resolve-launch', 'aquarius-resolve-menu-run',
                     'aquarius-resolve-window', 'aquarius-resolve-settings',
                     'aquarius-resolve-browser/setup'):
            self.assertTrue(os.access(LIBEXEC / name, os.X_OK), name)
        if ROOT == Path('/'):
            self.assertTrue((ROOT / 'usr/lib64/aquarius/libaquarius-resolve-menu.so').is_file())


if __name__ == '__main__':
    unittest.main()
