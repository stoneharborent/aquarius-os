#!/usr/bin/python3
"""Copy controller support from the exact OS payload already inside this ISO.

No second network download or independently chosen InputPlumber version. Only
these package files are copied; games, desktop settings and user data are not.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

EXACT = {
    'usr/bin/inputplumber',
    'usr/lib/systemd/system/inputplumber.service',
    'usr/lib/systemd/system/inputplumber-suspend.service',
    'usr/lib/udev/hwdb.d/59-inputplumber.hwdb',
    'usr/lib/udev/hwdb.d/60-inputplumber-autostart.hwdb',
    'usr/lib/udev/rules.d/90-inputplumber-autostart.rules',
    'usr/lib/udev/rules.d/99-inputplumber-device-setup.rules',
    'usr/lib/udev/rules.d/60-inputplumber-uaccess.rules',
    'usr/lib/udev/rules.d/55-8bitdo-u2-controller.rules',
    'usr/lib/modules-load.d/inputplumber-hrtimer.conf',
    'usr/share/dbus-1/system.d/org.shadowblip.InputPlumber.conf',
    'usr/share/polkit-1/actions/org.shadowblip.InputPlumber.policy',
    'usr/share/polkit-1/rules.d/org.shadowblip.InputPlumber.rules',
    'usr/libexec/aquarius-ally-controller',
    'usr/lib/systemd/system/aquarius-ally-controller.service',
    'usr/lib/udev/rules.d/71-aquarius-ally-controller.rules',
}
TREES = ('usr/share/inputplumber', 'usr/share/licenses/inputplumber')


def wanted(name):
    return name in EXACT or any(name == p or name.startswith(p + '/') for p in TREES)


def blob(oci, descriptor):
    algorithm, digest = descriptor['digest'].split(':', 1)
    if algorithm != 'sha256' or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
        raise ValueError('Unsupported OCI digest')
    path = oci / 'blobs/sha256' / digest
    with path.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != digest:
        raise ValueError(f'Payload checksum mismatch: {path}')
    return path


def extract(oci, root):
    index = json.loads((oci / 'index.json').read_text())
    if len(index['manifests']) != 1:
        raise ValueError('Expected one x86_64 OS payload')
    manifest = json.loads(blob(oci, index['manifests'][0]).read_text())
    config = json.loads(blob(oci, manifest['config']).read_text())
    if config.get('architecture') != 'amd64':
        raise ValueError('The handheld installer requires an amd64 payload')
    for layer in manifest['layers']:
        with tarfile.open(blob(oci, layer), mode='r|*') as archive:
            for member in archive:
                name = member.name.removeprefix('./')
                parts = PurePosixPath(name).parts
                if name.startswith('/') or '..' in parts:
                    raise ValueError(f'Unsafe payload member: {name}')
                # A removed controller file must never be resurrected by this
                # selective extraction. Fail and revisit when packaging changes.
                if parts and parts[-1].startswith('.wh.'):
                    target = (str(PurePosixPath(name).parent) if parts[-1] == '.wh..wh..opq'
                              else str(PurePosixPath(name).with_name(parts[-1][4:])))
                    if target == '.' or wanted(target) or any(p.startswith(target + '/') for p in EXACT | set(TREES)):
                        raise ValueError(f'Controller file removed in payload: {name}')
                if wanted(name):
                    archive.extract(member, root, filter='data')
    required = ('usr/bin/inputplumber', 'usr/libexec/aquarius-ally-controller',
                'usr/share/inputplumber/capability_maps/aquarius_ally_x_dinput.yaml',
                'usr/share/dbus-1/system.d/org.shadowblip.InputPlumber.conf')
    for name in required:
        if not (root / name).is_file():
            raise ValueError(f'Handheld payload is missing {name}')
    return index['manifests'][0]['digest']


if __name__ == '__main__':
    print(extract(Path(sys.argv[1]), Path(sys.argv[2])))
