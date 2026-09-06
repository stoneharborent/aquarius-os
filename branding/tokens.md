# AquariusOS design tokens — the source of truth

**This file is the law.** Every colour, font and measurement AquariusOS uses is written
down here. If you are theming *anything* — the desktop, an app, a website, a slide, a
YouTube thumbnail about the OS — you read this file first and you copy the values out of
it. You never pick a colour by eye.

**Where the colours come from (changed 2026-09-06, Royce's call):** the Aquarius Desktop
shell's own theme files, `theme/Ice.qml` and `theme/Midnight.qml` in the `aquarius-shell`
repository. Those are what runs on the bench and what Royce approved on screen. This file
records them so that everything else — icons, docs, web pages, the GNOME fallback — uses
the same values. **If this file and the shell ever disagree, the shell wins**, and whoever
notices updates this file in the same sitting.

Before 2026-09-06 the colours here came from the Claude Design project "AquariusOS Core
Identity" (the *Starlight* palette: `#8AB4FF` / `#5B4BE0` / `#E6DDB8`). That palette is
retired for the desktop. The design project and the `design-system/` mirror next to this
file still carry it and need re-syncing — see the note at the end of the colour section.

---

## How to read this file (plain English)

A "token" is just a named value. Instead of writing `#8AB4FF` in fifty places, we call it
`starlight` and write that. When the blue ever changes, it changes once.

Colours are written as **hex codes** (`#8AB4FF`) — the standard six-character way computers
name colours — or as **rgba(...)** when the colour needs to be see-through. In `rgba`, the
last number is opacity: `1` is solid, `0` is invisible, `.08` is barely there.

---

## Colours — Ice (the default, light)

AquariusOS is **Ice light-first** (decided 2026-09-02). Ice is the palette a new machine
boots into; Midnight is its dark mode. The names below are the shell's own names, so a
value in this file and a value in `Ice.qml` are always called the same thing.

### Grounds — the layers of the room

| Token | Hex | What it's for |
|---|---|---|
| `bg` | `#EAF1F8` | **The desktop and window background.** A blue-tinted white, never pure white. |
| `bgSoft` | `#DFEAF4` | Slightly recessed areas — a sidebar well, a list's gutter. |
| `surface` | `#F7FBFE` | Cards, menus and popups — the brightest paper. |
| `surfaceAlt` | `#E4EDF6` | Secondary cards; the lower half of an app-icon plate. |
| `panel` | `#F0F6FC` | Chrome — **the top bar**, a window's title bar. |
| `dockSurface` | `#E3ECF5` | The dock slab. |

### Ink — text and glyphs

| Token | Hex | What it's for |
|---|---|---|
| `ink` | `#16273A` | Primary text and line glyphs. Deep navy, not black. |
| `inkProse` | `#0E1B2A` | Long-form reading text — deeper still. |
| `inkSoft` | `#47586B` | Secondary text. Labels, captions, "last updated" lines. |
| `inkMute` | `#7C90A4` | Tertiary and disabled text; the greyed window lights. |
| `inkOnAccent` | `#FFFFFF` | Text and glyphs sitting *on* the accent. |

### Lines and washes (ink at a percentage)

| Token | Value | What it's for |
|---|---|---|
| `line` | `ink` at 10% | The default hairline between things. |
| `lineStrong` | `ink` at 18% | A stronger edge — a focused window, a menu card's border, an icon plate's ring. |
| `hoverWash` | `ink` at 8% | The pill behind a hovered row. |
| `pressWash` | `ink` at 13% | The same pill at the moment of the click. |
| `scrim` | `ink` at 35% | The dim behind a dialog. |

### Accents — the Aquarius blue and its family

| Token | Hex | What it's for |
|---|---|---|
| `aquariusBlue` | `#2C8FC4` | **THE accent.** Buttons, links, selection, focus rings, the running dot under a dock icon. Also called `accent`. |
| `accentWash` | `aquariusBlue` at 16% | The wash behind a selected row or a lit toggle. |
| `indigo` | `#6E2BE0` | Support. The far end of the working-line gradient (`aquariusBlue → indigo`), depth. Never a button on its own. |
| `turquoise` | `#0E9AA0` | Support, rare. |
| `aquamarine` | `#12A07C` | Support, rare. |
| `starred` | `#C28B22` | **The gold. Rare on purpose** — one highlight per screen, one gold thing per icon (a playhead, a nib, a rising sun). Twice on one surface is wrong. |

### Status

| Token | Hex | What it's for |
|---|---|---|
| `success` | `#1F9E8C` | Done, saved, connected, verified. Also the green window light. |
| `warn` | `#C2792E` | Careful, unsaved, degraded. Also the amber window light. |
| `danger` | `#C8463B` | Failed, destructive, disconnected. Also the red window light and a destructive menu row. |

### The working line (gradient)

| Token | Value | What it's for |
|---|---|---|
| `line-gradient` | `linear-gradient(90deg,#2C8FC4,#6E2BE0)` | `aquariusBlue` into `indigo`, left to right. Every app-icon glyph is drawn in it; the mark's "A" too. |

---

## Colours — Midnight (dark mode)

Midnight is not black. It is the same room after dark: deep-ocean navy grounds, ice-blue
ink, and the accent turned up so it still reads.

| Token | Midnight value | Note |
|---|---|---|
| `bg` | `#0B1220` | Deep-ocean navy. |
| `bgSoft` | `#111A2B` | Also the dock slab (`dockSurface`). |
| `surface` | `#121C2E` | Cards, menus, popups. |
| `surfaceAlt` | `#1B2940` | Secondary cards; the top of an app-icon plate. |
| `panel` | `#152033` | The top bar, a title bar. |
| `ink` | `#DCE9F4` | Ice-blue text. `inkProse` is the same value — Midnight has no deeper prose ink. |
| `inkSoft` | `#93A7BC` | |
| `inkMute` | `#5C6E82` | |
| `inkOnAccent` | `#08121E` | Near-black on the bright accent. |
| `line` | `#DCF3FF` at 8% | Ice-blue hairline. |
| `lineStrong` | `#DCF3FF` at 16% | |
| `hoverWash` / `pressWash` | `ink` at 8% / 13% | |
| `scrim` | `bg` at 60% | |
| `aquariusBlue` | `#00BFFF` | Deep Sky Blue. Brighter than Ice's so it carries on navy. |
| `accentWash` | `aquariusBlue` at 12% | |
| `indigo` | `#9B82FF` | |
| `turquoise` | `#40E0D0` | |
| `aquamarine` | `#7FFFD4` | |
| `starred` | `#E6B947` | The gold, brightened for the dark. |
| `success` / `warn` / `danger` | `#5FC9B0` / `#E0A35A` / `#E07B7B` | |
| `line-gradient` | `linear-gradient(90deg,#00BFFF,#9B82FF)` | |

### If you are holding an older name

The retired Starlight palette used different names. They map like this, and nothing new
should use the left-hand column:

| Old name | Now |
|---|---|
| `void` / `surface-1` / `surface-2` / `surface-3` | `bg` / `surface` / `surfaceAlt` / `panel` (choose by role, not by number) |
| `starlight` (`#8AB4FF` dark, `#3D63D6` light) | `aquariusBlue` |
| `nebula` | `indigo` |
| `ancient` | `starred` |
| `text-1` / `text-2` / `text-3` | `ink` / `inkSoft` / `inkMute` |
| `border-1` / `border-2` | `line` / `lineStrong` |
| `on-accent` | `inkOnAccent` |
| `selection` | `accentWash` |
| `grad-play` | `line-gradient` |
| `warning` | `warn` |

> **Done, 2026-09-06 (later the same day).** Everything the note here used to list as
> "still on the old palette" has been moved onto the shell's colours: the mark itself
> (`logo.svg` and its three companions), the About-page logo PNGs, the Plymouth boot assets,
> the wallpaper "The Pour", and `ANSI_COLOR` in `/etc/os-release`. The boot mark and the
> icon set's mark are now the same drawing in the same colours.
>
> **One thing is still stale:** the `design-system/` mirror next to this file, including its
> `tokens/colors.css`. That folder is re-synced from the Claude Design project, not edited
> here — see its own README. Nothing in this repository should read colours out of it.

---

## Typography

Three typefaces, all open-source, all free to ship in the OS.

| Role | Font | Weights used | Notes |
|---|---|---|---|
| **Display** | **Sora** | 700 hero/display, 600 titles & headings | Hero text gets `-0.02em` letter-spacing (slightly tightened). Not packaged by Fedora — the OS ships the font files itself. |
| **Body / UI** | **Inter** | 400, 500, 600 | The desktop's interface font. Everything you read in a menu, button or dialog. |
| **Mono** | **JetBrains Mono** | 400, 500 | Code, the terminal, and small uppercase labels. |

### Type scale

| Use | Size | Line height | Extra |
|---|---|---|---|
| UI text (buttons, menus, labels) | 13.5px | — | Inter. On the KDE desktop this is set as **10pt**, which is the closest clean match. |
| Body copy | 15px | 1.6 | Inter |
| Mono label | 11px | — | JetBrains Mono, UPPERCASE, `+0.14em` letter-spacing |
| Hero / display | large | — | Sora 700, `-0.02em` letter-spacing |

> **Why 10pt on the desktop:** KDE measures fonts in points, not pixels. At the standard
> 96 dots-per-inch, 10pt ≈ 13.3px and 11pt ≈ 14.7px. 13.5px sits between them, and 10pt is
> the closer, denser, more "pro tool" of the two. That is the one we ship.

---

## Spacing

One scale, in pixels. Use these numbers and no others:

**4 · 8 · 12 · 16 · 24 · 32 · 48 · 64**

---

## Corner radius

| Value | Used on |
|---|---|
| `7px` | Inputs — text fields, search boxes |
| `9px` | Buttons |
| `12px` | Cards |
| `16px` | Panels and windows |

---

## Shadows and glow

| Token | Value | Used on |
|---|---|---|
| card shadow | `0 12px 40px rgba(0,0,0,.45)` | Cards, raised panels |
| pop shadow | `0 24px 80px rgba(0,0,0,.6)` | Modals, popovers, the floating dock |
| accent glow | `0 0 24px` of `aquariusBlue` at 25% — `rgba(44,143,196,.25)` on Ice, `rgba(0,191,255,.25)` on Midnight | Focus, "this is live", the active item |
| panel blur | `18px` | The frosted-glass effect behind translucent panels |

---

## Motion

| Token | Value |
|---|---|
| easing | `cubic-bezier(.22,1,.36,1)` |
| fast | `120ms` — hovers, small state flips |
| medium | `220ms` — panels opening, things moving across the screen |

Nothing in AquariusOS should animate for longer than 220ms without a very good reason.
The feeling is *quick and calm*, not bouncy.

---

## The logo

Four files live in this folder. All are 64×64 and scale to any size without going blurry.

| File | Use it when |
|---|---|
| `logo.svg` | You want the real mark, in colour, on a light background. **Same drawing as `logo-ice.svg`** — this is just the name the rest of the repo already asks for. |
| `logo-ice.svg` | The Ice colourway, under its honest name. The "A" runs `aquariusBlue → indigo` (`#2C8FC4 → #6E2BE0`, the `line-gradient`); the wave runs `starred → aquariusBlue` (`#C28B22 → #2C8FC4`). |
| `logo-midnight.svg` | The Midnight colourway, for a dark background. Same two gradients at their Midnight values: `#00BFFF → #9B82FF` and `#E6B947 → #00BFFF`. |
| `logo-mono.svg` | You need one flat colour — a taskbar icon, a stamp, a watermark. It is drawn with `currentColor`, meaning **it takes on whatever text colour surrounds it**. |

**Pick by the background, not by the mood.** Ice on anything pale, Midnight on anything
dark. Never put the Ice mark on a dark panel "because it is the default" — its blue is
chosen to read against paper and it goes muddy on navy, and the reverse is true too.

### The apex — one clean point

**Royce's rule, set 2026-09-06.** The "A" is three straight moves and nothing else:

```
M14 54 L32 12 L50 54
```

Up the left leg, one point at the top, down the right leg. The point is at `x=32`, which is
the exact middle of the 64-wide grid, so the letter is symmetrical.

The drawing before this wrote the apex as a little curve — `M14 54 30 12 q1.4-3.6 4 0 L50 54`
— which put the peak slightly left of centre and read as a wobble at small sizes. **That
curve is retired.** If you find it anywhere, it is a stale copy. Nothing new draws it, and
the one function that draws the mark in code (`markPaths()` in `branding/icons/icons.mjs`)
was changed in the same sitting so the icons and the logo can never disagree about it.

Everything else about the mark is unchanged — the same leg positions, the same 5-unit
stroke, the same round caps, the same wave.

### The wave — one shape, everywhere

**Royce's rule, set 2026-09-06.** The logo's wave is drawn by exactly one path:

```
M20 40 q6-6 12 0 t12 0
```

In plain words: two humps side by side, each 12 units wide, and each rising 6 units — the
rise is always half the width of a hump. That proportion *is* the wave.

**Every wave anywhere in AquariusOS keeps that shape.** App icons, shell glyphs, wallpaper
details, slides, thumbnails, marketing — if it has a wave, it is this path, made bigger or
smaller as a whole and moved into place. Never:

- a third hump (or a single one),
- a taller or flatter rise than half the hump width,
- a wave drawn by eye that "looks about right".

If you are writing code, do not paste the numbers: write one small function that takes the
left end, the height and the hump width and returns the path, and call it. The app icons do
exactly this (the Editor and Writer icons carry the wave at 1.5× — humps 18 wide, rising 9).

---

## The wallpaper — "The Pour"

Two sources, one per theme: `wallpapers/the-pour-ice.svg` and
`wallpapers/the-pour-midnight.svg`. The rendered copies ship at
`system_files/usr/share/backgrounds/aquarius/`, one 4K picture each.

Ribbons of `aquariusBlue` and `indigo` pouring diagonally across the theme's `bg`, with one
thin `starred` gold thread. Everything is heavily blurred; nothing has a hard edge. The two
files are the same composition under two lights, not two different pictures.

`wallpapers/the-pour.svg` is the original, from the retired KDE line. Nothing installs it;
it is kept because it is the parent of the two above.

To change it: edit both SVGs, run `bash branding/render-wallpaper.sh gnome`, then commit the
SVGs and the PNGs it produced.

---

## Copy-paste block (CSS)

For any web page, dashboard or HTML artifact about AquariusOS. Ice is the default; add
`data-theme="midnight"` on the root for dark.

```css
:root{
  --bg:#EAF1F8;
  --bg-soft:#DFEAF4;
  --surface:#F7FBFE;
  --surface-alt:#E4EDF6;
  --panel:#F0F6FC;
  --dock:#E3ECF5;
  --ink:#16273A;
  --ink-prose:#0E1B2A;
  --ink-soft:#47586B;
  --ink-mute:#7C90A4;
  --ink-on-accent:#FFFFFF;
  --line:rgba(22,39,58,.10);
  --line-strong:rgba(22,39,58,.18);
  --hover-wash:rgba(22,39,58,.08);
  --press-wash:rgba(22,39,58,.13);
  --scrim:rgba(22,39,58,.35);
  --accent:#2C8FC4;
  --accent-wash:rgba(44,143,196,.16);
  --indigo:#6E2BE0;
  --turquoise:#0E9AA0;
  --aquamarine:#12A07C;
  --starred:#C28B22;
  --success:#1F9E8C;
  --warn:#C2792E;
  --danger:#C8463B;
  --line-gradient:linear-gradient(90deg,#2C8FC4,#6E2BE0);
}
[data-theme="midnight"]{
  --bg:#0B1220;
  --bg-soft:#111A2B;
  --surface:#121C2E;
  --surface-alt:#1B2940;
  --panel:#152033;
  --dock:#111A2B;
  --ink:#DCE9F4;
  --ink-prose:#DCE9F4;
  --ink-soft:#93A7BC;
  --ink-mute:#5C6E82;
  --ink-on-accent:#08121E;
  --line:rgba(220,243,255,.08);
  --line-strong:rgba(220,243,255,.16);
  --hover-wash:rgba(220,233,244,.08);
  --press-wash:rgba(220,233,244,.13);
  --scrim:rgba(11,18,32,.60);
  --accent:#00BFFF;
  --accent-wash:rgba(0,191,255,.12);
  --indigo:#9B82FF;
  --turquoise:#40E0D0;
  --aquamarine:#7FFFD4;
  --starred:#E6B947;
  --success:#5FC9B0;
  --warn:#E0A35A;
  --danger:#E07B7B;
  --line-gradient:linear-gradient(90deg,#00BFFF,#9B82FF);
}
```

---


## Where these tokens actually land in the OS

| Token | Ends up as |
|---|---|
| The whole palette, both themes | `theme/Ice.qml` and `theme/Midnight.qml` in the shell — the origin, not a copy |
| `aquariusBlue` | The GNOME fallback's accent is `'blue'`, the nearest of GNOME's nine fixed words (GNOME does not take a hex value) |
| The palette, in the app icons | `branding/icons/icons.mjs` → the `Aquarius-Ice` and `Aquarius-Midnight` icon themes |
| Inter | The desktop's general font |
| JetBrains Mono | The desktop's fixed-width font |
| Sora | The display face — headings, the wordmark, the "DR" letters in the Resolve icons |
| The Pour | `/usr/share/backgrounds/aquarius/` and the default background, one picture per theme |

The files that do that live in `../system_files/`. See `README.md` in this folder for how
that works.
