# One desktop: GNOME

*Rewritten 2026-10-19, the day AquariusOS became GNOME only. The first version
of this page (2026-09-15) was "Two desktops, one login screen". Assumes you have
never used Linux.*

---

## The one-paragraph version

AquariusOS has **one desktop: GNOME**. When the computer starts you see the
login screen, you click your name, you type your password, and you are in
GNOME. There is nothing to choose and no small button to find — the login
screen has only one thing to offer, so it does not ask.

Everything AquariusOS itself does — your drives opening by themselves, the
Installer, Check for Update, the welcome, DaVinci Resolve, the Mac keyboard,
Game Mode, the boot screen — sits underneath the desktop and works exactly as
it did.

---

## What changed on 19 October 2026, and why

From 15 September to 19 October 2026 every AquariusOS machine had **two**
desktops, GNOME and KDE Plasma, and the login screen let you pick one. That was
on purpose: Royce wanted to use both for real and keep the better one.

On 19 October he picked:

> *"Remove the first login screen where you can choose the desktop version and
> just go full GNOME. That way on startup we go straight into GNOME login."*

So:

- **KDE Plasma is no longer in the image.** Not hidden — removed: its programs,
  its settings pages, its file manager, its terminal, and the KDE pieces of
  ours that only existed for it (the "Mac or Windows" page in Plasma's System
  Settings, Plasma's keyboard shortcuts file).
- **The login screen offers GNOME and nothing else.** GDM, GNOME's login screen,
  only shows the session button under the password box when it has more than
  one thing to offer. Now it has one, so the button is gone.
- **Game Mode is still there** — it just is not a choice at the login screen any
  more. You reach it from the **Game Mode** icon in your apps, or by typing
  `aq game`, exactly as before; "Switch to Desktop" in Steam brings you back to
  GNOME. (How that works without being on the menu is below.)

The decision record, with what was given up:
[`../decision-2026-10-19-gnome-only-and-open-drives.md`](../../../docs/decision-2026-10-19-gnome-only-and-open-drives.md)
(in the AquariusOS project folder, one level above this repository).

---

## If your account was using KDE Plasma before the update

Nothing to do. The login screen remembers, per person, which desktop you used
last — and on a machine that was using Plasma, that memory says "Plasma", which
is no longer there. If nothing fixed it, the login screen would try to start a
desktop that does not exist and put you straight back at the password box.

So at **every start-up**, before the login screen appears, AquariusOS looks at
every account and, wherever the remembered desktop is one this computer no
longer has, points it at GNOME. Your next login lands in GNOME.

The program that does it is `/usr/libexec/aquarius-login-mode`, step 0. To see
what it did on this start-up:

```bash
journalctl -b -u aquarius-login-mode
```

A line like `rorobeckley: last used 'plasma', which is no longer on this
computer; the next login goes to GNOME.` is the fix happening.

**What you will notice is different, if you used Plasma:** Plasma's own apps
are gone — Dolphin, Konsole, Spectacle, Gwenview, Okular, Ark. Their GNOME
equivalents were always installed and are what you use now:

| You used (KDE Plasma) | Use now (GNOME) |
|---|---|
| Dolphin | **Files** |
| Konsole | **Ptyxis** (the Terminal) |
| Spectacle | **Print Screen** — GNOME's built-in screenshot and screen recording |
| Gwenview | **Image Viewer** (Loupe) |
| Okular | **Papers** |
| Ark | **Files** opens and makes `.zip` files itself |
| System Settings | **Settings** |
| KWallet | GNOME's keyring (Passwords and Keys). Anything saved only in KWallet is not carried across. |

Settings you made inside Plasma (its panels, its widgets, its colours) stay in
your home folder untouched; nothing reads them any more.

---

## What GNOME is

Calm and deliberately plain. One bar across the top, no icons on the desktop,
and an "Activities" overview you reach by throwing the mouse into the top-left
corner or pressing the key beside the space bar. It has few settings, on
purpose — the GNOME position is that a good default beats a choice.

AquariusOS adds a **dock along the bottom** (an extension called Dash to Dock),
because Royce wanted a Mac-shaped machine. Every drive that is open — inside
the computer or plugged in — has its own icon in that dock. See
[`hardware.md`](hardware.md#every-drive-opens-by-itself--inside-or-plugged-in).

If you have used a Mac, GNOME will feel close to home.

---

## What AquariusOS adds on top

| | |
|---|---|
| **Drives** | Every drive opens by itself, with no password — inside the computer at login, plugged in the moment you plug it in — and shows in the dock and in Files. ([`hardware.md`](hardware.md#every-drive-opens-by-itself--inside-or-plugged-in)) |
| **A drive from a Mac** | Read-only APFS. ([`mac-drives.md`](mac-drives.md)) |
| **Aquarius Installer** | Double-click a download — `.rpm`, `.deb`, AppImage, tarball — and it installs. ([`installer-app.md`](installer-app.md)) |
| **Check for Update** | `aq update`, or the window. ([`updater.md`](updater.md)) |
| **The welcome** | Opens once, at your first login. ([`welcome.md`](welcome.md)) |
| **Your creator apps** | The chooser, the Flatpaks, Aquarius Writer and Aquarius Editor. ([`creator-apps.md`](creator-apps.md)) |
| **DaVinci Resolve** | The setup, the launcher, the update check, the licence dongles. ([`resolve.md`](resolve.md)) |
| **Mac-style shortcuts** | Copy is Command-C. Command-Tab switches apps. The keyboard only — it does not move anything on the screen. The switch is in the menu at the top-right of the screen. ([`aquarius-keys.md`](aquarius-keys.md)) |
| **Window buttons** | Minimise, maximise and close, on the **RIGHT**, for everybody. Not a setting. ([`desktop-identity.md`](desktop-identity.md)) |
| **Game Mode** | Steam owning the whole screen. The **Game Mode** icon, or `aq game`. ([`game-mode.md`](game-mode.md)) |
| **Gaming** | Steam, Proton, controllers. ([`gaming.md`](gaming.md)) |
| **`aq-ingest`** | "Make Editor-Ready" on a camera card. ([`ingest.md`](ingest.md)) |
| **Homebrew, Swift, every codec** | Installed once, for the machine. |
| **The boot screen and the login screen** | Ours. ([`boot-branding.md`](boot-branding.md), [`login.md`](login.md)) |

---

## The keyboard

AquariusOS ships Mac-style shortcuts by default, and the three keys that belong
to the *desktop* rather than to the app you are typing in:

| Key | What it does | How |
|---|---|---|
| **Command-Tab** | switch apps | GNOME answers this out of the box |
| **Command-`** | switch between one app's windows | same |
| **Control-Command-Q** | lock the screen | we bind it |

> **Why the lock is Control-Command-Q and not Command-L.** On a Mac,
> Command-L means "jump to the address bar", and AquariusOS remaps it to do
> exactly that — before the desktop ever sees it. So a lock on Command-L would
> silently never fire. Control-Command-Q is the Mac's own lock shortcut and
> nothing remaps it. `Super+L` still locks too, for anybody in Windows mode.

**One honest gap: Command-Space.** GNOME already uses that key for "switch
keyboard layout", and taking that away is a decision for Royce rather than a
side effect. Use the key beside the space bar on its own for GNOME's overview.

Everything else is in [`aquarius-keys.md`](aquarius-keys.md).

---

## How Game Mode works without being on the login screen

This is the one clever part, so here it is in plain words.

The login screen builds its menu from a folder of small files, one per thing it
can start. Game Mode's file is still there — it has to be, because the switch
from the desktop and the handheld's start-up both log you **straight into Game
Mode, by name**. What changed is one line in that file, `NoDisplay=true`.

GNOME's login screen reads that line two different ways:

- **When it builds the menu**, a file marked `NoDisplay=true` is left off. So
  the menu has one entry — GNOME — and the session button disappears.
- **When it actually starts a session**, it does not look at `NoDisplay` at all.
  So Game Mode still starts the moment the switch asks for it.

(That is from GDM's own source code, checked on 2026-10-19; the details are
beside `aq_hide_extra_login_sessions` in `build_files/aq-lib.sh`. The build
checks it every time: GNOME on the menu, Game Mode installed, Game Mode not on
the menu, and nothing marked `Hidden=true`, which would stop it starting at
all.)

`aq login status` prints both lists: what the login screen offers you (GNOME),
and what is on the computer but not on the menu (Game Mode).

---

## Why there was a choice, and why there is not any more

From 23 August to 15 September 2026, AquariusOS built **its own** desktop — the
**Aquarius Session**, on a window manager called labwc — with GNOME installed
beside it as a fallback. Royce stopped that work on 15 September and asked for
GNOME and KDE Plasma side by side instead, so he could bench both and keep the
better one. ([`../decision-2026-09-15-two-desktops.md`](../../../docs/decision-2026-09-15-two-desktops.md))

On 19 October 2026 he kept GNOME — his words are at the top of this page. The
background that made it an easy call, from what is already on record: GNOME is
the look approved on the bench since 31 August, every AquariusOS window (the
welcome, the app chooser, the Installer, Check for Update) is built with
GNOME's own toolkit, and Plasma had already cost a bench run — on 20 September
it failed to light any screen on the NVIDIA bench machine. And two desktops is
two of everything to test after every update; one desktop is one.

**Nothing of either retired desktop is deleted.** The Aquarius Session's
repository is tagged `aquarius-session-final` and its guide is at
[`history/aquarius-session.md`](history/aquarius-session.md). The KDE Plasma
build step (`build_files/41-kde-desktop.sh`), the Plasma "Mac or Windows"
settings page (`kcm/`) and its build step (`build_files/73-keys-kcm-build.sh`)
are all in git history.

---

## What this costs, said plainly

1. **No second desktop to fall back to.** For five weeks, if one desktop
   misbehaved you could log out and pick the other. That safety net is gone.
   What is left if GNOME will not start is the text login below.
2. **No KDE window rules for Resolve.** Plasma could have forced Resolve's
   window to fit a 4K screen with a per-app rule; GNOME has no such thing.
   Resolve's own window memory still applies.
3. **The branded login screen** is still GNOME's plain one with our logo — the
   same as before. See [`login.md`](login.md).

---

## If something goes wrong

**The login screen comes straight back after you type your password.** Press
**Ctrl+Alt+F3** for a plain text login, log in with your name and password,
and run:

```bash
journalctl -b -u aquarius-login-mode
cat /var/lib/AccountsService/users/"$USER"
```

The second line should say `Session=gnome` (or `Session=gamescope-session-steam`
if you were last in Game Mode). If it names anything else, that is a bug in
the boot-time fix above and belongs in a bench note — and this puts it right
until it is fixed:

```bash
sudo sed -i 's/^Session=.*/Session=gnome/' /var/lib/AccountsService/users/"$USER"
sudo systemctl restart gdm
```

**The login screen does not appear at all.** Press **Ctrl+Alt+F3**, log in, and
run `aq login status`. If it reports that nothing is switched on, it prints the
commands that fix it. A plain text prompt after an update is a known fault with
a fifteen-second fix:
[`login.md`, "Booted to a text console, no login screen"](login.md#booted-to-a-text-console-no-login-screen--15-september-2026).

**The session button is back on the login screen.** That is a build fault — some
package has added a second session. `aq login status` names it; it belongs in a
bench note.

---

## Where to go next

- **The decision, and what was given up:** [`../decision-2026-10-19-gnome-only-and-open-drives.md`](../../../docs/decision-2026-10-19-gnome-only-and-open-drives.md)
- **The decision before it (two desktops):** [`../decision-2026-09-15-two-desktops.md`](../../../docs/decision-2026-09-15-two-desktops.md)
- **How the retired Aquarius Session worked:** [`history/aquarius-session.md`](history/aquarius-session.md)
- **The login screen, and why it looks like stock GNOME:** [`login.md`](login.md)
- **Drives:** [`hardware.md`](hardware.md#every-drive-opens-by-itself--inside-or-plugged-in)
- **Mac-style keyboard shortcuts:** [`aquarius-keys.md`](aquarius-keys.md)
- **Game Mode:** [`game-mode.md`](game-mode.md)
