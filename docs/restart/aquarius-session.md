# The Aquarius Desktop — our own desktop, on the login screen

*Written 2026-09-03, for Phase R2. Assumes you have never used Linux.*

---

## In one paragraph

AquariusOS now has **two desktops**. GNOME is the one you have been using: a
good, finished, ordinary desktop, dressed in Aquarius colours. The **Aquarius
Desktop** is ours — a top bar, a dock, a search palette, quick settings and
notifications that we wrote, running on a small window manager called labwc.
Both appear at the login screen. You pick one, you log in, and if you do not
like it you log out and pick the other. Nothing about GNOME changed, and nothing
can take it away.

---

## ⚠️ One thing is waiting on you, Royce

**The shell repository is private, and that is the only reason the bar might not
appear.**

The Aquarius Shell lives at `github.com/stoneharborent/aquarius-shell`. The
machine that builds AquariusOS has no GitHub account — it can read a *public*
repository and nothing else — and there is deliberately no password or token in
the build, because a secret handed to a container build gets recorded inside the
finished image where anybody who downloads AquariusOS could read it.

So while that repository is private, every build finishes **without** the shell.
The image is still good: the window manager, the wallpaper, the keyboard
shortcuts, screen recording, the login-screen entry are all there. Picking
"Aquarius Desktop" gives you a wallpaper and a dialog explaining that the bar is
not installed yet and how to get back to GNOME. Nothing is hidden — the build
log says it, the CI run says it, and the machine itself says it in
`/usr/share/aquarius/shell-build.txt`.

**The fix is four clicks and no code:**

1. Go to `github.com/stoneharborent/aquarius-shell`
2. **Settings** → **General**
3. Scroll to **Danger Zone** → **Change visibility** → **Make public**
4. Push anything to the AquariusOS repository, or re-run the last build

The next image bakes the shell in. Not one file in the OS recipe changes — it
already knows how to fetch it, and it already knows which exact commit to take.

*(The reason it must be public rather than token-protected: a token would work
for the test job, which runs on GitHub's own machines, but not for the image
build, which happens inside a container that must never carry a secret.)*

To check which state a machine is in:

```bash
cat /usr/share/aquarius/shell-build.txt
```

`status=installed` means the bar is there. `status=unavailable` means it is not,
and the file says why.

---

## Picking it

1. Log out, or start the computer.
2. At the login screen, **click your name first**. The session chooser only
   appears once a user is selected.
3. Look for a small **gear icon**, usually at the bottom-right of the screen
   near the "Sign In" button.
4. Click it. You will see:
   - **GNOME** — where you are today
   - **GNOME on Xorg** — an older way of running GNOME; ignore it
   - **Aquarius Desktop** — ours
5. Pick **Aquarius Desktop**, type your password, sign in.

GDM remembers your choice, so the next login goes straight there. Changing back
is the same four clicks.

---

## What you will see

A wallpaper, and along the top of the screen a thin bar in the Ice light theme:
the Aquarius mark on the left, the name of whatever window you are using next to
it, and on the right a cluster of small status glyphs — network, sound, battery
— and a clock.

A dock, centred along the bottom.

And these keys:

| Key | What it does |
| --- | --- |
| **Super + Space** | Opens the search palette. Type to find an application, do a sum, or reach a session action like Log Out. Escape closes it. |
| **Super + Return** | A terminal. This is the escape hatch — it works even when nothing else does. |
| **Super + Shift + E** | Leaves the Aquarius Desktop and returns you to the login screen. |
| **Alt + Tab** | Switch windows. |
| **Alt + F4** | Close a window. |
| **Super + arrow keys** | Snap a window to half the screen. |

"Super" is the key with the Windows logo on it, or Command on an Apple keyboard.

Clicking the status glyphs at the top-right opens **Quick Settings**: Wi-Fi,
Bluetooth, volume, brightness, a Focus toggle. Clicking the clock opens the
**notification panel**.

### How big it all is

The bar and the dock ship at the size Royce approved on the bench on 3 September
2026, looking at a 55-inch 4K monitor: everything 1.25 times the original design,
and the dock 1.5 times. The dock is deliberately the odd one out — you *read* a
bar and you *aim at* a dock, and a click target across a big desk wants to be
bigger than the text beside it.

If you want it a different size anyway, that is one command and a log out:

```
aq display ui 1.15     # smaller
aq display ui 1.4      # bigger
aq display ui 1        # back to the design as shipped
```

That knob moves **only the Aquarius bar and dock**. Making *everything* on the
screen bigger — your browser, Resolve, all of it — is the screen scale, which is
`aq display scale` and a different thing entirely. `aq display status` shows
both; on a machine nobody has changed it says `ui=1.0`.

### What language it speaks

The session sets `LANG` before anything starts, because a bare Fedora image can
hand a login session no language at all — and a program with no language falls
back to a character set from 1968 that cannot draw an accented letter.

It looks in this order: your own `~/.config/locale.conf`, then a UTF-8 language
the login screen already gave it, then the system's `/etc/locale.conf` (which
AquariusOS ships as `LANG=en_US.UTF-8`), and if none of those answer, `C.UTF-8`
— which is not a language, but is at least a modern character set. Whatever it
picks is checked against the languages actually installed, and the session log
says which one it used and why.

To change the machine's language: `localectl set-locale LANG=de_DE.UTF-8`, plus
`rpm-ostree install glibc-langpack-de` for the language's data. For yourself
only, put `LANG=` in `~/.config/locale.conf`.

---

## If it does not work

**This is the important section, so it is near the top rather than the bottom.**

### The rule

> If the Aquarius Desktop breaks, press **Super + Shift + E**, and at the login
> screen pick **GNOME**. Everything works exactly as it did before. Nothing has
> been damaged and nothing needs repairing.

That is the whole safety story, and it does not bend. GNOME is installed
permanently, it is never modified by any of this, and it does not share a single
setting with the Aquarius Desktop.

### If the bar does not appear but the wallpaper does

You will get a dialog explaining it, because that is what
`/usr/libexec/aquarius-shell-start` exists to do. **Read it** — it says which of
the two things happened:

- **"The Aquarius Shell is not installed yet"** — the shell was not in this
  build. See the section at the top of this page; it is four clicks to fix, then
  a rebuild. Nothing is wrong with your machine.
- **"The Aquarius bar could not start"** — the shell is there and it crashed.
  Either press **Super + Return** for a terminal and type `qs` to start it again,
  or press **Super + Shift + E** and log in with GNOME.

### If you get a black screen and go straight back to the login screen

The session failed before it drew anything. Log in with **GNOME**, open a
terminal, and read:

```
cat ~/.local/state/aquarius-session/session.log
```

It contains the whole story of the attempt: what was found, what was missing,
and a loud block of text explaining what went wrong. The previous attempt is
kept as `session.log.1`, which is enough to compare a login that worked against
one that did not.

That file is the first thing to look at, always.

---

## Switching between GNOME and the Aquarius Desktop

**This should just work, in both directions, first time.** Log out of one, pick
the other at the login screen, and it starts. If it takes two or three attempts,
something is wrong and this section is the one to read.

### The bug this section exists for

On the bench on **2026-09-04**, Royce reported it in one sentence:

> "When logging out of Aquarius to go to GNOME, it kicks me back to the login
> screen a couple of times before letting me log in."

That is fixed. Here is what was happening, because understanding it is what
stops it coming back.

When you log in, Linux starts a personal background manager for you. It is
yours, not any one desktop's, and it outlives a logout. Think of it as a
noticeboard plus a few running helpers.

The Aquarius Desktop pins things to that noticeboard on purpose — "the screen is
called wayland-0", "this desktop is called Aquarius", and a handful more.
Everything started later reads them, so it knows where it is. Every Wayland
desktop does this, GNOME included.

**The bug was that nobody ever rubbed the noticeboard out again.** So you logged
out, and left behind notes pointing at a screen that no longer existed, a note
telling the screen-recording system to use a back end that only works with our
window manager, and — worse — programs still running and still believing all of
it: the Aquarius bar, the wallpaper, the keyboard remapper, the recording
portal.

GNOME then started and could not do its job. It could not take the name that
every notification on the machine is delivered to, because our bar still had it.
Its portals were already running and pointed at a compositor that had died. Its
own start-up waited for things that were never going to answer, timed out, and
gave up — and GDM does exactly one thing when a session gives up while starting:
it puts the login screen back. Try again, same leftovers, same failure. Only
once the stragglers had been killed off by their own timeouts, a minute or so
later, was the machine clean enough for GNOME to start.

### What happens now when you log out

`man systemd.special` says a desktop must do two things when its session ends:
stop `graphical-session.target`, and **unset the variables it set**. We were
doing the first and had never done the second.

**And GNOME? Not what you would guess.** This was checked in gnome-session's own
source on 2026-09-04 rather than assumed, because the assumption was wrong.
GNOME does not clean up when it stops either — there is no clean-up on shutdown
in it at all. What it does is clean up when it **starts**: at login it tells
systemd to throw away `DISPLAY`, `XAUTHORITY`, `WAYLAND_DISPLAY`,
`WAYLAND_SOCKET` and a few GNOME-only variables before setting its own. In other
words GNOME protects *itself* on the way in and leaves its own mess for whoever
comes next.

Two things follow, and AquariusOS now does both:

- **We clean up on the way out.** It is what the rule actually asks for, and
  nothing of ours — `QS_CONFIG_PATH`, `AQ_LOG`, `AQ_UI_SCALE`,
  `XDG_SESSION_DESKTOP` — is anywhere on GNOME's list, so GNOME would never
  clear it for us however long we waited.
- **We also protect ourselves on the way in**, the same way GNOME does and on
  the same variables. A session that is force-killed never gets to run its
  clean-up, and a desktop that only starts properly when the last one shut down
  tidily is not actually fixed.

So `/usr/bin/aquarius-session` now stays alive for the few seconds after the
window manager exits and runs a clean-up, in this order:

1. **Stop the services** — the keyboard remapper, all four portal back ends,
   `labwc-session.target` and `graphical-session.target`.
2. **Wait, but not forever** — up to ten seconds for the graphical session to
   really be over. A stuck service must not turn a logout into a hang, so after
   ten seconds it stops waiting and moves on.
3. **Remove the settings** — this is the actual fix:
   `XDG_SESSION_TYPE`, `XDG_SESSION_DESKTOP`, `XDG_CURRENT_DESKTOP`,
   `QS_CONFIG_PATH`, `QT_QPA_PLATFORM`, `AQ_LOG`, `AQ_UI_SCALE`,
   `WAYLAND_DISPLAY` and `DISPLAY`.
   **`LANG` is deliberately left alone** — it is a fact about which language you
   read, not about which desktop you were in, and removing it would walk
   straight back into the 2026-09-03 bug where everything fell back to a 1968
   character set.
4. **Close anything still running** — `qs`/`quickshell` (the bar),
   `swaybg` (the wallpaper), `xremap-wlroots` and `xremap-gnome` (the keyboard
   remapper), `slurp`, and `xdg-desktop-portal-wlr`. Each is asked politely
   first, given three seconds, and only then forced. This is necessary because
   **Linux does not kill your programs when you log out** — Fedora ships
   `KillUserProcesses=no`, which is a good default (it lets a long build survive
   a logout) and means these are ours to tidy up.
5. **Clear the failure marks**, so the next login does not inherit a service
   systemd has decided to stop retrying.

The clean-up is armed with a `trap`, which means it runs on **every** way out —
the normal Super+Shift+E, a crash of the window manager, or the login screen
ending the session. Not "if we remember to call it", which is the version that
quietly does not run on the path that mattered.

You can watch it happen. The last few lines of
`~/.local/state/aquarius-session/session.log` are the clean-up talking, and they
begin `[logout]`:

```
[logout] cleaning up so the next login starts fresh
[logout] stopping the desktop's background services
[logout] the graphical session has stopped
[logout] forgetting this desktop's settings: XDG_SESSION_TYPE ...
[logout] asked these to close: qs swaybg
[logout] done — GNOME or Aquarius will start from a clean slate
```

**Logging out takes about three seconds longer than it used to.** That is the
polite pause in step 4, and it is deliberate: three seconds once is a much
better trade than a login that fails twice.

### The same problem in the other direction

GNOME leaves its portals running when you log out of it, just as we used to. Somebody coming here straight from GNOME would find a portal already
awake and still convinced it is in GNOME — so it ignores
`aquarius-portals.conf` entirely, and OBS shows an empty list of screens with no
error anywhere.

So the Aquarius session stops the portals at the **start** of a login too, from
`/usr/libexec/aquarius-session-portals`, run at the end of the window manager's
`autostart` file. That costs nothing: portals are started on demand, so the next
one to start is a fresh one that reads our settings.

### The bench check

Do this twice each way. It takes two minutes and it is the only real proof.

1. Log in to **Aquarius Desktop**. Log out with **Super + Shift + E**.
2. At the login screen pick **GNOME**. It must log in **first time** — no bounce
   back to the greeter.
3. Log out of GNOME. Pick **Aquarius Desktop**. It must log in **first time**.
4. **Do steps 1–3 again.** Once could be luck; the original bug was intermittent
   in exactly that way.
5. While in Aquarius after a round trip, check screen recording still works:
   open OBS, add a *Screen Capture (PipeWire)* source, and confirm you get the
   dimmed "which screen?" overlay rather than an empty list. That is the check
   that proves the portals were really refreshed rather than inherited.

**If it still bounces**, these two commands say why. Run them from GNOME right
after a failed attempt, while it is fresh:

```
journalctl --user -b --since "-15 min" | grep -iE "fail|error"
journalctl -b -u gdm
```

The first is your own session's story — look for a service that timed out or a
name that could not be taken. The second is the login screen's own account of
what it tried to start and why it gave up. Send both, plus
`~/.local/state/aquarius-session/session.log`, which should end with the
`[logout]` lines above. **If those `[logout]` lines are missing, the clean-up
never ran**, and that is a completely different problem from the clean-up
running and not being enough.

One more, worth knowing: `systemctl --user show-environment` prints the
noticeboard. Run it in GNOME after logging out of Aquarius. It must **not**
mention `Aquarius`, and `WAYLAND_DISPLAY` must be GNOME's screen rather than a
leftover. That single command is the shortest possible proof that the fix is
working.

---

## What it is made of

Four pieces. Two of them AquariusOS compiles itself, which is unusual and worth
understanding.

| Piece | What it is | Where it comes from |
| --- | --- | --- |
| **labwc 0.20.2** | The window manager. Draws title bars, moves windows, owns the keyboard shortcuts. | **Compiled during the build.** Fedora 44 packages 0.9.6. |
| **Quickshell 0.3.1** | The runtime that runs our QML and gives it a bar's powers. The command is `qs`. | **Compiled during the build.** Fedora packages a 0.2.1 snapshot. |
| **The Aquarius Shell** | Our own code: bar, dock, search, quick settings, notifications. | Fetched at a pinned commit from `github.com/stoneharborent/aquarius-shell`. |
| **The session plumbing** | The launcher, the login-screen entry, the labwc configuration, the portal configuration. | Written in this repository, under `system_files/`. |

### Why we compile labwc ourselves

labwc 0.20 is the release that added **HDR10 and colour management**. Those two
things are the entire reason this project uses labwc rather than the
scrollable-tiling alternative it also evaluated. A colour-accurate desktop is
the point of a machine built for a video editor, and Fedora 44's labwc 0.9.6
does not have it.

Fedora 45 has 0.20 already (in Rawhide). When AquariusOS moves to Fedora 45 this
whole compile step is deleted and replaced with one line.

**One thing that is checked twice, on purpose:** whether labwc can run X11-only
software. That is what DaVinci Resolve needs, and on 3 September the build
produced a labwc without it — one library was missing, the build printed a
single warning in the middle of a thousand lines, and carried on. The image
would have published. Both the build and the finished image now read labwc's own
report of itself and refuse to go on unless it says `+xwayland`. You can read
that report yourself:

```bash
labwc --version
```

It should say `labwc 0.20.2 (+xwayland +nls +rsvg +libsfdo) wlroots-0.20.2`.

### Why we compile Quickshell ourselves — and the evening it cost

Two reasons. The small one: the shell uses two Quickshell modules
(`Networking` and `Bluetooth`) that do not exist in 0.2.1, so the Wi-Fi and
Bluetooth tiles would simply be missing.

The large one is worth reading once, because it explains a whole class of
problem on this kind of operating system.

On 2 September 2026 the session was tried on the bench for the first time. The
window manager started. The bar did not. There was no error message anywhere.
Eighteen minutes went into working out whether anything had happened at all.

What had happened: `quickshell` had been *layered* onto the machine — installed
on top of the image — and the version Fedora had built was compiled against a
**newer Qt** than the one inside our image. AquariusOS is an atomic system: the
Qt in the image cannot be changed by installing something over it. So the
layered program asked the image's Qt for functions it did not have and died on
its first instruction:

```
qs: symbol lookup error: qs: undefined symbol: ... version Qt_6
```

Building Quickshell **inside** the image, against the image's own Qt, makes that
impossible by construction: the two are compiled together and shipped together
and can never drift apart. That is standing decision 2c.

**One practical consequence:** never `rpm-ostree install quickshell` on an
AquariusOS machine. The image already has one, and a layered copy will shadow it
and break exactly this way. If somebody already has, undo it:

```bash
rpm-ostree uninstall quickshell
systemctl reboot
```

---

## Screen recording, and why it needs a whole section

Screen recording on a modern Linux desktop goes through a thing called a
**portal**. A portal is a doorway: OBS is not allowed to read your screen
directly, so it asks the desktop, and the desktop asks you.

Which piece of software answers that request depends on which desktop you are
in, and getting it wrong **fails silently**. No error, no dialog — OBS just
shows an empty list of screens and you assume the program is broken.

So AquariusOS ships a file that says exactly which back end answers which
question in the Aquarius Desktop:

```
/usr/share/xdg-desktop-portal/aquarius-portals.conf
```

- **Screen recording and screenshots → `wlr`.** labwc is built on a library
  called wlroots and speaks its screen-copy protocol, so the small,
  purpose-built `xdg-desktop-portal-wlr` can capture it.
- **Everything else → `gtk`.** File pickers, printing, notifications, the
  "an app wants permission" prompt, and the light/dark setting.

The GNOME session is completely unaffected — it looks for a differently named
file and finds its own.

### Which screen gets recorded

When you start a recording, a dimmed overlay appears and you click the screen
you want. That is `slurp`, and it is configured in
`/etc/xdg/xdg-desktop-portal-wlr/config`.

It would have been possible to skip that click entirely. It is not skipped on
purpose: with the click removed, a machine with two monitors records an
**arbitrary** one, with no prompt and no error, and you find out after the
forty-minute take. If you have exactly one screen and want the prompt gone, the
comments in that file give you the two lines to change.

---

## The other login screen: greetd

AquariusOS uses **GDM**, GNOME's login screen. That is not changing yet.

A second login manager called **greetd** is installed, configured and switched
**off**. It is where this is eventually going — a login screen drawn by the
Aquarius Shell itself — and it is in the image now so that the switch is two
commands rather than a rebuild.

To try it:

```bash
sudo systemctl disable gdm
sudo systemctl enable greetd
sudo systemctl reboot
```

You will get a plain text login screen with a clock, your username filled in,
and a list of sessions you move through with the arrow keys. It is not pretty
and it is not meant to be.

To go back:

```bash
sudo systemctl disable greetd
sudo systemctl enable gdm
sudo systemctl reboot
```

⚠️ **Never enable both.** Exactly one login manager may be switched on;
two is a black screen with no way in. If that happens, boot the previous version
of the OS from the boot menu — every AquariusOS update keeps the last one.

---

## Where everything lives on the machine

| Path | What it is |
| --- | --- |
| `/usr/share/wayland-sessions/aquarius.desktop` | The entry that makes "Aquarius Desktop" appear at the login screen. |
| `/usr/bin/aquarius-session` | The launcher the login screen runs. Sets the environment, starts labwc, and cleans up after it. Heavily commented — worth reading. |
| `/usr/libexec/aquarius-session-lib` | The list of settings the session uses, and the clean-up that removes them again at logout. **Read this before changing anything about logging in or out.** |
| `/usr/libexec/aquarius-session-portals` | Run once at login: stops the portals the last desktop left behind, so ours start fresh. |
| `/usr/share/aquarius/labwc/` | The window manager's configuration: `rc.xml` (key bindings), `autostart`, `shutdown`, `environment`. |
| `/usr/share/aquarius/shell/` | The Aquarius Shell's QML. |
| `/usr/libexec/aquarius-shell-start` | Runs the shell, and puts a dialog on screen if it fails. |
| `/usr/libexec/aquarius-display-scale` | Sets each monitor to the right size at login. Without it every screen stays at 100% and a 4K desktop is tiny. Guide: [`aquarius-display.md`](aquarius-display.md). |
| `~/.config/aquarius/display.conf` | Your own screen-size answers, written by `aq display`. |
| `/usr/share/xdg-desktop-portal/aquarius-portals.conf` | Which portal back end answers which request. |
| `/etc/xdg/xdg-desktop-portal-wlr/config` | How screen recording picks a screen. |
| `/etc/greetd/config.toml` | The alternative login screen, switched off. |
| `~/.local/state/aquarius-session/session.log` | **The log. Read this first when something is wrong.** |
| `/usr/share/aquarius/shell-build.txt` | Exactly which commit of the shell this image contains. |
| `/usr/share/aquarius/quickshell-build.txt` | Which Quickshell, and which Qt it was built against. |

Everything under `/usr` is read-only — that is what makes this operating system
hard to break. To change something for yourself, copy it into your own
`~/.config` and edit the copy; both labwc and the portals read your folder
first.

---

## Changing which version of the shell ships

One line, in `aquarius-os.env`:

```
AQUARIUS_SHELL_REF="b14f4195ade4a379d795431aa3628c92d56d2029"
```

Change the commit, push, and the next build bakes in the new one. The build
**checks** that it got that exact commit and stops if it did not, so a moved tag
upstream cannot quietly change what AquariusOS ships. The same file pins labwc
and Quickshell the same way.

Every push also runs the shell's own test suite against that commit, in a job
called *The Aquarius Shell's own checks*. Bumping the pin to something
structurally broken fails the build rather than surprising somebody at the
login screen.

---

## What is honestly not finished

Being clear about this matters more than it being short.

- **The shell has never been through a full working day.** Its own repository
  says so plainly. Individual pieces have been seen working on the bench; a
  whole day of real editing has not been survived yet. That is R2's exit test.
- **`qmllint` does not run against the Quickshell we ship.** The CI job runs the
  shell's structural checks and its JavaScript tests, which is real but is not a
  QML compiler. The QML checker needs the matching Quickshell installed, and the
  matching Quickshell is the one compiled inside the image — it exists as a
  package nowhere. Running the checker against Fedora's 0.2.1 would fail on the
  two modules 0.2.1 does not have, which would be failing for the wrong reason.
- **The Vulkan renderer is off.** HDR output eventually needs it. It is not a
  build switch — it is chosen when the window manager starts, by setting
  `WLR_RENDERER=vulkan`. It is left at the default because it has not been tried
  on the NVIDIA driver on the bench. The line to uncomment is in
  `/usr/share/aquarius/labwc/environment`.
- **The Game Mode tile in Quick Settings does nothing.** It hands off to a
  script that only exists on Bazzite, which AquariusOS is no longer built on.
  It is harmless — it simply will not appear.
- **The brightness slider needs a laptop.** It reads and writes the backlight
  through `brightnessctl`, and a desktop monitor has no backlight the computer
  can control.
- **There is no lock screen yet, and no display settings panel.** Screen SIZE
  is now handled — see [`aquarius-display.md`](aquarius-display.md) and
  `aq display` — but monitor *layout* (which screen is left of which) still
  means `wlr-randr` in a terminal.
- **X11 applications are not scaled, and nothing can scale them.** On a screen
  set to 125% or 150%, a program running through XWayland — DaVinci Resolve is
  the one that matters here — is either drawn at its normal size or blown up
  and slightly soft. That is a limit of X11 itself; GNOME and KDE have exactly
  the same problem and no desktop solves it. Resolve's own answer is
  Preferences → User → UI Settings → **UI Display Scale**, and it is the right
  one to use.

---

## The bench test list

In order. Stop at the first failure and read the log.

0. **First, from GNOME, check whether the bar is even in this build:**
   `cat /usr/share/aquarius/shell-build.txt`. If it says `status=unavailable`,
   only steps 1, 11 and 12 below can pass — see the section at the top of this
   page for the four clicks that fix it.
1. **Log in.** At GDM, pick **Aquarius Desktop**. It should reach a wallpaper
   with a bar across the top, not a black screen.
2. **Look at the bar.** Aquarius mark on the left, the current window's name
   beside it, status glyphs and a clock on the right.
3. **Look at the dock**, centred at the bottom.
4. **Press Super + Space.** The search palette should appear. Type a few letters
   of an application's name; it should be first in the list. Type `12*12`; it
   should answer 144. Escape closes it.
5. **Click the status glyphs.** Quick Settings should open: Wi-Fi, Bluetooth,
   volume, Focus.
6. **Make a notification.** In a terminal (Super + Return):
   `notify-send "Hello" "This is a test"`. A toast should appear. Click the
   clock; it should be listed in the panel.
7. **Screen recording.** Install OBS from the software store if it is not there,
   start it, add a *Screen Capture (PipeWire)* source. A dimmed overlay should
   appear asking which screen — click one — and OBS should then show the screen.
   **This is the one that proves the portal configuration.**
8. **A file dialog.** In any Flatpak application, open a file. The dialog should
   appear. (This proves the GTK portal is answering.)
9. **Light and dark.** In a terminal:
   `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`. The bar
   should turn Midnight while you watch. Set it back to `default` for Ice.
10. **The version.** In a terminal: `qs --version` should say 0.3.1, and
    `labwc --version` should say 0.20.2.
10b. **No locale warning.** In a terminal, run `qs` by hand. It must NOT print
    *Detected locale "C" with character encoding "ANSI_X3.4-1968", which is not
    UTF-8*. `echo $LANG` should say `en_US.UTF-8`, and the top of
    `~/.local/state/aquarius-session/session.log` should have a line beginning
    `language en_US.UTF-8`. (Press Ctrl+C to stop the second shell — you will
    have two bars until you do.)
10c. **The size.** The bar and dock should look the way they did on the bench at
    `AQ_UI_SCALE=1.25` with the dock at 1.5 — because that is now the design.
    `aq display status` should say `ui=1.0`: the knob is back at neutral, and
    nothing is being multiplied to get this size.
11. **Leave.** Press **Super + Shift + E**. You should be back at the login
    screen within a few seconds. (It takes about three seconds longer than it
    used to — that is the logout clean-up doing its job, and it is deliberate.)
12. **Go back to GNOME.** Pick GNOME at the login screen and confirm it is
    exactly as it was — same wallpaper, same dock, same everything. This is the
    check that proves the fallback is intact.
13. **The switch, twice each way.** ⚠️ **This is the 2026-09-04 bug's own test
    and it is the one to run first after an update.** GNOME must log in **first
    time** after leaving Aquarius, and Aquarius must log in **first time** after
    leaving GNOME — no bouncing off the login screen. Do the whole round trip
    twice, because the original bug was intermittent. Then, in GNOME, run
    `systemctl --user show-environment` — it must not mention `Aquarius`
    anywhere. Full explanation and what to send if it fails: the section
    "Switching between GNOME and the Aquarius Desktop" above.

If any of 1–3 fails, the answer is in
`~/.local/state/aquarius-session/session.log`. Log in with GNOME and read it.
