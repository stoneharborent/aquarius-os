#!/usr/bin/env python3
"""Rehearse cold boots using the real login scripts and disposable files.

Only account lookup and the root identity are simulated. No live login files,
services, or Steam accounts are changed. Also usable against a built image:
  python3 tests/test-game-login.py /usr/libexec
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
PROGRAMS = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else REPO / 'system_files/usr/libexec'


class LoginTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.accounts = self.root / 'accounts'
        self.sessions = self.root / 'sessions'
        self.sessions.mkdir()
        for session in ('gnome', 'plasma', 'gamescope-session-steam'):
            (self.sessions / (session + '.desktop')).write_text('[Desktop Entry]\n')
        self.flag = self.root / 'login-mode'
        self.gdm = self.root / 'custom.conf'
        self.gdm.write_text('[daemon]\nWaylandEnable=true\n')
        self.passwd = self.root / 'passwd'
        self.passwd.write_text('root:x:0:0:root:/root:/bin/bash\n'
                               'second:x:1001:1001::/home/second:/bin/bash\n'
                               'owner:x:1000:1000::/home/owner:/bin/bash\n'
                               'nobody:x:65534:65534::/:/sbin/nologin\n')
        self.write_executable('id', '#!/bin/sh\necho 0\n')
        self.write_executable('getent', '''#!/bin/sh
[ "$1" = passwd ] || exit 1
if [ "$#" = 1 ]; then cat "$AQ_TEST_PASSWD"; else
    awk -F: -v name="$2" '$1 == name { print; found=1 } END { exit !found }' "$AQ_TEST_PASSWD"
fi
''')
        # Redirect constants in copies, so privileged production helpers gain
        # no environment-variable path overrides just to support a test.
        paths = {
            '/var/lib/AccountsService/users': str(self.accounts),
            '/etc/gdm/custom.conf': str(self.gdm),
            '/usr/share/wayland-sessions': str(self.sessions),
            '/etc/aquarius/login-mode': str(self.flag),
            '/usr/libexec/aquarius-session-root': str(self.bin / 'aquarius-session-root'),
        }
        for name in ('aquarius-login-mode', 'aquarius-session-root'):
            source = (PROGRAMS / name).read_text()
            for old, new in paths.items():
                source = source.replace('="' + old + '"', '="' + new + '"')
            self.write_executable(name, source)
        self.env = dict(os.environ, PATH=str(self.bin) + ':/usr/bin:/bin',
                        AQ_TEST_PASSWD=str(self.passwd))
        self.env.pop('PKEXEC_UID', None)

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def boot(self):
        subprocess.run(['bash', str(self.bin / 'aquarius-login-mode')],
                       env=self.env, check=True, capture_output=True, text=True)

    def test_fresh_handheld(self):
        self.flag.write_text((REPO / 'handheld_files/etc/aquarius/login-mode').read_text())
        self.boot()
        self.assertEqual((self.accounts / 'owner').read_text(),
                         '[User]\nSession=gamescope-session-steam\n')
        self.assertIn('AutomaticLoginEnable=true\n', self.gdm.read_text())
        self.assertIn('AutomaticLogin=owner\n', self.gdm.read_text())
        self.assertNotIn('TimedLogin', self.gdm.read_text())
        before = self.gdm.read_text()
        self.boot()
        self.assertEqual(before, self.gdm.read_text())

    def test_explicit_account(self):
        self.flag.write_text('mode=game\nuser=second\n')
        self.boot()
        self.assertIn('AutomaticLogin=second\n', self.gdm.read_text())

    def test_stale_account_falls_back_to_owner(self):
        self.flag.write_text('mode=game\nuser=deleted\n')
        self.boot()
        self.assertIn('AutomaticLogin=owner\n', self.gdm.read_text())

    def test_no_person_yet(self):
        self.flag.write_text('mode=game\n')
        self.passwd.write_text('root:x:0:0:root:/root:/bin/bash\n')
        before = self.gdm.read_text()
        self.boot()
        self.assertEqual(before, self.gdm.read_text())
        self.assertFalse(self.accounts.exists())

    def test_missing_game_session_cannot_autologin_to_desktop(self):
        self.flag.write_text('mode=game\n')
        (self.sessions / 'gamescope-session-steam.desktop').unlink()
        self.gdm.write_text('[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=owner\n')
        self.boot()
        self.assertNotIn('AutomaticLogin', self.gdm.read_text())

    def test_desktop_default_clears_previous_switch(self):
        self.flag.write_text((REPO / 'system_files/etc/aquarius/login-mode').read_text())
        self.gdm.write_text('[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=owner\n'
                            'TimedLoginEnable=true\nTimedLogin=owner\nTimedLoginDelay=1\n')
        self.boot()
        self.assertNotIn('Login=', self.gdm.read_text())
        self.assertNotIn('LoginEnable=', self.gdm.read_text())

    def test_boot_precedes_accounts_cache_and_login_screen(self):
        # The actual race that previously made the first handheld boot GNOME.
        unit = (REPO / 'system_files/usr/lib/systemd/system/aquarius-login-mode.service').read_text()
        before = [line.split('=', 1)[1].split() for line in unit.splitlines()
                  if line.startswith('Before=')]
        self.assertIn('accounts-daemon.service', sum(before, []))
        self.assertIn('display-manager.service', sum(before, []))


if __name__ == '__main__':
    unittest.main()
