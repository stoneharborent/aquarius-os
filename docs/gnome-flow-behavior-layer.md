# The GNOME-flow behaviour layer

*Built 2026-08-26. Implements `docs/gnome-principles-kde-spec.md` (one folder up,
in the AquariusOS project root). Everything here assumes zero Linux experience.*

## What this change is, in one paragraph

AquariusOS stays on KDE Plasma — it keeps the Aquarius Dark look, the top bar,
the dock. What changes is how it *behaves*. Press one key and everything you
have open spreads out in front of you, with a search box already listening.
Throw the mouse into the top-left corner and the same thing happens. There are
four workspaces laid out in a row. And the logo in the top bar now opens a
full-screen grid of every app instead of a small start menu. Those are GNOME's
habits and macOS's habits, wearing our paint.

Nothing here is forced. Every single item is a **starting point** that a person
can change in System Settings, and once they change it, it stays changed —
no OS update will ever put it back.

---

## The five things that shipped

| # | What you get | Where it is set |
|---|---|---|
| 1 | Tap **Super** (the ⌘-position key) → Overview opens | `system_files/etc/skel/.config/kglobalshortcutsrc` |
| 2 | Mouse into the **top-left corner** → Overview opens | `system_files/usr/share/aquarius/xdg/kwinrc` |
| 3 | **Four workspaces in one row** | `system_files/usr/share/aquarius/xdg/kwinrc` |
| 4 | Touchpad swipes — **verified, not changed** (KWin hard-codes them) | nothing; see below |
| 5 | Top-bar logo → **full-screen app grid** | the look-and-feel layout script |

And one thing deliberately *not* shipped: a notifications file. Explained at the
bottom.

---

## 1. The Super key — and the surprise we hit

This was meant to be one line in a settings file. It is not, and the reason is
worth writing down so nobody spends an afternoon rediscovering it.

**The old way is gone.** On Plasma 5 you told KWin what the Super key should do
by writing a `[ModifierOnlyShortcuts]` section into `kwinrc`. Search the internet
today and that is still the answer you will find. It has not worked since Plasma
6.1 (mid-2024). The code that read that section — the files
`modifier_only_shortcuts.cpp` and `.h` — is present in KWin's Plasma/5.27 source
and simply does not exist in Plasma/6.7. Nothing in modern KWin reads it. Write
it and you get silence.

- Gone from 6.7: <https://invent.kde.org/plasma/kwin/-/tree/Plasma/6.7/src>
  (no `modifier_only_shortcuts.*`; present at
  <https://invent.kde.org/plasma/kwin/-/tree/Plasma/5.27/src>)
- Plain-English write-up of the change:
  <https://www.lorenzobettini.it/2024/06/modifier-only-shortcuts-in-kde-plasma-6-1/>

**The new way exists but refuses to be a system default.** Since 6.1 the setting
lives in a file called `kglobalshortcutsrc`, and you can set it from System
Settings like any other shortcut. But the program that reads that file
(`kglobalacceld`) opens it in a mode called `SimpleConfig`, which means "read one
file, in the user's own home folder, ignore every system-wide folder." So the
`/usr/share/aquarius/xdg/` trick that carries all our other defaults does not
reach it. This is a known KDE limitation, still open:

- The code: `kglobalacceld/src/globalshortcutsregistry.cpp` (Plasma/6.7), line
  281 — `KConfig::SimpleConfig`
- The bug: <https://bugs.kde.org/show_bug.cgi?id=456958> — "kglobalshortcutsrc
  does not propagate via $XDG_CONFIG_DIRS", status CONFIRMED, still open as of
  February 2026

We also checked whether a global theme could carry shortcuts, since AquariusOS
already ships one. It cannot — the theme system only knows how to apply colours,
fonts, icons, cursors, wallpaper, window decorations and the splash screen.
(`plasma-workspace/libklookandfeel/klookandfeelmanager.cpp`, Plasma/6.7.)

**So we used `/etc/skel` instead.** `/etc/skel` is a folder of starter files that
Linux copies into a person's home folder once, at the moment their account is
created. That gives us exactly the behaviour we wanted: a starting point that is
theirs from the first second, that they can change freely, and that no update
will ever stamp over. It is the same shape as the desktop layout script, which
also runs once per new account.

The file is `system_files/etc/skel/.config/kglobalshortcutsrc` and its two real
lines are:

```ini
[kwin]
Overview=Meta+W\tMeta,Meta+W,Toggle Overview

[plasmashell]
activate application launcher=Alt+F1,Meta\tAlt+F1,Activate Application Launcher
```

Reading that: each line is `keys in use now`, `the app's own default`, `readable
name`, separated by commas; several key combinations for one action are joined
by a tab, written `\t`. The first line gives Overview both `Meta+W` and a bare
`Meta`. The second takes `Meta` away from the app launcher so the two are not
fighting over the same key — the launcher keeps `Alt+F1`.

> **⚠️ This is a mechanism change from the spec, and it needs Royce's sign-off.**
> The spec (item B1) said to put this in `kwinrc`. That is not possible on the
> Plasma version we ship, for the reasons above. `/etc/skel` is the honest
> substitute and it satisfies the spec's real rule — *a default, never a forced
> value* — but it is a different mechanism from the one that was approved, and
> it only reaches new accounts. If it is not wanted, deleting that one file
> reverts it completely and nothing else in this change depends on it.

---

## 2 and 3. The hot corner and the four workspaces

These two *do* go in the ordinary place: a new file at
`system_files/usr/share/aquarius/xdg/kwinrc`, sitting in the same folder as the
`kdeglobals` that already carries our colours and fonts.

```ini
[Desktops]
Number=4
Rows=1

[Effect-overview]
BorderActivate=7
```

`BorderActivate=7` is the top-left corner. The numbers run clockwise from the
top: 0 top, 1 top-right, 2 right, 3 bottom-right, 4 bottom, 5 bottom-left,
6 left, 7 top-left. **Being straight about this one: 7 is already KWin's own
default in Plasma 6.7, so on today's Bazzite this line changes nothing.** It is
written down anyway to state the intent somewhere readable and to pin the
behaviour if a future Plasma or Bazzite changes its mind.

`Number=4, Rows=1` is a genuine change — KWin's defaults are 1 desktop and
2 rows. Four desktops in a single row is the closest honest match to GNOME's
horizontal strip, and it is also what makes the sideways touchpad swipes useful
(see below).

**Why a file in that folder works, and why it works on a Wayland login.** KWin
reads its settings by walking every folder in a list called `XDG_CONFIG_DIRS`,
top to bottom, first answer wins — the same way it reads `kdeglobals`. Our
folder is added to the front of that list by the eight-line script at
`/etc/xdg/plasma-workspace/env/zz-aquarius.sh`. The thing worth verifying was the
*order*: does that script run before KWin starts, or after? It runs before. When
you log in, the program that starts is `startplasma-wayland`, and its `main()`
does this in order:

1. `runEnvironmentScripts()` — runs our script, which sets `XDG_CONFIG_DIRS`
2. `setupPlasmaEnvironment()` — adds the user's own `kdedefaults` folder above ours
3. `syncDBusEnvironment()` — hands that finished environment over to systemd
4. `startPlasmaSession()` — **only now** is `kwin_wayland` launched

So KWin starts with our folder already in its search path and reads the file on
its first pass. Nothing has to be reloaded.

- `plasma-workspace/startkde/startplasma-wayland.cpp` (Plasma/6.7), `main()`
  lines 66, 72, 87
- `kwin/src/main.cpp` (Plasma/6.7) line 84 —
  `KSharedConfig::openConfig("kwinrc")` with no flags, which is the cascading mode

---

## 4. Touchpad gestures — what they already do

We changed nothing here, because there is nothing to change: KWin writes the
gestures into its own code, and Plasma 6.7 has no settings page, no config file
and no switch for them. (KWin 6.7 ships settings pages for animations, window
decorations, desktops, effects, rules, screen edges, scripts, the task switcher,
the virtual keyboard and Xwayland — and none for gestures.)

What that hard-coded behaviour is, on **Wayland** (these gestures do not exist in
an X11 session at all):

| Gesture | What happens |
|---|---|
| **4 fingers up** | Opens the Overview. Keep pushing up and it continues into Grid View. |
| **4 fingers down** | Comes back out — Grid View, then closed. |
| **3 fingers left / right** | Move to the previous / next workspace, following your fingers as you go. |
| **4 fingers left / right** | Same as three fingers — both counts work. |
| **3 fingers up / down** | Nothing, on AquariusOS. |

That last row is a consequence of our own setting, not a bug. KWin only moves up
and down between workspaces if the workspace grid is more than one row tall, and
we deliberately set it to exactly one row. So the vertical axis is free and
sideways is the only way to change workspace — which is precisely the GNOME
feel, and it means the four-finger up gesture never gets confused with a
workspace switch.

On a **touchscreen** the counts are one lower: three fingers up opens the
Overview, three fingers sideways changes workspace.

- `kwin/src/plugins/overview/overvieweffect.cpp` (Plasma/6.7) lines 36–46 —
  `addTouchpadSwipeGesture(SwipeDirection::Up, 4)` and friends
- `kwin/src/virtualdesktops.cpp` (Plasma/6.7) lines 806–823 —
  `registerTouchpadSwipeShortcut(...)`, with the `grid().width() > 1` and
  `grid().height() > 1` guards that produce the "nothing" row above

This is the table the Phase-3 welcome app should teach from.

---

## 5. The top-bar logo becomes a full-screen app grid

In the layout script
(`.../look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js`)
one widget name changed:

```js
// before
var launcher = topBar.addWidget("org.kde.plasma.kickoff");
// after
var launcher = topBar.addWidget("org.kde.plasma.kickerdash");
```

The AquariusOS logo icon config is untouched. `kickoff` is KDE's start-menu-style
popup; `kickerdash` is the "Application Dashboard", which takes over the whole
screen with a searchable grid of every app. That is GNOME's app grid and macOS's
Launchpad, which is why one change serves both goals at once.

The name looks like a typo but is not. The dashboard has almost no code of its
own — it is a thin wrapper that borrows everything from a *different* widget
called `kicker` and simply asks to be drawn full-screen. Hence "kicker-dash",
not "kickoff-dash". It lives in a package called `kdeplasma-addons`, which `build.sh`
now installs by name so the layout script can never point at a widget the
machine does not have.

- The widget:
  <https://invent.kde.org/plasma/kdeplasma-addons/-/tree/master/applets/kickerdash>
- Worth knowing: this widget was briefly broken. Plasma 6.4.80 through 6.6
  changed how `kicker` is packaged and the dashboard stopped opening
  (<https://bugs.kde.org/show_bug.cgi?id=507893>). It is **RESOLVED FIXED**, and
  the fix — libplasma commit `11a8eb0bd`, "Make X-Plasma-RootPath work again",
  2025-09-02 — is in the Plasma/6.7 branch we build against.

Anyone who prefers the popup can right-click the top bar → *Show Alternatives* →
Application Menu. We set a starting point; we do not remove options.

---

## 6. Notifications — checked, and nothing needed

The spec asked us to make sure KDE's courtesy defaults are on: no notification
popups while you are screen-sharing, while screens are mirrored, or while an app
is full-screen. (Nobody wants a Discord message on a client's monitor mid-call.)

**They are on, and Bazzite does not touch them, so we ship nothing.**

Plasma 6.7's own defaults, from the file that defines them
(`plasma-workspace/libnotificationmanager/kcfg/donotdisturbsettings.kcfg`):

```
[DoNotDisturb] WhenScreensMirrored = true
[DoNotDisturb] WhenScreenSharing   = true
[DoNotDisturb] WhenFullscreen      = true
```

And Bazzite's side: a search of the entire `ublue-os/bazzite` repository returns
**zero** files named `plasmanotifyrc`. The KDE preset package it installs on the
desktop image (`steamdeck-kde-presets-desktop`) ships exactly five config files —
`gtkrc`, `settings.ini`, `kdeglobals`, `ktrashrc` and `kscreenlockerrc` — and no
notification file among them.

Two related things checked while we were in there:

- **Bazzite does not ship an `/etc/xdg/kwinrc` on our base image either.** The
  one `kwinrc` in their repo goes into the *handheld* preset package
  (`steamdeck-kde-presets`, used by `bazzite-deck`), and it contains only two
  virtual-keyboard lines that do not collide with anything we set. Worth
  remembering for Phase 4, when handhelds come into scope.
- Notification popups appear next to the notification icon in the tray, which on
  our top bar puts them top-right — Plasma's default (`PopupPosition =
  CloseToWidget`) and the Mac position, so no change needed there either.

---

## How to test this

**⚠️ You need a brand-new user account, or a fresh install. Logging out and back
in is not enough, and neither is rebooting.** Two of the five items — the Super
key and the top-bar launcher — are one-time starter settings that only get
applied when an account is first created. An account that already exists keeps
what it already has, on purpose.

The quickest way to get a clean account on a running AquariusOS machine: open
System Settings → Users → Add New User, make one, log out, and log in as them.

Then, in order:

1. **Tap the Super key once.** The Overview should open — every window spread
   out, workspaces along the top. Start typing; results should appear
   immediately without touching the mouse.
2. **Throw the mouse into the very top-left corner.** Same Overview.
3. **Look at the workspace strip in the Overview.** There should be four, in a
   single row.
4. **Click the AquariusOS logo** in the top bar. A full-screen grid of apps
   should take over the display, with a search field.
5. **Prove nothing is forced.** Change any one of the above in System Settings —
   for example, System Settings → Keyboard → Shortcuts, and give Super back to
   the application launcher. Log out, log back in. Your change must still be
   there.
6. **Both images still build.** `aquarius-os` and `aquarius-os-nvidia` both go
   green in GitHub Actions.

Bonus, if you have a touchpad: four fingers up should open the Overview, three
fingers sideways should slide between workspaces.

---

## What we could not check from a Mac

Honest list. None of this was testable without an x86 machine running the actual
image, and every claim above that is not source-quoted belongs here:

- **Nothing in this change has been run.** Every statement is read out of KDE's
  and Bazzite's published source for the versions we build against
  (`Plasma/6.7`, Bazzite `main`), not observed on a booted machine.
- **The exact Plasma version Bazzite ships.** The Xbox Ally boot test recorded
  "Plasma 6.7.4", so 6.7 is the right branch to read — but Bazzite tracks Fedora,
  and if a build lands on 6.8 the shortcut file format is the first thing to
  re-check.
- **Whether `kdeplasma-addons` was already installed.** We could not get a
  package list for `ghcr.io/ublue-os/kinoite-main` from here, so `build.sh` now
  asks for it by name. If it was already there the line costs a second; if it
  was not, it is what makes the app grid work at all. Either way the build log
  will say which.
- **Whether the shortcut file is accepted verbatim.** The three-part format and
  the tab separator are read straight from the source that parses them, and the
  two "default" values are copied from the code that registers them — but the
  file has not been fed to a live `kglobalacceld`. The failure mode is gentle: a
  line that does not parse is skipped and the shortcut reverts to normal KDE
  behaviour, so the worst case is "Super still opens the launcher", not a broken
  session.
- **Whether `/etc/skel` is honoured by the installer.** It is the standard Linux
  mechanism and `useradd` uses it, but the AquariusOS ISO's account-creation step
  has not been watched doing it.
