# Desktop identity — the pointer, the icons and the sounds

*Phase R5 polish. Written 2026-09-05.*
*Updated 2026-09-06: the app icons are now ours. Everything else stands.*

> **⚠️ WHAT CHANGED ON 2026-09-06, BEFORE YOU READ THE REST.** This page was
> written to explain why AquariusOS pointed at *other people's* themes for the
> pointer, the icons and the sounds, and it left a marked seam for our own
> artwork later. **The icon seam is now closed.** AquariusOS ships its own app
> icons — `Aquarius-Ice` (the default) and `Aquarius-Midnight` — drawn in
> `branding/icons/` and documented in
> [`branding/icons/README.md`](../../branding/icons/README.md).
>
> It is a *narrow* set on purpose: **nine icons**, the ones Royce looks at every
> day, and both themes say `Inherits=Adwaita,hicolor`, so every other icon on the
> machine still comes from GNOME. So the reasoning below about not drawing a
> whole icon set is still exactly right — we did not draw one.
>
> The pointer is still Adwaita and the sounds are still freedesktop. Those two
> seams are still open, and everything this page says about them still holds.

## The one-paragraph version

AquariusOS now sets three more pieces of its look on a brand-new machine: the
**mouse pointer** (cursor theme), the **app icons** (icon theme) and the
**system sounds** (the log-in chime, the notification ping, the error bleep).
All three are set to themes that already ship with Fedora and are kept up to
date by other people — **Adwaita** for the pointer and the icons, **freedesktop**
for the sounds. AquariusOS does **not** draw its own set of any of these yet.
That is a deliberate choice, not a gap, and there is a clearly marked seam so
real Aquarius artwork can drop in later by changing one line each.

## Why we did not draw our own

Drawing a cursor set, an icon set or a sound set is a real art project, not a
build task:

- A **cursor theme** is dozens of little pictures — an arrow, a hand, a text
  bar, a dozen kinds of "busy" spinner — each drawn at several sizes.
- An **icon theme** is *hundreds* of pictures, one for every kind of file and
  every app, and it has to keep up as apps come and go.
- A **sound theme** is a small set of composed audio cues that have to sit
  together and not grate after the tenth time you hear them.

A half-finished set of any of these looks worse than a good, complete existing
one — you get a nice custom arrow and then a stock hand the moment you hover a
link, or a beautiful folder icon next to a generic grey square for every app we
did not draw. So the decision (which is the same decision the rest of the
desktop makes — see [`README.md`](README.md), "The rules that do not move") is:
**work with GNOME's grain.** Pick the best existing, packaged, well-kept theme,
set it as the default, and leave the door open for our own artwork later.

## What ships, and why each one

| Piece | Theme | Package | Why this one |
|---|---|---|---|
| Mouse pointer | **Adwaita** | `adwaita-cursor-theme` | GNOME's own pointer: clean, neutral, already in the image, and already the pointer the **login screen** uses — so the pointer does not change shape the instant you log in. |
| App icons | **`Aquarius-Ice`** (ours, since 2026-09-06) | built in this repo, from `branding/icons/` | Our own nine app icons, light set — AquariusOS is light-first. Everything we do not draw falls through to `adwaita-icon-theme`, which is still installed and still where the other several thousand icons come from. The dark twin `Aquarius-Midnight` is built and installed beside it; nothing selects it yet (see below). |
| System sounds | **freedesktop** | `sound-theme-freedesktop` | The standard, complete cross-desktop sound set. Safe, familiar, nothing missing. |

The pointer size is set to **24**, GNOME's own default (in "logical" pixels). On
the 4K bench the desktop scale makes the pointer the right physical size on its
own; this number is the sane fallback that GDM and the odd app which reads it
directly use.

### The alternatives we looked at, and passed on for now

- **Bibata** (a popular rounded cursor set). Nice, but it is only in a COPR
  (a third-party add-on repository), and this project does not pull cursor art
  from a COPR. Ruled out by that alone. If it ever lands in Fedora proper, it
  becomes a candidate.
- **Papirus** (`papirus-icon-theme`, a fuller icon set many creator distros
  ship). It *is* in Fedora and it covers more third-party apps than Adwaita, so
  fewer apps show a generic icon. We passed on it for the default because
  Adwaita keeps the desktop coherent with GNOME and is zero-maintenance, but it
  is the obvious swap if Royce ever wants fuller app-icon coverage — see below.

## Where these are set

Two places, on purpose kept in step with each other:

1. **The desktop session** (every normal login) —
   `system_files/usr/share/glib-2.0/schemas/zz1-aquarius-10-look.gschema.override`,
   in the `[org.gnome.desktop.interface]` group (cursor and icons) and the
   `[org.gnome.desktop.sound]` group (sounds).
2. **The login screen** (GDM, before you log in) —
   `build_files/50-aquarius-desktop.sh`, which writes
   `/etc/dconf/db/gdm.d/02-aquarius-look`. It sets the same Adwaita cursor and
   the same `Aquarius-Ice` icons, so the login screen and the desktop match and
   nothing visibly changes the instant you log in. (The greeter does not play
   event sounds, so there is no sound line there.)

The icons themselves are checked by their own build step,
`build_files/56-aquarius-icons.sh`, and by `tests/test-aquarius-icons.sh` before
a build even starts.

Both are **defaults**, not locks. The moment a person picks a different pointer,
icon set or sound theme, their choice is written into their own settings and
wins over these forever after. Nothing here is forced on anybody.

The packages are installed in `build_files/40-gnome-desktop.sh`.

## How a user changes them

Everything here is a normal GNOME setting, so a person can change it without
touching the system:

- **Sounds on or off:** Settings → Sound → *System Sounds* toggle. Or from a
  terminal: `gsettings set org.gnome.desktop.sound event-sounds false`.
- **A different pointer or icon set:** install one (from Software, or a
  Flatpak, or by dropping a theme folder into `~/.icons` or
  `~/.local/share/icons`), then pick it in **GNOME Tweaks → Appearance**
  (Tweaks is already on the machine). GNOME's own Settings app does not expose a
  cursor/icon picker; Tweaks is the standard place.

## The seam — dropping in real Aquarius artwork later

This is the whole point of naming the themes explicitly rather than leaving them
at Fedora's unstated default. When Aquarius cursor / icon / sound artwork
exists, it lands like this — and each is a **one-line** change:

### A real Aquarius cursor theme

1. Ship the cursor folder in the image at
   `/usr/share/icons/Aquarius/cursors/` (a folder of cursor files plus an
   `index.theme` that names the theme "Aquarius"). The natural home is a new
   `system_files/usr/share/icons/Aquarius/` tree, or a build step in
   `build_files/`.
2. Change **one line** in `zz1-aquarius-10-look.gschema.override`:
   `cursor-theme='Aquarius'` — and the matching line in
   `build_files/50-aquarius-desktop.sh`'s `02-aquarius-look` so the login screen
   follows.
3. Update the CI read-back and folder checks in `.github/workflows/build.yml`
   (search for `cursor-theme`) to expect `'Aquarius'` and
   `/usr/share/icons/Aquarius`.

### A real Aquarius icon theme — ✅ **done, 2026-09-06**

This is what actually happened, kept here as the worked example for the two
seams still open above.

Two themes ship at `/usr/share/icons/Aquarius-Ice/` and
`/usr/share/icons/Aquarius-Midnight/`. Each has an `index.theme` saying
`Inherits=Adwaita,hicolor`, so it only has to draw the icons it wants to change —
which is nine (twelve files: Files, Settings and the Console are each filed under
GNOME's name and ours). `icon-theme='Aquarius-Ice'` is set in the same two files as
everything else on this page, and CI expects it.

The drawings live in `branding/icons/` and are rebuilt with
`bash branding/render-app-icons.sh`. Read
[`branding/icons/README.md`](../../branding/icons/README.md) before touching any
of it.

**⚠️ TODO — not this repo's job: nothing switches to Midnight yet.** The dark
set is built, installed and checked, and nothing ever selects it. Following the
desktop's light/dark setting is the *shell's* job (the aquarius-shell repository
already watches the colour scheme), so: **when the shell switches the colour
scheme to dark it should set `org.gnome.desktop.interface icon-theme` to
`'Aquarius-Midnight'`, and back to `'Aquarius-Ice'` when it goes light.** Both
themes are already in the image, so that is a one-setting change with no image
work behind it. Until it lands, a person switches by hand:

```bash
gsettings set org.gnome.desktop.interface icon-theme 'Aquarius-Midnight'
```

### A real Aquarius sound theme

1. Ship the sounds at **`/usr/share/sounds/aquarius/`** — a folder of audio
   files (the standard is `.oga`/Ogg Vorbis) plus an `index.theme` naming the
   theme "aquarius". The freedesktop sound-naming spec lists the standard event
   names (`bell`, `message`, `device-added`, and so on).
2. Change **one line** in `zz1-aquarius-10-look.gschema.override`:
   `theme-name='aquarius'`.
3. Update the CI read-back and folder checks in `.github/workflows/build.yml`
   (search for `theme-name` and `/usr/share/sounds/freedesktop`).

### To fall back to Papirus instead (no new artwork needed)

Kept for the record. If Royce ever wants fuller *third-party* app-icon coverage
and is willing to give up our own eight:

1. Add `papirus-icon-theme` to the install list in
   `build_files/40-gnome-desktop.sh`.
2. Set `icon-theme='Papirus'` in `zz1-aquarius-10-look.gschema.override` and in
   `build_files/50-aquarius-desktop.sh`'s `02-aquarius-look`.
3. Update the CI checks in `.github/workflows/build.yml` to expect `'Papirus'`,
   the package `papirus-icon-theme`, and the folder `/usr/share/icons/Papirus`.

A better answer, if this ever comes up, is to set `Inherits=Papirus,Adwaita,hicolor`
in our own two `index.theme` files instead — that keeps the Aquarius icons and
gets Papirus's coverage underneath them.

## How CI proves it

The **"Check the desktop comes up as Ice-light AquariusOS"** step in
`.github/workflows/build.yml` reads the *finished image* and checks:

- `gsettings` reports `cursor-theme='Adwaita'`, `cursor-size=24`,
  `icon-theme='Aquarius-Ice'`, `sound theme-name='freedesktop'` and
  `sound event-sounds=true` — the exact values a new account gets;
- the packages `adwaita-cursor-theme`, `adwaita-icon-theme` and
  `sound-theme-freedesktop` are installed (`rpm -q`) — Adwaita's icons still
  matter, because our themes inherit from them;
- the folders those settings point at really exist:
  `/usr/share/icons/Adwaita`, `/usr/share/icons/Adwaita/cursors`,
  `/usr/share/icons/Aquarius-Ice`, `/usr/share/icons/Aquarius-Midnight`,
  `/usr/share/sounds/freedesktop`.

The icons get a check of their own on top of that — every icon, in both themes,
at all eight sizes, read back from the PNG's own header rather than assumed. See
the **"Check the Aquarius app icons"** step, and
`build_files/56-aquarius-icons.sh` which does the same inside the build.

`build_files/40-gnome-desktop.sh` checks the same packages and folders at build
time as well, so a missing theme fails the build before the image is even
assembled.

## Bench check for Royce

After rebasing the bench to an image built from this branch:

1. **Log in.** The mouse pointer should be the clean GNOME arrow — the same one
   you saw on the login screen, with no flicker or change of shape as the
   desktop appears.
2. **Look at the app grid and Files.** The icons should be the standard
   coherent GNOME (Adwaita) set — no generic grey squares for the built-in apps.
3. **Trigger a sound.** Plug in a USB drive, or let a notification arrive — you
   should hear the standard freedesktop cue. If you would rather have silence,
   Settings → Sound → *System Sounds* off, and it stays off.

Nothing here should look dramatic — that is the point. It should look
*intentional and finished* rather than like leftover Fedora defaults, and it
should match the login screen you just came through.
