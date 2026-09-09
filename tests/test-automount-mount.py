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
# HOW TO RUN IT
#   ./tests/test-automount-mount.py
#   ./tests/test-automount-mount.py /usr/libexec/aquarius-automount
#
# It needs python3-gobject and nothing else. No bus, no drives, no screen —
# which is why it can run before the image is even built.
# =============================================================================

import importlib.util
import os
import sys

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

    print("")
    if FAILS:
        print("::error::aquarius-automount would not mount drives correctly "
              "(%d check(s) failed). See docs/restart/hardware.md." % len(FAILS))
        return 1
    print("All automount mount checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
