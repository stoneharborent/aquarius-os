#!/usr/bin/python3
"""Run normally for unit checks; --engine also uses an isolated File Roller bus.

For --engine, use a disposable D-Bus session and headless desktop as documented
in docs/restart/zip-extraction.md. Never point these tests at a user's folders.
"""
import importlib.machinery
import importlib.util
from pathlib import Path
import stat
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

    @unittest.skipUnless(ENGINE, "needs isolated File Roller session")
    def test_real_engine_normal_and_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            archive = base / "sample.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("Top/movie.txt", "footage")
            first = helper.reserve_destination(archive)
            helper.extract(archive, first)
            second = helper.reserve_destination(archive)
            helper.extract(archive, second)
            self.assertEqual((first / "Top/movie.txt").read_text(), "footage")
            self.assertEqual((second / "Top/movie.txt").read_text(), "footage")
            self.assertNotEqual(first, second)
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
