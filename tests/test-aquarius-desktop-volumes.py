#!/usr/bin/env python3
# ==============================================================================
# Tests for "drives on the desktop, and no app icons on the desktop"
# ==============================================================================
# The script under test is
#   system_files/usr/libexec/aquarius-desktop-volumes
#
# It has two jobs, and each one has a way of going wrong that would be genuinely
# upsetting rather than merely annoying:
#
#   1. It writes and deletes files inside somebody's Desktop folder. A bug here
#      does not draw a wrong icon — it eats a file. So the tests that matter most
#      in here are the ones that prove it only ever deletes its OWN files.
#
#   2. It moves application shortcuts off the desktop. The same rule applies: it
#      must never move a document, never move a bookmark, and never move one of
#      its own drive icons.
#
# Every test builds a complete little pretend world in a temporary folder — a
# pretend desktop, pretend files, a saved copy of a real machine's list of
# mounted drives — runs the real functions against it, and looks at what changed.
# No real drives are read and no real desktop is touched.
#
# HOW TO RUN IT
#   ./tests/test-aquarius-desktop-volumes.py
#   ./tests/test-aquarius-desktop-volumes.py /usr/libexec/aquarius-desktop-volumes
# ==============================================================================

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SCRIPT = os.path.join(
    HERE, "..", "system_files", "usr", "libexec", "aquarius-desktop-volumes"
)

# ------------------------------------------------------------------------------
# A saved copy of what /proc/self/mountinfo really looks like on an AquariusOS
# machine: the system disk (mounted in several places at once, which is normal on
# this kind of OS), a Windows game drive, a camera card, and a pile of things
# that are not drives at all and must never get an icon.
#
# The format is the kernel's, not ours:
#   id parent major:minor root mountpoint options... - fstype source superoptions
# ------------------------------------------------------------------------------
FAKE_MOUNTINFO = """\
21 26 0:19 / /proc rw,nosuid,nodev,noexec - proc proc rw
22 26 0:20 / /sys rw,nosuid,nodev,noexec - sysfs sysfs rw
23 26 0:5 / /dev rw,nosuid - devtmpfs devtmpfs rw
25 26 0:23 / /run rw,nosuid,nodev - tmpfs tmpfs rw
26 1 259:3 /root / rw,relatime - btrfs /dev/nvme0n1p3 rw,compress=zstd:1
27 26 259:3 /var /var rw,relatime - btrfs /dev/nvme0n1p3 rw,compress=zstd:1
28 26 259:3 /root/etc /etc rw,relatime - btrfs /dev/nvme0n1p3 rw
29 26 259:2 / /boot rw,relatime - ext4 /dev/nvme0n1p2 rw
30 29 259:1 / /boot/efi rw,relatime - vfat /dev/nvme0n1p1 rw
31 25 8:2 / /run/media/system/Games rw,noatime - ntfs3 /dev/sda2 rw,uid=1000
32 25 8:17 / /run/media/royce/CANON_SD rw,nosuid,nodev - exfat /dev/sdb1 rw,uid=1000
33 26 0:44 / /home/royce/.var/app/com.obsproject.Studio rw - tmpfs tmpfs rw
34 25 0:52 / /run/user/1000/doc rw,nosuid,nodev - fuse.portal portal rw
35 26 7:0 / /var/lib/snapd/snap/core rw - squashfs /dev/loop0 ro
"""


def load(path: str):
    """Import a script that has no `.py` on the end of its name."""
    spec = importlib.util.spec_from_loader(
        "aquarius_desktop_volumes",
        importlib.machinery.SourceFileLoader("aquarius_desktop_volumes", path),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PASSED = 0
FAILED = 0


def check(description: str, condition: bool) -> None:
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  OK    {description}")
    else:
        FAILED += 1
        print(f"  FAIL  {description}")


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def main(argv: list[str]) -> int:
    script = argv[0] if argv else DEFAULT_SCRIPT
    if not os.path.isfile(script):
        print(f"test-aquarius-desktop-volumes: cannot find {script}", file=sys.stderr)
        return 1

    module = load(script)
    work = tempfile.mkdtemp(prefix="aquarius-desktop-test-")

    try:
        # ---------------------------------------------------------------------
        print("\nWorking out which mounted things are actually drives")
        print("-" * 70)
        # ---------------------------------------------------------------------
        mountinfo = os.path.join(work, "mountinfo")
        write(mountinfo, FAKE_MOUNTINFO)
        rows = module.mount_table(mountinfo)
        check(
            "every line of the kernel's mount table is read without choking on it",
            len(rows) == len(FAKE_MOUNTINFO.strip().splitlines()),
        )
        check(
            "...including the awkward part, where the filesystem type sits after "
            "a lone '-' at an unpredictable position",
            {row["fstype"] for row in rows} >= {"btrfs", "ntfs3", "exfat", "vfat", "proc"},
        )

        labels = {"/dev/sda2": "Game Drive", "/dev/sdb1": "CANON_SD"}
        found = module.drives(rows=rows, labels=labels)
        names = [drive["name"] for drive in found]
        points = [drive["mountpoint"] for drive in found]

        check("the drive AquariusOS is installed on gets an icon", "AquariusOS" in names)
        check("...and it is the one mounted at /", found[0]["mountpoint"] == "/")
        check(
            "...and it is the first icon, so it sits at the top of the column",
            names[0] == "AquariusOS",
        )
        check("the Windows game drive gets an icon", "Game Drive" in names)
        check("the camera card in the reader gets an icon", "CANON_SD" in names)
        check("a drive is named by its own label, not by its folder", "sda2" not in names)

        check("/boot is not something to put on a desktop", "/boot" not in points)
        check("...nor is the EFI boot partition", "/boot/efi" not in points)
        check("/var is not a second icon for the system disk", "/var" not in points)
        check(
            "the system disk gets exactly ONE icon even though it is mounted "
            "in four places",
            points.count("/") == 1 and len(found) == 3,
        )
        check("the kernel's own bookkeeping folders are not drives", "/proc" not in points)
        check("a Flatpak app's innards are not a drive", not any("obsproject" in p for p in points))
        check("a Snap package image is not a drive", not any("snapd" in p for p in points))
        check("a portal folder in /run/user is not a drive", not any("/run/user" in p for p in points))

        # ---------------------------------------------------------------------
        print("\nThe shortcut file we write for a drive")
        print("-" * 70)
        # ---------------------------------------------------------------------
        games = next(drive for drive in found if drive["name"] == "Game Drive")
        text = module.shortcut_text(games)
        check(
            "[Desktop Entry] is the very first line, as the standard requires",
            text.startswith("[Desktop Entry]\n"),
        )
        check("it is a shortcut to a PLACE, so it opens without a warning", "Type=Link" in text)
        check("...pointing at where the drive is mounted", "URL=file:///run/media/system/Games" in text)
        check("...showing the drive's own name", "Name=Game Drive" in text)
        check("...with a drive picture on it", "Icon=drive-harddisk" in text)
        check("...and our own mark, so we can recognise it later", module.OUR_MARKER in text)

        root = found[0]
        check(
            "the system drive gets the special 'this is the OS disk' picture",
            "Icon=drive-harddisk-root" in module.shortcut_text(root),
        )

        spacey = module.shortcut_text(
            {"name": "My Drive", "mountpoint": "/run/media/system/My Drive", "icon": "drive-harddisk"}
        )
        check(
            "a space in a drive's name does not break the address KDE follows",
            "URL=file:///run/media/system/My%20Drive" in spacey,
        )

        check(
            "a drive's name becomes a filename ending in .desktop, which KDE requires",
            module.safe_filename("Game Drive") == "Game Drive.desktop",
        )
        check(
            "a slash in a drive's name cannot escape the Desktop folder",
            "/" not in module.safe_filename("Photos/2026"),
        )
        check(
            "a drive whose name starts with a dot does not become invisible",
            not module.safe_filename(".secret").startswith("."),
        )
        check(
            "a space in a drive's real name is read back correctly from /dev",
            module.unescape_device_name(r"Game\x20Drive") == "Game Drive",
        )
        check(
            "...and so is an accented letter, which /dev writes as two codes",
            module.unescape_device_name(r"Vid\xc3\xa9o") == "Vidéo",
        )

        # ---------------------------------------------------------------------
        print("\nKeeping the desktop's drive icons up to date")
        print("-" * 70)
        # ---------------------------------------------------------------------
        desktop = os.path.join(work, "Desktop")
        os.makedirs(desktop)

        # Things belonging to the person using the machine. NONE of these may be
        # touched, ever, by anything below.
        write(os.path.join(desktop, "Shot List.txt"), "wide, medium, close\n")
        write(os.path.join(desktop, "notes.md"), "# notes\n")
        os.makedirs(os.path.join(desktop, "Client Folder"))
        write(
            os.path.join(desktop, "My Bookmark.desktop"),
            "[Desktop Entry]\nType=Link\nName=A website\nURL=https://example.com\n",
        )

        module.drives = lambda rows=None, labels=None: found  # type: ignore[assignment]
        module.sync_drive_icons(desktop, True)

        after = set(os.listdir(desktop))
        check("the drive icons appear", {"AquariusOS.desktop", "Game Drive.desktop"} <= after)
        check("the person's own text file is untouched", "Shot List.txt" in after)
        check("...and their notes", "notes.md" in after)
        check("...and their folder", "Client Folder" in after)
        check("...and their website bookmark", "My Bookmark.desktop" in after)

        # Running twice must change nothing at all — no churn, no rewriting.
        stamps = {name: os.stat(os.path.join(desktop, name)).st_mtime_ns for name in after}
        module.sync_drive_icons(desktop, True)
        unchanged = all(
            os.stat(os.path.join(desktop, name)).st_mtime_ns == stamp
            for name, stamp in stamps.items()
        )
        check("running again rewrites nothing — the desktop does not churn", unchanged)

        # Now unplug the camera card and the game drive.
        module.drives = lambda rows=None, labels=None: [root]  # type: ignore[assignment]
        module.sync_drive_icons(desktop, True)
        after = set(os.listdir(desktop))
        check("a drive that has been unplugged loses its icon", "Game Drive.desktop" not in after)
        check("...while the drive still there keeps its icon", "AquariusOS.desktop" in after)
        check("...and the person's own files are STILL untouched", "Shot List.txt" in after)
        check("...bookmark included", "My Bookmark.desktop" in after)

        # And the off switch.
        module.sync_drive_icons(desktop, False)
        after = set(os.listdir(desktop))
        check("switching drive icons off removes ours", "AquariusOS.desktop" not in after)
        check("...and still leaves everything of theirs alone", "Shot List.txt" in after)
        check("...bookmark included", "My Bookmark.desktop" in after)

        # ---------------------------------------------------------------------
        print("\nKeeping application icons off the desktop")
        print("-" * 70)
        # ---------------------------------------------------------------------
        home = os.path.join(work, "home")
        os.makedirs(home)
        module.HOLDING_DIR = os.path.join(home, "app-icons")
        module.notify = lambda title, body: None  # type: ignore[assignment]

        write(
            os.path.join(desktop, "firefox.desktop"),
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=firefox\n",
        )
        module.drives = lambda rows=None, labels=None: found  # type: ignore[assignment]
        module.sync_drive_icons(desktop, True)
        module.tidy_app_icons(desktop)

        after = set(os.listdir(desktop))
        check("an app icon dropped on the desktop is taken off it", "firefox.desktop" not in after)
        check(
            "...and is NOT deleted — it is waiting in the holding folder",
            os.path.isfile(os.path.join(module.HOLDING_DIR, "firefox.desktop")),
        )
        check(
            "...with a note in there explaining what happened and how to stop it",
            os.path.isfile(os.path.join(module.HOLDING_DIR, "README.txt")),
        )
        check("our own drive icons are not mistaken for apps", "Game Drive.desktop" in after)
        check("a bookmark is a file, not an app, and stays", "My Bookmark.desktop" in after)
        check("an ordinary document is never touched", "Shot List.txt" in after)
        check("nor is a folder", "Client Folder" in after)

        # A second app with the same name must not overwrite the first one that
        # was tidied away.
        write(
            os.path.join(desktop, "firefox.desktop"),
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=firefox --new\n",
        )
        module.tidy_app_icons(desktop)
        check(
            "a second copy does not overwrite the one already in the holding folder",
            os.path.isfile(os.path.join(module.HOLDING_DIR, "firefox (2).desktop")),
        )

        # ---------------------------------------------------------------------
        print("\nThe two switches in ~/.config/aquarius-desktop.conf")
        print("-" * 70)
        # ---------------------------------------------------------------------
        config = os.path.join(work, "aquarius-desktop.conf")
        module.CONFIG_PATH = config

        settings = module.read_config()
        check("with no config file, drive icons are ON", settings["ShowDrivesOnDesktop"])
        check("with no config file, app icons are tidied away", settings["KeepAppIconsOffDesktop"])

        write(config, "# my machine, my rules\nKeepAppIconsOffDesktop=false\n")
        settings = module.read_config()
        check("the tidy-up can be switched off in one line", not settings["KeepAppIconsOffDesktop"])
        check("...without affecting the drive icons", settings["ShowDrivesOnDesktop"])

        write(config, "ShowDrivesOnDesktop=no\n")
        check("'no' works as well as 'false'", not module.read_config()["ShowDrivesOnDesktop"])

    finally:
        shutil.rmtree(work, ignore_errors=True)

    print()
    print(f"{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
