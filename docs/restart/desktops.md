# Two desktops, one login screen

*Written 2026-09-15, the day Royce stopped building a desktop of our own.
Assumes you have never used Linux.*

---

## The one-paragraph version

AquariusOS comes with **two complete desktops**: **GNOME** and **KDE Plasma**.
Both are installed on every machine. The login screen lists both, you pick one,
and it remembers. Everything AquariusOS itself does — your drives mounting by
themselves, the Installer, Check for Update, the welcome, DaVinci Resolve, the
Mac keyboard, the gaming layer, the boot screen — **works the same on either
one**, because all of it sits underneath the desktop rather than inside it.

You are meant to try both and keep the one you like. That is the entire point
of shipping two.

---

## How to pick one

At the login screen:

1. Click your name.
2. Look at the **bottom-right corner of the password box**. There is a small
   round button there — on most machines it is a cog or a gear.
3. Click it. A short list drops down: **GNOME** and **KDE Plasma**.
4. Pick one, then type your password.

That is it. The login screen remembers your choice and uses it every time after,
until you change it the same way. It is **per person**: two people on the same
computer can use different desktops.

**A brand-new account starts in GNOME.** That is a default, not a rule — it is
the look Royce approved on the bench, and every AquariusOS window (the welcome,
the app chooser, Aquarius Installer, Check for Update) is built with GNOME's
toolkit, so a first login is smoothest there.

> **There is no command for this.** There used to be an `aq login use …` and it
> was about something else entirely — a second *login screen*, not a second
> desktop. That is gone. `aq login status` will list the desktops this machine
> can offer you.

---

## What each one is

Neither of these is written by us. They are the two big desktops of the Linux
world, each with hundreds of people working on it, and that is exactly why they
are here.

### GNOME

Calm and deliberately plain. One bar across the top, no icons on the desktop by
default, and an "Activities" overview you reach by throwing the mouse into the
top-left corner or pressing the key beside the space bar. It has very few
settings, on purpose — the GNOME position is that a good default beats a
choice.

AquariusOS adds a **dock along the bottom** (an extension called Dash to Dock),
because Royce wanted a Mac-shaped machine and GNOME's own dock only appears
inside the overview.

If you have used a Mac, GNOME will feel closer to home.

### KDE Plasma

Adjustable to a fault. A task bar along the bottom by default, icons on the
desktop, and a settings app with a page for very nearly everything — including
things GNOME does not let you change at all. Panels can be moved, split, made
transparent, filled with widgets.

If you have used Windows, Plasma will feel closer to home. If you like taking a
machine apart, Plasma is the one.

---

## What is the same on both

This is the important half of this page. **Everything AquariusOS is actually
for** is below the desktop, so none of it changes when you switch:

| | On both desktops |
|---|---|
| **Plug a drive in** | It mounts by itself, with no password, and appears in the file manager's sidebar — Files on GNOME, Dolphin on Plasma. ([`hardware.md`](hardware.md)) |
| **A drive inside the machine** | Asks once, then opens at every login. ([`hardware.md`](hardware.md#why-an-inside-drive-asks-once-and-an-outside-drive-never-asks)) |
| **A drive from a Mac** | Read-only APFS, the same way. ([`mac-drives.md`](mac-drives.md)) |
| **Aquarius Installer** | Double-click a download — `.rpm`, `.deb`, AppImage, tarball — and it installs. ([`installer-app.md`](installer-app.md)) |
| **Check for Update** | `aq update`, or the window. ([`updater.md`](updater.md)) |
| **The welcome** | Opens once, at your first login, on either desktop. ([`welcome.md`](welcome.md)) |
| **Your creator apps** | The chooser, the Flatpaks, Aquarius Writer and Aquarius Editor. ([`creator-apps.md`](creator-apps.md)) |
| **DaVinci Resolve** | The setup, the launcher, the update check, the licence dongles. ([`resolve.md`](resolve.md)) |
| **Mac-style shortcuts** | Copy is Command-C. Command-Tab switches apps on both. ([`aquarius-keys.md`](aquarius-keys.md)) |
| **Gaming** | Steam, Proton, controllers. ([`gaming.md`](gaming.md)) |
| **`aq-ingest`** | "Make Editor-Ready" on a camera card. ([`ingest.md`](ingest.md)) |
| **Homebrew, Swift, every codec** | Installed once, for the machine. |
| **The boot screen and the login screen** | Ours, and the same however you log in. ([`boot-branding.md`](boot-branding.md), [`login.md`](login.md)) |

---

## The small handful of things that ARE different

Each desktop brings its own version of a few everyday programs. Neither list is
better; they are just the tools each desktop is built around.

| | GNOME | KDE Plasma |
|---|---|---|
| File manager | Files (Nautilus) | Dolphin |
| Terminal | Ptyxis | Konsole |
| Screenshot & screen recording | GNOME's built-in (Print Screen) | Spectacle |
| Image viewer | Loupe | Gwenview |
| PDF reader | Papers | Okular |
| Archives (`.zip`) | File Roller | Ark |
| Settings | Settings (`gnome-control-center`) | System Settings |
| Passwords / keyring | GNOME Keyring | KWallet |
| Screen size (a 4K monitor at 125%) | Settings → Displays → Scale | System Settings → Display Configuration |
| Light or dark | Settings → Appearance | System Settings → Colours |
| Wallpaper | Settings → Background | right-click the desktop → Configure |

**Firefox, and every app you install, is shared.** They are installed once, for
the machine, and they appear on both desktops. Installing something on GNOME
does not mean installing it again on Plasma.

---

## The keyboard, on both

AquariusOS ships Mac-style shortcuts by default, and the three keys that belong
to the *desktop* rather than to the app you are typing in work on both:

| Key | What it does | How |
|---|---|---|
| **Command-Tab** | switch apps | GNOME answers this out of the box; we teach KWin to, alongside its own Alt-Tab |
| **Command-`** | switch between one app's windows | same |
| **Control-Command-Q** | lock the screen | we bind it on both |

> **Why the lock is Control-Command-Q and not Command-L.** On a Mac,
> Command-L means "jump to the address bar", and AquariusOS remaps it to do
> exactly that — before the desktop ever sees it. So a lock on Command-L would
> silently never fire. Control-Command-Q is the Mac's own lock shortcut and
> nothing remaps it. `Super+L` still locks too, for anybody in Windows mode.

**One honest gap: Command-Space.** On Plasma it opens KRunner, Plasma's search
box. On GNOME it does not, because GNOME already uses that key for "switch
keyboard layout" and taking that away is a decision for Royce rather than a side
effect of adding a desktop. Use the key beside the space bar on its own for
GNOME's overview.

Everything else is in [`aquarius-keys.md`](aquarius-keys.md).

---

## Why there are two, and why there used to be three

From 23 August to 15 September 2026, AquariusOS was building **its own**
desktop — the **Aquarius Session**: our own bar, dock, search palette, app
switcher, menus, lock screen and login screen, written in QML on top of a window
manager called labwc. GNOME was installed beside it as a permanent fallback, so
that a bad night's work on ours could never lock Royce out of his own machine.

On 15 September 2026 Royce stopped that work:

> *"I want the OS to no longer try and make its own DE and instead rely on both
> GNOME and KDE Plasma. I want both included so I can test which will work
> better for the final version. I still want to include all the features I've
> developed, just replace the DE — these have been established and the main
> focus for me is providing the best distro I can without worrying about the DE
> as well."*

That is the whole reasoning, and it is a good one. A desktop is an enormous,
never-finished job: a switcher, a lock screen, a notification system, a
settings app, accessibility, every keyboard shortcut, and all of it re-tested
every time something underneath changes. Two teams already do it full-time. The
things nobody else does — camera files that open in an editor, a Resolve that
installs itself properly, drives that behave, a Mac keyboard that works — are
what AquariusOS is actually for, and they were competing for the same hours.

**Nothing of the Aquarius Session is deleted.** Its repository is tagged
`aquarius-session-final` and the last image that shipped it is still in the
registry. The guide to how it worked is kept, marked retired, at
[`history/aquarius-session.md`](history/aquarius-session.md). The decision
record, with the full list of what moved where, is
[`../decision-2026-09-15-two-desktops.md`](../decision-2026-09-15-two-desktops.md).

---

## What this cost, said plainly

Three things the Aquarius Session did are not replaced, and pretending otherwise
would be worse than saying so:

1. **The branded login screen.** Ours had the Ice wallpaper and the Aquarius
   mark. GDM is GNOME's, it is plain, and it cannot be given a background
   without the kind of theme-chasing this project refuses to do. It does carry
   our logo. See [`login.md`](login.md).
2. **Resolve's window fitting a 4K screen.** The Aquarius Session had one window
   rule, naming Resolve, that shrank an oversized window to the screen. GNOME
   has no such thing at all; KDE does, and shipping one is a real option. Until
   somebody sees it misbehave on the bench, nothing is done. Resolve's own
   window memory still applies.
3. **The Aquarius look on the desktop itself.** The bar, the dock and the menus
   drew in Ice and Midnight from our own palette. GNOME and Plasma each have
   their own look. Writing an Aquarius colour scheme that both of them read from
   the same design tokens is the next piece of work, not this one.

---

## If something goes wrong

**One desktop misbehaves.** Log out and pick the other one at the login screen.
That is the whole point of having two, and it is why neither is "the fallback"
any more — each is the other's.

**The login screen does not appear at all.** Press **Ctrl+Alt+F3** for a plain
text login, log in with your name and password, and run:

```bash
aq login status
```

It will say which login screen is switched on and what it can offer. If it
reports that nothing is switched on, it prints the two commands that fix it.

**Both desktops look wrong / no icons / no theme.** That is a build fault rather
than a setting. `aq update check` first; if the machine is already up to date,
it belongs in a bench note.

---

## Where to go next

- **The decision, and the full feature map:** [`../decision-2026-09-15-two-desktops.md`](../decision-2026-09-15-two-desktops.md)
- **How the retired Aquarius Session worked:** [`history/aquarius-session.md`](history/aquarius-session.md)
- **The login screen, and why it looks like stock GNOME:** [`login.md`](login.md)
- **The pointer, the icons, the sounds, the wallpaper:** [`desktop-identity.md`](desktop-identity.md)
- **Mac-style keyboard shortcuts:** [`aquarius-keys.md`](aquarius-keys.md)
- **How big things are on the screen:** [`aquarius-display.md`](aquarius-display.md)
