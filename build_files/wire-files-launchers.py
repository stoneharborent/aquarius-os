#!/usr/bin/python3
"""Route Fedora's Files entries through our temporary GTK crash workaround.

Keep translations, desktop actions, arguments and D-Bus activation intact.
Refuse unknown commands so a future package change cannot silently bypass it.
"""
from pathlib import Path
import re
import sys

WRAPPER = "/usr/libexec/aquarius-files"


def rewrite(path):
    text = path.read_text()
    lines = text.splitlines(keepends=True)
    count = 0
    for i, line in enumerate(lines):
        if not line.startswith("Exec="):
            continue
        match = re.match(r"Exec=(?:/usr/bin/nautilus|nautilus|" + re.escape(WRAPPER) + r")(?=\s|$)", line)
        if not match:
            raise ValueError(f"Unrecognized Files command in {path}: {line.rstrip()}")
        lines[i] = "Exec=" + WRAPPER + line[match.end():]
        count += 1
    if not count:
        raise ValueError(f"No Exec entry in {path}")
    return "".join(lines)


def main():
    paths = [Path(p) for p in sys.argv[1:]]
    if len(paths) != 2:
        raise SystemExit("usage: wire-files-launchers.py DESKTOP_FILE DBUS_SERVICE")
    updates = [(p, rewrite(p)) for p in paths]
    for path, text in updates:
        path.write_text(text)
        if path.read_text() != text:
            raise RuntimeError(f"Files launcher read-back failed: {path}")
        print(f"Files launcher checked: {path}")


if __name__ == "__main__":
    main()
