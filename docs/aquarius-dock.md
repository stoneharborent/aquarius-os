# The Aquarius Dock

*Built 2026-08-31. Tier 2, Track F of the V2 shell work; the plan it implements is
`docs/v2-shell-tier2-research.md`, "Layer 3 — Dock". Everything here assumes zero
Linux experience.*

## What this change is, in one paragraph

The dock at the bottom of the AquariusOS screen used to be KDE's own widget with
our artwork on it. It is now **our own widget** — the same KDE code, copied into
this repo, with three things added that the design asks for and KDE has no
setting for: the icon **lifts** when you point at it, a **dot** sits under an app
that is running, and a dashed **"+" tile** at the end opens the full-screen app
grid. Everything else about it — pinned apps, grouping, drag-to-reorder,
right-click, tooltips — is KDE's code, untouched.

Copying somebody else's code is a decision with a running cost, not a one-off
task. Most of this document is about that cost, because it is the part that is
easy to forget and expensive to rediscover.

---

## Why we had to copy the code at all

The three things the design asks for are all *behaviour*, and KDE's dock has no
setting for any of them:

| The design asks for | Could a setting do it? |
|---|---|
| Icon lifts and grows on hover | No. There is no such option, and an open request for it upstream. |
| A round dot centred under a running app | No — and not artwork either, see below. |
| A dashed "+" tile that opens the app grid | No. Nothing like it exists. |

The dot deserves a note, because we tried the cheaper route first and it does not
work. AquariusOS already has its own **Plasma Style** — the artwork behind the
panels and the dock tiles. Artwork would have been the tidy place for a dot. But
Plasma builds a tile out of nine pieces and stretches the middle ones to fit, so a
dot drawn in the middle becomes a *bar* as wide as the tile, and a dot drawn in a
corner stays stuck in that corner. There is no piece that is both fixed-size and
centred. The long version is written into the theme file itself
(`system_files/usr/share/plasma/desktoptheme/aquarius/widgets/tasks.svg`) so
nobody tries again.

So: the dot has to be drawn by the widget, and the widget has to be ours.

---

## Where the code came from

| | |
|---|---|
| Project | plasma-desktop — https://invent.kde.org/plasma/plasma-desktop |
| Folder | `applets/taskmanager/` |
| Branch | `Plasma/6.7` |
| Exact commit | `fda2a22c081b5baad4c8348eaf3693af0d6cc6ce` |
| Taken on | 2026-08-31 |
| Licence | GPL-2.0-or-later — unchanged, and every original copyright line kept |

It lives in this repo at

```
system_files/usr/share/plasma/plasmoids/com.aquariusos.dock/
```

and inside that folder is **`FORK-NOTES.md`**, which lists every single line we
changed and why. This document is the overview; that file is the precise record.
**Before editing anything in that folder, read it.**

Of the 25 files in there: **12 are byte-for-byte identical to KDE's**, 11 are
modified, and 2 we wrote.

---

## The surprise we found, and what it cost

The plan for this work assumed the dock was "all QML" — QML being the
plain-text, human-readable language Plasma widgets are written in — and that we
could copy those text files, change three things, and ship.

**That turned out to be wrong on Plasma 6.7, and it is worth writing down.**

On Plasma 6.7, KDE's task manager is *not* a folder of text files any more. It is
a **compiled program file**, and it carries its QML inside itself, together with a
helper written in C++ — a language that has to be compiled, and that QML cannot
stand in for. The compiled part does a handful of jobs the text part cannot.

That left three ways forward:

### The three options

**Option 1 — copy the text files, live without the C++ helper.** ← *what we did*

Ship the ordinary way: a folder of QML. Everything Plasma promises about widgets
applies — it keeps working across Plasma updates without us rebuilding anything.
The cost is that whatever the C++ helper did, we do without.

**Option 2 — compile our own copy of the whole thing, C++ and all.**

We already compile two window-manager add-ons from source in this image
(`docs/kwin-effects-layer.md`), so it is not unthinkable. It would keep every
last feature, and our changes would stay a genuinely tiny diff.

Rejected, for a reason worth understanding: a compiled add-on has to be **rebuilt
against each new Plasma**, and if it is not, it does not degrade — it fails to
load at all. We accept that cost for the rounded-corners effect because there is
no alternative. For the dock there *is* an alternative, and the whole reason the
plan chose a widget over a compiled add-on was to escape that treadmill. Paying
it anyway, for a dock, is the wrong trade. It also drags in KDE's entire build
setup, because that one applet links against six other KDE libraries and borrows
a settings file from a completely different part of the source tree.

**Option 3 — write a dock from scratch on the public window-list API.**

Start from nothing and build up. Total freedom, and no copied code to re-sync.

Rejected because "everything else" is not small: grouping windows, drag-to-
reorder, the right-click menu, tooltips with live window previews, audio
indicators, progress bars, keyboard navigation, right-to-left layouts,
accessibility. That is years of accumulated KDE work, and rewriting it to gain
three animations would be a bad trade in both directions — more work *and* a worse
dock.

### What Option 1 actually costs

Nothing visible, except in one place: **the right-click menu is shorter.**

Gone:

- an app's own shortcuts — "New Private Window", "Compose Message", and so on
- the list of files you recently opened in that app
- Dolphin's bookmarked folders, under Dolphin's icon

Still there, because these come from the window manager rather than the deleted
helper: Close, Minimise, Maximise, Move to Desktop, Move to Activity, Pin and
Unpin, More Actions, and the media-player controls.

And three smaller things, listed for honesty rather than because they will be
noticed:

- **No number badges and no progress bars on dock icons** — the "3 unread" dot
  some apps put on their icon, and the bar that fills up during a long copy. Both
  are opt-in: an app has to broadcast them, and most do not.
- The little speaker badge may not appear for apps that play sound through a
  separate helper process — Chrome-based browsers and Electron apps are the usual
  ones. Apps that play their own sound are unaffected.
- A browser's tooltip will not add the currently-playing media title to the
  window title.

This was not a surprise to the plan. The research note predicted precisely this,
citing a previous dock fork that lost its jump lists the same way.

**If the jump lists turn out to matter**, Option 2 is the answer, and this
document is the record of what it would take.

---

## What the "+" tile does when you click it

It asks Plasma to open the app launcher — using Plasma's own published way of
asking, `activateLauncherMenu`.

Plasma then looks through the panels for whichever widget says "I am an app
launcher", and opens that one. On AquariusOS that is the AquariusOS mark in the
top bar, which the desktop layout sets to **Application Dashboard**: the
full-screen grid of every installed app with a live search box. That is exactly
the surface the design draws.

Two things make this better than just launching something:

- It opens **the same** launcher the logo opens, not a second copy.
- If the top-bar launcher is ever swapped for a different one, the "+" tile
  follows it automatically — nothing here names a specific launcher.

`FORK-NOTES.md` lists the six other approaches that were considered and why each
is worse. The short version: one of them does not exist, one opens a stray extra
window, and the rest open the wrong thing entirely.

---

## The follow-up this creates: a leftover underline in the theme

Before the dock could draw a dot, the theme marked a running app with a **2-pixel
starlight underline** instead. It was always described as a stopgap.

Now that the dot exists, an app that is running gets **both** — a line *and* a dot.

**This branch deliberately does not fix that**, because the theme is being worked
on separately and two people editing one file is how work gets lost. The exact
elements to delete are listed in `FORK-NOTES.md`, under B2: seven states, three
rectangles each, identified by their group names.

One judgement call is flagged there and is worth Royce's eye: the `attention`
state (an app flashing for your attention) also uses that underline, and a
flashing line is a *different signal* from "this app is running". It may be worth
keeping that one.

---

## Keeping up with KDE — the honest cost of owning a copy

This is the part that is easy to skip and expensive to relearn.

**Nothing here needs doing on a schedule.** A copied widget does not rot. It will
keep working across Plasma updates on its own — that is the entire reason we chose
this shape over a compiled add-on.

There are exactly two moments that call for attention:

### 1. The build fails with "the Aquarius Dock would not load"

That is `build_files/dock-check.sh` doing its job. It runs on every build and
checks that every piece of KDE the dock leans on is actually in the image. When
Bazzite moves to a newer Plasma and something got renamed, this is what tells you
— at build time, in seconds, instead of on the machine after a reinstall, where
the only symptom would be **a dock that is silently not there**.

The error message names the missing piece and what to do. Usually it is a rename:
find where it went, update the import line, note it in `FORK-NOTES.md`.

### 2. You want something KDE added since we copied

Only then is a re-sync worth doing. The procedure:

1. **Get the same folder at the new version.** On any machine with `curl` and
   `tar`:

   ```bash
   # Replace 6.9 with the Plasma version you want
   SHA=$(curl -s "https://api.github.com/repos/KDE/plasma-desktop/branches/Plasma%2F6.9" \
         | python3 -c "import json,sys; print(json.load(sys.stdin)['commit']['sha'])")
   echo "$SHA"   # write this down — it goes in metadata.json
   curl -sL "https://github.com/KDE/plasma-desktop/archive/${SHA}.tar.gz" -o pd.tar.gz
   tar -xzf pd.tar.gz "plasma-desktop-${SHA}/applets/taskmanager"
   ```

2. **See what KDE changed**, between the commit recorded in `metadata.json` (key
   `X-AquariusOS-Fork-Commit`) and the new one. Only that folder matters:

   ```
   https://github.com/KDE/plasma-desktop/compare/<old-sha>...<new-sha>
   ```

   If nothing under `applets/taskmanager/` changed, stop — there is nothing to
   re-sync.

3. **Copy the new files in**, using the same folder mapping `FORK-NOTES.md`
   records (`qml/` becomes `contents/ui/`, and so on).

4. **Re-apply our changes**, working through `FORK-NOTES.md` in order. The
   "Kind A — plumbing" ones are mechanical, mostly search-and-replace. The
   "Kind B — the design" three are hand edits, and each is marked in the code with
   a comment beginning `AQUARIUS DEVIATION` so they are easy to find.

5. **Update `metadata.json`** — the `X-AquariusOS-Fork-Commit` key — and the
   commit table at the top of `FORK-NOTES.md`.

6. **Build, then run the bench checklist below.** There is no substitute for it;
   see the next section for why.

**Rough effort:** an hour or two if KDE only tidied things, a day if they
restructured. The `AQUARIUS DEVIATION` comments are what keep it at the low end,
which is why every one of them exists and why new changes must add one.

---

## What we could not check on Royce's Mac

Worth being blunt about, because it shapes how much to trust this until it is
booted:

- **`qmllint` does not run on macOS.** It is the tool that would catch a typo in a
  QML file, and it only works with a real Plasma installed. It was not run.
- **Nothing ran the dock.** Everything below is unverified on hardware.

What *was* checked, by machine:

- every QML and JavaScript file has balanced brackets, quotes and comments
- `metadata.json` is valid JSON and its Id matches what the layout script asks for
- `contents/config/main.xml` is valid XML
- the desktop layout script parses as valid JavaScript
- the 12 carried files are byte-for-byte identical to KDE's
- no build-machine paths leaked into anything
- nothing imports the compiled-only `plasma.applet.*`

That is enough to rule out a whole class of silly mistakes. It is not enough to
say the dock works.

---

## Bench checklist

Run this on real x86 hardware after the first build that includes the dock. It is
ordered so that a failure early on explains the failures after it.

### Does it exist at all?

1. **The dock is there** at the bottom of the screen, with the pinned apps in it.
   *If the dock panel is empty or missing*, the widget did not load. Check:
   ```bash
   ls /usr/share/plasma/plasmoids/com.aquariusos.dock/
   journalctl --user -b -u plasma-plasmashell | grep -i -A5 'com.aquariusos.dock\|QQmlApplicationEngine\|is not a type'
   ```
   A "is not a type" or "module not installed" line names the exact problem.

2. **All five pinned apps appear** — browser, Steam, Files, Console, Settings —
   as before. This confirms the widget reads the same `launchers` setting the old
   one did.

3. **Icons are the right size** and the dock is not stretched across the screen.
   *If it looks like a wide Windows taskbar with text labels*, the icons-only
   check failed — see `FORK-NOTES.md` A2.

### The three new things

4. **Hover lift** — point at an icon. It should rise slightly and grow, quickly
   and smoothly, and settle back when you move away. Check it does not clip at
   the top of the dock.

5. **Running dot** — open an app. A small blue dot should appear centred *under*
   its icon. Close the app: for a pinned app the dot goes and the icon stays; for
   an unpinned one both go.

6. **Only one running mark.** If you see a dot **and** a line under a running app,
   that is the expected leftover described above — note it, it is a theme
   follow-up, not a dock bug.

7. **The "+" tile** is at the right-hand end, dashed, with a `+` in it, and lines
   up with the app icons. It should sit *inside* the dock's background, not
   hanging off the end.

8. **Clicking "+"** opens the full-screen app grid — the same one the AquariusOS
   logo in the top bar opens. Typing should search immediately. Escape closes it.

9. **The "+" tile lifts on hover** like the app icons do.

### Nothing else broke

10. **Click an app** — it launches, or comes to the front if already running.
11. **Drag an icon** sideways to reorder. The lift should *not* fight the drag.
12. **Drag an app out** of the dock to unpin it.
13. **Right-click an app.** Close / Minimise / Maximise / Move to Desktop / Pin /
    More Actions are all present. The app's own shortcuts and Recent Files are
    **expected to be absent** — that is the known cost, not a bug.
14. **Hover for a tooltip.** The window preview should appear.
15. **Group behaviour** — open two windows of one app; they group into one icon,
    and clicking it offers both.
16. **Play audio** in an app. The speaker badge should appear. *Browsers and
    Electron apps are the known exception.*
17. **Widget settings** — right-click the dock, Configure. Both pages open, and
    changing icon spacing takes effect.
18. **Turn off "highlight windows on hover"** in those settings; confirm the lift
    stops too.
19. **Reboot.** The dock comes back with the same pinned apps in the same order.

### Photograph it

20. Against `branding/design-system/AquariusOS Desktop Shell.html`: the lift
    distance, the dot's size and colour, and the "+" tile's dash pattern are the
    three things most likely to be *nearly* right, and a side-by-side photo is
    the fastest way to judge them.
