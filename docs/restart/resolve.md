# DaVinci Resolve on AquariusOS

*Written 2026-09-04, for Phase R3a. Assumes you have never used Linux.*

---

## The short version

Open your apps, click **Install DaVinci Resolve**, pick the file you downloaded
from Blackmagic, and wait about fifteen minutes. A window shows you the six
steps as they happen. Resolve then sits in your dock like any other program, at
the same size as everything else on your screen and with your own mouse pointer.

You never see a terminal, and you never type anything. The way out is a window
too — **Remove DaVinci Resolve**, in the same place.

Everything below explains what happened and what to do when it does not.

> **A note on wording.** Resolve runs inside *its own protected environment* on
> this computer. That is what the windows call it and what this guide calls it
> in the parts written for you. Further down, in the part written for whoever
> maintains AquariusOS, it is called what it is: a Rocky Linux container. Same
> thing, two audiences.

---

## Why this is not just "install Resolve"

Two things are true about DaVinci Resolve on Linux, and AquariusOS is built
around both of them.

**One: nobody may hand out the installer.** Blackmagic's licence lets you
download Resolve from them and nobody else. It cannot be in AquariusOS, it
cannot be in the Fedora software centre, it cannot be in a Flatpak. Every Linux
has the same problem and every Linux solves it the same way — you download it,
and the system does the rest. Ours does more of the rest than most.

**Two: Resolve fights modern Linux, and it always has.** Resolve carries its own
copy of a piece of shared plumbing called *GLib*, from 2021. Modern Linux
systems have a much newer one, and a *third* piece of the system — the part that
draws text — asks Resolve's 2021 copy for something that did not exist in 2021.
Resolve dies before its window opens. You get either nothing, or a black
rectangle, and an error mentioning an "undefined symbol".

That is the single most common reason people give up on Resolve on Linux, and it
comes back every time a Linux distribution moves that plumbing forward. Which is
often.

**How AquariusOS answers both at once**

Blackmagic's only officially listed Linux for Resolve is **Rocky Linux 8.6** — a
2022 system. The film industry as a whole runs on the same family: the VFX
Reference Platform, which is the standard the studios agree on, requires
Enterprise Linux 9 from 2027 onward. Enterprise Linux is deliberately old and
deliberately still. Its GLib is *the same series Resolve carries*.

So AquariusOS runs Resolve inside a small **Rocky Linux 9** that lives on your
machine. In there, the clash is not worked around. It cannot happen. There is no
preloading trick, no patched library, nothing to break at the next update.

You will not notice it. Resolve appears in your apps, opens your ordinary
folders, and reads the card you plugged in. It is not a virtual machine and it
is not slow: it shares your computer's actual hardware, including the graphics
card, and it starts as fast as any other program.

**Is this a hack?** No — it is what the industry does. Universal Blue's
`davincibox` does exactly this with a Fedora container. We use the userland
Blackmagic themselves test against, which is the part everyone else skips.

---

## What you need

- **An NVIDIA graphics card.** This is Blackmagic's rule, not ours: NVIDIA is
  the only graphics vendor with official Resolve support on Linux, the only one
  with the CUDA compute Resolve uses, and the only one that can decode camera
  video in hardware. Royce's bench machine (an RTX 4090) is exactly the target.
  See *[If you have AMD or Intel](#if-you-have-amd-or-intel)* below for the
  honest position.
- **A recent driver.** Resolve 21 expects NVIDIA driver 580 or newer.
  AquariusOS ships the driver with the operating system, so `sudo bootc upgrade`
  is how you get a newer one. The setup checks and tells you.
- **About 15 GB free** — roughly 1 GB for the Rocky Linux, the rest for Resolve.
- **Your download from Blackmagic.**

---

## Doing it — the exact steps on the bench

> ### ⚠️ Read this first if you are testing before R3a is merged
>
> Until this branch merges into `restart/fedora-bootc`, the Rocky Linux runtime
> is published **only** under a development tag, so that a half-finished one can
> never overwrite what finished machines pull. The normal command will fail at
> "Downloading…" with a *manifest unknown* error, which is correct and not a
> fault.
>
> On the bench, run it like this instead:
>
> ```
> AQ_RESOLVE_RUNTIME_TAG=dev-restart-r3-resolve aq resolve install
> ```
>
> It prints a line saying it is using a runtime that is not the one this
> AquariusOS shipped with. Everything else is identical. After the merge, the
> plain command works and this note stops applying.
>
> The **Install DaVinci Resolve** button in the app grid cannot pass that
> setting, because nothing types anything into it. If you want the window
> *and* the development runtime, start the window from a terminal, where
> anything you set carries into it:
>
> ```
> AQ_RESOLVE_RUNTIME_TAG=dev-restart-r3-resolve aq resolve install --gui
> ```

### 1. Get the download

Go to <https://www.blackmagicdesign.com/products/davinciresolve>, choose **the
Linux version**, fill in their form, and save the file in your **Downloads**
folder.

Free or Studio both work. If you have bought Studio, use Studio — on Linux the
difference is much bigger than on a Mac, and the reason is in
*[The two things about codecs](#the-two-things-about-codecs-that-nobody-can-fix-inside-resolve)*
below.

> ### ⚠️ Do not open or run the file yourself
>
> If you double-click Blackmagic's installer on AquariusOS it will stop with a
> complaint about a missing package such as `zlib`. **Nothing is broken when
> that happens.** The installer expects an ordinary Linux where programs are
> installed one at a time; AquariusOS is not that kind of system, and the
> installer has to be run inside the container. That is the whole job of the
> next step. Just download the file and leave it alone.
>
> (This is not hypothetical. It happened to Royce on 2026-08-28 on the old
> Bazzite line, and half the wording in the setup script exists because of it.)

### 2. Run the setup

Press the **Super** key (the one with the Windows or Command symbol), type
**Install**, and click **Install DaVinci Resolve**.

A window opens. There are three pages and you will see all three.

**Page one — what will happen.** Two sentences saying what the setup is about to
do, and then two lines about your computer:

- **Your download.** If Blackmagic's file is already in your Downloads folder it
  is filled in for you and says so — *"Found DaVinci_Resolve_Studio_21.1_Linux.zip
  in /home/royce/Downloads"*. If it is somewhere else, click **Choose…** and pick
  it. If you have not downloaded it at all, that is fine too: **Get it from
  Blackmagic** opens their page, and if you press Install with nothing chosen the
  setup opens their page itself and then *waits*, for as long as you like, until
  the file appears.
- **Graphics card.** One honest line. On the bench it reads *"NVIDIA GeForce RTX
  4090 — CUDA ready"* with a tick beside it. On an AMD or Intel machine it says
  so, with a warning triangle, **before** you spend fifteen minutes finding out
  from Resolve.

Then click **Install**.

**Page two — the six steps.** A list, with a spinner on the step that is
happening and a tick on the ones that are done:

1. Checking your graphics card
2. Finding your download
3. Downloading the Rocky Linux runtime
4. Building the container
5. Installing DaVinci Resolve
6. Adding it to your apps

Underneath is a progress bar. During the download it fills properly, because
that is the one step where there is a real number to report; the rest of the
time it sweeps back and forth, which honestly means *"this is working and nobody
can say how long it will take"*. Step 5 is the long, quiet one.

Everything the old terminal window used to show is still there, behind
**Details**. Click it and the whole log is in front of you, scrolling as it
goes. It is worth a look the first time, and it opens **by itself** if anything
goes wrong.

**Cancel** really stops — the setup and everything underneath it. Nothing on
your computer is changed by stopping; the worst that can be left behind is a
half-built container, and the window tells you the one command that clears it.

**Page three — done.** *"DaVinci Resolve is installed."*, a button that opens it
straight away, and a short paragraph with the two things worth doing the first
time it opens (both are in *[The first time you open it](#the-first-time-you-open-it)*
below).

**If something goes wrong**, page two turns into the failure page in place: what
happened in plain English, the log already open beneath it, **Copy details** to
put the whole thing on the clipboard, and **Try again**, which takes you back to
page one where the file is.

If you would rather type, the same thing is:

```
aq resolve install
```

That runs the *same installer*, printing the same plain English into your
terminal instead of into a window. There is one installer on this operating
system and two ways to watch it — the window is not a second, simpler version
that might behave differently.

With no file name it looks in Downloads, and if there is nothing there it opens
Blackmagic's page **and waits** — as long as you like — until the download
appears. You cannot get the order wrong.

### 3. Open it

"DaVinci Resolve" is now in your apps and can be pinned to the dock. The window's
own **Open DaVinci Resolve** button does the same thing.

### Looking at the window without installing anything

```
aq resolve install --gui --dry-run
```

This opens the real window and walks through all six steps, and it **installs
nothing at all**: no container, no download, no Resolve, no change of any kind.
It is how to look at the window after changing it, or to see what the setup is
going to be like before committing fifteen minutes to it. It takes a few
seconds.

Without `--gui` you get the same rehearsal as text in your terminal, which is
what CI runs on every build.

---

## The first time you open it

Three things to do, in this order. None of them are faults.

**It opens as an X11 program through XWayland.** That is a compatibility layer
for older-style programs. Resolve has no Wayland version — not on AquariusOS,
not on any Linux, in 2026 — so this is how it runs everywhere. You will not
notice, and there is nothing to change.

**It should already be the right size.** Resolve used to open tiny on a 4K
screen, and every guide on the internet still tells you to fix that by hand.
AquariusOS does it for you: the launcher reads the size your desktop is set to
and hands it to Resolve on the way in.

If you want Resolve at a different size from everything else:

```
aq resolve scale 1.5     Resolve at 150%, whatever the desktop is at
aq resolve scale         what it is set to, and where that came from
aq resolve scale auto    go back to following the desktop
```

It takes effect the next time Resolve starts. Resolve's own setting — **DaVinci
Resolve menu → Preferences → User → UI Settings → Interface Scale** — still
works too, and is the better tool for fine adjustment, because Resolve knows
which parts of its interface should grow and which should not.

**Check it found the graphics card.**

> **Preferences** → **System** → **Memory and GPU**

*GPU processing mode* should say **CUDA**, and your card should be listed. If it
says the mode is unsupported, go to
*[When something is wrong](#when-something-is-wrong)*.

---

## The bench list for the size and the pointer, Royce

Five minutes, in this order. It is worth doing them as a list, because the two
Qt variables cannot be compared once you have started changing things by hand.

1. **Open Resolve from the app grid.** Is its interface the same sort of size as
   everything else on the 4K screen — menus, buttons, text readable from where
   you sit? That is the whole fix working.
2. **Look at the mouse pointer inside the Resolve window.** It should be the
   same arrow, at the same size, as on the desktop behind it. A tiny black arrow
   means the pointer half has not worked.
3. **Start it from a terminal once** — `aq resolve run` — and read the line it
   prints. It says the scale, which variable it used, and the pointer size:
   `interface at 1.25x (scale-factor), pointer Adwaita at 30px`.
4. **If the size is wrong, try the other variable** and say which looked better:

   ```
   echo 'qt_variable=device-pixel-ratio' >> ~/.config/aquarius/resolve.conf
   aq resolve run
   ```

   Then delete that line to go back. This is the one thing CI genuinely cannot
   answer — there is no Resolve and no screen in a build machine — so whichever
   of the two you say looks right becomes the default.
5. **Try `aq resolve scale 1.5`, open Resolve, then `aq resolve scale auto`.**
   The first should be visibly bigger than step 1; the second should put it
   back.
6. **Open "Remove DaVinci Resolve" and read page one without pressing
   anything.** Does it say plainly what goes and what stays? Is the settings
   switch off?

---

## The two things about codecs that nobody can fix inside Resolve

This is the part every other Linux distribution leaves you to discover for
yourself, so here it is plainly.

| | Resolve **Free** on Linux | Resolve **Studio** on Linux |
| --- | --- | --- |
| H.264 / H.265 video (what phones and cameras record) | ❌ cannot open at all | ✅ works, on NVIDIA |
| AAC audio (what is inside those same files) | ❌ | ❌ **still missing** |
| ProRes, DNxHR, BRAW, R3D, ARRIRAW, WAV | ✅ | ✅ |

Read that again, because it surprises everyone: **free Resolve on Linux cannot
open an ordinary phone or camera MP4**, and **even paid Studio opens it with
silent audio**.

Both are Blackmagic's licensing decisions, inside their application. No
operating system can change them. Anyone who tells you otherwise is wrong.

**What AquariusOS does about it — and this is the reason the OS exists**

AquariusOS fixes both from *outside* Resolve, before Resolve ever sees the file.
Right-click your footage in the file manager and choose **Make Editor-Ready**,
or run `aq-ingest --help`.

It rewraps the audio to a format Resolve can read (without touching the picture,
so nothing is re-compressed and nothing is lost), converts iPhone HEIC stills,
fixes the variable frame rates that make phone recordings drift, and can make
DNxHR proxies for footage your card cannot decode quickly. Your files then import
into Resolve with picture *and* sound.

No other operating system ships this. It is the single most valuable thing
AquariusOS does for a video editor, and it exists precisely because the table
above cannot be fixed any other way.

Professional formats, by the way, are Resolve-on-Linux's *strength*, not its
weakness — BRAW, RED R3D, ARRIRAW, Sony X-OCN and ProRes all work perfectly.
Hollywood grades on Linux. The gap is only in the consumer formats.

---

## Keeping it up to date

**A newer Resolve.** Download the new one from Blackmagic and run:

```
aq resolve update
```

It installs over the top. Your projects, settings, keyboard shortcuts and
databases live in your home folder and are not touched.

**A newer Rocky Linux underneath.** You do not have to do anything, and that is
the point of Enterprise Linux — its library versions do not move, so a rebuild
brings security fixes and nothing else. Removing and re-installing picks up the
newest build:

```
aq resolve remove
aq resolve install
```

**Moving to a whole new Enterprise Linux release** (Rocky 9 → 10, say) is a
decision somebody makes, not something that happens to you. It is one line in
`/usr/share/aquarius/resolve/runtime.env`, shipped in an AquariusOS update. See
*[Why Rocky 9 and not Rocky 10](#why-rocky-9-and-not-rocky-10)*.

---

## The other commands

```
aq resolve status     is it installed, and can it see the graphics card
aq resolve run        start Resolve (same as clicking the icon)
aq resolve scale 1.5  how big Resolve's own interface is drawn
aq resolve shell      a terminal INSIDE the environment Resolve runs in
aq resolve remove     remove Resolve and that environment
aq resolve --help     all of the above, explained

aq resolve install --gui         set it up in the window, from a terminal
aq resolve install --dry-run     a rehearsal that installs nothing at all
aq resolve remove --gui          remove it in the window
aq resolve remove --purge        also delete your Resolve settings and projects
                                 database. Never the default.
```

**`aq resolve status` is where to start when something is wrong.** It reports
more than "is it installed": it asks *inside* the container whether the graphics
card is visible, which is the question that actually matters and the one you
cannot answer by looking from outside.

**`aq resolve shell` puts you inside the environment Resolve runs in.** Your
home folder is the same folder in there. `exit` brings you back. You do not need this in normal
use; it is for looking at Resolve's own log files, which are at
`~/.local/share/DaVinciResolve/logs`.

**`aq resolve remove` is safe, and there is a window for it.** "Remove DaVinci
Resolve" in your apps is the same job with no terminal: it says exactly what
goes and what stays, and does it with the same list of steps the installer uses.

**Your projects and media are not in there** — they are in your ordinary
folders, which that environment only borrows while it is running. Nor are your
Resolve *settings*: the project library, your preferences and your keyboard
customisations live in `~/.local/share/DaVinciResolve` and are **kept** unless
you tick "Also delete my Resolve settings and project database", which is off
every time you open the window.

Removing and re-installing is the correct first move whenever a setup has gone
wrong, it costs you nothing but time, and with your settings kept it comes back
looking like the same computer.

---

## When something is wrong

### "GPU processing mode is unsupported"

The most common failure, and it almost never means a broken graphics card.

Run `aq resolve status` first. It tells you which of these it is.

1. **The container has no description of the card.** For a container to use an
   NVIDIA card, the computer writes a file describing that card and its driver
   libraries. A service called `nvidia-cdi-refresh` writes it at every boot.
   If `aq resolve status` says no description was found:

   ```
   sudo systemctl start nvidia-cdi-refresh.service
   ```

   or, if this machine's driver does not include that service, AquariusOS ships
   its own stand-in:

   ```
   sudo systemctl start aquarius-resolve-cdi.service
   ```

   Then `aq resolve remove` and set it up again — the description is read when
   the container is *created*, not each time it runs.

2. **The driver is too old.** Resolve 21 wants 580 or newer.
   `sudo bootc upgrade`, restart, and try again.

3. **It is an AMD or Intel card.** See below.

### A black window, or nothing at all

Start it from a terminal so you can see what it says:

```
aq resolve run
```

If the message mentions an **undefined symbol** and `glib` or `pango`, the whole
premise of this design has broken and it is worth reporting loudly — that is the
crash Rocky 9 exists to make impossible.

If it mentions **"could not load the Qt platform plugin xcb"**, something is
missing from the container. `aq resolve remove` and re-install; if it persists,
the runtime image needs a package adding to
`resolve-runtime/packages-required.txt`.

### Resolve's interface is still too small (or too big)

AquariusOS hands Resolve the size your desktop is set to. If that has not
worked, there are two things to try, in this order.

**One: set it yourself.**

```
aq resolve scale          what it thinks the size should be, and why
aq resolve scale 1.5      fix it at 150%
```

Close Resolve and open it again — Qt, the toolkit Resolve is built on, reads its
scale once at startup and nothing can change it afterwards.

**Two: try Resolve's other scaling variable.** Resolve is built on Qt 5, which
has two mechanisms for this, and different builds of Resolve have been reported
to respect different ones. AquariusOS uses `QT_SCALE_FACTOR` by default, because
it is the one Qt still documents and the only one that handles fractional sizes
like 1.25 properly. The other is `QT_DEVICE_PIXEL_RATIO`, which is what most
DaVinci Resolve advice on the internet names, and which prefers whole numbers.

```
echo 'qt_variable=device-pixel-ratio' >> ~/.config/aquarius/resolve.conf
```

Then start Resolve again. To go back, delete that line.

⚠️ **Never set both at once by hand.** Qt 5 reads both, and where both are set
they can multiply — 1.25 and 1.25 becoming 1.56 — which looks like the scaling
being broken rather than being applied twice. The launcher deliberately sets one
or the other, never the pair.

The launcher says which it used, so if you started Resolve from a terminal the
answer is on screen:

```
aquarius-resolve-launch: interface at 1.25x (scale-factor), pointer Adwaita at 30px
```

### The window is bigger than the screen

Resolve sizes its own window, and on a 4K display it occasionally opens one
whose edges — including its close button — are off the display.

Start it once at 100%, get a window you can see, and set the size properly
afterwards:

```
aq resolve scale 1
```

...or, for one launch only, without saving anything:

```
AQUARIUS_RESOLVE_SCALE=1 /usr/libexec/aquarius-resolve-launch
```

You can also drive any window from the keyboard, whether or not you can see its
edges: hold **Super** and drag anywhere in the window to move it, or Super and
right-drag to resize it.

### The mouse pointer inside Resolve looks wrong

It should not any more. The launcher carries your desktop's cursor theme into
the environment on purpose, **and its size multiplied by your screen scale** —
a 24-pixel pointer becomes 30 at 125% and 36 at 150%, so it matches the one
outside Resolve instead of shrinking as you scale up. The theme is also
installed inside the environment, so the common case works even if the shared
folder is not where the launcher expects.

If it still happens, it means the app-menu entry is not going through our
launcher. Check:

```
grep Exec ~/.local/share/applications/*[Rr]esolve*.desktop
```

It should say `/usr/libexec/aquarius-resolve-launch`. If it does not, re-run
`aq resolve install` — it rewrites those lines and says how many it changed.

### A Studio licence dongle is not seen

AquariusOS ships the USB rules for both Blackmagic's own hardware and the
licence dongles, at `/usr/lib/udev/rules.d/75-aquarius-resolve.rules`. They are
on the *host*, deliberately: Resolve's installer writes its own copies inside
the container, where they apply to nothing.

Check the dongle is one of the two manufacturers those rules cover:

```
lsusb
```

You are looking for `1edb` (Blackmagic Design) or `096e` (Feitian, who make the
dongles). Unplug and replug it after any AquariusOS update.

**You may not need it at all.** Resolve Studio also activates with a licence key
typed into the application, and that path works normally in the container — it
needs nothing from this section.

### If you have AMD or Intel

Straight answer, no hedging:

- **Intel**: Blackmagic does not support Resolve on Intel graphics on Linux at
  all. There is nothing to configure.
- **AMD**: Resolve needs AMD's ROCm compute libraries — about 24 GB — which are
  **not** set up in the runtime container yet. Resolve will install and start
  and will almost certainly say its GPU processing mode is unsupported. The
  setup says so before you begin rather than letting you find out from Resolve.

This is a limitation of AquariusOS today, and a real one. It is on the plan and
it is not done. NVIDIA is the supported creator path, and that is Blackmagic's
choice showing through ours.

### The Blackmagic RAW Player will not start

Resolve installs two small extra programs alongside itself, and `davincibox` —
the Fedora-based project this design learned from — renames two of their
libraries to get them running. AquariusOS does not do that, because on Rocky 9
it should not be necessary and copying a workaround nobody has tested here would
be guessing.

If you hit it, say so; it is a known loose end with a known fix, not a mystery.
Resolve itself is unaffected.

---

## How it is built, for whoever maintains this

### The pieces

| Where | What |
| --- | --- |
| `resolve-runtime/Containerfile` | The Rocky Linux itself. A separate image with a separate build. |
| `resolve-runtime/packages-required.txt` | What Resolve cannot start without. A missing one **fails the build**. |
| `resolve-runtime/packages-optional.txt` | What only makes things better. A missing one prints a note. |
| `resolve-runtime/system_files/usr/bin/aquarius-resolve-setup` | Runs Blackmagic's installer, **inside** the container. |
| `resolve-runtime/system_files/usr/bin/aquarius-resolve-run` | Starts Resolve, inside the container. |
| `build_files/62-resolve-runtime.sh` | The OS-image step. Checks everything below arrived. |
| `system_files/usr/libexec/aquarius-resolve-install` | **The setup, on the host. The long one, and the only one.** |
| `system_files/usr/libexec/aquarius-resolve-installer` | The window. GTK 4 + libadwaita, in Python. Runs the above; installs nothing itself. |
| `system_files/usr/libexec/aquarius-resolve-launch` | The host-side launcher. Carries the desktop's settings in. |
| `system_files/usr/share/aquarius/resolve/runtime.env` | **The one place the runtime image is named.** |
| `system_files/usr/lib/udev/rules.d/75-aquarius-resolve.rules` | Dongles and control panels. |
| `system_files/usr/lib/systemd/system/aquarius-resolve-cdi.service` | Graphics-card description, safety net only. |
| `.github/workflows/build-resolve-runtime.yml` | Builds and publishes the runtime. |

### The window, and the progress channel

*Added 2026-09-04. Before this, clicking "Install DaVinci Resolve" opened a file
picker and then a Ptyxis terminal. That worked — Royce installed Resolve through
it on 2026-09-03 — and it was replaced anyway, because the flagship feature of
an operating system for creative people should not look like system
administration.*

**The rule.** `aquarius-resolve-install` is the only thing that installs
Resolve. The window runs it and draws what it says. Nothing is reimplemented in
Python — not finding the download, not looking at the graphics card, not
patching the menu entries — so `aq resolve install` in a terminal and the window
cannot drift apart or disagree about the machine. If you are tempted to do "just
this one bit" in the window, put it in the script instead and both get it.

**How they talk.** The script's human output goes to stdout and stderr exactly
as it always did. Given `--progress-fd N` (or `AQ_PROGRESS_FD=N`) it *also*
writes four kinds of structured line to that descriptor, and nothing else:

| Line | Means |
| --- | --- |
| `STEP <n>/<total> <text>` | Step n has begun, and is called `<text>`. Beginning n means 1…n-1 finished. |
| `PERCENT <0-100>` | How far through the **current** step. Sent only where there is a real number. |
| `DONE` | Everything finished. Once, last. |
| `FAIL <text>` | Stopped, and `<text>` says why in words a person can act on. |

Three things about that are deliberate:

- **The step wording lives in the script.** The window prints whatever text
  arrives, so a step can be renamed — or re-named mid-flight, which is how
  "Finding your download" becomes "Waiting for your download from Blackmagic"
  when somebody clicks Install with nothing downloaded — without touching the
  window.
- **No `PERCENT` is not a stall.** Only the container download reports a real
  number, parsed out of podman's own output. Everywhere else the window sweeps a
  bar with no end, which is the honest picture of a step nobody can time. The
  parser is explicitly allowed to recognise nothing: podman's wording is not a
  promise anybody made us, and if it changes the download still works and the
  bar simply sweeps.
- **Unknown lines are ignored, not shown.** A line added to the script in future
  cannot break a window built before it.

**Two questions and a rehearsal**, all answered by the same script, so the window
never has a second opinion about the machine:

```
aquarius-resolve-install --find-installer   the download it would use, or exit 1
aquarius-resolve-install --gpu-summary      ok|warn|none, a tab, then a sentence
aquarius-resolve-install --dry-run          walk all six steps, change nothing
```

**No password is asked for and none should be.** podman and distrobox here are
rootless; the container is built and run as the person using it. The one part
that needs root — the udev rules for a Studio licence dongle — ships inside the
image and is in place before anybody clicks anything. `pkexec` appearing in this
feature would mean something else had gone wrong.

**Cancel** signals the whole process group, which is why the script is started
with a session of its own: podman and distrobox stop with it rather than being
orphaned to finish a download nobody is watching.

**Colours are not set by the window.** libadwaita follows the system light/dark
setting and AquariusOS's accent is set at the desktop level, so a window that
paints nothing itself is an AquariusOS-coloured window in both themes for free.
`branding/tokens.md` stays the law for anything that ever does need a literal
colour.

**Packages.** `build_files/62-resolve-runtime.sh` asks for `gtk4`, `libadwaita`
and `python3-gobject` by name. All three are already in the image and the size
this adds is **zero** — the first two come in with GNOME at step 40, and
`python3-gobject` arrives as a dependency of GDM's transaction at step 30.

That is the point of asking. Nothing wanted any of them on purpose, so the
flagship feature of this operating system rests on three packages that are here
by accident, and an accident can be undone by a change to a completely different
step. Named here, that change fails in this step instead of shipping an icon
that does nothing when clicked.

### Why Rocky 9 and not Rocky 10

Three reasons, in order of weight.

1. **GLib.** Rocky 9 carries GLib 2.68 — the same series Resolve bundles — so
   the launch crash is impossible rather than worked around. Rocky 10 carries a
   modern GLib and the crash becomes possible again. This is the entire premise
   of the design and it is checked at build time: the runtime build **fails** if
   Rocky 9's GLib is ever not 2.68.
2. **The industry floor.** Rocky 9's glibc is 2.34, which is the VFX Reference
   Platform's CY2027 requirement. Unreal Engine 5's own floor is Rocky 8, older
   still. One container serves both.
3. **An unexplained report.** DaVinci Resolve opening to a black window on
   AlmaLinux 10 — the same Enterprise Linux 10 userland — was reported in
   December 2025 and nobody has reproduced or explained it. Not proof of
   anything, but not a reason to choose 10 either.

Rocky 10 can be built with `--build-arg ROCKY=10`. The build prints a plain
warning that the GLib version no longer matches. It is an experiment.

### Why not Rocky 8, which is what Blackmagic actually lists

Rocky 8's kernel is from 2018 and its libraries with it. A 2026 NVIDIA driver
and a modern desktop's graphics stack do not fit. Rocky 9 is the closest thing
to Blackmagic's stated target that a 4090 can live in.

### How the graphics card gets into the container — the decision

There are two ways, and AquariusOS uses the first with the second as a fallback:

**(a) CDI — the Container Device Interface.** NVIDIA's own supported mechanism.
A file on the machine describes the card and every driver library, and podman
reads it. `nvidia-container-toolkit` provides the tool that writes it and, in
current builds, a service (`nvidia-cdi-refresh`) that rewrites it **at every
boot and after every driver change**. `build_files/60-nvidia.sh` installs the
toolkit, enables that service, and installs the SELinux rule that lets a
container reach the card.

**(b) `distrobox create --nvidia`.** distrobox copies the host's driver files
into the container itself. No toolkit needed, but it is distrobox's own
heuristic rather than NVIDIA's description of the hardware, and distrobox's
documentation is explicit that it needs a recent glibc in the container.

**Why (a), specifically on this operating system:** AquariusOS updates by
replacing the whole system, driver included. The description names driver
library files *by version*. Anything generated when the image was built would
name a driver that no longer existed after the first `bootc upgrade` — the
machine would work, then silently stop seeing the card. Generated at boot by the
driver actually installed, it cannot go stale. (And there is no graphics card in
the machine that builds the image, so there would be nothing true to generate.)

The installer picks (a) when the file exists and falls back to (b) when it does
not, so a driver build without the refresh service still works. Neither is
decided at build time.

**The device nodes** — `/dev/dri`, `/dev/nvidia*`, and any USB dongle — need no
special handling: distrobox already gives its containers the host's devices.
What (a) and (b) are for is the driver *libraries*, which are not devices.

`aquarius-resolve-cdi.service` is a **safety net only**. It runs only when
NVIDIA's own service is absent from the driver build, enforced by a
`ConditionPathExists=!…` line that CI checks. Two things writing one file would
be worse than neither.

### Other decisions worth not re-litigating

- **No `--init`.** That switch runs a service manager inside the container and,
  in distrobox's own words, disables host process integration. Resolve is one
  program, not a system.
- **No `--home`.** Sharing the real home folder is the default and is what we
  want — Resolve reads and writes ordinary folders, so nothing has to be moved
  in and out.
- **The tag is `9`, never `latest`.** A moving tag would follow us to Rocky 10
  one day without anybody deciding to. Moving everyone to a new Enterprise Linux
  is an edit to `runtime.env` shipped in an OS update.
- **No digest pinned in the OS image.** The exact digest a machine installed is
  recorded in `~/.local/share/aquarius/resolve/installed.env` and printed by
  `aq resolve status`. Pinning in the image would mean Rocky's security updates
  could only reach people through an OS update, which is the wrong risk for a
  container whose job is to be a *stable* userland.
- **The runtime is not baked into the OS image.** It is ~1 GB, for a feature not
  everybody uses. It is fetched on first use.

### What CI proves — and what it does not

Be clear about this, because a green tick is easy to over-read.

| CI checks | Only the bench can check |
| --- | --- |
| The runtime is really Rocky 9 | **That Resolve starts** |
| Its GLib is the 2.68 series Resolve bundles | That the 4090 is seen, and CUDA is offered |
| Its glibc is at the VFX CY2027 floor | That a Studio dongle is read |
| Every library Resolve is known to look for resolves by name (`ldconfig -p`) | That a 4K screen behaves |
| Neither image contains any Blackmagic software | Playback, export, colour |
| Every script parses, the desktop entry validates, `aq resolve --help` and `status` run | Whether it is actually pleasant to use |
| The window compiles, and Python inside the image can really import GTK 4 and libadwaita | **What the window looks like** |
| The rehearsal's six `STEP` lines arrive in order and end in `DONE` | That the bar moves sensibly during a real download |
| The desktop entry's `StartupWMClass` matches the window's application id | That the dock shows the right name and mark |

There is no Resolve in CI — we may not distribute it — and no graphics card in a
GitHub runner. The library check is a **proxy**: every "Resolve will not start"
report that is not the GLib clash is a missing library from that list, so it
catches the failure this image is most likely to suffer, which is a Rocky point
release moving a package between repositories.

**The real proof is the bench.** Nothing here is finished until a person on the
4090 machine has downloaded Resolve, clicked the icon, and looked at the window.
CI can prove the window is importable and that the lines it reads still arrive;
it cannot see a pixel of it. `aq resolve install --gui --dry-run` is the cheap
way to look, and it installs nothing.

### Testing a work-in-progress runtime on the bench

Side branches publish the runtime under a `dev-<branch>` tag, which can never
collide with the `9` tag real machines pull. To use one:

```
AQ_RESOLVE_RUNTIME_TAG=dev-restart-r3-resolve aq resolve install
```

The setup prints a line saying it is using a runtime that is not the one this
AquariusOS shipped with.

Add `--gui` to get the window instead of the terminal. Anything set in the
terminal carries into the window, because the window passes its whole
environment to the installer it runs — which is why this works and clicking the
icon in the app grid does not.

---

## Where to go next

- **The ingest helper, which fixes the codec table above:** `aq-ingest --help`
- **Why Fedora for the OS but Rocky for Resolve:**
  [`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md) §1 and §3.2
- **The full codec picture:** [`../codec-research.md`](../codec-research.md)
- **Moving the bench machine to the new line:** [`bench-rebase.md`](bench-rebase.md)
- **Why the NVIDIA driver is done the way it is:** [`nvidia-notes.md`](nvidia-notes.md)
