# branding/icons/ — the AquariusOS app icons

This folder is where the nine AquariusOS app icons are **drawn**. They are drawn by code,
not by hand in a design app, so that both colour versions of every icon come out of one
source and can never drift apart.

If you just want to look at them, open any file in [`ice/`](./ice) or
[`midnight/`](./midnight).

---

## The nine icons

| Icon | The name it ships under |
|---|---|
| Aquarius Editor | `aquarius-editor` |
| Aquarius Writer | `aquarius-writer` |
| Files | `org.gnome.Nautilus` *and* `aquarius-files` |
| Settings | `org.gnome.Settings` *and* `aquarius-settings` |
| Console | `org.gnome.Ptyxis` *and* `aquarius-console` |
| Aquarius Apps | `aquarius-apps` |
| Aquarius Welcome | `aquarius-welcome` |
| Install DaVinci Resolve | `aquarius-install-resolve` |
| Remove DaVinci Resolve | `aquarius-remove-resolve` |

**Why three of them have two names.** Files, Settings and the Console are somebody else's
programs — GNOME's Nautilus, GNOME's Settings, and Ptyxis, which is Fedora's terminal and
the terminal AquariusOS ships. Each one asks the desktop for its icon by its own identifier
— `org.gnome.Nautilus`, `org.gnome.Settings`, `org.gnome.Ptyxis` — and nothing will persuade
it to ask for anything else. So the drawing is filed under that name, which is what actually
replaces the icon, *and* under our own name, so that our windows, our docs and the Aquarius
Shell can refer to it without having to know GNOME's internal names. Same picture, two file
names.

**The Console icon** (Royce, 2026-09-06) is a prompt chevron in the Aquarius working line
with a gold underscore cursor beside it. The cursor is the thing that moves on a terminal,
so the cursor is the one gold thing. Two other versions were drawn and not chosen — a block
cursor, and a chevron with two lines of "text" — and both are still in `icons.mjs` as
`console_(size, 'prompt'|'lines')` so the reasoning is not lost. Neither ships.

There is deliberately **no icon for "Check for Update"** (Royce, 2026-09-06): there is no
Check-for-Update app, only a window the logo menu opens, and that window carries the Settings
icon until the whole flow moves into Settings proper.

---

## The grammar — what makes these one family

Every icon is the same five things. **One slate plate** — a rounded square filling the whole
64-unit grid, corner radius 16 (a quarter of the width), with a hairline ring just inside its
edge — carrying **one 5-unit stroke** in the working line, the Aquarius-blue-to-indigo
gradient, drawn with round ends and round joins, and nothing thinner or thicker anywhere.
Where an icon has a wave, it is **the logo's own wave** — never redrawn by eye, only scaled
and moved, which is the rule written down under "The wave" in [`../tokens.md`](../tokens.md).
Each icon has exactly **one gold thing** (`starred`) and no more, so the eye lands in one
place: the Editor's playhead, the Writer's nib, the Welcome sun, the Console's cursor, the
plus and the minus on the two Resolve icons. And the only shadow anywhere is a soft **glyph
shadow** — under the drawing, never under the plate — which lifts the mark off the plate at
large sizes and has quietly vanished by the time the icon is 32 pixels across.

The two themes are the same geometry with a different palette, and that is all: **Ice** is
the light set (pale plate, `#2C8FC4` line, navy ink) and **Midnight** is the dark one (navy
plate, `#00BFFF` line, ice-blue ink). Nothing moves between them. Every colour comes from
[`../tokens.md`](../tokens.md) — none is picked by eye.

> **The palette changed on 2026-09-06** (Royce's call). The colours now come from the
> Aquarius Desktop shell's own theme files — `theme/Ice.qml` and `theme/Midnight.qml` in the
> `aquarius-shell` repository, which is what runs on the bench — recorded in
> [`../tokens.md`](../tokens.md). The old "Starlight" palette from the design-system project
> (`#8AB4FF` blue, `#5B4BE0` purple, `#E6DDB8` gold) is retired for the desktop. Every icon
> was re-rendered in the new palette; **not one shape moved** — that was checked by comparing
> the shape data of the old and new drawings, not assumed.
>
> The logo, the boot assets and the wallpaper caught up later the same day, so the boot mark
> and the icons' mark are now the same drawing in the same colours. Only `../design-system/`
> is still on the old palette — it is a mirror of the design project and gets re-synced from
> there, not edited here. If you are drawing anything new, take the values from
> `../tokens.md` and nowhere else.

> **The mark's apex changed on 2026-09-06 too.** The "A" is now three straight moves,
> `M14 54 L32 12 L50 54`, with one clean point at the top — the little hand-drawn loop is
> gone. Only one icon carries the mark (`aquarius-apps`), and it was re-rendered; the other
> eight were byte-for-byte unchanged, which is how we know nothing else moved. The one
> function that draws it is `markPaths()` in `icons.mjs`, and it is the same shape the logo
> files use. See "The apex" in [`../tokens.md`](../tokens.md).

---

## Regenerating them

You only need this if you have edited `icons.mjs`.

Once, ever, to download the one library the drawings need:

```bash
npm --prefix branding/icons install
```

Then, whenever a drawing changes:

```bash
bash branding/render-app-icons.sh
```

That takes a few minutes — it draws 192 separate pictures — and it prints a check of every
one at the end. Then look at what changed and commit it:

```bash
git add branding/icons system_files/usr/share/icons && git commit
```

**Never edit anything in `ice/`, `midnight/`, or `system_files/usr/share/icons/Aquarius-*/`
by hand.** All of it is overwritten every time that script runs.

---

## What is in here

| File | What it is |
|---|---|
| `icons.mjs` | **The drawings.** Every icon is a function on a 64-unit grid, in both palettes. This is the file you edit. It also holds a few alternates that were tried and not chosen — they are kept as a record and are not shipped. |
| `outline.mjs` | Turns the letters "DR" into a shape for the two DaVinci Resolve icons, using the Sora font file the OS already ships. Letters become geometry so the finished icon never needs a font. |
| `render.mjs` | Writes the drawings out as SVG files. `branding/render-app-icons.sh` runs this; you normally do not. |
| `package.json` | Names the one library (`fontkit`). `node_modules/` is not committed. |
| `ice/`, `midnight/` | The finished master drawings at 1024 pixels — the reference copies, for looking at. |

**Only what is in `SET` at the bottom of `icons.mjs` ships.** The alternates above it
(`aquarius-settings` as three sliders, the Files folder with a wave in it, the tile-shaped
Resolve icons, and so on) exist so the reasoning is not lost, and `render.mjs` never writes
them out.

---

## Where the icons end up, and how the OS picks one

`branding/render-app-icons.sh` writes two complete icon themes into `system_files/`, which is
a mirror of the finished machine's filesystem:

```
system_files/usr/share/icons/Aquarius-Ice/          →   /usr/share/icons/Aquarius-Ice/
system_files/usr/share/icons/Aquarius-Midnight/     →   /usr/share/icons/Aquarius-Midnight/
```

Each theme has an `index.theme` (the file that makes a folder a *theme*), the drawing at
`scalable/apps/<name>.svg`, and the same drawing as a fixed-size picture at
`<size>/apps/<name>.png` in eight sizes from 16 to 512. Both themes say
`Inherits=Adwaita,hicolor`, which means any icon we do *not* draw falls through to GNOME's
own set — we draw nine icons, not the several thousand a desktop needs.

The build step `build_files/56-aquarius-icons.sh` checks all of that arrived, and
`tests/test-aquarius-icons.sh` checks it in this repo before a build even starts.

**The default is `Aquarius-Ice`**, because AquariusOS is light-first. It is set in two
places, and they have to agree: `system_files/usr/share/glib-2.0/schemas/`
`zz1-aquarius-10-look.gschema.override` (what a person's desktop gets) and
`build_files/50-aquarius-desktop.sh` (what the login screen gets).

---

## ⚠️ Two things that are deliberately NOT done here

**1. Nothing switches to Midnight automatically yet.** `Aquarius-Midnight` is built,
installed and ready, and nothing ever selects it. Switching icon themes when the desktop goes
dark is the *shell's* job, not the image's — it belongs in the aquarius-shell repository,
which is the thing that already watches the colour scheme.

> **TODO (aquarius-shell):** when the shell switches the colour scheme to dark, it should
> also set `org.gnome.desktop.interface icon-theme` to `'Aquarius-Midnight'`, and set it back
> to `'Aquarius-Ice'` when it goes light. Both themes are already in the image, so this is a
> one-setting change with no image work behind it.

**2. "Check for Update" has no icon of its own.** Its launcher entry uses
`Icon=org.gnome.Settings` on purpose (Royce, 2026-09-06).

> **TODO:** when the update flow moves into System Settings where it belongs, that launcher
> entry goes away rather than getting an icon.
