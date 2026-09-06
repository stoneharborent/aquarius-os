# The login screen

*Written 2026-09-04, after Royce photographed the bench machine booting and
asked why the screen he logs in at does not look like AquariusOS. Assumes you
have never used Linux.*

*Updated 2026-09-05 (twice). The first fix turned the login screen black. The
second fix did not catch it. What ships now is the third answer, and it is to
stop doing the thing. Start with the incident below — it is the most important
thing on this page.*

---

# The black login screen — twice, 4 and 5 September 2026

## If you are looking at a black screen right now

Press **Ctrl+Alt+F3** for a text login screen, log in, and run:

```bash
sudo rm -f /etc/xdg/monitors.xml /var/lib/gdm/.config/monitors.xml
sudo systemctl restart gdm
```

That is the whole recovery, and it has worked both times. If you would rather
undo the setting properly at the same time:

```bash
sudo aq login scale off
sudo systemctl restart gdm
```

And underneath all of it, AquariusOS keeps the previous version of itself:
holding the boot menu and picking the older entry undoes an update entirely.

## What happened

**Twice, on two consecutive days**, the bench machine booted and showed a black
screen with a mouse pointer on it and nothing else. No login screen. No error.
The pointer moved when the mouse moved, so the computer was alive — there was
just no way in.

Both times the two files above were the cause, and deleting them fixed it.

| | 4 → 5 September | 5 September |
| --- | --- | --- |
| What was on the machine | the copy, made exactly as your own settings had it (125%) | the copy, "made safe" first — part sizes rounded to whole ones — plus a guard that was supposed to undo it automatically |
| What happened | black screen | black screen **again** |
| What the guard did | it did not exist yet | **nothing.** It was enabled, it ran, and it decided the login screen was fine |
| How it was fixed | by hand, the commands above | by hand, the same commands |

## What those two files were

They were **this project's own idea**. Part A below explains it: the login
screen runs as a different user and cannot see the display size you chose in
Settings, so AquariusOS copied that setting somewhere the login screen could
read it. Those two files were the copies.

Royce's monitor is set to **125%**.

## Why we still do not know the cause

125% is a **part size** — not a whole number of times bigger. 100% and 200% are
whole sizes; 125%, 150% and 175% are not. Part sizes on GNOME have a long
history of quietly not working, so that was the first suspect.

**It is a suspect, not a conviction.** AquariusOS is built on Fedora 44, which
is GNOME 50, and GNOME 50 turned part sizes on by default for everybody (a
change to GNOME's window manager merged in February 2026). And the second black
screen happened on an image that had already rounded 125% down to 100% — which
is evidence against the part-size theory, though not proof, because the file
that broke that boot was probably written by the OLD logout hook at the previous
shutdown (see the trap below) and so was never rounded at all.

Other documented possibilities: the arrangement did not match the monitors
actually plugged in and GNOME threw the whole file away; or something about the
file's ownership or security label under a GDM that no longer keeps a permanent
`gdm` home folder. We could not find anybody else reporting this exact symptom
from this exact cause.

So the honest summary has not changed:

- **Certain:** those two files cause it. Removing them fixes it.
- **Not certain:** why. Two attempts to fix the *why* both shipped a machine
  that would not let Royce in.

## What ships now: the login screen is given nothing

**Royce's decision, 5 September 2026, and the whole of the change:**

> The login screen gets **no copied display file** by default.

It runs at GNOME's own 100%. On the 55-inch 4K bench monitor that means small
name tiles on a big screen — the exact complaint that started this work on
4 September. That is the deliberate trade, and it is not a close call:

**A login screen that is too small is annoying. A login screen that is black is
a computer nobody can get into.** Twice.

### The machine repairs itself on the first boot of this image

**You do not have to type anything.** If this computer already has one of those
copies — and Royce's does, left over from the older AquariusOS — the boot-time
program removes it. On the first boot after updating, the leftover is gone and
the login screen comes up.

That clean-up is the part that matters most, because it is the part that runs
with nobody watching:

- at every boot, `aquarius-gdm-display.service` runs
  `/usr/libexec/aquarius-gdm-display`
- with the switch off (the default) it deletes `/etc/xdg/monitors.xml` and
  `/var/lib/gdm/.config/monitors.xml` if either exists, writes one line saying
  so, and stops.

### The logout hook no longer copies either

`/etc/gdm/PostSession/Default` — the script GDM runs when you log out — now does
nothing at all unless the switch is on. It is back to being the two-line
do-nothing script Fedora ships.

> **The trap this closes, and it is worth understanding.** An update's new files
> do not take effect until you restart. So the **last** thing a machine does
> before its first boot on a new image is run the **old** logout hook. That is
> almost certainly what wrote the file that black-screened the bench on
> 5 September — an unsanitised 125% copy, written by yesterday's code, minutes
> before today's code first ran. A defence that only starts working after the
> next update is not a defence. A hook that copies by default copies once more
> after you have stopped wanting it to.

## The guard, and why it did not save the bench

`aquarius-gdm-guard.service` is the net underneath: if a login screen does not
appear and one of those copies is lying around, it takes the copy away and
restarts the login screen once.

**On 5 September it did nothing, and the reason is worth writing down.** It was
enabled. It ran. It was not broken in any way a build log could show. It asked
the wrong question:

> *"Is there a graphical session on this machine?"*

In a black-screen boot the answer is **yes**. The mouse pointer you are looking
at is drawn by the compositor — a pointer on the screen is proof that GNOME's
greeter started and has a session. What was wrong was one step further in: the
compositor came up and drew nothing, and the part of Linux that tracks sessions
cannot see that. So the guard was told "the login screen is up", twenty seconds
into the boot, and exited reporting success while Royce sat in front of a black
screen.

**What it asks now.** It watches for the full 45 seconds and acts if **any one**
of these is true — any one, not all:

| | What it looks at |
| --- | --- |
| **A** | No graphical session by the end — either nothing ever started, or one started and then went away. |
| **B** | The login screen keeps restarting — either systemd's restart count for GDM went up while we watched, or the session kept being replaced by a different one. A healthy login screen starts once and stays. |
| **C** | The compositor said in the system log that it could not use the display arrangement. That names our file as the problem directly, so it acts **even though a session exists** — which is exactly the case that beat it. |

It still stands aside completely when GDM is not the login screen in use, when
there is no copied file to take away, or when it has already acted once this
boot.

**And the case it still cannot see.** If the compositor comes up, keeps one
steady session, complains about nothing, and draws a black screen anyway, this
program has no way to know. It cannot read pixels. **That is the honest reason
the copy is off by default rather than "the guard has it covered."** The guard
is a net, not a fix.

The trigger is now executed on every build, against fake system commands, on
both sides — it must act on all four shapes of broken and stand aside on a
healthy machine (`tests/test-gdm-guard.sh`). A safety net whose trigger has
never been run is not a safety net; it is a comment. That is the lesson of
5 September.

> **Why not just make systemd notice GDM has failed?** Because GDM never fails.
> It restarts itself forever, so from systemd's point of view a login screen
> that draws nothing is a service in perfect health.

## How these services are switched on, and what that means for you

This is worth knowing because it bit Royce.

On an ordinary Linux machine, `systemctl enable` writes a link into `/etc`. On
AquariusOS that is a trap: **every update merges the current machine's `/etc`
onto the new image's, and anything you changed locally wins forever — including
deletions.** So one `sudo systemctl disable aquarius-gdm-display`, typed once
while trying something, would turn that service off *on that machine, for ever*,
and no future image could switch it back on. It would look exactly like a bug.

So AquariusOS switches its own services on from `/usr` instead —
`/usr/lib/systemd/system/graphical.target.wants/` — which is replaced whole at
every update and which nothing local can edit. An update always restores them.

**The honest cost:** `systemctl disable` no longer turns these two off, because
there is nothing in `/etc` for it to remove.

- To turn the display copy off, use its own switch: **`sudo aq login scale off`**.
  That is the one to reach for, and it is what this page tells you to use.
- To force a unit off regardless: `sudo systemctl mask aquarius-gdm-guard`. That
  writes to `/etc` and beats everything, including updates. Only do this if you
  have a reason; the guard costs nothing and covers leftovers.

## Trying it anyway, on one machine

The switch exists so the idea can be tested by somebody who is watching. It is
worth doing on the bench, and it is not worth doing on a machine you need.

```bash
sudo aq login scale on          # give the login screen your display settings
sudo systemctl reboot
```

**Watch the restart.**

- **A login screen appears, the right size** — it worked. Leave it on, and tell
  the rest of us.
- **A black screen with a pointer** — wait about a minute. The guard should
  remove the copy and restart the login screen, and you get in at 100%. *This is
  the thing most worth confirming*, because it did not happen on 5 September.
- **Still nothing after two minutes** — press **Ctrl+Alt+F3** for a text login
  screen, log in there, and run:
  ```bash
  sudo aq login scale off
  sudo systemctl restart gdm
  ```

While it is on, there is one more choice — what sizes may be passed through:

```bash
sudo aq login scale integer      # whole sizes only: 125% becomes 100%. The default.
sudo aq login scale fractional   # part sizes too: the login screen gets your real 125%
```

`integer` rounds with a rule table, in `/usr/libexec/aquarius-monitors-sanitize`:

| Your setting | What the login screen is given |
| --- | --- |
| 100%, 200%, 300% | the same, untouched |
| nothing set | nothing set (means 100%) |
| **125%** | **100%** |
| 150% | 200% if there is room on the screen, otherwise 100% |
| 175% | 200% |
| nonsense (0%, 900%, not a number) | 100% |

And if it cannot understand your file at all — half-written, not XML, not a
display arrangement — **nothing is copied.**

**Your own desktop is never affected by any of this,** and neither is the
AquariusOS login screen in Part B. Your file is never modified.

To go back at any time: `sudo aq login scale off`.

## The real fix, and it is not on this page yet

The proper answer to "the login screen is the wrong size" is not to smuggle a
file to GNOME's login screen. It is **our own login screen** — greetd plus the
Aquarius Shell, Part B below — which runs in our own compositor, reads the
session's scale itself, and needs nothing copied anywhere.

That is the **R5** job. Until it lands, the login screen is GNOME's, at 100%,
and that is a known and accepted state rather than an outstanding bug.

## Checking it, and reading what happened

```bash
sudo aq login scale status                        # on or off, and what happened
sudo /usr/libexec/aquarius-gdm-display --status   # the same, in more detail
sudo /usr/libexec/aquarius-gdm-display --dry-run  # what it would do, changing nothing
cat /var/lib/aquarius/gdm-display.log             # everything it has ever done
sudo /usr/libexec/aquarius-gdm-guard --status     # the three things the guard looks at
```

The log is written in the same plain English as this page. If your login screen
is ever a different size than you left it, it says why.

## The bench list for this fix

1. `sudo bootc upgrade`, then restart.
2. **Does a login screen appear?** That is the whole point. It should, on the
   first boot, with nothing typed.
3. `sudo aq login scale status` — does it say the login screen is **not** given
   anything?
4. `ls /etc/xdg/monitors.xml /var/lib/gdm/.config/monitors.xml` — both should say
   **No such file**. They were removed by the boot-time clean-up.
5. `cat /var/lib/aquarius/gdm-display.log` — does it say a leftover copy was
   removed, in words?
6. Is the login screen small on the 55-inch? **Expected.** See the trade above.
7. Optional, and only if you want to test it: `sudo aq login scale on`, restart,
   and watch. If it goes black, does it come back by itself within a minute?
   That is the repaired guard, and it is the thing most worth confirming.
   `sudo aq login scale off` to put it back, whichever way it went.

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

- **Part A — make GDM as good as GDM gets.** Ice light, our typefaces, our logo.
  Shipped and switched on. **Not the right size** — see below; that is the one
  thing we tried and gave up on.
- **Part B — replace it with our own.** A login screen drawn by the Aquarius
  Shell itself, on the Ice wallpaper, with the Aquarius mark. Shipped and
  switched **off**, waiting for you to try it on the bench. This is where the
  size problem actually gets solved.

---

# Part A — the GDM you already have

## 1. The size: we tried, and we stopped

### Why it is tiny

The size of everything on a screen is a number called the **scale**. On a 4K
monitor, 100% makes text physically small, so GNOME lets you set 125%, 150% and
so on in **Settings → Displays → Scale**. You set the bench machine to 125% weeks
ago.

That answer is written into a file inside your home folder
(`~/.config/monitors.xml`). The login screen runs as the `gdm` user, and the
`gdm` user is not allowed to look inside your home folder. So it never sees the
answer and does what it always does with no answer: **100%**.

### What now happens: nothing, on purpose

AquariusOS ships a program that can carry that answer across —
`/usr/libexec/aquarius-gdm-display` — and **it is switched off.** Handing the
login screen that file black-screened this computer on 4 September and again on
5 September, and nobody has worked out why. The incident section at the top of
this page is the full story.

So the login screen stays at 100%, and looks small on a big monitor. The program
still runs at every boot, but with the switch off its only job is to **take
away** a copy an older AquariusOS left behind — which is what makes a machine
that is updating come up at all.

For the record, when it *is* switched on it writes two files, because there are
two places GNOME might look:

- `/etc/xdg/monitors.xml` — the system-wide answer. **This is the one that
  works** on current versions of GNOME.
- `/var/lib/gdm/.config/monitors.xml` — the older place every guide on the
  internet tells you to use. It is written too, because it costs nothing.
  Honest note: it is probably dead. GDM 49 stopped using a permanent `gdm`
  account and gives the login screen a temporary one each time, so there is no
  longer a reliable home folder to put this in. It stays as a belt, not because
  we expect it to be read.

### What you have to do — nothing

Update, restart, and the login screen appears. If this machine had one of those
copies left over, it is removed on the way past, with nothing typed.

If you want the login screen to match your desktop, there are two roads and
neither is "do nothing":

1. **Test the switch on this machine** — `sudo aq login scale on`, restart, and
   watch. See "Trying it anyway" at the top of this page. It may work; it may
   black-screen; that is the state of our knowledge.
2. **Wait for Part B**, our own login screen, which gets the size right by
   construction because it is our own compositor. That is the R5 job and it is
   the answer we actually want.

### Checking it by hand

```bash
sudo /usr/libexec/aquarius-gdm-display --status     # what the login screen has
sudo /usr/libexec/aquarius-gdm-display --dry-run    # what it would do, changing nothing
sudo /usr/libexec/aquarius-gdm-display              # do it now
cat /var/lib/aquarius/gdm-display.log               # everything it has ever done
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

⚠️ **This is the part that has to change before Part B ships, and it is the
reason Part B is the real fix.**

It currently reads `/etc/xdg/monitors.xml` — the system-wide copy that Part A
used to write. **That copy no longer exists**, because writing it black-screened
GNOME's login screen twice and the whole mechanism is switched off. So as
written, this greeter would come up at 100% too.

The fix is genuinely easier here than it was for GDM, and it is why this is the
R5 job rather than another attempt at Part A: **this login screen runs in our
own compositor.** labwc does part sizes properly, and the greeter can be told
its scale directly instead of having a file smuggled to it — no copying, no
`gdm` user, no file that a compositor might silently reject.

Until that is done, you can set the login screen's size by hand with a single
line in `/var/lib/aquarius/greeter-display.conf`:

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
4. **Is it the right size on the 55" monitor?** **Expect tiny** — see "Where it
   gets its size" above: it reads a file that AquariusOS no longer writes, and
   fixing that properly is the R5 job. To make it the right size today, put
   `scale=1.5` in `/var/lib/aquarius/greeter-display.conf` and restart greetd.
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
| `/etc/dconf/db/gdm.d/03-aquarius-scale` | the old switch that used to be needed for part sizes. Belt only — GNOME 50 turns them on by itself. It does **not** decide whether part sizes are used; `aq login scale` does. |
| `/etc/dconf/db/gdm` | the built database. **This** is what GDM reads; the three files above do nothing until `dconf update` bakes them into it. |
| `/usr/libexec/aquarius-gdm-display` | the messenger. **Switched off by default**, and with the switch off its job is to REMOVE a copy an older AquariusOS left behind. |
| `/usr/libexec/aquarius-monitors-sanitize` | when it is switched on, **makes that copy safe first** — rounds part sizes, refuses files it cannot understand. Read its header for the full rule table. |
| `/usr/lib/systemd/system/aquarius-gdm-display.service` | runs the messenger at every boot, before the login screen |
| `/usr/libexec/aquarius-gdm-guard` | the rescue: removes the copies and restarts the login screen if it never appeared. Its trigger is three questions, not one — see "why it did not save the bench". |
| `/usr/lib/systemd/system/aquarius-gdm-guard.service` | runs the rescue once per boot, after the login screen starts |
| `/usr/lib/systemd/system/graphical.target.wants/` | the two links that switch those services on. **Under `/usr`, not `/etc`** — see "How these services are switched on". |
| `/etc/gdm/PostSession/Default` | runs the messenger again at every logout — **but only if the switch is on**. Otherwise it does nothing, like Fedora's. |
| `/usr/share/aquarius/gdm-PostSession-Default.orig` | Fedora's version of that file, kept so the difference is a fact and not a memory |
| `/etc/xdg/monitors.xml` | the copy of your display arrangement the login screen reads. **Should not exist** on a default machine. |
| `/var/lib/gdm/.config/monitors.xml` | the older second copy. Also should not exist. Probably dead on GDM 49+ anyway — see Part A. |
| `/var/lib/aquarius/display-scale` | one number: the scale, for our own greeter to read. Only written while the copy is switched on. |
| `/var/lib/aquarius/gdm-display.log` | **what happened, in plain English.** The first thing to read when the login screen is the wrong size. |
| `/var/lib/aquarius/gdm-display-optin` | **the master switch.** Present only if somebody ran `sudo aq login scale on`. Never shipped in the image. |
| `/var/lib/aquarius/gdm-fractional-ok` | the sub-mode, and only means anything alongside the switch above. Present only after `sudo aq login scale fractional`. Never shipped. |
| `/run/aquarius/gdm-guard-acted` | the guard's "already tried this boot" stamp. Under `/run`, so it clears at every restart. |
| `tests/test-gdm-scale-sanitize.sh` | the rule table and the off-by-default behaviour, executed. Runs on every build, before and inside the image. |
| `tests/test-gdm-guard.sh` | **the guard's trigger, executed** against fake system commands — both "act" and "stand aside". It exists because on 5 September a trigger that had never been run turned out not to work. |

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

---

## What we found out about GNOME while fixing this

Recorded so nobody repeats the research. Every claim here has a source; the
short version is in the incident section at the top.

| Question | Answer |
| --- | --- |
| Are part sizes still experimental in GNOME? | **No, not since GNOME 50** (March 2026). GNOME's window manager stopped marking framebuffer scaling and native Xwayland scaling as experimental in a change merged 2 February 2026, and the GNOME 50 release notes call it the first stable version. AquariusOS is Fedora 44, which is GNOME 50. |
| So is the `03-aquarius-scale` setting pointless? | Nearly. It changes nothing while GNOME's own default holds. It is kept because it costs one line and it keeps part sizes working on the login screen if Fedora ever turns that default back off. |
| Does the login screen read settings from `/etc/dconf/db/gdm.d/`? | **Yes**, and this is the mechanism to rely on. It is a file path, so it keeps working regardless of which temporary user the login screen is running as. |
| Does copying a file into the `gdm` user's home still work? | **Probably not, since GDM 49.** GDM stopped using a permanent `gdm` account and now gets a temporary one per session, so there may be no home folder to write into. There is an open bug about exactly this. `/etc/xdg/monitors.xml` is the path that matters. |
| Is "black screen, cursor only" a known result of a part size? | **Not confirmed by anybody upstream.** What *is* documented is that GNOME can reject a whole display arrangement that does not match the monitors plugged in and fall back to defaults, and that a part size can be silently ignored. Neither of those is a black screen. Our evidence is the bench, and it is strong (removing the files fixed it) but it is one machine. This is why the guard exists. |
