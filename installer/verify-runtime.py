#!/usr/bin/python3
"""Fail the ISO build if the handheld installer lost its input support."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
for name in (
    'usr/share/aquarius/installer/wordmark.png',
    'usr/share/aquarius/installer/setup.css',
    'etc/anaconda/conf.d/99-aquarius.conf',
    'usr/bin/inputplumber', 'usr/bin/gnome-shell', 'usr/bin/ibus-daemon',
    'usr/bin/setfacl',
    'usr/share/gnome-shell/extensions/installer@aquariusos/extension.js',
    'usr/share/gnome-shell/extensions/installer@aquariusos/metadata.json',
    'usr/lib/systemd/system/anaconda.service.d/60-aquarius-handheld.conf',
    'usr/libexec/aquarius-installer-compositor',
    'usr/libexec/aquarius-installer-input',
    'usr/libexec/aquarius-ally-controller',
    'usr/share/aquarius/installer-handheld',
    'usr/share/inputplumber/capability_maps/aquarius_ally_x_dinput.yaml',
    'usr/share/dbus-1/system.d/org.shadowblip.InputPlumber.conf',
):
    if not (root / name).is_file():
        raise SystemExit(f'Installer is missing {name}')
assert (root / 'usr/bin/gnome-kiosk').readlink() == Path('../libexec/aquarius-installer-compositor')
assert (root / 'usr/lib/systemd/system/anaconda.target.wants/aquarius-installer-input.service').is_symlink()
session = (root / 'usr/lib/systemd/system/anaconda.service.d/60-aquarius-handheld.conf').read_text()
assert 'Environment=GSETTINGS_BACKEND=keyfile' in session
assert 'Environment=XDG_CONFIG_HOME=/run/aquarius-installer-settings' in session
profile = (root / 'usr/share/aquarius/inputplumber/installer.yaml').read_text()
assert 'keyboard: KeyF12' in profile, 'Controller cannot toggle the keyboard'
assert 'keyboard: KeyF5' in profile and 'name: RightStick' in profile
assert 'motion:' not in profile, 'Installer navigation must not require pointer steering'
assert 'target_devices:\n  - keyboard\n  - mouse' in profile
for schema, key, expected in (
    ('org.gnome.desktop.a11y.applications', 'screen-keyboard-enabled', 'true'),
    ('org.gnome.desktop.interface', 'text-scaling-factor', '1.5'),
    ('org.gnome.desktop.interface', 'cursor-size', '40'),
    ('org.gnome.desktop.screensaver', 'lock-enabled', 'false'),
):
    actual = subprocess.check_output(
        ['chroot', str(root), '/usr/bin/env', 'GSETTINGS_BACKEND=memory',
         'gsettings', 'get', schema, key], text=True).strip()
    assert actual == expected, (schema, key, actual)
version = subprocess.check_output(['chroot', str(root), 'gnome-shell', '--version'], text=True).split()[-1].split('.')[0]
metadata = json.loads((root / 'usr/share/gnome-shell/extensions/installer@aquariusos/metadata.json').read_text())
assert version in metadata['shell-version'], 'Keyboard extension needs review for this GNOME version'
mode = json.loads((root / 'usr/share/gnome-shell/modes/aquarius-installer.json').read_text())
assert 'installer@aquariusos' in mode['enabledExtensions']
assert 'keyboard' in mode['panel']['right']
print('Installer input files and effective keyboard setting verified')

# Exercise MIME recognition against the rebuilt cache. The full decoder runs
# sandboxed and needs a booted /proc and /dev, so it is checked in the VM.
subprocess.run(['chroot', str(root), 'python3', '-c', """
from pathlib import Path
from gi.repository import Gio
icon = next(Path('/usr/share/icons/Adwaita').rglob('*.svg'))
assert Gio.content_type_guess(str(icon), None)[0] == 'image/svg+xml'
assert Path('/usr/libexec/glycin-loaders/2+/glycin-svg').is_file()
print('Installer MIME database recognizes SVG icons and its decoder is present')
"""], check=True)

wordmark = (root / 'usr/share/aquarius/installer/wordmark.png').read_bytes()
for logo in (root / 'usr/share/anaconda').rglob('sidebar-logo.png'):
    assert logo.read_bytes() == wordmark, f'Unbranded installer artwork: {logo}'
assert 'custom_stylesheet = /usr/share/aquarius/installer/setup.css' in (root / 'etc/anaconda/conf.d/99-aquarius.conf').read_text()
subprocess.run(['chroot', str(root), 'python3', '-c', """
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
Gtk.CssProvider().load_from_path('/usr/share/aquarius/installer/setup.css')
print('AquariusOS installer CSS parsed successfully')
"""], check=True)

# Content checks are needed because Lorax leaves package records and strips
# actual modules. Use the USB runtime's kernel, never the build host's kernel.
kernels = list((root / 'usr/lib/modules').iterdir())
assert len(kernels) == 1
kernel = kernels[0].name
for driver in ('hid_asus', 'xpad', 'uinput', 'uhid'):
    subprocess.run(['modinfo', '-b', str(root), '-k', kernel, driver],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['modprobe', '-d', str(root), '-S', kernel,
                    '--show-depends', driver], check=True)
subprocess.run(['chroot', str(root), 'setfacl', '--version'], check=True)
print('Controller kernel modules and ACL helper verified')
