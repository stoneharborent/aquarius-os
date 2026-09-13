# Screenshots and screen recording

*Written 2026-09-13 for Phase R8 (FEATURES 017). Assumes you have never used
Linux and have never typed a command on purpose.*

---

## The one-paragraph version

AquariusOS takes screenshots and records the screen with its own tool, and it
works the way a Mac works. Press **Command-Shift-3** for a picture of the whole
screen or **Command-Shift-4** to drag a box round part of it, and the picture
lands in a folder called **Screenshots** in your home folder — *and* on your
clipboard, so the very next thing you can do is paste it into the Editor, a chat
or an email. To film the screen instead, press **Command-Shift-6**, and
**Command-Shift-7** to stop. There is nothing to set up.

---

## The keys

If your keyboard is in **Mac style** (which is how AquariusOS arrives):

| Press | You get |
| --- | --- |
| **Command-Shift-3** | A picture of one whole monitor. Click the monitor you mean. |
| **Command-Shift-4** | Drag a box. You get a picture of exactly that box. |
| **Command-Shift-5** | A picture of a window — see [the honest bit](#the-honest-bit-picking-a-window) below. |
| **Command-Shift-6** | **Start** recording an area you drag. |
| **Command-Shift-7** | **Stop** recording, and keep the film. |

If your keyboard is in **Windows style** (`aq keys windows`):

| Press | You get |
| --- | --- |
| **Print Screen** | A picture of one whole monitor. |
| **Shift + Print Screen** | Drag a box. |
| **Win + Shift + S** | Drag a box. (Windows' own shortcut, if it is in your fingers.) |
| **Win + Shift + Print Screen** | A picture of a window. |
| **Win + Alt + R** | **Start** recording an area. |
| **Win + Alt + Shift + R** | **Stop** recording. |

There are also two buttons in the **top bar** — a camera and a record button —
and each one opens a little menu offering *Whole screen*, *An app*, and *Select
an area*. They do exactly the same thing the keys do. While a recording is
running, the record button turns red and counts the seconds; click it to stop.

**Escape cancels.** While the dimmed overlay is on the screen, pressing Escape
throws the whole thing away. Nothing is saved and nothing complains.

---

## Where everything goes

Everything lands in one folder:

```
Screenshots
```

— in your home folder, beside Documents and Downloads. It is **pinned in the
sidebar of the Files app**, so it is one click away and you never have to go
looking.

The names look like this, which is deliberate — they are exactly what a Mac
writes, so sorting the folder by name sorts it by time:

```
Screenshot 2026-09-13 at 14.02.11.png
Screen Recording 2026-09-13 at 14.02.11.mp4
```

Two small things worth knowing:

* **GNOME's screenshot tool saves here too.** GNOME is the other desktop on this
  computer and it has its own screenshot window, which we have not replaced.
  AquariusOS points it at the same folder, so you never end up with two piles in
  two places.
* **If you drag the Screenshots pin out of your sidebar, it stays out.** The
  computer offers it once, writes down that it has done so, and never puts it
  back. (Should you want it offered again, delete the file
  `~/.local/state/aquarius/capture-bookmark-done` and log in again.)

### Putting them somewhere else

Edit `~/.config/user-dirs.dirs`, find the line that says

```
XDG_SCREENSHOTS_DIR="$HOME/Screenshots"
```

and change the path. Both our tool and GNOME's read that line, so they will move
together. Files already saved stay where they are.

---

## The honest bit: picking a window

On a Mac, Command-Shift-4 then Space gives you a camera cursor: point at a
window, it lights up, click, and you get exactly that window. **AquariusOS
cannot do that today, and this page is not going to pretend otherwise.**

Here is why, in plain terms. To cut out exactly one window, the tool has to be
able to ask *"where is that window, and how big is it?"*. On Wayland — the modern
way Linux draws a screen — the list of open windows is published through a
standard that carries the app, the title, and whether the window is minimised,
and deliberately **carries no position or size at all**. That was a privacy
decision by the people who wrote it: they did not want any program able to map
out your screen. It is the same list our app switcher draws from, and the reason
the switcher can show you one big icon per app but could never draw a thumbnail
in the right place.

Some Linux desktops get round this because they have a private side-channel of
their own that *does* publish window geometry — sway is the well-known one.
**labwc, the window manager underneath the Aquarius Desktop, has none.** We
checked the obvious candidate tool on Fedora (`wlrctl`) and it reads the same
standard, so it knows no more than we do.

So **"An app" asks you to drag a box round the window.** One extra second, and
it tells you the truth. It is on its own key and its own menu row so that the
day labwc can answer the question, nothing you have learned changes — the key
just gets better.

*(If you would rather that row grabbed the whole monitor the window is on — one
click, no dragging — set `AQ_CAPTURE_WINDOW_MODE=output` in your environment.)*

---

## Recordings: what you get, and what you do not

* **An MP4, H.264.** It opens in DaVinci Resolve, Aquarius Editor, QuickTime,
  Premiere, a phone, and a browser. No conversion step.
* **It uses your graphics card when it can.** On an NVIDIA machine it encodes
  with NVENC; on AMD and Intel with VA-API; and if neither is available it falls
  back to the processor. The choice is made on your machine at the moment you
  press record, because it depends on what is in the machine rather than on
  which AquariusOS you installed.
* **⚠️ THERE IS NO SOUND IN VERSION ONE.** Recordings are silent, on purpose.
  Getting "the system sound, and my microphone, and not a recording of itself"
  right is its own piece of work and it is a separate job on the list. If you
  need sound today, use **OBS Studio** from the app chooser.
* Annotations, delayed capture and GIF export are not here either. Each is a
  small follow-up.

**Stopping properly matters.** Press the stop key, or click the red button. That
gives the recorder a moment to write the little index at the end of the file
that makes an MP4 playable. Killing it from a task manager gives you a file
nothing will open.

---

## Doing it from a terminal

Everything above is one program, and you can run it yourself:

```
/usr/libexec/aquarius-capture shot screen      # a picture of a whole monitor
/usr/libexec/aquarius-capture shot area        # drag a box
/usr/libexec/aquarius-capture shot window      # drag a box round a window

/usr/libexec/aquarius-capture record area      # start filming
/usr/libexec/aquarius-capture record stop      # stop, and keep the film

/usr/libexec/aquarius-capture status           # is it filming?
/usr/libexec/aquarius-capture folder           # where do the files go?
/usr/libexec/aquarius-capture --help           # all of this, in the program
```

`shot` and `record stop` print the path of the file they saved, so you can hand
it straight to something else. This is also the **best way to find out why a key
did nothing**: run the same command in a terminal and read what it says.

---

## What it is made of

Four small programs, none of them ours, all ordinary Fedora packages:

| Program | Its job |
| --- | --- |
| `grim` | Takes the picture. |
| `slurp` | Draws the dimmed overlay you drag on. (It was already here — it is what the screen-sharing pop-up uses to ask which screen.) |
| `wl-copy` | Puts the picture on the clipboard. |
| `wf-recorder` | Films, and hands the frames to ffmpeg. |

**Why `wf-recorder` and not `wl-screenrec`?** Because Fedora 44 packages
wf-recorder (version 0.6.0) in its ordinary repositories and does not package
wl-screenrec at all. Using it meant adding nothing new to trust and nothing new
to break at an update, which for a machine somebody edits on is worth more than
any difference between the two. It also comes from the same people as `grim` and
hands its frames straight to the full ffmpeg that AquariusOS already installs —
which is where the hardware encoding comes from.

Our own part is one program, `/usr/libexec/aquarius-capture`, which decides the
file names, the folder, the clipboard, the notification and the encoder. Read its
header if you want the long version; it is written for a person, not a compiler.

---

## When it goes wrong

**A key does nothing.**
Run the same thing in a terminal — `/usr/libexec/aquarius-capture shot area` —
and read the answer. If *that* works, the problem is the key rather than the
tool: check which keyboard style you are in with `aq keys status`.

**Nothing happens in GNOME.**
GNOME answers these keys with its own screenshot window, which is expected and
is not a fault. It saves into the same Screenshots folder.

**"Nothing was captured."**
You clicked instead of dragging, so the box had no size. Drag.

**The recording will not start.**
The recorder writes down why it failed. Read it with:

```
cat "$XDG_RUNTIME_DIR/aquarius-capture/recorder.log"
```

The usual cause on a fresh machine is that the graphics card's encoder is not
available to your account; the tool falls back to the processor by itself, so if
you are seeing this, something more unusual is going on and that file will say
what.

**The bar says it is recording and it is not.**
Ask the tool: `/usr/libexec/aquarius-capture status`. If it answers
`{"recording":false,...}` the bar is simply behind — it catches up within a
second. The tool clears away the leftovers of a recorder that died all by
itself, and everything it remembers lives in a folder that is wiped when you log
out, so logging out and back in always clears it.

**There is no Screenshots folder and no pin in Files.**
The folder is made at login by a small service. Ask it what happened:

```
systemctl --user status aquarius-capture-setup
journalctl --user -u aquarius-capture-setup -b
```

Or just make it happen now: `/usr/libexec/aquarius-capture setup`.

---

## Bench check for Royce

Six captures, then three checks. Ten minutes, on the machine, in the Aquarius
Desktop. Write what you find into `docs/design/bench-run-<date>.md`.

1. **Command-Shift-3.** Click a monitor. A notification appears saying
   "Screenshot saved".
2. **Command-Shift-4.** Drag a box. Same.
3. **Command-Shift-5.** Drag a box round a window. Same. *(This one is supposed
   to ask you to drag — see [the honest bit](#the-honest-bit-picking-a-window).)*
4. **Command-Shift-6**, drag a box, count to thirty, **Command-Shift-7.** A
   notification names the film.
5. Repeat 1 and 4 from the **top bar buttons** instead of the keys. While the
   recording runs, the record button should be red and counting.
6. On a **second monitor**, if one is plugged in: does Command-Shift-3 let you
   choose which one?

Then:

7. Open **Files**. Is **Screenshots** in the sidebar? Are all six files in it,
   named `Screenshot 2026-… .png` and `Screen Recording 2026-… .mp4`?
8. Take one more screenshot and **paste it straight into Aquarius Editor** —
   Command-V, no file dialogue. Does the picture arrive?
9. Drag the thirty-second recording into the Editor, or into Resolve. **Does it
   play, and does the timeline show the full thirty seconds?** (A recording that
   plays but is a few seconds short means the stop did not finish the file
   properly — say so, it is the one failure this feature is most likely to have.)

And one thing to look at rather than test: the recording is **silent**. That is
version one working as intended, not a fault.

---

## For the person maintaining this

* The image half is `build_files/71-capture.sh`, which installs the four tools
  and then reads back every one of them, the helper, the login service, and each
  keyboard shortcut in `rc.xml` and `mac.yaml`.
* The helper is `system_files/usr/libexec/aquarius-capture`.
* The top bar's buttons live in the **aquarius-shell** repository and talk to
  this by *running the program* — never by reaching into the compositor. That is
  the one architectural law of that repo. The agreed wording (`status` printing
  JSON once a second, `record` writing
  `$XDG_RUNTIME_DIR/aquarius-capture/recording.json`) is set out in the helper's
  header and is what `tests/test-capture.sh` exists to protect.
* `rc.xml` is one of the **four labwc files mirrored between os-image and
  aquarius-shell**. Change one copy and `build_files/check-labwc-drift.sh` will
  tell you about the other.
* **Windows mode adds no keyboard rules on purpose.** Its keys are already the
  real keys. `windows.yaml` having no rules is what keeps the keyboard remapper
  switched off in that mode entirely, which is a safety property rather than an
  optimisation.
