#!/usr/bin/env python3
"""Exercise scale decisions without touching the running desktop."""
from pathlib import Path
import runpy
import unittest

configuration = runpy.run_path(str(Path(__file__).resolve().parents[1] /
    'handheld_files/usr/libexec/aquarius-handheld-display'))['configuration']

class DisplayTest(unittest.TestCase):
    def setup_state(self, builtin=True, scale=1.0, width=1920, scales=None):
        spec = ('eDP-1', 'SDC', 'panel', 'serial')
        monitors = [(spec, [('native', width, 1080, 120., 1.,
            scales or [1., 1.5, 2.], {'is-current': True})], {'is-builtin': builtin})]
        logical = [(0, 0, scale, 0, True, [spec], {})]
        return monitors, logical

    def test_handheld(self):
        self.assertEqual(configuration(*self.setup_state()),
            [(0, 0, 1.5, 0, True, [('eDP-1', 'native', {})])])

    def test_preserves_existing_scale(self):
        self.assertIsNone(configuration(*self.setup_state(scale=2.)))

    def test_external_screen(self):
        self.assertIsNone(configuration(*self.setup_state(builtin=False)))

    def test_small_resolution(self):
        self.assertIsNone(configuration(*self.setup_state(width=1280)))

    def test_unsupported_scale(self):
        self.assertIsNone(configuration(*self.setup_state(scales=[1., 2.])))

    def test_docked_layout_is_not_rearranged(self):
        monitors, logical = self.setup_state()
        logical.append((1920, 0, 1., 0, False, [('DP-1', '', '', '')], {}))
        self.assertIsNone(configuration(monitors, logical))

if __name__ == '__main__':
    unittest.main()
