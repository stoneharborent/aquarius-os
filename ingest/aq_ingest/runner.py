"""Walking the inputs, deciding, doing, and reporting (spec §6).

Rules that matter here:
  * an original is never written to, never moved, never deleted;
  * an existing output is never overwritten unless --force says so;
  * a dry run writes absolutely nothing — not the copies, not the log, not the settings file.
"""

from __future__ import annotations

import datetime as _dt
import os
from dataclasses import dataclass, field
from pathlib import Path

from . import actions, rules
from .config import Settings, log_path
from .probe import probe_file
from .rules import Plan
from .tools import ToolFailed, ToolMissing

OUTPUT_FOLDER_NAME = "EditorReady"
OUTPUT_SUFFIX_TAG = "_editready"

#: Files a card dump is full of that are not footage.
IGNORED_NAMES = {".ds_store", "thumbs.db", "desktop.ini"}
IGNORED_SUFFIXES = (".part", ".tmp", ".crdownload")

# Result statuses
REWRAPPED = "rewrapped"
TRANSCODED = "transcoded"
CONVERTED = "converted"
ALREADY_READY = "already editor-ready"
UP_TO_DATE = "up to date"
LEFT_ALONE = "left alone"
PLANNED = "planned"
FAILED = "failed"


@dataclass
class Result:
    source: Path
    status: str
    message: str
    output: Path | None = None
    action: str = rules.LEAVE_ALONE
    rule: int = 0
    flags: tuple[str, ...] = field(default_factory=tuple)

    @property
    def ok(self) -> bool:
        return self.status != FAILED

    def as_dict(self) -> dict:
        return {
            "source": str(self.source),
            "status": self.status,
            "message": self.message,
            "output": str(self.output) if self.output else None,
            "action": self.action,
            "rule": self.rule,
            "flags": list(self.flags),
        }


# --------------------------------------------------------------------------------------
# Finding the work
# --------------------------------------------------------------------------------------


def _is_ignorable(path: Path) -> bool:
    name = path.name
    if name.startswith("."):
        return True
    if name.lower() in IGNORED_NAMES:
        return True
    return name.lower().endswith(IGNORED_SUFFIXES)


def collect_inputs(paths: list[Path]) -> tuple[list[tuple[Path, Path]], list[str]]:
    """Expand the command-line paths into (file, root) pairs.

    ``root`` is what relative output paths are mirrored against: the folder itself for a
    folder argument, the containing folder for a single file argument.
    """
    jobs: list[tuple[Path, Path]] = []
    problems: list[str] = []
    seen: set[Path] = set()

    for raw in paths:
        path = Path(raw).expanduser()
        try:
            path = path.resolve()
        except OSError:
            pass
        if not path.exists():
            problems.append(f"There is nothing at {path} — check the name and try again.")
            continue

        if path.is_file():
            if path not in seen:
                seen.add(path)
                jobs.append((path, path.parent))
            continue

        if path.is_dir():
            for folder, dirnames, filenames in os.walk(path):
                # Never walk into our own output folders, or hidden ones.
                dirnames[:] = sorted(
                    d for d in dirnames if d != OUTPUT_FOLDER_NAME and not d.startswith(".")
                )
                for filename in sorted(filenames):
                    candidate = Path(folder) / filename
                    if _is_ignorable(candidate):
                        continue
                    if candidate not in seen:
                        seen.add(candidate)
                        jobs.append((candidate, path))
            continue

        problems.append(f"{path} is not a file or a folder, so it was skipped.")

    return jobs, problems


# --------------------------------------------------------------------------------------
# Where the copy goes
# --------------------------------------------------------------------------------------


def output_path_for(source: Path, root: Path, settings: Settings, suffix: str) -> Path:
    if settings.output == "suffix":
        return source.with_name(f"{source.stem}{OUTPUT_SUFFIX_TAG}{suffix}")
    try:
        relative = source.relative_to(root)
    except ValueError:
        relative = Path(source.name)
    return root / OUTPUT_FOLDER_NAME / relative.parent / f"{source.stem}{suffix}"


def is_up_to_date(source: Path, output: Path) -> bool:
    """An output counts as current when it exists and is no older than its source.

    (aq-ingest copies the source's timestamp onto the output, so "no older" — not
    "strictly newer" — is the right test.)
    """
    if not output.is_file():
        # Missing, or something that is not a file at all (a folder in the way). Either way
        # it is not a finished copy, so do not report it as one.
        return False
    try:
        return output.stat().st_mtime >= source.stat().st_mtime - 0.001
    except OSError:
        return False


# --------------------------------------------------------------------------------------
# Doing the work
# --------------------------------------------------------------------------------------


def process_one(
    source: Path,
    root: Path,
    settings: Settings,
    *,
    dry_run: bool = False,
    force: bool = False,
    force_transcode: bool = False,
) -> Result:
    try:
        probe = probe_file(source)
    except ToolMissing:
        raise  # missing ffmpeg is a setup problem, not a per-file problem
    except OSError as exc:
        return Result(source, FAILED, f"Could not read {source}: {exc}")

    plan: Plan = rules.decide(probe, settings, force_transcode=force_transcode)

    if plan.action == rules.PASS_THROUGH:
        return Result(source, ALREADY_READY, plan.reason, action=plan.action, rule=plan.rule)
    if plan.action == rules.LEAVE_ALONE:
        return Result(source, LEFT_ALONE, plan.reason, action=plan.action, rule=plan.rule)

    output = output_path_for(source, root, settings, plan.output_suffix or ".mov")

    if output == source:
        return Result(
            source,
            LEFT_ALONE,
            "left alone — the fixed copy would land on top of the original",
            action=rules.LEAVE_ALONE,
        )

    if not force and is_up_to_date(source, output):
        return Result(
            source, UP_TO_DATE, "up to date", output=output, action=plan.action, rule=plan.rule
        )

    if dry_run:
        return Result(
            source,
            PLANNED,
            plan.reason,
            output=output,
            action=plan.action,
            rule=plan.rule,
            flags=plan.flags,
        )

    try:
        actions.execute(plan, source, output, probe, settings)
    except (ToolFailed, ToolMissing) as exc:
        return Result(source, FAILED, str(exc), output=None, action=plan.action, rule=plan.rule)
    except OSError as exc:
        return Result(
            source, FAILED, f"Could not write {output}: {exc}", action=plan.action, rule=plan.rule
        )

    status = {
        rules.REWRAP: REWRAPPED,
        rules.TRANSCODE: TRANSCODED,
        rules.STILL_CONVERT: CONVERTED,
    }[plan.action]
    return Result(
        source, status, plan.reason, output=output, action=plan.action, rule=plan.rule,
        flags=plan.flags,
    )


# --------------------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------------------


def summarize(results: list[Result]) -> str:
    """The one-line count the notification and the log both use."""
    counts: dict[str, int] = {}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1

    vfr = sum(1 for r in results if "vfr-conformed" in r.flags)
    parts: list[str] = []

    def add(status: str, label: str) -> None:
        n = counts.get(status, 0)
        if n:
            parts.append(f"{n} {label}")

    add(REWRAPPED, "rewrapped")
    n_transcoded = counts.get(TRANSCODED, 0)
    if n_transcoded:
        parts.append(
            f"{n_transcoded} transcoded" + (f" ({vfr} VFR)" if vfr else "")
        )
    add(CONVERTED, "photos converted")
    add(PLANNED, "would be processed")
    add(ALREADY_READY, "already editor-ready")
    add(UP_TO_DATE, "up to date")
    add(LEFT_ALONE, "left alone")
    parts.append(f"{counts.get(FAILED, 0)} failed")
    return ", ".join(parts)


def write_log(results: list[Result], summary: str, path: Path | None = None) -> Path | None:
    """Append this run to ~/.local/state/aquarius/ingest.log. Never fatal."""
    target = Path(path) if path else log_path()
    stamp = _dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    lines = [f"[{stamp}] aq-ingest: {summary}"]
    for result in results:
        arrow = f" -> {result.output}" if result.output else ""
        lines.append(f"    {result.status:<20} {result.source}{arrow}")
        if result.status == FAILED:
            for detail in result.message.splitlines():
                lines.append(f"        {detail}")
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    except OSError:
        return None
    return target
