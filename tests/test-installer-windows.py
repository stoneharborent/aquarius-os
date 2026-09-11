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


if __name__ == '__main__':
    unittest.main()
