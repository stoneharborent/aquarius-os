"""Does the "Make Editor-Ready" right-click menu actually load in Files?

WHY THIS FILE EXISTS
On 2026-09-04 Royce right-clicked an MP4 on the bench machine and there was no
"Make Editor-Ready" item in the menu. Everything the build checked was true: the
extension file was installed, in the right folder, and it compiled. It still did
not work, because compiling a Python file and RUNNING it are two different
things, and the failure was at the first line that runs:

    ValueError: Namespace Nautilus is already loaded with version 4.1

So this test does what the build's compile check cannot: it loads the extension
the same way GNOME Files loads it, then right-clicks a video at it and checks a
menu item comes back.

WHAT IT PRETENDS TO BE
Files hands an extension real file objects. Those cannot be made up out of thin
air, so this test hands it small stand-ins that answer the two questions the
extension actually asks — "what type of file are you?" and "where do you live on
disk?". That is enough: the extension does not care what else a file can do.

HOW TO RUN IT
    python3 ingest/tests/test_nautilus_extension.py          (from the repo root)
    python3 -m unittest discover -s tests -t .               (from ingest/)

Two switches, both used by CI:
    AQ_NAUTILUS_EXT=/path/to/aquarius_editor_ready.py
        test that copy instead of the one in this repository. CI points this at
        the copy INSIDE the finished image, which is the one that matters.
    AQ_NAUTILUS_REQUIRED=1
        refuse to skip. Without GNOME's Nautilus libraries there is nothing to
        load and this test skips itself, which is right on a Mac and wrong in
        CI — a test that quietly skips is a test that stopped protecting you.
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

# ---------------------------------------------------------------------------
# Load Nautilus exactly the way nautilus-python does, BEFORE the extension is
# imported. This is the whole point: nautilus-python has the interface loaded
# already by the time an extension runs, so that is the situation the extension
# has to cope with.
# ---------------------------------------------------------------------------
NAUTILUS_VERSION = None
IMPORT_PROBLEM = None
try:
    import gi

    for _version in ("4.1", "4.0"):
        try:
            gi.require_version("Nautilus", _version)
            NAUTILUS_VERSION = _version
            break
        except ValueError:
            continue
    if NAUTILUS_VERSION is None:
        raise ImportError("no Nautilus 4.x extension interface on this machine")
    from gi.repository import Nautilus  # noqa: E402
except Exception as error:  # pragma: no cover - depends on the machine
    IMPORT_PROBLEM = f"{type(error).__name__}: {error}"

REQUIRED = os.environ.get("AQ_NAUTILUS_REQUIRED") == "1"

if IMPORT_PROBLEM and REQUIRED:
    raise SystemExit(
        "AQ_NAUTILUS_REQUIRED=1 was set, so GNOME's Nautilus libraries were "
        "expected on this machine and they are not usable here.\n"
        f"  {IMPORT_PROBLEM}\n"
        "  Install nautilus-python (Fedora) or python3-nautilus (Debian/Ubuntu)."
    )


def _extension_path():
    """Where the extension we are testing lives."""
    from_env = os.environ.get("AQ_NAUTILUS_EXT")
    if from_env:
        return Path(from_env)
    # ingest/tests/this_file.py -> the repository root
    repo_root = Path(__file__).resolve().parents[2]
    return (
        repo_root
        / "system_files/usr/share/nautilus-python/extensions/aquarius_editor_ready.py"
    )


class FakeLocation:
    """Stands in for the GFile that Files attaches to every item."""

    def __init__(self, path):
        self._path = path

    def get_path(self):
        return self._path


class FakeFile:
    """Stands in for one row in the Files window."""

    def __init__(self, path, mime_type):
        self._path = str(path)
        self._mime_type = mime_type

    def get_mime_type(self):
        return self._mime_type

    def get_uri(self):
        return "file://" + self._path

    def is_directory(self):
        return self._mime_type == "inode/directory"

    def get_location(self):
        return FakeLocation(self._path)


@unittest.skipIf(IMPORT_PROBLEM, f"GNOME's Nautilus libraries are not here ({IMPORT_PROBLEM})")
class MakeEditorReadyMenuTest(unittest.TestCase):
    """The regression test for the missing menu of 2026-09-04."""

    @classmethod
    def setUpClass(cls):
        import importlib.util

        cls.path = _extension_path()
        if not cls.path.is_file():
            raise unittest.SkipTest(f"no extension file at {cls.path}")

        # THE ACTUAL REGRESSION. Before the fix, this line raised
        # ValueError: Namespace Nautilus is already loaded with version 4.1
        spec = importlib.util.spec_from_file_location("aquarius_editor_ready", cls.path)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

        cls.provider_class = None
        for value in vars(cls.module).values():
            if (
                isinstance(value, type)
                and issubclass(value, Nautilus.MenuProvider)
                and value is not Nautilus.MenuProvider
            ):
                cls.provider_class = value
                break
        print(
            f"\n  loaded {cls.path} against the Nautilus {NAUTILUS_VERSION} "
            "extension interface"
        )

    def setUp(self):
        self.assertIsNotNone(
            self.provider_class,
            "the extension loaded but defines no Nautilus.MenuProvider, so Files "
            "would load it and get no menu out of it",
        )
        self.provider = self.provider_class()

    @staticmethod
    def _labels(items):
        return [item.get_property("label") for item in items]

    # ------------------------------------------------------------------
    def test_a_video_offers_the_menu_item(self):
        """Right-click one MP4 — the thing Royce did on the bench."""
        items = self.provider.get_file_items([FakeFile("/tmp/clip.mp4", "video/mp4")])
        self.assertEqual(
            self._labels(items),
            ["Make Editor-Ready"],
            "right-clicking a video did not offer 'Make Editor-Ready'",
        )
        print("  PROOF: right-clicking clip.mp4 offers 'Make Editor-Ready'")

    def test_the_other_camera_formats_offer_it_too(self):
        """Everything a camera can hand you, not just MP4."""
        cases = {
            "clip.mp4": "video/mp4",
            "clip.mov": "video/quicktime",
            "clip.mts": "video/mp2t",
            "clip.MTS": "video/MP2T",  # some type databases capitalise this one
            "clip.mkv": "video/x-matroska",
            "clip.avi": "video/x-msvideo",
            "photo.heic": "image/heic",
            "photo.heif": "image/heif",
        }
        for name, mime in cases.items():
            with self.subTest(name=name, mime=mime):
                items = self.provider.get_file_items([FakeFile(f"/tmp/{name}", mime)])
                self.assertEqual(
                    self._labels(items),
                    ["Make Editor-Ready"],
                    f"{name} ({mime}) was left out of the menu",
                )

    def test_a_text_file_offers_nothing(self):
        """No menu item at all on things aq-ingest cannot use."""
        for name, mime in (("notes.txt", "text/plain"), ("budget.pdf", "application/pdf")):
            with self.subTest(name=name):
                items = self.provider.get_file_items([FakeFile(f"/tmp/{name}", mime)])
                self.assertEqual(
                    items, [], f"{name} should not offer a Make Editor-Ready item"
                )

    def test_a_folder_offers_it(self):
        """A camera card is a folder as far as a file manager is concerned."""
        items = self.provider.get_file_items(
            [FakeFile("/tmp/DCIM", "inode/directory")]
        )
        self.assertEqual(self._labels(items), ["Make Editor-Ready"])

    def test_right_clicking_the_background_of_a_folder_offers_it(self):
        """Open the card, right-click the empty space — the common case.

        This one needs a folder that really exists, because the extension checks
        the disk before offering to work on it.
        """
        with tempfile.TemporaryDirectory() as folder:
            items = self.provider.get_background_items(
                FakeFile(folder, "inode/directory")
            )
            self.assertEqual(self._labels(items), ["Make Editor-Ready"])

    def test_things_that_are_not_really_on_this_computer_are_left_out(self):
        """A file on a phone or a network share has no path aq-ingest can use."""

        class Remote(FakeFile):
            def get_location(self):
                return None

        items = self.provider.get_file_items([Remote("mtp://phone/clip.mp4", "video/mp4")])
        self.assertEqual(items, [])


if __name__ == "__main__":
    unittest.main(verbosity=2, buffer=False, argv=[sys.argv[0]])
