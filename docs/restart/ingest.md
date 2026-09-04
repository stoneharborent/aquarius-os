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

A notification says it has started, another counts the progress, and a last one
tells you what happened. Editor-friendly copies appear in a folder called
**EditorReady** next to the originals.

**Your original files are never touched.** Not renamed, not moved, not
modified. The tool treats them as read-only.

> ⚠️ **Right-click the card's FOLDER in the file list, not the device in the
> sidebar.** The sidebar entry is a place, not a folder, and the menu does not
> appear on it. Open the card first, then right-click.

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

## Bench test, for Royce

The point of this test is a **real camera file**, not a synthetic one. The 95
automated tests already cover every branch of the decision table with generated
fixtures; what they cannot prove is that a file from your actual camera, on
your actual machine, ends up in Resolve with sound.

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

7. **Try the watch folder.**
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

8. **If anything goes wrong**, these three answer almost every question:
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
