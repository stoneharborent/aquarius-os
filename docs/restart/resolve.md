# DaVinci Resolve on AquariusOS

*Written 2026-09-04, for Phase R3a. Assumes you have never used Linux.*

---

## The short version

Open your apps, click **Install DaVinci Resolve**, pick the file you downloaded
from Blackmagic, and wait about fifteen minutes. Resolve then sits in your dock
like any other program.

Everything below explains what happened and what to do when it does not.

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
> The graphical **Install DaVinci Resolve** button cannot pass that setting, so
> use the terminal for this one test.

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

A file picker opens in your Downloads folder. Choose the file. A terminal window
opens and tells you what it is doing, in plain English, for about fifteen
minutes.

If you would rather type, the same thing is:

```
aq resolve install
```

With no file name it looks in Downloads, and if there is nothing there it opens
Blackmagic's page **and waits** — as long as you like — until the download
appears. You cannot get the order wrong.

### 3. Open it

"DaVinci Resolve" is now in your apps and can be pinned to the dock.

---

## The first time you open it

Three things to do, in this order. None of them are faults.

**It opens as an X11 program through XWayland.** That is a compatibility layer
for older-style programs. Resolve has no Wayland version — not on AquariusOS,
not on any Linux, in 2026 — so this is how it runs everywhere. You will not
notice, and there is nothing to change.

**Set the interface size, inside Resolve.** On a big 4K screen Resolve's own
interface starts small:

> DaVinci Resolve menu → **Preferences** → **User** → **UI Settings** →
> **Interface Scale**

Set it and restart Resolve. **Do this inside Resolve, not with the system's
display scale.** Resolve ignores the system setting and has better scaling of
its own, because it knows which parts of its interface should grow and which
should not. Forcing the system's scaling on top gives you blurry text.

**Check it found the graphics card.**

> **Preferences** → **System** → **Memory and GPU**

*GPU processing mode* should say **CUDA**, and your card should be listed. If it
says the mode is unsupported, go to
*[When something is wrong](#when-something-is-wrong)*.

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
aq resolve shell      a terminal INSIDE the container
aq resolve remove     delete the container
aq resolve --help     all of the above, explained
```

**`aq resolve status` is where to start when something is wrong.** It reports
more than "is it installed": it asks *inside* the container whether the graphics
card is visible, which is the question that actually matters and the one you
cannot answer by looking from outside.

**`aq resolve shell` puts you inside the Rocky Linux.** Your home folder is the
same folder in there. `exit` brings you back. You do not need this in normal
use; it is for looking at Resolve's own log files, which are at
`~/.local/share/DaVinciResolve/logs`.

**`aq resolve remove` is safe.** It deletes the container and Resolve with it.
**Your projects and media are not in there** — they are in your ordinary
folders, which the container only borrows while it is running. Removing and
re-installing is the correct first move whenever a setup has gone wrong, and it
costs you nothing but time.

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

### The window is bigger than the screen

Resolve sizes its own window, and on a 4K display it occasionally opens one
whose edges — including its close button — are off the display.

Start it once with its own scaling switched off, get a window you can see, set
the Interface Scale properly in Preferences, and never do this again:

```
AQUARIUS_RESOLVE_SCALE=1 /usr/libexec/aquarius-resolve-launch
```

You can also drive any window from the keyboard, whether or not you can see its
edges: hold **Super** and drag anywhere in the window to move it, or Super and
right-drag to resize it.

### The mouse pointer inside Resolve looks wrong

It should not any more — the launcher carries your desktop's cursor theme into
the container on purpose. If it happens, it means the app-menu entry is not
going through our launcher. Check:

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
| `system_files/usr/libexec/aquarius-resolve-install` | The setup, on the host. The long one. |
| `system_files/usr/libexec/aquarius-resolve-install-gui` | The no-terminal way in: a file picker, then the above. |
| `system_files/usr/libexec/aquarius-resolve-launch` | The host-side launcher. Carries the desktop's settings in. |
| `system_files/usr/share/aquarius/resolve/runtime.env` | **The one place the runtime image is named.** |
| `system_files/usr/lib/udev/rules.d/75-aquarius-resolve.rules` | Dongles and control panels. |
| `system_files/usr/lib/systemd/system/aquarius-resolve-cdi.service` | Graphics-card description, safety net only. |
| `.github/workflows/build-resolve-runtime.yml` | Builds and publishes the runtime. |

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

There is no Resolve in CI — we may not distribute it — and no graphics card in a
GitHub runner. The library check is a **proxy**: every "Resolve will not start"
report that is not the GLib clash is a missing library from that list, so it
catches the failure this image is most likely to suffer, which is a Rocky point
release moving a package between repositories.

**The real proof is the bench.** Nothing here is finished until a person on the
4090 machine has downloaded Resolve, clicked the icon, and looked at the window.

### Testing a work-in-progress runtime on the bench

Side branches publish the runtime under a `dev-<branch>` tag, which can never
collide with the `9` tag real machines pull. To use one:

```
AQ_RESOLVE_RUNTIME_TAG=dev-restart-r3-resolve aq resolve install
```

The setup prints a line saying it is using a runtime that is not the one this
AquariusOS shipped with.

---

## Where to go next

- **The ingest helper, which fixes the codec table above:** `aq-ingest --help`
- **Why Fedora for the OS but Rocky for Resolve:**
  [`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md) §1 and §3.2
- **The full codec picture:** [`../codec-research.md`](../codec-research.md)
- **Moving the bench machine to the new line:** [`bench-rebase.md`](bench-rebase.md)
- **Why the NVIDIA driver is done the way it is:** [`nvidia-notes.md`](nvidia-notes.md)
