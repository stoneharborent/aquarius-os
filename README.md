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
   build_files/build.sh       downloads Bazzite                 (a bootable OS image)
   system_files/              runs our build script                      │
   aquarius-os.env            packages up the result                     ▼
                                                                 an .iso you can
        ▲                                                        burn to a USB stick
        │                                                        and install on a PC
   you edit a file
   and `git push`
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

## Repo map

| Path | What it is | Do you touch it? |
|---|---|---|
| `README.md` | This file. | — |
| `GETTING-STARTED.md` | **Click-by-click setup for putting this on GitHub.** Start here. | Read it |
| `Containerfile` | The recipe. Says "start from Bazzite, then run our build script." | Rarely |
| `build_files/build.sh` | **The main file you edit.** Installs packages and makes changes on top of Bazzite. This is where the creator apps will go in Phase 2. | Often |
| `aquarius-os.env` | Settings: the image name (`aquarius-os`), description, GitHub username. One place, used everywhere. | Once, at setup |
| `system_files/` | Anything here gets copied into the OS's filesystem. `system_files/usr/…` becomes `/usr/…` in the running OS. Empty for now. | Phase 3 |
| `branding/` | Staging area for wallpaper, logo, boot splash. Currently a README explaining the plan — no assets yet. | Phase 3 |
| `disk_config/` | Settings for turning the OS image into an installable `.iso` / VM disk. `iso.toml` is the one that's used. | Once, at setup |
| `.github/workflows/build.yml` | The build robot's instructions: build the OS and publish it. Runs on every push + nightly. | No |
| `.github/workflows/build-disk.yml` | The second robot: turns the published OS into a bootable `.iso`. You run this one by hand. | No |
| `Justfile` | A collection of shortcut commands used by the build robot (and usable on a Linux machine). | No |
| `docs/UPSTREAM-TEMPLATE-README.md` | The original README from the upstream template we copied, kept for reference. Written for experts. | Reference |
| `LICENSE` | Apache 2.0, inherited from the upstream template. | No |

Planning docs live one level up: `../ROADMAP.md` is the master plan (phases, decisions).

---

## Current state — Phase 1

This is a **v0.1 scaffold**. It has not been built or booted yet.

What's set up:
- Base image: **Bazzite stable, KDE desktop** (`ghcr.io/ublue-os/bazzite:stable`)
- Image name: **`aquarius-os`** → publishes to `ghcr.io/<your-github-username>/aquarius-os`
- Build layer: installs exactly one package (`htop`) as proof the layer works
- Phase 2 creator apps: **commented-out stubs only** in `build_files/build.sh` — visible, not active

What is *not* done yet (all tracked in `../ROADMAP.md`):
- Nothing has been pushed to GitHub, so nothing has ever been built
- Image signing (cosign) is **not** configured — see GETTING-STARTED, this one matters
- The OS still identifies itself as Bazzite, not AquariusOS (Phase 3 — see `branding/README.md`)
- No ISO has been built yet

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

Nothing was removed. All upstream workflows, the `Justfile`, and the build machinery are intact.

---

## Reference

- Upstream template: https://github.com/ublue-os/image-template
- Bazzite custom image guide: https://docs.bazzite.gg/Advanced/creating_custom_image/
- Universal Blue: https://universal-blue.org/
- Universal Blue forums (best place to ask questions): https://universal-blue.discourse.group/
