"""Milestone 2 — the Dolphin right-click menu, and how the tool gets into the OS.

The menu item itself can only really be tested by right-clicking it on a KDE machine.
What CAN be checked here, on any computer, is everything that silently breaks it:

  * the file in the wrong folder (Plasma 5's folder instead of Plasma 6's),
  * a missing executable bit (KDE ignores service menus it does not trust),
  * an Exec line naming a command the image does not install,
  * a mime type list that leaves out video, or folders, or iPhone photos,
  * a Terminal=true that would flash a black window in the user's face,
  * and the image wiring: no aq-ingest in /usr/bin means the menu item does nothing.

`desktop-file-validate` is deliberately NOT used: it does not know KDE's Type=Service and
reports the whole (correct) file as an error. These checks understand the format instead.
"""

from __future__ import annotations

import os
import unittest
from pathlib import Path

from aq_ingest import cli

#: ingest/tests/ -> ingest/ -> the os-image repo root
REPO = Path(__file__).resolve().parents[2]

#: Plasma 6 / KDE Frameworks 6 location. Plasma 5 used kservices5/ServiceMenus.
SERVICEMENU_DIR = REPO / "system_files/usr/share/kio/servicemenus"

MENU_FILE = SERVICEMENU_DIR / "aquarius-make-editor-ready.desktop"

#: The name Royce approved in the spec (§4). Changing it changes what he right-clicks.
MENU_LABEL = "Make Editor-Ready"


def parse_desktop(path: Path) -> dict[str, dict[str, str]]:
    """A small, strict reader for .desktop files.

    Groups in order, keys per group, comments and blank lines dropped. Raises on a
    duplicate key or a line that is neither — both of which KDE would quietly mis-read.
    """
    groups: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            name = line[1:-1]
            if name in groups:
                raise AssertionError(f"{path.name}:{number}: group [{name}] appears twice")
            current = groups[name] = {}
            continue
        if current is None:
            raise AssertionError(f"{path.name}:{number}: a setting before any [Group]")
        if "=" not in line:
            raise AssertionError(f"{path.name}:{number}: not a setting or a comment: {line!r}")
        key, _, value = line.partition("=")
        key = key.strip()
        if key in current:
            raise AssertionError(f"{path.name}:{number}: {key} is set twice")
        current[key] = value.strip()
    return groups


def semicolon_list(value: str) -> list[str]:
    return [item for item in value.split(";") if item]


class ServiceMenuFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(
            MENU_FILE.is_file(),
            f"the right-click menu file is missing: {MENU_FILE}",
        )
        self.groups = parse_desktop(MENU_FILE)
        self.entry = self.groups["Desktop Entry"]

    # -- where it lives ------------------------------------------------------------

    def test_it_is_in_the_plasma_6_folder_not_the_plasma_5_one(self):
        self.assertEqual(MENU_FILE.parent, SERVICEMENU_DIR)
        old = REPO / "system_files/usr/share/kservices5"
        self.assertFalse(old.exists(), "kservices5 is the Plasma 5 folder — KF6 ignores it")

    def test_kde_will_trust_it_because_it_is_executable(self):
        self.assertTrue(
            os.access(MENU_FILE, os.X_OK),
            "KDE ignores a service menu whose file is not marked executable "
            "(chmod +x, and build.sh re-applies it inside the image)",
        )

    def test_every_servicemenu_we_ship_is_checked_by_this_test(self):
        shipped = sorted(p.name for p in SERVICEMENU_DIR.glob("*.desktop"))
        self.assertEqual(
            shipped,
            [MENU_FILE.name],
            "a new service menu was added — extend these tests to cover it",
        )

    # -- the [Desktop Entry] group -------------------------------------------------

    def test_it_is_a_service_menu_and_not_an_application(self):
        self.assertEqual(self.entry["Type"], "Service")

    def test_it_does_not_carry_the_dead_plasma_5_key(self):
        self.assertNotIn(
            "ServiceTypes",
            self.entry,
            "ServiceTypes=KonqPopupMenu/Plugin was removed in Frameworks 6",
        )

    def test_it_shows_up_at_the_top_of_the_menu(self):
        self.assertEqual(self.entry.get("X-KDE-Priority"), "TopLevel")

    def test_it_uses_the_aquarius_logo_we_actually_ship(self):
        icon = self.entry["Icon"]
        self.assertEqual(icon, "aquarius-logo")
        self.assertTrue(
            (REPO / f"system_files/usr/share/icons/hicolor/scalable/apps/{icon}.svg").is_file(),
            "the icon named here is not in the image",
        )

    def test_you_can_right_click_video_photos_and_folders(self):
        mimetypes = semicolon_list(self.entry["MimeType"])
        self.assertIn("video/*", mimetypes)
        self.assertIn("inode/directory", mimetypes, "a camera card is a folder")
        self.assertIn("image/heic", mimetypes)
        self.assertIn("image/heif", mimetypes)

    def test_it_does_not_offer_itself_on_things_it_cannot_help_with(self):
        mimetypes = semicolon_list(self.entry["MimeType"])
        for unwanted in ("*/*", "all/all", "application/octet-stream", "text/plain"):
            self.assertNotIn(unwanted, mimetypes)

    # -- the action ----------------------------------------------------------------

    def test_every_listed_action_has_a_section_and_the_other_way_round(self):
        listed = semicolon_list(self.entry["Actions"])
        sections = [g for g in self.groups if g.startswith("Desktop Action ")]
        self.assertEqual(
            sorted(listed),
            sorted(g.removeprefix("Desktop Action ") for g in sections),
            "an action is listed with no section, or a section is never listed",
        )
        self.assertEqual(listed, ["makeEditorReady"])

    def test_the_menu_says_what_the_spec_says_it_says(self):
        self.assertEqual(self.groups["Desktop Action makeEditorReady"]["Name"], MENU_LABEL)

    def test_clicking_it_runs_our_command_the_way_we_mean_it_to(self):
        exec_line = self.groups["Desktop Action makeEditorReady"]["Exec"]
        self.assertEqual(exec_line, "aq-ingest --notify %F")

    def test_the_exec_line_is_a_command_line_aq_ingest_understands(self):
        exec_line = self.groups["Desktop Action makeEditorReady"]["Exec"]
        program, *arguments = exec_line.split()
        self.assertEqual(program, "aq-ingest")
        # Swap KDE's placeholder for what it expands to, then let argparse judge it.
        arguments = ["/run/media/royce/CARD" if a == "%F" else a for a in arguments]
        args = cli.build_parser().parse_args(arguments)
        self.assertTrue(args.notify, "the menu must run with notifications, or it looks dead")
        self.assertFalse(args.dry_run, "the menu must actually do the work")
        self.assertTrue(args.paths, "the menu passes no files to work on")

    def test_no_terminal_window_is_flashed_at_the_user(self):
        for group in self.groups.values():
            self.assertNotEqual(group.get("Terminal", "false").lower(), "true")


class ImageWiringTests(unittest.TestCase):
    """The menu item is useless unless the image really installs the command it names."""

    def setUp(self) -> None:
        self.build = (REPO / "build_files/build.sh").read_text(encoding="utf-8")
        self.containerfile = (REPO / "Containerfile").read_text(encoding="utf-8")
        # The lines that actually run, with the comments dropped. Some of the comments
        # in build.sh quote the wrong ways of doing things in order to warn about them,
        # so a check for "this must not appear" has to look at the code, not the prose.
        self.build_code = "\n".join(
            line for line in self.build.splitlines() if not line.lstrip().startswith("#")
        )

    def test_the_build_can_see_the_ingest_source(self):
        self.assertIn(
            "COPY ingest /ingest",
            self.containerfile,
            "build.sh reads the tool from /ctx/ingest, so the Containerfile must copy it in",
        )

    def test_the_command_is_installed_where_the_menu_looks_for_it(self):
        self.assertIn("/usr/bin/aq-ingest", self.build)
        self.assertIn("/ctx/ingest/aq-ingest", self.build)

    def test_the_code_the_command_imports_is_installed_too(self):
        self.assertIn("/ctx/ingest/aq_ingest", self.build)
        self.assertIn(
            'AQ_INGEST_SITE="/usr/lib/python${AQ_PYTHON_VERSION}/site-packages"',
            self.build,
            "the package must land in the image's own Python folder",
        )

    def test_the_install_never_goes_back_to_the_sysconfig_answer(self):
        # Fedora patches Python so that sysconfig's "purelib" answers /usr/local/lib/...
        # outside an RPM build. On an ostree image /usr/local is not ours and is not even
        # a real folder at build time, so that answer fails the build outright — it did
        # once already (Actions run 33219496395). The comment above the fix explains it;
        # this test is what stops someone "tidying" it back.
        self.assertNotIn("purelib", self.build_code)
        self.assertNotIn("sysconfig", self.build_code)
        self.assertNotIn("/usr/local", self.build_code)
        # …and the warning that explains why must stay next to the fix.
        self.assertIn("sysconfig", self.build, "the explanation was deleted with the bug")

    def test_the_build_marks_the_service_menu_executable(self):
        self.assertIn("chmod 0755 /usr/share/kio/servicemenus/*.desktop", self.build)

    def test_notify_send_is_installed(self):
        self.assertIn("dnf5 install -y libnotify", self.build)

    def test_the_build_proves_the_command_starts(self):
        self.assertIn("/usr/bin/aq-ingest --version", self.build)


if __name__ == "__main__":
    unittest.main()
