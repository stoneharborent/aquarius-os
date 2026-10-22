#!/usr/bin/env python3
"""Run the actual build-time InputPlumber patch against package-shaped data."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

REPO = Path(__file__).resolve().parents[1]
PATCH = (REPO / 'build_files/78-handheld.sh').read_text().split(
    'python3 - "${AQ_IP_YAML}" << \'AQ_PY\'\n', 1)[1].split('\nAQ_PY', 1)[0]
PROFILE = '''version: 1
kind: CompositeDevice
matches:
  - dmi_data:
      board_name: RC73XA
      sys_vendor: ASUSTeK COMPUTER INC.
  - dmi_data:
      board_name: RC73YA
      sys_vendor: ASUSTeK COMPUTER INC.
source_devices:
  - group: gamepad
    unique: false
    evdev:
      vendor_id: 0b05
      product_id: 1b4c
    events:
      exclude: ["*"]
      include:
        - Keyboard:KeyF16
        - Gamepad:Button:South
capability_map_id: aly2
'''

class BoardTest(unittest.TestCase):
    def test_real_board_vendor_pair_and_originals(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'profile.yaml'
            path.write_text(PROFILE)
            subprocess.run(['python3', '-', str(path)], input=PATCH, text=True, check=True)
            data = yaml.safe_load(path.read_text())
        matches = [entry['dmi_data'] for entry in data['matches']]
        self.assertIn({'board_name': 'RC74XA', 'sys_vendor': 'ASUS'}, matches)
        self.assertIn({'board_name': 'RC73XA', 'sys_vendor': 'ASUSTeK COMPUTER INC.'}, matches)
        self.assertIn({'board_name': 'RC73YA', 'sys_vendor': 'ASUSTeK COMPUTER INC.'}, matches)
        self.assertEqual(data['source_devices'][0]['capability_map_id'], 'aqx1')
        self.assertEqual(data['capability_map_id'], 'aly2')
        events = data['source_devices'][0]['events']
        self.assertEqual(events['exclude'], ['*'])
        self.assertEqual(set(events['include']), {
            'Keyboard:KeyF16', 'Keyboard:KeyF17', 'Keyboard:KeyF18',
            'Gamepad:Button:South', 'Gamepad:Button:LeftPaddle1',
            'Gamepad:Button:RightPaddle1'})
        # The source translator runs before filtering (InputPlumber 0.82).
        mapping = yaml.safe_load((REPO / 'handheld_files/usr/share/inputplumber/'
            'capability_maps/aquarius_ally_x_dinput.yaml').read_text())
        for entry in mapping['mapping']:
            if any(e['evdev']['event_code'] in ('KEY_F17', 'KEY_F18')
                   for e in entry['source_events']):
                translated = 'Gamepad:Button:' + entry['target_event']['gamepad']['button']
                self.assertIn(translated, events['include'])

    def test_keyboard_interface_composite_translation(self):
        patch = (REPO / 'build_files/78-handheld.sh').read_text().split(
            "<< 'AQ_PADDLES'\n", 1)[1].split('\nAQ_PADDLES', 1)[0]
        original = {"version": 1, "kind": "CapabilityMap", "id": "aly2",
                    "mapping": [{"name": "existing", "source_events": [{"keyboard": "KeyF14"}],
                                 "target_event": {"gamepad": {"button": "LeftPaddle1"}}}],
                    "filtered_events": []}
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'map.yaml'
            path.write_text(yaml.safe_dump(original, sort_keys=False))
            # Package mappings use indented sequence entries.
            path.write_text("version: 1\nkind: CapabilityMap\nid: aly2\nmapping:\n"
                "  - name: existing\n    source_events:\n      - keyboard: KeyF14\n"
                "    target_event:\n      gamepad:\n        button: LeftPaddle1\nfiltered_events: []\n")
            subprocess.run(['python3', '-', str(path)], input=patch, text=True, check=True)
            data = yaml.safe_load(path.read_text())
        self.assertEqual(data['mapping'][0], original['mapping'][0])
        mapping = {e['source_events'][0]['keyboard']: e['target_event']['gamepad']['button']
                   for e in data['mapping']}
        self.assertEqual(mapping['KeyF17'], 'LeftPaddle1')
        self.assertEqual(mapping['KeyF18'], 'RightPaddle1')
        self.assertEqual(data['filtered_events'], [])

    def test_captured_paddles_map_to_distinct_elite_buttons(self):
        data = yaml.safe_load((REPO / 'handheld_files/usr/share/inputplumber/'
            'capability_maps/aquarius_ally_x_dinput.yaml').read_text())
        mappings = {}
        for entry in data['mapping']:
            for source in entry['source_events']:
                mappings[source['evdev']['event_code']] = entry['target_event']
        for key, target in [('KEY_F17', 'LeftPaddle1'), ('KEY_F18', 'RightPaddle1'),
                            ('KEY_F15', 'LeftPaddle1')]:
            self.assertEqual(mappings[key], {'gamepad': {'button': target}})

if __name__ == '__main__':
    unittest.main()
