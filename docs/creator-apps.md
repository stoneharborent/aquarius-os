# The creator apps — what ships, and how it gets there

*Phase 2, Workstream A. Written 2026-08-28. Read this before changing which apps
AquariusOS comes with.*

This is the part of AquariusOS that makes it a creator's operating system rather
than Bazzite with a new coat of paint. It is written for somebody who has never
used Linux. Nothing here assumes you know what a container or a systemd unit is.

---

## What you get on a fresh install

| App | What it is | How it gets here |
|---|---|---|
| **Aquarius Editor** | Our video editor | Built into the OS |
| **Aquarius Writer** | Our writing / vault app | Built into the OS |
| **OBS Studio** | Screen recording and live streaming | Installed on first internet connection |
| **Audacity** | Audio recording and cleanup | Installed on first internet connection |
| **Firefox** | Web browser | Installed on first internet connection |
| **Google Chrome** | Web browser | Installed on first internet connection |
| **DaVinci Resolve** | Professional editing / colour | **Offered**, one click — see below |

Nobody has to open a terminal for any of it.

Deliberately **not** preinstalled: Krita, Blender, Ardour, Kdenlive, Obsidian.
They were on the original list and Royce cut them on 2026-08-28. The reasoning: a
short list everybody uses beats a long list that mostly sits there taking up
space, and every one of them is one click away in the app store. Aquarius Editor
takes the slot Kdenlive was going to have; Aquarius Writer takes Obsidian's.

---

## How the apps arrive

There are two completely different mechanisms here, and it matters which is
which.

### 1. Our own apps are *baked in*

Aquarius Editor and Aquarius Writer are not on any app store — they are ours, and
they are released on GitHub. So when GitHub Actions builds AquariusOS, the build
downloads each app's Linux release, checks it, unpacks it, and puts it inside the
OS image. By the time you install AquariusOS they are already there, exactly like
the calculator or the file manager.

The build does this in `build_files/creator-apps.sh`. Three details worth knowing:

* **Nothing is trusted without being checked.** Every release publishes a
  `SHA256SUMS.txt` — a list of fingerprints for the files in it. The build
  downloads that file first, uses it to work out which file is the Linux app and
  what its fingerprint should be, then downloads the app and recomputes the
  fingerprint. If the two differ by a single character the build stops and no OS
  is published. There is no fingerprint written down in our source code, which
  means there is none to forget to update when a new version is released.

* **They are unpacked, not left as "AppImages".** The releases are AppImages —
  one big file with a whole program inside. Normally an AppImage mounts itself
  like a disc every time you run it, using a system component called FUSE. We
  unpack it at build time instead and ship the loose files. Three reasons, in
  order of importance: nothing can be missing at runtime (a machine without FUSE
  fails with `dlopen(): error loading libfuse.so.2`, which is not a message a
  normal person can act on); we can switch Aquarius Editor's Chrome-style
  security sandbox back on, which a self-mounting AppImage physically cannot do;
  and the app starts faster, because the AppImage's insides are compressed with
  xz and have to be decompressed as they are read. The cost is disk space —
  unpacking roughly doubles to triples the size. For the flagship app of the OS,
  an app that cannot fail to start is worth the gigabyte.

* **Upgrading either app is a one-word change.** In `creator-apps.sh` there is a
  short list near the top:

  ```
  AQUARIUS_APPS=(
      "aquarius-editor stoneharborent/aquarius-editor v0.3.0"
      "aquarius-writer stoneharborent/aquarius-writer v0.1.0"
  )
  ```

  Change the version tag, push, and the next build picks up the new release.
  Nothing else needs touching.

### 2. Everything else is a *Flatpak*, fetched on first boot

A Flatpak is a self-contained app that updates on its own schedule, separately
from the operating system. That is exactly what you want for third-party apps: a
broken update to OBS can never stop your computer from starting.

Flatpaks cannot be installed while an OS image is being built — they need a
running system. So the OS ships a **shopping list** instead, and a small service
does the shopping the first time the machine is online.

* The list: `system_files/usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall`
  → lands at `/usr/share/flatpak/preinstall.d/` on the installed system.
* The shopper: `aquarius-flatpak-preinstall.service`, which runs
  `/usr/libexec/aquarius-flatpak-preinstall`.

**The list format is Flatpak's own**, not something we invented — see
`man flatpak-preinstall`. Flatpak gained this feature in version 1.17 and Fedora
44 (what Bazzite, and therefore AquariusOS, is built on) ships 1.17.7 or newer.
A block looks like:

```ini
[Flatpak Preinstall com.obsproject.Studio]
Branch=stable
```

`Branch=stable` is not optional. Leave it out and Flatpak looks for a branch
called `master`, which Flathub apps do not have, and finds nothing — silently.

**Why we run it ourselves.** Flatpak's documentation says "the OS runs
`flatpak preinstall -y` on start-up". On Bazzite, nothing does. Bazzite gets its
default apps onto a machine a different way: it installs them into the live USB
image while the ISO is being built, and the installer copies them across. That
route does not help us, for two reasons — the AquariusOS installer deliberately
skips it to keep the ISO small, and it does nothing at all for somebody who
switched an existing machine over to AquariusOS with `bootc switch`. One small
service on the running system covers both cases. Bazzite's own
`bazzite-flatpak-manager.service` does a different job (app permissions and
tweaks) and is left completely alone; ours simply runs after it.

**If it cannot finish, it tries again.** No internet on first boot? The service
exits and systemd retries a couple of minutes later, indefinitely, until it
works. One app fails but the others install? It says which one and tries that one
again the next time the computer starts — not every two minutes all day. Once
everything is present it writes a small note to
`/etc/aquarius/flatpak-preinstall-version` and never does any of this again.

**The user always wins.** Uninstall OBS and it stays uninstalled — Flatpak
remembers that you removed a preinstalled app and does not put it back. That is
Flatpak's own behaviour and it matches how the rest of AquariusOS treats
defaults: we choose the starting point, you choose everything after that.

To run the shopping trip again by hand (say you were offline for a week):

```
ujust install-creator-apps
```

#### Two notes on the browsers

**Firefox.** Stock Bazzite does ship Firefox — but from the USB stick, during
installation, which as explained above is a route AquariusOS does not use. So the
Firefox line in our list is what actually puts Firefox on an AquariusOS machine;
it is not a duplicate of something Bazzite already did. On a machine that came
from Bazzite and was switched over to us, Firefox is already installed and
Flatpak leaves it exactly as it is.

**Google Chrome.** Google does not let anyone redistribute Chrome, so Flathub's
`com.google.Chrome` is a small wrapper that downloads Google's own installer from
`google.com` at install time. Flatpak calls this "extra-data". It works fine with
the preinstall mechanism — it is a normal install as far as Flatpak is concerned
— with one wrinkle worth knowing about: extra-data apps break if Google removes
an old build before Flathub updates its recipe, and then that one app fails to
install for a day or two. Our service is built for exactly that: it installs
everything it can and retries the straggler on the next start-up.

---

## DaVinci Resolve

Resolve is the app most professional editors and colourists expect to find. We
**cannot ship it**: Blackmagic's licence allows only Blackmagic to hand out the
installer. No trick gets around that, and nothing of Blackmagic's is anywhere in
this repository or in the OS image.

What AquariusOS ships instead is the shortest honest path to having it.

### Three ways to start it, all doing the same thing

1. **A pop-up, once, on your first login.** "Set up DaVinci Resolve?" — Yes or
   Not now. Whichever you pick, it is never asked again: the answer is recorded
   in `~/.config/aquarius/resolve-offer-answered`. It waits half a minute after
   login so it never lands on top of a desktop that is still appearing, and it
   never blocks anything. You can switch the whole thing off in
   System Settings → Autostart like any other start-up item.
2. **"Install DaVinci Resolve" in your apps.** Always there, whatever you
   answered. This is what makes "Not now" safe rather than a dead end.
3. **`ujust install-resolve`** in a terminal, for anyone who prefers that.

### What the installer actually does

1. Explains the situation and asks whether to carry on.
2. Looks at your graphics card and picks the right setup for it — NVIDIA cards
   and AMD/Intel cards need different graphics libraries.
3. Makes sure your account is allowed to talk to the graphics card (the `render`
   and `video` groups). If it had to add you, it tells you to restart at the end.
4. Opens Blackmagic's download page in your browser and waits for you to download
   the free Linux version into your Downloads folder. It finds the file itself,
   zipped or not.
5. Builds a **davincibox** — a sealed-off mini-Linux on your machine, sharing
   your home folder but with its own system libraries, holding everything Resolve
   needs. This is the well-established community solution for Resolve on
   Fedora-based systems like ours, and its maintainer lists Bazzite as officially
   supported. Nothing about your real system is changed.
   Source: <https://github.com/zelikos/davincibox>
6. Installs Resolve into it. It then shows up in your apps like anything else.
7. Ends by telling you the two things every Linux Resolve user finds out the hard
   way (below).

If anything fails, it says so and stops. Nothing is left half-installed, and
running it again is always safe.

### The two things about Resolve on Linux

Both are Blackmagic's decisions, and no operating system can change them from the
outside. Being straight about them is the point.

1. **The free version cannot open ordinary phone or camera MP4 files.** The video
   inside them uses H.264/H.265, which free Resolve on Linux has no licence for.
   AquariusOS's answer is the ingest helper (`docs/ingest-helper-spec.md`), which
   converts camera files into something Resolve imports perfectly.
2. **Even paid Resolve Studio imports MP4s with silent audio**, because the AAC
   audio format is missing on Linux in both versions. If you own Studio there is
   a free community plug-in that fixes it, and AquariusOS will install it for
   you:

   ```
   ujust install-resolve-aac-plugin
   ```

   Read what that recipe prints before saying yes. In short: it only works in
   Studio (the free version cannot load plug-ins at all); it is written by a
   third party and published with no licence attached, so AquariusOS does **not**
   ship it — your computer downloads it from GitHub if you ask; and the download
   is checked against a fingerprint written into the recipe before a single byte
   of it is used. We copy one file into place ourselves rather than running the
   project's own installer script, so nothing of theirs executes on your machine.
   Source: <https://github.com/Toxblh/davinci-linux-aac-codec>

Full background on all of this: `docs/codec-research.md`.

---

## Where everything lives

| Path in this repo | What it is |
|---|---|
| `build_files/creator-apps.sh` | The build step. Bakes in our apps, switches the Flatpak service on, adds our `ujust` recipes. |
| `build_files/build.sh` | Calls the above. One short section, nothing else. |
| `system_files/usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall` | The shopping list. **This is the file you edit to change which Flatpaks ship.** |
| `system_files/usr/lib/systemd/system/aquarius-flatpak-preinstall.service` | The thing that does the shopping, on boot. |
| `system_files/usr/libexec/aquarius-flatpak-preinstall` | What that service runs. |
| `system_files/usr/libexec/aquarius-resolve-offer` | The one-time Resolve pop-up. |
| `system_files/etc/xdg/autostart/aquarius-resolve-offer.desktop` | What starts the pop-up at login. |
| `system_files/usr/share/ublue-os/just/96-aquarius-creator.just` | The `ujust` recipes: `install-resolve`, `install-resolve-aac-plugin`, `install-creator-apps`. |
| `system_files/usr/bin/aquarius-editor`, `…-writer` | Small launchers. Typing the name, or clicking the icon, comes here. |
| `system_files/usr/share/applications/*.desktop` | The entries in the app grid. |

On the installed machine, the two Aquarius apps live in
`/usr/lib/aquarius/aquarius-editor/` and `/usr/lib/aquarius/aquarius-writer/`.

## How to change what ships

* **Add or remove a Flatpak:** edit the `.preinstall` list. Copy an existing
  block, change the ID to the one on the app's flathub.org page, keep
  `Branch=stable`. Check `https://flathub.org/apps/<the-id>` really loads first —
  a typo there fails silently.
* **Ship a newer Aquarius Editor or Writer:** change the version tag in
  `creator-apps.sh`. Nothing else.
* **Add another app of ours:** add a line to `AQUARIUS_APPS`, and add a launcher,
  a `.desktop` file and an entry to the check loop at the bottom of
  `creator-apps.sh`. The release must publish exactly one `.AppImage` and a
  `SHA256SUMS.txt` next to it.

## Known open items

* **Aquarius Writer v0.1.0 was still being built** when this was written
  (2026-08-28): the tag was pushed and the release job was running, so nothing
  was downloadable yet to check against. The wiring is complete and was proven
  end-to-end against the Editor's real release instead — same shape, same
  `SHA256SUMS.txt` convention, and the file name is read out of that file rather
  than written down here, so the Writer needs no edit when it lands. If a build
  fails with a clear "could not download the checksum file … the release does not
  exist yet" message, the release simply has not published; re-run the build.
* **Image size.** Unpacking the two apps is the single largest thing this adds.
  The exact figures are printed in the build log by `creator-apps.sh` — look for
  the `installed size:` lines.
* **Creator Mode** (the Gamer / Creator / Both first-boot chooser) is still to
  come. When it lands, the "Creator" choice should add to this list rather than
  replace the mechanism.
