#!/usr/bin/env python3
"""Rehearse the X20 speaker loader's decisions with a fake machine.

The real program, /usr/libexec/aquarius-x20-audio, decides at start-up whether
to load the two patched sound drivers or Fedora's stock ones. This test runs a
COPY of it in which every system path (/sys, /proc, /run, /etc, /usr/lib,
/usr/share, /dev) points into a throwaway folder, and modprobe, insmod, modinfo
and chcon are small fakes that only write down what they were asked to do. No
real driver is loaded, nothing on this machine changes, and no root is needed.

Adapted from the bench experiment's test-persistent-loader.py (2026-10-16).
These are LOGIC tests. They prove which way the program decides; they do not
prove that the speakers make sound — only the handheld can.

  python3 tests/test-x20-audio-loader.py                  # the repository copy
  python3 tests/test-x20-audio-loader.py /usr/libexec/aquarius-x20-audio   # a built image's copy
"""
import hashlib
import lzma
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
LOADER = (Path(sys.argv.pop(1)) if len(sys.argv) > 1 and not sys.argv[1].startswith('-')
          else REPO / 'handheld_files/usr/libexec/aquarius-x20-audio')
SOURCE = LOADER.read_text()

KVER = '7.2.11-200.fc44.x86_64'
OURS = ('snd_acp_config', 'snd_soc_acpi_amd_match')
EFI = 'sys/firmware/efi/efivars/SPEAKER_ID-aa61eaaf-6e83-7523-b0d0-7df74bb24a81'
FIRMWARE = {('1', '8'): b'speaker-1 left amp', ('1', 'B'): b'speaker-1 right amp',
            ('0', '8'): b'speaker-0 left amp', ('0', 'B'): b'speaker-0 right amp'}


class FakeMachine:
    """One throwaway 'handheld': files, fake kmod tools, and a call log."""

    def __init__(self, root: Path, **opts):
        self.root = root
        self.log = root / 'calls'
        self.opts = opts
        files = {
            'sys/class/dmi/id/board_name': opts.get('board', 'RC74XA'),
            'sys/class/dmi/id/board_vendor': opts.get('vendor', 'ASUSTeK COMPUTER INC.'),
            'sys/module/firmware_class/parameters/path': opts.get('fw_path', ''),
            'sys/kernel/security/lockdown': opts.get('lockdown', '[none] integrity confidentiality'),
            'sys/module/module/parameters/sig_enforce': opts.get('sig_enforce', 'N'),
        }
        for rel, value in files.items():
            self.write(rel, value)
        for d in ('run', 'dev', 'etc/aquarius'):
            (root / d).mkdir(parents=True, exist_ok=True)
        if opts.get('off'):
            self.write('etc/aquarius/x20-audio-off', '')
        efi = opts.get('efi', bytes([7, 0, 0, 0, 1, 0, 0, 0]))
        if efi is not None:
            (root / EFI).parent.mkdir(parents=True, exist_ok=True)
            (root / EFI).write_bytes(efi)
        for mod in opts.get('loaded', ()):
            (root / 'sys/module' / mod).mkdir(parents=True)
        # The two patched drivers, filed for the kernel that is "running".
        moddir = root / f'usr/lib/modules/{KVER}/aquarius-x20-audio'
        moddir.mkdir(parents=True)
        for ko in ('snd-acp-config', 'snd-soc-acpi-amd-match'):
            if ko not in opts.get('missing_ko', ()):
                (moddir / f'{ko}.ko').write_text('fake driver')
        # Firmware as linux-firmware ships it (xz), and the image's list of hashes.
        fw = root / 'usr/lib/firmware'
        fw.mkdir(parents=True)
        manifest = []
        for (sid, amp), data in FIRMWARE.items():
            # A "missing" file is still in the image's list: it vanished later.
            if (sid, amp) not in opts.get('missing_fw', ()):
                (fw / f'1954-{sid}-0-0x{amp}.bin.xz').write_bytes(lzma.compress(data))
            digest = hashlib.sha256(data).hexdigest()
            if (sid, amp) in opts.get('bad_hash', ()):
                digest = '0' * 64
            if sid in opts.get('manifest_ids', ('1',)):
                manifest.append(f'{digest}  1954-{sid}-0-0x{amp}.bin\n')
        self.write('usr/share/aquarius/x20-audio/firmware.sha256', ''.join(manifest))
        self.tools()
        self.script = root / 'aquarius-x20-audio'
        text = re.sub(r'/(?:etc|proc|sys|run|usr/lib|usr/share|dev)/',
                      lambda m: str(root) + m.group(), SOURCE)
        for tool in ('modprobe', 'insmod', 'modinfo'):
            text = text.replace(f'/usr/sbin/{tool}', str(root / 'bin' / tool))
        text = text.replace('chcon --reference=', 'true --reference=')
        assert text.count('$(uname -r)') == 1, 'the loader should ask the kernel version once'
        text = text.replace('$(uname -r)', opts.get('kernel', KVER))
        self.script.write_text(text)

    def write(self, rel, value):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def tools(self):
        bindir = self.root / 'bin'
        bindir.mkdir()
        sysmod = self.root / 'sys/module'
        refuse = ' '.join(self.opts.get('insmod_refuses', ()))
        scripts = {
            # modprobe --ignore-install X = Fedora's stock driver; mark X as loaded.
            'modprobe': f'''#!/bin/bash
echo "modprobe $*" >> "{self.log}"
if [ "$1" = --ignore-install ]; then mkdir -p "{sysmod}/$2"; fi
exit 0
''',
            'insmod': f'''#!/bin/bash
echo "insmod $*" >> "{self.log}"
name="${{1##*/}}"; name="${{name%.ko}}"; name="${{name//-/_}}"
for r in {refuse}; do [ "$r" = "$name" ] && exit 1; done
mkdir -p "{sysmod}/$name"
''',
            'modinfo': '''#!/bin/bash
case "$3" in
    *snd-acp-config.ko) echo snd-soc-acpi ;;
    *snd-soc-acpi-amd-match.ko) echo snd-soc-sdca,snd-soc-acpi ;;
esac
''',
        }
        for name, body in scripts.items():
            (bindir / name).write_text(body)
            (bindir / name).chmod(0o755)

    def ask(self, module):
        result = subprocess.run(['bash', str(self.script), module],
                                capture_output=True, text=True)
        return result.returncode

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def status(self):
        path = self.root / 'run/aquarius-x20-audio-status'
        return path.read_text() if path.exists() else ''

    def firmware_path(self):
        return (self.root / 'sys/module/firmware_class/parameters/path').read_text()

    def new_boot(self):
        """Power-cycle: no drivers loaded, nothing in /run, firmware folder unset."""
        for mod in OURS:
            d = self.root / 'sys/module' / mod
            if d.exists():
                d.rmdir()
        for p in (self.root / 'run').iterdir():
            if p.is_dir():
                for q in p.iterdir():
                    q.unlink()
                p.rmdir()
            else:
                p.unlink()
        self.write('sys/module/firmware_class/parameters/path', '')


class LoaderTest(unittest.TestCase):
    def machine(self, **opts):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return FakeMachine(Path(tmp.name), **opts)

    def assert_patched(self, m):
        insmods = [c for c in m.calls() if c.startswith('insmod ')]
        self.assertEqual(len(insmods), 2, m.calls())
        self.assertTrue(insmods[0].endswith(f'/usr/lib/modules/{KVER}/aquarius-x20-audio/snd-acp-config.ko'))
        self.assertTrue(insmods[1].endswith(f'/usr/lib/modules/{KVER}/aquarius-x20-audio/snd-soc-acpi-amd-match.ko'))
        self.assertNotIn('--ignore-install', ' '.join(m.calls()))
        self.assertIn('patched RC74XA speaker drivers loaded', m.status())
        fwdir = m.root / 'run/aquarius-x20-firmware'
        self.assertEqual(m.firmware_path(), str(fwdir))
        self.assertEqual((fwdir / '1954-0-0x8.bin').read_bytes(), FIRMWARE[('1', '8')])
        self.assertEqual((fwdir / '1954-0-0xB.bin').read_bytes(), FIRMWARE[('1', 'B')])

    def assert_stock(self, m, module, reason):
        self.assertFalse(any(c.startswith('insmod ') for c in m.calls()), m.calls())
        self.assertIn(f'modprobe --ignore-install {module}', m.calls())
        self.assertIn(reason, m.status())

    # ------------------------------------------------------------------
    # The good path, in both request orders, then the second request, then
    # a fresh boot (the persistence the bench workaround had to prove).
    # ------------------------------------------------------------------
    def test_success_both_orders_repeat_and_next_boot(self):
        for first in OURS:
            with self.subTest(first=first):
                m = self.machine()
                self.assertEqual(m.ask(first), 0)
                self.assert_patched(m)
                # The dependencies were loaded the normal way, before insmod.
                deps = [c for c in m.calls() if c.startswith('modprobe ')]
                self.assertEqual(deps, ['modprobe snd-soc-acpi', 'modprobe snd-soc-sdca',
                                        'modprobe snd-soc-acpi'])
                before = m.calls()
                other = OURS[1] if first == OURS[0] else OURS[0]
                self.assertEqual(m.ask(other), 0)
                self.assertEqual(m.ask(first), 0)
                self.assertEqual(m.calls(), before, 'a repeat request must do nothing')
                m.new_boot()
                self.assertEqual(m.ask(first), 0)
                self.assertEqual(sum(c.startswith('insmod ') for c in m.calls()), 4)

    # ------------------------------------------------------------------
    # Every reason to fall back to Fedora's drivers.
    # ------------------------------------------------------------------
    def test_fallbacks(self):
        cases = {
            'switched-off': (dict(off=True), 'switched off'),
            'wrong-board': (dict(board='RC73XA'), 'not an RC74XA'),
            'wrong-vendor': (dict(vendor='Other Inc.'), 'not an RC74XA'),
            'stock-already-loaded': (dict(loaded='the other one'), 'never swapped'),
            'secure-boot-lockdown': (dict(lockdown='none [integrity] confidentiality'), 'lockdown is on'),
            'signed-only': (dict(sig_enforce='Y'), 'sig_enforce=Y'),
            'no-driver-for-kernel': (dict(kernel='7.2.12-200.fc44.x86_64'), 'no patched snd-acp-config'),
            'one-driver-missing': (dict(missing_ko=('snd-soc-acpi-amd-match',)), 'no patched snd-soc-acpi-amd-match'),
            'no-efi-variable': (dict(efi=None), 'could not read the speaker ID'),
            'short-efi-variable': (dict(efi=bytes([7, 0, 0, 0])), 'could not read the speaker ID'),
            'unknown-speaker-id': (dict(efi=bytes([7, 0, 0, 0, 5, 0, 0, 0])), 'no speaker firmware for speaker ID 5'),
            'id-not-in-image-list': (dict(efi=bytes([7, 0, 0, 0, 0, 0, 0, 0])), 'no speaker firmware for speaker ID 0'),
            'firmware-file-missing': (dict(missing_fw=(('1', 'B'),)), 'firmware 1954-1-0-0xB.bin is missing'),
            'firmware-bytes-wrong': (dict(bad_hash=(('1', '8'),)), 'not the firmware the image recorded'),
            'firmware-folder-taken': (dict(fw_path='/somewhere/else'), 'already set'),
        }
        for name, (opts, reason) in cases.items():
            for first in OURS:
                with self.subTest(case=name, first=first):
                    these = opts
                    if opts.get('loaded') == 'the other one':
                        # Fedora's driver for the OTHER name is already running.
                        these = dict(loaded=[x for x in OURS if x != first])
                    m = self.machine(**these)
                    self.assertEqual(m.ask(first), 0)
                    self.assert_stock(m, first, reason)

    def test_other_speaker_id_is_used_only_when_the_image_lists_it(self):
        # Speaker ID 0's files exist in linux-firmware. Listed by the image
        # build -> used; not listed -> refused (see test_fallbacks).
        m = self.machine(efi=bytes([7, 0, 0, 0, 0, 0, 0, 0]), manifest_ids=('0', '1'))
        self.assertEqual(m.ask(OURS[0]), 0)
        fwdir = m.root / 'run/aquarius-x20-firmware'
        self.assertEqual((fwdir / '1954-0-0x8.bin').read_bytes(), FIRMWARE[('0', '8')])
        self.assertIn('speaker ID 0', m.status())

    def test_kernel_refuses_patched_driver(self):
        # e.g. Secure Boot on without lockdown visible: insmod fails -> stock.
        m = self.machine(insmod_refuses=('snd_acp_config',))
        self.assertEqual(m.ask('snd_acp_config'), 0)
        self.assertIn('modprobe --ignore-install snd_acp_config', m.calls())
        self.assertIn('refused by the kernel', m.status())
        # The other name, asked next, sees a running stock driver and goes stock too.
        self.assertEqual(m.ask('snd_soc_acpi_amd_match'), 0)
        self.assertIn('modprobe --ignore-install snd_soc_acpi_amd_match', m.calls())

    def test_only_our_two_names(self):
        m = self.machine()
        self.assertNotEqual(m.ask('snd_hda_intel'), 0)
        self.assertNotEqual(m.ask(''), 0)
        self.assertEqual(m.calls(), [])


if __name__ == '__main__':
    unittest.main()
