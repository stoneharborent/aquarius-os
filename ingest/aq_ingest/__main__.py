"""Allows ``python3 -m aq_ingest …`` as well as the installed ``aq-ingest`` command."""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())
