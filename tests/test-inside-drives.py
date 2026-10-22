#!/usr/bin/python3
# =============================================================================
# test-inside-drives.py — every drive mounts at login, and never the wrong one
# =============================================================================
# WHAT THIS IS ABOUT
#
# ⚠️ CHANGED 2026-10-19. Royce: "Remove verification for all internal and
# external drives. Just mount them from login and show in dock." So since that
# day /usr/libexec/aquarius-automount mounts the drives INSIDE the computer at
# login too, with no question and no password. (Before, an inside drive asked
# "Mount every login?" once — FEATURES 020 — and that question is retired.
# This file replaces tests/test-remember-drive.py, which tested it.)
#
# The dangerous half of "mount every drive" is the word EVERY. The things that
# must never happen are the machine mounting a piece of its own start-up
# plumbing, a partition of the disk it is running from, a hidden recovery
# partition, or something encrypted. So most of this test is the NEGATIVES —
# fake drives that must be REFUSED — run through the real decision code.
#
# WHAT IT CHECKS
#   Mounted:
#     1. an ordinary inside data drive (ext4) IS mounted, through udisks2, with
#        auth.no_user_interaction so no password box can ever appear
#     2. an inside Windows (NTFS) drive is mounted READ-ONLY
#     3. a plugged-in drive still mounts the way it always did, read-write
#   Refused — and udisks2 is never even asked:
#     4. the EFI System Partition, BIOS boot, Microsoft Reserved, Windows
#        Recovery, swap, LVM, RAID and /boot partitions, by partition type
#        (GPT codes and the old MBR numbers)
#     5. a partition marked hidden / platform-required / do-not-automount
#     6. a partition of the disk AquariusOS is installed on
#     7. swap, LVM, RAID and blank partitions inside the computer
#     8. an encrypted drive (LUKS, BitLocker) — and it says why, once
#     9. anything already mounted
#    10. anything already in /etc/fstab — which is what keeps a drive the old
#        "ask once" feature remembered working, instead of mounted twice
#    11. anything udisks2 says to ignore
#    12. the AquariusOS installer stick
#   And:
#    13. the agent's rehearsal states the never-touch list out loud
#    14. the old --ask worker is gone and says so instead of asking
#
# HOW TO RUN IT
#   ./tests/test-inside-drives.py
#   ./tests/test-inside-drives.py /usr/libexec/aquarius-automount
#
# It needs python3-gobject and nothing else. No bus, no drives, no root.
# =============================================================================

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import sys

sys.dont_write_bytecode = True

FAILS = []


def ok(msg):
    print("  OK   %s" % msg)


def bad(msg):
    print("  FAIL %s" % msg, file=sys.stderr)
    FAILS.append(msg)


def load(path, name):
    """Import a program that has no .py on the end of its name."""
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# -----------------------------------------------------------------------------
# A fake udisks2. It answers property reads out of a dictionary per interface,
# says "that interface is not here" for anything it was not given, and writes
# down every Mount it is asked for.
# -----------------------------------------------------------------------------
class FakeBus:
    def __init__(self, GLib, interfaces):
        self.GLib = GLib
        self.interfaces = interfaces  # {iface: {prop: GLib.Variant}}
        self.calls = []

    def call_sync(self, name, path, iface, method, params, reply_type,
                  flags, timeout, cancellable):
        self.calls.append({"path": path, "iface": iface, "method": method,
                           "params": params})
        if method == "GetAll":
            wanted = params.unpack()[0]
            if wanted not in self.interfaces:
                raise self.GLib.Error("no such interface")
            return self.GLib.Variant("(a{sv})", ({},))
        if method == "Get":
            wanted, prop = params.unpack()
            values = self.interfaces.get(wanted)
            if values is None or prop not in values:
                raise self.GLib.Error("no such property")
            return self.GLib.Variant("(v)", (values[prop],))
        if method == "Mount":
            return self.GLib.Variant("(s)", ("/run/media/tester/Footage",))
        raise self.GLib.Error("the fake bus was asked for %s" % method)

    def mounts(self):
        return [c for c in self.calls if c["method"] == "Mount"]


BLOCK = "org.freedesktop.UDisks2.Block"
FS = "org.freedesktop.UDisks2.Filesystem"
PART = "org.freedesktop.UDisks2.Partition"
OBJ = "/org/freedesktop/UDisks2/block_devices/sdb1"


def drive(GLib, device="/dev/sdb1", label="Footage", uuid="1234-ABCD-5678",
          fstype="ext4", inside=True, hint_ignore=False, mount_points=None,
          parttype=None, flags=0, in_fstab=False, filesystem=True):
    """The interfaces udisks2 would publish for one partition."""
    block = {
        "Device": GLib.Variant("ay", list(device.encode() + b"\x00")),
        "IdLabel": GLib.Variant("s", label),
        "IdUUID": GLib.Variant("s", uuid),
        "IdType": GLib.Variant("s", fstype),
        "HintSystem": GLib.Variant("b", inside),
        "HintIgnore": GLib.Variant("b", hint_ignore),
        "HintAuto": GLib.Variant("b", not inside),
    }
    if in_fstab:
        block["Configuration"] = GLib.Variant(
            "a(sa{sv})", [("fstab", {"dir": GLib.Variant("ay", list(b"/mnt/x\x00"))})])
    else:
        block["Configuration"] = GLib.Variant("a(sa{sv})", [])
    interfaces = {BLOCK: block}
    if filesystem:
        interfaces[FS] = {"MountPoints": GLib.Variant("aay", mount_points or [])}
    if parttype is not None:
        interfaces[PART] = {"Type": GLib.Variant("s", parttype),
                            "Flags": GLib.Variant("t", flags)}
    return interfaces


def run_one(agent, GLib, interfaces, fstab_uuids=(), path=OBJ):
    bus = FakeBus(GLib, interfaces)
    mounter = agent.AutoMounter(bus)
    agent.uuid_in_fstab = lambda uuid: uuid in fstab_uuids
    mounter.consider(path)
    return bus


def check(path):
    import gi
    gi.require_version("GLib", "2.0")
    gi.require_version("Gio", "2.0")
    from gi.repository import GLib

    agent = load(path, "aquarius_automount")
    lines = []
    agent.log = lambda message: lines.append(str(message))
    # The real one reads /proc/self/mountinfo and would find THIS machine's
    # system disk, which has nothing to do with the fake drives below. Here the
    # operating system lives on sda.
    agent.critical_disks = lambda: {"sda"}

    print("-- mounted: inside drives at login, plugged-in drives as always --")

    # 1. An ordinary inside data drive.
    bus = run_one(agent, GLib, drive(GLib))
    mounts = bus.mounts()
    if len(mounts) == 1 and mounts[0]["path"] == OBJ:
        ok("an ordinary inside drive (ext4) is mounted at login, with no question")
        options = mounts[0]["params"].unpack()[0]
        if options.get("auth.no_user_interaction") is True:
            ok("and it is asked with auth.no_user_interaction, so a password box can"
               " never appear at login")
        else:
            bad("auth.no_user_interaction is missing: %r" % (options,))
        if "options" not in options:
            ok("and it is mounted read-write — it is the person's own drive")
        else:
            bad("an ext4 inside drive was given mount options %r" % options["options"])
    else:
        bad("an ordinary inside drive was not mounted (Mount calls: %d)" % len(mounts))

    # 2. Inside NTFS: read-only.
    bus = run_one(agent, GLib, drive(GLib, label="Windows", fstype="ntfs"))
    mounts = bus.mounts()
    if len(mounts) == 1 and mounts[0]["params"].unpack()[0].get("options") == "ro":
        ok("an inside Windows (NTFS) drive is mounted READ-ONLY — Windows' fast"
           " startup leaves it half-closed")
    else:
        bad("an inside NTFS drive was not mounted read-only: %r"
            % ([m["params"].unpack() for m in mounts],))

    # 3. Plugged in: unchanged.
    bus = run_one(agent, GLib, drive(GLib, device="/dev/sdc1", fstype="ntfs",
                                     inside=False))
    mounts = bus.mounts()
    if len(mounts) == 1 and "options" not in mounts[0]["params"].unpack()[0]:
        ok("a plugged-in drive still mounts exactly as it always did")
    else:
        bad("a plugged-in NTFS drive was mounted wrongly: %r"
            % ([m["params"].unpack() for m in mounts],))

    print("-- refused: the never-touch list (udisks2 must not even be asked) --")

    def refused(description, interfaces, **kwargs):
        bus = run_one(agent, GLib, interfaces, **kwargs)
        if bus.mounts():
            bad("%s was MOUNTED. It must never be." % description)
            return False
        return True

    # 4. Partition types.
    every = True
    for code, what in sorted(agent.NEVER_TOUCH_PARTITION_TYPES.items()):
        fstype = "vfat" if "EFI" in what else "ext4"
        every &= refused("%s (%s)" % (what, code),
                         drive(GLib, fstype=fstype, parttype=code))
        # Upper case must not slip past: udisks2 normally writes lower case,
        # but nothing promises it.
        every &= refused("%s (%s, upper case)" % (what, code),
                         drive(GLib, fstype=fstype, parttype=code.upper()))
    if every:
        ok("every never-touch partition type is refused (%d codes): the EFI"
           " partition, BIOS boot, Microsoft Reserved, Windows Recovery, swap,"
           " LVM, RAID, /boot, the hidden MBR types…"
           % len(agent.NEVER_TOUCH_PARTITION_TYPES))
    for needed in ("c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
                   "de94bba4-06d1-4d40-a16a-bfd50179d6ac",
                   "e3c9e316-0b5c-4db8-817d-f92df00215ae",
                   "21686148-6449-6e6f-744e-656564454649",
                   "0xef", "0x27"):
        if needed not in agent.NEVER_TOUCH_PARTITION_TYPES:
            bad("the never-touch list has lost %s" % needed)

    # 5. Hidden flags.
    every = True
    for bit in (0, 62, 63):
        every &= refused("a partition with GPT attribute bit %d" % bit,
                         drive(GLib, parttype="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7",
                               flags=1 << bit))
    if every:
        ok("a partition marked hidden, platform-required or do-not-automount is"
           " refused — how computer makers hide recovery partitions")
    bus = run_one(agent, GLib, drive(GLib, parttype="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7",
                                     flags=0x80))
    if len(bus.mounts()) == 1:
        ok("but an ordinary Windows data partition (and an MBR 'bootable' flag) is"
           " still mounted")
    else:
        bad("an ordinary basic-data partition was refused")

    # 6. The disk AquariusOS is on.
    for device in ("/dev/sda3", "/dev/sda9"):
        if not refused("a partition of the system disk (%s)" % device,
                       drive(GLib, device=device),
                       path="/org/freedesktop/UDisks2/block_devices/" + device[5:]):
            break
    else:
        ok("no partition of the disk AquariusOS is installed on is ever mounted")
    agent.critical_disks = lambda: {"nvme0n1"}
    if refused("an NVMe partition of the system disk",
               drive(GLib, device="/dev/nvme0n1p4"),
               path="/org/freedesktop/UDisks2/block_devices/nvme0n1p4"):
        ok("…including on an NVMe disk (nvme0n1p4 belongs to nvme0n1)")
    agent.critical_disks = lambda: {"sda"}

    # 7. Not a filesystem anybody keeps files on.
    every = True
    for fstype in ("swap", "LVM2_member", "linux_raid_member", "", "squashfs"):
        every &= refused("an inside %s partition" % (fstype or "blank"),
                         drive(GLib, fstype=fstype))
    if every:
        ok("swap, LVM, RAID, squashfs and blank partitions inside the computer are"
           " never mounted")

    # 8. Encrypted.
    every = True
    for fstype in ("crypto_LUKS", "BitLocker"):
        del lines[:]
        every &= refused("an encrypted (%s) drive" % fstype,
                         drive(GLib, fstype=fstype, filesystem=False))
        if not any("encrypted" in line for line in lines):
            bad("an encrypted (%s) drive was skipped silently — the journal should"
                " say why it is missing" % fstype)
            every = False
    if every:
        ok("an encrypted drive (LUKS, BitLocker) is left locked, and the journal"
           " says so in one plain line")

    # 9. Already mounted.
    if refused("an already-mounted drive",
               drive(GLib, mount_points=[list(b"/mnt/x\x00")])):
        ok("a drive that is already mounted is never mounted twice")

    # 10. Already in fstab — both ways udisks2 or the file can say so.
    if refused("a drive udisks2 says is in /etc/fstab", drive(GLib, in_fstab=True)) \
            and refused("a drive named by UUID in /etc/fstab", drive(GLib),
                        fstab_uuids=("1234-ABCD-5678",)):
        ok("a drive already in /etc/fstab is left to the machine — a drive the old"
           " 'ask once' feature remembered keeps working and is not mounted twice")

    # 11. HintIgnore.
    if refused("a drive udisks2 says to ignore", drive(GLib, hint_ignore=True)) \
            and refused("a plugged-in drive udisks2 says to ignore",
                        drive(GLib, inside=False, hint_ignore=True)):
        ok("anything udisks2 itself says to ignore is ignored")

    # 12. The installer stick.
    if refused("the AquariusOS installer stick",
               drive(GLib, device="/dev/sdd1", label="AQUARIUSOS", fstype="iso9660",
                     inside=False)):
        ok("the AquariusOS installer stick is never mounted")

    # 13. The rehearsal.
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        agent.dry_run()
    said = buffer.getvalue()
    for phrase in ("never-touch list", "EFI System Partition", "Windows Recovery",
                   "Microsoft Reserved", "disk AquariusOS is installed on",
                   "already listed in /etc/fstab", "encrypted", "READ-ONLY",
                   "installer stick", "49-aquarius-udisks.rules", "no password"):
        if phrase not in said:
            bad("the agent's rehearsal does not mention %r" % phrase)
            break
    else:
        ok("the agent's rehearsal states the never-touch list out loud")

    # 14. The retired question.
    for name in ("maybe_offer", "ask_about_drive", "never_ask_add", "REMEMBER_HELPER"):
        if hasattr(agent, name) or hasattr(agent.AutoMounter, name):
            bad("the retired 'ask once' piece %s is still in the agent" % name)
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        code = agent.main(["aquarius-automount", "--ask", "u", "l", "ext4", "/dev/x"])
    if code == 0 and "retired" in buffer.getvalue():
        ok("the old --ask worker asks nothing any more and says so")
    else:
        bad("--ask did not say it was retired (exit %r): %s" % (code, buffer.getvalue()))


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    agent = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.join(
        here, "..", "system_files", "usr", "libexec", "aquarius-automount")
    agent = os.path.abspath(agent)

    print("== every drive mounts at login, and never the wrong one ==")
    print("   agent: %s" % agent)

    if not os.path.isfile(agent):
        print("FAIL %s is not there — nothing to test." % agent, file=sys.stderr)
        return 1
    try:
        import gi  # noqa: F401
    except Exception as error:  # noqa: BLE001
        print("FAIL python3-gobject is not usable here: %s" % error, file=sys.stderr)
        return 1

    check(agent)

    print("")
    if FAILS:
        print("%d check(s) failed." % len(FAILS), file=sys.stderr)
        return 1
    print("All inside-drive checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
