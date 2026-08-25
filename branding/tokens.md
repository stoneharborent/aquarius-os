# AquariusOS design tokens — the source of truth

**This file is the law.** Every colour, font and measurement AquariusOS uses is written
down here. If you are theming *anything* — the desktop, an app, a website, a slide, a
YouTube thumbnail about the OS — you read this file first and you copy the values out of
it. You never pick a colour by eye.

**Where the design comes from:** the Claude Design project **"AquariusOS Core Identity"**,
direction **"Flow State"**. That project is where the look is *decided*. This file is where
the decision is *recorded* so that code can use it.

**If they ever disagree, the design project wins** — and whoever notices should update this
file to match, in the same sitting.

---

## How to read this file (plain English)

A "token" is just a named value. Instead of writing `#8AB4FF` in fifty places, we call it
`starlight` and write that. When the blue ever changes, it changes once.

Colours are written as **hex codes** (`#8AB4FF`) — the standard six-character way computers
name colours — or as **rgba(...)** when the colour needs to be see-through. In `rgba`, the
last number is opacity: `1` is solid, `0` is invisible, `.08` is barely there.

---

## Colours — dark theme (the default)

AquariusOS is **dark first**. The dark palette is the real design; light is derived from it.

### Backgrounds — the layers of the room

| Token | Hex | What it's for |
|---|---|---|
| `oled` | `#000000` | True black. Only for OLED-panel power saving and full-screen media. Not a UI colour. |
| `void` | `#06070C` | **The desktop and app background.** The deepest normal surface. |
| `surface-1` | `#10121C` | Cards and panels sitting on the void. |
| `surface-2` | `#161A29` | Raised things — popovers, menus, dropdowns. |
| `surface-3` | `#1D2236` | The highest layer. Tooltips, and the top of a stack of stacked things. |

### Lines

| Token | Value | What it's for |
|---|---|---|
| `border-1` | `rgba(237,239,247,.08)` | The default hairline between things. Deliberately almost invisible. |
| `border-2` | `rgba(237,239,247,.14)` | A stronger line — focused inputs, the edge of something active. |

### Accents — the AquariusOS blue

| Token | Hex | What it's for |
|---|---|---|
| `starlight` | `#8AB4FF` | **THE hero accent.** Buttons, links, selection, focus rings. This exact value is the KDE Plasma accent colour on the desktop. |
| `starlight-hover` | `#A8C6FF` | The same blue when the mouse is over it. |
| `starlight-press` | `#6E9BF2` | The same blue at the moment of the click. |
| `nebula` | `#5B4BE0` | Support purple. Depth, gradients, the far end of the wallpaper pour. Never a button colour on its own. |
| `ancient` | `#E6DDB8` | Support gold. **Rare on purpose** — a single highlight, a thin thread, one badge. If you are using it twice on one screen you are using it wrong. |
| `on-accent` | `#080B14` | The text/icon colour that goes *on top of* `starlight`. Near-black, because the blue is bright. |

### Text

| Token | Hex | What it's for |
|---|---|---|
| `text-1` | `#EDEFF7` | Primary text. Headings, body, anything you must read. |
| `text-2` | `#8A90A6` | Secondary text. Labels, captions, "last updated" lines. |
| `text-3` | `#565C72` | Tertiary text. Disabled items, placeholder text, dividers-as-text. |

### Status

| Token | Hex | What it's for |
|---|---|---|
| `success` | `#55D6A5` | Done, saved, connected, verified. |
| `warning` | `#E6C069` | Careful, unsaved, degraded. |
| `danger` | `#FF7A85` | Failed, destructive, disconnected. |

### Selection

| Token | Value | What it's for |
|---|---|---|
| `selection` | `rgba(138,180,255,.16)` | The wash behind selected text and selected rows. It is `starlight` at 16%. |

### Gradients

| Token | Value | What it's for |
|---|---|---|
| `grad-play` | `linear-gradient(90deg,#8AB4FF,#5B4BE0)` | Starlight into nebula, left to right. The signature gradient — the logo uses it, the wallpaper uses it. |

---

## Colours — light theme (derived)

Light is not a separate design. It is the dark palette re-grounded: backgrounds go pale,
and the accent **deepens** so it still passes contrast against white.

| Token | Light value |
|---|---|
| background (`void` equivalent) | `#EEF0F7` |
| `surface-1` | `#F7F8FC` |
| `surface-2` | `#FFFFFF` |
| `starlight` | `#3D63D6` |
| `starlight-hover` | `#2E52C4` |
| `starlight-press` | `#2545AD` |
| `nebula` | `#4A3BC9` |
| `ancient` | `#8A7B3D` |
| `on-accent` | `#FFFFFF` |
| `text-1` | `#141726` |
| `text-2` | `#565C72` |
| `text-3` | `#8A90A6` |
| `border-1` | `rgba(20,23,38,.10)` |
| `border-2` | `rgba(20,23,38,.16)` |
| `selection` | `rgba(61,99,214,.14)` |

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
| accent glow | `0 0 24px rgba(138,180,255,.25)` | Focus, "this is live", the active item |
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

Two files live in this folder:

| File | Use it when |
|---|---|
| `logo.svg` | You want the real mark, in colour. Uses the `grad-play` gradient plus a gold-to-blue sweep on the wave. |
| `logo-mono.svg` | You need one flat colour — a taskbar icon, a stamp, a watermark. It is drawn with `currentColor`, meaning **it takes on whatever text colour surrounds it**. |

Both are 64×64 and scale to any size without going blurry.

---

## The wallpaper — "The Pour"

Source: `wallpapers/the-pour.svg`. Rendered copies ship at
`system_files/usr/share/wallpapers/AquariusThePour/`.

Ribbons of `starlight` and `nebula` pouring diagonally across the `void`, with one thin
`ancient` gold thread. Everything is heavily blurred; nothing has a hard edge.

To change it: edit the SVG, then run `bash branding/render-wallpaper.sh`, then commit both
the SVG and the PNGs it produced.

---

## Copy-paste block (CSS)

For any web page, dashboard or HTML artifact about AquariusOS:

```css
:root{
  --oled:#000000;
  --void:#06070C;
  --surface-1:#10121C;
  --surface-2:#161A29;
  --surface-3:#1D2236;
  --border-1:rgba(237,239,247,.08);
  --border-2:rgba(237,239,247,.14);
  --starlight:#8AB4FF;
  --starlight-hover:#A8C6FF;
  --starlight-press:#6E9BF2;
  --nebula:#5B4BE0;
  --ancient:#E6DDB8;
  --on-accent:#080B14;
  --text-1:#EDEFF7;
  --text-2:#8A90A6;
  --text-3:#565C72;
  --success:#55D6A5;
  --warning:#E6C069;
  --danger:#FF7A85;
  --selection:rgba(138,180,255,.16);
  --grad-play:linear-gradient(90deg,#8AB4FF,#5B4BE0);
}
```

---

## Where these tokens actually land in the OS

| Token | Ends up as |
|---|---|
| The whole dark palette | `/usr/share/color-schemes/AquariusDark.colors` — the KDE colour scheme |
| `starlight` | The KDE **accent colour** |
| Inter | The desktop's general font |
| JetBrains Mono | The desktop's fixed-width font |
| The Pour | `/usr/share/wallpapers/AquariusThePour/` and the default background |

The files that do that live in `../system_files/`. See `README.md` in this folder for how
that works.
