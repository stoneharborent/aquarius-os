# The kernel — why AquariusOS pins it, and what to do when Fedora is ahead

*Written 2026-09-04. Assumes you have never used Linux.*

---

## The one-paragraph version

AquariusOS does **not** ship whatever kernel Fedora shipped this morning. It
ships the kernel that a group called **Universal Blue** built their ready-made
drivers against, and it does that on **both** images. That costs us a kernel
that is sometimes a few days old. It buys us a graphics driver, a webcam and
Xbox controllers that work on every single build, instead of on most of them.

---

## What a kernel is, and why this comes up at all

The **kernel** is the part of Linux that talks to the hardware. Everything else
— the desktop, the apps, the login screen — talks to the kernel, and the kernel
talks to the graphics card, the keyboard, the network and the disks.

Some pieces of hardware need code that runs **inside** the kernel to work at
all. That code is called a **kernel module**, and AquariusOS ships four of them.
Every one is a feature you would notice losing:

| Module | What you would lose without it |
| --- | --- |
| `nvidia` | The graphics driver on the NVIDIA image. Without it: a black screen. |
| `v4l2loopback` | OBS Studio's **Start Virtual Camera** button — being a webcam for Zoom, Meet, Discord or Riverside. |
| `xone` | The Xbox Wireless Adapter — the little USB dongle. |
| `xpadneo` | Xbox controllers over Bluetooth, with the right buttons, rumble and battery level. |

And here is the whole problem in one sentence:

> **A kernel module only works with the exact kernel version it was built
> against.** Not roughly the same. The exact one, down to the build number.

Give a machine a module built for kernel 7.1.12 while it is running 7.1.13, and
it does not warn you or try its best. It simply refuses to load it, and the
feature is gone.

---

## Where our modules come from, and why we do not build them ourselves

We could compile all four during the build. We deliberately do not, and the
reason is **Secure Boot**.

Secure Boot is a switch in your computer's firmware — on by default on almost
every modern PC, including the 4090 bench machine — that refuses to load kernel
code unless it has been signed by a key the machine trusts. A module we compiled
ourselves would be signed by nobody. The machine would refuse it, and the only
way around that would be to ask you to turn Secure Boot off, which is a real
security decision to demand of somebody who only wanted a webcam.

So instead we take them ready-made and already signed from **Universal Blue**,
the people behind Bazzite and Bluefin. They rebuild these daily and publish them
as two boxes:

| Box | What is in it | Which image uses it |
| --- | --- | --- |
| `ghcr.io/ublue-os/akmods` | `v4l2loopback`, `xone`, `xpadneo` | both |
| `ghcr.io/ublue-os/akmods-nvidia-open` | the NVIDIA driver | the NVIDIA image only |

Both boxes also contain **a copy of the exact kernel they were built against**.
That copy is not an accident — Universal Blue put it there precisely so that
anyone using their modules can make their kernel match, and it is what their own
images do.

---

## The pin

Every AquariusOS build now makes one decision, early, before anything installs a
module:

> **The kernel in AquariusOS is the kernel Universal Blue's module box was built
> for.**

The step that does it is `build_files/58-kernel-pin.sh`. In plain terms it:

1. reads which kernel the module box was built for (out of the box's own
   packages, not out of a file name — a file name is a guess);
2. on the NVIDIA image, checks that Universal Blue's two boxes agree with each
   other, and refuses to build if they do not;
3. compares that with the kernel our image happens to have;
4. if they differ, removes our kernel and installs theirs — the five packages
   `kernel`, `kernel-core`, `kernel-modules`, `kernel-modules-core` and
   `kernel-modules-extra`, taken straight out of the box;
5. checks the result on disk, and writes down what it did in
   `/usr/share/aquarius/kernel.txt`.

Everything after that step — the NVIDIA driver, the virtual camera, the Xbox
drivers, and the rebuild of the boot ramdisk — can simply assume the match.

---

## What happens when Fedora is ahead

Fedora ships a kernel update. Universal Blue rebuild on their own schedule, so
for a day or two the newest Fedora kernel is newer than the one their modules
were built for.

**Nothing happens.** The build notices, swaps our kernel back to Universal
Blue's, says so in the build log, and carries on. The published image is
correct — it is just running a kernel a few days old, which is what almost every
Fedora machine on earth is doing anyway.

You can see which one any image ended up with:

```
cat /usr/share/aquarius/kernel.txt
```

It looks like this:

```
kernel=7.1.12-200.fc44.x86_64
source=ghcr.io/ublue-os/akmods (kernel-rpms)
action=swapped-from-7.1.13-200.fc44.x86_64
```

`action` is either `already-matched` (Fedora and Universal Blue agreed that day)
or `swapped-from-…` (they did not, and this is the kernel we replaced).

---

## Why this file exists — the bug it came from

It is worth writing down, because the failure was invisible and that is the
dangerous kind.

Until 4 September 2026 the swap lived **inside the NVIDIA step**. That step does
nothing at all on the AMD/Intel image, so the AMD/Intel image had no pin:

- The **NVIDIA image** swapped its kernel and was always correct.
- The **AMD/Intel image** kept whatever kernel Fedora gave it. When the two
  matched, everything worked. When they did not, the virtual camera and both
  Xbox drivers were quietly skipped.

That is exactly what happened in build `33900370878`. Fedora had moved to
7.1.13, Universal Blue were still on 7.1.12, and the AMD/Intel image published —
green, no red text anywhere — with **no virtual camera and no Xbox controller
support**. The only trace was a line inside a file in the image saying
`status=unavailable`.

Two things changed as a result:

1. **The pin moved out of the NVIDIA step and became its own step**, run on both
   images, before anything that installs a module.
2. **A mismatch is now a build failure**, not a shrug. The virtual camera step
   and the gaming step used to leave the feature out and let the build go green.
   They stop the build instead. With the pin in place there is no innocent
   reason for a mismatch, so any mismatch is a real fault and should behave like
   one.

---

## How to bump the kernel

You mostly do not. The kernel follows Universal Blue automatically: they rebuild
daily, and the next AquariusOS build picks up whatever they have. To move to a
newer kernel, **build again** — that is the whole procedure.

If you want a *specific* newer kernel sooner than Universal Blue provide it,
there are only two honest options:

1. **Wait for them.** Usually a day or two. This is almost always the right
   answer.
2. **Change which Fedora release we build from.** `FEDORA_VERSION` at the top of
   the `Containerfile` decides that, and it has to be a release Universal Blue
   publish a module box for — they build `main-43`, `main-44` and so on, and the
   image tags in the `Containerfile` follow it automatically. Bumping it is a
   whole-OS move, not a kernel tweak, and it belongs in a ROADMAP phase.

What you must **not** do is install a newer kernel and leave the modules where
they are. The build will stop you — that is what these checks are for — but the
reason is worth knowing: you would be choosing a version number over a working
graphics driver.

---

## Where this is checked

Three times, deliberately, because "the build was green" and "the image works"
are different sentences:

| Where | What it checks |
| --- | --- |
| `build_files/58-kernel-pin.sh` | Does the pin itself, then reads the result back off disk. |
| `build_files/62-virtual-camera.sh`, `build_files/68-gaming.sh`, `build_files/60-nvidia.sh` | Each module step re-asks whether the module it is about to install matches the kernel, and stops the build if it does not. |
| `build_files/90-cleanup.sh` | At the very end: is the kernel still the one that was pinned, and is there exactly one of it? |
| `.github/workflows/build.yml` | Starts the **finished** image and asks it directly — the pin note, the package database and the folder on disk must all say the same version, and all three (four on NVIDIA) modules must be installed and filed under it. |

---

## See also

- **Why the NVIDIA driver is done the way it is:** [`nvidia-notes.md`](nvidia-notes.md)
- **The virtual camera, and OBS generally:** [`creator-apps.md`](creator-apps.md)
- **The Xbox controllers and the rest of the gaming layer:** [`gaming.md`](gaming.md)
- **Universal Blue's module boxes:** <https://github.com/ublue-os/akmods>
