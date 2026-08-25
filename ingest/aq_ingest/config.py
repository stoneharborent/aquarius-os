"""Settings for aq-ingest (spec §7).

Reads ``~/.config/aquarius/ingest.toml`` (or ``$XDG_CONFIG_HOME/aquarius/ingest.toml``).
The file is created with commented defaults the first time the tool runs for real —
never during ``--dry-run``, because a dry run writes nothing at all.

Importing this module has no side effects: everything touching disk lives in a function.
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field, replace
from pathlib import Path

DEFAULT_CONFIG_TEXT = """\
# aq-ingest settings — AquariusOS "Editor-Ready Ingest" helper.
# Lines starting with # are notes to you and are ignored by the tool.
# Edit a value, save the file, and the next run uses it.

# Do you have DaVinci Resolve STUDIO (the paid one)?
#   "free"   -> normal camera MP4s are fully converted so free Resolve can open them
#   "studio" -> normal camera MP4s only get their sound fixed (much faster, no quality loss)
resolve_edition = "free"

# Where the fixed copies go:
#   "subfolder" -> an "EditorReady" folder next to your files
#   "suffix"    -> beside the original, named NAME_editready.mov
output = "subfolder"

# What iPhone HEIC photos become: "png" (best quality) or "jpeg" (smaller files)
still_format = "png"

# Video quality for converted clips:
#   "auto" -> SQ for normal footage, HQX for 10-bit footage (recommended)
#   or force one of: "sq", "hq", "hqx"
dnxhr_profile = "auto"

# Folders watched automatically (Milestone 3 — not active yet).
# Example: watch_folders = ["~/Videos/Ingest"]
watch_folders = []
"""

VALID_RESOLVE_EDITIONS = ("free", "studio")
VALID_OUTPUT_MODES = ("subfolder", "suffix")
VALID_STILL_FORMATS = ("png", "jpeg")
VALID_DNXHR_PROFILES = ("auto", "sq", "hq", "hqx")


class ConfigError(Exception):
    """A settings file we cannot honour. Message is written for a human."""


@dataclass(frozen=True)
class Settings:
    resolve_edition: str = "free"
    output: str = "subfolder"
    still_format: str = "png"
    dnxhr_profile: str = "auto"
    watch_folders: tuple[str, ...] = field(default_factory=tuple)

    @property
    def still_suffix(self) -> str:
        return ".png" if self.still_format == "png" else ".jpg"


def default_config_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(Path.home(), ".config")
    return Path(base) / "aquarius" / "ingest.toml"


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(Path.home(), ".local", "state")
    return Path(base) / "aquarius"


def log_path() -> Path:
    return state_dir() / "ingest.log"


def _check(name: str, value: object, allowed: tuple[str, ...], path: Path) -> str:
    if not isinstance(value, str) or value not in allowed:
        raise ConfigError(
            f"The setting {name} in {path} is set to {value!r}, which is not something "
            f"aq-ingest understands.\nAllowed values: {', '.join(allowed)}.\n"
            f"Fix that line (or delete the file to start over with the defaults) and run again."
        )
    return value


def load_settings(path: Path | None = None, *, create: bool = False) -> Settings:
    """Load settings. ``create=True`` writes the commented defaults if none exist."""
    path = Path(path) if path is not None else default_config_path()

    if not path.exists():
        if create:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(DEFAULT_CONFIG_TEXT, encoding="utf-8")
            except OSError as exc:
                raise ConfigError(
                    f"Could not create the settings file at {path}: {exc}"
                ) from exc
        return Settings()

    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ConfigError(
            f"Could not read the settings file at {path}: {exc}\n"
            f"Fix the file, or delete it to start over with the defaults."
        ) from exc

    known = {"resolve_edition", "output", "still_format", "dnxhr_profile", "watch_folders"}
    unknown = sorted(set(raw) - known)
    if unknown:
        raise ConfigError(
            f"The settings file at {path} has setting(s) aq-ingest does not know: "
            f"{', '.join(unknown)}.\nRemove them (or check the spelling) and run again."
        )

    folders = raw.get("watch_folders", [])
    if not isinstance(folders, list) or not all(isinstance(f, str) for f in folders):
        raise ConfigError(
            f"The setting watch_folders in {path} must be a list of folder names, "
            f'for example: watch_folders = ["~/Videos/Ingest"]'
        )

    return Settings(
        resolve_edition=_check(
            "resolve_edition", raw.get("resolve_edition", "free"), VALID_RESOLVE_EDITIONS, path
        ),
        output=_check("output", raw.get("output", "subfolder"), VALID_OUTPUT_MODES, path),
        still_format=_check(
            "still_format", raw.get("still_format", "png"), VALID_STILL_FORMATS, path
        ),
        dnxhr_profile=_check(
            "dnxhr_profile", raw.get("dnxhr_profile", "auto"), VALID_DNXHR_PROFILES, path
        ),
        watch_folders=tuple(folders),
    )


def with_overrides(settings: Settings, **overrides: object) -> Settings:
    """Apply command-line overrides on top of the file settings."""
    clean = {k: v for k, v in overrides.items() if v is not None}
    return replace(settings, **clean) if clean else settings
