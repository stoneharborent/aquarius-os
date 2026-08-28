# The codec layer, and the pro desktop defaults

*Built 2026-08-28 (Phase 2, Track B). Implements the codec-layer and "sane pro
defaults" entries in `ROADMAP.md`, from the plan in `docs/codec-research.md` one
folder up. Everything here assumes zero Linux experience.*

---

## What this is, in one paragraph

A "codec" is the compression format inside a video file. This layer is the
promise that AquariusOS can open, play and export the formats a working
filmmaker actually has on their cards — and that it does it using the graphics
card rather than melting the processor. It also covers three small quality-of-
life defaults that belong in the same conversation: a player that hardware-
decodes, a desktop that does not secretly change your colours, and camera cards
that mount the moment you plug them in.

**The surprise finding: almost none of it needed building.** Bazzite, the OS we
build on top of, already ships the entire codec stack. We checked every item on
the plan against the real published image and found all of them present. So this
layer is mostly a written-down audit plus three small, honest additions.

---

## What actually shipped

| # | What you get | Where it is set |
|---|---|---|
| 1 | `mpv` — a reference video player that hardware-decodes | `build_files/build.sh` |
| 2 | mpv's factory settings: `hwdec=auto-safe` | `system_files/etc/mpv/mpv.conf` |
| 3 | Camera cards and drives mount when plugged in | `system_files/usr/share/aquarius/xdg/kded_device_automounterrc` |

And three things deliberately **not** shipped, each explained below: browser
hardware decoding, a colour-management default, and any codec package at all.

---

## 1. The codec audit — what Bazzite already gives us

Our research note listed four things to bake into the image. All four were
already there. The check was done against the real published image
`ghcr.io/ublue-os/bazzite:stable`, build **44.20260825** (Fedora 44), by reading
the package list recorded inside the image itself.

| The plan said to add… | Reality | What it does |
|---|---|---|
| GStreamer VA-API encode packages | `gstreamer1-plugins-bad-free` **already installed** | Contains `libgstva.so`, the modern VA-API encoders and decoders (`vah264enc`, `vah265enc`…), plus `libgstnvcodec.so` for NVIDIA's NVENC/NVDEC |
| `libheif` (+ HEIF thumbnail loaders) | `libheif` **already installed**, and `kf6-kimageformats` too | Opens iPhone HEIC photos, and gives Dolphin HEIC thumbnails via `kimg_heif.so` |
| `libva-nvidia-driver` | **already installed on the NVIDIA image**, correctly absent from the AMD/Intel one | Bridges NVIDIA's NVDEC decoder into VA-API so ordinary Linux apps can use it |
| `libva-utils` | **already installed** | Provides the `vainfo` command — the one-line way to check hardware video is alive |

Three details worth keeping, because each one is a trap for whoever touches this
next.

**The libheif that is installed is the good one.** Fedora's own `libheif` is
built without the HEVC decoder for patent reasons, which would mean iPhone
photos still do not open. Universal Blue swaps it for the unrestricted build
from the `fedora-multimedia` repository, which ships the decoder plug-in
(`libheif-libde265.so`) alongside encoders for x265, AV1 and more. That swap is
inherited, not ours — but it is the reason this box is ticked.

**The Mesa video drivers are not where you would look for them.** Bazzite
*removes* Fedora's `mesa-va-drivers` package and installs Terra's Mesa instead,
whose `mesa-dri-drivers` package contains the video drivers
(`radeonsi_drv_video.so` and friends) directly inside it. AMD hardware decode
works fine — but if you ever "helpfully" reinstall `mesa-va-drivers`, the build
will fail on a file conflict, or quietly replace a version-locked Mesa. Don't.

**`libva-nvidia-driver` must never be added to `build_files/build.sh`.** One
build script builds both AquariusOS images, so a line there would put an
NVIDIA-only driver onto AMD and Intel machines. It is already on the NVIDIA
image, which is the only place it means anything.

### A correction to `docs/codec-research.md`

That note says Bazzite is missing "some GStreamer VA-API encode pieces for OBS"
and calls it "cheap for us to add in the Containerfile", citing Bazzite issue
[#1125](https://github.com/ublue-os/bazzite/issues/1125).

Reading the issue: it is not about a system package at all. It is about a
**Flatpak add-on** for the Flatpak version of OBS
(`org.freedesktop.Platform.GStreamer.gstreamer-vaapi`), which cannot be
installed from a Containerfile in the first place — Flatpaks are not installed
during an image build. Bazzite closed the issue as "not planned".

And it is moot anyway: Bazzite's own list of Flatpaks to install on first boot
already contains `com.obsproject.Studio.Plugin.GStreamerVaapi` and
`com.obsproject.Studio.Plugin.Gstreamer`. The gap named in the research note is
already closed, twice over, by someone else. Nothing for us to do.

---

## 2. The player — and how to check hardware video is working

Bazzite ships **Haruna** as the desktop video player. It arrives as a Flatpak on
first boot, it is built on mpv underneath, and it already has hardware decoding
switched on by its own authors (its `HWDecoding` setting defaults to `auto`,
which is the same thing our mpv setting asks for). So the desktop player needed
nothing from us.

What was missing was a player on the **command line**. AquariusOS now installs
`mpv`, with `/etc/mpv/mpv.conf` setting `hwdec=auto-safe`. Two reasons:

- it plays anything ffmpeg can read and steps a frame at a time, which is how
  you check footage off a card;
- it prints exactly which decoder it chose, which is how you *prove* hardware
  video is working rather than hoping.

mpv's launcher is hidden from the app grid on purpose — Haruna is the player you
click, mpv is the tool you type. Typing `mpv` in a terminal works normally.

### Checking your machine — two commands

**Is hardware video alive at all?**

```
vainfo
```

You want a list of "profiles" — lines mentioning `VAProfileH264…`,
`VAProfileHEVC…`, `VAProfileAV1…`. Each `VAEntrypointVLD` line is a format your
card can *decode*; each `VAEntrypointEncSlice` is one it can *encode*. If the
command prints an error about not finding a driver, hardware video is not
working and nothing else in this document will help until it is.

**Is a real video actually using it?**

```
mpv -v yourfile.mp4 2>&1 | grep -i "hardware decoding"
```

You want a line saying it is using hardware decoding. To see the difference, run
the same file with `mpv --hwdec=no -v` and watch the processor work instead.
While a video is playing, `Ctrl+H` toggles hardware decoding on and off.

---

## 3. Browsers — researched, and deliberately left alone

**The finding: we ship nothing here, on purpose.** Three reasons, in order of
how much they mattered.

**Firefox is not part of the OS.** Bazzite removes the Firefox package from the
image entirely — its build script says so in as many words ("we use the
flatpak") — and installs the Flathub Flatpak on first boot instead. So there is
no system Firefox for an image-level setting to reach.

**A Flatpak's settings do not live in the image.** Flatpak keeps its system-wide
overrides in `/var/lib/flatpak/overrides/`, and on an atomic OS like this one
`/var` is the machine's own state, not part of the image we build. The only way
to write an override at image level is a script that runs at boot and calls
`flatpak override` — which is exactly what Bazzite's own
`bazzite-flatpak-manager` does. Bending that to our will means owning a fork of
somebody else's boot script forever, for a setting the browser mostly gets right
already.

**And the thing that actually breaks is not a setting.** The known failure on
this family of images ([bluefin#1409](https://github.com/ublue-os/bluefin/issues/1409))
is a library mismatch: the host's Intel video driver is built against a newer
C++ runtime than the one inside the Flatpak sandbox, so Firefox's driver test
fails before any preference is consulted. No preference we could ship would fix
that, and shipping preferences that pretend to would be worse than shipping
nothing.

So: **no browser settings ship, and browsing cannot break because of us.**

### If you want to try it yourself — the one toggle

On AMD or Intel graphics, Firefox usually hardware-decodes already. To check:

1. Open `about:support`, find the **Media** section, and look for hardware
   decoding entries.
2. If it is off, open `about:config`, accept the warning, search for
   `media.ffmpeg.vaapi.enabled` and set it to **true**.
3. Restart Firefox and check `about:support` again.

On **NVIDIA** it is a longer road and honestly not worth it for most people:
besides that preference you need `media.hardware-video-decoding.force-enabled`,
`media.rdd-ffmpeg.enabled`, and the environment variables
`MOZ_DISABLE_RDD_SANDBOX=1` and `LIBVA_DRIVER_NAME=nvidia` set on the Flatpak
(the Flatseal app does this with checkboxes). It is decode-only — it never helps
with encoding — and the requirements change with driver versions. The list above
comes from the [nvidia-vaapi-driver](https://github.com/elFarto/nvidia-vaapi-driver)
project's own README; check it before following it, because it moves.

---

## 4. Colour management — checked, and nothing needed

Two separate worries here, and both came out clean.

**Does the desktop secretly change my colours?** No. Night Light — the feature
that warms the screen towards orange in the evening — is the obvious offender on
a machine used for grading, and KDE ships it switched **off**. Neither Fedora
nor Bazzite turns it on. So there is nothing to disable, and we deliberately did
not write a line saying "off" when off is already the answer. The reasoning is
recorded in the comments at the bottom of
`system_files/usr/share/aquarius/xdg/kwinrc`.

**Can we ship a colour-managed desktop as a default?** Not meaningfully, and
this is a case where the honest answer is "the machinery is there, the content
cannot be". Plasma 6.7 has a full colour-management stack — it can apply an ICC
profile per screen, and 6.7 was the release that made ICC profiles work at the
same time as HDR. The tools to manage profiles (`colord`, `colord-kde`) are
already installed. But an ICC profile describes *one particular monitor*: it is
generated by pointing a calibration device at that specific screen. A profile
shipped in an OS image would be wrong for every display it landed on. KDE also
stores the choice in its per-screen output configuration, not in a settings file
we could ship from `/usr/share/aquarius/xdg/`.

So the defensible default is the one we shipped: nothing. When a user calibrates
a monitor, they load their profile in **System Settings → Display & Monitor →
Colour Profile**, and the desktop honours it from then on.

---

## 5. Camera cards mount by themselves

Plug a card, a card reader or an offload SSD into an AquariusOS machine and it
mounts. No click, no dialog.

KDE ships this **off**, and it takes three separate switches to get the
behaviour you actually want — turn the service on, tell it to act when something
is plugged in, and tell it that cards it has never seen before still count. All
three are set in
`system_files/usr/share/aquarius/xdg/kded_device_automounterrc`, which is
heavily commented with the KDE source lines each one comes from.

A fourth switch — mounting everything at login — is deliberately left off. On a
dual-boot gaming PC that would mount the Windows partition every time you log in
and prompt for passwords on encrypted drives. The cost of leaving it off is that
a card already sitting in the reader when you boot waits for one click.

Like everything else in that folder, these are starting points. System Settings
→ Removable Storage → Removable Devices changes them, and the change sticks.

**One known limitation.** When KDE's automounter starts up and finds itself
switched off, it writes "do not load me again" into the user's own settings.
That means an account that already logged into an older AquariusOS build may
never start the service at all, and never read our file. Fresh installs and new
accounts are unaffected. The fix on such an account is one checkbox in the
System Settings page above.

This is separate from — and does not collide with — the service Bazzite already
ships (`ublue-os-media-automount-udev`), which mounts labelled *internal* disks
at boot. That one handles fixed drives; ours handles removable ones.

---

## 6. What is impossible — so nobody expects it

Being straight about the hardware ceiling, from `docs/codec-research.md`:

- **Apple's ProRes and ProRes RAW hardware engines do not exist on a PC.** They
  are a physical part of Apple's own chips. No package, no driver and no setting
  puts them on an AMD or Intel or NVIDIA machine. ProRes still works — it is
  encoded and decoded by the processor via ffmpeg, which is fast and fine — it
  just is not hardware-accelerated, and never will be.
- **10-bit 4:2:2 H.264/H.265 — the flagship format of the Sony FX3/a7S III and
  Canon R5 class — has hardware decode only on Intel Quick Sync and NVIDIA's
  50-series (Blackwell) cards.** On anything older the processor does it, and
  timelines feel sluggish. The answer there is proxies, not packages: the ingest
  helper's DNxHR proxy option, or Resolve's own optimised media.
- **DaVinci Resolve's own codec gaps are inside Resolve, not the OS.** Free
  Resolve on Linux cannot decode H.264/H.265 at all, and even paid Studio
  imports normal camera files with silent audio because it has no AAC decoder.
  That is Blackmagic's licensing, and no Linux distribution can change it from
  the outside. The AquariusOS answer is the ingest helper (`ingest/`), which
  rewraps files before Resolve ever sees them.

---

## What we could not check from a Mac

Honest list. Everything above is read out of published source and out of the
real published image's own package list — none of it has been run on a booted
AquariusOS machine.

- **Nothing here has been executed.** The package audit reads the component list
  recorded inside `ghcr.io/ublue-os/bazzite:stable` (build 44.20260825); the KDE
  behaviour is read from the Plasma 6.7 source that defines it; the mpv paths
  are read from Fedora's own packaging. That is strong evidence, not a test.
- **The `mpv` install has not been resolved by a real `dnf5`.** It is a Fedora 44
  package (`mpv-0.41.0-5.fc44`) and its dependencies are ordinary shared-library
  ones that the image already satisfies, but the first CI build is the proof. If
  it fails it fails loudly and red, and reverting is one line plus one file.
- **The automounter has never been handed a real card.** The settings file name,
  the four key names, their defaults and the cascading read are all quoted from
  KDE's source, but no camera card has been plugged into a machine running this
  image.
- **Whether `kded6` sees our settings folder.** It should, for the same reason
  KWin does — the `zz-aquarius.sh` script sets `XDG_CONFIG_DIRS` before the
  session starts and hands it to systemd — but the automounter service
  specifically has not been watched reading the file.
- **Bazzite's `stable` tag was read from its `main` branch source.** The package
  list came from the actual `stable` image, so the audit stands; but the build
  script quotes (Firefox removal, the Mesa swap, the Flatpak list) come from
  `main`, which can be slightly ahead.

### How to re-run the package audit

Whoever revisits this next should not take the table above on faith — the base
image changes weekly. This reads the package list straight out of the published
image, with no Linux machine and no `podman` needed:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:ublue-os/bazzite:pull&service=ghcr.io" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://ghcr.io/v2/ublue-os/bazzite/manifests/stable" \
  | python3 -c 'import sys,json
m=json.load(sys.stdin)
p=set()
for l in m["layers"]:
    for k,v in l.get("annotations",{}).items():
        if k=="ostree.components":
            p.update(v.replace(","," ").split())
print("\n".join(sorted(p)))'
```

Swap `bazzite` for `bazzite-nvidia-open` to audit the NVIDIA image. Each layer
of a Universal Blue image is annotated with the packages inside it, which is
what makes this work.
