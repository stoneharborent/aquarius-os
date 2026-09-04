# How big things are on the screen

*Written 2026-09-03, after the bench test. Assumes you have never used Linux.*

---

## The short version

On the bench, the Aquarius Desktop drew everything **far too small** — Royce's
words were *"really small icons… will need to size everything up."*

Nothing was broken. The desktop was simply running the monitor at 100%, while
GNOME on the same computer had been running it at 125% for weeks. Nobody had
told our session about that.

Now somebody does. Every time you log into the Aquarius Desktop, one small
program works out the right size for each screen and applies it before the bar
is drawn.

**The command you actually need:**

```
aq display scale 1.25      make everything on the screen 125% size
aq display status          what is it set to, and why
aq display auto            forget my answer, work it out again
```

---

## Two different sizes, and it matters that they are different

This trips people up, so it is worth thirty seconds.

| | What it makes bigger | When you want it |
|---|---|---|
| **`aq display scale`** | **Everything.** Firefox, DaVinci Resolve, your file manager, and the Aquarius bar along with them. | "Everything on this screen is too small." This is the one you almost always want. It is the same setting GNOME calls **Scale**. |
| **`aq display ui`** | **Only our own bar, dock, search box and panels.** Your applications are untouched. | "The bar is too small but everything else looks right." This is a design dial for tuning the Aquarius Desktop itself. |

`scale` takes effect immediately. `ui` takes effect the next time you log in,
because the bar reads that setting once, when it starts.

Both are stored in one small file you can read:
`~/.config/aquarius/display.conf`.

---

## Where the answer comes from — three places, in this order

The program asks three questions and stops at the first one that answers.

### 1. Your own setting

`~/.config/aquarius/display.conf`, written by `aq display scale`. If it is
there, it wins, and nothing else gets a vote. That is the point of having it.

### 2. What you already told GNOME

`~/.config/monitors.xml` — the file GNOME writes when you move the Scale slider
in its Displays panel.

Reading it means **the Aquarius Desktop inherits the answer you already gave**,
on the very first login, without asking you the same question twice. On the
bench that file said 125%, which is exactly the number that should have been
applied and was not.

If several monitor arrangements are saved in it (desk with two screens, laptop
on its own), the one whose screens match what is plugged in right now is used.

### 3. A guess from the monitor itself

Only if neither of the above exists. The monitor reports two things: how many
dots the picture is, and how many millimetres of glass that is spread across.
Divide one by the other and you get **dots per inch**, which is the honest way
to ask "is this screen dense, or is it just large?".

**The rule, in full:**

| Dots per inch | Scale applied | What that is, in real monitors |
|---|---|---|
| under 110 | **100%** | An ordinary desktop monitor. Also a 55" 4K (81 dpi) and a 49" ultrawide (108 dpi) — see the warning below. |
| 110 – 149 | **125%** | A dense 1440p laptop panel, a 32" 4K |
| 150 – 189 | **150%** | A 27" 4K, and the 57" 7680×2160 Odyssey G9 (164 dpi) |
| 190 – 239 | **175%** | Most "retina"-class laptop screens |
| 240 and up | **200%** | A very dense laptop or tablet panel |

**If the monitor does not say how big it is** — cheap ones and every virtual
machine do not — there is no honest DPI to work with. Then, and only then, it
counts dots instead: 2000 or more tall gets 200%, anything less stays at 100%.
That is a coarse rule and it is meant to be. The log says so, and the fix is to
run `aq display scale` once.

### ⚠️ Why the guess is the LAST question, not the first

Royce's monitor is a **Samsung Odyssey Ark: 55 inches, 3840×2160**. Work out its
DPI and you get **81** — *lower than an ordinary 1080p office monitor*. On the
numbers alone, the correct answer for that screen is 100%.

He runs it at 125%, because you sit further back from a 55" screen than the
arithmetic assumes.

That is the whole argument for the order above, and it is why "read the monitor"
comes third and not first. **A guess is a last resort. Somebody who has already
answered the question should never be asked again, and must never be
overruled.**

---

## What about fractional sizes like 125%?

They work properly.

The window manager AquariusOS uses (labwc 0.20) supports the standard
*fractional scale* protocol. An application that understands it — every modern
GTK4 and Qt6 program, which is most of what you will run — is told "draw
yourself at 1.25" and draws crisply at that size. Older applications are drawn
at the next whole number up and shrunk, which is very slightly soft but never
broken.

### ⚠️ The honest exception: X11 applications, including DaVinci Resolve

Some programs do not speak Wayland at all and run through a compatibility layer
called **XWayland**. DaVinci Resolve is one of them.

**XWayland gets no automatic scaling.** That is a limitation of X11 itself, not
something AquariusOS is doing wrong, and no Linux desktop fixes it — GNOME and
KDE have the same problem. On a scaled screen, an X11 application is either
drawn at its normal size (so it looks small next to everything else) or blown up
by the window manager (so it looks slightly soft).

**AquariusOS does fix it for Resolve specifically**, because Resolve is the
application this operating system exists for. Its launcher asks this helper what
the session is scaled by — `aquarius-display-scale --effective-scale`, which
prints one number and always answers — and hands that to Resolve's toolkit on
the way in. So Resolve opens at the size everything else is, without anybody
setting anything.

To give Resolve a different size from the rest of the desktop:

```
aq resolve scale 1.5     Resolve at 150%, whatever the desktop is at
aq resolve scale auto    back to following the desktop
```

Resolve's own setting still exists and is still the better tool for fine
adjustment: **DaVinci Resolve → Preferences → User → UI Settings → UI Display
Scale.**

Every *other* X11 application is still unscaled, and there is nothing anybody
can do about that from outside the application.

---

## What AquariusOS sets, and what it deliberately does not

Different kinds of application find out about the screen size in different ways.
Setting a variable for a toolkit that already knows is not a helpful extra
belt — it is a second opinion, and the two opinions end up disagreeing.

| Kind of application | How it learns the size | What we set |
|---|---|---|
| GTK4 (GNOME apps, Files, most Flatpaks) | Asks the compositor, over the fractional-scale protocol | **Nothing.** It already knows, and setting `GDK_SCALE` on top would double-apply and make everything enormous. |
| Qt6 (the Aquarius Shell, Qt apps) | Asks the compositor, the same way | **Nothing.** Qt6 enables high-DPI scaling on Wayland by itself; `QT_ENABLE_HIGHDPI_SCALING` exists for Qt5-era software and would be a second opinion here. |
| GTK3 | Asks the compositor, but only understands whole numbers | **Nothing.** At 125% it is drawn at 200% and shrunk, which is the standard behaviour everywhere. |
| X11 / XWayland (DaVinci Resolve, some plugins) | It cannot be told | **Nothing, and nothing would help.** See the box above — use Resolve's own UI Display Scale. |
| The Aquarius Shell's own design | `AQ_UI_SCALE`, on top of everything above | Only if you set `aq display ui`. Normally unset — the shell's own sizes were moved on 2026-09-03 to the size Royce approved on the bench, so 1 already *is* that size. |

So the honest summary: **the compositor does the work, we set no toolkit
variables at all, and X11 applications are on their own.** Anything else would
be a guess layered on top of a correct answer.

---

## Checking it on the bench

Log into the **Aquarius Desktop** and open a terminal (Command-Return).

```
aq display status
```

That prints your setting, every screen with its size and dots-per-inch, and
where each answer came from.

To see the whole reasoning without changing anything:

```
/usr/libexec/aquarius-display-scale --explain
```

And the session log records what it did at login, every time:

```
grep display ~/.local/state/aquarius-session/session.log
```

---

## If something is wrong

**Everything is still tiny after logging in.**
Run `aq display status`. If it says the scale is 100% and you expected more,
either your `monitors.xml` does not name this monitor the same way (the log will
say so), or you never set a scale in GNOME. Fix it in one command:
`aq display scale 1.25`.

**Everything is enormous and I cannot read anything.**
`aq display auto` puts it back. If the bar is so large you cannot find the
terminal, log out with Command-Shift-E, log into GNOME, and run it there — the
setting is a file, and it is read at the next Aquarius login either way.

**It changed size while I was working.**
It should not. The size is set once, at login, before the bar is drawn. If you
see it change later, something else is calling `wlr-randr`, and the session log
will not mention it.

**I want a different size on each monitor.**
Edit `~/.config/aquarius/display.conf` and add a line naming the screen, using
the name `aq display status` prints for it:

```
scale=1.25
scale.DP-2=1.0
```
