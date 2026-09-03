# The Restart — what changed, and how to read the new build

*Written 2026-09-03, for Phase R1. Assumes you have never used Linux.*

---

## The one-paragraph version

AquariusOS used to be built on top of **Bazzite**, a gaming operating system.
On 2 September 2026 Royce decided to start over on **bare Fedora** instead. The
reason is not that Bazzite is bad — it is that Bazzite had already made a few
thousand decisions for us, most of them about handheld gaming consoles, and we
were spending our time undoing them instead of building a creator's machine.
Worse, the exact thing Bazzite is best at (shipping the newest possible
software, very fast) is the exact thing DaVinci Resolve on Linux hates most.

So: same family, different starting point. AquariusOS is still Fedora
underneath. It is just Fedora with *nothing on it*, and everything that is on it
now is there because we chose it.

**The long version, with the research behind it, is one folder up:**
[`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md).

---

## Nothing on your computer broke

This is worth saying plainly, because "we started over" sounds alarming.

The six Bazzite-based images are still published and still updating. The 4090
bench machine, which is running one of them right now, keeps working exactly as
it did. The old recipe lives on the `main` branch and is frozen — no new work
lands on it, but it is not deleted and it is not going anywhere.

The new line publishes under **different names** so it cannot possibly overwrite
the old one:

| Old (Bazzite, frozen) | New (Fedora, current) |
| --- | --- |
| `aquarius-os-gnome` | `aquarius-os-next` |
| `aquarius-os-gnome-nvidia` | `aquarius-os-next-nvidia` |

Moving the bench from one to the other is a single command, and it is reversible
with a single command. That is what
[`bench-rebase.md`](bench-rebase.md) walks through.

The word "next" comes off the names when Phase R3 finishes and the new line has
earned them.

---

## What R1 actually builds

R1 is called *"it boots and it's ours, from nothing"*, and that is the whole
ambition. When it is done, the bench machine should start up, show a login
screen with the AquariusOS logo, log into an ice-blue GNOME desktop with our
wallpaper and our dock, and say "AquariusOS" in Settings → About.

That is a lower bar than the Bazzite line cleared months ago, and that is fine:
this is starting from an empty room.

### What is in it

- **A computer that works.** Graphics, sound, Wi-Fi, Bluetooth, battery,
  firmware updates, camera cards, Windows drives, a graphical boot screen.
- **Every codec.** The full ffmpeg, the AAC encoder, hardware H.264 and H.265
  decoding, HEIC photos from iPhones. This is the part Fedora leaves out for
  patent reasons and it is the part a video machine cannot live without.
- **A desktop.** GNOME — a deliberately short list of it, not the whole thing —
  in the Ice light theme, with our wallpaper, our fonts, our logo on the About
  page and the login screen, and a dock along the bottom.
- **The plumbing for what comes next.** Flatpak with Flathub already set up,
  `distrobox` and `podman` ready for the Resolve container, XWayland ready for
  Resolve itself, and the NVIDIA container toolkit already wired in.
- **`aq-ingest`**, the "Make Editor-Ready" right-click menu — the one feature no
  other operating system ships.

### What is NOT in it yet, and when it arrives

| Missing | Comes back in |
| --- | --- |
| The Aquarius Desktop (our own shell), labwc, Quickshell, greetd | **R2** |
| The AquariusOS logo button in the top-left corner of the screen | **R2** (see below) |
| DaVinci Resolve container, Aquarius Editor, Aquarius Writer, OBS, Blender | **R3** |
| Steam, Proton, MangoHud — desktop gaming | **R4** |

Two smaller absences, so they are not mistaken for bugs:

- **No logo in the top bar.** That button came from a GNOME extension called
  Logo Menu, which Universal Blue packages and Fedora does not. Packaging it
  ourselves is an R2 job. Until then the AquariusOS identity lives on the About
  page, the login screen, the wallpaper and in the system's own name.
- **No printing.** Not on this machine's job list, and the printing stack is
  large. One command adds it for anyone who wants it.

---

## How to read the build

Everything the operating system is made of is described by two kinds of file.

### 1. `Containerfile` — the recipe

Think of it as a numbered list: "start from this, then run step 1, step 2, step
3…". It is short, it is heavily commented, and it almost never changes.

The one part of it worth understanding is how *two* images come out of *one*
recipe. There is a switch called `NVIDIA`, it is `0` or `1`, and the recipe uses
a standard trick so that the AMD/Intel build never even downloads the NVIDIA
parts. The comment above that trick in the file explains it properly.

### 2. `build_files/` — the steps

Eight scripts, numbered in the order they run. The numbers are the point: the
build log reads in the same order as the folder listing, so when something goes
wrong you can find the file by its heading.

| File | What it does |
| --- | --- |
| `aq-lib.sh` | Shared helpers. Read the top of this one first — it explains the "trust content, never timestamps" rule that shapes every check in the repo. |
| `10-repos.sh` | Adds RPM Fusion, so the next step has real codecs to install. |
| `20-hardware-media.sh` | Makes it a working computer: graphics, sound, network, power, firmware, filesystems, and every codec. The biggest step. |
| `30-session.sh` | The invisible layer between "has drivers" and "has a desktop": the login screen, portals, XWayland, Flatpak, fonts, containers. |
| `40-gnome-desktop.sh` | GNOME — a hand-written short list, with a note on everything deliberately left out. |
| `50-aquarius-desktop.sh` | Makes it *ours*: wallpaper, logos, Ice theme, fonts, dock, the right-click ingest menu. |
| `60-nvidia.sh` | The NVIDIA driver. Does nothing on the AMD/Intel image. The hardest file in the repo — see [`nvidia-notes.md`](nvidia-notes.md). |
| `70-image-info.sh` | Teaches the system to call itself AquariusOS. |
| `90-cleanup.sh` | Sweeps up, and refuses to ship an image with two kernels in it. |

### 3. `system_files/` — files that are copied in as-is

Whatever is in here is copied to the same place on the finished system. To add
a file to the operating system, put it in the right place under `system_files/`
— there is no list anywhere to update.

The interesting ones are the three `zz1-aquarius-*.gschema.override` files,
which are GNOME's factory settings replaced with ours. Each one has a long
plain-English header explaining what it does and, more usefully, what it
deliberately does *not* do.

---

## Every step checks its own work

This is the habit that matters most in this repo, and it comes from a real
failure.

On 31 August 2026 a build step decided whether it had done its job by checking
whether one file was *newer* than another. That works on a normal computer. It
is meaningless here, because the tool that packages a bootable image sets every
file's clock to the same value. The check passed every time — including the
times the step had silently done nothing at all.

So: **every check reads actual content.** The text inside `/etc/os-release`. The
value `gsettings` reports when asked. The answer `rpm` gives. The checksum of a
picture. Never a date, never "is this file newer than that one".

It happens twice, on purpose:

1. **During the build**, inside each step, so a failure names the step.
2. **After the build**, in GitHub Actions, by starting the finished image and
   interrogating it the way a real machine would — before anything is published.

The second one is why `.github/workflows/build-next.yml` is long. It is not
ceremony. It is the difference between "the build was green" and "the image
actually works".

---

## Building it

You do not need a Linux computer. GitHub builds the OS.

- **Every push to `restart/fedora-bootc`** builds and publishes both images.
  Watch it at GitHub → Actions → *Build AquariusOS (next)*.
- **Installer ISOs are built by hand** when they are needed, by pushing a tag
  named `iso-base-…` or `iso-nvidia-…`. It takes 20–40 minutes and the ISO
  appears at the bottom of the run's page.

  It is a tag rather than the usual "Run workflow" button because GitHub only
  shows that button for workflows on the repository's *default* branch, and ours
  is still `main`. The button starts working, with no change to anything, the
  day this branch becomes the default one.

If you *do* have a Linux machine with `podman` on it, `just build` does the same
thing locally. `just` with no arguments lists everything available.

---

## The rules that do not move

1. **Never merge this branch into `main`.** `main` is the frozen Bazzite line
   and the six published images depend on it staying exactly as it is.
2. **New names until R3 closes.** `aquarius-os-next`, not `aquarius-os`.
3. **One recipe.** The NVIDIA difference is a switch, not a second Containerfile.
   Adding a second recipe is how two images quietly drift apart.
4. **Read the result back.** Content, never timestamps.
5. **Plain language everywhere.** Every file in this repo is written for someone
   who has never used Linux, because that is who has to maintain it.

---

## Where to go next

- **Moving the bench machine over:** [`bench-rebase.md`](bench-rebase.md)
- **Why the NVIDIA driver is done the way it is:** [`nvidia-notes.md`](nvidia-notes.md)
- **Why Fedora and not Bazzite/Arch/Ubuntu:** [`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md)
- **The plan for R2, R3 and R4:** `ROADMAP.md`, one folder above the repo
