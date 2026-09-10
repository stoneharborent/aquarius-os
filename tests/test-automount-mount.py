#!/usr/bin/python3
# =============================================================================
# test-automount-mount.py — a drive plugged in really does get mounted
# =============================================================================
# WHAT THIS PROVES, AND THE FAULT IT COMES FROM
#
# ⚠️ THE BENCH FAULT OF 8 SEPTEMBER 2026. Royce plugged in his drives and they
# appeared in the Files app but not in the dock. That looked like a dock
# problem. It was not: /usr/libexec/aquarius-automount crashed on EVERY single
# mount, with
#
#     File ".../gi/overrides/GLib.py", line 396, in __getitem__
#     KeyError: 0
#
# — and the two drives sitting in /run/media had been mounted by Files, not by
# us. One line of the agent built the argument for udisks2's Mount method the
# wrong way round: it wrapped a GLib.Variant inside another GLib.Variant, where
# PyGObject expects a plain Python dictionary and walks it itself.
#
# ⚠️ AND WHY THE BUILD DID NOT CATCH IT. build_files/76-automount.sh ran
# `py_compile` on the agent and imported `gi`. Both passed — the broken line was
# perfectly valid Python, and the fault only exists at the moment PyGObject
# actually builds the value. Nothing on the machine ever called mount() in CI.
#
# So this test calls mount() for real, against a FAKE bus, on a machine with no
# udisks2 and no drives. The Variant is genuinely constructed by the PyGObject
# that ships in this image, which is the only thing that can tell us the shape
# is right.
#
# WHAT IT CHECKS
#   1. mount() reaches the bus at all — i.e. it does not blow up before it asks.
#   2. It asks org.freedesktop.UDisks2.Filesystem.Mount, on the right object.
#   3. The argument it sends really is `(a{sv})` and really carries
#      auth.no_user_interaction = true — the option that stops a password box
#      appearing for a drive somebody just plugged in.
#   4. A successful mount logs one plain line naming the drive and where it went.
#   5. A REFUSED mount logs one plain line and does not raise. A drive that
#      cannot be mounted must never take the agent down with it.
#   6. "Already mounted" is not reported as a fault, because it is a race and
#      not one.
#   7. ⚠️ And the outermost net: an unexpected error inside mount() — the exact
#      class of thing the KeyError was — is caught by consider(), logged as one
#      sentence, and the agent carries on.
#
# =============================================================================
# AND THE SECOND HALF: MAC DRIVES (APFS)
# =============================================================================
# Added 2026-09-09 with the Mac-drive feature. A Mac drive is the ONE kind this
# computer cannot hand to udisks2 — Linux has no APFS, so udisks2 has nothing to
# mount it with — so the agent runs apfs-fuse itself, as the person, read-only.
#
# Every part of that is unrunnable on a build machine: there is no Mac drive, no
# FUSE, no root, and no udisks2. So all of it is faked, and what is checked is
# the two things a fake CAN prove and a person cannot check by reading:
#
#   8.  the parser really reads what apfsutil really prints. The inputs are
#       three captured listings kept beside this file — an ordinary external
#       drive, a Mac's internal disk with its five volumes, and a FileVault
#       drive — so a future apfs-fuse that changed its output would be caught
#       here rather than by a drive that quietly never appears.
#   9.  an APFS drive takes the Mac path and NEVER asks udisks2 to mount it.
#       (udisks2 would refuse, log nothing a person could read, and the drive
#       would simply not turn up.)
#   10. the apfs-fuse command line is EXACTLY the designed one: read-only, this
#       person's uid and gid, subtype=apfs — and no allow_other, which would
#       hand the drive to every account on the machine.
#   11. a FileVault volume is NOT mounted and NOT silent: the notification
#       helper is started instead, and nothing is mounted.
#   12. Apple's own machinery volumes (Preboot, Recovery, VM) are left alone.
#   13. a drive that is already open is not opened twice.
#   14. unplugging the drive really closes the mount and takes the empty folder
#       away — because nothing else on the computer will. Every other drive is
#       udisks2's to clean up; this one is ours.
#
# HOW TO RUN IT
#   ./tests/test-automount-mount.py
#   ./tests/test-automount-mount.py /usr/libexec/aquarius-automount
#
# It needs python3-gobject and nothing else. No bus, no drives, no screen —
# which is why it can run before the image is even built.
# =============================================================================

import importlib.util
import os
import shutil
import sys
import tempfile

# Never write bytecode next to the agent: inside the image build that would
# leave /usr/libexec/__pycache__ behind, and the image check refuses that.
sys.dont_write_bytecode = True

FAILS = []


def ok(msg):
    print("  OK   %s" % msg)


def bad(msg):
    print("  FAIL %s" % msg, file=sys.stderr)
    FAILS.append(msg)


def load_agent(path):
    """Import the agent as a module, without running it.

    The agent has no .py on the end of its name (it lives in /usr/libexec and is
    run as a command), so it cannot simply be imported. This loads it from its
    path. It is written so that importing it does nothing at all: everything is
    behind `if __name__ == "__main__"`.
    """
    spec = importlib.util.spec_from_loader(
        "aquarius_automount",
        importlib.machinery.SourceFileLoader("aquarius_automount", path),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeError(Exception):
    """Stands in for GLib.Error, which cannot be raised from Python directly."""


class FakeBus:
    """A stand-in for the system bus that writes down what it was asked.

    It answers property reads with whatever is in `props`, and answers Mount
    with `mount_reply` — or raises, if `mount_raises` is set.
    """

    def __init__(self, GLib, props=None, mount_reply="/run/media/tester/SHOOT-2026",
                 mount_raises=None):
        self.GLib = GLib
        self.props = props or {}
        self.mount_reply = mount_reply
        self.mount_raises = mount_raises
        self.calls = []

    def call_sync(self, name, path, iface, method, params, reply_type,
                  flags, timeout, cancellable):
        self.calls.append(
            {"path": path, "iface": iface, "method": method, "params": params}
        )
        if method == "Get":
            prop = params.unpack()[1]
            value = self.props.get(prop)
            if value is None:
                raise self.GLib.Error("no such property")
            return self.GLib.Variant("(v)", (value,))
        if method == "Mount":
            if self.mount_raises is not None:
                raise self.mount_raises
            return self.GLib.Variant("(s)", (self.mount_reply,))
        raise self.GLib.Error("the fake bus was asked for %s" % method)


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "system_files", "usr", "libexec", "aquarius-automount",
    )
    path = os.path.abspath(path)

    print("== a drive plugged in really does get mounted ==")
    print("   agent under test: %s" % path)

    if not os.path.isfile(path):
        print("FAIL %s is not there — nothing to test." % path, file=sys.stderr)
        return 1

    try:
        import gi
        gi.require_version("GLib", "2.0")
        gi.require_version("Gio", "2.0")
        from gi.repository import GLib
    except Exception as error:  # noqa: BLE001
        print("FAIL python3-gobject is not usable here: %s" % error, file=sys.stderr)
        print("     This test needs the same GLib the agent uses; without it it", file=sys.stderr)
        print("     would prove nothing, so it fails rather than passing quietly.", file=sys.stderr)
        return 1

    agent = load_agent(path)

    # Everything the agent prints is collected, so the log lines can be checked
    # as carefully as the behaviour. A silent failure is the thing this whole
    # exercise is about.
    lines = []
    agent.log = lambda message: lines.append(str(message))

    # ------------------------------------------------------------------------
    # 1–4. A mount that works
    # ------------------------------------------------------------------------
    label = GLib.Variant("s", "SHOOT-2026")
    device = GLib.Variant("ay", list(b"/dev/sdb1\x00"))
    bus = FakeBus(GLib, props={"IdLabel": label, "Device": device})
    mounter = agent.AutoMounter(bus)

    del lines[:]
    try:
        mounter.mount("/org/freedesktop/UDisks2/block_devices/sdb1")
    except Exception as error:  # noqa: BLE001
        bad("mount() raised %s: %s — this is the 2026-09-08 fault, exactly"
            % (type(error).__name__, error))
        # Everything below depends on mount() working, so stop here rather than
        # printing a page of consequences of one cause.
        print("")
        print("::error::aquarius-automount cannot mount a drive. See "
              "docs/restart/hardware.md.")
        return 1

    mount_calls = [c for c in bus.calls if c["method"] == "Mount"]
    if len(mount_calls) == 1:
        ok("mount() asks udisks2 to Mount, exactly once")
    else:
        bad("mount() made %d Mount calls, expected 1" % len(mount_calls))

    if mount_calls:
        call = mount_calls[0]
        if call["iface"] == "org.freedesktop.UDisks2.Filesystem":
            ok("it asks on the Filesystem interface")
        else:
            bad("it asked on interface %s" % call["iface"])
        if call["path"].endswith("/sdb1"):
            ok("it asks about the drive it was given")
        else:
            bad("it asked about %s" % call["path"])

        # ⚠️ THE LINE THAT WAS WRONG. The type string is the whole point of this
        # test: `(a{sv})` and nothing else.
        params = call["params"]
        type_string = params.get_type_string()
        if type_string == "(a{sv})":
            ok("the argument it sends is (a{sv}) — one dictionary of options")
        else:
            bad("the argument it sends is %s, not (a{sv})" % type_string)

        unpacked = params.unpack()[0]
        if unpacked.get("auth.no_user_interaction") is True:
            ok("and it carries auth.no_user_interaction = true, so no password box appears")
        else:
            bad("auth.no_user_interaction is %r — a drive could pop a password box"
                % unpacked.get("auth.no_user_interaction"))

    joined = "\n".join(lines)
    if "SHOOT-2026" in joined and "/run/media/tester/SHOOT-2026" in joined:
        ok("it logs one plain line naming the drive and where it went")
    else:
        bad("the log does not say what was mounted where. It said:\n%s" % joined)
    if any(line.startswith("mounting ") for line in lines):
        ok("and one line when the attempt STARTS, so a refusal is not silent")
    else:
        bad("nothing was logged before the attempt — a hung mount would be invisible")

    # ------------------------------------------------------------------------
    # 5. A mount that is refused
    # ------------------------------------------------------------------------
    refused = GLib.Error.new_literal(
        GLib.quark_from_string("g-dbus-error-quark"),
        "GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorized: Not authorized",
        1,
    )
    bus = FakeBus(GLib, props={"IdLabel": label, "Device": device},
                  mount_raises=refused)
    mounter = agent.AutoMounter(bus)
    del lines[:]
    try:
        mounter.mount("/org/freedesktop/UDisks2/block_devices/sdb1")
        joined = "\n".join(lines)
        if "could not mount" in joined and "SHOOT-2026" in joined:
            ok("a refused mount logs one plain line naming the drive, and does not raise")
        else:
            bad("a refused mount said: %s" % joined)
    except Exception as error:  # noqa: BLE001
        bad("a refused mount raised %s — one bad drive would take the agent down"
            % type(error).__name__)

    # ------------------------------------------------------------------------
    # 6. Already mounted is not a fault
    # ------------------------------------------------------------------------
    already = GLib.Error.new_literal(
        GLib.quark_from_string("g-dbus-error-quark"),
        "GDBus.Error:org.freedesktop.UDisks2.Error.AlreadyMounted: Already mounted",
        1,
    )
    bus = FakeBus(GLib, props={"IdLabel": label, "Device": device},
                  mount_raises=already)
    mounter = agent.AutoMounter(bus)
    del lines[:]
    mounter.mount("/org/freedesktop/UDisks2/block_devices/sdb1")
    joined = "\n".join(lines)
    if "could not mount" in joined:
        bad("'already mounted' was reported as a failure; it is a race, not a fault")
    else:
        ok("'already mounted' is not reported as a failure")

    # ------------------------------------------------------------------------
    # 7. ⚠️ The outermost net: an unexpected error must not take the agent down
    # ------------------------------------------------------------------------
    # This is the shape of the 2026-09-08 fault itself: an exception that is NOT
    # a GLib.Error, escaping mount(). consider() has to turn it into one plain
    # sentence and carry on, so that the next drive plugged in still works.
    class ExplodingMounter(agent.AutoMounter):
        def should_mount(self, object_path):
            return True

        def mount(self, object_path):
            raise KeyError(0)

    mounter = ExplodingMounter(FakeBus(GLib))
    del lines[:]
    try:
        mounter.consider("/org/freedesktop/UDisks2/block_devices/sdb1")
        joined = "\n".join(lines)
        if "could not deal with" in joined:
            ok("an unexpected error is caught, said in one sentence, and survived")
        else:
            bad("an unexpected error was swallowed silently. The log said: %s" % joined)
    except Exception as error:  # noqa: BLE001
        bad("an unexpected error escaped consider() as %s — the exact 2026-09-08 shape"
            % type(error).__name__)

    # ------------------------------------------------------------------------
    # 8–14. Mac drives (APFS)
    # ------------------------------------------------------------------------
    mac_drives(agent, GLib, lines)

    print("")
    if FAILS:
        print("::error::aquarius-automount would not mount drives correctly "
              "(%d check(s) failed). See docs/restart/mac-drives.md and "
              "docs/restart/hardware.md." % len(FAILS))
        return 1
    print("All automount mount checks passed.")
    return 0


# =============================================================================
# Mac drives (APFS) — the whole second half
# =============================================================================
FIXTURES = os.path.dirname(os.path.abspath(__file__))


def fixture(name):
    with open(os.path.join(FIXTURES, name), "r") as handle:
        return handle.read()


class Recorder:
    """Stands in for every program the agent runs, and writes down every call.

    The agent funnels EVERYTHING it runs through two methods — run() and
    spawn() — precisely so that this can exist. Nothing here needs a Mac drive,
    FUSE, root or a screen.
    """

    def __init__(self, apfsutil_output="", fuse_code=0, fuse_error=""):
        self.calls = []
        self.spawned = []
        self.apfsutil_output = apfsutil_output
        self.fuse_code = fuse_code
        self.fuse_error = fuse_error

    def run(self, argv, timeout=120):
        del timeout
        self.calls.append(list(argv))
        program = os.path.basename(argv[0])
        if program == "apfsutil":
            return 0, self.apfsutil_output, ""
        if program == "apfs-fuse":
            return self.fuse_code, "", self.fuse_error
        return 0, "", ""

    def spawn(self, argv):
        self.spawned.append(list(argv))
        return True

    def named(self, program):
        return [call for call in self.calls if os.path.basename(call[0]) == program]


def apfs_bus(agent, GLib, device=b"/dev/sdz1\x00", label="SHOOT 2026",
             hint_system=False):
    """A fake udisks2 answering the way it answers for a plugged-in Mac drive."""
    del agent
    return FakeBus(GLib, props={
        "IdType": GLib.Variant("s", "apfs"),
        "IdLabel": GLib.Variant("s", label),
        "Device": GLib.Variant("ay", list(device)),
        "HintAuto": GLib.Variant("b", True),
        "HintIgnore": GLib.Variant("b", False),
        "HintSystem": GLib.Variant("b", hint_system),
    })


OBJECT = "/org/freedesktop/UDisks2/block_devices/sdz1"


def mac_drives(agent, GLib, lines):
    print("")
    print("== a Mac drive (APFS) is read, read-only, and put away again ==")

    # --- 8. the parser, against three real apfsutil listings ----------------
    apfs = agent.aquarius_apfs

    single = apfs.parse_apfsutil(fixture("apfsutil-external-drive.fixture"))
    if len(single) == 1 and single[0].name == "SHOOT 2026" and not single[0].encrypted:
        ok("an ordinary Mac drive reads as one unlocked volume called SHOOT 2026")
    else:
        bad("an ordinary Mac drive was read as %r" % (single,))
    if single and single[0].display_name == "SHOOT 2026":
        ok("and the '(Case-insensitive)' apfsutil prints after the name is not"
           " part of the folder name")
    else:
        bad("the case-sensitivity note leaked into the name: %r"
            % (single[0].display_name if single else None))

    boot = apfs.parse_apfsutil(fixture("apfsutil-mac-boot.fixture"))
    if len(boot) == 5:
        ok("a Mac's internal disk reads as five volumes")
    else:
        bad("a Mac's internal disk read as %d volume(s), expected 5" % len(boot))
    wanted = [volume.display_name for volume in boot if volume.should_mount]
    if wanted == ["Macintosh HD", "Macintosh HD - Data"]:
        ok("and only the two a person would open: %s" % ", ".join(wanted))
    else:
        bad("the volumes we would mount are %r — Preboot, Recovery and VM are"
            " Apple's own machinery and must be left alone" % (wanted,))

    locked = apfs.parse_apfsutil(fixture("apfsutil-encrypted.fixture"))
    if len(locked) == 1 and locked[0].encrypted and locked[0].display_name == "Archive":
        ok("a FileVault drive reads as locked, and its NAME is still readable"
           " (which is what lets us say which drive is locked)")
    else:
        bad("a FileVault drive was read as %r" % (locked,))

    # --- the fake machine everything below runs on --------------------------
    work = tempfile.mkdtemp(prefix="aq-apfs-test-")
    media = os.path.join(work, "run", "media", "tester")
    os.makedirs(media)
    mountinfo = os.path.join(work, "mountinfo")
    with open(mountinfo, "w") as handle:
        handle.write("25 1 8:2 / / rw,relatime shared:1 - btrfs /dev/sda2 rw\n")
    os.environ["AQ_MEDIA_ROOT"] = media
    os.environ["AQ_MOUNTINFO"] = mountinfo

    try:
        _mac_drive_cases(agent, GLib, lines, media, mountinfo)
    finally:
        os.environ.pop("AQ_MEDIA_ROOT", None)
        os.environ.pop("AQ_MOUNTINFO", None)
        shutil.rmtree(work, ignore_errors=True)


def _mac_drive_cases(agent, GLib, lines, media, mountinfo):
    uid, gid = os.getuid(), os.getgid()
    expected_options = "ro,uid=%d,gid=%d,subtype=apfs" % (uid, gid)

    # --- 9 & 10. one ordinary Mac drive -------------------------------------
    bus = apfs_bus(agent, GLib)
    mounter = agent.AutoMounter(bus)
    rec = Recorder(apfsutil_output=fixture("apfsutil-external-drive.fixture"))
    mounter.run, mounter.spawn = rec.run, rec.spawn
    del lines[:]
    mounter.consider(OBJECT)

    if not [call for call in bus.calls if call["method"] == "Mount"]:
        ok("a Mac drive never asks udisks2 to Mount — udisks2 has no APFS and"
           " would refuse, leaving the drive silently missing")
    else:
        bad("a Mac drive was handed to udisks2's Mount, which cannot mount APFS")

    utils = rec.named("apfsutil")
    if len(utils) == 1 and utils[0][1] == "/dev/sdz1":
        ok("it asks apfsutil what is on the drive, once")
    else:
        bad("apfsutil was called %d time(s): %r" % (len(utils), utils))

    fuses = rec.named("apfs-fuse")
    if len(fuses) == 1:
        ok("it mounts exactly one volume")
        expected = [
            agent.aquarius_apfs.APFS_FUSE, "-v", "0",
            "-o", expected_options,
            "/dev/sdz1", os.path.join(media, "SHOOT 2026"),
        ]
        if fuses[0] == expected:
            ok("and the command line is exactly the designed one: read-only,"
               " this person's uid and gid, subtype=apfs")
        else:
            bad("the command line is\n         %r\n       expected\n         %r"
                % (fuses[0], expected))
        # ⚠️ Said again as its own check, because it is the one option whose
        # presence would quietly widen this from "my drive" to "everybody's".
        if "allow_other" not in " ".join(fuses[0]):
            ok("and it does NOT pass allow_other — the drive is the person's own,"
               " not every account's")
        else:
            bad("the command line passes allow_other, which hands the drive to"
                " every account on the computer and needs /etc/fuse.conf changed")
    else:
        bad("apfs-fuse was called %d time(s), expected 1: %r" % (len(fuses), fuses))

    if os.path.isdir(os.path.join(media, "SHOOT 2026")):
        ok("the folder it mounts onto is /run/media/<user>/SHOOT 2026 — exactly"
           " where udisks2 puts everything else, which is what the dock watches")
    else:
        bad("no folder was made at %s" % os.path.join(media, "SHOOT 2026"))

    joined = "\n".join(lines)
    if "read-only" in joined and "SHOOT 2026" in joined:
        ok("and it says in the journal, in one plain line, that it is read-only")
    else:
        bad("the journal does not say what happened. It said:\n%s" % joined)

    # --- 14. unplugging it --------------------------------------------------
    del lines[:]
    rec.calls[:] = []
    mounter._on_interfaces_removed(
        None, None, None, None, None,
        GLib.Variant("(oas)", (OBJECT, ["org.freedesktop.UDisks2.Block"])))

    unmounts = rec.named("fusermount3")
    if len(unmounts) == 1 and unmounts[0][1:3] == ["-u", "-z"]:
        ok("unplugging the drive closes the mount with fusermount3 -u -z")
    else:
        bad("unplugging the drive ran %r — nothing else on this computer will"
            " ever close a mount we made" % (unmounts,))
    if not os.path.exists(os.path.join(media, "SHOOT 2026")):
        ok("and takes the empty folder away, so the dock does not keep a tile"
           " that opens onto nothing")
    else:
        bad("the folder %s was left behind after the drive was unplugged"
            % os.path.join(media, "SHOOT 2026"))

    # --- 11. a locked (FileVault) drive -------------------------------------
    bus = apfs_bus(agent, GLib, label="Archive")
    mounter = agent.AutoMounter(bus)
    rec = Recorder(apfsutil_output=fixture("apfsutil-encrypted.fixture"))
    mounter.run, mounter.spawn = rec.run, rec.spawn
    del lines[:]
    mounter.consider(OBJECT)

    if not rec.named("apfs-fuse"):
        ok("a FileVault drive is not mounted (it cannot be, without the password)")
    else:
        bad("a locked drive was handed to apfs-fuse, which would sit waiting for"
            " a password on a terminal that is not there")
    if len(rec.spawned) == 1 and rec.spawned[0][1] == "--notify" \
            and rec.spawned[0][-1] == "Archive":
        ok("and it is NOT silent: %s --notify is started, naming the drive"
           % os.path.basename(rec.spawned[0][0]))
    else:
        bad("a locked drive started %r — a drive that does not appear and says"
            " nothing is the worst outcome this feature can produce"
            % (rec.spawned,))
    joined = "\n".join(lines)
    if "FileVault" in joined:
        ok("and the journal says the word FileVault, so the reason is findable")
    else:
        bad("the journal does not mention FileVault. It said:\n%s" % joined)

    # --- 12. a Mac's own internal disk --------------------------------------
    bus = apfs_bus(agent, GLib, label="Macintosh HD")
    mounter = agent.AutoMounter(bus)
    rec = Recorder(apfsutil_output=fixture("apfsutil-mac-boot.fixture"))
    mounter.run, mounter.spawn = rec.run, rec.spawn
    del lines[:]
    mounter.consider(OBJECT)

    mounted = [call[-1] for call in rec.named("apfs-fuse")]
    expected = [os.path.join(media, "Macintosh HD"),
                os.path.join(media, "Macintosh HD - Data")]
    if mounted == expected:
        ok("a Mac's internal disk opens its two real volumes and leaves Preboot,"
           " Recovery and VM alone")
    else:
        bad("a Mac's internal disk mounted %r, expected %r" % (mounted, expected))

    # --- 13. a drive that is already open -----------------------------------
    with open(mountinfo, "a") as handle:
        handle.write("60 25 0:52 / %s ro,nosuid,nodev,relatime - fuse.apfs"
                     " /dev/sdz1 ro,user_id=%d,group_id=%d\n"
                     % (os.path.join(media, "SHOOT 2026").replace(" ", "\\040"),
                        os.getuid(), os.getgid()))
    bus = apfs_bus(agent, GLib)
    mounter = agent.AutoMounter(bus)
    rec = Recorder(apfsutil_output=fixture("apfsutil-external-drive.fixture"))
    mounter.run, mounter.spawn = rec.run, rec.spawn
    del lines[:]
    mounter.consider(OBJECT)
    if not rec.calls:
        ok("a drive that is already open is left alone — it is not mounted twice")
    else:
        bad("a drive already open was opened again: %r" % (rec.calls,))
    joined = "\n".join(lines)
    if "already open" in joined:
        ok("and it says so, rather than saying nothing")
    else:
        bad("nothing was logged about the drive already being open: %s" % joined)

    # --- the seatbelt still applies to Mac drives ---------------------------
    bus = apfs_bus(agent, GLib, hint_system=True)
    mounter = agent.AutoMounter(bus)
    rec = Recorder(apfsutil_output=fixture("apfsutil-external-drive.fixture"))
    mounter.run, mounter.spawn = rec.run, rec.spawn
    del lines[:]
    mounter.consider(OBJECT)
    if not rec.calls:
        ok("⚠️ a device udisks2 calls SYSTEM-INTERNAL is refused on the Mac path"
           " too, exactly as on the udisks2 path")
    else:
        bad("a system-internal device was opened as a Mac drive: %r" % (rec.calls,))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
