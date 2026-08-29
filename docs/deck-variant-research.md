# The handheld image: which Bazzite it starts from, and what it collides with

*Decided 2026-08-28. Trigger: Phase 2G — Royce owns a base ROG Xbox Ally (Ryzen Z2 A),
which already live-booted the desktop AquariusOS image successfully on 2026-08-26.*

This is the handheld sibling of `nvidia-variant-research.md`. Same job: say which base
image we picked, prove it exists, and — the part that took the most work — answer
whether anything AquariusOS layers on top fights the handheld base.

Short version: it does. **One thing we already ship would have stopped Game Mode from
starting**, and it had been quietly wrong on the other two images for months. It is
fixed, and there is now a build gate so it cannot come back. The rest of our layers
turned out to be structurally incapable of touching Game Mode, which is the answer we
wanted.

Everything below marked "read from source" was read out of `ublue-os/bazzite` at commit
`8c65139` (2026-08-27), or checked against the live registry, on 2026-08-28.

---

## The decision

`aquarius-os-deck` is built on **`ghcr.io/ublue-os/bazzite-deck:stable`**.

Bazzite publishes ten images. Three of them are handhelds, and only one is ours:

| Image | Verdict |
|---|---|
| **`bazzite-deck`** | **Ours.** KDE handheld. |
| `bazzite-deck-gnome` | No. GNOME. Every AquariusOS layer we have — colour scheme, fonts, the top-bar-and-dock layout, the whole GNOME-flow-on-KDE behaviour work — is written for KDE Plasma and would be inert. Standing decision 1 in `../CLAUDE.md` says the desktop choice is not to be reopened. |
| `bazzite-deck-nvidia` | No. Handhelds with an NVIDIA GPU. Every device we care about — Xbox Ally, Ally X, Steam Deck, Legion Go — is an AMD APU. |

**How we know `bazzite-deck` is the KDE one** rather than assuming it from the name:
Bazzite's build workflow derives the Fedora base from the image name — `if [[ "$IMAGE"
== *gnome* ]]; then BASE_IMAGE_NAME="silverblue"; else BASE_IMAGE_NAME="kinoite"; fi`.
`bazzite-deck` has no `gnome` in it, so it is built on Kinoite, which is KDE.

There is **no ASUS-specific image**. A `bazzite-ally` image existed in 2024, was
repurposed for ASUS *laptops*, and is now gone — Bazzite Buzz #18 told ROG Ally handheld
users to move to `-deck`, and `bazzite-ally` returns `DENIED` on the registry today.
`bazzite-deck` is the image for the Ally line, full stop.

And **the recipe does not change**. `aquarius-os-deck` is built from the same
Containerfile and the same `build_files/build.sh` as the other two images, with the base
swapped by the `BASE_IMAGE` build argument exactly the way the NVIDIA variant already
works. There is no `if deck` in the image build. There is one in the *ISO* build, and it
earns its place — see the last section.

---

## The image is real, current, and in step with the others

Checked against the registry directly on 2026-08-28, anonymous pull token, no login:

| Image | `stable` built | Bazzite source revision |
|---|---|---|
| `ghcr.io/ublue-os/bazzite` | 2026-08-25T23:59:43Z | `75cf7fe1bc8a` |
| `ghcr.io/ublue-os/bazzite-nvidia-open` | 2026-08-25T23:01:41Z | `75cf7fe1bc8a` |
| `ghcr.io/ublue-os/bazzite-deck` | 2026-08-25T23:01:50Z | `75cf7fe1bc8a` |

All three come out of the **same commit of `ublue-os/bazzite`**, minutes apart. That is
the thing worth knowing: the handheld image is not a side project on a slower cadence,
it is the same Bazzite built a third way. Our three images stay in step with each other
for free.

`bazzite-deck:stable` reports version `44.20260825` — Fedora 44, same as the desktop base
we already ship. `stable`, `latest`, `testing` and `unstable` all exist, same as on the
other two repos, and on the main branch `stable` and `latest` are pushed together as the
same digest (`latest` is not a bleeding-edge track). We track `:stable`, matching what
`aquarius-os` and `aquarius-os-nvidia` already do.

---

## What the handheld base gives us

Bazzite's Containerfile is staged: `FROM ${BASE_IMAGE} AS bazzite` and then `FROM bazzite
AS bazzite-deck`. So **the handheld image is the desktop image plus a handheld layer**,
with a few deliberate removals. Everything AquariusOS already relies on is still under
it.

What arrives for free, read from source:

- **Game Mode as the default startup**, in three parts. A vendor default at
  `/usr/lib/sddm/sddm.conf.d/holo.conf` that names the session
  (`gamescope-session-ogui-steam.desktop`); a oneshot unit `bazzite-autologin.service`
  enabled at build time and ordered before the login screen; and
  `/usr/libexec/bazzite-autologin`, which writes the autologin config into
  `/etc/sddm.conf.d/` on every boot. The autologin is configured **in the image**, not by
  the installer.
- **The Desktop Mode toggle.** Whether the machine starts in Game Mode or on the desktop
  is decided by whether the file `/etc/bazzite/desktop_autologin` exists — flipped by
  `ujust set-default-desktop` / `set-default-game-mode`. Nothing we do goes near it.
- **The handheld hardware layer.** `inputplumber`, OpenGamepadUI, `steamos-manager` and
  `powerstation` for buttons, gyro, TDP, GPU clocks and fan curves; `jupiter-fan-control`,
  `powerbuttond`, `sdgyrodsu`, `steamdeck-dsp`, a Steam-Deck-patched `upower`, per-device
  udev rules and audio profiles.
- **Steam, Proton and the anti-cheat work**, same as everywhere else.

Two corrections to things that are widely repeated and are **no longer true**, both
verified against the current tree:

- **HHD (Handheld Daemon) is gone.** It is not in the Containerfile or anywhere in the
  repo; the only mentions left are stale translated READMEs. Bazzite Deck 44 uses
  OpenGamepadUI + InputPlumber instead. Do not write "HHD" in AquariusOS docs.
- **`asusctl` is not preinstalled.** It is an opt-in `ujust asus` recipe, and that recipe
  ships on both the desktop and handheld images.

### For the ROG Xbox Ally specifically

`bazzite-deck` carries real, named support for the device:
`/usr/libexec/hwsupport/steamos-manager-hardware` matches both `"ROG Ally"*` and
`"ROG Xbox Ally"*` (the second added 2026-07-24, commit `5cd0be8`, "fix(deck): Add missing
check for ROG Xbox Ally"), so TDP control is driven by SteamOS-Manager on this hardware.
There is also an Ally fingerprint udev rule and Ally / Ally X audio profiles.

Hardware detection throughout is **DMI-based** — the scripts read
`/sys/devices/virtual/dmi/id/product_name`. Nothing we rebrand can affect it.

The honest gaps, also read from source: the Xbox Ally is absent from `sysid`'s
name-truncation table, from the `needs-100-scale` list, from the IOMMU workaround list in
`bazzite-hardware-setup`, and from the pipewire/wireplumber per-device profiles, which
cover only `rc71l` (Ally) and `rc72la` (Ally X). TDP works; several per-device tweaks are
not yet wired up for the newest board.

---

## Do our layers conflict?

### The one that would have broken Game Mode ⚠️

**`/usr/share/ublue-os/image-info.json` is not a label. It is read at runtime, and we
overwrite the whole file.**

Bazzite's own first-boot and session scripts do not read `os-release` to work out what
kind of machine they are on — they read that JSON file. An exhaustive grep of Bazzite's
`system_files/`, `just_scripts/` and `installer/` found nine consumers, and two fields
they care about:

| Field | Who reads it | What breaks if it is wrong |
|---|---|---|
| `base-image-name` | `bazzite-autologin`, `return-to-gamemode`, `os-session-select`, `bazzite-desktop-bootstrap` | Autologin. |
| `image-name` | `bazzite-hardware-setup`, `bazzite-user-setup`, `bazzite-steam`, several `ujust` recipes | The handheld setup switches itself off. |

`bazzite-autologin` runs before the login screen on every boot and does, in effect:

```
if base-image-name =~ "kinoite"      -> log in to KDE
elif base-image-name =~ "silverblue" -> log in to GNOME
else  "Unknown base image ... leaving autologin alone"
```

Bazzite fills that field with the plain word **`kinoite`** or **`silverblue`** — the
Fedora edition underneath, *not* the name of the Bazzite image.

Our `image-info.sh` was filling it with `bazzite`. The line that read the old file matched
on `"image-name"` with a leading `.*`, which also matches the `"base-image-name"` line, and
`head -n1` took the first hit — so it copied Bazzite's *image* name into the field meant
for the Fedora edition. On the desktop images nothing reads it, so it sat there harmlessly
wrong. On the handheld base it would have hit that `else` branch, skipped autologin
entirely, and booted the Ally to a login screen instead of Game Mode. Silently. On the one
feature the image exists for.

**Fixed** in `build_files/image-info.sh`: the field is now read by its own name, anchored
to the start of the line, and passed through untouched. If it is missing or is a word
autologin does not recognise, the build stops with an explanation. The old "which Bazzite
did we come from" value was worth keeping, so it moved to its own key,
`aquarius-upstream-image`, where nothing upstream will ever collide with it.

The second field, `image-name`, is safe by a hair. Bazzite asks "am I a handheld?" by
checking whether it **contains the substring `deck`** — e.g. in `bazzite-hardware-setup`:

```
if [[ "$IMAGE_NAME" != *deck* && "$IMAGE_NAME" != *dx* ]]; then
    rm -f /etc/sddm.conf.d/steamos.conf     # i.e. "you are not a handheld"
```

We replace their name with ours, and `aquarius-os-deck` still contains `deck`, so every
one of those tests keeps giving the right answer. But only because of the name we happened
to pick — so `image-info.sh` now asserts it, and refuses to build a handheld-based image
whose name has no `deck` in it.

Both facts are now also checked **from the outside, on the finished image**, in the
"Verify OS identity" step of `build.yml`, alongside the os-release checks. Same reasoning
as the identity bug of 2026-08-28: a thing that is true today and load-bearing forever is
exactly the kind of thing to keep checking.

### The desktop defaults (kdeglobals, kwinrc, the GNOME-flow layer) — safe, structurally

Our KDE defaults live in `/usr/share/aquarius/xdg/`, and that folder counts for something
only because of eight lines in `system_files/etc/xdg/plasma-workspace/env/zz-aquarius.sh`,
which put it on `XDG_CONFIG_DIRS`.

The important part is *who runs that script*: `startplasma-wayland` / `startplasma-x11`, as
step one of starting a Plasma session. Game Mode is a gamescope session — it starts Steam,
not Plasma — so `zz-aquarius.sh` is never sourced there and `/usr/share/aquarius/xdg/` is
never on the path. **Our entire settings layer is, by construction, desktop-session-only.**
No guard was needed and none was added.

Which is right in both directions: the defaults apply in Desktop Mode on a handheld (a
real Plasma session, which does run the script), and are invisible in Game Mode.

### `/etc/xdg/kwinrc` — the trap we happened to have already avoided

The deck base ships a file the desktop base does not. Both images install a KDE preset
package, and they are different packages that conflict with each other:
`steamdeck-kde-presets-desktop` on the desktop image, plain `steamdeck-kde-presets` on the
handheld. Reading the two spec files side by side, the desktop one explicitly `rm`s
`kwinrc`, `kcminputrc`, `kwinrulesrc`, `powerdevilrc` and `baloofilerc` during install; the
handheld one ships all of them.

So `/etc/xdg/kwinrc` **does not exist on `bazzite`, and does exist on `bazzite-deck`**. It
is three lines:

```ini
[Wayland]
InputMethod[$e]=/usr/share/applications/org.kde.plasma.keyboard.desktop
VirtualKeyboardEnabled=true
```

That is the on-screen keyboard on a device with no keyboard. If we shipped our own
`/etc/xdg/kwinrc`, our copy would replace theirs in the image layer and silently delete it.

**We don't, and that is the design rather than luck.** Our kwinrc is at
`/usr/share/aquarius/xdg/kwinrc` — a different path, one level *above* `/etc/xdg` in KDE's
search order. Keys we set win; keys we do not set fall through to theirs untouched. We set
exactly two sections (`[Desktops] Number=4, Rows=1` and `[Effect-overview] BorderActivate=7`),
neither of which is a virtual-keyboard key. The "add a level, never edit their file"
arrangement documented at the top of `system_files/usr/share/aquarius/xdg/kdeglobals` is
what made a handheld base a non-event here.

> **Rule to keep:** never add a virtual-keyboard key to our `kwinrc`, and never ship a
> file at `/etc/xdg/kwinrc`. On a handheld those two lines are load-bearing and ours would
> outrank them without saying so.

### The desktop layout script — no conflict, and nothing to coordinate

Checked directly: **neither preset package ships a
`plasma-org.kde.plasma.desktop-appletsrc`**, in `/etc/skel` or anywhere else. So a new
account on a deck image has no saved layout, and KDE will run a layout script — which was
the one way our layout could have been silently skipped.

Bazzite sets its own default panel by `sed`-appending `bazzite-pins.js` into the stock
Plasma *layout template*, and it does that in the shared base stage, so the deck image
inherits the identical arrangement. We do not touch that template: our layout comes from
the layout script inside our own global theme (`org.aquariusos.desktop`), selected by
`LookAndFeelPackage` in our `kdeglobals` one level above Bazzite's
`com.valve.vapor.desktop`. A look-and-feel package's own layout script takes precedence
over the default template, so ours runs and theirs is bypassed — on all three images
equally.

**Desktop Mode on a handheld is the same Plasma our desktop images boot into.** There is
no separate deck layout to fight.

### `/etc/skel` — additive, no collisions

The deck image adds `/etc/skel/.config/kcminputrc` (mouse acceleration), adds
`/etc/skel/Desktop/Return.desktop` (the "back to Game Mode" icon), and promotes Steam's
autostart entry from `/etc/skel/.config/autostart/` to `/etc/xdg/autostart/`.

We ship one file into skel, `/etc/skel/.config/kglobalshortcutsrc` (the Super-key binding
from the GNOME-flow work). Different filename, different purpose; `cp -a` merges
directories rather than replacing them. Nothing collides.

### The creator apps — kept, and the size stated honestly

`aquarius-os-deck` carries the **complete creator layer**: Aquarius Editor and Aquarius
Writer baked in, the browsers queued for first boot, the first-login "which creator apps
do you want?" checklist, the DaVinci Resolve flow, the "Make Editor-Ready" right-click
ingest helper.

That is roughly **2.4 GB of baked applications** on an image aimed at a handheld (Aquarius
Editor 2.1 GB, Aquarius Writer 262 MB, measured on the 2026-08-28 build). Stating it
plainly because it is a real cost on a device with a soldered SSD — and keeping it anyway,
because **it is the product**. A handheld that plays games is a Steam Deck; a handheld that
plays games and then edits the footage is the only reason AquariusOS exists. Cutting the
creator apps out of the handheld image would leave us shipping a Bazzite reskin.

The `ujust` collision check in `creator-apps.sh` was a live question here, because the deck
image imports recipe files the desktop image does not (`95-bazzite-deck-session.just` among
them). It needed no change: it already walks every `*.just` in `/usr/share/ublue-os/just/`
on whatever image it is running on, so it will simply check more files on this one. Our
four recipe names (`aquarius-resolve`, `aquarius-resolve-fixups`,
`install-resolve-aac-plugin`, `install-creator-apps`) are checked against all of them, and
an alias collision — which would take down the whole `ujust` menu — is still fatal.

One behavioural note that falls out for free: the first-login checklist is an ordinary
desktop start-up item (`/etc/xdg/autostart/aquarius-creator-apps-offer.desktop`, marked
`OnlyShowIn=KDE`). On a handheld, start-up goes into Game Mode, so the window does not
appear on first boot — it appears the first time the owner switches to Desktop Mode, which
is exactly when it is wanted. Nothing had to be built for that.

### Identity

`image-info.sh` already worked out the "edition" line from the image name rather than being
told it, so this needed one new `case` arm:

```
*-deck*)   IMAGE_VARIANT="Handheld Edition"
*-nvidia*) IMAGE_VARIANT="NVIDIA Edition"
*)         IMAGE_VARIANT="Desktop Edition"
```

That value flows into **both** identity files the script writes — os-release's `VARIANT`,
and `/etc/xdg/kcm-about-distrorc`, the KDE-only override that reads ahead of os-release and
caused the "still says Bazzite" bug of 2026-08-28. The branding is one code path with the
variant as a value inside it, so the handheld image gets the kcm-about-distrorc treatment
automatically rather than needing to be remembered. (Bazzite's own file words this
"Handheld & HTPC Edition"; ours says "Handheld Edition", which is the half that is true for
us.)

The only place a person reads it is KDE's *About This System* page, which lives in Desktop
Mode — Game Mode has no About page. So it does a useful job exactly where it is seen:
telling you this desktop belongs to a handheld.

And rebranding os-release is confirmed safe. **No Bazzite runtime consumer reads `VARIANT`
or `VARIANT_ID` at all** — they all read the JSON file above. `ID=bazzite` still matters,
for the Anaconda installer profile, and stays.

---

## The ISO is built differently, on purpose

For `base` and `nvidia`, the live USB session and the installed OS are the same image. For
`deck` they are not:

```
the live session you boot  →  aquarius-os        (an ordinary desktop)
what gets INSTALLED        →  aquarius-os-deck   (boots into Game Mode)
```

Because Game Mode is a terrible place to run an installer from. Boot a live USB made of the
handheld image and you land in Steam's controller interface with Anaconda somewhere behind
it.

This mirrors Bazzite exactly. Their ISO workflow computes a "non-deck image ref" by string
substitution and comments it plainly — *"We need this as we use the desktop image as the
runtime for the livecds"* — then passes the desktop image as `BASE_IMAGE` and the deck image
as `INSTALL_IMAGE_PAYLOAD`. Our `installer/Containerfile` has taken those same two arguments
since the day it was adapted from theirs, with a comment saying so. Until now we passed the
same value to both. The handheld ISO is the case those two arguments were written for.

`build-iso.yml` decides this from the image **name**, not from the variant drop-down, so the
"Advanced: a specific image" escape hatch gets the same treatment — type a `-deck` image in
that box by hand and you still get a usable installer rather than a puzzle.

### The one deck-specific flag worth having

Bazzite's ISO pipeline has almost nothing deck-specific in it. Checked: the Flatpak list is
split by desktop (KDE vs GNOME), not by deck; there is no separate Anaconda profile or
kickstart; there is no `--variant`. **The single deck conditional in their whole ISO build
is the on-screen keyboard**, and it is the one thing a handheld ISO genuinely cannot do
without: an Ally has a touchscreen and no keyboard, Anaconda asks for a user name and a
password, and with no keyboard on screen there is literally no way to answer it.

So it is ported into `installer/titanoboa_hook_postrootfs.sh`, behind an
`if [[ $imageref == *-deck* ]]` test — the same variable the NVIDIA blocks already use,
derived from the image being *installed*, which is what makes the test meaningful even
though the surrounding filesystem is the desktop image.

We do one thing more than Bazzite there. Restoring the keyboard's launcher makes it
available; it does not switch Plasma's virtual keyboard *on*. On an installed handheld that
second half arrives with the deck base's `/etc/xdg/kwinrc` — the very file the desktop
preset package deletes, which means it is exactly what is missing in a live session built
from the desktop image. So we append those same two lines. It is the only place in this
whole change where we go beyond mirroring upstream, and it is written up in the hook.

Two more consequences worth knowing:

- The live session on a handheld ISO runs the AMD/Intel desktop image, which is correct:
  every target handheld is an AMD APU. The NVIDIA-specific live-session fixes in the same
  hook key off the **installed** image name, so they correctly do not fire for a deck build.
- `installer/build.sh` reaches the payload with `podman pull`, so the deck image must be
  **public on GHCR** before its first ISO build. Every new variant starts out private. This
  is the single most likely reason a first deck ISO run fails, and both the workflow's
  failure message and `GETTING-STARTED.md` now say so.

---

## What this does NOT decide

- **Game Mode branding.** The Aquarius identity *inside* Game Mode — boot splash, Steam
  skin, sounds — is untouched. Game Mode looks like Bazzite's Game Mode. Phase 3 work, and
  `FEATURES.md` entry 002 item 2.
- **The handheld home screen.** The touch-and-controller home screen Royce designed
  (`docs/handheld-mode-design.md`, entry 002) is not in this image. Nothing here builds
  toward it yet.
- **"Dock & Create".** The docked-handheld creator flow from entry 002 item 3 is still a
  design.
- **A VM disk of the handheld image.** `build-disk.yml` still builds the AMD/Intel image
  only. A Game Mode image in a virtual machine is close to useless — this variant is proven
  on hardware or not at all.
- **Whether to pin the tag.** See the risk below. We track `:stable` like the other two;
  changing that for one variant is Royce's call, not a build detail.

---

## Unverified, and the risks worth naming

Everything above is about picking the right starting point and proving nothing we add
fights it. **None of it has been built or booted.** Specifically:

- **Nobody has run this through GitHub Actions.** The image has never been built once. The
  first run proves the base pulls, the creator apps bake on a deck base, and both
  verification gates pass on it.
- **Nobody has booted it.** Does the Ally reach Game Mode; does Desktop Mode look like
  AquariusOS; are the creator apps usable on a 7-inch screen? Only the hardware answers
  that.
- **Screen scaling in Desktop Mode.** Our layout script sizes panels in `gridUnit` multiples
  specifically so they scale, but that has been checked on 1080p and 4K desktops, not on a
  7-inch panel at the fractional scale Bazzite sets by default. This is the most likely
  place the desktop looks wrong, and the Xbox Ally is missing from Bazzite's own
  `needs-100-scale` list.
- **The live-session on-screen keyboard.** Ported and reasoned about, never seen working.
  It is the first thing to check when the deck ISO boots on the Ally, because if it is
  missing the install cannot be completed without a USB keyboard.
- **`/etc/bazzite/desktop_autologin`** — the file that flips Game Mode off — is not created
  anywhere in Bazzite's repo, so it comes from the external `steamos-manager` package. We
  never touch it, but we also cannot see its code.
- **Bazzite Deck 44 is about a week old** and carries four open ROG Xbox Ally **X**
  regressions filed since the stable rollout: black screen on boot (#5517), button chords
  (#5521), trigger rumble stuck at full (#5549), and VRR above 60 Hz (#5625). Royce's device
  is the base Ally, not the X, so these may not apply — but they are the same generation of
  handheld support. If the first boot goes badly, pinning `DECK_BASE_IMAGE` to a dated tag
  such as `stable-44.20260820` is the escape hatch, and `aquarius-os.env` is the one place
  to do it.
