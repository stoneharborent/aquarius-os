#!/usr/bin/env python3
"""Windows handoff contract, with no downloads, real setup or account changes.

An optional system_files root tests the copy read back from a finished image.
Only external processes are mocked; sorting, dispatch, CLI output and records
use the real implementation in a throwaway account.
"""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parent.parent / 'system_files')
spec = importlib.util.spec_from_file_location('aquarius_installer', ROOT / 'usr/lib/aquarius/python/aquarius_installer.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
sys.modules['aquarius_installer'] = core
window = runpy.run_path(str(ROOT / 'usr/libexec/aquarius-installer'), run_name='installer_test')


class WindowsSetup(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.file = self.folder / '--setup $(echo nope); spaces.EXE'
        self.file.write_bytes(b'MZ' + b'\0' * 80)
        self.progress = core.Progress()
        for mocker in (
            patch.dict(os.environ, HOME=str(self.folder), WAYLAND_DISPLAY='test-desktop'),
            patch.object(core, 'running_as_root', return_value=False),
            patch.object(core.shutil, 'which', return_value='/usr/bin/flatpak'),
        ):
            mocker.start()
            self.addCleanup(mocker.stop)
        self.run = patch.object(core.subprocess, 'run').start()
        self.addCleanup(patch.stopall)
        self.run.return_value = subprocess.CompletedProcess([], 0)
        self.launch = MagicMock()
        self.launch.wait.return_value = 0
        self.popen = patch.object(core.subprocess, 'Popen', return_value=self.launch).start()

    def install(self):
        return core.install(core.sort_path(str(self.file)), self.progress)

    def assert_no_install(self):
        self.assertEqual(core.registry_ids(), [])
        self.assertFalse((self.folder / '.local/lib/aquarius').exists())
        self.assertNotIn('DONE', self.progress.lines)
        self.assertFalse(any(line.startswith('OK ') for line in self.progress.lines))

    def test_both_extensions_and_uppercase_are_supported(self):
        for suffix in ('.exe', '.msi', '.EXE', '.MSI'):
            path = self.folder / ('setup' + suffix)
            path.write_bytes(b'MZ' + b'\0' * 20)
            verdict = core.sort_path(str(path))
            self.assertEqual(verdict.route, core.ROUTE_WINDOWS)
            self.assertTrue(verdict.can_install)
            self.assertIn('Bottles', verdict.where)

    def test_user_install_handoff_uses_portal_and_exact_path(self):
        result = self.install()
        self.assertTrue(result.ok)
        self.assertEqual(result.outcome, 'handoff')
        self.assertIsNone(result.record)
        self.assertEqual(self.popen.call_args.args[0], [
            'flatpak', 'run', '--user', '--file-forwarding', core.BOTTLES_ID,
            '@@', str(self.file), '@@'])
        self.assertNotIn('shell', self.popen.call_args.kwargs)
        self.assertIn('HANDOFF ' + core.BOTTLES_ID, self.progress.lines)
        self.assertIn('create an Application bottle', result.message)
        self.assertIn('again', result.message)
        self.assertTrue(Path(result.detail).is_file())
        self.assert_no_install()

    def test_system_install_is_reused(self):
        self.run.side_effect = [subprocess.CompletedProcess([], 1), subprocess.CompletedProcess([], 0)]
        self.assertTrue(self.install().ok)
        self.assertIn('--system', self.popen.call_args.args[0])
        self.assertEqual(self.popen.call_count, 1)

    def helper(self, code, found_after=True):
        codes = [1, 1, 1, 0] if found_after else [1, 1, 1, 1]
        self.run.side_effect = [subprocess.CompletedProcess([], n) for n in codes]
        helper = MagicMock()
        helper.__enter__.return_value = helper
        helper.stdout = iter(['Preparing runtime\n'])
        helper.wait.return_value = code
        self.popen.side_effect = [helper, self.launch]

    def test_missing_bottles_uses_existing_helper_and_reads_install_back(self):
        self.helper(0)
        self.assertTrue(self.install().ok)
        self.assertEqual(self.popen.call_args_list[0].args[0], [
            'pkexec', core.FLATPAK_HELPER, '--mode', 'install', core.BOTTLES_ID])
        self.assertEqual(self.run.call_count, 4)
        self.assertIn('--system', self.popen.call_args_list[1].args[0])
        self.assert_no_install()

    def test_failed_or_cancelled_dependency_never_opens_download(self):
        for code, word in ((1, 'could not be installed'), (126, 'cancelled'), (127, 'permission')):
            with self.subTest(code=code):
                self.popen.reset_mock()
                self.helper(code)
                result = self.install()
                self.assertFalse(result.ok)
                self.assertIn(word, result.message)
                self.assertEqual(self.popen.call_count, 1)
                self.assert_no_install()

    def test_helper_zero_without_bottles_is_failure(self):
        self.helper(0, found_after=False)
        self.assertFalse(self.install().ok)
        self.assertEqual(self.popen.call_count, 1)

    def test_launch_failure_is_not_handoff(self):
        self.launch.wait.return_value = 1
        self.assertFalse(self.install().ok)
        self.assert_no_install()
        self.assertFalse(any(line.startswith('HANDOFF ') for line in self.progress.lines))

    def test_running_gui_does_not_block_until_windows_wizard_finishes(self):
        self.launch.wait.side_effect = [subprocess.TimeoutExpired('flatpak', 2), 0]
        with patch.object(core.threading, 'Thread') as waiter:
            self.assertEqual(self.install().outcome, 'handoff')
            waiter.return_value.start.assert_called_once()
        self.assert_no_install()

    def test_no_flatpak_headless_and_root_fail_before_any_download(self):
        for mocker in (
            patch.object(core.shutil, 'which', return_value=None),
            patch.dict(os.environ, WAYLAND_DISPLAY='', DISPLAY=''),
            patch.object(core, 'running_as_root', return_value=True),
        ):
            with mocker:
                self.assertFalse(self.install().ok)
                self.popen.assert_not_called()

    def test_missing_file_and_launch_oserror_are_reported(self):
        verdict = core.sort_path(str(self.file))
        self.file.unlink()
        self.assertFalse(core.install(verdict, self.progress).ok)
        self.popen.assert_not_called()
        self.file.write_bytes(b'MZ1234')
        self.popen.side_effect = OSError('permission denied')
        self.assertFalse(self.install().ok)

    def test_flatpak_check_timeout_is_reported(self):
        self.run.side_effect = subprocess.TimeoutExpired('flatpak info', 30)
        self.assertFalse(self.install().ok)
        self.popen.assert_not_called()

    def test_cli_reports_request_not_installed_and_nonzero_on_failure(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(window['do_install'](str(self.file)), 0)
        self.assertIn('HANDOFF', output.getvalue())
        self.assertIn('setup was requested', output.getvalue())
        self.assertNotIn('is installed', output.getvalue())
        self.launch.wait.return_value = 1
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(window['do_install'](str(self.file)), 1)

    def test_desktop_associations_cover_windows(self):
        desktop = (ROOT / 'usr/share/applications/aquarius-installer.desktop').read_text()
        mimeapps = (ROOT / 'etc/xdg/mimeapps.list').read_text()
        for kind in ('application/x-msi', 'application/x-msdownload', 'application/vnd.microsoft.portable-executable'):
            self.assertIn(kind + ';', desktop)
            self.assertIn(kind + '=aquarius-installer.desktop', mimeapps)


class WindowPieces(unittest.TestCase):
    """The four parts of the window that have no GTK in them.

    ⚠️ THEY ARE TESTED HERE BECAUSE THEY CAN BE. The window itself needs a
    desktop, GTK 4 and libadwaita, so on a build machine it is only ever
    import-checked (runpy, at the top of this file, with no screen anywhere).
    Every one of the faults found on 2026-09-13 lived in a piece of ordinary
    Python, so every one of them is reachable from here.
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def test_both_pipes_are_read_at_once(self):
        # Enough on the second pipe to fill it several times over. Read one
        # pipe to exhaustion first, as the window used to, and this hangs for
        # ever — which is exactly what a long download did to it.
        noisy = (
            'import sys\n'
            'for n in range(4000): sys.stderr.write("PERCENT %d\\n" % (n % 100))\n'
            'sys.stderr.flush()\n'
            'sys.stdout.write("log line\\n")\n'
            'sys.exit(3)\n')
        proc = subprocess.Popen([sys.executable, '-c', noisy],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, bufsize=1)
        out, err = [], []
        code = window['read_both_pipes'](proc, out.append, err.append)
        self.assertEqual(code, 3)
        self.assertEqual(out, ['log line\n'])
        self.assertEqual(len(err), 4000)
        self.assertTrue(err[0].startswith('PERCENT '))

    def test_a_pipe_that_is_never_opened_is_not_waited_for(self):
        proc = subprocess.Popen([sys.executable, '-c', 'print("only stdout")'],
                                stdout=subprocess.PIPE, text=True)
        seen = []
        self.assertEqual(
            window['read_both_pipes'](proc, seen.append, seen.append), 0)
        self.assertEqual(seen, ['only stdout\n'])

    def test_only_the_newest_answer_is_kept(self):
        import threading

        started = threading.Event()
        release = threading.Event()

        def slow(term):
            if term == 'ob':
                started.set()
                release.wait(5)
            return [term]

        landed = []
        finder = window['LatestOnly'](slow)
        finder.start('ob', lambda asked, hits: landed.append(asked))
        started.wait(5)
        finder.start('obs', lambda asked, hits: landed.append(asked))
        for _ in range(200):
            if 'obs' in landed:
                break
            time.sleep(0.01)
        release.set()
        time.sleep(0.2)
        self.assertEqual(landed, ['obs'],
                         'a stale answer reached the window')

    def test_update_check_never_runs_on_the_drawing_thread(self):
        import threading

        where = {}

        def read():
            where['thread'] = threading.current_thread().name
            return ['com.example.One', 'com.example.Two']

        cache = window['UpdateCache'](read)
        self.assertEqual(cache.ids, [], 'it must start out knowing nothing')
        delivered = []
        cache.start(delivered.append).join(5)
        self.assertEqual(cache.ids, ['com.example.One', 'com.example.Two'])
        self.assertEqual(delivered, [cache.ids])
        self.assertNotEqual(where['thread'], 'MainThread')

        # An app store that is not there means no updates, never a crash.
        broken = window['UpdateCache'](lambda: 1 / 0)
        broken.start().join(5)
        self.assertEqual(broken.ids, [])

    def test_open_presses_the_entry_that_was_written(self):
        entry = self.folder / 'openapp.desktop'
        entry.write_text('[Desktop Entry]\nType=Application\nName=Open App\n')
        self.assertEqual(window['launch_argv'](str(entry)),
                         ['gio', 'launch', str(entry)])
        # A Flatpak has no entry of ours, so the id is what gets pressed.
        self.assertEqual(window['launch_argv']('', 'com.example.App'),
                         ['flatpak', 'run', 'com.example.App'])
        # And when there is nothing to press, it says so rather than guessing:
        # an empty list is what makes the window show a sentence.
        self.assertEqual(window['launch_argv'](), [])
        self.assertEqual(window['launch_argv'](str(self.folder / 'gone')), [])

    def test_a_stopped_install_never_becomes_all_set(self):
        words = window['done_words']
        self.assertEqual(words(True, 'installed'), ('All set.', True, True))
        self.assertEqual(words(True, 'handoff'),
                         ('Continue in Bottles', False, True))
        self.assertEqual(words(False, 'failed'),
                         ('That did not work.', False, False))
        # The late answer from a worker that was already told to stop.
        self.assertEqual(words(True, 'installed', cancelled=True),
                         ('Stopped.', False, False))
        self.assertEqual(words(False, 'cancelled'), ('Stopped.', False, False))
        self.assertIn('Stopped', core.SAY['cancelled'])

    def test_cancel_file_reaches_the_app_helper(self):
        argv = core.flatpak_argv('install', ['com.example.App'], progress_fd=2,
                                 cancel_file='/tmp/stop-me')
        self.assertIn('--cancel-file', argv)
        self.assertEqual(argv[argv.index('--cancel-file') + 1], '/tmp/stop-me')
        helper = (ROOT / 'usr/libexec/aquarius-creator-apps-install').read_text()
        self.assertIn('--cancel-file', helper,
                      'the helper must still understand the flag we pass it')


if __name__ == '__main__':
    unittest.main()
