# The NVIDIA driver: which way we did it, and why

*Phase R1, 2026-09-03. The hardest single part of the build, explained from
scratch.*

---

## Why NVIDIA is the hard one

Most drivers on Linux are already inside the kernel. You plug the thing in and
it works. NVIDIA's is not: it is a separate piece of code that has to be loaded
*into* the kernel, and a piece of code loaded into the kernel only works with
**the exact kernel version it was compiled against.** Not "roughly that
version" — the exact one, build number included.

Fedora ships a new kernel every few weeks. So the driver has to be recompiled
every few weeks, against whatever kernel has just arrived.

There are only three ways to deal with that, and every Linux distribution picks
one.

---

## The three options

### Option A — compile it on the user's computer (`akmod`)

This is what RPM Fusion's `akmod-nvidia-open` does, and what a normal Fedora
desktop does. The compiler stays installed forever, and every kernel update
triggers a rebuild in the background.

**Why not:** AquariusOS is an image. There is no "on the user's computer" —
every machine gets the same picture of a finished system, and nothing is
compiled after it ships. We could compile during *our* build instead, and that
is Option B.

### Option B — compile it during our build, from RPM Fusion

Install `akmod-nvidia-open` and the kernel headers in the build, run the
compiler, get a module.

**Why not, for R1:**

- It adds about ten minutes to every image we ever publish, on both variants.
- It drags a full compiler toolchain into the build for one package.
- **The result is signed with a key that does not exist.** Modern PCs ship with
  Secure Boot switched on, and Secure Boot refuses to load a kernel module that
  is not signed by a key the machine trusts. A self-compiled module is not, so
  the user has to turn Secure Boot off in their BIOS — which is a real
  instruction we would have to put in a beginner's install guide, and it is a
  bad one.
- It is not what the bench is already running, so it changes two things at once.

This stays the documented fallback. If Universal Blue ever stops publishing,
this is where we go.

### Option C — use somebody else's already-compiled, already-signed modules ✅

**This is what R1 ships.**

Universal Blue — the people behind Bazzite and Bluefin — publish a box of
NVIDIA kernel modules, rebuilt daily against the current Fedora kernel, signed
with their key, at `ghcr.io/ublue-os/akmods-nvidia-open`. Anyone can pull it.

**Why it wins:**

- No compiler in our build, no ten minutes, no toolchain.
- **Signed**, so Secure Boot machines work without touching the BIOS.
- It is what the bench machine is *already* running, because the Bazzite images
  used exactly these modules. Rebasing keeps the same driver family and the same
  signing key, so the move changes one thing instead of two.
- It is maintained by people whose whole job is keeping it current, and it is
  rebuilt every day.

**What we take on:** a dependency on somebody else's build. If they stop, we
move to Option B. That is a known, bounded risk with a documented exit.

---

## The genuinely tricky part, and how it is solved

Here is the trap that would otherwise bite us every few weeks.

Universal Blue's box was compiled against *some* Fedora kernel. Our image
contains *some* Fedora kernel. Most days those are the same one — as of
2 September 2026 both are `7.1.12-200.fc44`, because both track mainline Fedora.

But they rebuild on different schedules. Fedora ships a kernel update; one of
the two picks it up a day before the other; for a day or two they differ.

**If they differ and we install anyway, the image builds perfectly and the
machine boots to a black screen.** No error during the build. Nothing to see
until somebody restarts a computer.

### The fix: do not hope, make it true

Universal Blue's box also contains **a copy of the exact kernel it was compiled
against**. So `build_files/60-nvidia.sh` does this:

1. Read which kernel the driver expects (it is written in a small file inside
   the box, `rpms/kmods/nvidia-vars`).
2. Read which kernel our image has.
3. If they match, carry on.
4. **If they do not match, remove our kernel and install theirs**, then check
   again and stop the build if it still does not match.

After that the match is not likely — it is guaranteed by construction. This is
the mechanism Universal Blue's own README documents for exactly this situation.

**The cost:** the NVIDIA image's kernel can be a few days behind the AMD/Intel
image's. That is the right trade. A slightly older kernel that boots beats a
newer one that does not.

**The check afterwards:** CI opens the finished image and confirms that a file
called `nvidia*.ko` actually exists under `/usr/lib/modules/<the kernel that is
in this image>/extra/`. That is the check that catches a build where every
package installed cleanly and the module ended up filed under a kernel that is
not there.

---

## The driver pin (2026-10-06)

> ⚠️ **Right now the NVIDIA image does NOT follow Universal Blue's newest
> driver.** It is held on driver **610.57.04** with kernel **7.2.4-200.fc44**.
> The AMD/Intel and handheld images are not affected and still follow
> Universal Blue every day.

### Why

On 11 September 2026 Universal Blue moved their NVIDIA box to driver
**615.71.09** (the first AquariusOS build with it was `c1c7d32`, the same day).
That driver crashes the RTX 5080 under any sustained CUDA work — AI tools,
ComfyUI, PyTorch. The kernel log fills with `Xid 13` / `Illegal Instruction
Encoding` / `SKEDCHECK … failed`, and the graphics card locks up until the
computer is restarted.

It was proven on the bench on 6 October 2026: same machine, same PyTorch, same
tests. On 615.71.09 it fails within seconds. Booted into the older image
`aquarius-os-nvidia:20260910-fcd0793` (kernel 7.2.4 + driver 610.57.04) it
passes everything — 174 TFLOPS sustained, zero Xid errors. Clocks, power, PCIe,
the PyTorch build, cuBLAS and ComfyUI were all ruled out. The full log is the
**Log** section of `Workflow/Branches/Animation/MoCap/Processing/ComfyUI
Pipeline.md`.

### How the pin works

Normally the build takes Universal Blue's boxes by **tag** — `main-44`, which
means "whatever they built most recently". A tag is a label they move every
day. They even rebuild their very specific tags in place: on 6 October
`main-44-7.2.4-200.fc44` already held the broken driver. So a tag cannot hold a
pin.

Instead the NVIDIA image takes both boxes by **fingerprint** (a *digest*, the
long `@sha256:…` string). A fingerprint is a checksum of one exact build and can
never point at anything else. The two fingerprints are Universal Blue's builds
from 10 September 2026, the ones the good AquariusOS image `fcd0793` used:

| Box | Fingerprint | What is in it |
| --- | --- | --- |
| `ghcr.io/ublue-os/akmods-nvidia-open` | `@sha256:d7620a16…a3e7cf8` | NVIDIA driver 610.57.04, built for kernel 7.2.4-200.fc44 |
| `ghcr.io/ublue-os/akmods` | `@sha256:6801d0d5…b589d51b` | kernel 7.2.4-200.fc44 (and the webcam / Xbox modules for it) |

**Both** are pinned, together. The common box decides which kernel the image
gets (see [`kernel.md`](kernel.md)), and the driver only loads on the kernel it
was built for. Pin only one and the build stops with "Universal Blue's two
module boxes disagree".

Where it lives:

- **`aquarius-os.env`** — the three `NVIDIA_PIN_*` lines, under a big warning
  that repeats everything on this page. **This is the only place to change.**
- `Justfile` (`just build`) — passes those lines to the build, for the NVIDIA
  image only.
- `Containerfile` — takes either a tag or a fingerprint for each box
  (`AKMODS_NVIDIA_REF`, `AKMODS_REF`); the default is still the `main-44` tag.
- `build_files/60-nvidia.sh` — prints `AQUARIUS NVIDIA DRIVER` and
  `AQUARIUS KERNEL` in the build log, **stops the build** if the driver is not
  the pinned version, and writes `/usr/share/aquarius/nvidia.txt`.
- `.github/workflows/build.yml` — reads that file back inside the finished image
  and checks the driver again.

On a machine running the NVIDIA image you can see it for yourself:

```
cat /usr/share/aquarius/nvidia.txt
```

`pinned_driver=610.57.04` means the pin is on; an empty `pinned_driver=` means it
is off.

### How to remove the pin

Do this once NVIDIA have released a driver newer than 615.71.09 that fixes the
crash, and Universal Blue have picked it up.

1. Open `aquarius-os.env` and empty the three values, so each line ends in `""`:

   ```
   NVIDIA_PIN_AKMODS_NVIDIA_REF=""
   NVIDIA_PIN_AKMODS_REF=""
   NVIDIA_PIN_DRIVER=""
   ```

   Empty means "no pin". (Deleting the whole warning block works too.)
2. Commit that on a side branch, add the branch name to the list at the top of
   `.github/workflows/build.yml` like every other fix branch, and push. GitHub
   builds all three images.
3. In the NVIDIA build's log, open **Build the image** and search for
   `AQUARIUS NVIDIA DRIVER`. It shows the driver the image now has. It must not
   be 615.71.09.
4. **Test on the bench before merging.** Put the bench on the new driver,
   reboot, open a terminal and run:

   ```
   ~/ComfyUI/venv/bin/python "/run/media/rorobeckley/Internal Drive/Workflow/Branches/Animation/MoCap/Processing/gpu_stress.py"
   ```

   It must print **PASS**. Then run:

   ```
   journalctl -k | grep -i xid
   ```

   That must print **nothing at all**. Any line with `Xid` in it means the new
   driver is still broken — put the three values back and wait for the next one.
5. Only then merge.

### One risk worth knowing

The pinned builds are old, untagged builds sitting in Universal Blue's registry.
If they ever clean those up, the NVIDIA build will stop with an error saying it
cannot find the image. Nothing broken would ship — the build simply would not
finish — and the fix is either to remove the pin (if a good driver exists by
then) or to choose another known-good build.

---

## What else goes in

Not just the driver:

| Piece | Why |
| --- | --- |
| `egl-wayland` | Without it an NVIDIA card cannot draw a Wayland desktop at all. |
| `nvidia-container-toolkit` | Lets the graphics card be used from *inside* a container. Nothing uses it yet — it is here because Phase R3's whole plan is to run DaVinci Resolve in a Rocky Linux container, and Resolve without the GPU is not Resolve. |
| `libva-nvidia-driver` | Hardware video decoding through the card. |
| `nvidia-drm.modeset=1` | A boot option. It tells the driver to take the screen from the very start rather than halfway through booting. Without it a Wayland desktop on NVIDIA either refuses to start or flickers through a mode change on every boot. It ships as a file in `/usr/lib/bootc/kargs.d/`, so it travels with the image and nobody has to edit a bootloader. |
| A dracut tweak | Loads the driver from the initial boot ramdisk, and pre-loads the built-in Intel/AMD graphics alongside it so Chromium-based apps — Aquarius Editor among them — can still find a GPU for video acceleration. |
| An SELinux rule | Lets containers reach the graphics card. Without it, R3's Resolve container fails with permission errors that look exactly like a driver problem. |

---

## Why `nvidia-open` and not the older closed driver

The "open" driver is NVIDIA's own open-source kernel module. It is the **only**
one that supports RTX 50-series cards at all, and it fully supports RTX 20, 30
and 40 series — which covers the bench's 4090 and everything anyone would buy
now.

The older closed module only matters for GTX 900/1000-era cards. If that ever
becomes a real requirement, Universal Blue publishes that box too
(`akmods-nvidia` instead of `akmods-nvidia-open`) and it is a one-line change in
`aquarius-os.env`.

---

## A naming trap, written down

The package that contains the kernel module is called **`kmod-nvidia`**, even in
the `nvidia-open` box. Not `kmod-nvidia-open`.

That is because the box is built from negativo17's packaging, which uses the
same package name for both flavours and distinguishes them by which repository
they came from. So `rpm -q kmod-nvidia-open` returns "not installed" on a
perfectly correct NVIDIA image, and `rpm -q kmod-nvidia` is the right question.
CI asks the right one.

---

## If Universal Blue's box ever changes shape

`build_files/60-nvidia.sh` prints the entire contents of the box near the top of
its log, before it does anything with it, and every path it expects is checked
with a message that says what to do. If they reorganise, the build stops with a
readable error and a listing of what is actually in there, rather than
installing half a driver.

Their README is the reference: <https://github.com/ublue-os/akmods>
