#!/usr/bin/python3
"""Test menu/actions, D-Bus activation, argument forwarding and env preservation."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wiring", ROOT / "build_files/wire-files-launchers.py")
wiring = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wiring)


class FilesLaunchers(unittest.TestCase):
    def test_entries_preserve_everything_except_program(self):
        samples = [
            "[Desktop Entry]\nName=Files\nName[fr]=Fichiers\nExec=nautilus --new-window %U\nDBusActivatable=true\nActions=new-window;\n[Desktop Action new-window]\nName=New Window\nExec=nautilus --new-window\n",
            "[D-BUS Service]\nName=org.gnome.Nautilus\nExec=/usr/bin/nautilus --gapplication-service\n",
        ]
        with tempfile.TemporaryDirectory() as temp:
            for n, original in enumerate(samples):
                path = Path(temp) / str(n)
                path.write_text(original)
                expected = original.replace("Exec=/usr/bin/nautilus", "Exec=" + wiring.WRAPPER).replace("Exec=nautilus", "Exec=" + wiring.WRAPPER)
                self.assertEqual(wiring.rewrite(path), expected)
                path.write_text(expected)
                self.assertEqual(wiring.rewrite(path), expected)

    def test_upstream_command_changes_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "entry"
            for text in ("[Desktop Entry]\nName=Files\n", "Exec=unexpected-command --new-window\n"):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    wiring.rewrite(path)
                self.assertEqual(path.read_text(), text)

    def test_wrapper_preserves_environment_and_arguments(self):
        # Replace only the final executable in a temporary copy; never open the
        # user's real Files process or depend on a graphical session.
        with tempfile.TemporaryDirectory() as temp:
            fake = Path(temp) / "nautilus"
            fake.write_text('#!/usr/bin/python3\nimport os,sys,json\nprint(json.dumps([os.environ["GDK_WAYLAND_DISABLE"],sys.argv[1:]]))\n')
            fake.chmod(0o755)
            wrapper = Path(temp) / "wrapper"
            source = (ROOT / "system_files/usr/libexec/aquarius-files").read_text()
            self.assertEqual(source.count('exec /usr/bin/nautilus "$@"'), 1)
            wrapper.write_text(source.replace('exec /usr/bin/nautilus "$@"', 'exec "' + str(fake) + '" "$@"'))
            for value in (None, "", "wp_color_manager_v1;other_protocol", "xdg_toplevel_icon_manager_v1"):
                env = os.environ.copy()
                env.pop("GDK_WAYLAND_DISABLE", None)
                if value is not None:
                    env["GDK_WAYLAND_DISABLE"] = value
                args = ["--new-window", "file:///tmp/folder with spaces", "--gapplication-service"]
                result = json.loads(subprocess.check_output(["bash", str(wrapper), *args], env=env, text=True))
                self.assertEqual(result, [(value + "," if value else "") + "xdg_toplevel_icon_manager_v1", args])


if __name__ == "__main__":
    unittest.main()
