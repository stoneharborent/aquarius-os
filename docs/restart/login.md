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

Not written yet in this document. It lands on the same branch as this file.

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

Build steps that put them there: `build_files/50-aquarius-desktop.sh`, section 4.
