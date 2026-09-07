# branding/ — the AquariusOS look

This folder is where the AquariusOS **design** lives: the colours, the fonts, the logo and
the wallpaper art. It is the *source*. The OS itself reads copies of these things from
`../system_files/`, which is a mirror of the finished operating system's filesystem.

**If you only read one file in here, read [`tokens.md`](./tokens.md).** That is the list of
every colour and measurement AquariusOS uses. Nothing in this project should ever use a
colour that isn't in that file.

**Where the design is decided.** Since 2026-09-06 the colours come from the Aquarius Desktop
shell's own theme files — `theme/Ice.qml` and `theme/Midnight.qml` in the `aquarius-shell`
repository. Those are what runs on the bench and what Royce approved on screen.
`tokens.md` writes them down so everything else can use the same numbers. If `tokens.md` and
the shell ever disagree, **the shell wins**.

Before that, the design came from the Claude Design project "AquariusOS Core Identity",
direction "Flow State" — the *Starlight* palette. That palette is retired. The
`design-system/` folder next to this one is still a copy of it and is waiting to be
re-synced; its own README says so. Do not copy colours out of it.

---

## What's in here

| File | What it is |
|---|---|
| `tokens.md` | **The source of truth.** Every colour, font, size, corner radius, shadow and animation speed. Read this first. |
| `logo.svg` | The AquariusOS mark, in colour, for a light background. Same drawing as `logo-ice.svg` — this is the name the rest of the repo asks for. |
| `logo-ice.svg` | The mark in the Ice (light) colours, under its honest name. |
| `logo-midnight.svg` | The mark in the Midnight (dark) colours — brighter blue, brighter gold, so it still carries on a navy ground. |
| `logo-mono.svg` | The same mark in a single colour, for icons and watermarks. |
| `wallpapers/the-pour-ice.svg` | The default wallpaper for light mode, as editable artwork. |
| `wallpapers/the-pour-midnight.svg` | The same picture for dark mode. |
| `wallpapers/the-pour.svg` | The original drawing, from the retired KDE line. Nothing installs it any more; it is kept because it is the parent of the two above. |
| `render-wallpaper.sh` | Turns that artwork into the picture files the OS actually ships. |
| `render-logo-png.sh` | Makes the bitmap copy of the mark that GNOME's **login screen** needs. |
| `render-about-logo.sh` | Makes the two wide "mark + AquariusOS" pictures for GNOME's **Settings > About** page — one for light mode, one for dark. |
| `pour.mjs` | **The boot animation itself**, written down as arithmetic. `bootFrame()` is the pour — a stream of water falls from above the screen and the "A" is poured out of it, 2.2 seconds. `shutFrame()` is the wind — the mark is taken apart and blown away to the right, 1.9 seconds. Read its header. |
| `render-plymouth-assets.sh` | Turns those into the 124 picture files the **boot screen** plays, plus the four small shapes the update and disk-password screens are built from. About four minutes. See `../docs/restart/boot-branding.md`. |
| `png-colours.py` | Reads the colours that are really inside a picture file, with no image library. It is how the build proves a retired colour is not hiding in one of those 124 frames, where grep cannot look. |
| `icons/` | **The eight AquariusOS app icons** — the Editor, the Writer, Files, Settings, the app chooser, the welcome window and the two DaVinci Resolve buttons. Drawn by code, in both colour versions. Read [`icons/README.md`](./icons/README.md). |
| `render-app-icons.sh` | Turns those drawings into the two icon themes the OS ships, `Aquarius-Ice` and `Aquarius-Midnight`. |
| `README.md` | This file. |

> **Why the About page needs its own pictures.** It does not look the logo up by name like
> everything else does: on Fedora, `gnome-control-center` is compiled with two fixed file
> paths under `/usr/share/pixmaps/`, and the only way to change that picture is to replace
> the files at those paths. The full explanation is in `docs/gnome-variants.md` under
> "First bench findings — branding", and in the header of `render-about-logo.sh`.

---

## The most important thing to understand

**Putting a file in this folder does nothing.** Nothing in `branding/` is copied into the
operating system.

To make something reach the OS, it has to be placed inside `../system_files/`, at the exact
path it needs to live at in the finished system. `system_files/` is a mirror of `/`. So:

```
system_files/usr/share/plymouth/themes/aquarius/boot-0001.png
        ↓  becomes, in the running OS  ↓
            /usr/share/plymouth/themes/aquarius/boot-0001.png
```

The build script (`../build_files/build.sh`) copies everything under `system_files/` into
the image with a single command. That is the whole mechanism.

---

## Where each piece of the design ends up

| The design says | Which becomes this file | Which makes this happen |
|---|---|---|
| the whole palette, both themes | `theme/Ice.qml` / `theme/Midnight.qml`, in the **shell's** repo | Every colour in the Aquarius Desktop. This folder copies *from* there, never the other way round. |
| `aquariusBlue` `#2C8FC4` | `ANSI_COLOR` in `build_files/70-image-info.sh` | The colour a terminal paints the logo in (`neofetch` and friends) |
| `aquariusBlue`, as a word | `'blue'` in the GNOME defaults | GNOME's accent. GNOME takes one of nine fixed words, not a hex code, and `blue` is the nearest. |
| the palette, in the app icons | `branding/icons/icons.mjs` → `system_files/usr/share/icons/Aquarius-{Ice,Midnight}/` | The two icon themes |
| Midnight `bg` `#0B1220` + `aquariusBlue` `#00BFFF` | `system_files/usr/share/plymouth/themes/aquarius/` | The boot screen's ground and its progress bar |
| Inter, JetBrains Mono | two `dnf5 install` lines in the build files | The desktop's normal and code fonts |
| Sora | `system_files/usr/share/fonts/sora-fonts/` | The display font, for headlines |
| "The Pour" | `system_files/usr/share/backgrounds/aquarius/` | The default desktop background, one picture per theme |
| the mark | `system_files/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg` | The logo every app finds by name — the About page, the boot screen, the logo menu |

---

## Changing the wallpaper

1. Open `wallpapers/the-pour-ice.svg` (light mode) or `wallpapers/the-pour-midnight.svg`
   (dark mode) and edit it. They are plain text — any code editor opens them, and design
   apps can open them too. **Change both**, or the desktop will look like two different
   designs depending on the time of day.
2. Run this, from anywhere:
   ```bash
   bash branding/render-wallpaper.sh gnome
   ```
   That writes both pictures at 4K straight into
   `system_files/usr/share/backgrounds/aquarius/`.

   ⚠️ Say `gnome`. Plain `render-wallpaper.sh` with no argument also runs the old KDE half,
   which writes a wallpaper package this line does not install.
3. `git add`, `git commit`, `git push`. GitHub rebuilds the OS with the new background.

You do **not** need to install anything for step 2 — the script uses Google Chrome, which is
already on the Mac. (If `rsvg-convert` happens to be installed it quietly uses that instead,
because it's faster.)

**Never edit the `.png` files by hand.** They get overwritten every time step 2 runs.

---

## Changing a colour

The desktop's colours do not start here. They start in the shell's `theme/Ice.qml` and
`theme/Midnight.qml`, in the `aquarius-shell` repository. So:

1. **Change it in the shell first.** That is the only place a colour is really decided.
2. **Write the new value into `tokens.md`**, in the same sitting. If the two ever disagree,
   the shell is right and `tokens.md` is stale.
3. **Find the copies of that colour in this repository and change them too.** There are only
   a handful, and the "Where each piece of the design ends up" table above lists them all.
   Grep for the old hex code before you decide you are finished.
4. **Re-run whichever renderer that colour feeds** — `render-app-icons.sh`,
   `render-plymouth-assets.sh`, `render-about-logo.sh`, `render-wallpaper.sh` — and commit
   the pictures it writes along with the change.
5. Push.

There is no colour-scheme file to edit any more. The KDE line, and its
`usr/share/color-schemes/AquariusDark.colors`, are gone.

---

## The fonts

Two of the three come from Fedora's own package list, so the build just asks for them by
name. The third isn't packaged by anyone, so we carry the font file ourselves.

| Font | How it gets in | Notes |
|---|---|---|
| **Inter** | `dnf5 install rsms-inter-fonts` | Also makes Inter the system's default sans-serif, which is exactly what we want. |
| **JetBrains Mono** | `dnf5 install jetbrains-mono-fonts` | Also makes it the system's default monospace font. |
| **Sora** | The file is committed in this repo | See below. |

### About the copy of Sora in this repo

Sora is not in Fedora's package list, so the actual font file lives here:

```
system_files/usr/share/fonts/sora-fonts/Sora[wght].ttf
system_files/usr/share/licenses/sora-fonts/OFL.txt
```

It came from Google's official fonts repository, from one exact frozen point in that
repository's history so it can always be re-downloaded identically:

- Source: `https://github.com/google/fonts/tree/main/ofl/sora`
- Pinned commit: `a926665019d3f7f25c8b1212cecbfa871e70de82`
- `Sora[wght].ttf` — sha256 `84ff7096ae3ec6c8be47d906d1a0ba4de7f2ce78c615275c77301964a316e16c`
- `OFL.txt` — sha256 `ba0b9729c9428ba79a0459ab8ec575791b51509dbec213e383d0316d37fec299`

It is a "variable font": one file that contains every weight from Thin to ExtraBold, rather
than one file per weight. The licence is the SIL Open Font License, which explicitly allows
bundling it in a product like this — the `OFL.txt` file next to it is that licence, and it
has to ship alongside the font.

To update Sora later: download the two files from that repository again, replace them in
`system_files/`, and update the commit and sha256 lines above.

---

## Rules for this folder

- **Source files only.** Layered design masters (`.afdesign`, `.psd`) do not belong here —
  this repo gets rebuilt on every push and should stay small. Keep masters on the design
  side of the vault and export finals here.
- **`tokens.md` is upstream of everything.** Change it first, then change the files that
  copy from it.
- **Don't invent colours.** If the design needs a colour that isn't in `tokens.md`, it needs
  to be added to the Claude Design project first, then to `tokens.md`, then used.

---

## Still open

**The `design-system/` folder is stale.** It is a mirror of the Claude Design project, and
that project still carries the retired Starlight palette. It gets re-synced from the design
side, not edited here — its own README says so, and nothing in this repository should read
colours out of it. `tokens.md` is the record until the mirror catches up.
