# The login screen

*Written 2026-09-04, after Royce photographed the bench machine booting and
asked why the screen he logs in at does not look like AquariusOS. Assumes you
have never used Linux.*

---

## The photograph, and what it was showing

The bench machine boots, and on a 55-inch 4K monitor you get a flat light-grey
screen with two small tiles on it — a picture and a name — and the AquariusOS
logo down at the bottom. Everything is tiny. It looks like a different, plainer
computer than the one you get thirty seconds later.

Nothing is broken. **You are looking at two different programs and assuming they
are one.**

| | What draws it | When you see it |
| --- | --- | --- |
| **The login screen** | **GDM** — GNOME's own login program | straight after the computer starts, before anybody has logged in |
| **The lock screen** | **your desktop**, inside your own session | when you walk away and come back |

The lock screen looks like AquariusOS because it *is* AquariusOS: your session,
your wallpaper, your screen size, our colours.

The login screen is a separate program that starts before anybody has logged in.
It runs as its own user, called `gdm`, with its own settings, and it has never
seen yours. It is GNOME's program and it is designed to be adjusted, not
redesigned.

So there are two answers to "make the login screen look like that", and this
document is both of them:

- **Part A — make GDM as good as GDM gets.** Right size, Ice light, our
  typefaces, our logo. Shipped and switched on. This is what you will see the
  next time you update.
- **Part B — replace it with our own.** A login screen drawn by the Aquarius
  Shell itself, on the Ice wallpaper, with the Aquarius mark. Shipped and
  switched **off**, waiting for you to try it on the bench.

---

# Part A — the GDM you already have, fixed

## 1. It is now the right size

### Why it was tiny

The size of everything on a screen is a number called the **scale**. On a 4K
monitor, 100% makes text physically small, so GNOME lets you set 125%, 150% and
so on in **Settings → Displays → Scale**. You set the bench machine to 125% weeks
ago.

That answer is written into a file inside your home folder
(`~/.config/monitors.xml`). The login screen runs as the `gdm` user, and the
`gdm` user is not allowed to look inside your home folder. So it never saw the
answer and did what it always does with no answer: 100%.

### What now happens

AquariusOS ships a small program whose entire job is to carry that answer
across: `/usr/libexec/aquarius-gdm-display`. It runs as an administrator, finds
the display arrangement the people who use this computer have chosen, and puts a
copy in two places the login screen *can* read:

- `/etc/xdg/monitors.xml` — the system-wide answer. This is the one that works
  on current versions of GNOME.
- `/var/lib/gdm/.config/monitors.xml` — the older place every guide on the
  internet tells you to use. It is written too, because it costs nothing and
  different versions of GDM read different ones.

It runs at **two** moments:

1. **Every boot**, before the login screen appears
   (`aquarius-gdm-display.service`).
2. **Every logout**, because GDM runs a script as an administrator at that
   moment and we put a line in it (`/etc/gdm/PostSession/Default`).

Between the two, the login screen is never more than one logout behind your
desktop.

### What you have to do — once

If you have already set a Scale in Settings → Displays (you have, on the bench),
**nothing**. Update, reboot, and the login screen will be the right size.

If a brand-new machine has never had a scale chosen, the login screen stays at
100% and this program says so in the system log rather than guessing. Guessing
would mean writing a file that names a monitor and a video mode we cannot see
from outside a running session, and a wrong one of those files can leave a
screen blank. So:

> Open **Settings → Displays**, set **Scale**, then log out. The login screen
> matches from then on.

### Checking it by hand

```bash
sudo /usr/libexec/aquarius-gdm-display --status     # what the login screen has
sudo /usr/libexec/aquarius-gdm-display --dry-run    # what it would do, changing nothing
sudo /usr/libexec/aquarius-gdm-display              # do it now
```

### Why we did NOT just make the text bigger

There is a setting called `text-scaling-factor` that makes GNOME's text larger,
and it does work on the login screen. We deliberately do not use it, because the
real problem is the monitor scale — and if we fixed the monitor scale *and* made
the text bigger, the login screen would end up too big instead of too small. One
fix for one problem.

## 2. It is now Ice, not stock

The login screen reads its settings from its own database, and AquariusOS now
puts our answers in it:

| Setting | Value | Why |
| --- | --- | --- |
| logo | the Aquarius mark | already there before this change |
| colour scheme | **light** | GNOME 47 made the login screen dark by default. AquariusOS is Ice, and Ice is light. |
| accent colour | blue | the nearest of GNOME's nine fixed words to Aquarius Blue — the same compromise the desktop makes |
| interface font | Inter | ours, so your name is set in our typeface |
| monospace font | JetBrains Mono | ours |
| mouse pointer / icons | Adwaita | GNOME's, written down explicitly so that the day AquariusOS has its own, the login screen is not forgotten |

Honest limitation, and it is other people's too: even in light mode a few pieces
of GNOME's own top bar can stay dark. We are not chasing that.

## 3. What we could NOT fix, and why we stopped

**The background.** GDM paints its background from a rule buried inside a
compiled resource file that ships with GNOME Shell. There is no setting for it —
not in GNOME 47, 48, 49 or 50. Every tool on the internet that changes it does
one of two things:

- unpacks GNOME's resource file, edits it, and repacks it, or
- loads a GNOME Shell *extension* into the login screen.

Both mean owning a piece of GNOME's internals and re-checking it every time
GNOME releases. That is the "theme treadmill" this project has a standing rule
against — it is what has eaten entire Linux distributions — and it is
particularly silly to walk it here, because the answer we actually want is not a
better GDM. It is our own login screen.

Which is Part B.

---

# Part B — our own login screen

**It is in the image. It is switched OFF. Turning it on is one command.**

## What it looks like

```
                          09:42
                    Friday 4 September

           ┌──────────────────────────────────────┐
           │             ◭  AquariusOS            │
           │                                      │
           │                ( RA )                │
           │           ‹  Royce Adkins  ›         │
           │                                      │
           │   ┌──────────────────────────────┐   │
           │   │ ••••••••                     │   │
           │   └──────────────────────────────┘   │
           │   Password:                          │
           │                                      │
           │          ◇ Aquarius Desktop          │
           └──────────────────────────────────────┘

      Enter to sign in  ·  Esc to start over  ·  ← → for another desktop
```

On "The Pour" — the Ice wallpaper — with the Aquarius mark, the Aquarius
typefaces, the Aquarius colours and the Aquarius spacing, because it is drawn by
the Aquarius Shell out of the same design files as the desktop. That is the
whole point: the screen you log in at and the desktop you land on are one thing.

## What each key does

| Key | What it does |
| --- | --- |
| **Enter** | Sign in. |
| **Escape** | Start over — empties the box and forgets the attempt. |
| **↑ ↓** | A different account. Only when there is more than one. |
| **← →** | A different desktop — Aquarius Desktop or GNOME. |
| **Tab** | The same as →. |

The hints are written on the screen, under the card, because this is the one
screen in the whole computer where you cannot open Settings to find out.

## How to try it

```bash
sudo aq login use greetd
sudo systemctl reboot
```

## How to go back

```bash
sudo aq login use gdm
sudo systemctl reboot
```

That second command works **from a text console too**. If the new login screen
ever gives you trouble, press **Ctrl+Alt+F3**, log in at the text prompt, and run
it. And `aq login status` says which one is switched on and whether the other is
ready.

## Why it cannot lock you out

This is the part worth reading before you switch, because switching login
managers is the classic way to lock yourself out of a Linux computer: the new
one fails to start, the login manager restarts it, and you are looking at a
flickering black screen with no way to type anything.

**Three things stop that here.**

1. **If the graphical login screen fails to start, it falls through to a plain
   text one by itself.** `/usr/libexec/aquarius-greeter` runs the graphical
   screen and, if that comes back with an error, runs `tuigreet` instead — the
   text login screen that has been in the image since R2. Ugly, and completely
   usable. You log in, you type `sudo aq login use gdm`, you restart.
2. **GNOME is one keypress away at the login screen itself.** The pill under the
   password box says which desktop is about to start; ← and → change it. So even
   if the Aquarius Desktop is the thing misbehaving, GNOME is right there.
3. **GDM is still installed and is still the default.** Nothing was removed.
   `aq login use gdm` puts everything back exactly as it was.

And underneath all three: AquariusOS keeps the previous version of itself.
Holding the boot menu and picking the older entry undoes an update entirely.

## How it works, in order

```
greetd                    the login manager. Draws nothing at all. Its one job
  │                       is to run a program and to be the only thing on the
  │                       computer that checks passwords.
  └─ /usr/libexec/aquarius-greeter
       │                  our launcher — and the safety net above
       └─ labwc           a window manager, because the login screen is a
            │             Wayland program and needs something to draw into
            └─ /usr/libexec/aquarius-greeter-shell
                 │        sets the screen size, then starts the login screen
                 └─ qs -p /usr/share/aquarius/shell/greeter/greeter.qml
                          the login screen itself
```

When you log in successfully, the login screen asks greetd to start your desktop
and then exits. labwc was started with `-s`, which means "shut down when that
finishes", so the whole chain unwinds and greetd has the screen back to start
your desktop on.

### Why labwc and not something smaller

`cage` is the obvious choice — it is a window manager built for exactly this,
running one program full screen. It does not implement the **layer-shell**
protocol (an open request since 2019), and layer-shell is how the login screen
covers the whole screen with nothing able to appear over it. labwc implements
it, and it is already in this image for the Aquarius Desktop, so it is one fewer
program to keep working.

### Where it gets its size

The same place GDM now does: `/etc/xdg/monitors.xml`, written by
`/usr/libexec/aquarius-gdm-display` (Part A). The login screen runs as its own
user with no home folder worth reading, so it is pointed at the system-wide copy
instead. One answer, three places that need it, one program that carries it.

If you ever want the *login screen* at a different size from the desktop, put a
single line in `/var/lib/aquarius/greeter-display.conf`:

```
scale=1.5
```

### Where it gets the accounts and the desktops

`/usr/libexec/aquarius-greeter-info` — a small program that prints them as one
line of JSON. Run it yourself:

```bash
/usr/libexec/aquarius-greeter-info --people
/usr/libexec/aquarius-greeter-info --desktops
```

Accounts come from `/etc/passwd` (anyone with a real login shell and an ordinary
user number). Desktops come from `/usr/share/wayland-sessions/`, which is where
both the Aquarius Desktop and GNOME describe themselves. The Aquarius Desktop is
listed first, which is what makes it the default.

## What is NOT done yet

Written down so nobody has to guess whether it was forgotten.

- **No fingerprint reader.** greetd can carry it — it arrives as another
  question, the same way a password does — but it has never been tried here.
- **No on-screen keyboard.** So this is not yet a login screen for a machine
  with no keyboard plugged into it.
- **No accessibility menu.** GDM has one; this does not. That is a real
  step backwards from GDM, and it is one of the reasons GDM stays installed and
  stays the default.
- **No restart or shut down buttons.** They need a permissions conversation the
  login screen's own user does not have set up yet. The power button on the case
  still works.
- **No photographs on the accounts** — initials in a blue circle instead. The
  reasoning is in `greeter/GreeterAvatar.qml` in the shell repository; the short
  version is that those picture files have a long history of being unreadable,
  and making them round would mean an extra import whose absence would stop the
  *whole login screen* loading. Bad trade for a decoration.
- **One monitor gets the card.** The others show the wallpaper. Nothing is
  black, but the clock and the password box are on the first screen only.
- **Nobody has looked at it on real hardware.** Which is the next line.

## The bench list — what to check when you switch it on

In order, and stop at the first one that is wrong:

1. `sudo aq login status` — does it agree that GDM is on now, and say the
   AquariusOS one is ready?
2. `sudo aq login use greetd`, then `sudo systemctl reboot`.
3. **Does a login screen appear at all?** If it is a plain blue-and-grey text
   screen, the graphical one failed and fell back — that is the safety net
   working. `journalctl -u greetd -b` says why.
4. **Is it the right size on the 55" monitor?** This is the whole reason for the
   work. If it is tiny, `sudo /usr/libexec/aquarius-gdm-display --status` says
   what it thinks the answer is.
5. **Does typing work?** The password box should have the cursor without you
   clicking anything.
6. **Does a wrong password say so** and let you try again, rather than going
   quiet?
7. **Does a right password start the Aquarius Desktop?**
8. **Do ← and → change the desktop pill**, and does picking GNOME start GNOME?
9. **Escape** — does it clear the box and let you start again?
10. Log out. Does it come back to the same screen?
11. `sudo aq login use gdm`, restart, and check GDM comes back — because the way
    out matters more than the way in.

---

## The files, for the record

| Path | What it is |
| --- | --- |
| `/etc/dconf/db/gdm.d/01-aquarius-logo` | the login screen's logo |
| `/etc/dconf/db/gdm.d/02-aquarius-look` | its colours, typefaces and pointer |
| `/etc/dconf/db/gdm` | the built database. **This** is what GDM reads; the two files above do nothing until `dconf update` bakes them into it. |
| `/usr/libexec/aquarius-gdm-display` | the messenger that carries your screen size to the login screen |
| `/usr/lib/systemd/system/aquarius-gdm-display.service` | runs it at every boot, before the login screen |
| `/etc/gdm/PostSession/Default` | runs it again at every logout |
| `/usr/share/aquarius/gdm-PostSession-Default.orig` | Fedora's version of that file, kept so the difference is a fact and not a memory |
| `/etc/xdg/monitors.xml` | the copy of your display arrangement the login screen reads |
| `/var/lib/aquarius/display-scale` | one number: the scale, for our own greeter to read |

And Part B's:

| Path | What it is |
| --- | --- |
| `/etc/greetd/config.toml` | greetd's own settings. Names our launcher and the user it runs as. |
| `/usr/libexec/aquarius-greeter` | The launcher — and the safety net that falls back to a text login screen. **Read this one.** |
| `/usr/libexec/aquarius-greeter-shell` | Sets the screen size, then starts the login screen. |
| `/usr/libexec/aquarius-greeter-info` | Prints the accounts and the desktops. Runnable by hand. |
| `/usr/share/aquarius/greeter-labwc/` | The login screen's own window manager configuration — deliberately almost empty. Not the desktop's. |
| `/usr/share/aquarius/shell/greeter/` | The login screen itself, in QML. Comes from the aquarius-shell repository. |
| `/var/lib/aquarius/greeter-display.conf` | Optional. A different screen size for the login screen alone. |

Build steps that put them there: `build_files/50-aquarius-desktop.sh` section 4
(Part A), `build_files/55-aquarius-session.sh` section 3 (Part B). The login
screen's own design notes are in the shell repository at `docs/greeter.md`.
