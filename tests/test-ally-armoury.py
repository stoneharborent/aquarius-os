#!/usr/bin/python3
import importlib.util
from importlib.machinery import SourceFileLoader
from unittest.mock import patch
from pathlib import Path
import unittest
source = Path(__file__).resolve().parents[1] / 'handheld_files/usr/libexec/aquarius-ally-armoury'
spec = importlib.util.spec_from_loader('armoury', SourceFileLoader('armoury', str(source)))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class CaptureTests(unittest.TestCase):
    def test_one_shortcut_per_press(self):
        b = m.Button()
        self.assertTrue(b.update(m.PRESS))
        self.assertFalse(b.update(m.PRESS))
        self.assertFalse(b.update(m.RELEASE))
        self.assertTrue(b.update(m.PRESS))

    def test_other_reports_do_not_activate_or_release(self):
        b = m.Button()
        for report in [b'', b'\x5a', bytes.fromhex('5a9300000000'), m.PRESS+b'\0']:
            self.assertFalse(b.update(report))
        self.assertTrue(b.update(m.PRESS))
        self.assertFalse(b.update(bytes.fromhex('5ad101000000')))
        self.assertFalse(b.update(m.PRESS))

    def test_disconnect_closes_hid(self):
        with patch.object(m.Path, 'read_text', return_value='RC74XA'), \
             patch.object(m, 'composite', return_value='/test'), \
             patch.object(m, 'vendor', return_value='/dev/hidraw5'), \
             patch.object(m.os, 'open', return_value=123), \
             patch.object(m.select, 'select', return_value=([123], [], [])), \
             patch.object(m.os, 'read', return_value=b''), \
             patch.object(m.os, 'close') as close:
            m.main()
            close.assert_called_once_with(123)

if __name__ == '__main__':
    unittest.main()
