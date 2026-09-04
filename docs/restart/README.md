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

Moving the bench from one to the other is one command on the bench PC — `bootc
switch`, or `rpm-ostree rebase` on a machine that does not have `bootc` — and it
is reversible with a single command. That is what
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
  firmware updates, camera cards, Windows drives.
- **A boot screen that is ours.** The Aquarius mark and the word AquariusOS on
  near-black while the machine starts — no Fedora logo and no computer-maker's
  badge — plus the name AquariusOS in the boot menu and over a text login
  prompt. How it works, and the one trap in it:
  [`boot-branding.md`](boot-branding.md).
- **Every codec.** The full ffmpeg, the AAC encoder, hardware H.264 and H.265
  decoding, HEIC photos from iPhones. This is the part Fedora leaves out for
  patent reasons and it is the part a video machine cannot live without.
- **A desktop.** GNOME — a deliberately short list of it, not the whole thing —
  in the Ice light theme, with our wallpaper, our fonts, our logo on the About
  page and the login screen, and a dock along the bottom.
- **The plumbing for what comes next.** Flatpak with Flathub already set up,
  `distrobox` and `podman` ready for the Resolve container, XWayland ready for
  Resolve itself, and the NVIDIA container toolkit already wired in. R3a turned
  all of that into a working **Install DaVinci Resolve** button.
- **`aq-ingest`**, the "Make Editor-Ready" right-click menu — the one feature no
  other operating system ships.
- **btrfs by default**, declared inside the image, so every installer agrees:
  snapshots and transparent compression on a machine that stores video.

### What is NOT in it yet, and when it arrives

| Missing | Comes back in |
| --- | --- |
| ~~The Aquarius Desktop (our own shell), labwc, Quickshell, greetd~~ | **shipped in R2** — see [`aquarius-session.md`](aquarius-session.md) |
| The AquariusOS logo button in the top-left corner of the screen | **R2** (see below) |
| ~~DaVinci Resolve, in its own Rocky Linux container~~ | **shipped in R3a** — see [`resolve.md`](resolve.md) |
| ~~Aquarius Editor, Aquarius Writer, OBS, Kdenlive, Blender and the rest of the creator suite~~ | **shipped in R3b** — see [`creator-apps.md`](creator-apps.md) |
| ~~Steam, Proton, MangoHud — desktop gaming~~ | **shipped in R4** — see [`gaming.md`](gaming.md) |

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

Twelve numbered scripts, run in order, plus four `stage-` scripts that are not
part of the operating system at all — they compile or fetch the pieces Fedora
does not give us (labwc, Quickshell, the Aquarius Shell, xremap), in throwaway
containers, and only the results are copied in. The numbers on the rest are the
point: the build log reads in the same order as the folder listing, so when
something goes wrong you can find the file by its heading. Numbers are left
spare between them so a new step can be slotted in without renaming everything
after it.

| File | What it does |
| --- | --- |
| `stage-labwc.sh` | Not part of the operating system. Compiles the labwc window manager in a throwaway container, because Fedora 44 packages an older one than we need. |
| `stage-quickshell.sh` | The same, for Quickshell — the runtime that draws our bar. Compiled inside the image so it can never disagree with the image's Qt. |
| `stage-aquarius-shell.sh` | The same idea again: fetches the Aquarius Shell at one exact commit and copies across only the parts that run. |
| `aq-lib.sh` | Shared helpers. Read the top of this one first — it explains the "trust content, never timestamps" rule that shapes every check in the repo. |
| `10-repos.sh` | Adds RPM Fusion, so the next step has real codecs to install. |
| `20-hardware-media.sh` | Makes it a working computer: graphics, sound, network, power, firmware, filesystems, and every codec. The biggest step. |
| `30-session.sh` | The invisible layer between "has drivers" and "has a desktop": the login screen, portals, XWayland, Flatpak, fonts, containers. |
| `40-gnome-desktop.sh` | GNOME — a hand-written short list, with a note on everything deliberately left out. |
| `50-aquarius-desktop.sh` | Makes it *ours*: wallpaper, logos, Ice theme, fonts, dock, the right-click ingest menu. |
| `55-aquarius-session.sh` | The **Aquarius Desktop** — our own shell on the labwc window manager, added beside GNOME as a second choice at the login screen. Installs what the two compiled programs need, sets up the portals, and switches greetd off. See [`aquarius-session.md`](aquarius-session.md). |
| `60-nvidia.sh` | The NVIDIA driver. Does nothing on the AMD/Intel image. The hardest file in the repo — see [`nvidia-notes.md`](nvidia-notes.md). |
| `62-resolve-runtime.sh` | **DaVinci Resolve — everything except Resolve.** Resolve itself may not be shipped by anybody but Blackmagic, so this puts in place the setup that builds a Rocky Linux container on the user's own machine and installs their own download into it, plus the launcher, the `aq resolve` commands, the USB rules for licence dongles, and the graphics-card plumbing. Why a container at all: [`resolve.md`](resolve.md). |
| `62-resolve-runtime.sh` (the windows) | Also checks the two DaVinci Resolve windows — Install and Remove — the shared window pieces in `/usr/lib/aquarius/python/aquarius_ui.py`, and the rule that nothing a person reads may name another Linux. |
| `70-image-info.sh` | Teaches the system to call itself AquariusOS. |
| `74-xremap-build.sh` | ⚠️ Does NOT run inside AquariusOS. It runs in a throwaway container whose only job is to compile the keyboard remapper, so that a compiler never ends up in the finished operating system. |
| `55-aquarius-session.sh` (password prompts) | Also installs the polkit authentication agent and checks the session starts it. Without one, nothing in the Aquarius Desktop can ask for a password and installing creator apps fails with a message about `/dev/tty` — the 2026-09-04 bench fault. See [`aquarius-session.md`](aquarius-session.md#asking-for-your-password). |
| `55-aquarius-session.sh` (screen size) | Also installs `/usr/libexec/aquarius-display-scale`, which sets each monitor to the right size at every login. Without it labwc leaves every screen at 100% and a 4K desktop is physically tiny — the bench's first complaint on 2026-09-03. Guide: [`aquarius-display.md`](aquarius-display.md). |
| `75-aquarius-keys.sh` | Mac-style keyboard shortcuts, on by default — Copy is Command-C. Installs what the step above built, and checks the whole feature. Plain-language guide: [`aquarius-keys.md`](aquarius-keys.md). |
| `62-virtual-camera.sh` | The fake webcam behind OBS Studio's "Start Virtual Camera" button. Takes a ready-made, already-signed kernel module from Universal Blue. ⚠️ Must run after `60-nvidia.sh`, which sometimes replaces this image's kernel. If the module and our kernel do not match it leaves the feature out and writes down why, rather than shipping something that cannot work. |
| `64-creator-apps.sh` | **The creator layer.** Bakes Aquarius Editor and Aquarius Writer into the image, checks the list of creator Flatpaks against Flathub, validates the extra permissions those apps need, switches the permissions service on (and deliberately leaves the bulk app installer OFF, because the chooser at first login asks the person which apps they want), and promotes the ingest helper. The biggest and slowest step. See [`creator-apps.md`](creator-apps.md). |
| `66-creator-apps-chooser.sh` | **The window that offers those apps to a person** — "Your creator apps" at the first login, "Aquarius Apps" in the app grid afterwards. Installs what a GTK window needs to run from Python, checks both menu entries, checks that nothing installs itself any more, and — the check that matters — reads the real list in the finished image with the window's own parser. See [`creator-apps.md`](creator-apps.md). |
| `68-gaming.sh` | **The gaming layer.** Adds Terra (and switches it straight off again), installs Steam, umu-launcher, gamescope, gamemode, MangoHud, vkBasalt and the 32-bit graphics libraries a Windows game needs, takes the Xbox controller drivers from the same signed module box as the virtual camera, and proves that none of it replaced Fedora's graphics driver. ⚠️ Must run after `60-nvidia.sh`, for the same kernel reason as `62-virtual-camera.sh`. See [`gaming.md`](gaming.md). |
| `80-boot-branding.sh` | Everything you see BEFORE the login screen: the Aquarius boot splash, the name in the boot menu, the text login banners — and a rebuild of the boot ramdisk, without which none of it takes effect. ⚠️ Must run after `60-nvidia.sh`; see [`boot-branding.md`](boot-branding.md). |
| `90-cleanup.sh` | Sweeps up, and refuses to ship an image with two kernels in it. |

### There is a SECOND recipe, and it does not build the operating system

`resolve-runtime/Containerfile` builds a small **Rocky Linux** that DaVinci
Resolve runs inside. It is its own image, with its own build
(`.github/workflows/build-resolve-runtime.yml`), and it is downloaded onto a
machine the first time somebody sets Resolve up — never before, because it is
about a gigabyte and not everybody uses it.

It exists because Resolve carries its own copy of a library from 2021 that
clashes with any modern Linux's own and kills it before its window opens.
Enterprise Linux still carries the matching version, so in there the clash
cannot happen. The whole argument is in [`resolve.md`](resolve.md).

There is **no DaVinci Resolve inside it**, and there never will be —
Blackmagic's licence does not allow anyone else to distribute their installer.
Both builds check for its absence and refuse to publish an image containing it.

### 3. `system_files/` — files that are copied in as-is

Whatever is in here is copied to the same place on the finished system. To add
a file to the operating system, put it in the right place under `system_files/`
— there is no list anywhere to update.

The interesting ones are the three `zz1-aquarius-*.gschema.override` files,
which are GNOME's factory settings replaced with ours. Each one has a long
plain-English header explaining what it does and, more usefully, what it
deliberately does *not* do.

A few more worth knowing about, all added in R3b:

| Path | What it is |
| --- | --- |
| `usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall` | The shopping list of creator apps. Adding or removing an app is a one-block edit here. |
| `usr/share/aquarius/flatpak-overrides/` | The extra permissions those apps need — a camera for OBS, an external drive for Kdenlive. Its `README.md` explains why they cannot simply be shipped where Flatpak reads them. |
| `etc/skel/.config/aquarius-shell/dock.json` | What a brand-new account finds pinned to the Aquarius Desktop's dock. |
| `usr/libexec/aquarius-creator-apps` | **The app chooser window.** Opens itself once at the first login, and lives in the app grid as "Aquarius Apps". Knows no app names of its own — it reads them from the two files above. |
| `usr/libexec/aquarius-creator-apps-install` | The part that actually installs, one app at a time, as an administrator. The window starts it through `pkexec`, which is where the single password prompt comes from. |
| `usr/share/aquarius/gaming/README.md` | *(R4)* The plain-language gaming note that ships inside the OS. Next to it, `controllers.txt` is written by the build and is the honest answer to "are the Xbox drivers in this image?". |
| `usr/share/applications/aquarius-steam-bigpicture.desktop` | *(R4)* **Steam (Big Picture)** in the app grid — the desktop's answer to a console interface, with no separate session behind it. |
| `etc/xdg/autostart/aquarius-creator-apps-firstrun.desktop` | What opens the chooser at a first GNOME login. ⚠️ The Aquarius session needs the same thing said again, at the end of `usr/share/aquarius/labwc/autostart`, because labwc does not read this folder at all. |

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
- **How the boot screen and the boot menu are branded:** [`boot-branding.md`](boot-branding.md)
- **The creator apps: what ships, how it arrives, how to remove one:** [`creator-apps.md`](creator-apps.md)
- **Making camera files open in an editor (the ingest helper):** [`ingest.md`](ingest.md)
- **Mac-style keyboard shortcuts (Copy is Command-C):** [`aquarius-keys.md`](aquarius-keys.md)
- **How big things are on the screen (and why it was too small):** [`aquarius-display.md`](aquarius-display.md)
- **DaVinci Resolve — installing it, and why it lives in a container:** [`resolve.md`](resolve.md)
- **Gaming: what ships, the launch options worth knowing, and what is deliberately not here:** [`gaming.md`](gaming.md)
- **Why the NVIDIA driver is done the way it is:** [`nvidia-notes.md`](nvidia-notes.md)
- **Why Fedora and not Bazzite/Arch/Ubuntu:** [`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md)
- **The plan for R2, R3 and R4:** `ROADMAP.md`, one folder above the repo
