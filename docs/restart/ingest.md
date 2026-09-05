# Making camera files open in a video editor

*The ingest helper. Phase R3b, written 2026-09-04. Written for somebody who has
never used Linux.*

---

## The problem this exists to solve

**The free DaVinci Resolve on Linux cannot open a file from a camera or a
phone.** Not "opens it badly" — cannot open it.

- H.264 and H.265 — what every camera and every phone records — can only be
  decoded by Resolve **Studio**, and only on **NVIDIA**.
- AAC — the sound track in almost every one of those files — is not supported
  by **any** version of Resolve on Linux. Import the clip and it has picture
  and **no sound at all**, with no error message.

Every person who tries Resolve on Linux hits this on their first import, and
most of them conclude that Linux is not for editing. Nobody fixes it at the
operating-system level.

AquariusOS does. That is why this small tool is a flagship feature and not a
utility.

---

## How you use it

### The right-click way (the main way)

1. Open **Files** and go to the folder with your clips — the card, the phone's
   folder, wherever they are.
2. Select the files, or the whole folder.
3. Right-click → **Make Editor-Ready**.

**One notification appears and stays there, filling up**, until the work is
done. Editor-friendly copies appear in a folder called **EditorReady** next to
the originals.

**Your original files are never touched.** Not renamed, not moved, not
modified. The tool treats them as read-only.

> ⚠️ **Right-click the card's FOLDER in the file list, not the device in the
> sidebar.** The sidebar entry is a place, not a folder, and the menu does not
> appear on it. Open the card first, then right-click.

---

## Watching it work

*Added 2026-09-04, because Royce asked for it after the first bench test: the
old notification said it had started and then went quiet for the several minutes
a real camera clip takes.*

There is now **one** notification for the whole job, and it is redrawn in place
rather than joined by more:

```
┌────────────────────────────────────────────────┐
│ ⬤  Making your files editor-ready            × │
│    Converting A001_C003.MP4 · 42% ·             │
│    about 2 min left                             │
│    ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░                  │
└────────────────────────────────────────────────┘
```

When it finishes, that same notification becomes the answer:

```
┌────────────────────────────────────────────────┐
│ ⬤  A001_C003.MP4 is editor-ready             × │
│    1 transcoded, 0 failed                       │
│    The fixed copy is in: /run/media/…/EditorReady│
│    [ Show in Files ]                            │
└────────────────────────────────────────────────┘
```

**Converting several files at once** counts them: `Converting 12 files · 3 of
12 · 24% · about 9 min left`.

### Where the numbers come from

**The percentage** is ffmpeg's own. It is asked to report itself, and it says how
many seconds of the new file it has written; divided by how long the clip is,
that is the percentage. Nothing is estimated or guessed at.

Every file in a run counts the same amount, though — a ten-second clip and a
ten-minute clip each move the bar by the same step. Weighting them by length
would mean reading all 200 clips on a card before starting the first one, which
is a minute of nothing happening at the start of every offload.

**The time left** is elapsed time scaled by how much is left to do, then
smoothed, so a slow few seconds does not turn "2 min" into "20 min" and back
again. For the first couple of seconds it says nothing at all, because any guess
made that early is wrong by minutes. It is deliberately vague — "about 3 min
left", never "3 minutes 14 seconds" — because vague is what we actually know.

### What it looks like in each desktop

| Where | What you see |
| --- | --- |
| **The Aquarius Desktop** (our own shell) | The bar, drawn in the accent colour, in the popup and again in the notifications panel if you open it. The popup does **not** time out while the job is running — it stays until the job is done. |
| **GNOME** (the fallback session) | The same one notification, updating in place, with the percentage and the time left **in the words**: "Converting A001_C003.MP4 · 42% · about 2 min left". GNOME Shell has no progress bar in its notifications and ignores the bar part outright — which is exactly why the numbers are written into the sentence as well. |
| **A terminal** (`aq ingest …`) | One line at the bottom, rewritten in place: `Converting A001_C003.MP4 · 42% · about 2 min left`. It is wiped before the report is printed. Nothing is drawn if the output is going into a file or a pipe. |

### The terminal way

```
aq ingest ~/Videos/Card1
aq ingest --dry-run ~/Videos/Card1     # say what would happen, write nothing
```

`aq ingest` is a front door onto the same program the right-click menu runs
(`aq-ingest`). Anything that program accepts, this accepts.

### The automatic way — a watch folder

**Off until you turn it on.**

```
aq ingest watch on          # watch ~/Videos/Ingest
aq ingest watch status      # what is being watched, and what happened last
aq ingest watch off
```

With it on, anything you drop into `~/Videos/Ingest` is converted a few seconds
later, with no clicking. It is the fastest route for phone footage: send the
clip with **LocalSend** straight into that folder and it is editor-ready by the
time you have put the phone down.

Two things worth knowing:

- **It waits until the file has finished arriving.** A folder "changes" the
  moment a copy *starts*, and converting a half-copied file gives a broken
  result. Nothing is touched until its size has stopped changing for three
  seconds, and obviously-in-progress names (`.part`, `.tmp`, `.crdownload`, and
  anything beginning with a dot) are skipped outright.
- **It gets out of the way.** The conversion runs at low priority, so a big drop
  never fights the editor you are actually using for the machine.

It is off by default because the right-click menu is the main surface and a
folder that converts things without being asked is a folder you cannot predict.
That was the specification's own choice, not an oversight.

---

## What it actually does to a file

It looks at each file and picks exactly one action. There is no guessing: if it
does not recognise something, it says so and leaves it alone.

| What it finds | What it does | Why |
| --- | --- | --- |
| A file that already works — ProRes, DNxHR, BRAW, R3D, WAV, PNG… | **Nothing.** Reports "already editor-ready". | It opens in Resolve today. |
| An iPhone HEIC photo | Converts to PNG. | Resolve and Kdenlive cannot read HEIC. |
| A phone clip with a wobbly frame rate | Converts to DNxHR at a proper fixed frame rate, sound to PCM. | A variable frame rate makes the sound drift out of sync in every editor, and no amount of container fiddling fixes timing. |
| H.264 or H.265 video (a camera or phone clip) | Converts to DNxHR, sound to PCM. | The free Resolve cannot decode either. |
| A file whose picture is fine but whose sound is AAC, AC-3 or DTS | **Rewraps** — the picture is copied across untouched, in seconds, with the sound converted. | This is the classic silent-audio fix: no re-encoding, no quality loss, no waiting. |
| AV1 | Nothing, with a note. | It may work; it depends on the graphics card. Re-running with `--force-transcode` converts it if it does not. |
| Anything else | Nothing, and says so. | Honesty over magic. |

**The results open in everything**, not just Resolve — Kdenlive, Blender, and
anything else you point at them.

**It is safe to run twice.** If an output already exists and is newer than its
source, it is skipped and reported as "up to date". That is what makes the
watch folder and repeated right-clicks harmless.

---

## Settings

`~/.config/aquarius/ingest.toml`, created with commented defaults the first
time it runs.

The one worth knowing about:

```toml
resolve_edition = "free"   # change to "studio" if you own DaVinci Resolve Studio
```

With `"free"` — the default — H.264 and H.265 clips get a full conversion,
which is slower and produces bigger files, but they always import. With
`"studio"` on an NVIDIA machine, Resolve can decode them itself, so those clips
get the fast rewrap instead: seconds rather than minutes, and no quality loss.

**If you have Resolve Studio, change this.** It is the single biggest
difference to how long an offload takes.

The log of everything it has ever done is at
`~/.local/state/aquarius/ingest.log`.

---

## If the right-click menu is missing

**Fixed on 2026-09-04. This section is here so the next person recognises it.**

The symptom is that you right-click a video in Files and there is no **Make
Editor-Ready** in the menu. Nothing else is wrong: the terminal way (`aq
ingest`) still works, no error appears, no notification, nothing in the log.

That silence is the point. GNOME Files never tells you when one of its
extensions fails to load — the menu item is simply not there.

**Two things to try first**, in this order:

1. **Restart Files**, then try again:
   ```
   nautilus -q
   ```
   Files starts again by itself the next time you open a folder. Do this after
   every system update: Files keeps running in the background, and a copy that
   started before the update is still using the old extension.

2. **Right-click the card's folder in the file list, not the device in the
   sidebar.** The sidebar entry is a place, not a folder, and no menu item
   appears on it.

**If it is still missing**, ask Files to say what went wrong. Close it first,
then start it from a terminal with its debugging switched on:

```
nautilus -q
NAUTILUS_PYTHON_DEBUG=misc nautilus
```

Right-click a video in the window that opens and read the terminal. A broken
extension prints a traceback there and nowhere else.

### The one that happened, 2026-09-04

On the bench machine (Fedora 44, `nautilus-50.3`, `nautilus-python-4.1.0`) that
command printed:

```
File "/usr/share/nautilus-python/extensions/aquarius_editor_ready.py", line 54, in <module>
    gi.require_version("Nautilus", "4.0")
ValueError: Namespace Nautilus is already loaded with version 4.1
```

In plain English: our menu file asked for version 4.0 of the plug-in interface,
and the Files that Fedora 44 ships had already loaded version 4.1 of it. The
two cannot both be true, so Python stopped reading our file at that line — a
long way before the line that adds the menu item.

The fix was to stop naming one version: the file now asks for the newest
interface it knows about, falls back to the older one, and accepts whichever
version Files has already loaded. It ships in every image built after
2026-09-04.

**Why the build did not catch it:** the build checked that the file *compiled*,
and it did — this failure only happens when the file *runs*. Every build now
loads the extension inside the finished image, hands it a pretend `clip.mp4`,
and refuses to publish unless a "Make Editor-Ready" item comes back
(`ingest/tests/test_nautilus_extension.py`, run by the
"Check the 'Make Editor-Ready' menu really loads in Files" step).

---

## Bench test, for Royce

The point of this test is a **real camera file**, not a synthetic one. The 159
automated tests already cover every branch of the decision table with generated
fixtures, and the progress arithmetic against a clock they control; what they
cannot prove is that a file from your actual camera, on your actual machine,
ends up in Resolve with sound — or that a bar filling up on a real screen looks
right.

1. **Get a real file onto the machine.** Either put a card in the reader, or
   send a clip from your phone with **LocalSend** (it is one of the
   preinstalled apps). What you want is an ordinary **H.264 + AAC MP4** —
   which is what a phone and most cameras produce.

2. **Prove the problem first.** Open the clip in **DaVinci Resolve** (R3a's
   container — `aq resolve`, or the app-grid entry) and import the original.
   Expect: it either refuses to import, or imports with **picture and no
   sound**. This step matters — it is what makes the next one meaningful.

3. **Right-click → Make Editor-Ready.** In Files, right-click the clip. Watch
   for the notification. When it finishes there should be an `EditorReady`
   folder beside the original, with a `.mov` in it.

4. **Import the new file into Resolve.** Expect: it imports, it plays, and
   **it has sound**. Scrub the timeline and check the sound stays in sync to
   the end of the clip — that is the check that catches a wobbly frame rate.

5. **Open the same file in Kdenlive.** Expect: it imports and plays there too.
   This is the "works for more than Resolve" promise.

6. **Check the original is untouched.** Same name, same size, same date, in
   the same place.

7. **Watch the progress bar on a clip that takes a while.** This is the
   2026-09-04 request, and it needs a clip long enough to have progress worth
   showing — **a minute or two of 4K**, not a five-second test.

   Right-click it → **Make Editor-Ready**, then watch the notification. Expect,
   in order:

   - one notification, saying "Making your files editor-ready";
   - a bar under the text that **fills up**, with a percentage beside it;
   - "about N min left" appearing after a couple of seconds and counting down
     without jumping about;
   - the popup **staying on screen** for the whole conversion rather than
     disappearing after five seconds;
   - and at the end, that **same** notification — not a second one — turning
     into "clip.MP4 is editor-ready", with a **Show in Files** button that
     opens the EditorReady folder.

   Then log out into **GNOME** and do it again. Expect the same single
   notification updating in place, with the percentage and the time left in the
   text. There is no bar there, and that is GNOME's own limitation, not a fault.

   And once in a terminal:
   ```
   aq ingest ~/Videos/that-clip.MP4
   ```
   Expect one line rewriting itself at the bottom of the terminal, wiped when
   the report prints.

   **If the bar never moves**, the first thing to check is that this is really a
   long clip: a file that converts in under a second only ever reports "done".
   ```
   aq ingest --dry-run <the file>     # says what it thinks the file is
   ```

8. **Try the watch folder.**
   ```
   aq ingest watch on
   ```
   Then send another clip from your phone with LocalSend, choosing
   `~/Videos/Ingest` as the destination. Within a few seconds an `EditorReady`
   folder should appear inside it with the converted file. Then:
   ```
   aq ingest watch status     # should say it is watching and listening
   aq ingest watch off
   ```

9. **If anything goes wrong**, these three answer almost every question:
   ```
   aq ingest watch status
   cat ~/.local/state/aquarius/ingest.log
   aq ingest --dry-run <the file>      # says what it thinks the file is
   ```

### If you own Resolve Studio

Do step 3 again after setting `resolve_edition = "studio"` in
`~/.config/aquarius/ingest.toml`. The same clip should now take **seconds**
instead of minutes, and the resulting file should be much smaller — because it
is rewrapping the picture rather than re-encoding it. Then check it still
imports into Resolve with sound.
