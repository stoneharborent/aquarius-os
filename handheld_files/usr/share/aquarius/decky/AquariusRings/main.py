# =============================================================================
# AquariusRings — the Decky backend for the stick rings, in Game Mode
# =============================================================================
# HANDHELD IMAGE ONLY. Ships in /usr/share/aquarius/decky/AquariusRings and is
# copied into Decky's plugins folder by /usr/libexec/aquarius-decky-rings-sync.
#
# ⚠️ IT DECIDES NOTHING. The desktop's Rings menu, the terminal and this panel
# all do the same thing: run `aq handheld rings <choice>`, which writes
# ~/.config/aquarius/rings.conf and nudges the one ring service
# (/usr/libexec/aquarius-ally-rings). So there is ONE owner of the lights and
# ONE setting, whichever screen it was changed from.
#
# No "root" flag: Decky runs this backend as the person (UNPRIVILEGED_USER in
# plugin_loader.service), which is exactly who `aq handheld rings` is for.
# =============================================================================

import os
import subprocess

import decky

AQ = "/usr/bin/aq"
CONF = os.path.join(decky.DECKY_USER_HOME, ".config", "aquarius", "rings.conf")
CHOICES = {
    "white", "blue", "steam", "xbox", "x20", "cyan", "green", "red",
    "orange", "pink", "purple", "rainbow", "cycle", "breathe", "off", "on",
}


def _env():
    # Decky is a PyInstaller program: its own libraries must not leak into aq.
    env = {k: v for k, v in os.environ.items() if k not in ("LD_LIBRARY_PATH", "LD_PRELOAD")}
    env.update(HOME=decky.DECKY_USER_HOME, USER=decky.DECKY_USER,
               PATH="/usr/local/bin:/usr/bin:/bin")
    return env


def _read():
    found = {"effect": "solid", "colour": "ffffff"}
    try:
        with open(CONF) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "=" in line:
                    key, value = (p.strip().lower() for p in line.split("=", 1))
                    if key in found:
                        found[key] = value
    except OSError:
        pass
    return found


class Plugin:
    async def get_rings(self) -> dict:
        return _read()

    async def set_rings(self, choice: str) -> dict:
        if choice not in CHOICES:
            raise ValueError(f"'{choice}' is not a ring choice")
        result = subprocess.run([AQ, "handheld", "rings", choice], env=_env(),
                                capture_output=True, text=True, timeout=20)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"aq handheld rings {choice} failed")
        decky.logger.info(f"rings -> {choice}")
        return _read()

    async def _main(self):
        decky.logger.info(f"AquariusRings ready for {decky.DECKY_USER}")

    async def _unload(self):
        pass
