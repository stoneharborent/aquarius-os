#!/usr/bin/python3
# =============================================================================
# aquarius_apfs — reading a Mac drive's list of volumes, in one place
# =============================================================================
# PLAIN ENGLISH
#
# A Mac-formatted drive (APFS) is not laid out like a Windows or camera-card
# drive. Where a USB stick has ONE thing on it, an APFS drive has a "container"
# with one or more "volumes" inside it. An external drive you formatted on a Mac
# normally has exactly one volume — the one with your files on. A Mac's own
# internal SSD has five or six, and only one or two of them are yours; the rest
# are Apple's own machinery (the recovery system, the sleep-image volume, the
# pre-boot helper) and nobody would ever want to open them.
#
# The program that tells us which is which is `apfsutil`, which comes in the
# same package as `apfs-fuse`. You hand it a drive and it prints a paragraph per
# volume. THIS FILE IS THE ONE PLACE THAT READS THAT PARAGRAPH, because two
# different programs need the answer:
#
#   /usr/libexec/aquarius-automount      mounts the drive when you plug it in
#   /usr/libexec/aquarius-drive-unlock   unlocks a FileVault drive
#
# Two copies of a parser is two chances to disagree about whether a volume is
# encrypted, and being wrong about that means either an unnecessary password box
# or a mount that silently hangs. So there is one copy, and it is tested
# (tests/test-automount-mount.py).
#
# -----------------------------------------------------------------------------
# WHAT apfsutil ACTUALLY PRINTS
# -----------------------------------------------------------------------------
# This is a real listing of an ordinary external drive with one volume on it:
#
#     Volume 0 6502FAEA-D13B-4569-9410-BAFABC8EBD3E
#     ---------------------------------------------
#     Role:               No specific role
#     Name:               SHOOT 2026 (Case-insensitive)
#     Capacity Consumed:  488600719360 Bytes
#     FileVault:          No
#
# and here is the shape of a Mac's own internal disk, cut down:
#
#     Volume 0 ...     Role: System     Name: Macintosh HD
#     Volume 1 ...     Role: Preboot    Name: Preboot
#     Volume 2 ...     Role: Recovery   Name: Recovery
#     Volume 3 ...     Role: VM         Name: VM
#     Volume 4 ...     Role: Data       Name: Macintosh HD - Data
#
# The exact spellings come from apfsutil's own source (ApfsUtil/ApfsUtil.cpp in
# sgan81/apfs-fuse, the 2020 snapshot Fedora packages). They are:
#
#   "No specific role", and then either a comma-separated list drawn from
#   System, User, Recovery, VM, Preboot, Installer
#   — or one of
#   Data, Baseband, Update, Xart, Hardware, Backup, Reserved-7, Reserved-8,
#   Enterprise, Reserved-10, Prelogin
#
# If the drive is handed to apfsutil as a WHOLE DISK rather than a partition it
# prints a partition table first ("Found partitions:" …). We always hand it a
# partition, but the parser skips anything before the first "Volume" line anyway,
# because a parser that only works on the input you expected is a parser that
# fails on the one drive that is different.
#
# -----------------------------------------------------------------------------
# ⚠️ FILEVAULT IS READ FROM HERE AND NOWHERE ELSE
# -----------------------------------------------------------------------------
# `FileVault: Yes` means the volume's contents are encrypted and cannot be
# opened without the password. apfsutil can still read the volume's NAME and
# ROLE without it — the label on the box is not inside the locked box — which is
# exactly why this works: we can tell somebody "the drive called Archive is
# locked" without ever asking them for anything.
#
# If we got this wrong in the "no" direction, apfs-fuse would be started on a
# locked volume, would want a passphrase, and — with no terminal to ask on —
# would fail with "Unable to get volume!". Not dangerous, but a drive that
# silently does not appear. So the mount side always asks this file first.
# =============================================================================

import os
import pwd
import re
import subprocess

# Where the two programs live. Both come from Fedora's `apfs-fuse` package.
APFSUTIL = "/usr/bin/apfsutil"
APFS_FUSE = "/usr/bin/apfs-fuse"

# The volumes that are Apple's machinery, not anybody's files. We never mount
# these — there is nothing on them a person would open, and on a Mac's internal
# disk they would otherwise fill the dock with four tiles nobody wants.
#
# "Backup" is deliberately NOT in this list: that is the role a Time Machine
# drive carries, and pulling a file out of a Time Machine backup is exactly the
# rescue this whole feature exists for.
#
# "System" and "Data" are not here either. On a Mac's internal disk those are
# "Macintosh HD" and "Macintosh HD - Data" — the operating system and the
# person's home folder. The second one is the one somebody plugging their old
# Mac's disk into this computer is looking for.
SKIP_ROLES = frozenset((
    "Recovery",     # the macOS recovery system
    "Preboot",      # the helper macOS boots through
    "VM",           # the sleep image / swap file
    "Update",       # a staged macOS update
    "Xart",         # Apple key storage
    "Hardware",     # firmware-owned
    "Baseband",     # modem firmware (Apple silicon)
    "Installer",    # a staged installer
    "Prelogin",     # pre-login helper
))


class Volume(object):
    """One volume inside an APFS container, as apfsutil described it."""

    def __init__(self, index, uuid="", name="", role="", encrypted=False,
                 capacity=-1):
        self.index = index
        self.uuid = uuid
        self.name = name
        self.role = role
        self.encrypted = encrypted
        self.capacity = capacity

    # The role line can name more than one role ("System, User"), so it is
    # compared as a set of words rather than as one string.
    @property
    def roles(self):
        if not self.role or self.role == "No specific role":
            return ()
        return tuple(part.strip() for part in self.role.split(",") if part.strip())

    @property
    def is_apple_internal(self):
        """True for the volumes that are Apple's own machinery."""
        for role in self.roles:
            if role in SKIP_ROLES or role.startswith("Reserved-"):
                return True
        return False

    @property
    def should_mount(self):
        """True for a volume worth putting in front of a person.

        Encrypted volumes are NOT included: they need a password, which is a
        separate, deliberate step (aquarius-drive-unlock). This property is only
        about "would we mount it if we could".
        """
        return not self.is_apple_internal

    @property
    def display_name(self):
        """The name to show, and to use as the folder name. Never empty."""
        return self.name or ("Mac volume %d" % self.index)

    def __repr__(self):
        return "Volume(%d, %r, role=%r, encrypted=%r)" % (
            self.index, self.name, self.role, self.encrypted)


# -----------------------------------------------------------------------------
# The parser
# -----------------------------------------------------------------------------
_VOLUME_RE = re.compile(r"^Volume\s+(\d+)\s*(\S*)\s*$")
_FIELD_RE = re.compile(r"^([A-Za-z][A-Za-z ]*?):\s+(.*?)\s*$")

# apfsutil puts the case-sensitivity of the volume in brackets after its name.
# That is information about the filesystem, not part of what the volume is
# called, and a folder called "SHOOT 2026 (Case-insensitive)" in somebody's dock
# would be absurd.
_CASE_SUFFIX_RE = re.compile(r"\s*\((?:Case-insensitive|Case-sensitive)\)\s*$")


def parse_apfsutil(text):
    """Turn apfsutil's output into a list of Volume objects.

    Anything before the first "Volume N" line is ignored (that is the partition
    table apfsutil prints when it is given a whole disk). A line it does not
    recognise is ignored rather than being an error: apfsutil also prints a
    "Snapshots:" section, indented, which is not our business.

    A drive it could not read at all produces an empty list, which every caller
    treats as "leave this drive alone".
    """
    volumes = []
    current = None

    for raw in (text or "").splitlines():
        line = raw.rstrip("\r")

        match = _VOLUME_RE.match(line)
        if match:
            current = Volume(int(match.group(1)), uuid=match.group(2))
            volumes.append(current)
            continue

        if current is None:
            continue
        # Indented lines belong to the snapshot list, not to the volume.
        if line[:1] in (" ", "\t"):
            continue

        field = _FIELD_RE.match(line)
        if not field:
            continue
        key = field.group(1).strip()
        value = field.group(2).strip()

        if key == "Role":
            current.role = value
        elif key == "Name":
            current.name = _CASE_SUFFIX_RE.sub("", value)
        elif key == "FileVault":
            # Anything that is not a plain "No" is treated as locked. Being
            # wrong in this direction costs a password box that was not needed;
            # being wrong the other way costs a drive that silently never
            # appears.
            current.encrypted = (value.strip().lower() != "no")
        elif key == "Capacity Consumed":
            digits = value.split()[0] if value else ""
            current.capacity = int(digits) if digits.isdigit() else -1

    return volumes


def read_volumes(device, run=None, timeout=60):
    """Ask apfsutil about a device and return its volumes.

    `run` is the thing that actually runs the command. It exists so that the
    tests can hand in a captured apfsutil output instead of needing a real Mac
    drive; every real caller leaves it alone.
    """
    if run is None:
        run = _run_apfsutil
    code, out, err = run([APFSUTIL, device], timeout)
    if code != 0 and not out:
        return []
    return parse_apfsutil(out or err)


def _run_apfsutil(argv, timeout):
    try:
        proc = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
            errors="replace",
        )
    except FileNotFoundError:
        return 127, "", "%s is not installed" % argv[0]
    except subprocess.SubprocessError as exc:
        return 1, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


# -----------------------------------------------------------------------------
# Folder names, made exactly the way udisks2 makes them
# -----------------------------------------------------------------------------
# Every other drive on this computer is mounted by udisks2 at
# /run/media/<you>/<label>. Ours have to look identical or the dock, the Files
# app and the person's own eyes would treat them as something different. So the
# two rules udisks2 uses are copied here from its source
# (src/udiskslinuxfilesystem.c, sanitize_mount_point and the loop under it):
#
#   1. a character that would break a path or a shell — "/" '"' "'" "\" and
#      anything unprintable — becomes an underscore;
#   2. if that name is taken, a number is stuck on the END with no separator:
#      SHOOT-2026, then SHOOT-20261, then SHOOT-20262. It looks odd and it is
#      what udisks2 does, and matching it matters more than improving it.
_UNSAFE = set('/"\'\\')


def sanitize_name(name):
    """The folder name for a volume, sanitized the way udisks2 sanitizes a label."""
    out = []
    for char in name or "":
        if ord(char) < 128:
            # printable ASCII, minus the four characters udisks2 refuses
            if char in _UNSAFE or not (32 <= ord(char) < 127):
                out.append("_")
            else:
                out.append(char)
        elif char.isprintable():
            out.append(char)
        else:
            out.append("_")
    return "".join(out)


def unique_mount_point(media_root, name, exists=os.path.exists):
    """A path under media_root that nothing is using yet."""
    base = os.path.join(media_root, sanitize_name(name) or "disk")
    if not exists(base):
        return base
    for n in range(1, 1001):
        candidate = "%s%d" % (base, n)
        if not exists(candidate):
            return candidate
    return None


# -----------------------------------------------------------------------------
# Where the drives are: the mount table, and the folder they appear in
# -----------------------------------------------------------------------------
# These are not really about APFS — they are about drives — but they live here
# because they are the two questions BOTH programs that touch a Mac drive have to
# ask, and one copy of an answer cannot disagree with itself.

# Where Linux writes down every mount on the machine. AQ_MOUNTINFO overrides it
# and is read fresh on every call, ONLY so the tests can hand in a made-up mount
# table; nothing on a real machine sets it.
def mountinfo_path():
    return os.environ.get("AQ_MOUNTINFO", "/proc/self/mountinfo")


def _unescape(field):
    r"""Turn the \040 that /proc writes for a space back into a space.

    Linux escapes space, tab, newline and backslash in the mount table as octal
    (\040 \011 \012 \134). A drive called "My Drive" would otherwise come back
    as "My\040Drive" and never match the folder we made.
    """
    out = []
    i = 0
    while i < len(field):
        if field[i] == "\\" and field[i + 1:i + 4].isdigit() and len(field) >= i + 4:
            try:
                out.append(chr(int(field[i + 1:i + 4], 8)))
                i += 4
                continue
            except ValueError:
                pass
        out.append(field[i])
        i += 1
    return "".join(out)


def read_mounts(path=None):
    """Every mount on this machine, as a list of small dictionaries.

    Each one has: mount_point, fstype, source. Read from /proc/self/mountinfo,
    whose layout is

        ID PARENT MAJOR:MINOR ROOT MOUNT-POINT OPTIONS [tags...] - FSTYPE SOURCE SUPER-OPTIONS

    The "-" in the middle is a real separator with a variable number of optional
    tags before it, which is why this looks for it rather than counting fields.
    """
    mounts = []
    try:
        with open(path or mountinfo_path(), "r") as handle:
            for line in handle:
                parts = line.split()
                try:
                    dash = parts.index("-")
                    mounts.append({
                        "mount_point": _unescape(parts[4]),
                        "fstype": parts[dash + 1],
                        "source": _unescape(parts[dash + 2]),
                    })
                except (IndexError, ValueError):
                    continue
    except OSError:
        pass
    return mounts


def media_root():
    """/run/media/<this person> — the folder every drive appears in.

    AQ_MEDIA_ROOT overrides it, and means exactly what it means to the dock
    (aquarius-shell, components/dock/DockDrives.qml): "the folder drives are
    mounted into". Nothing on a real machine sets it; it is how a test can watch
    a folder it is allowed to create.
    """
    override = os.environ.get("AQ_MEDIA_ROOT")
    if override:
        return override
    try:
        name = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        return ""
    if not name or "/" in name:
        return ""
    return "/run/media/%s" % name
