# branding/ — the AquariusOS look

This folder is where the AquariusOS **design** lives: the colours, the fonts, the logo and
the wallpaper art. It is the *source*. The OS itself reads copies of these things from
`../system_files/`, which is a mirror of the finished operating system's filesystem.

**If you only read one file in here, read [`tokens.md`](./tokens.md).** That is the list of
every colour and measurement AquariusOS uses. Nothing in this project should ever use a
colour that isn't in that file.

The design itself is decided in the Claude Design project **"AquariusOS Core Identity"**,
direction **"Flow State"**. This folder is where that decision gets written down in a form
the build can use.

---

## What's in here

| File | What it is |
|---|---|
| `tokens.md` | **The source of truth.** Every colour, font, size, corner radius, shadow and animation speed. Read this first. |
| `logo.svg` | The AquariusOS mark, in colour. |
| `logo-mono.svg` | The same mark in a single colour, for icons and watermarks. |
| `wallpapers/the-pour.svg` | The default wallpaper, as editable artwork. |
| `render-wallpaper.sh` | Turns that artwork into the picture files the OS actually ships. |
| `render-logo-png.sh` | Makes the bitmap copy of the mark that GNOME's **login screen** needs. |
| `render-about-logo.sh` | Makes the two wide "mark + AquariusOS" pictures for GNOME's **Settings > About** page — one for light mode, one for dark. |
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
system_files/usr/share/color-schemes/AquariusDark.colors
        ↓  becomes, in the running OS  ↓
            /usr/share/color-schemes/AquariusDark.colors
```

The build script (`../build_files/build.sh`) copies everything under `system_files/` into
the image with a single command. That is the whole mechanism.

---

## Where each piece of the design ends up

| The design says | Which becomes this file | Which makes this happen |
|---|---|---|
| the dark colour palette | `system_files/usr/share/color-schemes/AquariusDark.colors` | The KDE colour scheme "Aquarius Dark" |
| `starlight` `#8AB4FF` | same file + the KDE defaults | The accent colour on buttons, links and selections |
| Inter, JetBrains Mono | two `dnf5 install` lines in `build.sh` | The desktop's normal and code fonts |
| Sora | `system_files/usr/share/fonts/sora-fonts/` | The display font, for headlines |
| "The Pour" | `system_files/usr/share/wallpapers/AquariusThePour/` | The default desktop background |
| the desktop layout | `system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/` | The top bar and the floating dock |

---

## Changing the wallpaper

1. Open `wallpapers/the-pour.svg` and edit it. It is plain text — any code editor opens it,
   and design apps can open it too.
2. Run this, from anywhere:
   ```bash
   bash branding/render-wallpaper.sh
   ```
   That writes fresh picture files at 4K, 1080p and 1280×800 straight into
   `system_files/usr/share/wallpapers/AquariusThePour/contents/images/`.
3. `git add`, `git commit`, `git push`. GitHub rebuilds the OS with the new background.

You do **not** need to install anything for step 2 — the script uses Google Chrome, which is
already on the Mac. (If `rsvg-convert` happens to be installed it quietly uses that instead,
because it's faster.)

**Never edit the `.png` files by hand.** They get overwritten every time step 2 runs.

---

## Changing a colour

1. Change it in `tokens.md`. Always here first.
2. Convert the hex code to the "red,green,blue" numbers KDE wants — `#8AB4FF` becomes
   `138,180,255`. (Any "hex to RGB" web page does this, or ask Claude.)
3. Change every place that colour appears in
   `system_files/usr/share/color-schemes/AquariusDark.colors`. That file has a cheat sheet
   at the top listing which token is which number.
4. Push.

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

**The OS still calls itself Bazzite** in "About this system" and in the terminal. Renaming
it is deliberately a separate job with its own risks — the research is written up in
[`../docs/os-release-branding-research.md`](../docs/os-release-branding-research.md) and it
is tracked in `../../ROADMAP.md`. Nothing in this folder attempts it.
