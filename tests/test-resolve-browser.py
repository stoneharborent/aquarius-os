#!/usr/bin/env python3
"""Exercise browser handoff and safe container migration without account login."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else Path(__file__).resolve().parent.parent / 'system_files'
BRIDGE = ROOT / 'usr/libexec/aquarius-resolve-browser/xdg-open'
SETUP = ROOT / 'usr/libexec/aquarius-resolve-browser/setup'


class BrowserBridge(unittest.TestCase):
    def test_handoff_and_private_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            capture = folder / 'calls'
            host = folder / 'host-exec'
            host.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                            'with open(os.environ["CAPTURE"], "a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
                            'sys.exit(int(os.environ.get("RESULT", "0")))\n')
            host.chmod(0o755)
            opener = folder / 'xdg-open'
            opener.write_text(BRIDGE.read_text().replace('/run/.containerenv', str(host))
                              .replace('/usr/bin/distrobox-host-exec', str(host)))
            uri = "https://example.invalid/login?state=test&code=a%27b;$literal"
            env = dict(os.environ, CAPTURE=str(capture))
            result = subprocess.run(['sh', str(opener), uri], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(capture.read_text()), ['/usr/bin/xdg-open', uri])
            self.assertEqual(result.stdout + result.stderr, '')
            capture.unlink()
            result = subprocess.run(['sh', str(opener), uri], env=dict(env, RESULT='1'), capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertNotIn(uri, result.stdout + result.stderr)
            calls = [json.loads(line) for line in capture.read_text().splitlines()]
            self.assertEqual(calls[1][0], '/usr/bin/notify-send')
            self.assertNotIn(uri, json.dumps(calls[1]))
            capture.unlink()
            local_file = '/run/media/Example Drive/Project One.drp'
            subprocess.run(['sh', str(opener), local_file], env=env, check=True)
            self.assertEqual(json.loads(capture.read_text()), ['/usr/bin/xdg-open', local_file])

    def test_migration_and_updates_preserve_original(self):
        for symlink in (False, True):
            with self.subTest(symlink=symlink), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                source, target, original = [folder / name for name in ('source', 'target', 'original')]
                source.write_text(BRIDGE.read_text())
                stock = folder / 'stock'
                stock.write_text('original-opener')
                if symlink:
                    target.symlink_to(stock)
                else:
                    target.write_text('original-opener')
                setup = folder / 'setup'
                setup.write_text(SETUP.read_text().replace('/run/.containerenv', str(stock))
                    .replace('/run/host/usr/libexec/aquarius-resolve-browser/xdg-open', str(source))
                    .replace('/usr/bin/xdg-open', str(target))
                    .replace('/usr/libexec/aquarius-original-xdg-open', str(original))
                    .replace('$(id -u)', '0').replace('mkdir -p /usr/libexec', ':')
                    .replace('/usr/bin/.aquarius-xdg-open.XXXXXX', str(folder / '.opener.XXXXXX')))
                for _ in range(2):
                    subprocess.run(['sh', str(setup)], check=True)
                    self.assertEqual(target.read_bytes(), source.read_bytes())
                    self.assertEqual(original.read_text(), 'original-opener')
                    self.assertFalse(target.is_symlink())
                    self.assertTrue(os.access(target, os.X_OK))
                source.write_text(source.read_text() + '\n# updated\n')
                subprocess.run(['sh', str(setup)], check=True)
                self.assertEqual(target.read_bytes(), source.read_bytes())
                self.assertEqual(original.read_text(), 'original-opener')
                self.assertEqual(stock.read_text(), 'original-opener')
                self.assertEqual(original.is_symlink(), symlink)
                source.unlink()
                failed = subprocess.run(['sh', str(setup)], capture_output=True)
                self.assertNotEqual(failed.returncode, 0)
                self.assertIn(b'# updated', target.read_bytes())
                self.assertEqual(original.read_text(), 'original-opener')


if __name__ == '__main__':
    unittest.main()
