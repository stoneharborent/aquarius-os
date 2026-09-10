#!/usr/bin/python3
"""Exercise real notify-send against a private notification bus; open no windows."""
import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch

# Never acquire the user's live notification service name.
if sys.argv[1:] != ["--private-bus"]:
    raise SystemExit(subprocess.run([
        "dbus-run-session", "--", sys.executable, __file__, "--private-bus",
    ], timeout=20).returncode)

from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("extract_zip", str(ROOT / "system_files/usr/libexec/aquarius-extract-zip"))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)
INTERFACE = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
XML = '''<node><interface name="org.freedesktop.Notifications">
<method name="GetCapabilities"><arg type="as" direction="out"/></method>
<method name="GetServerInformation"><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/></method>
<method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/></method>
<method name="CloseNotification"><arg type="u" direction="in"/></method>
<signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
<signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
</interface></node>'''
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", GLib.Variant("(su)", (INTERFACE, 0)), None, Gio.DBusCallFlags.NONE, -1, None)
received = []
opened = []
errors = []
action = [True]
loop = GLib.MainLoop()


def close_notification():
    if action[0]:
        bus.emit_signal(None, PATH, INTERFACE, "ActionInvoked", GLib.Variant("(us)", (42, "show")))
    bus.emit_signal(None, PATH, INTERFACE, "NotificationClosed", GLib.Variant("(uu)", (42, 2)))
    return GLib.SOURCE_REMOVE


def method(connection, sender, path, interface, name, params, invocation):
    if name == "GetCapabilities":
        invocation.return_value(GLib.Variant("(as)", (["actions", "body"],)))
    elif name == "GetServerInformation":
        invocation.return_value(GLib.Variant("(ssss)", ("ZIP test", "AquariusOS", "1", "1.2")))
    elif name == "Notify":
        received.append(params.unpack())
        invocation.return_value(GLib.Variant("(u)", (42,)))
        GLib.timeout_add(100, close_notification)
    else:
        invocation.return_value(None)


registration = bus.register_object(PATH, Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], method, None, None)
real_run = subprocess.run


def intercept_open(args, **kwargs):
    if args[0] == "/usr/bin/xdg-open":
        opened.append(args)
        return subprocess.CompletedProcess(args, 0)
    return real_run(args, **kwargs)


def exercise():
    try:
        with tempfile.TemporaryDirectory(prefix="ZIP $ & spaces ") as temp:
            with patch.object(helper.subprocess, "run", side_effect=intercept_open):
                assert helper.completion_notification(temp, "ZIP extracted", "Done") == 0
                assert received[-1][5] == ["show", "Show extracted files"], received
                assert opened == [["/usr/bin/xdg-open", Path(temp).as_uri()]], opened
                action[0] = False
                assert helper.completion_notification(temp, "ZIP extracted", "Done") == 0
                assert len(opened) == 1, opened
        print("PASS: real notify-send action label/key, ActionInvoked opens exact folder URI, dismissal opens nothing")
    except BaseException as error:
        errors.append(error)
    finally:
        GLib.idle_add(loop.quit)


thread = threading.Thread(target=exercise)
thread.start()
loop.run()
thread.join()
bus.unregister_object(registration)
if errors:
    raise errors[0]
