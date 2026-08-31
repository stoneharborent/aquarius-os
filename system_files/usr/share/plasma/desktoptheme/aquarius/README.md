# The Aquarius Plasma Style — what is in this folder

This folder **is** the look of the AquariusOS desktop shell: the dark top bar,
the floating dock, and every popup that drops out of them. It is pure data —
pictures and settings, no code — so it cannot crash anything and it cannot go
out of date with a KDE release the way a compiled plugin can.

Full write-up, including how to test it on real hardware:
`docs/plasma-style.md` in the repo root.

## ⚠️ The glass was removed — 2026-08-30

Read this before you look at the drawings and wonder where the transparency
went, and **before** you compare them against the design mirror.

**What changed.** Every surface in this theme — the top bar, the dock, popups,
KRunner, tooltips, cards — is now **fully opaque**. It used to be see-through.

**Why.** The theme was drawn for frosted glass: partly see-through, with the
compositor blurring whatever was behind it. The blur half never worked. On
Bazzite 44 / Plasma 6.7 the compositor simply does not draw it, and an evening
of systematic testing on real hardware cleared every layer we control — our
theme, our KWin effects, our whole settings cascade, the graphics driver, HDR,
display scaling — while a protocol trace showed our request going out and being
accepted. The full investigation is in `docs/blur-known-issue.md` in the repo
root; the summary is that it is not our bug and we cannot fix it from here.

Transparency **without** blur is not glass. It is a panel you can read the
wallpaper through, and text on top of moving window contents. It is harder to
read and it looks cheap. Royce's call: drop it and make the surfaces solid.

**What stayed.** Everything else, deliberately: the 16px rounded corners, the
drop shadows, the hairline borders, the 1px sheen along the top edge, the very
dark surface colours, the radii, the spacing, the aurora wallpaper. Only the
see-through-ness is gone.

**The colours were not re-picked by eye.** Each opaque fill is the old recipe
finished off — the design's translucent colour mixed with the desktop it sat
on (`void` = `#06070C`), computed channel by channel, with the sum written into
each SVG:

| Surface | Was | Now |
|---|---|---|
| top bar, dock | `#06070C` at 62% | `#06070C` (mixing a colour with itself) |
| popups, tooltip, "translucent" card | `#0D0F18` at 76% | `#0B0D15` |
| desktop card | `#10121C` at 86% | `#0F101A` |

So each surface keeps the colour a person already saw over the wallpaper.

**Two files kept their percentages, on purpose.** `widgets/tasks.svg` and
`widgets/plasmoidheading.svg` are washes painted *on top of* a surface that is
itself now solid — highlights, not glass. They never let the wallpaper through
and they still do not. Each file explains this at the top.

**`solid/` is now a byte-identical copy of the root artwork.** It existed to be
the opaque version of two drawings that were see-through; they are opaque now,
so there is nothing left to differ about. Do not delete it — without it, the
panel's "Opaque" setting drops the user into stock KDE Breeze. If you edit
either root file, copy it over its `solid/` twin in the same change.

**We have deliberately diverged from the V2 design mirror.** The design in
`branding/design-system/` still shows glass, and it has **not** been edited to
match — that mirror is a copy of the Claude Design project "AquariusOS Core
Identity", and design changes are made there, never here. If the design is
ever re-cut without glass, the mirror gets re-exported and this note can go.
Until then: **the drawings in this folder are the shipping truth; the mirror
is the design of record.** They disagree about exactly one thing, and this is
it.

**To put the glass back** (if a future Plasma fixes the blur): revert this
branch's theme commits, and set `[BlurBehindEffect] enabled=true` in `plasmarc`
below. Both halves are needed — opaque artwork with blur switched on stays
opaque, and translucent artwork with blur switched off is the raw see-through
look this change removed.

## The files

| File | What it is the background of |
|---|---|
| `widgets/panel-background.svg` | The top bar **and** the dock. Opaque since 2026-08-30. |
| `widgets/tasks.svg` | The tile behind a dock icon — hover, active, running, needs-you. Added 2026-08-30; without it Plasma borrows Breeze's, which paints the active app as a bright blue box. |
| `dialogs/background.svg` | Every popup: tray popups, the calendar, notifications, applet popups, and the search box (KRunner). Opaque since 2026-08-30. |
| `widgets/tooltip.svg` | The little tooltip that follows the pointer. |
| `widgets/background.svg` | A card — a widget sitting on the desktop itself. |
| `widgets/translucentbackground.svg` | The other version of that card. The name is Plasma's — Plasma looks the file up by that exact string — and it is now a lie: this drawing is opaque too. |
| `widgets/plasmoidheading.svg` | The quiet title strip at the top (or bottom) of a popup. |
| `solid/…` | Byte-identical copies of the panel and popup, used when somebody sets a panel to Opaque. Identical because the root artwork is opaque now — see the note above. |
| `plasmarc` | The theme's settings. Read it — every line is explained in place. |
| `metadata.json` | The theme's name, id and version. |
| `metadata.desktop` | Not redundant. Read the comment at the top of it before deleting. |

Anything not listed here is inherited from KDE's Breeze artwork on purpose; see
`FallbackTheme` in `plasmarc`.

## Why there is no `colors` file, and why that is deliberate

A Plasma Style is allowed to ship a `colors` file that overrides the desktop
colour scheme for panels and popups only. **We deliberately do not ship one.**

AquariusOS already sets its palette once, system-wide, in
`/usr/share/color-schemes/AquariusDark.colors`, and that is what the whole
desktop follows — apps, dialogs, panels, everything. If this theme also carried
its own colours, there would be two sources of truth: change the accent in one
and the panels would keep the old one. Worse, anyone who picked a different
colour scheme in Settings would find that their panels ignored the change,
because a theme `colors` file wins over the system scheme.

So: **one palette, set in one place, and this theme follows it.** The only
colours written literally into the SVGs are the decorative ones the design fixes
regardless of scheme — the dark surface fills, the hairline borders, and the thin
sheen along the top edge. Those are design constants, not palette entries.

## The one rule if you edit the drawings

Every shape is drawn twice: once visibly, and once in solid black under a name
starting `mask-`. The black copy is the region Plasma reports as the window's
shape.

**If you change a corner radius, change it in both.** Plasma hands the black
copy to the compositor as the window's mask — the region the window actually
occupies — so if it is squarer than the visible drawing, the window claims
space its artwork does not fill and the corners stop agreeing. (It used to be
the blur region as well, back when this theme asked for blur; that job is
gone, this one is not.) It looks like a driver bug rather than a drawing
mistake, which is why it costs an afternoon.
