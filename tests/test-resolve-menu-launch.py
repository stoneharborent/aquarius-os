#!/usr/bin/env python3
"""Exercise the container-side launch boundary without starting Resolve."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)) if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else Path(__file__).resolve().parent.parent / 'system_files'
WRAPPER = ROOT / 'usr/libexec/aquarius-resolve-menu-run'


class MenuLaunch(unittest.TestCase):
    def test_launch_boundary(self):
        with tempfile.TemporaryDirectory(prefix='aq menu ') as tmp:
            work = Path(tmp)
            editor, raw = work / 'resolve', work / 'raw'
            program = '#!/usr/bin/python3\nimport os,sys,json\nprint(json.dumps([sys.argv[1:], os.getenv("LD_PRELOAD")]))\n'
            for target in (editor, raw):
                target.write_text(program)
                target.chmod(0o755)
            # Loader accepts this real harmless system library; the adapter's
            # own behavior/inheritance is checked in the Qt executable test.
            library = Path('/usr/lib64/libm.so.6')
            self.assertTrue(library.exists())
            qt = work / 'Qt5-present'
            qt.touch()
            wrapper = work / 'wrapper'
            source = WRAPPER.read_text().replace(
                '/run/host/usr/lib64/aquarius/libaquarius-resolve-menu.so', str(library)
            ).replace('/opt/resolve/bin/resolve', str(editor)).replace(
                '/opt/resolve/libs/libQt5Widgets.so.5', str(qt))
            # Literal test paths include spaces, as a user's media arguments do.
            source = source.replace(f'AQ_MENU_LIBRARY={library}', f'AQ_MENU_LIBRARY="{library}"')
            source = source.replace(f'= {editor} ]', f'= "{editor}" ]')
            source = source.replace(f'[ -r {qt} ]', f'[ -r "{qt}" ]')
            wrapper.write_text(source)
            env = dict(os.environ)
            env.pop('LD_PRELOAD', None)
            env.pop('AQUARIUS_RESOLVE_READABLE_MENUS', None)
            args = ['Clip (final).drp', 'literal $HOME; untouched']

            def launch(target=editor, extra=None):
                return json.loads(subprocess.check_output(
                    ['sh', str(wrapper), str(target), *args],
                    env=dict(env, **(extra or {})), text=True))

            self.assertEqual(launch(), [args, str(library)])
            self.assertEqual(launch(raw), [args, None])
            self.assertEqual(launch(extra={'AQUARIUS_RESOLVE_READABLE_MENUS': '0'}), [args, None])
            self.assertEqual(launch(extra={'LD_PRELOAD': str(library)}), [args, f'{library} {library}'])
            qt.unlink()
            self.assertEqual(launch(), [args, None])
            wrapper.write_text(source.replace(str(library), '/absent/adapter.so'))
            qt.touch()
            self.assertEqual(launch(), [args, None])


if __name__ == '__main__':
    unittest.main()
