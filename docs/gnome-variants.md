# The GNOME line — what changed, what ships, and what is still to come

*Written 2026-08-31, when the three GNOME images were added. Nothing here has been booted
yet; the "what still needs a real machine" section at the end says so honestly and lists
what has to be checked when one is available.*

---

## The short version

AquariusOS used to be one desktop: **KDE Plasma**. On 2026-08-31 Royce changed it to
**GNOME**. Rather than delete a month of KDE work on the same day, both are being built
side by side for a while:

| | The KDE line | The GNOME line |
|---|---|---|
| Images | `aquarius-os`, `-nvidia`, `-deck` | `aquarius-os-gnome`, `-gnome-nvidia`, `-gnome-deck` |
| Status | **Frozen** | **Where all new work goes** |
| Still built? | Yes, every run | Yes, every run |
| New features? | No | Yes |

**Frozen** means exactly what it says: those three images are still built and published
every night, so a machine that already has one installed keeps getting updates and keeps
working. But nothing new lands on them. They retire when the GNOME line is good enough to
live on every day.

---

## Why the change

The KDE line was rebuilding a lot of GNOME by hand. Six weeks of it went into a slim top
bar, a floating dock, a clock with a notifications panel, a Quick Settings menu, and a
rounded-window plug-in compiled from source — every one of which is a thing GNOME simply
*has*, and has had for years.

The KDE work is real and it works. It is also a treadmill: each of those pieces is a fork
or a copy of something KDE owns, and every Plasma release is a chance for one of them to
quietly stop loading. The blur effect never worked at all
([`blur-known-issue.md`](./blur-known-issue.md)) and cost days before it was cut.

The decision was to stop rebuilding and start decorating. Which brings us to the posture.

---

## The posture: work with GNOME's grain

This is the rule that decides every argument on the GNOME line, so it is worth stating
plainly.

**We change what GNOME lets us change through settings, and we do not repaint the desktop.**

In practice:

| We do | We do not |
|---|---|
| Set the accent colour | Ship a GTK theme |
| Ship a wallpaper | Ship a GNOME Shell theme |
| Set the fonts | Patch libadwaita |
| Pick which extensions are on | Compile our own shell extensions |
| Add a dock | Rebuild the top bar |

Every one of those "do nots" is a thing that would look better for about four months and
then break on a GNOME release, at which point somebody has to fix it or the desktop is
broken. A setting cannot break that way. That is the whole argument.

**libadwaita in particular is never patched.** libadwaita is the library that draws almost
every window on a GNOME desktop. Patching it to get an exact brand colour would mean owning
a fork of the single most important library on the machine, forever, and rebuilding it on
every security update. The cost of not doing it is that our accent is GNOME's `blue`
(`#3584e4`) rather than Aquarius Blue (`#2C8FC4`) — a shade off, on a colour most people
would not be able to tell apart side by side. That is a good trade and it is not open for
re-litigation.

---

## The colours: Ice, and Midnight

AquariusOS on GNOME is **light first**. That is unusual — almost no Linux desktop leads
with a light theme — and it is the point.

The palette is **Ice**, taken from Aquarius Writer: cool azure-tinted papers with deep-navy
ink. Its designed dark twin is **Midnight**: deep-ocean navy grounds with ice-blue ink, so
the electric aquas read like light under water. Somebody who prefers dark flips one switch
in Settings and gets Midnight, wallpaper included.

The raw values are recorded in `docs/custom-de/ice-theme-tokens.md` on the
`research/custom-de` branch. The wallpaper sources that use them are
`branding/wallpapers/the-pour-ice.svg` and `the-pour-midnight.svg`.

> The KDE line's identity is the older "Flow State" — near-black `#06070C` with Starlight
> blue. That is a genuinely different colour identity, not a darker render of this one, and
> its wallpaper (`branding/wallpapers/the-pour.svg`) is deliberately untouched.

---

## How our settings actually reach the desktop

This is the part most worth understanding, because it works differently from the KDE line
and the difference is invisible until something goes wrong.

### The mechanism, in plain English

GNOME keeps every setting on the machine in one database. Each setting has a **factory
value**, and a small text file can change what that factory value is. Those files live in
`/usr/share/glib-2.0/schemas/` and end in `.gschema.override`.

Ours are, in the order they are read:

| File | What it sets |
|---|---|
| `zz1-aquarius-10-look.gschema.override` | Light mode, blue accent, the three fonts, both wallpapers |
| `zz1-aquarius-20-shell.gschema.override` | The apps in the dock, and which extensions are on |
| `zz1-aquarius-30-dash-to-dock.gschema.override` | How the dock behaves |
| `zz1-aquarius-40-handheld.gschema.override` | One extra extension — **handheld image only** |

Three things about this that are easy to get wrong:

1. **The files do nothing until the index is rebuilt.** GNOME reads a compiled index, not
   the text files. Dropping a file in and doing nothing else changes nothing at all, with
   no error anywhere. `build_files/gnome-desktop.sh` rebuilds the index as its very last
   step, which is why that step is last.

2. **The name has to start with `zz1`.** All the files in that folder are read in
   alphabetical order and the last one to mention a setting wins. Bazzite ships its own
   defaults in files starting `zz0-`. `zz1` sorts after all of them, so we get the last
   word on the handful of things we care about and Bazzite keeps the last word on
   everything else — which is what we want, because their file is full of good gaming
   decisions we have no reason to re-make. Renaming ours to sort earlier would silently
   turn all of this off.

3. **`enabled-extensions` is a complete list, not an addition.** Whatever we write there
   replaces Bazzite's list entirely. There is no "inherit and add". So the list has to be
   written out deliberately, and anything of theirs left off it is switched off.

### How that differs from the KDE line

On KDE we ship a folder of settings files and put it on Plasma's own search path, so KDE
reads our answers as one more layer underneath the user's. On GNOME there is no such
cascade — there is one database, and we change what "untouched" means inside it.

**What the two have in common is the only part that matters: a person's own choice always
wins.** Nothing we ship is a lock. The moment somebody picks a different wallpaper or turns
dark mode on, their answer is written into their own settings and it beats ours forever
after.

---

## The extensions we ship, and the ones we deliberately do not

Bazzite's GNOME images already install a good set of extensions and switch most of them on.
Because our list replaces theirs, every name had to be a decision. Here it is.

### Kept from Bazzite

| Extension | Why |
|---|---|
| **appindicatorsupport** | Lets older apps put an icon in the top bar. Without it several creator tools — Steam included — lose their tray icon completely. |
| **gsconnect** | Phone pairing: notifications, file send, clipboard. Genuinely useful and hard to replace. |
| **caffeine** | Stops the screen sleeping. On a machine that exports video for an hour at a time this is not a nicety. |
| **hotedge** | Moves GNOME's "throw the pointer at the corner" gesture down to the bottom edge. Suits a desktop with a dock at the bottom, which ours has. |
| **logomenu** | The distro menu at the top left. It shows the OS logo, which on our images is ours. |
| **add-to-steam** | Right-click any app, add it to your Steam library. Pure Bazzite gaming value. |
| **restartto** | Restart into another OS or the BIOS from the power menu. The dual-boot gaming PC wants this. |
| **bazaar-integration** | Wires the shell up to Bazaar, the app store Bazzite ships. |

### Added by us

**Dash to Dock** — the dock itself. GNOME's own dash only exists inside the Activities
overview; this puts it on the desktop, along the bottom, always visible, centred. Bazzite
does not ship it, so `build_files/gnome-extensions.sh` bakes it in from a pinned,
checksummed release.

### Deliberately off (all still installed — just not switched on)

| Extension | Why not |
|---|---|
| **blur-my-shell** | Frosted-glass panels. Against the posture, and we have history: the KDE line spent days on window blur that never rendered and the design's transparency was removed on 2026-08-30 because of it ([`blur-known-issue.md`](./blur-known-issue.md)). Not walking back into that. |
| **compiz-alike-magic-lamp-effect** | The "genie" minimise animation. A novelty that costs frames on every minimise. |
| **burn-my-windows** | Window open/close special effects. Same reasoning. (Bazzite installs it but does not switch it on either.) |
| **desktop-cube** | Spinning 3D workspace switcher. Same reasoning. |
| **user-theme** | Not an effect — it is the switch that lets a custom GNOME Shell theme be applied, and Bazzite uses it to apply one of their own. We ship no shell theme and do not intend to; a shell theme is exactly the kind of thing that breaks on every GNOME release. With this off, the shell is stock Adwaita wearing our accent and our wallpaper, which is the look we want. Anyone who disagrees can switch it back on in the Extensions app. |

### One extra on the handheld

**block-caribou-36**, which stops GNOME's on-screen keyboard fighting Steam's. Two
on-screen keyboards over one text box is worse than either alone. It ships in
`zz1-aquarius-40-handheld.gschema.override`, which exists on the handheld image and is
deleted from the other five.

---

## Everything else that changed

### The dock

Dash to Dock, pinned to release `extensions.gnome.org-v106` (commit `a7b1981`, SHA-256
recorded in `build_files/gnome-extensions.sh`). Bottom, always visible, sized to its icons
so it floats in the middle rather than stretching edge to edge, 48-pixel icons.

The one subtle thing: it is installed **system-wide**, which means its settings description
goes into `/usr/share/glib-2.0/schemas/` and it keeps no private compiled copy of its own.
That is not tidiness — an extension with a private copy reads that first and ignores every
default we set, so the dock would come up stock and nothing would say why. Both the build
script and the CI step check that the private copy is absent.

### Dialogs and the terminal

Our own scripts ask questions with a window. On KDE that is `kdialog`; on GNOME it is
`zenity`. Four scripts now pick between them at run time by reading `XDG_CURRENT_DESKTOP`,
keeping the other as a fallback:

- the first-login "set up your creator apps" tick-box window
- the "that app could not start" error dialog
- the "Resolve is not set up yet" message
- the Resolve setup's "keep waiting or stop?" dialog

Notifications go through `notify-send`, which works on both. The terminal the Resolve setup
opens follows the same rule: `xdg-terminal-exec` first on GNOME (which lands on Ptyxis,
Bazzite's GNOME terminal), `konsole` first on KDE.

Nothing about the KDE behaviour changed — it reaches for the same tools in the same order
with the same words.

### "Make Editor-Ready" in Files

The right-click menu item that runs `aq-ingest` exists on both desktops, as two completely
different kinds of file:

- **KDE:** `system_files/usr/share/kio/servicemenus/aquarius-make-editor-ready.desktop` — a
  settings file. KDE reads it and builds the menu itself.
- **GNOME:** `system_files/usr/share/nautilus-python/extensions/aquarius_editor_ready.py` —
  a small Python program, because GNOME has no settings-file way to add a menu item.

Both ship on both images; neither desktop reads the other's. They run the same command on
the same kinds of file, and `ingest/tests/test_desktop.py` compares them so they cannot
drift apart.

### The login screen

The two GNOME **desktop** images put the AquariusOS logo on the GDM login screen, using
GNOME's own documented recipe (`/etc/dconf/profile/gdm` plus `/etc/dconf/db/gdm.d/`).

The GNOME **handheld** does not, and that is not an oversight: Bazzite's handheld images
use SDDM rather than GDM, even the GNOME ones, because SDDM is what Valve's Game Mode
session is wired into. Writing GDM settings there would be writing a file nothing reads.

### Editions on the About page

While both lines are published, "Desktop Edition" on its own would be ambiguous, so the
GNOME images say "GNOME Desktop Edition", "GNOME NVIDIA Edition" and "GNOME Handheld
Edition". The three KDE strings are unchanged, because an installed machine's About page
should not start saying something new.

---

## How the two lines stay apart in one recipe

There is exactly **one** new branch in the whole build: a build argument called
`AQ_DESKTOP` that holds either `kde` or `gnome`. It defaults to `kde`, so every older
command line still produces exactly what it always did.

The Justfile works it out from the variant name (`just variant-desktop gnome-deck` → `gnome`),
the Containerfile passes it in, and `build_files/build.sh` reads it. Everywhere it is used
says out loud why that step belongs to one desktop.

**Skipped on GNOME:**

| Step | Why |
|---|---|
| `kwin-effects.sh` | Compiles a KWin plug-in. A GNOME image has no KWin — this would not be a no-op, it would be a red build. GNOME rounds its own window corners. |
| `plasma-style-version.sh` | Version-stamps a Plasma style. GNOME has no such object. |
| `kdeplasma-addons` | A bag of Plasma widgets, plus the chunk of KDE behind them. |
| The four Plasma widget checks | They look for KDE libraries a GNOME image genuinely does not have. |
| The KWin handheld settings | A `kwinrc`, which nothing on GNOME reads. |
| KDE's About-page override file | Read by KDE's Info Centre and nothing else. |

**Removed from KDE:** everything in the GNOME layer — the four settings files, the two
wallpapers, the wallpaper listing, the Nautilus extension, the login-screen logo. They are
copied onto every image by the shared `system_files/` step and then deleted again, which is
the same ship-and-un-ship arrangement the handheld settings have used since 2026-08-28: the
files are always in the repo, always reviewed, always in one place, and the only
image-specific thing is one `rm`.

Would leaving them on a KDE image hurt? Almost certainly not. But "frozen" has to mean
something, and a frozen image should contain exactly what it contained yesterday — not "a
few harmless extra files".

**Nothing KDE was deleted.** The Plasma widgets, the layout script, the Plasma style and
the KDE service menu all still ship on the GNOME images. They are plain files that GNOME
never opens. Tidying them away is a job for the day the KDE line retires, not for the day
the GNOME line starts.

---

## What still needs a real machine

**None of this has been booted.** GitHub Actions proves the images build and that every
file is where it should be; it cannot prove the desktop looks right, because there is no
desktop inside a build container. When an x86 machine is available:

- [ ] Does it come up **light**, with the Ice wallpaper?
- [ ] Is the accent blue, and are the fonts Inter and JetBrains Mono?
- [ ] Is the dock at the bottom, centred, and does it stay put when a window is maximised?
- [ ] Switch to dark in Settings — does the wallpaper change to Midnight?
- [ ] Is our wallpaper listed in Settings > Appearance?
- [ ] Is the AquariusOS logo on the login screen?
- [ ] Right-click a folder of clips in Files — is "Make Editor-Ready" there, and does it work?
- [ ] Does the first-login creator-apps window appear, and does it look like a GNOME window?
- [ ] `gnome-extensions list --enabled` — is it the nine we listed, and nothing else?
- [ ] On the handheld: does it still boot into Game Mode, and does the desktop button land in GNOME?

---

## What is deferred, and to when

### G2 — the things that need a booted machine to design

| Item | Why it is not in G1 |
|---|---|
| **Drives on the desktop** | The KDE line puts every mounted drive on the desktop, macOS-style (`docs/drives-and-desktop-icons.md`). GNOME has no desktop icons at all out of the box; doing this needs the Gtk4 Desktop Icons NG extension, and how it behaves next to Dash to Dock and with our automounter is a question that can only be answered by watching it. Until then, drives show up in the dock and in the Files sidebar. |
| **A first-run chooser** | The Gamer / Creator / Both choice has been designed since Phase 2 and still has no mechanism. GNOME's own first-run tour is a candidate. |
| **Login-screen scaling, re-tested** | `aquarius-greeter-scale` fixes an enormous login screen on a 7-inch handheld by writing a KWin config. On a GNOME image nothing reads that file. Whether GDM (or SDDM, on the handheld) has the same problem, and what the fix is, has to be measured on the Ally rather than guessed. |
| **Controller navigation on the GNOME handheld** | The KDE handheld turns the game controller into a mouse and keyboard through a KWin setting — the only way to use an Ally with nothing plugged in. GNOME has no equivalent setting. Needs real investigation: whether Bazzite's handheld daemon already covers it, whether an extension does, or whether this is a genuine gap. **Until this is answered, treat the GNOME handheld's desktop mode as keyboard-and-mouse only.** |
| **The GNOME live installer session** | `installer/titanoboa_hook_postrootfs.sh` dresses the USB installer session and parts of it are written for Plasma — including the on-screen keyboard for the handheld installer, which on a GNOME live image writes a file nothing reads. Nobody has booted a GNOME ISO yet. There is a loud TODO on the step in `build-iso.yml`. |

### G3 — the cut-over

The day the GNOME line is daily-drivable:

1. Flip the ISO workflow's default variant from `base` to `gnome`.
2. Rename the images so `aquarius-os` *is* the GNOME one, and give the frozen KDE images a
   suffix of their own. (This is the awkward step: `aquarius-os` is an installed machine's
   update address, so it needs a written migration note, not just a rename.)
3. Point the README, GETTING-STARTED and the docs at the GNOME line as the default.
4. Announce a retirement date for the KDE images.
5. Only then delete the Plasma widgets, the layout script, the Plasma style and the KWin
   effect build — all at once, in one commit, after the images stop being published.

---

## The files, if you are going looking

| File | What it is |
|---|---|
| `aquarius-os.env` | The three GNOME image names and their three Bazzite bases |
| `Justfile` | `variant-image-name`, `variant-base-image`, `variant-desktop` |
| `Containerfile` | The `AQ_DESKTOP` build argument, and the note on why it is the only branch |
| `build_files/build.sh` | Every gated step, and the GNOME/KDE fork near the end |
| `build_files/gnome-extensions.sh` | The Dash to Dock bake — pin, checksum, and the system-wide install |
| `build_files/gnome-desktop.sh` | Packages, handheld trim, GDM logo, and the settings compile |
| `system_files/usr/share/glib-2.0/schemas/zz1-aquarius-*` | The four settings files |
| `branding/wallpapers/the-pour-ice.svg`, `-midnight.svg` | The wallpaper sources |
| `branding/render-wallpaper.sh`, `render-logo-png.sh` | How the PNGs are made |
| `.github/workflows/build.yml` | The six-variant matrix and the "Verify the GNOME desktop layer" step |
