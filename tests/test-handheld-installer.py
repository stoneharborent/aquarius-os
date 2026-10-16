#!/usr/bin/env python3
"""Controller reconnects and safe extraction of the ISO's own input stack."""
import hashlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[1]


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


controller = load('installer_input', REPO / 'installer/runtime/usr/libexec/aquarius-installer-input')
extractor = load('extract_controller', REPO / 'installer/extract-controller.py')


class ControllerTests(unittest.TestCase):
    def test_new_controller_gets_profile_existing_one_is_left_alone(self):
        answers = ['/org/shadowblip/InputPlumber/CompositeDevice0\n'
                   '/org/shadowblip/InputPlumber/CompositeDevice12\n',
                   "Profile: 'AquariusOS Installer'", "Profile: 'Default'", '']
        with patch.object(controller, 'run', side_effect=answers) as run:
            controller.configure()
        self.assertEqual(run.call_args_list[-1].args,
                         ('inputplumber', 'device', '12', 'profile', 'load', controller.PROFILE))
        self.assertEqual(run.call_count, 4)

    def test_disconnect_does_not_block_other_controllers(self):
        answers = ['/org/shadowblip/InputPlumber/CompositeDevice0\n'
                   '/org/shadowblip/InputPlumber/CompositeDevice1\n',
                   subprocess.CalledProcessError(1, 'inputplumber'), 'Default', '']
        with patch.object(controller, 'run', side_effect=answers) as run:
            controller.configure()
        self.assertEqual(run.call_args_list[-1].args[2], '1')

    def test_reconnected_device_with_reused_number_gets_profile(self):
        with patch.object(controller, 'run', side_effect=[
            '/org/shadowblip/InputPlumber/CompositeDevice0\n', 'AquariusOS Installer',
            '/org/shadowblip/InputPlumber/CompositeDevice0\n', 'Default', '',
        ]) as run:
            controller.configure()
            controller.configure()
        self.assertEqual(run.call_args_list[-1].args[-2:], ('load', controller.PROFILE))

    def test_no_controller_is_not_an_error(self):
        with patch.object(controller, 'run', return_value='') as run:
            controller.configure()
        self.assertEqual(run.call_count, 1)


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.oci = Path(self.tmp.name) / 'oci'
        (self.oci / 'blobs/sha256').mkdir(parents=True)
        self.root = Path(self.tmp.name) / 'runtime'
        self.root.mkdir()

    def blob(self, data):
        digest = hashlib.sha256(data).hexdigest()
        (self.oci / 'blobs/sha256' / digest).write_bytes(data)
        return {'digest': 'sha256:' + digest, 'size': len(data)}

    def layer(self, members):
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode='w:gz') as out:
            for path, content in members.items():
                item = tarfile.TarInfo(path)
                item.size = len(content)
                out.addfile(item, io.BytesIO(content))
        return self.blob(buf.getvalue())

    def payload(self, extra=None):
        files = {
            'usr/bin/inputplumber': b'controller',
            'usr/libexec/aquarius-ally-controller': b'helper',
            'usr/share/inputplumber/capability_maps/aquarius_ally_x_dinput.yaml': b'map',
            'usr/share/dbus-1/system.d/org.shadowblip.InputPlumber.conf': b'dbus',
            'usr/share/unrelated-file': b'not for the installer',
        }
        layers = [self.layer(files)]
        if extra:
            layers.append(self.layer(extra))
        manifest = {'config': self.blob(b'{"architecture":"amd64"}'), 'layers': layers}
        desc = self.blob(json.dumps(manifest).encode())
        (self.oci / 'index.json').write_text(json.dumps({'manifests': [desc]}))

    def test_exact_input_stack_without_unrelated_os_content(self):
        self.payload({'usr/bin/inputplumber': b'updated controller'})
        extractor.extract(self.oci, self.root)
        self.assertEqual((self.root / 'usr/bin/inputplumber').read_bytes(), b'updated controller')
        self.assertFalse((self.root / 'usr/share/unrelated-file').exists())

    def test_deleted_input_file_cannot_be_resurrected(self):
        self.payload({'usr/bin/.wh.inputplumber': b''})
        with self.assertRaisesRegex(ValueError, 'removed'):
            extractor.extract(self.oci, self.root)

    def test_opaque_controller_parent_cannot_resurrect_old_files(self):
        self.payload({'usr/share/.wh..wh..opq': b''})
        with self.assertRaisesRegex(ValueError, 'removed'):
            extractor.extract(self.oci, self.root)

    def test_traversal_is_rejected(self):
        self.payload({'../outside': b'bad'})
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            extractor.extract(self.oci, self.root)

    def test_corrupted_payload_is_rejected(self):
        self.payload()
        desc = json.loads((self.oci / 'index.json').read_text())['manifests'][0]
        (self.oci / 'blobs/sha256' / desc['digest'].split(':')[1]).write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            extractor.extract(self.oci, self.root)


if __name__ == '__main__':
    unittest.main()
