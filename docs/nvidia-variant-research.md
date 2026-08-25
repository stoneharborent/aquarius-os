# Which Bazzite image the NVIDIA build starts from

*Decided 2026-08-24. Trigger: Royce ordered a PC with an NVIDIA RTX 5090.*

## The decision

`aquarius-os-nvidia` is built on **`ghcr.io/ublue-os/bazzite-nvidia-open:stable`**.

Not `bazzite-nvidia`. The names are one word apart and they are not
interchangeable — picking the wrong one gives a machine that will not display
anything on an RTX card.

## Why, in one paragraph

Bazzite publishes two NVIDIA images because NVIDIA ships two different drivers.
The older one (`-nvidia`, the closed-source "proprietary" driver) stopped getting
support for new cards. The newer one (`-nvidia-open`, built on NVIDIA's *open
kernel modules*) is the only one that supports modern cards. An RTX 5090 is a
"Blackwell" card — about as modern as it gets — so it is `-nvidia-open` or
nothing.

## The evidence

**1. Bazzite's own FAQ says exactly which is which.** From
<https://docs.bazzite.gg/General/FAQ/> (page footer: last updated 23 July 2026),
under *"Are Nvidia graphics card drivers pre-installed?"*:

> The legacy ( -nvidia ) image supports Pascal, Maxwell, and Volta architectures
> (GTX 900, GTX 1000, Nvidia Titan V, GTX 750 (TI) and GTX 745). The modern
> ( -nvidia-open ) image supports every Nvidia card from the Turing architecture
> and newer (GTX 16 and all RTX cards).

"All RTX cards" includes the RTX 5090. The legacy list stops at cards from
roughly 2016–2018.

The same FAQ's image chart lists the desktop line-up we care about:

| Bazzite image | Desktop | Hardware |
|---|---|---|
| `bazzite` | KDE Plasma | AMD / Intel GPUs |
| `bazzite-nvidia` | KDE Plasma | Nvidia GPUs |
| `bazzite-nvidia-open` | KDE Plasma | Nvidia GPUs (Newer Nvidia GPUs) |

`bazzite-nvidia-open` is therefore the NVIDIA equivalent of the image AquariusOS
already uses: same desktop (KDE), same edition (Desktop, not handheld).

**2. The image really exists, is current, and is public.** Checked against the
registry directly on 2026-08-24 (no login, anonymous pull token):

```
ghcr.io/ublue-os/bazzite-nvidia-open:stable
  digest  sha256:d372cf1693b18e1b50a2007288d8b1f01aa6a2d47e94e0148627c7812a679970
  version 44.20260824          (label org.opencontainers.image.version)
  built   2026-08-24T21:31:34Z (label org.opencontainers.image.created)
```

For comparison, `ghcr.io/ublue-os/bazzite:stable` — the image AquariusOS is
already built on — reported version `44.20260824`, built `2026-08-24T21:28:22Z`.
Same Bazzite version, built three minutes apart, so the two AquariusOS variants
stay in step with each other automatically. `stable`, `latest`, `testing` and
`unstable` tags all exist on the NVIDIA-open repo, same as on the plain one.

**3. Bazzite builds and ships ISOs for it themselves.** `bazzite-nvidia-open` is
in the image matrix of `ublue-os/bazzite`'s own `.github/workflows/build_iso.yml`
on `main`, alongside `bazzite` and `bazzite-nvidia`. It is a first-class image,
not a side experiment.

**4. Independent corroboration that RTX 50-series *requires* the open modules.**
NVIDIA's proprietary kernel-module branch does not support Blackwell; open kernel
modules are the only supported path for RTX 50-series on Linux. See
<https://github.com/NVIDIA/open-gpu-kernel-modules> and NVIDIA's own developer
forum thread "RTX 50 Series (Blackwell) GPU Drivers on Linux"
(<https://forums.developer.nvidia.com/t/rtx-50-series-blackwell-gpu-drivers-on-linux/335669>).

## What this does NOT decide

- **Tag.** We track `:stable`, matching what `aquarius-os` already does.
- **Desktop.** KDE, matching `aquarius-os`. There is a
  `bazzite-gnome-nvidia-open` if we ever want GNOME; we don't.
- **Handhelds.** `bazzite-deck-nvidia` exists and is a Phase 4 question, not
  this one.

## Unverified

Nobody has booted `aquarius-os-nvidia` on real NVIDIA hardware yet. Everything
above is about picking the right starting point; whether the resulting image
works on the 5090 is answered by plugging in a USB stick, not by reading docs.
