# Research: Making the OS Identify as "AquariusOS"

*Fable research note, 2026-08-24. Status: DECIDED — implementation is a Phase 3 task for an Opus agent.*

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

## Acceptance test
On a booted image: `cat /etc/os-release` shows `PRETTY_NAME="AquariusOS"`, the Settings "About" page says AquariusOS, and `ujust` + system updates still work.
