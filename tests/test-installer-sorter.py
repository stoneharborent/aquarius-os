#!/usr/bin/env python3
# ==============================================================================
# Tests for the Aquarius Installer sorter, its routes and its registry
# ==============================================================================
# WHAT THIS IS FOR
# ------------------------------------------------------------------------------
# Aquarius Installer is the window that takes anything a person downloads — an
# .rpm, a .deb, an AppImage, a .flatpakref, a tarball with a program inside it —
# and lands it in their own apps. The person never chooses how; a sorter decides.
#
# ⚠️ A SORTER THAT GETS IT WRONG LOOKS EXACTLY LIKE A SORTER THAT GETS IT RIGHT.
# Every failure mode here is silent. A package that should have been refused
# installs into a home folder and leaves a dead icon. A menu entry with the
# wrong window class puts a second, nameless icon in the dock. A menu entry with
# a `Path=` naming a folder this computer does not have makes the desktop refuse
# to start the app AT ALL, with nothing in any log a person would ever read —
# that one cost a week on the bench in September 2026 and is the reason
# /usr/libexec/aquarius-resolve-entry exists.
#
# So this builds real files — a real .deb, a real archive, a payload that wants
# to be part of the operating system, a program that needs a library this
# computer does not have — really installs them into a throwaway home folder,
# and really reads back what happened.
#
# HOW TO RUN IT
# ------------------------------------------------------------------------------
#   ./tests/test-installer-sorter.py
#       tests the copy in this repo, under system_files/. This is what CI runs
#       BEFORE the twenty-minute build.
#
#   ./tests/test-installer-sorter.py /usr/lib/aquarius/python/aquarius_installer.py
#       tests the copy inside a finished image, which is the version that will
#       actually run on Royce's machine. build_files/65-installer.sh does this.
#
# It prints a line per check and exits non-zero if any of them is wrong.
#
# ⚠️ IT NEVER TOUCHES THE HOME FOLDER OF WHOEVER RUNS IT. Every test sets HOME
# to a temporary folder of its own first and deletes it afterwards.
# ==============================================================================

import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_MODULE = os.path.join(
    REPO, "system_files", "usr", "lib", "aquarius", "python",
    "aquarius_installer.py")

PASSED = 0
FAILED = 0
SKIPPED = 0


def ok(what):
    global PASSED
    PASSED += 1
    print("  OK    %s" % what)


def bad(what, detail=""):
    global FAILED
    FAILED += 1
    print("  FAIL  %s" % what)
    if detail:
        for line in str(detail).splitlines():
            print("        %s" % line)


def skip(what, why):
    global SKIPPED
    SKIPPED += 1
    print("  SKIP  %s — %s" % (what, why))


def check(condition, what, detail=""):
    if condition:
        ok(what)
    else:
        bad(what, detail)
    return bool(condition)


def heading(text):
    print()
    print("== %s ==" % text)


# ==============================================================================
# Load the decider, from wherever we were told
# ==============================================================================
def load(path):
    import importlib.util

    spec = importlib.util.spec_from_file_location("aquarius_installer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ==============================================================================
# The fixtures — built here, every time, so nothing is checked in and stale
# ==============================================================================
DESKTOP = """[Desktop Entry]
Type=Application
Name=Test App
GenericName=A Test
Comment=Something to install
Exec=/opt/{name}/{name} %U
Icon={name}
Terminal=false
StartupWMClass=TestAppWindow
Categories=Utility;Development
Path=/opt/{name}/
"""

# A PNG's first 24 bytes say what it is and how wide it is, and that is all the
# icon code ever reads. A real picture would prove nothing more.
PNG = (b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR"
       + (64).to_bytes(4, "big") + (64).to_bytes(4, "big"))


def build_payload(root, name="testapp", os_bits=False, elf=False,
                  entry=True, icon=True):
    """An app-shaped tree: a program, a menu entry, an icon.

    `os_bits` adds the folders that mean "this wants to be part of the
    operating system" — which is the one thing the installer must refuse.
    """
    binary = os.path.join(root, "opt", name, name)
    os.makedirs(os.path.dirname(binary), exist_ok=True)
    with open(binary, "wb") as handle:
        if elf:
            # An ELF header and nothing else. Enough for the ldd pass to find
            # the file and try to read it, which is all this fixture is for.
            handle.write(b"\x7fELF" + b"\x00" * 60)
        else:
            handle.write(b"#!/bin/sh\necho hello\n")
    os.chmod(binary, 0o755)

    if entry:
        path = os.path.join(root, "usr", "share", "applications",
                            "%s.desktop" % name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(DESKTOP.format(name=name))

    if icon:
        path = os.path.join(root, "usr", "share", "icons", "hicolor",
                            "64x64", "apps", "%s.png" % name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(PNG)

    if os_bits:
        for folder, filename, text in (
                (("usr", "lib", "systemd", "system"), "%s.service" % name,
                 "[Unit]\nDescription=no\n"),
                (("usr", "lib", "modules", "6.0.0", "extra"), "%s.ko" % name,
                 "not really a kernel module"),
                (("etc", "udev", "rules.d"), "99-%s.rules" % name,
                 'ACTION=="add"\n')):
            path = os.path.join(root, *folder)
            os.makedirs(path, exist_ok=True)
            with open(os.path.join(path, filename), "w") as handle:
                handle.write(text)
    return root


def make_tarball(path, **kw):
    work = tempfile.mkdtemp(prefix="aq-fixture-")
    try:
        build_payload(work, **kw)
        mode = "w:xz" if path.endswith((".xz", ".txz")) else "w:gz"
        with tarfile.open(path, mode) as archive:
            for name in sorted(os.listdir(work)):
                archive.add(os.path.join(work, name), arcname=name)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return path


def make_zip(path, **kw):
    work = tempfile.mkdtemp(prefix="aq-fixture-")
    try:
        build_payload(work, **kw)
        with zipfile.ZipFile(path, "w") as archive:
            for base, _dirs, files in os.walk(work):
                for filename in files:
                    full = os.path.join(base, filename)
                    archive.write(full, os.path.relpath(full, work))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return path


def make_deb(path, **kw):
    """A real .deb, built the way a .deb is built.

    ⚠️ TWO WAYS, ON PURPOSE. `dpkg-deb -b` is the real thing and is what the
    build machine and the finished image both have. `ar` plus two tarballs is
    what a .deb actually IS underneath, and it is the fallback for a machine
    with neither — which is also the fallback the installer itself carries, so
    testing through it is testing something real rather than a stunt.
    """
    work = tempfile.mkdtemp(prefix="aq-fixture-")
    try:
        build_payload(work, **kw)
        control = os.path.join(work, "DEBIAN")
        os.makedirs(control, exist_ok=True)
        with open(os.path.join(control, "control"), "w") as handle:
            handle.write("Package: testapp\nVersion: 1.2.3\n"
                         "Architecture: amd64\nMaintainer: A Person <a@b.c>\n"
                         "Description: a test\n")
        # ⚠️ A MAINTAINER SCRIPT, ON PURPOSE. If the installer ever ran one,
        # this would leave a file behind, and the test below looks for it. It is
        # the only way to PROVE "no scripts, ever" rather than assert it.
        with open(os.path.join(control, "postinst"), "w") as handle:
            handle.write("#!/bin/sh\ntouch %s/SCRIPT-RAN\n"
                         % os.path.dirname(path))
        os.chmod(os.path.join(control, "postinst"), 0o755)

        if shutil.which("dpkg-deb"):
            done = subprocess.run(["dpkg-deb", "--build", "--root-owner-group",
                                   work, path],
                                  capture_output=True, text=True)
            if done.returncode == 0:
                return path
        if not shutil.which("ar"):
            return ""
        stage = tempfile.mkdtemp(prefix="aq-deb-")
        try:
            with open(os.path.join(stage, "debian-binary"), "w") as handle:
                handle.write("2.0\n")
            with tarfile.open(os.path.join(stage, "control.tar.gz"), "w:gz") as a:
                a.add(os.path.join(work, "DEBIAN"), arcname=".")
            with tarfile.open(os.path.join(stage, "data.tar.gz"), "w:gz") as a:
                for name in sorted(os.listdir(work)):
                    if name == "DEBIAN":
                        continue
                    a.add(os.path.join(work, name), arcname="./" + name)
            done = subprocess.run(
                ["ar", "rc", os.path.abspath(path), "debian-binary",
                 "control.tar.gz", "data.tar.gz"], cwd=stage,
                capture_output=True, text=True)
            return path if done.returncode == 0 else ""
        finally:
            shutil.rmtree(stage, ignore_errors=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def make_rpm(path, **kw):
    """A real .rpm, if this machine can build one. "" if it cannot."""
    if not shutil.which("rpmbuild"):
        return ""
    work = tempfile.mkdtemp(prefix="aq-fixture-")
    try:
        build_payload(os.path.join(work, "root"), **kw)
        spec = os.path.join(work, "testapp.spec")
        with open(spec, "w") as handle:
            # ⚠️ Built by joining pieces, NOT with Python's % formatting: an
            # RPM spec is full of %-words (%description, %install, %files),
            # and Python's % operator applies to the WHOLE run of adjacent
            # string literals, so "%description" once became a "%d" directive
            # and this fixture crashed the CI job (2026-09-10) on the one
            # machine that had rpmbuild — this branch never runs where it
            # does not. The two %global lines switch off RPM's strip and
            # debuginfo passes, which would otherwise try to read the fake
            # binary in the payload as a real program.
            root = os.path.join(work, "root")
            handle.write(
                "%global debug_package %{nil}\n"
                "%global __os_install_post %{nil}\n"
                "Name: testapp\nVersion: 1.2.3\nRelease: 1\n"
                "Summary: a test\nLicense: MIT\nBuildArch: x86_64\n"
                "%description\na test\n"
                "%install\ncp -a " + root + "/. %{buildroot}/\n"
                "%files\n/opt/testapp\n/usr/share/applications\n"
                "/usr/share/icons\n")
        done = subprocess.run(
            ["rpmbuild", "-bb", "--define", "_topdir %s" % work,
             "--define", "_rpmdir %s" % work, spec],
            capture_output=True, text=True)
        if done.returncode != 0:
            return ""
        for base, _dirs, files in os.walk(work):
            for name in files:
                if name.endswith(".rpm"):
                    shutil.copyfile(os.path.join(base, name), path)
                    return path
        return ""
    finally:
        shutil.rmtree(work, ignore_errors=True)


def make_appimage_shaped(path):
    """A file whose first bytes say "AppImage" the way the format says so.

    Bytes 8 and 9 of an AppImage are the letters AI. That is the whole of the
    "AppImage magic", and it is what lets a file called `download` still be
    recognised.
    """
    with open(path, "wb") as handle:
        handle.write(b"\x7fELF\x02\x01\x01\x00AI\x02" + b"\x00" * 100)
    os.chmod(path, 0o755)
    return path


def make_escaping_tarball(path):
    """An archive with a path that climbs OUT of the folder it unpacks into.

    ⚠️ THIS IS HOW A DOWNLOAD REWRITES SOMEBODY'S HOME FOLDER, and Python's own
    extractors have shipped the hole more than once. The installer must drop
    every one of these and say how many it dropped.
    """
    work = tempfile.mkdtemp(prefix="aq-fixture-")
    try:
        build_payload(work)
        evil = os.path.join(work, "innocent")
        with open(evil, "w") as handle:
            handle.write("nope")
        with tarfile.open(path, "w:gz") as archive:
            for name in sorted(os.listdir(work)):
                archive.add(os.path.join(work, name), arcname=name)
            archive.add(evil, arcname="../../escaped")
            archive.add(evil, arcname="/absolutely/escaped")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return path


# ==============================================================================
# A throwaway home folder, and a stand-in for one command at a time
# ==============================================================================
class FakeHome:
    """Everything an install writes goes here, and here is deleted afterwards."""

    def __init__(self):
        self.path = None
        self.was = None

    def __enter__(self):
        self.path = tempfile.mkdtemp(prefix="aq-test-home-")
        self.was = os.environ.get("HOME")
        os.environ["HOME"] = self.path
        return self.path

    def __exit__(self, *_):
        if self.was is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = self.was
        shutil.rmtree(self.path, ignore_errors=True)


class StandIn:
    """Put a stand-in command at the front of PATH, for one test.

    The same trick the greeter, the guard and the USB4 tests use: the code under
    test really runs the command, and the command really answers — it is just
    not the real one. That is how a branch nobody can reproduce on a build
    machine gets executed anyway.
    """

    def __init__(self, name, script):
        self.name = name
        self.script = script
        self.folder = None
        self.was = None

    def __enter__(self):
        self.folder = tempfile.mkdtemp(prefix="aq-standin-")
        path = os.path.join(self.folder, self.name)
        with open(path, "w") as handle:
            handle.write(self.script)
        os.chmod(path, 0o755)
        self.was = os.environ.get("PATH", "")
        os.environ["PATH"] = self.folder + os.pathsep + self.was
        return self.folder

    def __exit__(self, *_):
        os.environ["PATH"] = self.was
        shutil.rmtree(self.folder, ignore_errors=True)


# ==============================================================================
# THE TESTS
# ==============================================================================
def test_sorter_by_name(core, work):
    heading("the sorter, by what a file is called")
    cases = [
        ("thing.flatpakref", core.ROUTE_FLATPAK),
        ("thing.flatpak", core.ROUTE_FLATPAK),
        ("Thing-1.2.3-x86_64.AppImage", core.ROUTE_APPIMAGE),
        ("thing.appimage", core.ROUTE_APPIMAGE),
        ("thing.rpm", core.ROUTE_PACKAGE),
        ("thing.deb", core.ROUTE_PACKAGE),
        ("thing.tar.gz", core.ROUTE_ARCHIVE),
        ("thing.tgz", core.ROUTE_ARCHIVE),
        ("thing.tar.xz", core.ROUTE_ARCHIVE),
        ("thing.zip", core.ROUTE_ARCHIVE),
        ("thing.run", core.ROUTE_REFUSE),
        ("thing.sh", core.ROUTE_REFUSE),
        ("thing.snap", core.ROUTE_REFUSE),
        ("thing.exe", core.ROUTE_REFUSE),
        ("thing.msi", core.ROUTE_REFUSE),
        ("thing.dmg", core.ROUTE_REFUSE),
        ("thing.pkg", core.ROUTE_REFUSE),
        ("thing.whatever", core.ROUTE_REFUSE),
    ]
    for name, want in cases:
        path = os.path.join(work, name)
        with open(path, "w") as handle:
            handle.write("x")
        verdict = core.sort_path(path)
        check(verdict.route == want,
              "%-28s -> %s" % (name, want),
              "got %s" % verdict.route)

    # ⚠️ THE ONE THAT MATTERS MOST IN THIS BLOCK. An .rpm and a .deb must take
    # the SAME route. "No conversion, ever" is not a comment somewhere; it is
    # the fact that there is only one thing either of them can do.
    rpm = core.sort_path(os.path.join(work, "thing.rpm"))
    deb = core.sort_path(os.path.join(work, "thing.deb"))
    check(rpm.route == deb.route,
          "an .rpm and a .deb take the same route — nothing is ever converted")


def test_sorter_by_content(core, work):
    heading("the sorter, by what is inside a file with no useful name")
    tarball = make_tarball(os.path.join(work, "download"))
    check(core.sort_path(tarball).route == core.ROUTE_ARCHIVE,
          "a file called 'download' that is really an archive is still an archive")

    appimage = make_appimage_shaped(os.path.join(work, "nameless"))
    check(core.sort_path(appimage).route == core.ROUTE_APPIMAGE,
          "a file with no ending at all that is really an AppImage is recognised")

    rpm_shaped = os.path.join(work, "mystery")
    with open(rpm_shaped, "wb") as handle:
        handle.write(b"\xed\xab\xee\xdb" + b"\x00" * 100)
    check(core.sort_path(rpm_shaped).route == core.ROUTE_PACKAGE,
          "and so is a package with its ending stripped off")

    # A real .deb with its ending taken off. This is the one the magic-bytes
    # reading is easiest to get subtly wrong on: a .deb is an `ar` archive, and
    # so is every static library on the machine, so the first member's name has
    # to be read too.
    deb = make_deb(os.path.join(work, "sniff.deb"))
    if deb:
        renamed = os.path.join(work, "sniffme")
        shutil.copyfile(deb, renamed)
        check(core.sort_path(renamed).route == core.ROUTE_PACKAGE,
              "a package with its ending taken off is still a package")
        plain_ar = os.path.join(work, "libsomething.a")
        with open(plain_ar, "wb") as handle:
            handle.write(b"!<arch>\n" + b"something.o/  " + b"\x00" * 100)
        check(core.sort_path(plain_ar).route != core.ROUTE_PACKAGE,
              "and an ordinary archive that is not a package is not mistaken for one")
    else:
        skip("recognising a package by its contents",
             "this machine cannot build that fixture")

    empty = os.path.join(work, "empty.deb")
    open(empty, "w").close()
    verdict = core.sort_path(empty)
    check(not verdict.can_install and "empty" in verdict.message.lower(),
          "an empty file is refused, and says so in one plain sentence")

    verdict = core.sort_path(os.path.join(work, "not-there-at-all.deb"))
    check(not verdict.can_install,
          "a file that is not there is refused rather than crashing")


def test_refusals_say_something_useful(core, work):
    heading("what a refusal says")
    for name, must_contain in (("thing.snap", "flathub"),
                               ("thing.exe", "windows"),
                               ("thing.msi", "windows"),
                               ("thing.dmg", "mac"),
                               ("thing.pkg", "mac"),
                               ("thing.run", "installer program")):
        verdict = core.sort_path(os.path.join(work, name))
        check(must_contain in verdict.message.lower(),
              "%-14s says something a person can act on" % name,
              verdict.message)
        check(bool(verdict.flathub_hint) or name.endswith(".run"),
              "%-14s offers something to search for instead" % name)

    # ⚠️ NO MESSAGE ANYWHERE MAY NAME ANOTHER LINUX (Royce's rule, from
    # 62-resolve-runtime.sh). Checked on the sentences themselves rather than on
    # the file, because the file is allowed to say anything in a comment.
    forbidden = ("debian", "ubuntu", "fedora", "rocky", "distrobox", "podman")
    leaked = []
    for key, sentence in core.SAY.items():
        for word in forbidden:
            if word in sentence.lower():
                leaked.append("%s: %s" % (key, sentence))
    check(not leaked, "no sentence a person reads names another Linux",
          "\n".join(leaked))


def test_route_a(core, work):
    heading("Route A — a real package, opened and never run")
    deb = make_deb(os.path.join(work, "testapp_1.2.3_amd64.deb"))
    if not deb:
        skip("Route A against a real .deb", "no dpkg-deb and no ar on this machine")
        return
    with FakeHome() as home:
        core.REHEARSAL = True
        verdict = core.sort_path(deb)
        check(verdict.route == core.ROUTE_PACKAGE, "it is sorted as a package")
        if shutil.which("dpkg-deb"):
            check(verdict.name == "testapp",
                  "its name is read out of the package itself", verdict.name)
            check(verdict.version == "1.2.3",
                  "and so is its version", verdict.version)
            check(verdict.signature == "unsigned",
                  "an unsigned package is called unsigned, and installs anyway")

        progress = core.Progress()
        result = core.install(verdict, progress)
        if not check(result.ok, "it installed", result.message):
            return

        record = result.record
        # ⚠️ THE PROOF THAT NO MAINTAINER SCRIPT RAN. The fixture's postinst
        # would have left a file beside the .deb. On any other Linux that script
        # runs as an administrator on your computer.
        check(not os.path.exists(os.path.join(work, "SCRIPT-RAN")),
              "the package's own install script was never run")

        entry = core.read_entry(record.entry_path)
        check(entry.get("Name") == "Test App",
              "the menu entry carries the app's own name", entry.get("Name"))
        check(entry.get("StartupWMClass") == "TestAppWindow",
              "and its window class, so the dock can join the window to the icon",
              entry.get("StartupWMClass"))
        check("Path" not in entry,
              "and the Path= naming a folder this computer lacks was dropped",
              entry.get("Path"))
        check(entry.get("Exec", "").startswith(record.install_path),
              "and Exec points at where the app really landed",
              entry.get("Exec"))
        check(os.path.isfile(entry.get("Exec", "").split()[0]),
              "and that program is really there and runnable")
        check(entry.get("Icon") and any(
            entry["Icon"] + ".png" in files
            for _b, _d, files in os.walk(core.icon_root())),
            "the icon was installed under our own name", entry.get("Icon"))
        check(entry.get("Categories", "").endswith(";"),
              "Categories ends in a semicolon, as the format requires",
              entry.get("Categories"))

        # The version is in the path with a link on top: an update can never
        # replace a working app with half of one.
        link = os.path.join(core.app_root(), record.id)
        check(os.path.islink(link), "the app is reached through a link")
        check(os.path.realpath(link) == os.path.realpath(record.install_path),
              "which points at the version that was just installed")

        test_registry(core, record, deb)
        test_remove(core, record, home)
        core.REHEARSAL = False


def test_registry(core, record, source):
    heading("the registry — what happened, so the reverse is never a guess")
    reloaded = core.Record.load(record.id)
    if not check(reloaded is not None, "the note was written and can be read back"):
        return
    check(reloaded.route == core.ROUTE_PACKAGE, "it remembers the route")
    check(reloaded.source == os.path.abspath(source),
          "and the file it came from", reloaded.source)
    check(len(reloaded.source_sha256) == 64,
          "and that file's fingerprint", reloaded.source_sha256)
    check(os.path.isdir(reloaded.install_path), "and where it went")
    check(any("installed" in line for line in reloaded.log),
          "and it wrote a dated line in its own log", "\n".join(reloaded.log))
    check(bool(reloaded.data_dirs), "and where the app's settings would live")


def test_remove(core, record, home):
    heading("Remove — the exact reverse, and nothing else")
    # A settings folder, and a file the person MADE. Only the first is ever in
    # scope, tick box or no tick box.
    settings = os.path.join(home, ".config", record.id)
    os.makedirs(settings, exist_ok=True)
    with open(os.path.join(settings, "prefs"), "w") as handle:
        handle.write("x" * 4096)
    documents = os.path.join(home, "Documents")
    os.makedirs(documents, exist_ok=True)
    with open(os.path.join(documents, "my film.txt"), "w") as handle:
        handle.write("mine")

    plan = core.removal_plan(record.id)
    check(plan is not None and plan["app_bytes"] > 0,
          "it can say how much space removing the app frees")
    check(plan and plan["data_bytes"] >= 4096,
          "and how much its settings take up, so the tick box is a real choice")

    result = core.remove(record.id, with_data=False)
    check(result.ok, "it removed", result.message)
    check(not os.path.isdir(record.install_path), "the app is gone")
    check(not os.path.exists(record.entry_path), "so is the menu entry")
    check(os.path.isdir(settings),
          "its settings were LEFT, because the tick box was not ticked")
    check(os.path.isfile(os.path.join(documents, "my film.txt")),
          "and the thing the person made with it was never in scope")
    check(core.Record.load(record.id) is not None,
          "the registry keeps the note, so 'what happened to X?' has an answer")
    check(any("removed" in line for line in core.Record.load(record.id).log),
          "and the log says when it went")

    # And again, with the box ticked.
    reinstalled = core.Record(record.id)
    reinstalled.name = record.name
    reinstalled.route = record.route
    reinstalled.install_path = ""
    reinstalled.data_dirs = settings
    reinstalled.save()
    result = core.remove(record.id, with_data=True)
    check(result.ok, "with the box ticked, it removes again", result.message)
    check(not os.path.isdir(settings), "and this time the settings go too")
    check(os.path.isfile(os.path.join(documents, "my film.txt")),
          "and the thing the person made is STILL never in scope")


def test_route_c_is_off(core, work):
    heading("Route C — a package that wants the operating system")
    for maker, name in ((make_tarball, "systemthing.tar.gz"),
                        (make_deb, "systemthing.deb")):
        path = maker(os.path.join(work, name), name="systemthing", os_bits=True)
        if not path:
            skip("a package that wants the operating system (%s)" % name,
                 "this machine cannot build that fixture")
            continue
        with FakeHome():
            core.REHEARSAL = True
            result = core.install(core.sort_path(path))
            check(not result.ok, "%s is refused" % name, result.message)
            check("operating system" in result.message,
                  "%s is refused in Royce's own words" % name, result.message)
            check("systemd" in result.detail or "udev" in result.detail
                  or "modules" in result.detail,
                  "%s — and the reason is recorded for Details" % name,
                  result.detail)
            core.REHEARSAL = False

    # And the detector itself, on each marker on its own, so a marker that is
    # dropped from the list one day fails here rather than on somebody's bench.
    work_dir = tempfile.mkdtemp(prefix="aq-markers-")
    try:
        for marker in core.OS_MARKERS:
            folder = os.path.join(work_dir, marker)
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, "something"), "w") as handle:
                handle.write("x")
            found = core.wants_the_os(work_dir)
            check("/" + marker in found, "%s is recognised" % marker)
            shutil.rmtree(os.path.join(work_dir, marker.split("/")[0]),
                          ignore_errors=True)
        check(core.wants_the_os(work_dir) == [],
              "and an ordinary app trips none of them")
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def test_ldd_failure(core, work):
    heading("the honest stop — an app that needs parts this computer lacks")
    tarball = make_tarball(os.path.join(work, "needy.tar.gz"), name="needy",
                           elf=True)
    # ⚠️ A STAND-IN ldd, BECAUSE THE REAL ONE CANNOT BE MADE TO FAIL ON DEMAND.
    # Building a program that needs a library nobody has would mean a compiler
    # in CI. This runs the real code path — find the ELF files, run ldd, read
    # its answer — against a command that gives the answer we need to test.
    script = ("#!/bin/sh\n"
              "echo '\\tlibnothing.so.6 => not found'\n"
              "echo '\\tlibc.so.6 => /lib64/libc.so.6 (0x0)'\n")
    with FakeHome():
        core.REHEARSAL = True
        with StandIn("ldd", script):
            result = core.install(core.sort_path(tarball))
        check(not result.ok, "it is refused rather than installed as a dead icon")
        check("does not have yet" in result.message,
              "and refused in the words the feature note wrote", result.message)
        check("libnothing.so.6" in result.detail,
              "and the missing piece is named behind Details", result.detail)
        core.REHEARSAL = False

    # ...and the other way: an app whose libraries all resolve must install.
    tarball = make_tarball(os.path.join(work, "happy.tar.gz"), name="happy",
                           elf=True)
    with FakeHome():
        core.REHEARSAL = True
        with StandIn("ldd", "#!/bin/sh\necho '\\tlibc.so.6 => /lib64/libc.so.6'\n"):
            result = core.install(core.sort_path(tarball))
        check(result.ok, "an app whose libraries all resolve installs",
              result.message)
        core.REHEARSAL = False


def test_archive_routes(core, work):
    heading("archives — a tarball and a zip with a program inside")
    for maker, name in ((make_tarball, "app-2.0.tar.gz"),
                        (make_tarball, "app-2.0.tar.xz"),
                        (make_zip, "app-2.0.zip")):
        path = maker(os.path.join(work, name), name="zipapp")
        with FakeHome():
            core.REHEARSAL = True
            result = core.install(core.sort_path(path))
            check(result.ok, "%s installed" % name, result.message)
            if result.ok:
                entry = core.read_entry(result.record.entry_path)
                check(os.access(entry.get("Exec", "x").split()[0], os.X_OK),
                      "%s — and the program inside it is runnable" % name)
            core.REHEARSAL = False


def test_update_by_dropping(core, work):
    heading("dropping a newer file on an app you already have")
    first = make_tarball(os.path.join(work, "dropapp-1.0.tar.gz"),
                         name="dropapp")
    second = make_tarball(os.path.join(work, "dropapp-2.0.tar.gz"),
                          name="dropapp")
    with FakeHome() as home:
        core.REHEARSAL = True
        one = core.install(core.sort_path(first))
        if not check(one.ok, "the first version installed", one.message):
            core.REHEARSAL = False
            return
        settings = os.path.join(home, ".config", one.record.id)
        os.makedirs(settings, exist_ok=True)
        with open(os.path.join(settings, "prefs"), "w") as handle:
            handle.write("mine")

        two = core.install(core.sort_path(second))
        check(two.ok, "the second one installed over it", two.message)
        check(two.record.id == one.record.id,
              "it is the same app, not a second copy",
              "%s vs %s" % (one.record.id, two.record.id))
        versions = os.path.join(core.versions_root(), one.record.id)
        kept = sorted(os.listdir(versions)) if os.path.isdir(versions) else []
        check(len(kept) == 1,
              "only the version in use is kept — the old copy was thrown away",
              kept)
        link = os.path.join(core.app_root(), one.record.id)
        check(os.path.realpath(link) == os.path.realpath(two.record.install_path),
              "and the shortcut points at the new one")
        check(os.path.isfile(os.path.join(settings, "prefs")),
              "the settings were kept, because an update is not a reinstall")
        log = core.Record.load(one.record.id).log
        check(any("updated to" in line for line in log),
              "and the log calls it an update rather than a second install", log)
        core.REHEARSAL = False


def test_escaping_archive(core, work):
    heading("an archive that tries to climb out of the folder it unpacks into")
    path = make_escaping_tarball(os.path.join(work, "sneaky.tar.gz"))
    with FakeHome() as home:
        core.REHEARSAL = True
        progress = core.Progress()
        result = core.install(core.sort_path(path), progress)
        check(result.ok, "the good part of it still installs", result.message)
        check(any("pointed outside" in line for line in progress.log_lines),
              "and it says how many parts pointed outside it were left out",
              "\n".join(progress.log_lines))
        escaped = [p for p in (os.path.join(home, "escaped"),
                               os.path.join(os.path.dirname(home), "escaped"),
                               "/absolutely/escaped")
                   if os.path.exists(p)]
        check(not escaped, "and nothing was written outside the folder",
              "\n".join(escaped))
        core.REHEARSAL = False


def test_entry_repair_rules(core, work):
    heading("the four menu-entry rules, one at a time")
    root = tempfile.mkdtemp(prefix="aq-entry-")
    try:
        build_payload(root, name="entryapp")
        entry_path, values, program = core.pick_entry(root)
        check(entry_path is not None, "the app's own menu entry was found")
        check(program is not None and os.path.isfile(program),
              "and the program it names really exists inside the package")

        out = os.path.join(root, "out.desktop")
        core.write_entry(values, program, core.exec_arguments(values["Exec"]),
                         "Entry App", "entryapp", out)
        written = core.read_entry(out)
        check(written.get("Name") == "Entry App",
              "OUR name is what the entry says")
        check(written.get("StartupWMClass") == "TestAppWindow",
              "the window class is read out of the app, not guessed")
        check("Path" not in written,
              "a Path= naming a folder this computer lacks is dropped")
        check(written.get("Exec", "").endswith("%U"),
              "the field codes the app asked for are kept", written.get("Exec"))
        check(written.get("TryExec") == program,
              "and TryExec names the same program")

        # A Path= that names a real folder is somebody's deliberate setting and
        # must survive. The two cases are one line apart in the code and it
        # would be very easy to break the second while fixing the first.
        values["Path"] = os.path.dirname(program)
        core.write_entry(values, program, "", "Entry App", "entryapp", out)
        written = core.read_entry(out)
        check(written.get("Path") == os.path.dirname(program),
              "but a Path= naming a folder that DOES exist is left alone")

        # An entry pointing at a program that is not in the package is
        # upstream's leftovers, and installing it gives somebody a dead icon.
        os.remove(program)
        _entry, _values, found = core.pick_entry(root)
        check(found is None,
              "an entry naming a program that is not there is not treated as the app")
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_root_refusal(core, work):
    heading("it refuses to install as an administrator")
    was = core.REHEARSAL
    core.REHEARSAL = False
    try:
        if core.running_as_root():
            tarball = make_tarball(os.path.join(work, "asroot.tar.gz"))
            with FakeHome():
                result = core.install(core.sort_path(tarball))
            check(not result.ok and "sudo" in result.message,
                  "run as an administrator, it refuses and says why",
                  result.message)
        else:
            check(not core.refuse_root(),
                  "run as an ordinary person, it does not refuse")
            check("sudo" in core.ROOT_REFUSAL,
                  "and the refusal it would print names the thing not to do")
    finally:
        core.REHEARSAL = was


def test_flatpak_command(core):
    heading("the Flatpak route asks the one privileged helper, through pkexec")
    argv = core.flatpak_argv("install", ["org.kde.kdenlive//stable"],
                             progress_fd=2)
    check(argv[0] == "pkexec",
          "it goes through pkexec — the desktop's own one-prompt question", argv)
    check("sudo" not in argv, "and never through sudo", argv)
    check(argv[1] == core.FLATPAK_HELPER,
          "and it is the same helper the app chooser already uses", argv)
    check("--mode" in argv and argv[argv.index("--mode") + 1] == "install",
          "the job is named", argv)
    for action in ("install-file", "uninstall", "update"):
        argv = core.flatpak_argv(action, ["com.example.App"])
        check(argv[argv.index("--mode") + 1] == action,
              "...and so is %s" % action, argv)
    argv = core.flatpak_argv("install", ["x"], dry_run=True)
    check(argv[0] != "pkexec",
          "a rehearsal never asks anybody for a password", argv)


def test_helper_understands_the_modes():
    heading("the privileged helper really understands all four jobs")
    helper = os.path.join(REPO, "system_files", "usr", "libexec",
                          "aquarius-creator-apps-install")
    if not os.access(helper, os.X_OK):
        skip("the helper's four jobs", "not in this checkout")
        return
    for mode, expect in (("install", "flatpak install --system"),
                         ("install-file", "flatpak install --system"),
                         ("uninstall", "flatpak uninstall --system"),
                         ("update", "flatpak update --system")):
        done = subprocess.run([helper, "--mode", mode, "--dry-run",
                               "--progress-fd", "1", "com.example.App"],
                              capture_output=True, text=True)
        check(expect in done.stdout,
              "--mode %-13s rehearses the right command" % mode, done.stdout)
        check("DONE" in done.stdout,
              "--mode %-13s finishes cleanly" % mode)
    done = subprocess.run([helper, "--mode", "nonsense", "--dry-run", "x"],
                          capture_output=True, text=True)
    check(done.returncode != 0 and "not one of the four" in done.stdout,
          "a job it does not know is refused before anything privileged happens",
          done.stdout)


def test_links_and_urls(core):
    heading("pasting a link")
    check(core.looks_like_link("https://flathub.org/apps/com.obsproject.Studio"),
          "a web address is recognised as one")
    check(not core.looks_like_link("obs studio"),
          "and an ordinary search is not")
    check(core.flathub_page_id(
        "https://flathub.org/apps/com.obsproject.Studio") == "com.obsproject.Studio",
        "a Flathub page link becomes the app it names")
    check(core.flathub_page_id(
        "https://example.com/thing.deb") == "",
        "and an ordinary download link does not pretend to be one")


def test_names(core):
    heading("the small readings that everything else rests on")
    check(core.safe_name("Some App! v2") == "some-app-v2",
          "a name becomes something safe to use as a folder",
          core.safe_name("Some App! v2"))
    check(core.safe_name("") == "app", "and an empty name still becomes something")
    check(core.safe_name("../../etc/passwd") == "etc-passwd",
          "and a name that tries to climb out cannot",
          core.safe_name("../../etc/passwd"))
    check(core.exec_program("/opt/a/b --flag %U") == "/opt/a/b",
          "the program is read out of an Exec line")
    check(core.exec_arguments("/opt/a/b --flag %U") == "--flag %U",
          "and so is everything after it")
    check(core.exec_program("env FOO=1 /opt/a/b") == "/opt/a/b",
          "even when the line starts with an environment setting")
    check(core.human_size(1500) == "2 kB", core.human_size(1500))
    check(core.human_size(2 * 1000 ** 3) == "2.0 GB", core.human_size(2 * 1000 ** 3))


# ==============================================================================
# Run them
# ==============================================================================
def main(argv):
    path = argv[1] if len(argv) > 1 else DEFAULT_MODULE
    if not os.path.isfile(path):
        print("test-installer-sorter: %s is not there." % path)
        return 2
    print("test-installer-sorter: reading %s" % path)
    core = load(path)

    work = tempfile.mkdtemp(prefix="aq-installer-test-")
    try:
        test_sorter_by_name(core, work)
        test_sorter_by_content(core, work)
        test_refusals_say_something_useful(core, work)
        test_names(core)
        test_links_and_urls(core)
        test_entry_repair_rules(core, work)
        test_route_a(core, work)
        test_archive_routes(core, work)
        test_update_by_dropping(core, work)
        test_escaping_archive(core, work)
        test_route_c_is_off(core, work)
        test_ldd_failure(core, work)
        test_root_refusal(core, work)
        test_flatpak_command(core)
        test_helper_understands_the_modes()

        # A real .rpm, when this machine can make one. It is the same code path
        # as the .deb above — that is the point of "no conversion, ever" — so
        # this is a spot check of the one command that differs, not a repeat.
        heading("Route A — a real .rpm, if this machine can build one")
        rpm = make_rpm(os.path.join(work, "testapp.rpm"))
        if not rpm:
            skip("Route A against a real .rpm",
                 "no rpmbuild here; the same route is proved by the .deb above")
        else:
            with FakeHome():
                core.REHEARSAL = True
                verdict = core.sort_path(rpm)
                check(verdict.route == core.ROUTE_PACKAGE, "it is a package")
                result = core.install(verdict)
                check(result.ok, "it installed", result.message)
                core.REHEARSAL = False
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print()
    print("test-installer-sorter: %d passed, %d failed, %d skipped"
          % (PASSED, FAILED, SKIPPED))
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
