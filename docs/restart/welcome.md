# The welcome — the first three minutes of AquariusOS

*Written 2026-09-04, for Phase R5. Assumes you have never used Linux.*

---

## The one-paragraph version

Ten seconds after somebody logs in to a brand-new AquariusOS account, one window
opens. It asks two questions and then says goodbye:

| | |
| --- | --- |
| **Step 1 of 3** | *How should keyboard shortcuts work?* Mac, or Windows. Mac is already chosen. |
| **Step 2 of 3** | *Your creator apps.* The window you already know — tick what you want. |
| **Step 3 of 3** | *You're set.* Three things worth knowing, and a button that closes it. |

Then it never opens again. `aq welcome` brings it back if you want to see it.

---

## Why there is a welcome at all

Until 4 September 2026 the first login opened the creator-apps chooser and
nothing else. That window is good, but on its own it made a strange first
impression: a machine that says nothing whatsoever about itself, and then, ten
seconds in, asks you to go shopping.

More importantly it left the single most surprising thing about this operating
system **undeclared**.

AquariusOS remaps the keyboard to work like a Mac — **Copy is ⌘C** — by default.
That is deliberate (it is why FEATURES 008 exists, and it is Royce's call), it
is the right default for the people this OS is for, and it is exactly the sort
of thing an operating system has to say out loud on its first screen rather than
let somebody discover an hour later when their Ctrl+C stops working.

So: one flow, three steps, asked once.

---

## What a new person actually sees

### Step 1 — the keyboard

> **How should keyboard shortcuts work?**
>
> AquariusOS can work the way a Mac does. Most people who edit video came from
> one, so that is what it does unless you say otherwise.

Two large cards, side by side:

| **Mac** *(already chosen)* | **Windows** |
| --- | --- |
| Copy is ⌘C · Quit is ⌘Q · Search is ⌘Space | Copy is Ctrl+C |
| The key beside the space bar is Command. | The normal Linux and Windows shortcuts. |

Under them, one line that changes as you press a card — **Copy is ⌘C**, or
**Copy is Ctrl+C**. That line is the whole point of the page: it turns an
abstract question about "shortcut styles" into the one keystroke everybody
already has an opinion about.

And under that: *"You can change this any time. Open a terminal and type `aq
keys mac` or `aq keys windows` — it takes effect straight away, with no need to
log out."*

**Continue** saves the answer. **Skip** leaves it as it is, which is Mac.

> **Where the answer goes.** The welcome does not write the setting itself. It
> runs `aq keys mac` or `aq keys windows` — the same command you would type —
> which writes `~/.config/aquarius/keys.conf` and restarts the remapper. There
> is one program in this operating system that knows the format of that file
> and it stays that way; the build fails if the welcome ever learns it. The
> whole feature is explained in [`aquarius-keys.md`](aquarius-keys.md).

### Step 2 — your creator apps

This is the window that has been there since R3b, unchanged:
[`creator-apps.md`](creator-apps.md) describes it in full. The only differences
when the welcome opens it are cosmetic — it says **Step 2 of 3** beside its
title, and its last page offers **Continue** rather than **Close**, because the
welcome is still waiting behind it.

**Skip for now** is a complete answer here too. Nothing is installed unless you
press Install.

### Step 3 — done

> **You're set.**
>
> - **⌘Space searches everything.** Apps, files, settings, even sums.
> - **Aquarius Apps adds or removes apps any time.** Everything you skipped is
>   still there, and nothing you installed is stuck.
> - **GNOME is one arrow key away at login.** If the Aquarius Desktop ever gives
>   you trouble, the login screen can start a plain GNOME desktop instead.

One button: **Start using AquariusOS**. It closes the window, and that is that.

---

## If your account already exists — the migration

Royce's account on the bench machine has been through the creator-apps chooser
already. It has obviously never seen a welcome, because there was not one.

Asking him to choose his apps all over again would be rude, so it does not:

| What the account has | What it gets at the next login |
| --- | --- |
| Neither stamp *(a brand-new account)* | All three steps. |
| `creator-apps-seen` but no `welcome-seen` *(Royce's account)* | **Two** steps: the keyboard question, then the last page. The keyboard page says *"Your apps are already set up, so this is the only question — everything else stays exactly as you left it."* |
| `welcome-seen` | Nothing. It is done. |

The counting is honest either way: an account that gets two steps sees "Step 1
of 2" and "Step 2 of 2", not "Step 1 of 3" followed by "Step 3 of 3", which
would look like something had gone wrong.

The two files it looks at:

| File | Written by | Means |
| --- | --- | --- |
| `~/.config/aquarius/welcome-seen` | the welcome, the moment its window appears | you have been welcomed |
| `~/.config/aquarius/creator-apps-seen` | the creator-apps window, the moment it appears | you have been offered the apps |

Both are written when the window **appears**, not when it is finished with. The
promise is "you are asked once", and closing a window half way through is a
complete answer to a question.

---

## Seeing it again

```
aq welcome
```

That opens it at step 1, whatever the stamps say, and changes nothing until you
press something. There is also a hidden menu entry (`Aquarius Welcome`) that
does the same thing — hidden because a "Welcome" tile sitting in your apps
forever is clutter.

To make a *login* show it again, delete the stamp:

```
rm ~/.config/aquarius/welcome-seen
```

---

## How it opens by itself, once

Two files, because the two desktops start things differently:

| Session | What starts it |
| --- | --- |
| GNOME (the fallback) | `/etc/xdg/autostart/aquarius-welcome-firstrun.desktop` |
| The Aquarius Desktop | a block at the end of `/usr/share/aquarius/labwc/autostart` |

**labwc does not read `/etc/xdg/autostart` at all.** It reads exactly one file,
its own `autostart`, and that is deliberate — it is what keeps a dozen GNOME
background programs out of the Aquarius session. The cost is that anything which
must run at login in both sessions is written down twice, and the build checks
that the two copies still run the *same command*.

Both wait ten seconds, so the window arrives once the desktop has settled rather
than on top of a login screen. Both pass `--first-run`, which is what makes it
happen once.

> **⚠️ The two entries that used to be here are GONE.**
> `aquarius-creator-apps-firstrun.desktop` and the chooser's block in the labwc
> `autostart` were removed by this change. If either came back, a brand-new
> person would get the creator-apps window twice ten seconds after their first
> login — once by itself and once inside the welcome. Both the build and the
> post-build check fail if either reappears.

> **A note for whoever next syncs the `aquarius-shell` repository:** that repo is
> the home of the labwc `autostart` file and AquariusOS ships an adapted copy.
> Its copy still carries the creator-apps first-run block; the replacement lines
> are in the "For the shell repository" section at the bottom of this page.

---

## Why step 2 is a separate program

This is the design decision most likely to be second-guessed, so here is the
reasoning in one place.

The welcome **launches** the creator-apps window as a child program and waits
for it, hiding itself in the meantime. It does not draw the chooser's pages
inside its own window.

Embedding was considered on 2026-09-04 and rejected. The chooser is a
two-thousand-line window whose every page, footer and button was bench-tested by
Royce on 3 and 4 September. Its pages are built inside one function, as
closures, and around forty of its methods assume they are *on* a window: they
set the window title, swap the window's footer, close the window when an install
is cancelled. Turning that into a view that can live inside somebody else's
window is a rewrite of the file — and the thing being rewritten is the one part
of the first-boot experience already proved to work on real hardware.

A child program costs one flicker between two windows. The rewrite risks the
part that works. That trade is not close.

The flag that says "you are step 2" is `--embedded-flow`, and it changes exactly
three cosmetic things:

1. **It always opens.** `--first-run` means "open only if this person has never
   been asked", which is right for a login autostart and wrong here — the
   welcome has already decided. If both flags are given, this one wins.
2. **"Step 2 of 3" appears beside its title**, so the window reads as part of
   something with an end to it.
3. **Its last page offers "Continue" instead of "Close"**, because the welcome
   is still waiting behind it.

Run without the flag — from the app grid, from `aq apps`, from the build's
`--dry-run` — it is the same window it always was. The build checks that too.

---

## Looking at all of this without a screen

```
aquarius-welcome --dry-run
```

prints the steps, both keyboard cards, which one is preselected, and what this
account would actually be shown. It opens no window and changes nothing.

```
aquarius-welcome --dry-run --pretend-apps-seen
```

does the same as if this account had already been through the chooser — which is
how the build proves the migration rule works without needing an old account.

The shape of those lines is a contract: `build_files/67-welcome.sh` reads them.
Add lines to it freely; do not reword the ones already there.

---

## What the build checks

`build_files/67-welcome.sh`, during the build, and again in the finished image
in `.github/workflows/build-next.yml` — the twice-on-purpose habit that the rest
of this repo runs on. Every check reads content, never a timestamp.

- The window is there, is valid Python, can find the shared window pieces in
  `/usr/lib/aquarius/python`, and **builds every page on the shared `hero`
  helper** so every page carries the Aquarius mark. No `Adw.StatusPage`
  anywhere — that is the widget that gave three other windows a blank top on
  4 September.
- Python on this image can really load GTK 4 and libadwaita. (The way this
  breaks is a missing typelib: the packages are installed, the import fails, and
  the first person to find out is somebody logging in for the first time.)
- **Mac is still the preselected answer**, and the Mac card still says
  *Copy is ⌘C* while the Windows card says *Copy is Ctrl+C*. Four things in this
  operating system have to agree that Mac is the default and this is the one a
  person *sees*; a card that came up preselected the other way would look
  completely normal in a screenshot.
- The keyboard answer really is written by `aq keys`, and the welcome carries no
  copy of the `keys.conf` format.
- **The existing-account rule**: rehearsed as an account with `creator-apps-seen`,
  it must produce two steps with the apps step skipped, and the window must say
  so on screen.
- **The old first-login entries are gone**, in both places, and **the two new
  ones run the same command as each other**.
- `aq welcome` is in `aq --help` and `aq welcome --help` works — a command
  nobody can discover is a command nobody uses.
- **The creator-apps window still works on its own**, and only claims to be
  "Step 2 of 3" when the welcome opened it.

---

## Testing it on the bench

Royce's account, then a fresh one. In this order, because the first two are
about the account that already exists and the third is the real exit test.

**1. What Royce's own account gets at its next login.**

His account has `creator-apps-seen` and has never had `welcome-seen`, so there
is nothing to delete. Log out, log back in, wait ten seconds:

- The welcome opens, saying **Step 1 of 2**.
- It asks the keyboard question, with **Mac** already chosen and *Copy is ⌘C*
  under the cards. Press **Windows** — the line changes to *Copy is Ctrl+C*.
  Press **Mac** again.
- It says *"Your apps are already set up"*, and there is **no apps step**.
- **Continue** → **Step 2 of 2**, "You're set.", three tips.
- **Start using AquariusOS** closes it.
- `aq keys status` still says Mac, and Cmd+C still copies.
- Log out and back in again: **nothing opens.** That is the stamp working.

**2. The whole thing, on demand.**

```
aq welcome
```

- Three steps this time, because `aq welcome` never skips anything.
- Step 2 opens the creator-apps window, titled **Step 2 of 3**, with its
  familiar list. Press **Skip for now** — the apps window closes and the welcome
  comes back at **Step 3 of 3**.
- Run it again and this time press **Install** on one small app instead. When it
  finishes, the last page's main button should say **Continue**, not Close;
  pressing it returns to the welcome.

**3. A brand-new account — the real test.**

Make one in GNOME Settings → Users (or `sudo useradd -m tester && sudo passwd
tester`), log out, and log in as that person:

- Ten seconds in, the welcome opens at **Step 1 of 3**.
- Mac is preselected. Choose either.
- **Step 2 of 3** is the apps window, with nothing installed on this account yet.
- **Step 3 of 3** finishes it.
- Log out and back in as that person: nothing opens.
- Worth doing once in **each session** — the Aquarius Desktop and the GNOME
  fallback — because the two start things in completely different ways and this
  is exactly the sort of thing that works in one and not the other.

---

## For the shell repository

`github.com/stoneharborent/aquarius-shell` carries its own
`session/labwc/autostart` (and the niri equivalent in `session/niri/config.kdl`)
so that the session can be started from a clone, on the bench or on plain
Fedora. That copy still has the creator-apps first-run block. It needs the same
change, or a session started from that repo will show a person the apps chooser
with no welcome around it.

The replacement is one word in two places — the block becomes:

```sh
if [ -x /usr/libexec/aquarius-welcome ]; then
    (
        sleep 10
        /usr/libexec/aquarius-welcome --first-run
    ) >> "${AQ_LOG:-/dev/null}" 2>&1 &
fi
```

The comment above it should say what this file's does: the welcome asks about
the keyboard, then opens the creator-apps window itself as step 2, and the
chooser is still an ordinary app in the app grid. **This file
(`system_files/usr/share/aquarius/labwc/autostart`) is the authoritative one**;
the two are kept in step by hand.

---

## Where to go next

- **The keyboard feature the first step switches:** [`aquarius-keys.md`](aquarius-keys.md)
- **The apps the second step offers:** [`creator-apps.md`](creator-apps.md)
- **Everything else in the restart:** [`README.md`](README.md)
