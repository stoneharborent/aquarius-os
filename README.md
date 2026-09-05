# AquariusOS

**A Linux desktop built for creators — and a good gaming machine too.**

This repository is the *recipe* for an operating system. It is not the operating
system itself: it is a short list of instructions that a robot on GitHub follows
to build the operating system for us, automatically, every time we change
something.

If you have never done OS work before, **you are in the right place and this is
much smaller than it sounds.**

---

> ## ⚠️ Which branch am I looking at?
>
> **`main` is AquariusOS** — rebuilt from scratch on bare Fedora, started
> 2 September 2026. It publishes:
>
> - `ghcr.io/stoneharborent/aquarius-os` — AMD and Intel graphics
> - `ghcr.io/stoneharborent/aquarius-os-nvidia` — NVIDIA graphics
>
> **`bazzite-archive` is the older Bazzite-based line**, which was `main` until
> 4 September 2026. It is frozen and no longer built: its six images stay in the
> registry, each with a permanent `bazzite-final` tag, and nothing is ever
> merged between the two branches.
>
> Why we started over: [`docs/base-distro-reassessment-2026-09.md`](docs/base-distro-reassessment-2026-09.md)
> What that means in practice: [`docs/restart/README.md`](docs/restart/README.md)
> How the names and branches were swapped over: [`docs/restart/final-names.md`](docs/restart/final-names.md)

---

## The whole idea, in one picture

```
   THIS REPO                GITHUB ACTIONS                 THE RESULT
   (the recipe)             (the free build robot)         (the OS)

   Containerfile      ──►   reads the recipe         ──►   ghcr.io/stoneharborent/
   build_files/             starts from Fedora             aquarius-os
   system_files/            runs our eight steps           aquarius-os-nvidia
   aquarius-os.env          INSPECTS the result
                            publishes and signs it                │
        ▲                                                        ▼
        │                                                 an .iso you can write
   you edit a file                                        to a USB stick and
   and `git push`                                         install on a PC
```

Three things to understand, and then you know the model.

**1. We do not maintain a kernel, drivers, or an installer.** We start from
`quay.io/fedora/fedora-bootc` — Fedora's official bootable base image. Fedora
handles the terrifying parts forever, for free. We add every other layer
ourselves, on purpose.

**2. The whole OS is defined by a recipe file.** `Containerfile` says where to
start; the eight numbered scripts in `build_files/` say what to add and what to
change. That is genuinely the entire operating system definition.

**3. GitHub builds it, not your Mac.** You cannot build a Linux OS image on an
Apple Silicon Mac and you never need to. Push a change, and GitHub Actions spins
up a Linux machine, builds it, checks it, and publishes it.

**Why "atomic" matters:** this style of OS updates as one single unit and can
always go back to the previous version at boot. If a bad update ships, the user
picks the older entry in the boot menu and they are fine. It is very hard to
break permanently — which is exactly what you want on a machine somebody edits
video on.

---

## What is in each folder

| Path | What it is |
| --- | --- |
| `Containerfile` | The recipe. Short, heavily commented, rarely changes. |
| `build_files/` | The eight build steps, numbered in the order they run. This is where day-to-day changes happen. |
| `system_files/` | Files copied into the OS exactly as they are — wallpaper, logos, fonts, GNOME defaults, and the AquariusOS windows (the welcome, the app chooser, the Resolve installers). To add a file to the OS, put it here in the right place. |
| `branding/` | The sources those files are made from: logo SVGs, wallpaper SVGs, the scripts that render them, and `tokens.md` (the colours). |
| `ingest/` | `aq-ingest`, the "Make Editor-Ready" helper, with its own test suite. |
| `.github/workflows/` | The build robot's instructions. |
| `disk_config/` | Settings for turning a published image into an installer ISO. |
| `docs/restart/` | **Start here.** Plain-language docs for the current line. |
| `docs/` | Older research notes and decision records. Some describe the Bazzite line; the ones that still apply are linked from `docs/restart/README.md`. |
| `aquarius-os.env` | Image names and versions. The one place they live. |
| `Justfile` | The build commands. `just` on its own lists them. |

---

## What AquariusOS is for

Two audiences, and the first one is the reason the project exists.

### Creators

The thing no other Linux distribution does: **free DaVinci Resolve on Linux
cannot open a file from a camera or a phone.** Not "opens it badly" — cannot
open it. H.264 and H.265 decoding is Studio-only and NVIDIA-only, and AAC audio
is unsupported in every version. Every person who tries Resolve on Linux hits
this on their first import.

AquariusOS fixes it at the operating-system level. Right-click a file, choose
**Make Editor-Ready**, and it becomes something Resolve will open. That is
`aq-ingest`, it ships in the image, and nobody else does it.

Around that: every codec present and working, hardware video decoding, XWayland
because Resolve is X11-only, NVIDIA drivers because NVIDIA is the only vendor
Blackmagic supports on Linux, and containers ready for the Rocky Linux userland
Resolve actually wants.

### Gamers

Desktop gaming, properly, and it is **in the image now** (Phase R4): Steam,
Proton, gamescope, gamemode, MangoHud, vkBasalt, umu, the 32-bit libraries a
Windows game needs, and Xbox controller drivers — on both images, with nothing
to set up. Four more gaming apps (Heroic, Lutris, ProtonUp-Qt, Protontricks)
are offered, unticked, in the app chooser — step 2 of the welcome — at first
login.

There is no Game Mode session — Steam's own Big Picture does that job on a
desktop — and handheld consoles are explicitly **out of scope**: that is
Bazzite's and SteamOS's product, and doing it well means testing thirty devices.
Full guide: [`docs/restart/gaming.md`](docs/restart/gaming.md).

---

## How to do things

Full guide: [`GETTING-STARTED.md`](GETTING-STARTED.md).

**Change something in the OS** — edit a file, commit, push to `main`. GitHub
builds and publishes both images. Watch it at
[Actions](https://github.com/stoneharborent/aquarius-os/actions).

**Put a new build on a machine that already runs AquariusOS** — on that Linux
machine (not on the Mac), run `command -v bootc`. If it prints a path:
`sudo bootc switch ghcr.io/stoneharborent/aquarius-os-nvidia:latest`. If it
prints nothing, the older tool does the same job:
`sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/stoneharborent/aquarius-os-nvidia:latest`.
Then reboot. Reversible with `sudo bootc rollback`. Step by step:
[`docs/restart/bench-rebase.md`](docs/restart/bench-rebase.md).

**Install on a machine that does not run it yet** — build an ISO by hand:
Actions → **Build AquariusOS ISO** → *Run workflow*. Pushing a tag
(`git tag iso-nvidia-2026-09-05 && git push origin iso-nvidia-2026-09-05`) still
works and is the way to build one from a branch. Details: see
[`GETTING-STARTED.md`](GETTING-STARTED.md#3-make-an-installer-usb-stick).

---

## The rules

1. **Never merge `bazzite-archive` and `main`.** They are two different
   operating systems that happen to share a repository.
2. **The images are called `aquarius-os` and `aquarius-os-nvidia`.** For two
   days in September 2026, while both lines were live, they were published
   under temporary names ending in `-next`. That is history now, and the build
   fails if one of those names comes back. See
   [`docs/restart/final-names.md`](docs/restart/final-names.md).
3. **One recipe, two images.** The NVIDIA difference is a build switch, never a
   second Containerfile.
4. **Check the result by reading its contents** — the value a setting reports,
   the text in a file, the answer `rpm` gives. **Never timestamps**: the tool
   that packages a bootable image flattens every file's clock, so a timestamp
   check passes forever, including when the step it was checking did nothing.
5. **Plain language everywhere**, in every file, for someone who has never used
   Linux.

---

## Licence

Apache 2.0. See [LICENSE](LICENSE).
