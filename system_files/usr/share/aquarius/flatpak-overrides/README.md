# Extra permissions for the preinstalled creator apps

**Read `docs/restart/creator-apps.md` first — it explains all of this in plain
English. This note is for whoever edits the files in this folder.**

Every file here is named after a Flatpak app ID and is that app's *override*: a
short list of extra permissions AquariusOS grants it on top of whatever its
author asked Flathub for.

## Why the files live here and not where Flatpak reads them

Flatpak reads system-wide overrides from exactly one place:

    /var/lib/flatpak/overrides/<app-id>

That is checked, not assumed — `flatpak_save_override_keyfile()` in Flatpak's
own `common/flatpak-dir.c` builds the path as *system base directory* +
`overrides`, and the system base directory is `/var/lib/flatpak`. There is no
`/usr/share/flatpak/overrides/` and no `/etc/flatpak/overrides/`. Writing to
either of those does nothing at all, silently.

On AquariusOS `/var` belongs to the machine, not to the image, so nothing we
write there during a build survives the first boot. So the files ship here,
read-only, inside the image, and `/usr/libexec/aquarius-flatpak-preinstall`
copies them into `/var/lib/flatpak/overrides/` on first boot.

**It never overwrites a file that is already there.** If you have ever run
`flatpak override` for an app, or changed its permissions in Flatseal, that is
your file and AquariusOS leaves it alone forever.

## The file format

Flatpak's own. The keys are the ones from an app's `metadata` file:

    [Context]
    devices=all;
    filesystems=xdg-videos;/run/media;

`shared`, `sockets`, `devices`, `filesystems`, `persistent`, `features`, and an
`[Environment]` group. Lists are semicolon-separated with a trailing semicolon.
A leading `!` removes a permission the app asked for.

The build validates every file here by handing it to Flatpak's own parser —
`flatpak override --show` — rather than by eyeballing it, so a malformed file
fails the build instead of being ignored on somebody's machine.

## Why never `--filesystem=host`

`host` means "the whole computer", which is the same as having no sandbox at
all. Every file here names the specific places a creator actually keeps work:

| Path | What it is |
|---|---|
| `xdg-videos` | your Videos folder |
| `xdg-music` | your Music folder |
| `xdg-pictures` | your Pictures folder |
| `xdg-documents` | your Documents folder |
| `/run/media` | USB sticks, SD cards and external drives, as Fedora mounts them |
| `/media`, `/mnt` | where drives get mounted by hand, and by other tools |
