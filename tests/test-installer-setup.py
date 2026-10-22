#!/usr/bin/python3
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('setup', REPO/'installer/simplify-setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

class SetupTest(unittest.TestCase):
    def fixture(self, root):
        gui = root/'usr/lib64/python3.14/site-packages/pyanaconda/ui/gui'
        (gui/'spokes').mkdir(parents=True)
        for name, title in [('storage', 'Installation _Destination'), ('user', '_User Creation'),
                            ('network', '_Network & Host Name'), ('datetime_spoke', '_Time & Date')]:
            (gui/'spokes'/f'{name}.py').write_text(
                f'title = CN_("GUI|Spoke", "{title}")\nmandatory = True\n')
        ui = root/'usr/share/anaconda/ui/summary.glade'
        ui.parent.mkdir(parents=True)
        ui.write_text('''<interface>
<object id="summaryWindow"><property name="window_name">INSTALLATION SUMMARY</property></object>
<object id="summaryWindow-atkobject"><property name="AtkObject::accessible-name">INSTALLATION SUMMARY</property></object>
<object id="continueButton"><property name="label">_Begin Installation</property><signal name="clicked" handler="on_continue_clicked"/></object>
<object id="label1"><property name="label">Old note</property></object>
</interface>''')
        # Storage also ships a summary.glade; do not modify that confirmation.
        (gui/'spokes/summary.glade').write_text('<interface><object id="storageConfirmation"/></interface>')
        return gui, ui

    def test_only_labels_change_and_confirmation_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); gui, ui = self.fixture(root)
            setup.simplify(root)
            data = ET.parse(ui)
            self.assertEqual(data.find(".//object[@id='continueButton']/signal").get('handler'), 'on_continue_clicked')
            self.assertIn('erase data', data.find(".//object[@id='label1']/property[@name='label']").text)
            self.assertIn('mandatory = True', (gui/'spokes/user.py').read_text())
            self.assertIn('storageConfirmation', (gui/'spokes/summary.glade').read_text())

    def test_unknown_ui_fails_before_changing_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); gui, ui = self.fixture(root)
            before = (gui/'spokes/user.py').read_text()
            ui.write_text('<interface/>')
            with self.assertRaises(ValueError): setup.simplify(root)
            self.assertEqual((gui/'spokes/user.py').read_text(), before)

if __name__ == '__main__': unittest.main()
