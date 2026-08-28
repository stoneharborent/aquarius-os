"""The aq-ingest command line (spec §4).

Exit codes:
    0  everything the tool tried to do, it did
    1  at least one file failed
    2  aq-ingest could not start (bad settings, missing ffmpeg, nothing to do)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__, notify, runner
from .config import (
    ConfigError,
    Settings,
    default_config_path,
    load_settings,
    with_overrides,
)
from .tools import ToolMissing

DESCRIPTION = """\
Make camera, phone and drone files ready for video editing.

aq-ingest looks at each file, works out what a video editor would choke on
(silent sound, a video format the free DaVinci Resolve cannot open, a phone's
changing frame rate, an iPhone HEIC photo) and writes a fixed copy next to it.
Your original files are never changed.
"""

EPILOG = """\
examples:
  aq-ingest ~/Videos/CardDump          fix everything in a folder
  aq-ingest --dry-run ~/Videos/A001    show what would happen, change nothing
  aq-ingest --force clip.MP4           redo a file even if a fixed copy exists

You do not have to use the terminal at all: in the file manager, right-click a camera
card, a folder or a selection of clips and choose "Make Editor-Ready". That runs this same
command with --notify, so the progress and the result arrive as desktop notifications.

Settings live in ~/.config/aquarius/ingest.toml and a record of every run is kept in
~/.local/state/aquarius/ingest.log
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aq-ingest",
        description=DESCRIPTION,
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("paths", nargs="*", type=Path, help="files or folders to make ready")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the plan and write nothing at all",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="redo files that already have an up-to-date fixed copy",
    )
    parser.add_argument(
        "--force-transcode",
        action="store_true",
        help="fully convert everything, even files that would only need a quick repack",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help=f"use a different settings file (default: {default_config_path()})",
    )
    parser.add_argument(
        "--resolve-edition",
        choices=("free", "studio"),
        default=None,
        help="override the resolve_edition setting for this run",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the report as JSON instead of plain text",
    )
    parser.add_argument(
        "--notify",
        action="store_true",
        help="report progress and the result as desktop notifications "
        "(this is how the file manager's right-click menu runs it)",
    )
    parser.add_argument("--version", action="version", version=f"aq-ingest {__version__}")
    return parser


#: Messages that only repeat what the status column already said.
_OBVIOUS = {"up to date", "already editor-ready", "unrecognized — left alone"}


def _wants_detail(result: runner.Result) -> bool:
    if result.message in _OBVIOUS:
        return False
    if result.status in (runner.FAILED, runner.LEFT_ALONE, runner.PLANNED):
        return True
    return "vfr-conformed" in result.flags


def _print_human(results: list[runner.Result], summary: str, log_file: Path | None) -> None:
    folders: list[str] = []
    for result in results:
        line = f"  {result.status:<20} {result.source.name}"
        if result.output:
            line += f"  ->  {result.output.name}"
        print(line)
        if _wants_detail(result):
            for detail in result.message.splitlines():
                print(f"      {detail}")
        if result.output and result.status in (
            runner.REWRAPPED,
            runner.TRANSCODED,
            runner.CONVERTED,
            runner.PLANNED,
        ):
            folder = str(result.output.parent)
            if folder not in folders:
                folders.append(folder)

    print()
    print(summary)
    for folder in folders:
        print(f"Fixed copies are in: {folder}")
    if log_file:
        print(f"Full record: {log_file}")


def make_notifier(args: argparse.Namespace) -> notify.Notifier:
    """The one place a Notifier is built, so tests can swap it for a fake."""
    return notify.Notifier(enabled=args.notify, dry_run=args.dry_run)


def _stop(notifier: notify.Notifier, message: str) -> int:
    """Report a we-cannot-start problem on both the terminal and the desktop."""
    print(message, file=sys.stderr)
    notifier.failure(message)
    return 2


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.paths:
        parser.print_help()
        print("\nTell aq-ingest which files or folders to work on.", file=sys.stderr)
        return 2

    notifier = make_notifier(args)

    try:
        settings: Settings = load_settings(args.config, create=not args.dry_run)
    except ConfigError as exc:
        return _stop(notifier, f"aq-ingest could not start.\n{exc}")
    settings = with_overrides(settings, resolve_edition=args.resolve_edition)

    jobs, problems = runner.collect_inputs(list(args.paths))
    for problem in problems:
        print(problem, file=sys.stderr)

    if not jobs:
        if problems:
            notifier.failure("\n".join(problems))
            return 2
        return _stop(notifier, "Nothing to do — no files were found in what you gave me.")

    total = len(jobs)
    notifier.start(total)

    results: list[runner.Result] = []
    try:
        for done, (source, root) in enumerate(jobs, start=1):
            results.append(
                runner.process_one(
                    source,
                    root,
                    settings,
                    dry_run=args.dry_run,
                    force=args.force,
                    force_transcode=args.force_transcode,
                )
            )
            notifier.progress(done, total, source.name)
    except ToolMissing as exc:
        return _stop(notifier, f"aq-ingest cannot run.\n{exc}")

    summary = runner.summarize(results)
    if args.dry_run:
        summary = f"Dry run — nothing was written. {summary}"

    log_file = None if args.dry_run else runner.write_log(results, summary)

    if args.json:
        print(
            json.dumps(
                {
                    "summary": summary,
                    "dry_run": args.dry_run,
                    "log": str(log_file) if log_file else None,
                    "results": [r.as_dict() for r in results],
                },
                indent=2,
            )
        )
    else:
        _print_human(results, summary, log_file)

    # Last, so a notification never appears before the work behind it is finished.
    notifier.finish(results, summary, log_file)

    failures = [r for r in results if r.status == runner.FAILED]
    if failures:
        print(
            f"\n{len(failures)} file(s) failed. Nothing was lost — your originals are untouched.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
