# The Aquarius Plasma Style — what is in this folder

This folder **is** the glass look of the AquariusOS desktop: the smoked top bar,
the floating dock, and every popup that drops out of them. It is pure data —
pictures and settings, no code — so it cannot crash anything and it cannot go
out of date with a KDE release the way a compiled plugin can.

Full write-up, including how to test it on real hardware:
`docs/plasma-style.md` in the repo root.

## The files

| File | What it is the background of |
|---|---|
| `widgets/panel-background.svg` | The top bar **and** the dock. |
| `widgets/tasks.svg` | The tile behind a dock icon — hover, active, running, needs-you. Added 2026-08-30; without it Plasma borrows Breeze's, which paints the active app as a bright blue box. |
| `dialogs/background.svg` | Every popup: tray popups, the calendar, notifications, applet popups, and the search box (KRunner). |
| `widgets/tooltip.svg` | The little tooltip that follows the pointer. |
| `widgets/background.svg` | A card — a widget sitting on the desktop itself. |
| `widgets/translucentbackground.svg` | The see-through version of that card. |
| `widgets/plasmoidheading.svg` | The quiet title strip at the top (or bottom) of a popup. |
| `solid/…` | Opaque copies of the panel and popup, used when somebody turns transparency off. |
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
regardless of scheme — the smoked-glass fills, the hairline borders, and the thin
sheen along the top edge. Those are design constants, not palette entries.

## The one rule if you edit the drawings

Every shape is drawn twice: once visibly, and once in solid black under a name
starting `mask-`. The black copy is the exact area KWin blurs.

**If you change a corner radius, change it in both.** If the black copy is
squarer than the visible one, blurred wallpaper pokes out past the rounded
corners as four pale squares. It is the single most common way to break a glass
theme, and it looks like a driver bug rather than a drawing mistake.
