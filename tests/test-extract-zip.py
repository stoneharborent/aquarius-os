#!/usr/bin/python3
"""Run normally for unit checks; --engine also uses an isolated File Roller bus.

For --engine, use a disposable D-Bus session and headless desktop as documented
in docs/restart/zip-extraction.md. Never point these tests at a user's folders.
"""
import errno
import importlib.machinery
import importlib.util
from pathlib import Path
import stat
import subprocess
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ENGINE = "--engine" in sys.argv
if ENGINE:
    sys.argv.remove("--engine")
ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("extract_zip", str(ROOT / "system_files/usr/libexec/aquarius-extract-zip"))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)


class ZipExtraction(unittest.TestCase):
    def test_collisions_include_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / "Archive").write_text("keep")
            (base / "Archive (2)").mkdir()
            (base / "Archive (3)").symlink_to(base / "missing")
            self.assertEqual(helper.reserve_destination(base / "Archive.zip"), base / "Archive (4)")
            self.assertEqual((base / "Archive").read_text(), "keep")
            self.assertEqual(helper.reserve_destination(base / "Archive.zip"), base / "Archive (5)")

    def test_valid_zip_and_corrupt_file(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "spaced name.ZIP"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("file.txt", "hello")
            self.assertEqual(helper.archive_path(str(archive)), archive)
            archive.write_text("not a ZIP")
            with self.assertRaises(ValueError):
                helper.archive_path(str(archive))

    def test_dbus_failure_reports_partial_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "files.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("file.txt", "hello")
            with patch.object(helper, "extract", side_effect=RuntimeError("Service failed")), patch.object(helper, "notify") as notify:
                self.assertEqual(helper.main([str(archive)]), 1)
                self.assertIn("incomplete", notify.call_args.args[1])
                self.assertTrue(notify.call_args.kwargs["failed"])
                self.assertTrue((Path(temp) / "files").is_dir())

    def test_dbus_contract_has_no_extraction_deadline(self):
        from gi.repository import Gio, GLib
        with patch.object(Gio, "bus_get_sync") as get_bus:
            helper.extract(Path("/tmp/a b.zip"), Path("/tmp/a b"))
            args = get_bus.return_value.call_sync.call_args.args
            self.assertEqual(args[:4], ("org.gnome.ArchiveManager1", "/org/gnome/ArchiveManager1", "org.gnome.ArchiveManager1", "Extract"))
            self.assertEqual(args[4].unpack(), ("file:///tmp/a%20b.zip", "file:///tmp/a%20b", False))
            self.assertEqual(args[7], GLib.MAXINT)

    def test_success_notification(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "files.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("file.txt", "hello")
            with patch.object(helper, "extract") as extract, patch.object(helper, "notify") as notify:
                self.assertEqual(helper.main([str(archive)]), 0)
                extract.assert_called_once_with(archive, Path(temp) / "files")
                self.assertEqual(notify.call_args.args[0], "ZIP extracted")

    def test_action_opens_exact_folder_uri(self):
        with tempfile.TemporaryDirectory(prefix="ZIP $() & ") as temp:
            folder = Path(temp)
            with patch.object(helper.subprocess, "run", side_effect=[
                subprocess.CompletedProcess([], 0, stdout="show\n"),
                subprocess.CompletedProcess([], 0),
            ]) as run:
                self.assertEqual(helper.completion_notification(str(folder), "ZIP extracted", "Done"), 0)
                self.assertIn("--action=show=Show extracted files", run.call_args_list[0].args[0])
                self.assertEqual(run.call_args_list[1].args[0], ["/usr/bin/xdg-open", folder.as_uri()])

    def test_dismissal_does_not_open_files(self):
        with patch.object(helper.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="")) as run:
            self.assertEqual(helper.completion_notification("/tmp", "Done", "Done"), 0)
            self.assertEqual(run.call_count, 1)

    def test_removed_drive_reports_action_failure(self):
        with patch.object(helper.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="show\n")) as run, patch.object(helper, "notify") as notify:
            self.assertEqual(helper.completion_notification("/no-such-zip-test-drive/folder", "Done", "Done"), 1)
            self.assertEqual(run.call_count, 1)
            self.assertIn("no longer available", notify.call_args.args[1])

    def test_completion_worker_does_not_wait(self):
        with patch.object(helper.subprocess, "Popen") as start, patch.object(helper.subprocess, "run") as run:
            helper.notify("ZIP extracted", "Done", destination=Path("/tmp/spaced name"))
            self.assertEqual(start.call_args.args[0][-4:], ["--completion-notification", "/tmp/spaced name", "ZIP extracted", "Done"])
            self.assertTrue(start.call_args.kwargs["start_new_session"])
            run.assert_not_called()

    def test_disk_errors_are_actionable(self):
        cases = [(errno.ENOSPC, "Free up space"), (errno.EDQUOT, "Free up space"),
                 (errno.EROFS, "read-only"), (errno.EACCES, "permission")]
        for code, expected in cases:
            with self.subTest(code=code):
                self.assertIn(expected, helper.failure_reason(OSError(code, "localized message")))
        for message, expected in [("GDBus.Error: No space left on device", "Free up space"),
                                  ("Not enough free space", "Free up space"),
                                  ("Read-only file system", "read-only")]:
            self.assertIn(expected, helper.failure_reason(RuntimeError(message)))
        with patch.object(helper.os, "statvfs", return_value=SimpleNamespace(f_flag=helper.os.ST_RDONLY, f_bavail=20)):
            self.assertIn("read-only", helper.failure_reason(RuntimeError("localized"), Path("/tmp")))
        with patch.object(helper.os, "statvfs", return_value=SimpleNamespace(f_flag=0, f_bavail=0)):
            self.assertIn("Free up space", helper.failure_reason(RuntimeError("localized"), Path("/tmp")))
        with patch.object(helper.os, "statvfs", return_value=SimpleNamespace(f_flag=0, f_bavail=0)):
            self.assertIn("permission", helper.failure_reason(OSError(errno.EACCES, "localized"), Path("/tmp")))
            self.assertEqual(helper.failure_reason(RuntimeError("CRC error"), Path("/tmp")), "CRC error")
        from gi.repository import Gio, GLib
        error = GLib.Error.new_literal(Gio.io_error_quark(), "localized", Gio.IOErrorEnum.NO_SPACE)
        self.assertIn("Free up space", helper.failure_reason(error))

    def test_destination_creation_error_preserves_zip(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "files.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("file.txt", "hello")
            original = archive.read_bytes()
            for code, expected in [(errno.ENOSPC, "Free up space"), (errno.EROFS, "read-only")]:
                with patch.object(helper, "reserve_destination", side_effect=OSError(code, "localized")), patch.object(helper, "notify") as notify, patch.object(helper, "extract") as extract:
                    self.assertEqual(helper.main([str(archive)]), 1)
                    self.assertIn(expected, notify.call_args.args[1])
                    self.assertTrue(notify.call_args.kwargs["failed"])
                    extract.assert_not_called()
                    self.assertEqual(archive.read_bytes(), original)

    @unittest.skipUnless(ENGINE, "needs isolated File Roller session")
    def test_real_engine_normal_and_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            archive = base / "sample.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("Top/movie.txt", "footage")
            original = archive.read_bytes()
            first = helper.reserve_destination(archive)
            helper.extract(archive, first)
            second = helper.reserve_destination(archive)
            helper.extract(archive, second)
            self.assertEqual((first / "Top/movie.txt").read_text(), "footage")
            self.assertEqual((second / "Top/movie.txt").read_text(), "footage")
            self.assertNotEqual(first, second)
            self.assertEqual(archive.read_bytes(), original)
            unsafe = base / "unsafe.zip"
            outside = base / "outside"
            outside.mkdir()
            with zipfile.ZipFile(unsafe, "w") as z:
                z.writestr("../escaped.txt", "BAD")
                z.writestr(str(base / "absolute-escaped.txt"), "BAD")
                link = zipfile.ZipInfo("link")
                link.create_system = 3
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(link, "../outside")
                z.writestr("link/escaped.txt", "BAD")
                z.writestr("safe.txt", "OK")
            try:
                helper.extract(unsafe, helper.reserve_destination(unsafe))
            except Exception:
                pass  # Rejecting the malicious archive is also acceptable.
            self.assertFalse((base / "escaped.txt").exists())
            self.assertFalse((base / "absolute-escaped.txt").exists())
            self.assertFalse((outside / "escaped.txt").exists())


if __name__ == "__main__":
    unittest.main()
