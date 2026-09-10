# =============================================================================
# aquarius_installer — the sorter, the routes and the registry
# =============================================================================
# PLAIN ENGLISH
#
# On a Mac you double-click the thing you downloaded and it installs. On Linux
# the same act is a research project: is it an .rpm, a .deb, an AppImage, a
# .flatpakref, a .run, a tarball with a program inside it? Aquarius Installer is
# one window that takes any of those and does the right thing with it.
#
# THIS FILE IS THE PART THAT DECIDES. It has no window in it and it imports
# nothing graphical, on purpose:
#
#     /usr/libexec/aquarius-installer     the window (draws)
#     /usr/bin/aq apps ...                the same jobs from a terminal
#     tests/test-installer-sorter.py      proves this file, with no screen
#
# ...all three call into here, so the window and the terminal can never disagree
# about what a file is or where an app went.
#
# -----------------------------------------------------------------------------
# THE ONE IDEA: THE PERSON NEVER CHOOSES THE ROUTE
# -----------------------------------------------------------------------------
# `sort_path()` looks at a file and picks one of a handful of ways to land it.
# Everything else in here is one of those ways. What a person sees is always the
# same: what it is, where it will go, an Install button.
#
# -----------------------------------------------------------------------------
# THE RULES THIS FILE OBEYS, ALL OF THEM WORTH SAYING OUT LOUD
# -----------------------------------------------------------------------------
# 1. NOTHING IS EVER LAYERED ONTO THE OPERATING SYSTEM. /usr is read-only and
#    updates are whole-image. A package that wants to change the system itself
#    is refused, plainly, with the reason. (Royce's decision, 2026-09-08.)
# 2. A PACKAGE'S OWN SCRIPTS ARE NEVER RUN. Not as you, not as an administrator,
#    not ever. `.rpm` and `.deb` files are UNPACKED — the same act for both, and
#    no conversion between them, ever.
# 3. IT REFUSES TO INSTALL OR REMOVE AS AN ADMINISTRATOR. Under `sudo` every
#    path below would point into the administrator's home folder, where the
#    person who asked can never see it, and the failure would look like success.
#    The one exception is a Flatpak, which is installed for the whole computer
#    by the existing helper through `pkexec` — one prompt, and this code has no
#    special powers at any moment.
# 4. NOTHING A PERSON READS NAMES ANOTHER LINUX. Royce's rule from
#    62-resolve-runtime.sh. Comments and command names may say what they must;
#    every message a person sees says "AquariusOS" and nothing else.
# 5. TRUST CONTENT, NEVER APPEARANCES. Nothing is called installed because a
#    command exited zero. Every install ends by reading the result back.
#
# -----------------------------------------------------------------------------
# WHERE THINGS GO
# -----------------------------------------------------------------------------
#     ~/.local/lib/aquarius/versions/<name>/<version>/   the app, unpacked
#     ~/.local/lib/aquarius/<name>            -> versions/<name>/<version>
#     ~/.local/share/applications/<name>.desktop         the menu entry
#     ~/.local/share/icons/hicolor/…/<name>.png          the icon
#     ~/.local/share/aquarius/apps/<name>.ini            the registry note
#     ~/.cache/aquarius/installer/                       downloads
#
# ⚠️ THAT IS DELIBERATELY THE SHAPE /usr/libexec/aquarius-appimage-install
#    ALREADY USES, and not the `~/.local/opt/<app>/` the feature note sketched.
#    Two reasons: the version is in the path with a link on top, so a half-
#    finished update can never replace a working app; and the existing installer,
#    the existing launcher and the existing update machinery all already know
#    this shape. One shape, one set of bugs.
# =============================================================================

import configparser
import datetime
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile

# -----------------------------------------------------------------------------
# The other halves of AquariusOS this one leans on
# -----------------------------------------------------------------------------
CATALOG_CLI = "/usr/libexec/aquarius-flatpak-preinstall"
FLATPAK_HELPER = "/usr/libexec/aquarius-creator-apps-install"
APPIMAGE_INSTALLER = "/usr/libexec/aquarius-appimage-install"

# -----------------------------------------------------------------------------
# The routes. A route is "how this file lands on this computer".
# -----------------------------------------------------------------------------
ROUTE_FLATPAK = "flatpak"        # through the pkexec helper, for the whole computer
ROUTE_APPIMAGE = "appimage"      # unpacked into the home folder
ROUTE_ARCHIVE = "archive"        # a tarball or zip with a program inside it
ROUTE_PACKAGE = "package"        # an .rpm or a .deb, unpacked, no scripts run
ROUTE_REFUSE = "refuse"          # we will not, and we say why

# What the OS calls itself in anything a person reads.
OS_NAME = "AquariusOS"


# =============================================================================
# Where everything lives
# =============================================================================
def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def app_root():
    return os.path.join(home(), ".local", "lib", "aquarius")


def versions_root():
    return os.path.join(app_root(), "versions")


def desktop_dir():
    return os.path.join(home(), ".local", "share", "applications")


def icon_root():
    return os.path.join(home(), ".local", "share", "icons", "hicolor")


def registry_dir():
    return os.path.join(home(), ".local", "share", "aquarius", "apps")


def cache_dir():
    return os.path.join(home(), ".cache", "aquarius", "installer")


# ⚠️ A REHEARSAL IS ALLOWED TO RUN AS AN ADMINISTRATOR, AND ONLY A REHEARSAL.
#    The image build and its tests run as root inside a container, with a
#    throwaway HOME they set themselves — so refusing root there would mean the
#    one place this code is checked is the one place it cannot run, and nothing
#    would ever be checked at all. /usr/libexec/aquarius-appimage-install makes
#    exactly this exception, for exactly this reason, and says so at length.
#    Nothing a person can click sets this.
REHEARSAL = False


def refuse_root():
    """Should this stop, because it is running as an administrator?"""
    return running_as_root() and not REHEARSAL


def running_as_root():
    return hasattr(os, "geteuid") and os.geteuid() == 0


ROOT_REFUSAL = (
    "Do not run this with sudo. It installs into your own home folder and needs "
    "no special permission at all. Run as an administrator it would install "
    "into the administrator's home folder instead, where you would never find "
    "it."
)


# =============================================================================
# Progress — the same vocabulary every AquariusOS installer speaks
# =============================================================================
# STEP / PERCENT / OK / FAILED / DONE / FAIL / CANCELLED, exactly as
# docs/restart/creator-apps.md writes it down. The window turns these into step
# rows and a bar; the terminal prints them; a test collects them in a list.
class Progress:
    """Somewhere to say what is happening. The default says it to nobody."""

    def __init__(self, on_line=None, on_log=None):
        self._on_line = on_line
        self._on_log = on_log
        self.lines = []
        self.log_lines = []

    def line(self, text):
        self.lines.append(text)
        if self._on_line:
            self._on_line(text)

    def log(self, text):
        self.log_lines.append(text)
        if self._on_log:
            self._on_log(text)

    def step(self, n, total, text):
        self.line("STEP %d/%d %s" % (n, total, text))

    def percent(self, value):
        self.line("PERCENT %d" % max(0, min(100, int(value))))

    def ok(self, app_id):
        self.line("OK %s" % app_id)

    def failed(self, app_id, why):
        self.line("FAILED %s %s" % (app_id, why))

    def done(self):
        self.line("DONE")

    def fail(self, why):
        self.line("FAIL %s" % why)

    def cancelled(self):
        self.line("CANCELLED")


# =============================================================================
# THE SORTER
# =============================================================================
# What a file is, and how it would land. Nothing here writes anything, so it is
# safe to run against a file somebody merely hovered over.
class Verdict:
    """What the sorter decided about one file."""

    def __init__(self, route, kind, name, **kw):
        self.route = route          # one of the ROUTE_ constants
        self.kind = kind            # a short machine word: rpm, deb, appimage…
        self.name = name            # what to call it on screen
        self.path = kw.get("path", "")
        self.version = kw.get("version", "")
        self.publisher = kw.get("publisher", "")
        self.signature = kw.get("signature", "unknown")  # signed/unsigned/unknown
        self.where = kw.get("where", "")        # one sentence: where it will go
        self.message = kw.get("message", "")    # why not, when we refuse
        self.flathub_hint = kw.get("flathub_hint", "")
        self.app_id = kw.get("app_id", "")      # for a Flatpak reference

    @property
    def can_install(self):
        return self.route != ROUTE_REFUSE

    def __repr__(self):
        return "<Verdict %s/%s %r>" % (self.route, self.kind, self.name)


# The sentences. They live together in one block so that the rule "nothing a
# person reads names another Linux" can be checked by reading one place.
SAY = {
    "home": "It goes into your own apps. No password needed.",
    "flatpak": "It comes from Flathub, for the whole computer. "
               "You will be asked for your password once.",
    "os": "This package wants to change the operating system itself. "
          "%s does not allow that, so updates always work. If it is a driver "
          "or a system service %s should have, it belongs in the image — ask "
          "for it." % (OS_NAME, OS_NAME),
    "missing_parts": "This app needs parts %s does not have yet. A later "
                     "update will run it in its own environment." % OS_NAME,
    "run": "This is an installer program — a program whose job is to install "
           "another program. %s does not run those yet, because it cannot see "
           "what one would change. DaVinci Resolve is the exception and has a "
           "guided flow of its own: open \"Install DaVinci Resolve\" from your "
           "apps." % OS_NAME,
    "snap": "This is a Snap. %s uses Flathub instead." % OS_NAME,
    "windows": "This is a Windows program. %s cannot run it." % OS_NAME,
    "mac": "This is a Mac download. It cannot run here — look for the Linux "
           "download on the same page.",
    "unknown": "%s does not recognise this file, so it does not know what "
               "installing it would mean." % OS_NAME,
    "empty": "That file is empty.",
    "missing": "That file is not there any more.",
}

# The endings we know, and the word we use for each. Read longest-first, so
# ".tar.gz" is never mistaken for ".gz".
SUFFIXES = [
    (".flatpakref", "flatpakref"),
    (".flatpak", "flatpak"),
    (".appimage", "appimage"),
    (".rpm", "rpm"),
    (".deb", "deb"),
    (".tar.gz", "tar"),
    (".tgz", "tar"),
    (".tar.xz", "tar"),
    (".tar.bz2", "tar"),
    (".txz", "tar"),
    (".tar", "tar"),
    (".zip", "zip"),
    (".snap", "snap"),
    (".run", "run"),
    (".sh", "run"),
    (".exe", "windows"),
    (".msi", "windows"),
    (".dmg", "mac"),
    (".pkg", "mac"),
]


def kind_of(path):
    """The short word for what this file is, from its ending and its first bytes.

    The ending is asked first because it is what a person sees, and the bytes
    are asked when the ending says nothing — a file called `download` that is
    really an AppImage should still install.
    """
    lowered = os.path.basename(path).lower()
    for suffix, kind in SUFFIXES:
        if lowered.endswith(suffix):
            return kind
    return sniff(path)


def sniff(path):
    """What the first bytes of the file say it is. "" when they say nothing."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(1024)
    except OSError:
        return ""
    if head.startswith(b"\xed\xab\xee\xdb"):
        return "rpm"
    # A .deb is an `ar` archive whose first member is called debian-binary.
    # Both halves are asked for: plenty of things are `ar` archives (every
    # static library, for one) and none of the rest is an app.
    if head.startswith(b"!<arch>\n") and b"debian-binary" in head[:120]:
        return "deb"
    if head.startswith(b"PK\x03\x04"):
        return "zip"
    if head.startswith(b"\x1f\x8b"):
        return "tar"
    if head.startswith(b"\xfd7zXZ\x00"):
        return "tar"
    if head.startswith(b"BZh"):
        return "tar"
    # An AppImage is an ELF file with the letters "AI" and a version byte at
    # offset 8 — the "AppImage magic". That is how the format itself says so.
    if head.startswith(b"\x7fELF") and head[8:10] == b"AI":
        return "appimage"
    if head.startswith(b"[Flatpak Ref]"):
        return "flatpakref"
    if head.startswith(b"xar!"):
        return "mac"
    if head.startswith(b"MZ"):
        return "windows"
    return ""


def sort_path(path):
    """The whole sorter: a file in, a Verdict out. Changes nothing."""
    path = os.path.abspath(os.path.expanduser(path))
    display = os.path.basename(path)

    if not os.path.exists(path):
        return Verdict(ROUTE_REFUSE, "missing", display, path=path,
                       message=SAY["missing"])
    if os.path.isdir(path):
        return Verdict(ROUTE_REFUSE, "folder", display, path=path,
                       message="That is a folder, not something to install.")
    try:
        if os.path.getsize(path) == 0:
            return Verdict(ROUTE_REFUSE, "empty", display, path=path,
                           message=SAY["empty"])
    except OSError:
        pass

    kind = kind_of(path)

    if kind == "flatpakref":
        name, app_id = read_flatpakref(path)
        return Verdict(ROUTE_FLATPAK, kind, name or display, path=path,
                       app_id=app_id, where=SAY["flatpak"],
                       publisher="Flathub", signature="signed")
    if kind == "flatpak":
        return Verdict(ROUTE_FLATPAK, kind, display, path=path,
                       where=SAY["flatpak"], signature="unknown")
    if kind == "appimage":
        name, version = appimage_name(path)
        return Verdict(ROUTE_APPIMAGE, kind, name or display, path=path,
                       version=version, where=SAY["home"],
                       signature=signature_of(path))
    if kind in ("tar", "zip"):
        return Verdict(ROUTE_ARCHIVE, kind, display, path=path,
                       where=SAY["home"], signature=signature_of(path))
    if kind in ("rpm", "deb"):
        meta = package_metadata(path, kind)
        return Verdict(ROUTE_PACKAGE, kind, meta.get("name") or display,
                       path=path, version=meta.get("version", ""),
                       publisher=meta.get("publisher", ""),
                       signature=meta.get("signature", "unsigned"),
                       where=SAY["home"])
    if kind == "run":
        return Verdict(ROUTE_REFUSE, kind, display, path=path,
                       message=SAY["run"])
    if kind == "snap":
        return Verdict(ROUTE_REFUSE, kind, display, path=path,
                       message=SAY["snap"],
                       flathub_hint=flathub_term(display))
    if kind == "windows":
        return Verdict(ROUTE_REFUSE, kind, display, path=path,
                       message=SAY["windows"],
                       flathub_hint=flathub_term(display))
    if kind == "mac":
        return Verdict(ROUTE_REFUSE, kind, display, path=path,
                       message=SAY["mac"],
                       flathub_hint=flathub_term(display))
    return Verdict(ROUTE_REFUSE, "unknown", display, path=path,
                   message=SAY["unknown"])


def flathub_term(filename):
    """A search word to offer when we have refused something.

    The file name with its ending and its version numbers taken off, which is
    usually the app's name and is always better than offering nothing.
    """
    stem = os.path.basename(filename)
    stem = re.split(r"[-_](?=\d)", stem)[0]
    stem = re.sub(r"\.[A-Za-z0-9]{1,10}$", "", stem)
    return stem.strip("-_. ")


def signature_of(path):
    """Whether a plain file is signed. It never is, and we say so plainly.

    ⚠️ AN UNSIGNED FILE IS NEVER BLOCKED (Royce, 2026-09-08, open question 4).
    The window says what it knows once, in ordinary words, and lets the person
    decide. Blocking would mean refusing most of the good software on the
    internet in the name of a promise we cannot keep anyway.
    """
    return "unsigned"


def read_flatpakref(path):
    """The app's name and id out of a .flatpakref, which is an ini file."""
    name = app_id = ""
    try:
        with open(path, "r", errors="replace") as handle:
            for raw in handle:
                key, sep, value = raw.strip().partition("=")
                if not sep:
                    continue
                if key == "Name" and not app_id:
                    app_id = value.strip()
                elif key == "Title":
                    name = value.strip()
    except OSError:
        pass
    return name or app_id, app_id


def appimage_name(path):
    """A name and a version guessed from an AppImage's file name.

    Guessed, and only used as a heading before the file is opened. The real
    name comes out of the app's own menu entry once it is unpacked.
    """
    stem = os.path.basename(path)
    for suffix in (".AppImage", ".appimage"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
    match = re.search(r"[-_]([0-9][0-9A-Za-z.+~-]*)$", stem)
    version = ""
    if match:
        version = match.group(1)
        stem = stem[: match.start()]
    stem = re.sub(r"[-_](x86_64|amd64|linux)$", "", stem, flags=re.I)
    return stem.replace("_", " ").strip(), version


# =============================================================================
# Reading a package without unpacking it
# =============================================================================
def package_metadata(path, kind):
    """Name, version, publisher and signature, read out of the package itself.

    Everything here is "best effort and say so": a package we cannot read the
    name of still installs, it just shows up under its file name.
    """
    meta = {"signature": "unsigned"}
    if kind == "rpm":
        out = run_text(["rpm", "-qp", "--nosignature", "--queryformat",
                        "%{NAME}\\n%{VERSION}-%{RELEASE}\\n%{VENDOR}\\n"
                        "%{SIGPGP:pgpsig}\\n", path])
        fields = (out or "").splitlines()
        if len(fields) >= 3:
            meta["name"] = fields[0].strip()
            meta["version"] = fields[1].strip()
            publisher = fields[2].strip()
            meta["publisher"] = "" if publisher in ("(none)", "none") else publisher
        if len(fields) >= 4 and fields[3].strip() not in ("(none)", "none", ""):
            meta["signature"] = "signed"
    elif kind == "deb":
        out = run_text(["dpkg-deb", "-f", path, "Package", "Version", "Maintainer"])
        for raw in (out or "").splitlines():
            key, sep, value = raw.partition(":")
            if not sep:
                continue
            key = key.strip().lower()
            if key == "package":
                meta["name"] = value.strip()
            elif key == "version":
                meta["version"] = value.strip()
            elif key == "maintainer":
                meta["publisher"] = value.strip()
    return meta


def run_text(argv, timeout=30, cwd=None):
    """Run a command and give back its output, or None if it would not run."""
    try:
        done = subprocess.run(argv, capture_output=True, text=True,
                              timeout=timeout, errors="replace", cwd=cwd)
    except (OSError, subprocess.SubprocessError):
        return None
    if done.returncode != 0:
        return None
    return done.stdout


# =============================================================================
# UNPACKING — and the two things we look for once it is open
# =============================================================================
# ⚠️ NO MAINTAINER SCRIPT IS EVER RUN, AND THAT IS WHAT THESE TWO COMMANDS BUY.
#    `rpm2cpio | cpio` and `dpkg-deb -x` take the FILES out of a package and
#    nothing else. The install-time scripts, which on any other Linux run as an
#    administrator on your computer, are never even looked at.
def unpack(path, kind, into, progress):
    """Open a package or archive into `into`. True if anything came out."""
    os.makedirs(into, exist_ok=True)
    if kind == "rpm":
        return unpack_rpm(path, into, progress)
    if kind == "deb":
        return unpack_deb(path, into, progress)
    if kind == "appimage":
        return unpack_appimage(path, into, progress)
    if kind == "tar":
        return unpack_tar(path, into, progress)
    if kind == "zip":
        return unpack_zip(path, into, progress)
    return False


def unpack_rpm(path, into, progress):
    if not shutil.which("rpm2cpio") or not shutil.which("cpio"):
        progress.log("rpm2cpio or cpio is missing from this computer.")
        return False
    try:
        with open(path, "rb") as source:
            first = subprocess.Popen(["rpm2cpio", "-"], stdin=source,
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)
            second = subprocess.Popen(["cpio", "-idmu", "--quiet"],
                                      stdin=first.stdout,
                                      stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, cwd=into)
            first.stdout.close()
            _, err = second.communicate(timeout=900)
            first.wait(timeout=10)
    except (OSError, subprocess.SubprocessError) as exc:
        progress.log("Could not open the package: %s" % exc)
        return False
    if err:
        progress.log(err.decode("utf-8", "replace").strip())
    return has_content(into)


def unpack_deb(path, into, progress):
    if shutil.which("dpkg-deb"):
        done = subprocess.run(["dpkg-deb", "-x", path, into],
                              capture_output=True, text=True, errors="replace")
        if done.stderr.strip():
            progress.log(done.stderr.strip())
        if done.returncode == 0 and has_content(into):
            return True
    # The fallback, for a computer with no dpkg-deb: a .deb is an `ar` archive
    # with the files in a member called data.tar.something. Nothing else in it
    # is ever opened, which is the same promise as above.
    return unpack_deb_by_hand(path, into, progress)


def unpack_deb_by_hand(path, into, progress):
    if not shutil.which("ar"):
        progress.log("Neither dpkg-deb nor ar is on this computer.")
        return False
    work = tempfile.mkdtemp(prefix="aquarius-deb-")
    try:
        done = subprocess.run(["ar", "x", os.path.abspath(path)],
                              cwd=work, capture_output=True, text=True,
                              errors="replace")
        if done.returncode != 0:
            progress.log(done.stderr.strip())
            return False
        for entry in sorted(os.listdir(work)):
            if not entry.startswith("data.tar"):
                continue
            return unpack_tar(os.path.join(work, entry), into, progress)
        progress.log("There is no data.tar inside that package.")
        return False
    finally:
        shutil.rmtree(work, ignore_errors=True)


def unpack_appimage(path, into, progress):
    """The app's own unpack mode, never its self-mounting mode.

    ⚠️ THE SAME DECISION build_files/64-creator-apps.sh WRITES OUT AT LENGTH.
    Running an AppImage self-mounted needs FUSE present and working at the
    moment somebody clicks the icon, and it mounts the app in a way that forbids
    the one thing some apps need. `--appimage-extract` needs none of that and
    works anywhere, so we unpack once, here, and run ordinary files afterwards.
    """
    work = tempfile.mkdtemp(prefix="aquarius-appimage-")
    try:
        copy = os.path.join(work, "app.AppImage")
        shutil.copy2(path, copy)
        os.chmod(copy, 0o755)
        done = subprocess.run([copy, "--appimage-extract"], cwd=work,
                              capture_output=True, text=True, errors="replace",
                              timeout=1800)
        if done.returncode != 0:
            progress.log(done.stderr.strip() or done.stdout.strip())
            return False
        root = os.path.join(work, "squashfs-root")
        if not os.path.isdir(root):
            progress.log("The app unpacked into nothing.")
            return False
        for entry in os.listdir(root):
            shutil.move(os.path.join(root, entry), os.path.join(into, entry))
        return has_content(into)
    except (OSError, subprocess.SubprocessError) as exc:
        progress.log("Could not unpack the app: %s" % exc)
        return False
    finally:
        shutil.rmtree(work, ignore_errors=True)


def safe_members(names):
    """Every name that stays inside the folder we are unpacking into.

    ⚠️ A PATH LIKE `../../.bashrc` INSIDE AN ARCHIVE IS HOW A DOWNLOAD REWRITES
    YOUR HOME FOLDER. Python's own extractors have shipped this hole more than
    once. Anything that climbs out, and every absolute path, is dropped and
    counted rather than trusted.
    """
    kept = []
    dropped = 0
    for name in names:
        if os.path.isabs(name) or name.startswith("/"):
            dropped += 1
            continue
        parts = os.path.normpath(name).split(os.sep)
        if ".." in parts:
            dropped += 1
            continue
        kept.append(name)
    return kept, dropped


def unpack_tar(path, into, progress):
    try:
        with tarfile.open(path) as archive:
            members = archive.getmembers()
            names = [m.name for m in members]
            keep, dropped = safe_members(names)
            keep = set(keep)
            chosen = [m for m in members if m.name in keep
                      and not (m.issym() and os.path.isabs(m.linkname))]
            archive.extractall(into, members=chosen)
        if dropped:
            progress.log("%d item(s) in that archive pointed outside it and "
                         "were left out." % dropped)
    except (OSError, tarfile.TarError) as exc:
        progress.log("Could not open that archive: %s" % exc)
        return False
    return has_content(into)


def unpack_zip(path, into, progress):
    try:
        with zipfile.ZipFile(path) as archive:
            keep, dropped = safe_members(archive.namelist())
            archive.extractall(into, members=keep)
            # A zip file forgets which files were runnable; the mode is in the
            # archive but Python does not apply it. Put it back, or the program
            # inside is there and cannot be started.
            for info in archive.infolist():
                if info.filename not in keep:
                    continue
                mode = info.external_attr >> 16
                if mode & stat.S_IXUSR:
                    target = os.path.join(into, info.filename)
                    if os.path.isfile(target):
                        os.chmod(target, os.stat(target).st_mode | 0o755)
        if dropped:
            progress.log("%d item(s) in that archive pointed outside it and "
                         "were left out." % dropped)
    except (OSError, zipfile.BadZipFile) as exc:
        progress.log("Could not open that archive: %s" % exc)
        return False
    return has_content(into)


def has_content(root):
    for _, dirs, files in os.walk(root):
        if files or dirs:
            return True
    return False


# -----------------------------------------------------------------------------
# Does this want to change the operating system? — Route C detection
# -----------------------------------------------------------------------------
# ⚠️ ROUTE C IS OFF BY DECISION (Royce, 2026-09-08). Nothing is ever layered
# onto the operating system, so the only thing left to do is to RECOGNISE a
# package that wants to be, and say so plainly instead of installing half of it
# into a home folder where it can never work.
#
# These are the folders that only mean one thing: a system service, a kernel
# part, a rule the kernel reads when hardware appears, a login module, a
# printer driver.
OS_MARKERS = [
    "usr/lib/systemd/system",
    "usr/lib/systemd/user",
    "lib/systemd/system",
    "etc/systemd/system",
    "usr/lib/modules",
    "lib/modules",
    "etc/udev/rules.d",
    "usr/lib/udev/rules.d",
    "lib/udev/rules.d",
    "etc/pam.d",
    "usr/lib/security",
    "usr/lib/firmware",
    "lib/firmware",
    "usr/lib/cups/backend",
    "etc/sudoers.d",
]


def wants_the_os(root):
    """Which system folders this payload wanted to write into. [] is the good case."""
    found = []
    for marker in OS_MARKERS:
        candidate = os.path.join(root, marker)
        if os.path.isdir(candidate) and os.listdir(candidate):
            found.append("/" + marker)
    return found


# -----------------------------------------------------------------------------
# Does it actually run here? — the ldd pass
# -----------------------------------------------------------------------------
# The honest test for "is this self-contained". We ask the system's own linker
# what each program inside the package needs and whether it can find it. This is
# what catches a package built for another Linux that expects libraries this one
# does not have — before it is installed, rather than as a dead icon afterwards.
def elf_files(root, limit=400):
    """Every ELF program and library in the payload, biggest first."""
    found = []
    for base, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as handle:
                    if handle.read(4) != b"\x7fELF":
                        continue
                found.append((os.path.getsize(path), path))
            except OSError:
                continue
            if len(found) >= limit:
                break
    found.sort(reverse=True)
    return [path for _size, path in found]


def missing_libraries(root, progress=None, limit=60):
    """The libraries this payload needs and this computer does not have.

    An empty list means every program inside it resolves — which is what Route A
    is allowed to install. Anything else is the honest stop.
    """
    if not shutil.which("ldd"):
        if progress:
            progress.log("ldd is missing, so nothing could be checked.")
        return []
    missing = {}
    for path in elf_files(root)[:limit]:
        try:
            done = subprocess.run(["ldd", path], capture_output=True, text=True,
                                  timeout=30, errors="replace",
                                  env=dict(os.environ, LC_ALL="C"))
        except (OSError, subprocess.SubprocessError):
            continue
        for raw in done.stdout.splitlines():
            if "not found" not in raw:
                continue
            name = raw.strip().split()[0]
            missing.setdefault(name, os.path.relpath(path, root))
    return sorted(missing.items())


# =============================================================================
# THE MENU ENTRY — our Name, a real Icon, the window class, and no stray Path
# =============================================================================
# ⚠️ THESE ARE THE FOUR RULES /usr/libexec/aquarius-resolve-entry WAS WRITTEN
#    FOR, AND THEY COST A WEEK ON THE BENCH. An entry with the wrong window
#    class shows a running app as a second, nameless icon in the dock. An entry
#    with a `Path=` naming a folder this computer does not have makes the
#    desktop refuse to start the app AT ALL, silently, with nothing in any log a
#    person would look at. Everything unpacked here has both faults by default,
#    because it was built for a computer where /opt/<app> exists.
DESKTOP_SEARCH = [
    "usr/share/applications",
    "share/applications",
    "usr/local/share/applications",
    ".",
]


def find_desktop_entries(root):
    """Every menu entry inside a payload, best candidate first."""
    found = []
    for folder in DESKTOP_SEARCH:
        base = os.path.join(root, folder)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if name.endswith(".desktop"):
                found.append(os.path.join(base, name))
    if found:
        return found
    for base, _dirs, files in os.walk(root):
        for name in sorted(files):
            if name.endswith(".desktop"):
                found.append(os.path.join(base, name))
    return found


def read_entry(path):
    """A .desktop file as a plain dictionary of its [Desktop Entry] section."""
    values = {}
    section = ""
    try:
        with open(path, "r", errors="replace") as handle:
            for raw in handle:
                line = raw.strip()
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                    continue
                if section != "Desktop Entry":
                    continue
                key, sep, value = line.partition("=")
                if sep and key and not key.startswith("#"):
                    values.setdefault(key.strip(), value.strip())
    except OSError:
        pass
    return values


def exec_program(exec_line):
    """The program out of an Exec= line, without its arguments or field codes.

    ⚠️ AN Exec LINE DOES NOT ALWAYS START WITH THE PROGRAM. A great many real
    ones read `env SOMETHING=1 /opt/app/app`, because that is how an app author
    sets a variable it needs. Taking the first word would give "env", the entry
    would name a program that is not in the package, and the app would be
    treated as having no runnable program at all.
    """
    if not exec_line:
        return ""
    for part in exec_line.split():
        if part.startswith("%"):
            continue
        if part in ("env", "/usr/bin/env", "/bin/env"):
            continue
        if "=" in part and not part.startswith("/"):
            continue
        return part.strip('"')
    return ""


def exec_arguments(exec_line):
    """Everything after the program on an Exec= line, kept exactly as it was."""
    program = exec_program(exec_line)
    if not program:
        return ""
    index = exec_line.find(program)
    return exec_line[index + len(program):].strip()


def pick_entry(root):
    """The one menu entry that is the app, and what it says.

    "The app" is the entry whose Exec names a program that really exists inside
    the payload. An entry naming something that is not there is upstream's own
    leftovers and installing it would give somebody an icon that does nothing.
    """
    best = None
    for path in find_desktop_entries(root):
        values = read_entry(path)
        if values.get("NoDisplay", "").lower() == "true":
            continue
        if values.get("Type", "Application") != "Application":
            continue
        program = exec_program(values.get("Exec", ""))
        target = inside(root, program)
        if target and os.path.isfile(target):
            return path, values, target
        if best is None:
            best = (path, values, None)
    return best if best else (None, {}, None)


def inside(root, absolute):
    """An absolute path from inside a package, as it will be after unpacking."""
    if not absolute:
        return ""
    if not absolute.startswith("/"):
        return ""
    return os.path.join(root, absolute.lstrip("/"))


def find_program(root, hint=""):
    """The runnable program in a payload that has no usable menu entry.

    Looks in the obvious places first, then anywhere, and prefers a name that
    matches whatever we already think the app is called.
    """
    candidates = []
    for base, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            if not os.access(path, os.X_OK):
                continue
            if name.endswith((".so", ".pak", ".dat", ".json", ".png", ".sh.in")):
                continue
            candidates.append(path)
    if not candidates:
        return ""
    apprun = [p for p in candidates if os.path.basename(p) == "AppRun"]
    if apprun:
        return apprun[0]
    if hint:
        named = [p for p in candidates
                 if os.path.basename(p).lower() == hint.lower()]
        if named:
            return named[0]
    binish = [p for p in candidates
              if os.sep + "bin" + os.sep in p or os.sep + "opt" + os.sep in p]
    pool = binish or candidates
    pool.sort(key=lambda p: (len(p.split(os.sep)), len(p)))
    return pool[0]


def safe_name(text, fallback="app"):
    """A name safe to use as a folder, a file and an icon name."""
    text = (text or "").strip().lower()
    text = re.sub(r"[^a-z0-9._-]+", "-", text).strip("-._")
    text = re.sub(r"-{2,}", "-", text)
    return text or fallback


def write_entry(values, program, arguments, name, icon_name, out_path):
    """Write OUR menu entry for an app that has just landed in a home folder.

    Every key here is either read out of the app's own entry or decided by the
    four rules above. Nothing is guessed at, and a key we cannot answer for is
    simply not written — a menu entry with a missing line behaves; a menu entry
    with a wrong line does not.
    """
    exec_line = shell_quote(program)
    if arguments:
        exec_line += " " + arguments

    lines = [
        "[Desktop Entry]",
        "Type=Application",
        "Version=1.0",
        "Name=%s" % name,
    ]
    for key in ("GenericName", "Comment"):
        if values.get(key):
            lines.append("%s=%s" % (key, values[key]))
    lines.append("Exec=%s" % exec_line)
    lines.append("TryExec=%s" % program)
    if icon_name:
        lines.append("Icon=%s" % icon_name)
    lines.append("Terminal=%s" % values.get("Terminal", "false"))
    lines.append("StartupNotify=true")

    # ⚠️ THE WINDOW CLASS IS READ OUT OF THE APP, NEVER GUESSED. It is the key
    # that answers "when this window appears, which icon does it belong to?" —
    # get it wrong and the dock shows a second, nameless icon beside the one
    # that was clicked.
    wmclass = values.get("StartupWMClass")
    if not wmclass and values.get("Exec"):
        wmclass = os.path.basename(exec_program(values["Exec"]))
    if wmclass:
        lines.append("StartupWMClass=%s" % wmclass)

    categories = values.get("Categories", "")
    if categories and not categories.endswith(";"):
        categories += ";"
    lines.append("Categories=%s" % (categories or "Utility;"))
    if values.get("Keywords"):
        lines.append("Keywords=%s" % values["Keywords"])
    if values.get("MimeType"):
        lines.append("MimeType=%s" % values["MimeType"])

    # ⚠️ `Path=` IS DROPPED WHEN IT NAMES A FOLDER THIS COMPUTER DOES NOT HAVE,
    # and that is the 2026-09-09 bench fault written down in
    # /usr/libexec/aquarius-resolve-entry. The desktop steps into that folder
    # BEFORE it starts anything, so a folder it cannot enter means it refuses to
    # start the app at all, with no error anywhere. Every package unpacked into
    # a home folder carries one of these, because it was written for a computer
    # where /opt/<app> exists.
    path_value = values.get("Path", "")
    if path_value and os.path.isdir(path_value):
        lines.append("Path=%s" % path_value)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    os.chmod(out_path, 0o644)
    return out_path


def shell_quote(path):
    """A path as a .desktop Exec= line wants it."""
    if re.search(r"[\s\"'\\]", path):
        return '"%s"' % path.replace("\\", "\\\\").replace('"', '\\"')
    return path


# -----------------------------------------------------------------------------
# The icon
# -----------------------------------------------------------------------------
def install_icon(root, values, name, into=None):
    """Put the app's own icon where the desktop looks for it.

    Copying the app's whole icon theme across is better than picking one file
    and guessing at its size: the desktop then has a small icon for the dock and
    a large one for the app grid, exactly as the app's own author intended.
    """
    into = into or icon_root()
    icon_value = values.get("Icon", "")
    copied = 0

    if icon_value.startswith("/"):
        source = inside(root, icon_value)
        if source and os.path.isfile(source):
            copied += place_icon(source, name, into)
            return name if copied else ""

    for base in ("usr/share/icons/hicolor", "share/icons/hicolor",
                 "usr/local/share/icons/hicolor"):
        tree = os.path.join(root, base)
        if not os.path.isdir(tree):
            continue
        for folder, _dirs, files in os.walk(tree):
            for filename in files:
                stem, dot, ext = filename.rpartition(".")
                if not dot or ext.lower() not in ("png", "svg"):
                    continue
                if icon_value and stem != icon_value:
                    continue
                relative = os.path.relpath(folder, tree)
                destination = os.path.join(into, relative)
                os.makedirs(destination, exist_ok=True)
                shutil.copyfile(os.path.join(folder, filename),
                                os.path.join(destination, "%s.%s" % (name, ext)))
                copied += 1
        if copied:
            return name

    # No icon theme inside it. Fall back to a loose picture at the top level —
    # which is what an AppImage carries — and read its real width out of the
    # file, because an icon filed under the wrong size is drawn blurry and
    # nobody can see why.
    for candidate in (icon_value + ".png", icon_value + ".svg",
                      ".DirIcon", "icon.png", "logo.png"):
        source = os.path.join(root, candidate)
        if candidate and os.path.isfile(source):
            copied += place_icon(source, name, into)
            if copied:
                return name
    return ""


def place_icon(source, name, into):
    extension = source.rsplit(".", 1)[-1].lower()
    if extension == "svg":
        destination = os.path.join(into, "scalable", "apps")
    else:
        width = png_width(source)
        destination = os.path.join(into, "%dx%d" % (width, width), "apps")
    os.makedirs(destination, exist_ok=True)
    shutil.copyfile(source, os.path.join(destination, "%s.%s" % (name, extension)))
    return 1


def png_width(path):
    """Bytes 17 to 20 of any PNG are its width, big-endian. That is the format."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            width = int.from_bytes(head[16:20], "big")
            if 16 <= width <= 1024:
                return width
    except OSError:
        pass
    return 256


# =============================================================================
# THE REGISTRY — one note per app, so the reverse of an install is never a guess
# =============================================================================
# Every route ends here, which is what makes "Installed apps" one list whatever
# a thing came from, and what makes Remove exact rather than a search for files
# that look related.
class Record:
    FIELDS = ("id", "name", "route", "kind", "version", "source", "source_sha256",
              "install_path", "entry_path", "icon_name", "data_dirs",
              "update_feed", "installed_on")

    def __init__(self, app_id, **kw):
        self.id = app_id
        for field in self.FIELDS[1:]:
            setattr(self, field, kw.get(field, ""))
        self.log = list(kw.get("log", []))

    def path(self):
        return os.path.join(registry_dir(), "%s.ini" % self.id)

    def note(self, what):
        self.log.append("%s %s" % (now(), what))

    def save(self):
        parser = configparser.RawConfigParser()
        parser.add_section("app")
        for field in self.FIELDS:
            parser.set("app", field, str(getattr(self, field) or ""))
        parser.add_section("log")
        for number, line in enumerate(self.log, start=1):
            parser.set("log", str(number), line)
        os.makedirs(registry_dir(), exist_ok=True)
        with open(self.path(), "w") as handle:
            parser.write(handle)
        return self.path()

    @classmethod
    def load(cls, app_id):
        path = os.path.join(registry_dir(), "%s.ini" % app_id)
        if not os.path.isfile(path):
            return None
        parser = configparser.RawConfigParser()
        try:
            parser.read(path)
        except configparser.Error:
            return None
        if not parser.has_section("app"):
            return None
        values = dict(parser.items("app"))
        record = cls(values.get("id", app_id))
        for field in cls.FIELDS[1:]:
            setattr(record, field, values.get(field, ""))
        if parser.has_section("log"):
            record.log = [value for _key, value in sorted(
                parser.items("log"), key=lambda item: int_or_zero(item[0]))]
        return record


def int_or_zero(text):
    try:
        return int(text)
    except (TypeError, ValueError):
        return 0


def now():
    return datetime.datetime.now().replace(microsecond=0).isoformat()


def registry_ids():
    folder = registry_dir()
    if not os.path.isdir(folder):
        return []
    return sorted(name[:-4] for name in os.listdir(folder)
                  if name.endswith(".ini"))


def registry_records():
    records = []
    for app_id in registry_ids():
        record = Record.load(app_id)
        if record:
            records.append(record)
    return records


# =============================================================================
# INSTALLING — Route A and the home-folder routes, which are the same act
# =============================================================================
class Result:
    def __init__(self, ok, message="", record=None, detail=""):
        self.ok = ok
        self.message = message
        self.record = record
        self.detail = detail


def sha256(path):
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError:
        return ""
    return digest.hexdigest()


def install(verdict, progress=None, update_of=None):
    """Land one sorted file on this computer. The whole of Routes A and home."""
    progress = progress or Progress()

    if verdict.route == ROUTE_REFUSE:
        progress.fail(verdict.message)
        return Result(False, verdict.message)
    if refuse_root() and verdict.route != ROUTE_FLATPAK:
        progress.fail(ROOT_REFUSAL)
        return Result(False, ROOT_REFUSAL)
    if verdict.route == ROUTE_FLATPAK:
        # The one route this file does not do itself: it belongs to the existing
        # privileged helper, behind one pkexec prompt. `flatpak_argv()` builds
        # the command; the window and `aq` run it.
        message = "A Flatpak is installed by the app helper, not from here."
        progress.fail(message)
        return Result(False, message)

    total = 6
    work = tempfile.mkdtemp(prefix="aquarius-installer-")
    try:
        # --- 1. open it ------------------------------------------------------
        progress.step(1, total, "Opening %s" % verdict.name)
        payload = os.path.join(work, "payload")
        if not unpack(verdict.path, verdict.kind, payload, progress):
            why = "%s could not open that file." % OS_NAME
            progress.failed(verdict.name, why)
            return Result(False, why)
        progress.percent(20)

        # --- 2. does it want the operating system? ---------------------------
        progress.step(2, total, "Checking what it would change")
        wanted = wants_the_os(payload)
        if wanted:
            progress.log("It wanted to write into: %s" % ", ".join(wanted))
            progress.failed(verdict.name, SAY["os"])
            return Result(False, SAY["os"], detail=", ".join(wanted))
        progress.percent(35)

        # --- 3. does it run here? --------------------------------------------
        progress.step(3, total, "Checking it runs on this computer")
        missing = missing_libraries(payload, progress)
        if missing:
            for library, where in missing[:8]:
                progress.log("%s needs %s, which is not here." % (where, library))
            progress.failed(verdict.name, SAY["missing_parts"])
            return Result(False, SAY["missing_parts"],
                          detail=", ".join(name for name, _ in missing))
        progress.percent(50)

        # --- 4. what is it called, and what starts it? -----------------------
        progress.step(4, total, "Working out what it is called")
        entry_path, values, program = pick_entry(payload)
        name = values.get("Name") or verdict.name
        short = safe_name(values.get("Icon") or
                          (os.path.basename(entry_path)[:-8] if entry_path else "")
                          or name)
        if update_of:
            short = update_of
        version = verdict.version or values.get("X-AppImage-Version") or "1"
        version = safe_name(version, "1")
        progress.percent(60)

        # --- 5. move it into place, and only then move the link --------------
        progress.step(5, total, "Putting it into your apps")
        target = os.path.join(versions_root(), short, version)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        partial = target + ".partial"
        shutil.rmtree(partial, ignore_errors=True)
        shutil.rmtree(target, ignore_errors=True)
        normalise_permissions(payload)
        shutil.move(payload, partial)
        os.rename(partial, target)

        # ⚠️ THE LINK MOVES LAST, AND IT IS THE ONLY MOMENT ANYTHING VISIBLE
        #    CHANGES. Everything above wrote into a folder nothing points at, so
        #    a failure anywhere up to here leaves the app you already had
        #    exactly as it was.
        link = os.path.join(app_root(), short)
        os.makedirs(app_root(), exist_ok=True)
        if os.path.islink(link) or os.path.exists(link):
            try:
                os.unlink(link)
            except OSError:
                shutil.rmtree(link, ignore_errors=True)
        os.symlink(os.path.join("versions", short, version), link)

        # The program was found inside the folder we have just moved, so its
        # path has to be re-based onto where that folder landed.
        if program:
            program = os.path.join(target, os.path.relpath(program, payload))
        else:
            program = find_program(target, short)
        if not program or not os.path.isfile(program):
            why = "There is no program inside that file to start."
            progress.failed(verdict.name, why)
            return Result(False, why)
        os.chmod(program, os.stat(program).st_mode | 0o755)

        icon_name = install_icon(target, values, short)
        entry_out = os.path.join(desktop_dir(), "%s.desktop" % short)
        write_entry(values, program, exec_arguments(values.get("Exec", "")),
                    name, icon_name, entry_out)
        refresh_desktop_database()
        progress.percent(85)

        # --- 6. ASK, do not assume -------------------------------------------
        progress.step(6, total, "Checking it is really there")
        if not (os.path.isfile(program) and os.path.isfile(entry_out)):
            why = "It unpacked but is not where it should be."
            progress.failed(verdict.name, why)
            return Result(False, why)

        # ⚠️ DROPPING A NEWER FILE ON AN APP YOU ALREADY HAVE IS AN UPDATE, NOT A
        #    SECOND COPY. Nothing special makes that true: the id comes out of
        #    the payload itself, so the same app lands in the same place under a
        #    new version number, the link moves, and the old version is thrown
        #    away. The only thing worth doing by hand is calling it what it is
        #    in the log — "installed" twice would make the log a liar.
        record = Record.load(short)
        was_here = record is not None and bool(record.install_path)
        record = record or Record(short)
        record.name = name
        record.route = verdict.route
        record.kind = verdict.kind
        record.version = version
        record.source = verdict.path
        record.source_sha256 = sha256(verdict.path)
        record.install_path = target
        record.entry_path = entry_out
        record.icon_name = icon_name
        record.data_dirs = ",".join(guess_data_dirs(short, values))
        record.update_feed = update_feed(target, values)
        record.installed_on = now()
        record.note("%s %s from %s" %
                    ("updated to" if (was_here or update_of) else "installed",
                     version, verdict.path))
        record.save()

        tidy_old_versions(short, target, progress)
        progress.percent(100)
        progress.ok(short)
        progress.done()
        return Result(True, "%s is installed." % name, record=record)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def normalise_permissions(root):
    """Make every folder enterable and every file readable by its owner.

    ⚠️ THIS IS THE WHOLE OF THE BUG OF 2026-08-28, written down again because it
    is the same extractor. An AppImage's own extractor made all 3,097 of one
    app's folders mode 0700 — and a folder you cannot enter makes every file
    inside it read as missing, so the app appeared in the grid and clicking it
    did absolutely nothing.
    """
    for base, dirs, files in os.walk(root):
        for name in dirs:
            path = os.path.join(base, name)
            if os.path.islink(path):
                continue
            try:
                os.chmod(path, os.stat(path).st_mode | 0o700)
            except OSError:
                pass
        for name in files:
            path = os.path.join(base, name)
            if os.path.islink(path):
                continue
            try:
                mode = os.stat(path).st_mode
                os.chmod(path, mode | (0o700 if mode & stat.S_IXUSR else 0o600))
            except OSError:
                pass


def guess_data_dirs(short, values):
    """Where this app's own settings live, as far as anybody can know.

    Written down at install so that Remove's tick box can show real sizes rather
    than hunting for folders that look related afterwards. Only folders named
    after the app itself are ever listed — never a folder somebody's documents
    could be in.
    """
    names = {short}
    for key in ("Icon", "StartupWMClass"):
        if values.get(key):
            names.add(safe_name(values[key]))
    dirs = []
    for name in sorted(names):
        for base in (os.path.join(home(), ".config"),
                     os.path.join(home(), ".local", "share"),
                     os.path.join(home(), ".cache")):
            dirs.append(os.path.join(base, name))
    return dirs


def update_feed(root, values):
    """The app's own "where to look for a newer one", when it declares one.

    ⚠️ RECORDED, NOT ACTED ON (v1). Many AppImages carry a zsync feed and some
    packages name a vendor repository. Writing it down now means the day the
    updater learns to use it, every app already installed is ready. Until then
    the Installed tab simply says "drop the new file on this window to update".
    """
    for key in ("X-AppImage-UpdateInformation", "X-Update-Feed"):
        if values.get(key):
            return values[key]
    candidate = os.path.join(root, "update_info")
    if os.path.isfile(candidate):
        try:
            with open(candidate, "r", errors="replace") as handle:
                return handle.read(500).strip()
        except OSError:
            pass
    return ""


def tidy_old_versions(short, keep, progress):
    """Throw away versions nothing points at. Each one can be gigabytes."""
    folder = os.path.join(versions_root(), short)
    if not os.path.isdir(folder):
        return
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if path == keep or not os.path.isdir(path):
            continue
        shutil.rmtree(path, ignore_errors=True)
        progress.log("Removed the old copy, version %s." % name)


def refresh_desktop_database():
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", desktop_dir()],
                       capture_output=True)


# =============================================================================
# REMOVE — the exact reverse of how it landed, and never a guess
# =============================================================================
def directory_size(path):
    total = 0
    for base, _dirs, files in os.walk(path):
        for name in files:
            candidate = os.path.join(base, name)
            if os.path.islink(candidate):
                continue
            try:
                total += os.path.getsize(candidate)
            except OSError:
                pass
    return total


def human_size(total):
    """Bytes as a person would say them. The same words the chooser uses."""
    if total >= 1000 ** 3:
        return "%.1f GB" % (total / 1000.0 ** 3)
    if total >= 1000 ** 2:
        return "%d MB" % round(total / 1000.0 ** 2)
    if total >= 1000:
        return "%d kB" % round(total / 1000.0)
    return "%d bytes" % total


def removal_plan(app_id):
    """What Remove would free, split into the app and its settings.

    Two numbers, because they are two decisions: the app always goes, and its
    settings only go if the person ticks the box.
    """
    record = Record.load(app_id)
    if record is None:
        return None
    app_bytes = directory_size(record.install_path) \
        if record.install_path and os.path.isdir(record.install_path) else 0
    data = []
    for folder in [d for d in (record.data_dirs or "").split(",") if d]:
        if os.path.isdir(folder):
            data.append((folder, directory_size(folder)))
    return {"record": record, "app_bytes": app_bytes, "data": data,
            "data_bytes": sum(size for _folder, size in data)}


def remove(app_id, with_data=False, progress=None):
    """Take a home-folder app away again. No password, and nothing else touched.

    ⚠️ IT NEVER DELETES A FILE THE APP DID NOT CREATE, AND NEVER TOUCHES THE
    OPERATING SYSTEM. Nothing this window installed is in the image, so there is
    nothing in the image to remove. Files the person made WITH the app —
    projects, exports, documents — are never in scope, tick box or no tick box.
    """
    progress = progress or Progress()
    if refuse_root():
        progress.fail(ROOT_REFUSAL)
        return Result(False, ROOT_REFUSAL)

    record = Record.load(app_id)
    if record is None:
        why = "%s has no record of that app." % OS_NAME
        progress.fail(why)
        return Result(False, why)

    freed = 0
    if record.install_path and os.path.isdir(record.install_path):
        freed += directory_size(record.install_path)
        shutil.rmtree(record.install_path, ignore_errors=True)
    parent = os.path.dirname(record.install_path or "")
    if parent and os.path.isdir(parent) and not os.listdir(parent):
        shutil.rmtree(parent, ignore_errors=True)

    link = os.path.join(app_root(), app_id)
    if os.path.islink(link) or os.path.exists(link):
        try:
            os.unlink(link)
        except OSError:
            shutil.rmtree(link, ignore_errors=True)

    if record.entry_path and os.path.isfile(record.entry_path):
        os.remove(record.entry_path)
    if record.icon_name:
        remove_icons(record.icon_name)
    refresh_desktop_database()

    if with_data:
        for folder in [d for d in (record.data_dirs or "").split(",") if d]:
            if os.path.isdir(folder):
                freed += directory_size(folder)
                shutil.rmtree(folder, ignore_errors=True)

    record.install_path = ""
    record.entry_path = ""
    record.note("removed%s" % (", with its settings" if with_data else ""))
    record.save()

    progress.ok(app_id)
    progress.done()
    return Result(True, "%s has been removed. %s freed." %
                  (record.name or app_id, human_size(freed)), record=record)


def remove_icons(name):
    root = icon_root()
    if not os.path.isdir(root):
        return
    for base, _dirs, files in os.walk(root):
        for filename in files:
            stem, dot, ext = filename.rpartition(".")
            if dot and stem == name and ext.lower() in ("png", "svg"):
                try:
                    os.remove(os.path.join(base, filename))
                except OSError:
                    pass


# =============================================================================
# WHAT IS ON THIS COMPUTER — the registry, and Flatpak asked live
# =============================================================================
# ⚠️ APPS THIS WINDOW DID NOT INSTALL SHOW UP TOO, AND THAT IS THE POINT. A
#    Flatpak somebody added from a terminal is still an app on this computer, so
#    the Flatpak list is READ LIVE rather than only remembered. One place to
#    remove anything.
class Row:
    def __init__(self, app_id, name, version, route, **kw):
        self.id = app_id
        self.name = name
        self.version = version
        self.route = route
        self.removable = kw.get("removable", True)
        self.note = kw.get("note", "")
        self.update_to = kw.get("update_to", "")
        self.record = kw.get("record")

    def __repr__(self):
        return "<Row %s %s %s>" % (self.route, self.id, self.version)


# The two apps that came with the operating system and are not this window's to
# remove. Said in the row rather than hidden, because "why is Aquarius Writer
# not in the list?" is a worse question than a row that explains itself.
PART_OF_OS = {
    "aquarius-writer": "part of %s" % OS_NAME,
    "firefox": "part of %s" % OS_NAME,
    "org.mozilla.firefox": "part of %s" % OS_NAME,
}
UPDATES_WITH_OS = {
    "aquarius-editor": "updates with %s" % OS_NAME,
    "os.aquarius.editor": "updates with %s" % OS_NAME,
}


def flatpak_rows():
    out = run_text(["flatpak", "list", "--app",
                    "--columns=application,name,version"], timeout=40)
    rows = []
    for raw in (out or "").splitlines():
        fields = raw.split("\t")
        if not fields or not fields[0].strip():
            continue
        app_id = fields[0].strip()
        name = fields[1].strip() if len(fields) > 1 and fields[1].strip() else app_id
        version = fields[2].strip() if len(fields) > 2 else ""
        rows.append(Row(app_id, name, version, ROUTE_FLATPAK))
    return rows


def home_rows():
    rows = []
    for record in registry_records():
        if not record.install_path or not os.path.isdir(record.install_path):
            continue
        note = PART_OF_OS.get(record.id) or UPDATES_WITH_OS.get(record.id, "")
        rows.append(Row(record.id, record.name or record.id, record.version,
                        record.route or ROUTE_APPIMAGE,
                        removable=not PART_OF_OS.get(record.id),
                        note=note, record=record))
    return rows


def appimage_installer_rows():
    """The apps the OS's own home-folder installer put here (Aquarius Editor).

    Asked of that installer rather than by looking at a folder, so where it puts
    things stays its own business and the two can never disagree.
    """
    if not os.access(APPIMAGE_INSTALLER, os.X_OK) \
            or not os.access(CATALOG_CLI, os.X_OK):
        return []
    ids = (run_text([CATALOG_CLI, "--list-appimage"], timeout=20) or "").split()
    if not ids:
        return []
    out = run_text([APPIMAGE_INSTALLER, "--status"] + ids, timeout=25)
    rows = []
    current = {}
    for raw in (out or "").splitlines():
        key, sep, value = raw.partition("=")
        if not sep:
            continue
        if key == "id":
            current = {"id": value.strip()}
        else:
            current[key] = value.strip()
        if key == "path" or (key == "offered" and current.get("installed")):
            if current.get("installed"):
                rows.append(Row(current["id"], current.get("name", current["id"]),
                                current["installed"], ROUTE_APPIMAGE,
                                removable=False,
                                note=UPDATES_WITH_OS.get(current["id"],
                                                         "updates with %s" % OS_NAME)))
                current = {}
    return rows


def installed_rows():
    """Everything on this computer, from every route, in one list."""
    rows = {}
    for row in home_rows() + appimage_installer_rows() + flatpak_rows():
        rows.setdefault(row.id, row)
    return sorted(rows.values(), key=lambda row: (row.name or row.id).lower())


# =============================================================================
# UPDATES
# =============================================================================
def flatpak_updates():
    """The Flatpaks with something newer waiting. [] when there is nothing."""
    out = run_text(["flatpak", "remote-ls", "--updates", "--app",
                    "--columns=application"], timeout=90)
    return [line.strip() for line in (out or "").splitlines() if line.strip()]


def flatpak_argv(action, refs, progress_fd=None, cancel_file=None,
                 dry_run=False, privileged=True):
    """The command line for the privileged Flatpak helper.

    Built here so the window, `aq apps` and the tests all ask for the same thing.
    `pkexec` is on the front and `sudo` never is: pkexec is the desktop's own
    permission prompt and it asks ONCE, for the whole run.
    """
    argv = []
    if privileged and not dry_run:
        argv.append("pkexec")
    argv.append(FLATPAK_HELPER)
    argv += ["--mode", action]
    if progress_fd is not None:
        argv += ["--progress-fd", str(progress_fd)]
    if cancel_file:
        argv += ["--cancel-file", cancel_file]
    if dry_run:
        argv.append("--dry-run")
    argv += list(refs)
    return argv


def update_plan():
    """What Update All would do: a list of rows and what can be done about each."""
    plan = {"flatpak": flatpak_updates(), "home": [], "os": []}
    for row in home_rows():
        if row.note:
            plan["os"].append(row)
        else:
            plan["home"].append(row)
    return plan


# =============================================================================
# SEARCH — one bar, three labelled groups, in this order
# =============================================================================
def catalog_entries():
    """What AquariusOS suggests: the ONE catalogue, read the one way.

    ⚠️ NEVER A SECOND LIST. The first-login chooser and this search bar are two
    faces of the same catalogue; a copy of it in here would be the thing
    docs/restart/creator-apps.md forbids in as many words.
    """
    out = run_text([CATALOG_CLI, "--catalog"], timeout=25)
    entries = []
    for raw in (out or "").splitlines():
        fields = raw.split("\t")
        if len(fields) < 9:
            continue
        named = {}
        for field in fields[4:]:
            key, sep, value = field.partition(":")
            if sep:
                named[key] = value
        if named.get("runtime") == "yes":
            continue
        entries.append({"id": fields[0], "name": fields[1],
                        "description": fields[2], "category": fields[3],
                        "branch": named.get("branch", "stable"),
                        "type": named.get("type", "flatpak")})
    return entries


# Things `flatpak search` finds that are not apps a person installs. A plug-in
# arrives with the app it belongs to; a runtime and a theme are pieces other
# things are built out of. Offering any of them as "an app you could install"
# is the same mistake the chooser's runtime:yes rule exists to avoid.
NOT_AN_APP = ("org.freedesktop.Platform", "org.freedesktop.Sdk",
              "org.gnome.Platform", "org.gnome.Sdk", "org.kde.Platform",
              "org.kde.Sdk", "org.gtk.Gtk3theme.", "org.gtk.Gtk4theme.",
              "org.winehq.Wine.")


def flathub_search(term):
    """Flathub, searched through the copy of its index Flatpak already keeps.

    ⚠️ THE SAME APP COMES BACK MORE THAN ONCE, and that is not a bug in Flatpak.
    It lists one line per branch and per remote, so an app on two branches is two
    lines with the same id. A search bar that shows "OBS VkCapture tools" five
    times looks broken, so the first line for each id wins and the rest are
    dropped.
    """
    if not term.strip():
        return []
    out = run_text(["flatpak", "search", "--columns=application,name,description",
                    term], timeout=40)
    results = []
    seen = set()
    for raw in (out or "").splitlines():
        fields = raw.split("\t")
        if len(fields) < 2 or not fields[0].strip():
            continue
        app_id = fields[0].strip()
        if app_id in seen:
            continue
        if ".Plugin." in app_id or app_id.startswith(NOT_AN_APP):
            continue
        seen.add(app_id)
        results.append({"id": app_id, "name": fields[1].strip(),
                        "description": fields[2].strip() if len(fields) > 2 else ""})
    return results


def search(term):
    """The three groups, in the order the window shows them."""
    lowered = term.strip().lower()
    here = [row for row in installed_rows()
            if not lowered or lowered in (row.name or "").lower()
            or lowered in row.id.lower()]
    suggested = [entry for entry in catalog_entries()
                 if not lowered or lowered in entry["name"].lower()
                 or lowered in entry["description"].lower()
                 or lowered in entry["id"].lower()]
    known = {row.id for row in here}
    suggested = [entry for entry in suggested if entry["id"] not in known]
    on_flathub = []
    if lowered:
        seen = known | {entry["id"] for entry in suggested}
        on_flathub = [hit for hit in flathub_search(lowered)
                      if hit["id"] not in seen]
    return {"here": here, "suggested": suggested, "flathub": on_flathub}


NOTHING_FOUND = ("Not on Flathub. If you have its Linux download, drop it here.")


# -----------------------------------------------------------------------------
# Pasting a link
# -----------------------------------------------------------------------------
LINK = re.compile(r"^https?://", re.I)
FLATHUB_PAGE = re.compile(r"^https?://(?:www\.)?flathub\.org/apps/(?:details/)?"
                          r"([A-Za-z0-9_.-]+)/?$", re.I)


def looks_like_link(text):
    return bool(LINK.match(text.strip()))


def flathub_page_id(text):
    match = FLATHUB_PAGE.match(text.strip())
    return match.group(1) if match else ""


def download(url, progress=None, into=None):
    """Fetch something a person pasted, into the download cache.

    The cache is a folder of ours in the home folder, so a file that arrived
    this way can be found again — which is what makes "reinstall the previous
    one" possible for an app that has no update feed.
    """
    progress = progress or Progress()
    into = into or cache_dir()
    os.makedirs(into, exist_ok=True)
    name = safe_name(os.path.basename(url.split("?")[0]), "download")
    target = os.path.join(into, name)
    if not shutil.which("curl"):
        progress.fail("This computer has no way to download that link.")
        return ""
    done = subprocess.run(
        ["curl", "-fL", "--retry", "3", "--retry-delay", "5",
         "--speed-limit", "1024", "--speed-time", "60",
         "--max-time", "3600", "-o", target, url],
        capture_output=True, text=True, errors="replace")
    if done.returncode != 0:
        progress.log(done.stderr.strip())
        progress.fail("That link could not be downloaded.")
        return ""
    return target
