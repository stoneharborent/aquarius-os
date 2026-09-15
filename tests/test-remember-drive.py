#!/usr/bin/python3
# =============================================================================
# test-remember-drive.py — "ask once" really does ask once, and never the wrong
# drive
# =============================================================================
# WHAT THIS IS ABOUT
#
# A drive that lives INSIDE this computer used to ask for an administrator
# password at every single login. FEATURES 020 changed that to: ask ONCE, per
# drive, and then put it in /etc/fstab so it is simply there.
#
# The dangerous half of that sentence is "per drive". The one thing that must
# never happen is the machine offering to rewrite /etc/fstab for the disk the
# operating system is living on, the little EFI partition it boots from, or
# Windows' own volume. So this test spends most of its length proving the
# NEGATIVES — the drives that must never be offered and never be written.
#
# ⚠️ AND THE OTHER NEGATIVE, WHICH IS THE WHOLE DESIGN. The obvious way to make
# internal drives stop asking is to widen the no-password rule in
# 49-aquarius-udisks.rules. That is forbidden; the build stops on it. So this
# test also proves that the agent's inside-drive path never asks udisks2 to
# mount anything at all — it only ever puts a question on screen.
#
# WHAT IT CHECKS
#   The agent (/usr/libexec/aquarius-automount):
#     1. an ordinary inside data drive IS offered, exactly once, and the
#        question carries its UUID, label and filesystem
#     2. ⚠️ and offering it asks udisks2 to Mount NOTHING
#     3. the EFI partition is never offered
#     4. a partition of the disk AquariusOS is on is never offered
#     5. swap / LUKS / LVM / anything unrecognised is never offered
#     6. a drive with no UUID is never offered
#     7. a drive already mounted is never offered
#     8. a drive the person said "never ask" about is never offered again
#     9. a drive already in /etc/fstab is never offered
#    10. a REMOVABLE drive is not dragged into this path at all
#
#   The privileged helper (/usr/libexec/aquarius-remember-drive):
#    11. its rehearsal states the never-touch list out loud
#    12. it refuses a UUID that is not a UUID, and a filesystem it does not know
#    13. it refuses to do anything at all when it is not the administrator
#    14. the fstab options it builds are the designed ones — nofail and
#        x-systemd.automount always, and NTFS read-only
#    15. a drive label becomes a folder name that cannot surprise anybody
#    16. BitLocker is recognised from the volume's own signature, with no mount
#    17. "forget" removes ONLY a line AquariusOS wrote, never a hand-written one
#
# HOW TO RUN IT
#   ./tests/test-remember-drive.py
#   ./tests/test-remember-drive.py /usr/libexec/aquarius-automount \
#                                  /usr/libexec/aquarius-remember-drive
#
# It needs python3-gobject and nothing else. No bus, no drives, no root.
# =============================================================================

import importlib.machinery
import importlib.util
import os
import sys
import tempfile

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
# and says "that interface is not here" for anything it was not given.
# -----------------------------------------------------------------------------
class FakeBus:
    def __init__(self, GLib, interfaces):
        self.GLib = GLib
        self.interfaces = interfaces  # {iface: {prop: GLib.Variant}}
        self.calls = []

    def call_sync(self, name, path, iface, method, params, reply_type,
                  flags, timeout, cancellable):
        self.calls.append({"path": path, "iface": iface, "method": method})
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
        raise self.GLib.Error("the fake bus was asked for %s" % method)


BLOCK = "org.freedesktop.UDisks2.Block"
FS = "org.freedesktop.UDisks2.Filesystem"
PART = "org.freedesktop.UDisks2.Partition"
OBJ = "/org/freedesktop/UDisks2/block_devices/sdb1"


def block_props(GLib, device="/dev/sdb1", label="Footage", uuid="1234-ABCD-5678",
                fstype="ext4", hint_system=True, hint_ignore=False,
                mount_points=None):
    props = {
        "Device": GLib.Variant("ay", list(device.encode() + b"\x00")),
        "IdLabel": GLib.Variant("s", label),
        "IdUUID": GLib.Variant("s", uuid),
        "IdType": GLib.Variant("s", fstype),
        "HintSystem": GLib.Variant("b", hint_system),
        "HintIgnore": GLib.Variant("b", hint_ignore),
        "HintAuto": GLib.Variant("b", not hint_system),
    }
    fs = {"MountPoints": GLib.Variant("aay", mount_points or [])}
    return props, fs


def make_mounter(agent, GLib, interfaces, never=(), fstab_uuids=()):
    """An AutoMounter wired to a fake bus, with the two files faked out too."""
    bus = FakeBus(GLib, interfaces)
    mounter = agent.AutoMounter(bus)
    agent.never_ask_list = lambda: set(never)
    agent.uuid_in_fstab = lambda uuid: uuid in fstab_uuids
    spawned = []
    mounter.spawn = lambda argv: spawned.append(argv) or True
    return mounter, bus, spawned


def check_agent(path):
    import gi
    gi.require_version("GLib", "2.0")
    gi.require_version("Gio", "2.0")
    from gi.repository import GLib

    agent = load(path, "aquarius_automount")
    agent.log = lambda message: None
    # The real one reads /proc/self/mountinfo and would find THIS machine's
    # system disk, which has nothing to do with the fake drives below.
    agent.critical_disks = lambda: {"sda"}

    print("-- the agent: which inside drives get a question, and which never do --")

    # 1 & 2. An ordinary inside data drive.
    block, fs = block_props(GLib)
    mounter, bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs})
    mounter.maybe_offer(OBJ)
    if len(spawned) == 1 and spawned[0][2] == "--ask":
        argv = spawned[0]
        if argv[3:7] == ["1234-ABCD-5678", "Footage", "ext4", "/dev/sdb1"]:
            ok("an ordinary inside drive is offered once, with its UUID, label,"
               " filesystem and device")
        else:
            bad("the question was asked with %r" % (argv[3:7],))
    else:
        bad("an ordinary inside drive was not offered (spawned %r)" % (spawned,))

    # Asked twice — udisks2 routinely announces the same device more than once.
    mounter.maybe_offer(OBJ)
    if len(spawned) == 1:
        ok("and asking about it twice still puts only ONE question on screen")
    else:
        bad("the same drive was offered %d times" % len(spawned))

    if not [c for c in bus.calls if c["method"] == "Mount"]:
        ok("⚠️ and offering a drive asks udisks2 to Mount nothing at all — the"
           " narrow polkit rule is never exercised, let alone widened")
    else:
        bad("maybe_offer() asked udisks2 to Mount something. It must never do that.")

    # 3. The EFI partition.
    block, fs = block_props(GLib, device="/dev/sdb1", label="", fstype="vfat")
    part = {"Type": GLib.Variant("s", agent.EFI_PARTTYPE)}
    mounter, _bus, spawned = make_mounter(
        agent, GLib, {BLOCK: block, FS: fs, PART: part})
    mounter.maybe_offer(OBJ)
    if not spawned:
        ok("the EFI partition the computer boots from is never offered")
    else:
        bad("the EFI partition was offered: %r" % (spawned,))

    # 4. A partition of the disk AquariusOS is on.
    block, fs = block_props(GLib, device="/dev/sda3")
    mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs})
    mounter.maybe_offer("/org/freedesktop/UDisks2/block_devices/sda3")
    if not spawned:
        ok("a partition of the disk AquariusOS is installed on is never offered")
    else:
        bad("a partition of the system disk was offered: %r" % (spawned,))

    # 5. Things that are not filesystems people keep files on.
    for fstype in ("swap", "crypto_LUKS", "LVM2_member", "linux_raid_member",
                   "apfs", ""):
        block, fs = block_props(GLib, fstype=fstype)
        mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs})
        mounter.maybe_offer(OBJ)
        if spawned:
            bad("a %s partition was offered" % (fstype or "blank"))
            break
    else:
        ok("swap, LUKS, LVM, RAID, APFS and blank partitions are never offered")

    # 6. No UUID.
    block, fs = block_props(GLib, uuid="")
    mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs})
    mounter.maybe_offer(OBJ)
    if not spawned:
        ok("a drive with no UUID is never offered — there is no safe way to name it")
    else:
        bad("a drive with no UUID was offered")

    # 7. Already mounted.
    block, fs = block_props(GLib, mount_points=[list(b"/mnt/x\x00")])
    mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs})
    mounter.maybe_offer(OBJ)
    if not spawned:
        ok("a drive that is already open is never offered — the question would be noise")
    else:
        bad("an already-mounted drive was offered")

    # 8. "Never ask".
    block, fs = block_props(GLib)
    mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs},
                                          never=("1234-ABCD-5678",))
    mounter.maybe_offer(OBJ)
    if not spawned:
        ok("a drive the person said \"Never ask\" about is never offered again")
    else:
        bad("a \"never ask\" drive was offered anyway")

    # 9. Already in fstab.
    block, fs = block_props(GLib)
    mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs},
                                          fstab_uuids=("1234-ABCD-5678",))
    mounter.maybe_offer(OBJ)
    if not spawned:
        ok("a drive already named in /etc/fstab is never offered — it is already remembered")
    else:
        bad("a drive already in fstab was offered again")

    # 10. A removable drive belongs to the old path, not this one.
    block, fs = block_props(GLib, hint_system=False)
    mounter, _bus, spawned = make_mounter(agent, GLib, {BLOCK: block, FS: fs})
    mounter.maybe_offer(OBJ)
    if not spawned:
        ok("a REMOVABLE drive is not dragged into this path — it just mounts, as it always did")
    else:
        bad("a removable drive was offered a question it does not need")

    # And the rehearsal the build reads.
    import io
    import contextlib
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        agent.dry_run()
    said = buffer.getvalue()
    for phrase in ("Windows' system volume", "EFI partition",
                   "already in /etc/fstab", "READ-ONLY",
                   "49-aquarius-udisks.rules"):
        if phrase in said:
            continue
        bad("the agent's rehearsal does not mention %r" % phrase)
        break
    else:
        ok("the agent's rehearsal states the never-touch list out loud")


# -----------------------------------------------------------------------------
# The privileged helper
# -----------------------------------------------------------------------------
class FakeRun:
    """Stands in for subprocess, so nothing on this machine is really run."""

    def __init__(self):
        self.calls = []

    def run(self, argv, **kwargs):
        self.calls.append(argv)

        class Result:
            returncode = 0
            stdout = ""
            stderr = ""
        return Result()


def check_helper(path):
    helper = load(path, "aquarius_remember_drive")
    said = []
    helper.out = lambda message: said.append(str(message))
    helper.fail = lambda message: (said.append("ERROR " + str(message)), 1)[1]

    print("-- the privileged helper: what it refuses, and the line it writes --")

    # 11. The rehearsal.
    del said[:]
    helper.dry_run()
    rehearsal = "\n".join(said)
    for phrase in ("EFI partition", "Windows' system volume", "BitLocker",
                   "no UUID", "READ-ONLY", "49-aquarius-udisks.rules"):
        if phrase in rehearsal:
            continue
        bad("the helper's rehearsal does not mention %r" % phrase)
        break
    else:
        ok("the helper's rehearsal states the never-touch list out loud")

    # 13 (first, because it gates everything). Not the administrator.
    #
    # The build runs this test as root inside the build container, so we cannot
    # simply "be" a normal user here. Instead we hand the helper a stand-in for
    # the one question it asks — "who am I running as?" — and have that stand-in
    # answer with an ordinary user's number (1000) instead of root's 0. That is
    # the honest test: the helper's real refusal code runs, and it must refuse
    # BEFORE it looks at the UUID or touches any disk.
    real_geteuid = helper.os.geteuid
    helper.os.geteuid = lambda: 1000
    del said[:]
    code = helper.do_remember("1234-ABCD-5678", "Footage", "ext4", 1000, 1000)
    if code != 0 and "administrator" in "\n".join(said):
        ok("it refuses to do anything at all when it is not the administrator")
    else:
        bad("a non-root 'remember' was not refused: %r" % said)

    # From here on, pretend to be root but keep it away from the real machine.
    helper.os.geteuid = lambda: 0
    fake = FakeRun()
    real_subprocess = helper.subprocess
    helper.subprocess = fake
    try:
        # 12. Nonsense arguments.
        del said[:]
        if helper.do_remember("not a uuid; rm -rf /", "x", "ext4", 1000, 1000) != 0:
            ok("it refuses anything that is not a filesystem UUID")
        else:
            bad("it accepted a UUID that is not one")

        del said[:]
        if helper.do_remember("1234-ABCD-5678", "x", "swap", 1000, 1000) != 0:
            ok("it refuses a filesystem it does not know how to remember (swap, LUKS, …)")
        else:
            bad("it accepted 'swap' as something to remember")

        # 14. The options.
        common = helper.COMMON_OPTIONS
        for needed in ("nofail", "x-systemd.automount", "x-systemd.device-timeout=10"):
            if needed not in common:
                bad("the shared options are missing %s" % needed)
                break
        else:
            ok("every remembered drive gets nofail, x-systemd.automount and a"
               " ten-second timeout — a missing drive can never stop the computer starting")

        ntfs = helper.options_for("ntfs", 1000, 1000)
        if ",ro," in ntfs or ntfs.endswith(",ro"):
            ok("an NTFS drive is remembered READ-ONLY (Windows' fast startup leaves it dirty)")
        else:
            bad("NTFS is not read-only: %s" % ntfs)
        if "uid=1000" in ntfs and "uid=" not in helper.options_for("ext4", 1000, 1000):
            ok("Windows and camera filesystems are handed to the person who uses"
               " the computer; ext4 and friends keep their own ownership")
        else:
            bad("the ownership options are wrong: ntfs=%s ext4=%s"
                % (ntfs, helper.options_for("ext4", 1000, 1000)))
        if helper.fstab_type("ntfs") == "ntfs-3g":
            ok("NTFS is written into fstab as ntfs-3g — the driver this image really ships")
        else:
            bad("fstab_type('ntfs') is %r" % helper.fstab_type("ntfs"))

        # 15. Folder names.
        cases = {
            "Footage": "Footage",
            "My Drive/../etc": "My Drive-..-etc",
            "": "Drive-1234-ABC",
            "  ": "Drive-1234-ABC",
        }
        for label, expected in cases.items():
            got = helper.safe_folder_name(label, "1234-ABCD-5678")
            if got != expected:
                bad("safe_folder_name(%r) is %r, expected %r" % (label, got, expected))
                break
        else:
            ok("a drive's label becomes a folder name with no slashes and no surprises")

        if helper.fstab_escape("My Drive") == "My\\040Drive":
            ok("a space in a drive name is escaped the way fstab needs it")
        else:
            bad("fstab_escape is wrong: %r" % helper.fstab_escape("My Drive"))

        # 16. BitLocker, read straight off the volume.
        with tempfile.NamedTemporaryFile(delete=False) as handle:
            handle.write(b"\xeb\x58\x90" + b"-FVE-FS-" + b"\x00" * 100)
            locked = handle.name
        with tempfile.NamedTemporaryFile(delete=False) as handle:
            handle.write(b"\xeb\x52\x90" + b"NTFS    " + b"\x00" * 100)
            plain = handle.name
        try:
            if helper.looks_like_bitlocker(locked) and not helper.looks_like_bitlocker(plain):
                ok("BitLocker is recognised from the volume's own signature — nothing is mounted to find out")
            else:
                bad("the BitLocker check is wrong (locked=%s plain=%s)"
                    % (helper.looks_like_bitlocker(locked),
                       helper.looks_like_bitlocker(plain)))
            if helper.looks_like_bitlocker("/dev/definitely-not-there"):
                ok("and a volume it cannot read at all is refused, not waved through")
            else:
                bad("an unreadable volume was treated as safe")
        finally:
            os.unlink(locked)
            os.unlink(plain)

        # 17. forget touches only our own lines.
        with tempfile.NamedTemporaryFile("w", suffix=".fstab", delete=False) as handle:
            handle.write(
                "UUID=aaaa-bbbb / ext4 defaults 0 0\n"
                "UUID=1234-ABCD-5678 /mnt/hand-written ext4 defaults 0 0\n"
                "UUID=9999-8888 /media/aquarius/Footage ext4 %s 0 0 %s\n"
                % (helper.COMMON_OPTIONS, helper.TAG))
            fstab = handle.name
        real_fstab = helper.FSTAB
        helper.FSTAB = fstab
        try:
            del said[:]
            if helper.do_forget("1234-ABCD-5678") != 0:
                ok("'forget' refuses a drive AquariusOS never wrote — a"
                   " hand-written fstab line is nobody's business but its author's")
            else:
                bad("'forget' removed a line AquariusOS did not write")

            del said[:]
            if helper.do_forget("9999-8888") == 0:
                left = open(fstab).read()
                if helper.TAG not in left and "/mnt/hand-written" in left and "UUID=aaaa-bbbb" in left:
                    ok("'forget' removes our own line and leaves every other line alone")
                else:
                    bad("fstab after forget is:\n%s" % left)
            else:
                bad("'forget' could not remove our own line: %r" % said)

            # And the fstab reader used to decide "is it already remembered".
            if helper.fstab_mentions("aaaa-bbbb", "/nowhere") \
                    and helper.fstab_mentions("0000-0000", "/mnt/hand-written") \
                    and not helper.fstab_mentions("0000-0000", "/nowhere"):
                ok("a drive already in fstab — by UUID or by folder — is seen as already remembered")
            else:
                bad("fstab_mentions() does not answer correctly")
        finally:
            helper.FSTAB = real_fstab
            os.unlink(fstab)
    finally:
        helper.os.geteuid = real_geteuid
        helper.subprocess = real_subprocess


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    agent = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.join(
        here, "..", "system_files", "usr", "libexec", "aquarius-automount")
    helper = os.path.abspath(argv[2]) if len(argv) > 2 else os.path.join(
        here, "..", "system_files", "usr", "libexec", "aquarius-remember-drive")
    agent = os.path.abspath(agent)
    helper = os.path.abspath(helper)

    print("== an inside drive asks once, and never the wrong drive ==")
    print("   agent:  %s" % agent)
    print("   helper: %s" % helper)

    for path in (agent, helper):
        if not os.path.isfile(path):
            print("FAIL %s is not there — nothing to test." % path, file=sys.stderr)
            return 1

    try:
        import gi  # noqa: F401
    except Exception as error:  # noqa: BLE001
        print("FAIL python3-gobject is not usable here: %s" % error, file=sys.stderr)
        return 1

    check_agent(agent)
    check_helper(helper)

    print("")
    if FAILS:
        print("%d check(s) failed." % len(FAILS), file=sys.stderr)
        return 1
    print("All remembered-drive checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
