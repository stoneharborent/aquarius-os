# AquariusOS

**AquariusOS — the OS for gamers and creators.**

This repository is the *recipe* for a Linux operating system. It is not the operating
system itself — it is the short list of instructions that a robot on GitHub follows to
build the operating system for us, automatically, every time we change something.

If you have never done OS work before: **you are in the right place, and this is much
smaller than it sounds.** Read this page, then follow [GETTING-STARTED.md](./GETTING-STARTED.md)
to put it on GitHub.

---

## How AquariusOS works (the whole idea in one picture)

```
   THIS REPO                  GITHUB ACTIONS                    THE RESULT
   (the recipe)               (the free build robot)            (the OS)

   Containerfile        ──►   reads the recipe            ──►   ghcr.io/<you>/aquarius-os
   build_files/build.sh       downloads Bazzite                 ghcr.io/<you>/aquarius-os-nvidia
   system_files/              runs our build script             ghcr.io/<you>/aquarius-os-deck
   aquarius-os.env            packages up the result            (bootable OS images)
                              …three times: AMD/Intel,                  │
        ▲                     NVIDIA, and handheld                      ▼
        │                                                        an .iso you can
   you edit a file                                               burn to a USB stick
   and `git push`                                                and install on a PC
```

Three things to understand and then you know the model:

**1. We are not building an OS from scratch.** We start from **Bazzite**, a well-maintained
gaming Linux system (Steam, Game Mode, GPU drivers, controller support, handheld support all
work already). Bazzite handles the terrifying parts — the kernel, drivers, security updates —
forever, for free. We add a layer on top. That layer is what makes it *ours*.

**2. The OS is defined by a recipe file, like a Dockerfile.** `Containerfile` says "start from
Bazzite," and `build_files/build.sh` says "…then install these things and change these
settings." That is genuinely the entire OS definition.

**3. GitHub builds it, not your Mac.** You cannot build a Linux OS image on an Apple Silicon
Mac, and you never need to. Every time you push a change, GitHub Actions spins up a Linux
machine, builds the image, and publishes it. You watch a progress bar. That's the job.

**Why "atomic" matters:** this style of OS updates as one single unit and can always roll
back to the previous version at boot. If a bad update ships, the user picks the older entry
in the boot menu and they're fine. It is very hard for a user to break permanently — which is
exactly what you want when non-technical creators are your audience.

---

## Which image do I pick?

There are **three AquariusOS images**. They are the same operating system — same apps, same
settings, same creator suite — built on three different Bazzite foundations. Two questions
pick one for you, in this order:

**1. Is the machine a gaming handheld?** (ROG Xbox Ally, ROG Ally X, Steam Deck, Legion Go —
something with a screen, thumbsticks and no keyboard.)

| Answer | Pick | Full address |
|---|---|---|
| **Yes, it's a handheld** | `aquarius-os-deck` | `ghcr.io/stoneharborent/aquarius-os-deck:latest` |

**2. Otherwise — what graphics card is in it?**

| Your graphics card | Pick | Full address |
|---|---|---|
| **NVIDIA** — any RTX card (including the RTX 5090), or a GTX 16-series | `aquarius-os-nvidia` | `ghcr.io/stoneharborent/aquarius-os-nvidia:latest` |
| **AMD or Intel** — including laptop built-in graphics | `aquarius-os` | `ghcr.io/stoneharborent/aquarius-os:latest` |

If you're not sure, it's AMD or Intel — NVIDIA cards are a deliberate purchase and you'd know.

**What the handheld one does differently.** It starts up in **Game Mode** — the full-screen,
controller-driven Steam interface, the same shape of thing a Steam Deck boots into — instead
of a desktop. The desktop is still there and is still the whole AquariusOS creator desktop:
you switch to it from Steam's power menu, and everything below is waiting for you. That is
the point of the image, and the thing no other handheld OS offers: dock the handheld, switch
to Desktop, and edit the footage you just captured.

**Why they can't be one image:** NVIDIA graphics need NVIDIA's own driver baked into the OS,
and that driver can't be present on machines that don't have the card. Handhelds need a
different startup mode and a pile of handheld-specific hardware support. Both splits happen
one level down, in Bazzite, and we inherit them. Nothing about the AquariusOS layer differs
between the three — it is genuinely one recipe.

**You are not stuck with your choice.** Switching between them later is one command and a
reboot — see "Switching between the two images" in [GETTING-STARTED.md](./GETTING-STARTED.md).
Worth knowing if you ever swap the graphics card in a machine.

All three are built by the same GitHub Actions run, from the same recipe, at the same time.
There is no "the NVIDIA one is behind" — they ship together. Which Bazzite image each one is
built on, and why that specific one:
[`docs/nvidia-variant-research.md`](./docs/nvidia-variant-research.md) and
[`docs/deck-variant-research.md`](./docs/deck-variant-research.md).

---

## Repo map

| Path | What it is | Do you touch it? |
|---|---|---|
| `README.md` | This file. | — |
| `GETTING-STARTED.md` | **Click-by-click setup for putting this on GitHub.** Start here. | Read it |
| `Containerfile` | The recipe. Says "start from Bazzite, then run our build script." Used for all three images — which Bazzite to start from is a knob it accepts. | Rarely |
| `build_files/build.sh` | **The main file you edit.** Installs packages and makes changes on top of Bazzite. Applies to all three images. This is where the creator apps live. | Often |
| `aquarius-os.env` | Settings: all three image names, all three base images, description, GitHub username. One place, used everywhere. | Once, at setup |
| `system_files/` | Anything here gets copied into the OS's filesystem. `system_files/usr/…` becomes `/usr/…` in the running OS. Holds the desktop look: colour scheme, wallpaper, fonts, layout. | Sometimes |
| `branding/` | **The design.** Colours, fonts, logo and wallpaper artwork, with `tokens.md` as the single source of truth. Read [`branding/README.md`](./branding/README.md) before changing how anything looks. | To change the look |
| `ingest/` | **"Make Editor-Ready"** — the tool that takes camera files and writes copies DaVinci Resolve can actually open, with sound. Added to the right-click menu in the Files app. Read [`ingest/README.md`](./ingest/README.md). | Rarely |
| `docs/ingest-right-click.md` | **How to get a camera card ready for editing** — the beginner walkthrough for the above. No terminal needed. | Read it |
| `disk_config/` | Settings for turning the OS image into an installable `.iso` / VM disk. `iso.toml` is the one that's used. | Once, at setup |
| `.github/workflows/build.yml` | The build robot's instructions: build **all three** OS images and publish them. Runs on every push + nightly. | No |
| `.github/workflows/build-iso.yml` | The second robot: turns one published OS image into a USB installer `.iso`. You run this by hand and pick which image. | No |
| `.github/workflows/build-disk.yml` | Makes a virtual-machine disk for testing. By hand, AMD/Intel image only. | No |
| `installer/` | The live USB installer environment the ISO robot builds. Works for any of the three images. | Rarely |
| `Justfile` | A collection of shortcut commands used by the build robot (and usable on a Linux machine). | No |
| `docs/nvidia-variant-research.md` | Why the NVIDIA image is built on `bazzite-nvidia-open` and not `bazzite-nvidia`. | Reference |
| `docs/deck-variant-research.md` | Why the handheld image is built on `bazzite-deck`, what it inherits, and why none of our layers fight Game Mode. | Reference |
| `docs/UPSTREAM-TEMPLATE-README.md` | The original README from the upstream template we copied, kept for reference. Written for experts. | Reference |
| `LICENSE` | Apache 2.0, inherited from the upstream template. | No |

Planning docs live one level up: `../ROADMAP.md` is the master plan (phases, decisions).

---

## Current state — Phase 1

This is a **v0.1 scaffold**. It has not been built or booted yet.

What's set up:
- **The AquariusOS look** — dark "Flow State" colour scheme, Inter / JetBrains Mono /
  Sora typefaces, the "The Pour" wallpaper, and a macOS-shaped desktop (slim top bar,
  floating dock, desktop icons down the right edge). See "The look" below.
- Base image: **Bazzite stable, KDE desktop** (`ghcr.io/ublue-os/bazzite:stable`)
- Image name: **`aquarius-os`** → publishes to `ghcr.io/<your-github-username>/aquarius-os`
- Second image: **`aquarius-os-nvidia`**, same recipe on `ghcr.io/ublue-os/bazzite-nvidia-open:stable`,
  built by the same run — see "Which image do I pick?" above
- Third image: **`aquarius-os-deck`**, same recipe on `ghcr.io/ublue-os/bazzite-deck:stable`,
  built by the same run — the handheld one, boots into Game Mode
- Build layer: installs exactly one package (`htop`) as proof the layer works
- Phase 2 creator apps: **commented-out stubs only** in `build_files/build.sh` — visible, not active

What is *not* done yet (all tracked in `../ROADMAP.md`):
- Image signing (cosign) is **not** configured — see GETTING-STARTED, this one matters
- The OS still identifies itself as Bazzite, not AquariusOS (a separate job — see
  `docs/os-release-branding-research.md`)
- The top bar has no window title or close/minimise/maximise buttons yet — KDE ships no
  widget for either. Explained in the layout script's own comments.
- Nothing has been booted on real hardware yet

---

## The look

AquariusOS has its own visual identity, and it is all defined in one place.

**[`branding/tokens.md`](./branding/tokens.md) is the source of truth** — every colour,
font, size and animation speed, written down in plain language. Nothing in this project
should use a colour that isn't in that file. The design itself is decided in the Claude
Design project "AquariusOS Core Identity", direction "Flow State".

What a user actually sees after installing:

| | |
|---|---|
| **Colours** | Near-black backgrounds (`#06070C`), a bright blue accent called *starlight* (`#8AB4FF`) on every button, link and selection. |
| **Fonts** | **Inter** for everything you read in the interface, **JetBrains Mono** for code and the terminal, **Sora** for headlines. |
| **Wallpaper** | "The Pour" — blurred ribbons of blue and violet pouring diagonally across near-black. |
| **Desktop** | A thin bar across the top (launcher, the app's menus, tray, clock) and a floating dock at the bottom. Desktop icons stack down the right-hand edge. Deliberately Mac-shaped. |

**Everything is a default, never a rule.** If somebody changes their wallpaper or picks a
different colour scheme, their choice is stored in their own home folder and wins — and no
future AquariusOS update will ever stamp over it.

**To change any of it**, read [`branding/README.md`](./branding/README.md) first. It walks
through changing a colour, changing the wallpaper, and where each piece of the design
actually lands inside the OS.

---

## What's different from the stock template

We started from [ublue-os/image-template](https://github.com/ublue-os/image-template) and changed:

1. `image-template.env` → **`aquarius-os.env`**, with our image name, description and keywords
   (the `Justfile`'s first line was updated to match).
2. `Containerfile` — base image set to `ghcr.io/ublue-os/bazzite:stable` (was a
   digest-pinned Bazzite), with plain-language comments added.
3. `build_files/build.sh` — rewritten as a commented Phase 1 / Phase 2 structure.
   Installs `htop` instead of the template's `tmux`; the template's `podman.socket`
   example is now commented out to keep Phase 1 truly minimal.
4. **Added `disk_config/iso.toml`.** The template shipped `iso-kde.toml` and
   `iso-gnome.toml`, but both the `Justfile` and the ISO workflow look for `iso.toml`,
   which didn't exist. Ours is the KDE variant (matching our base), pointed at our image.
5. `.github/workflows/build-disk.yml` — image name hardcoded to `aquarius-os` instead of
   "whatever the repo is called," so a repo rename can't silently break ISO builds.
   Both workflows renamed to say AquariusOS.
6. **Added `branding/`** (placeholder README) and this `README.md` + `GETTING-STARTED.md`.
   The template's original README moved to `docs/UPSTREAM-TEMPLATE-README.md`.
7. `.gitignore` — added macOS/iCloud junk files (this repo lives in an iCloud folder).
8. **Two images from one recipe.** The template builds a single image. `Containerfile` now
   takes its base image as a build argument, `build.yml` runs as a two-entry matrix, and
   `aquarius-os.env` holds both names. The AMD/Intel image is built exactly as before.
9. **A whole visual identity.** `branding/` holds the design; `system_files/` holds the
   copies of it that reach the OS — a KDE colour scheme, a wallpaper package, three
   typefaces, and a "global theme" that sets the desktop layout. `build.sh` gained two font
   packages and a font-index rebuild. All of it applies to both images.

Nothing was removed. All upstream workflows, the `Justfile`, and the build machinery are intact.

---

## Reference

- Upstream template: https://github.com/ublue-os/image-template
- Bazzite custom image guide: https://docs.bazzite.gg/Advanced/creating_custom_image/
- Universal Blue: https://universal-blue.org/
- Universal Blue forums (best place to ask questions): https://universal-blue.discourse.group/
