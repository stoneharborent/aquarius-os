# How to get a camera card ready for editing

*For anyone using AquariusOS. No Linux knowledge needed — you never have to open a
terminal.*

---

## The short version

1. Plug the card in.
2. Open the card in the **Files** app (Dolphin).
3. **Right-click** the card, a folder, or just the clips you want.
4. Choose **Make Editor-Ready**.
5. Wait for the notification that says it's done. Click **Open folder**.
6. Import the files from the new **`EditorReady`** folder into DaVinci Resolve.

Your original camera files are never changed, moved, or deleted. The tool only ever writes
new copies.

---

## Why this step exists at all

Camera clips look fine on the card. Then you drag one into DaVinci Resolve on Linux and it
either has no sound, or it won't import at all.

That isn't a bug in Resolve, and it isn't something you did wrong. On Windows and Mac,
Microsoft and Apple pay licence fees for the compression formats cameras use. On Linux
nobody does, so every app has to bring its own — and Resolve doesn't bring all of them:

- The **free** version of Resolve can't open a normal camera MP4 at all.
- **Even the paid Studio version** imports normal camera MP4s with **no sound**.
- iPhone HEIC photos won't import anywhere.
- Phone videos slowly drift out of sync, because phones don't record at a steady frame rate.

None of that can be fixed inside Resolve. All of it can be fixed *before* Resolve sees the
file. That's the whole job of **Make Editor-Ready**.

---

## Step by step, with what you'll see

### 1. Right-click

Right-click **any** of these and you'll see **Make Editor-Ready** near the top of the menu:

- the camera card itself (or any folder — it looks inside sub-folders too),
- one clip,
- a whole selection of clips,
- an iPhone photo.

If the menu item isn't there, see *"It isn't in the menu"* below.

### 2. It starts working

No window opens and no terminal appears. Instead a notification slides in:

> **Making your files editor-ready**
> Working through 24 files. Your originals are not changed.

It updates as it goes (*"Finished 7 of 24 — C0007.MP4"*), so you can carry on doing
something else. Big cards take a while — see *"How long does it take"* below.

### 3. It tells you what it did

When it's finished you get one last notification with the real counts:

> **Your files are editor-ready**
> 18 rewrapped, 4 transcoded (1 VFR), 2 already editor-ready, 0 failed
> Fixed copies are in: /run/media/royce/CARD/EditorReady

with an **Open folder** button that takes you straight there.

Those words mean:

| Word | What happened |
|---|---|
| **rewrapped** | Quick fix — the picture was copied across untouched and only the sound was converted. Takes seconds. No quality lost. |
| **transcoded** | Full conversion, because the picture itself needed changing. Takes minutes. Makes bigger files, which is normal for editing. |
| **VFR** | That clip came from a phone and its frame rate wobbled; it's been locked to a steady rate so the sound won't drift. |
| **photos converted** | An iPhone HEIC photo became a PNG. |
| **already editor-ready** | Nothing needed doing. Professional formats (BRAW, R3D, ProRes, WAV…) are left completely alone. |
| **up to date** | You already ran this. Running it twice is safe and does nothing. |
| **left alone** | It didn't recognise the file, so it didn't touch it. It never guesses. |
| **failed** | Something went wrong on that file. It's named for you, and your original is fine. |

If anything failed, the notification turns red and stays on screen until you dismiss it.
The tool never says it worked when it didn't.

### 4. Import from `EditorReady`

Import from the new **`EditorReady`** folder, not from the originals. Keep the originals —
they're your negatives.

---

## Things you might reasonably ask

### It's making files much bigger than the camera's

That's expected, and it's the right trade. Editing formats are big on purpose so your
computer isn't unpacking heavy compression on every frame while you scrub. A minute of
4K can go from ~400 MB to several GB.

### How long does it take?

- **Rewrapping** is seconds per clip.
- **Full conversion** runs at roughly real time or faster, so an hour of footage is
  roughly an hour. Start it and go do something else.

### Do you own DaVinci Resolve **Studio** (the paid one)?

Tell the tool, and most files stop needing full conversion — they get the seconds-long
quick fix instead. Open this file (create it if it isn't there):

```
~/.config/aquarius/ingest.toml
```

and change one line to:

```toml
resolve_edition = "studio"
```

Save it. That's it. (Every setting in that file has a plain-English note above it.)

### A clip still won't import

Right-click it and choose Make Editor-Ready again — a second run skips everything that's
already done. If it still won't import, that clip needs the heavy hammer, which for now
means one terminal command:

```bash
aq-ingest --force-transcode ~/path/to/that/clip.MP4
```

### Where's the record of what happened?

```
~/.local/state/aquarius/ingest.log
```

Every run is appended to it, with every file and every failure.

### It isn't in the menu

Three things to check, in order:

1. **Is this AquariusOS?** The menu item ships with the OS. It won't be on stock Bazzite.
2. **Have you logged out since updating?** KDE reads its menus when you log in.
3. **Does the command exist?** Open a terminal and run `aq-ingest --version`. If that
   prints a version, the tool is installed and the problem is the menu file; if it says
   "command not found", the OS image didn't install it — that's a bug worth reporting.

---

## For whoever maintains this

The moving parts, and where they live in the `os-image` repo:

| Piece | Where |
|---|---|
| The menu item | `system_files/usr/share/kio/servicemenus/aquarius-make-editor-ready.desktop` |
| The tool | `ingest/` (source) → `/usr/bin/aq-ingest` + Python's site-packages (installed by `build_files/build.sh`) |
| Notification wording and behaviour | `ingest/aq_ingest/notify.py` |
| Tests for all of the above | `ingest/tests/` — `python3 -m unittest discover -s tests -t .` from `ingest/` |
| The design it implements | `../docs/ingest-helper-spec.md` |
| Why Linux needs this at all | `../docs/codec-research.md` |

Two things that will bite you:

- The service menu **must** be in `/usr/share/kio/servicemenus/` (Plasma 6). The Plasma 5
  folder was `/usr/share/kservices5/ServiceMenus/`; a file left there is ignored with no
  error anywhere.
- KDE **ignores a service menu whose file is not executable**. `build.sh` re-applies the
  executable bit inside the image, because not every way of copying files preserves it.

Still to come (spec §10): the watch folder (M3), the ProRes converter and its own menu
item (M4).
