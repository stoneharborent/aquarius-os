#!/usr/bin/env python3
"""Check Resolve's automatic scale and explicit overrides without launching it."""
import json
import os
from pathlib import Path
import runpy
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else (
    Path(__file__).resolve().parent.parent / "system_files")
HELPER = ROOT / "usr/libexec/aquarius-display-scale"
MODULE = runpy.run_path(str(HELPER))


def output(width=3840, height=2160, scale=1, enabled=True):
    return {"name": "DP-1", "enabled": enabled, "scale": scale,
            "physical_size": {"width": 1210, "height": 680},
            "modes": [{"width": width, "height": height, "current": True}]}


class ResolveScale(unittest.TestCase):
    def test_auto_policy(self):
        cases = [([output()], 1.25), ([output(1920, 1080)], 1),
                 ([output(scale=2)], 2), ([output(), output(1920, 1080)], 1),
                 ([output(), output(1920, 1080, enabled=False)], 1.25),
                 ([output(0, 0)], 1), ([], 1),
                 ([output(scale=1.5)], 1.5)]
        for outputs, wanted in cases:
            with self.subTest(outputs=outputs):
                screens = MODULE["outputs_from_json"](json.dumps(outputs))
                self.assertEqual(MODULE["resolve_scale"](screens, {}, ""), wanted)
        unknown = output()
        del unknown["scale"]
        screens = MODULE["outputs_from_json"](json.dumps([unknown]))
        self.assertEqual(MODULE["resolve_scale"](screens, {}, ""), 1)
        # The existing desktop policy remains exactly as before for this Ark.
        screens = MODULE["outputs_from_json"](json.dumps([output()]))
        self.assertEqual(MODULE["effective_scale"](screens, {}, ""), 1)

    def test_launcher_precedence(self):
        with tempfile.TemporaryDirectory(prefix="resolve-scale-test-") as temporary:
            work = Path(temporary)
            config = work / "config"
            (config / "aquarius").mkdir(parents=True)
            outputs = work / "outputs.json"
            outputs.write_text(json.dumps([output()]))
            stub = work / "display-helper"
            stub.write_text("#!/bin/sh\nexec " + shlex.join([
                sys.executable, str(HELPER), "--outputs-from", str(outputs),
                "--conf", str(work / "absent"), "--monitors-xml", str(work / "absent")])
                + ' "$@"\n')
            stub.chmod(0o755)
            launcher = work / "launcher"
            launcher.write_text((ROOT / "usr/libexec/aquarius-resolve-launch").read_text()
                                .replace("/usr/libexec/aquarius-display-scale", shlex.quote(str(stub))))
            env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(config),
                       XCURSOR_THEME="Adwaita", XCURSOR_SIZE="24")
            env.pop("AQUARIUS_RESOLVE_SCALE", None)
            env.pop("AQUARIUS_RESOLVE_QT_VAR", None)

            def report():
                return subprocess.check_output(["bash", str(launcher), "--report"],
                                               env=env, text=True, stderr=subprocess.STDOUT)

            self.assertIn("interface at 1.25x", report())
            (config / "aquarius/resolve.conf").write_text("scale=1\n")
            self.assertIn("interface at 1x", report())
            env["AQUARIUS_RESOLVE_SCALE"] = "1.5"
            self.assertIn("interface at 1.5x", report())


if __name__ == "__main__":
    unittest.main()
