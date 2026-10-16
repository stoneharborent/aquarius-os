#!/usr/bin/python3
"""Put our existing artwork in the USB runtime's actual Anaconda paths."""
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

root, assets = map(Path, sys.argv[1:])
wordmark = assets / 'branding/aquarius-about-logo.png'
mark = assets / 'branding/aquarius-logo.png'
destination = root / 'usr/share/aquarius/installer'
destination.mkdir(parents=True, exist_ok=True)
shutil.copyfile(wordmark, destination / 'wordmark.png')
shutil.copytree(assets / 'fonts', root / 'usr/share/fonts', dirs_exist_ok=True)
# The custom stylesheet is authoritative. Also replace fallback artwork so a
# different Anaconda product profile cannot show Fedora's logo during setup.
logos = list((root / 'usr/share/anaconda').rglob('sidebar-logo.png'))
logos += list((root / 'usr/share/anaconda').rglob('anaconda_header.png'))
assert logos, 'Fedora moved the installer artwork; review the new paths'
for path in logos:
    shutil.copyfile(wordmark, path)
for path in (root / 'usr/share/icons').glob('hicolor/*/apps/anaconda.png'):
    shutil.copyfile(mark, path)
print(f'AquariusOS artwork installed at {len(logos)} Anaconda logo paths')

# Replace Fedora's promotional slides with one quiet AquariusOS identity card.
# Reuse the approved mark verbatim; never redraw the apex or wave.
slides = root / 'usr/share/anaconda/pixmaps/rnotes'
if slides.exists():
    shutil.rmtree(slides)
(slides / 'en').mkdir(parents=True)
ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = '{http://www.w3.org/2000/svg}'
card = ET.Element(ns + 'svg', {'width': '480', 'height': '260', 'viewBox': '0 0 480 260'})
ET.SubElement(card, ns + 'rect', {'width': '480', 'height': '260', 'fill': '#EAF1F8'})
logo = ET.parse(assets / 'logo-ice.svg').getroot()
logo.attrib.update({'x': '160', 'y': '20', 'width': '160', 'height': '160'})
card.append(logo)
word = ET.SubElement(card, ns + 'text', {'x': '240', 'y': '224', 'text-anchor': 'middle',
    'font-family': 'Sora, sans-serif', 'font-size': '30', 'fill': '#16273A'})
word.text = 'AquariusOS'
ET.ElementTree(card).write(slides / 'en/aquarius.svg', encoding='utf-8', xml_declaration=True)
