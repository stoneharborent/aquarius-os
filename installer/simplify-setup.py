#!/usr/bin/python3
"""Simplify the handheld GTK installer while preserving Anaconda validation."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def simplify(root):
    root = Path(root)
    # Actual runtime paths are discovered, not tied to its Python minor version.
    candidates = list(root.glob('usr/lib*/python*/site-packages/pyanaconda/ui/gui'))
    if len(candidates) != 1:
        raise ValueError('Expected one Anaconda GTK runtime')
    gui = candidates[0]
    titles = {
        'storage.py': ('Installation _Destination', 'Installation _Drive'),
        'user.py': ('_User Creation', 'Your _Account'),
        'network.py': ('_Network & Host Name', '_Wi-Fi & Network'),
        'datetime_spoke.py': ('_Time & Date', '_Region & Time'),
    }
    changes = []
    for name, (old, new) in titles.items():
        path = gui / 'spokes' / name
        text = path.read_text()
        anchor = f'title = CN_("GUI|Spoke", "{old}")'
        if text.count(anchor) != 1:
            raise ValueError(f'Anaconda title changed: {name}')
        text = text.replace(anchor, f'title = CN_("GUI|Spoke", "{new}")')
        compile(text, str(path), 'exec')
        changes.append((path, text))

    paths = [path for path in root.rglob('summary.glade')
             if ET.parse(path).find(".//object[@id='summaryWindow']") is not None]
    if len(paths) != 1:
        raise ValueError('Expected one installation summary UI')
    path = paths[0]
    tree = ET.parse(path)
    edits = [
        ('summaryWindow', 'window_name', 'Set up AquariusOS'),
        ('summaryWindow-atkobject', 'AtkObject::accessible-name', 'Set up AquariusOS'),
        ('continueButton', 'label', '_Install AquariusOS'),
        ('label1', 'label', 'Choose your installation drive and create your account. '
         'Check Wi-Fi and region settings if needed. Review your drive selection before '
         'selecting Install AquariusOS; installation can erase data on that drive.'),
    ]
    for ident, prop, value in edits:
        matches = tree.findall(f".//object[@id='{ident}']/property[@name='{prop}']")
        if len(matches) != 1:
            raise ValueError(f'Installer summary control changed: {ident}/{prop}')
        matches[0].text = value
        # New AquariusOS text has no entry in Fedora's translation catalog.
        matches[0].attrib.pop('translatable', None)
        matches[0].attrib.pop('context', None)
    note = tree.find(".//object[@id='label1']")
    for name, value in [('wrap', 'True'), ('max_width_chars', '68')]:
        prop = note.find(f"property[@name='{name}']")
        if prop is None:
            prop = ET.SubElement(note, 'property', {'name': name})
        prop.text = value
    # Refuse before writing anything if the package structure has changed.
    for target, text in changes:
        target.write_text(text)
        # Prevent bytecode copied from the original package taking precedence.
        for cached in (target.parent / '__pycache__').glob(target.stem + '.*.pyc'):
            cached.unlink()
    tree.write(path, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    simplify(sys.argv[1])
