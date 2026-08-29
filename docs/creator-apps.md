# The creator apps — what ships, and how it gets there

*Phase 2, Workstream A. Written 2026-08-28, revised the same day to the shape
below. Read this before changing which apps AquariusOS comes with.*

This is the part of AquariusOS that makes it a creator's operating system rather
than Bazzite with a new coat of paint. It is written for somebody who has never
used Linux. Nothing here assumes you know what a container or a systemd unit is.

---

## The one idea to hold on to

There are **three ways** an app can reach a user, and which one an app gets is a
real decision rather than an implementation detail.

| | Which apps | Why |
|---|---|---|
| **Baked in** | Aquarius Editor, Aquarius Writer | They are ours. They are on no app store. They are part of the OS in the same way the file manager is. |
| **Preinstalled** | Firefox, Google Chrome | A web browser is the one app a computer is unusable without. It should simply be there. |
| **Offered** | OBS Studio, Audacity, Blender, DaVinci Resolve | One tick-box window on the first login, everything already ticked. Saying yes to all of it is one click — but three gigabytes of 3D suite should still be somebody's decision. |

Nobody has to open a terminal for any of it.

Deliberately **not** included anywhere: Kdenlive, Obsidian, Ardour. Aquarius
Editor takes the slot Kdenlive was going to have and Aquarius Writer takes
Obsidian's; Ardour was cut as overlapping with Audacity for the audio a video
creator actually does. All three are one click away in the app store.

---

## Baked in: Aquarius Editor and Aquarius Writer

These are not on any app store — they are ours, released on GitHub. So when
GitHub Actions builds AquariusOS, the build downloads each app's Linux release,
checks it, unpacks it, and puts it inside the OS image. By the time you install
AquariusOS they are already there.

The build does this in `build_files/creator-apps.sh`. Three details worth
knowing:

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

---

## Preinstalled: the two browsers

A Flatpak is a self-contained app that updates on its own schedule, separately
from the operating system. That is exactly what you want for third-party apps: a
broken update to a browser can never stop your computer from starting.

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
[Flatpak Preinstall org.mozilla.firefox]
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
works. One app fails but the other installs? It says which one and tries that
one again the next time the computer starts — not every two minutes all day.
Once everything is present it writes a small note to
`/etc/aquarius/flatpak-preinstall-version` and never does any of this again.

**The user always wins.** Uninstall Chrome and it stays uninstalled — Flatpak
remembers that you removed a preinstalled app and does not put it back. That is
Flatpak's own behaviour and it matches how the rest of AquariusOS treats
defaults: we choose the starting point, you choose everything after that.

### Two notes on the browsers

**Firefox.** Stock Bazzite does ship Firefox — but from the USB stick, during
installation, which as explained above is a route AquariusOS does not use. So the
Firefox line in our list is what actually puts Firefox on an AquariusOS machine;
it is not a duplicate of something Bazzite already did. On a machine that came
from Bazzite and was switched over to us, Firefox is already installed and
Flatpak leaves it exactly as it is. Installing it **system-wide** also matters on
the NVIDIA edition: Bazzite's own start-up housekeeping sets Firefox's
hardware-video-decode environment with `flatpak override --system`, and those
settings only reach a system-installed Firefox.

**Google Chrome.** Google does not let anyone redistribute Chrome, so Flathub's
`com.google.Chrome` is a small wrapper that downloads Google's own installer from
`google.com` at install time. Flatpak calls this "extra-data". It works fine with
the preinstall mechanism — it is a normal install as far as Flatpak is concerned
— with one wrinkle worth knowing about: extra-data apps break if Google removes
an old build before Flathub updates its recipe, and then that one app fails to
install for a day or two. Our service is built for exactly that: it installs
everything it can and retries the straggler on the next start-up.

---

## Offered: the first-login window

On the first login, one window appears:

> **Set up your creator apps**
>
> AquariusOS can set these up for you now. They are the apps most people doing
> this kind of work end up wanting, and they are all ticked — clicking OK is the
> whole job. …
>
> * ☑ OBS Studio — record your screen and stream live
> * ☑ Audacity — record and tidy up audio and voiceovers
> * ☑ Blender — 3D modelling, animation and visual effects (about 3 GB)
> * ☑ DaVinci Resolve — professional editing and colour (guided setup)

Everything starts ticked, so the common case is one click. The script is
`/usr/libexec/aquarius-creator-apps-offer`.

**The tool is `kdialog --separate-output --checklist`.** kdialog is part of
Plasma, so it is guaranteed present on every AquariusOS machine — no new
dependency, nothing to compile, nothing to keep working across a decade of
Plasma releases. Its tick-box list is plain, so the plainness is handled in the
writing: each line carries its own short "what is this for", which is what a
beginner actually needs. `--separate-output` is the part that makes it safe to
read from a script — without it kdialog returns every choice on one line wrapped
in quotes, which then has to be unpicked; with it you get one plain tag per
line. It exits 0 for OK and 1 for Cancel.

**What happens on OK.** The chosen Flatpaks install in the background — the
script is already running in the background, so nothing is blocked and there is
no window to watch. Two desktop notifications (also kdialog, `--passivepopup`)
say when it starts and when it is done, or name anything that failed. They go in
**system-wide**, the same as the browsers, so every account on the machine gets
them and Bazzite's own system-wide Flatpak tweaks reach them; that is what the
one password prompt is for, and the window says so in advance. All the apps go
in as a single request, so the password is asked for once rather than once per
app; if that request fails, the script retries them one at a time so a single
awkward app cannot cost you the rest.

If **DaVinci Resolve** was ticked, its guided setup opens in a terminal window
*after* the Flatpaks, not alongside them — Resolve's setup needs your attention
and a large download of its own, and two big downloads plus a conversation at
once is a bad first five minutes.

**What happens on Cancel.** A small note is written to
`~/.config/aquarius/creator-apps-offered` and the question is never asked again.
Same if you press OK with everything unticked.

**It is never a dead end.** "Install Creator Apps" is in the app grid forever,
and re-opens exactly the same window (it runs the same script with `--again`,
which ignores the note). Anything already installed comes up **unticked**, so
re-opening the window offers you what you do not have rather than what you do.
`ujust install-creator-apps` does the same thing from a terminal.

**Guardrails**, unchanged from the first version: it never holds up the login (it
waits half a minute for the desktop to settle first), it never appears in the USB
installer session, and it can be switched off in System Settings → Autostart like
any other start-up item.

### Why there are two app-grid entries

There is an **"Install Creator Apps"** entry (the checklist) *and* a separate
**"Install DaVinci Resolve"** entry. That is deliberate, not a leftover:
"DaVinci Resolve" is the name people will actually type into the app search, and
somebody who wants only Resolve should not have to walk through a checklist to
reach it. They lead to the same place — the Resolve entry runs
`ujust install-resolve`, which is exactly what the checklist calls when Resolve
is ticked.

---

## DaVinci Resolve

Resolve is the app most professional editors and colourists expect to find. We
**cannot ship it**: Blackmagic's licence allows only Blackmagic to hand out the
installer. No trick gets around that, and nothing of Blackmagic's is anywhere in
this repository or in the OS image.

What AquariusOS ships instead is the shortest honest path to having it, reachable
three ways — the first-login checklist, the "Install DaVinci Resolve" app entry,
and `ujust install-resolve` — all of which run the same thing.

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
| `build_files/creator-apps.sh` | The build step. Bakes in our apps, switches the browser service on, checks the offer is wired up, adds our `ujust` recipes. |
| `build_files/build.sh` | Calls the above. One short section, nothing else. |
| `system_files/usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall` | The list of apps that arrive unasked. **Two browsers. Think hard before adding a third thing.** |
| `system_files/usr/lib/systemd/system/aquarius-flatpak-preinstall.service` | The thing that does that shopping, on boot. |
| `system_files/usr/libexec/aquarius-flatpak-preinstall` | What that service runs. |
| `system_files/usr/libexec/aquarius-creator-apps-offer` | **The first-login tick-box window**, and the installs it triggers. Takes `--again` to re-open on demand. |
| `system_files/etc/xdg/autostart/aquarius-creator-apps-offer.desktop` | What starts that window at login. |
| `system_files/usr/share/applications/aquarius-install-creator-apps.desktop` | "Install Creator Apps" — re-opens the window, forever. |
| `system_files/usr/share/applications/aquarius-install-resolve.desktop` | "Install DaVinci Resolve" — the direct route. |
| `system_files/usr/share/ublue-os/just/96-aquarius-creator.just` | The `ujust` recipes: `install-creator-apps`, `install-resolve`, `install-resolve-aac-plugin`. |
| `system_files/usr/bin/aquarius-editor`, `…-writer` | Small launchers. Typing the name, or clicking the icon, comes here. |
| `system_files/usr/share/applications/aquarius-{editor,writer}.desktop` | The entries in the app grid. |

On the installed machine, the two Aquarius apps live in
`/usr/lib/aquarius/aquarius-editor/` and `/usr/lib/aquarius/aquarius-writer/`.

## How to change what ships

* **Move an app between "offered" and "preinstalled":** the offer's list is the
  `ITEMS` array in `aquarius-creator-apps-offer`; the preinstall list is the
  `.preinstall` file. Both take the same Flathub app IDs. Check
  `https://flathub.org/apps/<the-id>` really loads first — a typo in the
  `.preinstall` file fails silently.
* **Ship a newer Aquarius Editor or Writer:** change the version tag in
  `creator-apps.sh`. Nothing else.
* **Add another app of ours:** add a line to `AQUARIUS_APPS`, and add a launcher,
  a `.desktop` file and an entry to the check loop in `creator-apps.sh`. The
  release must publish exactly one `.AppImage` and a `SHA256SUMS.txt` next to it.

## Known open items

* **The first-login window has not been seen on real hardware yet.** Everything
  around it is checked automatically, but "does this dialog read well on a 4K
  screen at 125% scaling, thirty seconds after a first login" is a question only
  a bench boot answers. That is part of the Phase 2 exit-test boot.
* **The password prompt** for the offered apps depends on KDE's polkit agent
  being up when the install starts. It normally is by then; if it is not, the
  install fails, the notification says so, and "Install Creator Apps" is right
  there to try again. Worth watching on the bench boot.
* **Machines that already ran the earlier version of this layer** (Royce's 4090
  bench) have OBS, Audacity, Firefox and Chrome installed system-wide from when
  all four were preinstalled. Nothing removes them, and that is correct — they
  are apps the owner has. Two follow-ons: those machines will see the new offer
  with OBS and Audacity already unticked, and the old
  `~/.config/aquarius/resolve-offer-answered` note is now ignored, so a Resolve
  question answered before will be asked once more inside the new window. That is
  deliberate; it is a different question now.
* **Removing apps from the `.preinstall` list is not purely cosmetic.**
  `flatpak preinstall` *synchronises*: anything it installed and that later stops
  being listed is a candidate for removal the next time something runs it. Today
  nothing on Bazzite runs `flatpak preinstall` except our own service, so
  dropping OBS and Audacity from that list does not uninstall them from anybody.
  If Bazzite's app store ever starts running it, that could change — and the fix
  is one click on "Install Creator Apps".
* **Image size.** Unpacking the two Aquarius apps is the single largest thing
  this adds. The exact figures are printed in the build log by
  `creator-apps.sh` — look for the `installed size:` lines.
* **Creator Mode** (the Gamer / Creator / Both first-boot chooser) is still to
  come. When it lands, the "Creator" choice and this window are obviously the
  same conversation and should become one screen, not two.
