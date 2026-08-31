# aq-ingest — "Make Editor-Ready"

**What it does, in one sentence:** you point it at files from a camera, phone or drone, and
it puts editor-friendly copies next to them, so DaVinci Resolve (and Kdenlive, and Blender)
open them with picture *and* sound.

Your original files are never changed, never moved, never deleted. Ever.

---

## Why this exists

On Windows and Mac, Microsoft and Apple paid the licence fees for the compression formats
cameras use. On Linux nobody did, so each app has to bring its own — and DaVinci Resolve
does not bring all of them. The result:

- The **free** Resolve cannot open a normal camera MP4 at all.
- **Even paid Resolve Studio** imports normal camera MP4s with **no sound**.
- iPhone HEIC photos will not import anywhere.
- Phone videos recorded at a "changing" frame rate slowly drift out of sync.

None of that is fixable inside Resolve. It *is* fixable before Resolve ever sees the file,
which is what this tool does.

Background reading (no jargon): `../docs/codec-research.md`.
The full design: `../docs/ingest-helper-spec.md`.

---

## How to use it

**The normal way: right-click.** In the Files app, right-click a camera card, a folder,
or a selection of clips and choose **Make Editor-Ready**. No terminal, no window — it
works in the background and tells you what it did with desktop notifications. This works
the same way on both flavours of AquariusOS: in Dolphin on the KDE images and in Nautilus
on the GNOME ones. The beginner walkthrough, with pictures of what each message means, is
[`../docs/ingest-right-click.md`](../docs/ingest-right-click.md).

**The terminal way**, which is the same tool with the same options:

```bash
# Fix everything in a folder (it looks in sub-folders too)
aq-ingest ~/Videos/CardDump

# See what it WOULD do, without changing anything at all
aq-ingest --dry-run ~/Videos/CardDump

# Fix one file
aq-ingest ~/Videos/C0001.MP4
```

Fixed copies appear in a folder called **`EditorReady`** next to your files. Open those in
your editor.

Useful extras:

| Option | What it does |
|---|---|
| `--dry-run` | Shows the plan. Writes nothing — not even the log. |
| `--force` | Redoes a file even if a good copy already exists. |
| `--force-transcode` | Fully converts everything, even files that only needed a quick repack. Use it when a file still refuses to import. |
| `--resolve-edition studio` | Just for this run, treat you as a Resolve **Studio** owner (much faster — see below). |
| `--json` | Prints the report as JSON. For other programs, not for people. |
| `--notify` | Report progress and the result as desktop notifications. This is what the right-click menu uses; there is no reason to type it yourself. |

Run `aq-ingest --help` at any time.

### Running it before it is installed in the OS

While it is still just files in this repo:

```bash
cd os-image/ingest
./aq-ingest --dry-run ~/Videos/CardDump
```

You need `ffmpeg` installed (AquariusOS ships it). For iPhone HEIC photos you also need
`heif-convert`, which comes from the `libheif-tools` package (`libheif-examples` on
Debian/Ubuntu).

---

## What it decides, and why

For every file it looks inside, then does exactly one of these:

| What it finds | What it does |
|---|---|
| Professional camera formats (BRAW, R3D, ARRIRAW, ProRes, DNxHR, WAV, EXR, PNG…) | **Nothing.** These already work. It says "already editor-ready". |
| iPhone HEIC photo | Converts to **PNG** (or JPEG, your choice). |
| Video with a changing frame rate | **Full conversion**, locked to a steady frame rate. This is the only way to stop sound drifting. |
| VP8/VP9 web video | **Full conversion.** Resolve cannot open these anywhere. |
| Normal camera video (H.264/H.265), free Resolve | **Full conversion**, because free Resolve cannot open it at all. |
| Normal camera video, Resolve **Studio** | **Quick repack** — the picture is copied across untouched (seconds, no quality loss) and only the sound is converted. |
| AV1 video | **Nothing**, plus a note. It may already work on your machine; if it does not, run again with `--force-transcode`. |
| Anything it does not recognize | **Nothing**, and it says so. It never guesses. |

"Full conversion" means DNxHR in a `.mov` file — a professional editing format Resolve
handles perfectly. It makes bigger files than the camera original, and that is normal and
expected for editing.

**Tell it if you own Resolve Studio.** It makes most files process in seconds instead of
minutes. Edit `~/.config/aquarius/ingest.toml` and set:

```toml
resolve_edition = "studio"
```

---

## Settings

The settings file is created for you the first time you run the tool, at
`~/.config/aquarius/ingest.toml`, with notes on every line. Every setting is explained
there in plain English.

A record of every run is kept at `~/.local/state/aquarius/ingest.log`.

---

## For developers

- Python 3.11+, standard library only. It shells out to `ffprobe`/`ffmpeg`.
- `aq_ingest/rules.py` is the decision engine and is **pure** — probe data in, a plan out,
  no disk access, no subprocesses, no printing. AquariusTransfer imports it later, so keep
  it that way.
- `aq_ingest/probe.py` runs ffprobe and builds the dictionary `rules.py` expects.
- `aq_ingest/actions.py` holds the ffmpeg command lines. Every output is written to a
  hidden part-file and moved into place only on success.
- `aq_ingest/runner.py` walks the inputs, applies the "never overwrite" rules, and reports.
- `aq_ingest/cli.py` is the argparse front end. Exit codes: `0` fine, `1` a file failed,
  `2` could not start.
- `aq_ingest/notify.py` is the desktop-notification layer (`--notify`). The wording
  functions are pure; the `Notifier` funnels every outside call through one place that
  cannot raise, because a notification must never be able to break a run.

### How it gets into the OS

- The Dolphin menu item is `system_files/usr/share/kio/servicemenus/aquarius-make-editor-ready.desktop`
  — Plasma 6's folder, not Plasma 5's, and it has to stay executable or KDE ignores it.
- The Nautilus menu item is `system_files/usr/share/nautilus-python/extensions/aquarius_editor_ready.py`.
  GNOME has no settings-file way to add a menu item, so this one is a small Python program.
  It needs the `nautilus-python` package, which `build_files/gnome-desktop.sh` installs on
  the GNOME images. Both files ship on both images and each is ignored where it does not
  belong; `tests/test_desktop.py` compares them so the two cannot drift apart.
- `build_files/build.sh` installs `aq-ingest` to `/usr/bin/` and this package into Python's
  own `site-packages`, and fails the build if the command won't start. The Containerfile's
  `COPY ingest /ingest` line is what makes this folder visible to that step.
- `tests/test_desktop.py` guards all of the above, so a wiring change that would silently
  kill the right-click menu fails a test instead.

### Running the tests

The test suite makes all of its own test footage with ffmpeg — no real camera files needed.

```bash
cd os-image/ingest
python3 -m unittest discover -s tests -t . -v
```

Everything passes on a machine with ffmpeg. Tests that need tools you do not have (for
example `heif-enc` for the iPhone-photo test) are **skipped with a message saying why**,
never silently. GitHub Actions installs everything and runs the whole suite on every push
that touches this folder.
