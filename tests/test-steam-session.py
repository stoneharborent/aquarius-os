#!/usr/bin/env python3
"""Exercise the real session wrapper with a fresh account and unavailable network."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'handheld_files/usr/libexec/aquarius-steam-session'

class SteamSessionTest(unittest.TestCase):
    def run_session(self, complete=False):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            binaries = root / 'bin'
            binaries.mkdir()
            client = root / '.local/share/Steam/ubuntu12_32/steamui.so'
            client.parent.mkdir(parents=True)
            if complete:
                client.write_text('installed')
            commands = {
                'steam': '''echo steam >> "$HOME/calls"
if [ -f "$HOME/attempted" ]; then
 echo installed > "$HOME/.local/share/Steam/ubuntu12_32/steamui.so"
 exit 0
fi
touch "$HOME/attempted"
exit 7
''',
                'nm-online': 'echo network >> "$HOME/calls"; exit 1\n',
                'gnome-control-center': 'echo wifi >> "$HOME/calls"\n',
                'zenity': 'echo retry >> "$HOME/calls"\n',
                'logger': 'exit 0\n',
                'sleep': 'exit 0\n',
            }
            for name, body in commands.items():
                path = binaries / name
                path.write_text('#!/bin/bash\n' + body)
                path.chmod(0o755)
            env = dict(os.environ, HOME=str(root), PATH=f'{binaries}:/usr/bin:/bin')
            env.pop('XDG_DATA_HOME', None)
            result = subprocess.run(['bash', str(SCRIPT)], env=env, timeout=5)
            return result.returncode, (root / 'calls').read_text().splitlines()

    def test_incomplete_client_retries_without_ending_session(self):
        result, calls = self.run_session()
        self.assertEqual(result, 0)
        self.assertEqual(calls.count('steam'), 2)
        self.assertIn('retry', calls)
        self.assertIn('network', calls)

    def test_complete_client_preserves_exit_and_offline_behavior(self):
        result, calls = self.run_session(complete=True)
        self.assertEqual(result, 7)
        self.assertEqual(calls, ['steam'])

if __name__ == '__main__':
    unittest.main()
