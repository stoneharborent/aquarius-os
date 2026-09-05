# The Bazzite line — what it was, and how to get any of it back

*The record of the first AquariusOS. Nothing here is live; all of it is
recoverable. Assumes no Linux experience.*

---

## The short version

AquariusOS was built twice.

**The first version** (23 August – 2 September 2026) was built on top of
**Bazzite**, a gaming operating system in the Fedora family. It reached a real,
working state: it booted on two machines, it was branded, it had the creator
apps, the ingest helper and a full KDE theme, and later a GNOME line beside it.
It published **six images**.

**The second version** — the one this repository builds now — was started from
scratch on **bare Fedora** on 2 September 2026, because Bazzite had already made
a few thousand decisions for us and most of them were about handheld gaming
consoles. The reasoning is in
[`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md).

On **4 September 2026** the second version took over the names, the branch and
the repository's front page. This page is what the first one left behind.

---

## Where it is

| | |
| --- | --- |
| **Branch** | `bazzite-archive` (it was `main` until 4 September 2026) |
| **Last commit** | `5ec20f3` — *"Bake quickshell and niri into the GNOME images, so Qt can never drift"*, 2 September 2026 |
| **Built by** | `.github/workflows/build.yml` **on that branch** — a different file from the one with the same name on `main`. They are two different operating systems that happen to share a repository. |
| **Still building?** | No. It was a nightly scheduled build, and GitHub only runs scheduled builds on the repository's *default* branch. It stopped by itself the moment `main` became the new line. |

Nothing on `bazzite-archive` is ever edited again. That is the point of an
archive: it is what it was on its last day.

---

## The six images

All six were published to `ghcr.io/stoneharborent/`. Each was built on the
matching Bazzite base image, with the AquariusOS identity, theme, creator apps
and ingest helper layered on top.

| Image | Desktop | Graphics | Built on |
| --- | --- | --- | --- |
| `aquarius-os` | KDE Plasma | AMD / Intel | `ghcr.io/ublue-os/bazzite:stable` |
| `aquarius-os-nvidia` | KDE Plasma | NVIDIA (RTX and newer) | `ghcr.io/ublue-os/bazzite-nvidia-open:stable` |
| `aquarius-os-deck` | KDE Plasma, boots to Game Mode | handhelds | `ghcr.io/ublue-os/bazzite-deck:stable` |
| `aquarius-os-gnome` | GNOME | AMD / Intel | `ghcr.io/ublue-os/bazzite-gnome:stable` |
| `aquarius-os-gnome-nvidia` | GNOME | NVIDIA | `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable` |
| `aquarius-os-gnome-deck` | GNOME, handheld | handhelds | `ghcr.io/ublue-os/bazzite-deck-gnome:stable` |

**The first two names are in use again.** `aquarius-os` and `aquarius-os-nvidia`
now mean the Fedora-based operating system. That is exactly why the next section
exists.

---

## How to get any of them back

Every one of the six was given a permanent tag, **`bazzite-final`**, before the
new line published anything. It points at that image's last build and it will
never be moved or overwritten — the workflow that made it refuses to touch a
`bazzite-final` tag that already exists.

So on any machine that runs an image-based OS:

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-gnome-nvidia:bazzite-final
sudo systemctl reboot
```

…swapping in whichever of the six names you want. Nothing is erased; the current
system stays on the disk and `sudo bootc rollback` comes straight back.

To look at one without installing it:

```bash
skopeo inspect docker://ghcr.io/stoneharborent/aquarius-os-gnome-nvidia:bazzite-final
```

**The tags were made by** the *Archive the Bazzite image tags* workflow
(`.github/workflows/archive-bazzite-tags.yml`), run once by hand on 4 September
2026. It can be run again safely at any time: anything already archived is left
alone. The digests it recorded are in that run's summary, on the Actions tab.

---

## The temporary `-next` images

Between 2 and 4 September 2026 the new line published under two temporary names
so it could not tread on the six above:

| Image | Was |
| --- | --- |
| `aquarius-os-next` | what `aquarius-os` is now |
| `aquarius-os-next-nvidia` | what `aquarius-os-nvidia` is now |

They are frozen at their last build of 4 September 2026 and nothing publishes to
them again. They are not deleted. If you find one of these names in an old note
or screenshot, it means the same operating system, two days younger.

---

## What was kept from the first version

Almost all of the work, because most of it was never Bazzite-specific: the
branding and boot artwork, the theme and colour tokens, the ingest helper (the
"Make Editor-Ready" right-click), the creator-apps chooser, the shape of the CI
pipeline with its read-the-finished-image checks, and every lesson written into
the `docs/` folder. What was left behind was Bazzite itself — its package
sources, its handheld assumptions, its KDE opinions, and the constant work of
undoing them.

---

## Related reading

- **Why we started over:** [`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md)
- **How the names and branches were swapped:** [`final-names.md`](final-names.md)
- **What the current line is and how to read it:** [`README.md`](README.md)
