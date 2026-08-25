# `installer/` — how the USB stick gets made

**You do not need to read this to use AquariusOS.** It only matters if you are
changing how the installer USB stick works. Everyday OS changes go in
`build_files/build.sh`, not here.

## What this folder is

There are two different things called "AquariusOS":

1. **The OS itself** — built by `Containerfile` in the repo root, published to
   `ghcr.io/stoneharborent/aquarius-os:latest`. This is what ends up on your
   computer's hard drive.
2. **The installer** — a *separate*, throwaway image built from this folder. It
   is a small live desktop with the Fedora installer (Anaconda) on it, and a copy
   of thing #1 tucked inside it. This is what gets written to the USB stick.

This folder builds thing #2. It is usually called the **payload image**, because
it carries the real OS as its payload.

## Why it has to exist

The ISO builder we use, [Titanoboa](https://github.com/ublue-os/titanoboa),
refuses to work unless the image it is given contains a config file at
`/usr/lib/bootc-image-builder/iso.yaml`. Bazzite does *not* put that file in
`bazzite:stable` — it adds it in exactly this kind of separate installer layer,
built moments before its own ISOs. Since AquariusOS is built on `bazzite:stable`,
we had the same hole, and this folder fills it.

## The files

| File | What it does |
|---|---|
| `Containerfile` | Says "start from AquariusOS, then run `build.sh`". |
| `build.sh` | The main script. Embeds the OS image, adds live-boot support, calls the two hooks, copies `iso.yaml` into place. |
| `iso.yaml` | The disc label and the boot menu you see when the USB stick starts. |
| `titanoboa_hook_preinitramfs.sh` | Swaps in a plain signed Fedora kernel so Secure Boot machines will boot the stick. |
| `titanoboa_hook_postrootfs.sh` | Installs the Anaconda installer and writes the "install recipe". Also strips out things that don't belong in a live session. |
| `system_files/shared/` | Files copied into the live image early (installer settings). |
| `system_files/overrides/` | Files copied in last, to overwrite whatever the base image put there. |

## How it gets built

You never build it by hand. `.github/workflows/build-iso.yml` does it:

```
podman build --cap-add sys_admin --security-opt label=disable \
  --build-arg BASE_IMAGE=ghcr.io/stoneharborent/aquarius-os:latest \
  --build-arg INSTALL_IMAGE_PAYLOAD=ghcr.io/stoneharborent/aquarius-os:latest \
  -t localhost/payload:latest installer/
```

…and then hands `localhost/payload:latest` to Titanoboa, which squashes it into
an `.iso`. The odd `--cap-add sys_admin` is required because `build.sh` runs
podman *inside* the build to embed the OS image.

Nothing in this folder is tied to one AquariusOS image. Running the workflow with
**variant = nvidia** simply passes
`ghcr.io/stoneharborent/aquarius-os-nvidia:latest` in both of those `--build-arg`
lines instead, and the same machinery produces the NVIDIA installer. One ISO per
run — you pick which.

## NVIDIA

The `-nvidia` ISO needs two extra things in the live session, both in
`titanoboa_hook_postrootfs.sh` and both guarded by `if [[ $imageref == *-nvidia* ]]`
so they are inert for the normal image:

1. `GSK_RENDERER=gl` — otherwise GTK apps (including the installer's own
   browser window) refuse to open on NVIDIA.
2. Re-enabling **nouveau** and its Vulkan drivers.

Point 2 is the one worth understanding. `titanoboa_hook_preinitramfs.sh` replaces
AquariusOS's kernel with a plain signed Fedora kernel so Secure Boot machines will
boot the USB stick at all — and NVIDIA's real drivers are built against the kernel
that just got removed. So the *installer desktop* runs on nouveau, the open-source
driver. It is slow, and that is fine: it only has to draw an installer. The machine
you end up with runs the proper NVIDIA drivers.

Both blocks are copied from Bazzite, which hits exactly the same problem on its own
NVIDIA ISOs.

## Credit

Everything here is adapted from
[`ublue-os/bazzite` → `installer/`](https://github.com/ublue-os/bazzite/tree/main/installer),
licensed Apache-2.0, read at commit
`0fb3abacb1135fbb50cbb575a18f53fea683ab0f` (23 August 2026). Bazzite in turn
credits [`ondrejbudai/bootc-isos`](https://github.com/ondrejbudai/bootc-isos).
Individual files carry their own attribution comments and note what we changed.

## Known differences from Bazzite, and known rough edges

- **No preinstalled Flatpaks.** Bazzite preloads Flathub apps into the live image
  so the installer can copy them onto the new machine. AquariusOS ships none yet
  (Phase 2), so those steps are gone. Does not affect booting or installing.
- **No Steam Deck variant** (Phase 4), so that special-casing is gone. The NVIDIA
  special-casing *is* kept — see "NVIDIA" below.
- **No cosmetic branding** — Bazzite's custom wallpaper, Conky overlay, KDE panel
  pins, login popups and bootloader-restore tool are not carried over. The live
  session will look like plain Bazzite KDE with an AquariusOS terminal greeting.
- **`bazzite_xboot` is kept on purpose.** AquariusOS inherits Bazzite's boot
  partition layout; the installed system looks for that exact label. Do not
  "clean this up".
- **Signature enforcement is off for updates.** Bazzite runs
  `bootc switch --enforce-container-sigpolicy` after install. We don't, because
  AquariusOS does not yet ship a signing policy for `ghcr.io/stoneharborent`.
  Add the flag back the day that policy ships (see
  `titanoboa_hook_postrootfs.sh`).
