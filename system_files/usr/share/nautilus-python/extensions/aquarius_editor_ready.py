# =============================================================================
# AquariusOS — "Make Editor-Ready" right-click menu (GNOME Files / Nautilus)
# =============================================================================
# Plain English: this file is what puts "Make Editor-Ready" in the menu you get
# when you right-click a camera card, a folder, or some video clips in Files.
# Clicking it runs the aq-ingest tool on whatever you selected, in the
# background, and the tool tells you what it did with desktop notifications.
#
# It is the GNOME twin of the KDE version, which is a completely different kind
# of file:
#
#   KDE    /usr/share/kio/servicemenus/aquarius-make-editor-ready.desktop
#          — a settings file. KDE reads it and builds the menu item itself.
#   GNOME  this file
#          — a small program. GNOME has no settings-file way to add a menu item;
#            the supported way is a Python extension, which is what this is.
#
# ⚠️ BOTH FILES SHIP ON BOTH IMAGES and that is deliberate — neither desktop
# reads the other's, so each one is simply ignored where it does not belong.
# The KDE one is the older of the two and it is the reference for WHAT the menu
# item does; if you change the command, change it in both.
#
# THE ONE THING THAT MAKES THIS WORK AT ALL
# GNOME cannot read this file on its own. It needs the `nautilus-python`
# package, which is the bridge between Files and Python extensions.
# build_files/gnome-desktop.sh installs it on the GNOME images. Without that
# package this file is just text on a disk and the menu item never appears,
# with no error anywhere — which is why the build installs the package and
# checks this file compiles rather than assuming either.
#
# WHERE THIS FILE HAS TO LIVE
#   /usr/share/nautilus-python/extensions/     <- system-wide (ours)
#   ~/.local/share/nautilus-python/extensions/ <- one person's own
# Anywhere else and Files never looks at it.
#
# AFTER CHANGING THIS FILE ON A RUNNING MACHINE, Files has to be restarted
# before it notices:  nautilus -q   (it starts again on its own next time you
# open a folder).
#
# The tool itself, and what it actually does to your footage: ingest/README.md
# and docs/ingest-right-click.md.
# =============================================================================

import os
import subprocess

import gi

# ⚠️ NEVER PIN A SINGLE INTERFACE VERSION HERE. This bit line, and the reason
# it is written the way it is, cost Royce a bench session on 2026-09-04.
#
# The number below is not the version of Nautilus. It is the version of the
# extension interface. It was 4.0 from Nautilus 43 (the move to GTK4) until
# Fedora 44 shipped Nautilus 50, which brought interface 4.1 with it.
#
# The old line said, flatly, `gi.require_version("Nautilus", "4.0")`. What
# happens then is this: nautilus-python has ALREADY loaded the interface — at
# 4.1 — before it hands this file to Python. Asking for 4.0 at that point is not
# a polite preference, it is a contradiction, and Python stops the file dead:
#
#     ValueError: Namespace Nautilus is already loaded with version 4.1
#
# The extension never finishes loading, so it never registers its menu, so the
# "Make Editor-Ready" item is simply not in the right-click menu — with no error
# anywhere a person would look. (To see it: run `NAUTILUS_PYTHON_DEBUG=misc
# nautilus` in a terminal and read the traceback it prints.)
#
# So: ask for the newest interface we know about, fall back to the older one,
# and if neither request can be honoured, say nothing at all and carry on. That
# last case is the normal one — Files has already loaded the interface for us
# and there is nothing left to ask for.
for _interface_version in ("4.1", "4.0"):
    try:
        gi.require_version("Nautilus", _interface_version)
        break
    except ValueError:
        # Either this machine's Files does not offer that interface version, or
        # it has already loaded a different one, which is fine — the import
        # below then simply uses the one that is already loaded.
        continue

from gi.repository import GObject, Nautilus  # noqa: E402  (must follow require_version)


# The command this menu item runs. Exactly the same one the KDE service menu
# runs, and the two must stay in step.
#
#   --notify   report progress and the result as desktop notifications. There is
#              no terminal window here for the tool to print into, so without
#              this the work would happen in complete silence.
INGEST_COMMAND = "/usr/bin/aq-ingest"
INGEST_ARGS = ["--notify"]

# What you are allowed to right-click on. The same list as the KDE version:
# any video, iPhone HEIC photos, and folders — a camera card mounted on the
# desktop is a folder as far as a file manager is concerned.
#
# Videos are matched by their first half ("video/") because there are dozens of
# video types and they all start the same way. The photo types are listed in
# full because only these particular ones need converting.
PHOTO_TYPES = {
    "image/heif",
    "image/heic",
    "image/heif-sequence",
    "image/heic-sequence",
}
FOLDER_TYPE = "inode/directory"


def _is_interesting(file_info):
    """True if this is something aq-ingest could do anything with.

    The type is lower-cased first. Almost every type comes back lower-case
    already, but a few camera formats are written with capitals in places
    (MPEG-2 transport streams, the .MTS files a Sony camera makes, are listed as
    "video/MP2T" in some versions of the type database), and a capital letter
    must not be the reason a clip is left out of the menu.
    """
    mime = (file_info.get_mime_type() or "").lower()
    return (
        mime.startswith("video/")
        or mime in PHOTO_TYPES
        or mime == FOLDER_TYPE
    )


def _local_path(file_info):
    """The ordinary /path/to/file for a thing in Files, or None.

    Files can show you things that are not really on this computer — a folder on
    a phone, a network share, a file inside an archive. Those have no ordinary
    path, and aq-ingest works on real files with real paths. `get_location()`
    hands back None for anything else, and everywhere this function is used, a
    None simply means "leave that one out".
    """
    location = file_info.get_location()
    if location is None:
        return None
    return location.get_path()


class AquariusEditorReady(GObject.GObject, Nautilus.MenuProvider):
    """Adds "Make Editor-Ready" to the right-click menu in Files."""

    # ------------------------------------------------------------------
    # Right-clicking on selected files or folders
    # ------------------------------------------------------------------
    def get_file_items(self, files):
        paths = [
            path
            for path in (_local_path(f) for f in files if _is_interesting(f))
            if path
        ]
        if not paths:
            # Nothing we can work on. Return no menu items at all rather than a
            # greyed-out one — a menu item that never does anything is worse
            # than no menu item.
            return []
        return [self._menu_item("AquariusEditorReady::Selection", paths)]

    # ------------------------------------------------------------------
    # Right-clicking on the empty space inside a folder
    # ------------------------------------------------------------------
    # This is the "do the whole card" case, and it is the one people actually
    # use: open the camera card, right-click the background, one click.
    def get_background_items(self, folder):
        path = _local_path(folder)
        if not path or not os.path.isdir(path):
            return []
        return [self._menu_item("AquariusEditorReady::Folder", [path])]

    # ------------------------------------------------------------------
    def _menu_item(self, name, paths):
        item = Nautilus.MenuItem(
            name=name,
            label="Make Editor-Ready",
            tip="Write editor-friendly copies next to these files, so DaVinci "
                "Resolve opens them with picture and sound. Your originals are "
                "never changed.",
        )
        item.connect("activate", self._run, paths)
        return item

    def _run(self, _menu_item, paths):
        """Start aq-ingest and get out of the way.

        ⚠️ THIS MUST NOT WAIT FOR THE TOOL TO FINISH. This function runs inside
        Files itself, on the same thread that draws its window. Waiting here
        would freeze the whole file manager — with no window, no progress bar
        and no way to cancel — for however long it takes to convert a card full
        of footage, which can be twenty minutes. Popen starts the tool and
        returns immediately; the tool talks to the user through desktop
        notifications from then on.

        start_new_session=True puts the tool in a process group of its own, so
        closing the Files window does not take the conversion down with it.
        """
        try:
            subprocess.Popen(
                [INGEST_COMMAND, *INGEST_ARGS, *paths],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as error:
            # If the tool cannot even be started, say so with a notification
            # rather than letting the exception escape. An extension that
            # raises can take the whole right-click menu down with it.
            subprocess.Popen(
                [
                    "notify-send",
                    "--app-name=AquariusOS",
                    "Make Editor-Ready could not start",
                    f"{INGEST_COMMAND} could not be run: {error}",
                ],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
