# Research: Making the OS Identify as "AquariusOS"

*Fable research note, 2026-08-24. Status: **IMPLEMENTED, 2026-08-26** — shipped in commit
`270cdf7` as `build_files/image-info.sh`, called as the last step of `build_files/build.sh`.
Both images (`aquarius-os` and `aquarius-os-nvidia`) built green in Actions run
[32935412890](https://github.com/stoneharborent/aquarius-os/actions/runs/32935412890).*

> ⚠️ **Read the addendum at the bottom before trusting this page.** The plan below
> shipped and was incomplete: KDE's About This System page does not read
> os-release, so the installed OS still called itself Bazzite. Fixed 2026-08-28.

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

---

# Addendum, 2026-08-28 — the branding shipped broken, and why

**Status: FIXED.** The 2026-08-26 images installed and booted, and KDE's
*Settings → About This System* still said **"Bazzite 44 / NVIDIA Edition /
https://bazzite.gg"** with the Bazzite logo. Everything above was correct and
had worked; it was simply *incomplete*, and the acceptance test above could not
tell the difference because a human had to run it by hand and nobody did.

## What the research above did not anticipate

It assumed **os-release is the single source of the OS name**. That assumption
is stated at the top of the shipped script ("Almost everything that displays the
name of the OS reads that file: KDE's Settings > About This System page…").

It is wrong for exactly one reader, and it happens to be the most visible one.

**KDE's About This System page reads `/etc/xdg/kcm-about-distrorc` first, and
every key that file sets overrides os-release.** From
`kinfocenter/kcms/about-distro/src/main.cpp`, `loadOSData()`:

```cpp
KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("kcm-about-distrorc"), KConfig::NoGlobals);
KConfigGroup cg = KConfigGroup(config, "General");
KOSRelease os;
QString logoPath        = cg.readEntry("LogoPath", os.logo());     // os-release is only the FALLBACK
const QString distroName = cg.readEntry("Name",    os.name());
const QString variant    = cg.readEntry("Variant", os.variant());
const QString url        = cg.readEntry("Website", os.homeUrl());
```

Bazzite ships that file, per desktop variant. Ours came from
`ublue-os/bazzite → system_files/nvidia/kinoite/etc/xdg/kcm-about-distrorc`:

```ini
[General]
LogoPath=/usr/share/pixmaps/system-logo-white.png
Name=Bazzite
Website=https://bazzite.gg
Variant=NVIDIA Edition
```

That is, line for line, the screen Royce photographed. Nothing in our build ever
touched it, so it survived untouched into the image. ("44" is the one field the
rc file does *not* set, so it still came from os-release's `VERSION_ID`.)

## The hypothesis that was wrong

The obvious theory was a split `/etc/os-release` (a real Bazzite file) vs
`/usr/lib/os-release` (our rewritten one). **Disproven, three ways:**

1. **Fedora ships `/etc/os-release` as a symlink**, not a file —
   `fedora-release.spec`: `ln -s ../usr/lib/os-release %{buildroot}%{_sysconfdir}/os-release`.
2. **Nothing in `ublue-os/*` creates a real one.** A tree search of the Bazzite
   repo finds no `etc/os-release` file, and Bazzite's own `build_files/image-info`
   writes only `/usr/lib/os-release` — exactly like ours.
3. **The "NVIDIA Edition" string was the tell.** Our shipped
   `/usr/lib/os-release` says `VARIANT="Kinoite"` (printed in Actions run
   `33112610021`). The About page said "NVIDIA Edition" — a string that exists
   *nowhere* in any os-release file, only in `kcm-about-distrorc`. So the About
   page was not reading a stale os-release; it was not reading os-release at all.

Homebrew's user agent showing `AquariusOS` in the same session was not a
contradiction — it was the control. It reads os-release, and os-release was
right the whole time.

**Ordering was also not the cause.** `image-info.sh` was already the last line of
`build.sh`, and the Actions log shows the rewrite intact in the committed layer.

## Second finding: the hostname

`DEFAULT_HOSTNAME="aquarius"` was set correctly, and systemd honours it whenever
`/etc/hostname` is missing or empty. But Bazzite's first-boot script
`/usr/libexec/bazzite-hardware-setup` contains:

```bash
if (( $(hostname | wc -m) > 20 )); then
  hostnamectl set-hostname bazzite
fi
```

It is a guard against over-long DHCP/rDNS hostnames breaking Distrobox — but the
name it falls back to is hard-coded, it runs on our image, and
`hostnamectl set-hostname` writes `/etc/hostname` **permanently**. One pass
through that branch and the machine is called `bazzite` for good.

This is the only place in the whole image that hard-codes the hostname `bazzite`,
so it is the only candidate. Whether the length condition actually fired on
Royce's machine cannot be confirmed from outside the box (`hostnamectl status`
on the installed system would settle it). Either way the string is now ours.

## What changed (commit of 2026-08-28)

`build_files/image-info.sh`, still the last step of `build.sh`:

| Change | Why |
|--------|-----|
| Writes `/etc/xdg/kcm-about-distrorc` (`Name`, `Variant`, `Website`) | **The actual fix.** Overwrites Bazzite's copy. `LogoPath` is deliberately omitted so the logo falls back to os-release's `LOGO` — one source of truth, not two. |
| `VARIANT` now branded per image (`"NVIDIA Edition"` / `"Desktop Edition"`) | It was still saying `"Kinoite"`, inherited from Fedora. Derived from `IMAGE_NAME`, so the two images can't drift. |
| `HOME_URL` → `https://github.com/stoneharborent/aquarius-os` | It pointed at bazzite.gg. No website yet, so the repo is the honest answer. |
| `BUG_REPORT_URL` → our issues tracker | An AquariusOS bug filed on Bazzite's tracker is noise for them and a dead end for us. |
| Asserts (and repairs) `/etc/os-release → ../usr/lib/os-release` | The symlink is correct today. This makes it *stay* correct instead of being assumed. |
| Rebrands the hard-coded hostname in `/usr/libexec/bazzite-hardware-setup` | Closes the only remaining `bazzite` hostname source. Guarded so a Bazzite rename can't break the build, and grep-verified so a Bazzite *reword* can't slip past silently. |
| Field writes go through a `set_field` helper | Bazzite's bare `sed -i` per field silently does nothing if a field ever disappears. The helper replaces the line, or appends it if missing. |
| Verification now checks **every** field in **both** os-release paths **and** the KDE rc file | It used to check one line of one file, which is why a broken image shipped green. |

Unchanged, as originally decided: `ID`, `ID_LIKE`, `CPE_NAME`,
`DOCUMENTATION_URL`, `SUPPORT_URL`, `BOOTLOADER_NAME`, `IMAGE_ID`,
`VERSION_CODENAME`.

## New acceptance test — automated

The old acceptance test needed a human with a booted machine, which is why the
regression shipped. `.github/workflows/build.yml` now has a **Verify OS identity**
step that runs *after* the rechunk (so it inspects the exact bits that get
pushed), starts the image with podman, and fails the build unless the image
passes every check — including the literal
`grep -q '^NAME="AquariusOS"' /etc/os-release` and `grep -q AquariusOS /usr/lib/os-release`.

From now on, **green means the OS actually knows its own name.**

Verified against a reconstructed `bazzite-nvidia-open:stable` fixture: the CI
script fails 8 of 11 checks on the stock file (reproducing the shipped bug
exactly) and passes all 11 after the branding pass.

### Still not covered

- **The ISO workflows** (`build-iso.yml`, `build-disk.yml`) have no identity
  check. They consume the same image, so a broken image can no longer reach
  them, but the installer's own live session is not inspected.
- **`/usr/share/pixmaps/system-logo-white.png`** is still Bazzite's artwork.
  Nothing points at it any more (we dropped `LogoPath`), but other Bazzite
  components may.
- **Anything else Bazzite branded outside os-release** — the boot splash,
  Plymouth theme, the MOTD, `ujust` output. Same class of bug as this one; none
  is checked. Worth a sweep for `bazzite` strings in a future pass.
