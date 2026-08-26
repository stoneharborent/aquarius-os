# Research: Making the OS Identify as "AquariusOS"

*Fable research note, 2026-08-24. Status: **IMPLEMENTED, 2026-08-26** — shipped in commit
`270cdf7` as `build_files/image-info.sh`, called as the last step of `build_files/build.sh`.
Both images (`aquarius-os` and `aquarius-os-nvidia`) built green in Actions run
[32935412890](https://github.com/stoneharborent/aquarius-os/actions/runs/32935412890).*

## Finding
The scaffold left "OS naming" as a TODO because hand-editing `/usr/lib/os-release` looked risky. Research resolved it: **Bazzite itself rebrands the OS with sed edits at image build time**, in `build_files/image-info` of the ublue-os/bazzite repo. Editing at build time (inside the Containerfile layer) is the supported, canonical mechanism — the risk warning only applies to editing a *running* system.

Reference implementation: https://github.com/ublue-os/bazzite/blob/main/build_files/image-info

## What Bazzite's script does (our template)
1. Writes `/usr/share/ublue-os/image-info.json` with image name/vendor/ref/version.
2. `sed` edits `/usr/lib/os-release`: `NAME`, `PRETTY_NAME`, `VARIANT_ID`, `HOME_URL`, `DOCUMENTATION_URL`, `SUPPORT_URL`, `BUG_REPORT_URL`, `CPE_NAME`, `DEFAULT_HOSTNAME`, `ID` (+ adds `ID_LIKE`), `LOGO`, `ANSI_COLOR`, `VERSION_CODENAME`; deletes the REDHAT_* fields.
3. Compatibility fixes for the rename: writes `/etc/system-release` ("Bazzite release NN") so grub uses the right distributor name, and pins `EFIDIR="fedora"` in `/usr/sbin/grub2-switch-to-blscfg` because the EFI directory must stay `fedora`.

## Decision for AquariusOS (conservative first pass)
Phase 3 implementation should add a `build_files/image-info.sh` step, run late in `build.sh`, that:

- **Changes (user-visible identity):** `NAME="AquariusOS"`, `PRETTY_NAME="AquariusOS"`, `VARIANT_ID=aquarius-os`, `DEFAULT_HOSTNAME="aquarius"`, `LOGO`/`ANSI_COLOR` once branding assets exist, and our URLs when a website exists (until then leave Bazzite's support URLs — honest, since Bazzite docs still apply).
- **Does NOT change (compatibility):** `ID` stays `bazzite` for now. Bazzite changed `ID` and had to patch fallout (grub EFIDIR, etc.), and Bazzite's own ujust/tooling may check `ID=bazzite`. Keeping it costs nothing user-visible — `PRETTY_NAME` is what neofetch/Settings/installers display. Revisit only if something specifically needs `ID=aquarius-os`, and then copy Bazzite's full fix list (system-release + EFIDIR) verbatim.

## What actually shipped (2026-08-26)
`build_files/image-info.sh`, run as the last step of `build_files/build.sh` so nothing
installed afterwards can overwrite it. It rewrites exactly six lines of `/usr/lib/os-release`:

| Field | Value |
|-------|-------|
| `NAME` / `PRETTY_NAME` | `"AquariusOS"` — no version number, matching how Bazzite composes its own |
| `VARIANT_ID` | `aquarius-os` — same for both images; NVIDIA is the same OS with different drivers |
| `DEFAULT_HOSTNAME` | `"aquarius"` |
| `LOGO` | `aquarius-logo` — the icon we already ship at `/usr/share/icons/hicolor/scalable/apps/` |
| `ANSI_COLOR` | `"0;38;2;138;180;255"` — Starlight `#8AB4FF` as truecolor, Bazzite's exact format |

It also rewrites `/usr/share/ublue-os/image-info.json`, which arrives from the base image
still claiming the machine runs Bazzite. Same field names as Bazzite's, filled with our
image name/vendor/ref. `image-ref` uses `ostree-unverified-registry:` rather than
`ostree-image-signed:` because AquariusOS does not yet install a signing policy for
`ghcr.io/stoneharborent` (see `installer/README.md`) — change it the day we do.

Because one recipe builds two images, the image name is now a build knob: `IMAGE_NAME` and
`IMAGE_VENDOR` are ARGs in the `Containerfile` (with working defaults) that the `Justfile`
fills in per variant, the same way `BASE_IMAGE` already worked.

The script hard-fails the build if `PRETTY_NAME` did not take, so a silently-unbranded image
can never ship, and it prints the finished file into the Actions log.

Untouched, as decided: `ID`, `ID_LIKE`, `CPE_NAME`, all four URLs, plus `BOOTLOADER_NAME`,
`IMAGE_ID` and `VERSION_CODENAME` (nobody reads them, and `IMAGE_ID` would force an initramfs
rebuild). No `/etc/system-release` or grub `EFIDIR` patching — those are only needed if `ID`
changes, and it did not.

## Acceptance test
On a booted image: `cat /etc/os-release` shows `PRETTY_NAME="AquariusOS"`, the Settings "About" page says AquariusOS, and `ujust` + system updates still work.
