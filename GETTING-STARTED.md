# Getting started

*How to actually do things with this repository. Assumes no Linux experience.*

> **This page is for the `restart/fedora-bootc` branch** — AquariusOS rebuilt on
> bare Fedora. The `main` branch is the older Bazzite line, frozen, with its own
> (different) instructions. Nothing here is ever merged into `main`.
>
> The previous version of this page walked through setting the GitHub repository
> up from nothing — creating it, adding the signing key, making packages public.
> That was a one-time job and it is done. What is left is the things you actually
> do, which is the list below.

---

## The four things you will ever do

1. [Change something and publish it](#1-change-something-and-publish-it)
2. [Put a new build on a machine](#2-put-a-new-build-on-a-machine)
3. [Make an installer USB stick](#3-make-an-installer-usb-stick)
4. [Work out why a build went red](#4-work-out-why-a-build-went-red)

---

## 1. Change something and publish it

### The loop

1. Edit a file.
2. `git add`, `git commit`, `git push` to `restart/fedora-bootc`.
3. GitHub builds both images, checks them, and publishes them.
4. Watch it at [Actions](https://github.com/stoneharborent/aquarius-os/actions).

Twenty to forty minutes for both images. Nothing is published unless every check
passes.

### Where to make the change

| I want to… | Edit |
| --- | --- |
| Add or remove a program | the right numbered script in `build_files/` |
| Change a desktop default (colours, fonts, dock) | `system_files/usr/share/glib-2.0/schemas/zz1-aquarius-*.gschema.override` |
| Add a file to the finished OS | put it in `system_files/`, in the place it should end up |
| Rename an image, or move to a new Fedora | `aquarius-os.env` |
| Change the order of the build steps | `Containerfile` |

The eight build steps and what each one is for are listed in
[`docs/restart/README.md`](docs/restart/README.md).

### The one habit that matters

**Whatever you change, check it by reading the result back** — not by assuming
the command worked.

Every script in `build_files/` does this and there are helpers for it in
`build_files/aq-lib.sh`. If you add a package, add it to the `aq_installed` list
at the bottom of the same script. If you add a setting, add a `want` line that
asks GNOME what the setting *is* now.

**Never check a timestamp.** The tool that packages a bootable image sets every
file's clock to the same value, so "is this file newer than that one" is always
true, forever, including when the step did nothing. We shipped that bug on
31 August 2026 and it is why this paragraph exists.

---

## 2. Put a new build on a machine

If the machine already runs AquariusOS — which the 4090 bench does — you do not
reinstall anything. One command points it at a different image, and one command
puts it back.

**Run these on the Linux machine, not on the Mac.** `bootc` and `rpm-ostree` are
Linux tools; on macOS they are simply not installed and you get `command not
found`.

First ask the machine which tool it has:

```bash
command -v bootc
```

**If that printed a path:**

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-next-nvidia:latest
sudo systemctl reboot
```

**If it printed nothing** — the older `rpm-ostree` does the same job, and the
`ostree-unverified-registry:` prefix is how you hand it a container image:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/stoneharborent/aquarius-os-next-nvidia:latest
sudo systemctl reboot
```

To go back (the new image always has `bootc`; `sudo rpm-ostree rollback` is the
fallback, and picking the older boot-menu entry works with no command at all):

```bash
sudo bootc rollback
sudo systemctl reboot
```

**The full walkthrough — what to expect, what to check, what to do if the
desktop comes up dark — is [`docs/restart/bench-rebase.md`](docs/restart/bench-rebase.md).**
Read that one, not this summary, the first time.

Use `-next` for an AMD or Intel machine and `-next-nvidia` for anything with an
RTX card.

### Ordinary updates

Once a machine is on the new image it updates itself, and `bootc` is the only
tool you need from then on:

```bash
sudo bootc upgrade
sudo systemctl reboot
```

---

## 3. Make an installer USB stick

Only needed for a machine that does **not** already run AquariusOS. It is built
by hand because an ISO is several gigabytes and takes half an hour.

```bash
git tag iso-nvidia-2026-09-03      # or iso-base-… for an AMD/Intel machine
git push origin iso-nvidia-2026-09-03
```

Then watch [Actions](https://github.com/stoneharborent/aquarius-os/actions),
wait, and download the ISO from **Artifacts** at the bottom of the run's page.
Write it to a USB stick with
[Fedora Media Writer](https://fedoraproject.org/workstation/download/) or
[balenaEtcher](https://etcher.balena.io/), boot the target computer from the
stick, and follow the installer.

### Why a tag, and not the "Run workflow" button

Because the button does not exist yet, and this catches everybody once.

GitHub only shows "Run workflow" for workflows that live on the repository's
**default** branch. Ours is `main` — the frozen Bazzite line — and nothing from
this branch is ever put there. So the button is genuinely absent from the
Actions page, and looking harder does not help.

A tag works because a tag is not a branch: pushing one changes no branch,
touches nothing on `main`, and runs the workflow from the code at that tag,
which is ours. The first part of the tag name (`iso-base-` or `iso-nvidia-`) is
how the workflow knows which image you meant; the rest is yours, and a date is
the obvious thing.

The day this branch becomes the default branch — Phase R3 — the button starts
working on its own, with no change to anything.

⚠️ **Installing erases the disk you point it at.** There is no dual-boot option
in this installer. If the machine has anything on it you want, get it off first.

⚠️ **The image has to be published before you can build an ISO of it.** This
workflow wraps something that already exists on GitHub; it does not build one.

### Artifacts expire

GitHub deletes them after 7 days. Download it when it is fresh, or run the
workflow again.

---

## 4. Work out why a build went red

Click the red run in Actions, then the red job, then the red step. GitHub shows
the log. Every check in this repository is written to say what is wrong and what
to do about it, in English, so start by reading the last few red lines rather
than the whole log.

The common ones:

### "No match for argument: some-package-name"

The package does not exist under that name on Fedora 44. Names change between
releases and between repositories more often than you would expect — the AAC
library is `fdk-aac` on RPM Fusion and `libfdk-aac` somewhere else; Fedora's
`mesa-va-drivers` was folded into `mesa-dri-drivers`.

Check the real name at <https://packages.fedoraproject.org> before changing it.

### "no space left on device"

The build machine ran out of disk. The images are large. There is already a step
that clears space; if it is not enough, something got much bigger and that is
worth understanding rather than working around.

### A check failed with FAIL in the message

That is one of ours and the message says what it expected and what it found.
These are the good failures — they mean the build noticed something before a
person did.

### "unauthorized" or "manifest unknown" when switching a machine

The package on GitHub is private. A newly published image name is private until
somebody makes it public, once:

1. <https://github.com/orgs/stoneharborent/packages>
2. Find the package → Package settings → Danger Zone → **Change visibility** →
   Public

---

## Building on your own machine (optional)

You do not need this — GitHub does it — but if you have a Linux machine with
`podman` and `just`:

```bash
just                # list everything you can do
just build          # the AMD/Intel image
just build aquarius-os-next-nvidia latest 1   # the NVIDIA one
just lint           # check the build scripts for common shell mistakes
```

It will not work on an Apple Silicon Mac. These are x86 images and a Mac can
only emulate x86 very slowly.

---

## Where the important documents are

| Document | What it answers |
| --- | --- |
| [`docs/restart/README.md`](docs/restart/README.md) | What changed in the restart, what R1 builds, how to read the build |
| [`docs/restart/bench-rebase.md`](docs/restart/bench-rebase.md) | Moving the bench machine onto the new line, step by step |
| [`docs/restart/welcome.md`](docs/restart/welcome.md) | What a brand-new person sees at their first login, and how to see it again |
| [`docs/restart/nvidia-notes.md`](docs/restart/nvidia-notes.md) | How the NVIDIA driver is done and why |
| [`docs/base-distro-reassessment-2026-09.md`](docs/base-distro-reassessment-2026-09.md) | Why Fedora, and not Bazzite / Arch / Ubuntu / Enterprise Linux |
| `ROADMAP.md` (one folder above the repo) | What R2, R3 and R4 are |
