# branding/ — the AquariusOS look

**Status: empty on purpose (Phase 1).** No image files live here yet. This folder exists
so there is one obvious home for the visual identity when we get to it.

## What this folder is for

Everything that makes AquariusOS *look* like AquariusOS instead of like Bazzite:

| File (planned) | What it is | Phase |
|---|---|---|
| `wallpaper.png` | The default desktop background a user sees after install. 4K (3840×2160) so it looks sharp on any screen. | 3 |
| `wallpaper-dark.png` | Optional dark-mode variant of the wallpaper. | 3 |
| `logo.svg` | The AquariusOS mark. SVG so it scales cleanly to any size. | 3 |
| `logo-256.png` / `logo-512.png` | Raster versions for places that can't use SVG. | 3 |
| `boot-splash/` | The graphic shown while the machine is starting up (this is a system called Plymouth). | 3 |
| `icon-theme/` | Custom system icons, if we ever go that far. | later |

## How files here actually reach the OS

Dropping a file in this folder does **nothing** by itself. Nothing in `branding/` is
copied into the OS automatically — it is a staging area for the source assets.

To ship a branding asset, it has to be placed at the path it needs to live at inside
`../system_files/`, which mirrors the root of the filesystem. For example, a wallpaper
that should end up at `/usr/share/backgrounds/aquarius/wallpaper.png` in the running OS
goes at `../system_files/usr/share/backgrounds/aquarius/wallpaper.png`. The build script
(`../build_files/build.sh`) copies everything under `system_files/` into the image.

So the Phase 3 flow is: design the asset → save the source here → copy it to the right
place under `system_files/` → push → GitHub rebuilds.

## ⚠️ Open question: renaming the OS itself

Making the system report itself as "AquariusOS" (in About This System, in the terminal,
on the login screen) means changing a file called `/usr/lib/os-release`. **This is not
done yet, and it should not be improvised.**

The upstream ublue-os/image-template does not document a supported way to do it, and
hand-editing `os-release` on an atomic system can interfere with how updates and
rollbacks identify the OS. Before anyone writes that code:

1. Check how Bazzite and other ublue downstream images handle their own naming.
2. Ask in the Universal Blue forums/Discord (linked in `../docs/UPSTREAM-TEMPLATE-README.md`).
3. Record the decision in `../../ROADMAP.md` first.

Until then this is an open TODO, tracked as part of Phase 3.

## Rules

- **Source files only.** Design masters (`.afdesign`, `.psd`, layered exports) do not
  belong in this repo — this repo gets rebuilt on every push and should stay small.
  Keep masters in the Creative Power / design side of the vault and export finals here.
- **No binaries committed until Phase 3.** Placeholder text only for now.
