# Aquarius Dock — what we changed, and where

This widget is **KDE's task manager, copied**, with a small number of changes.
This file lists every one of them. If you are about to edit something in here,
read the entry for that file first.

The beginner-facing version of this story — why we forked at all, what it costs
us, and how to pull in a newer KDE — is in `docs/aquarius-dock.md` in the
`os-image` repo. This file is the precise list.

## Where the code came from

| | |
|---|---|
| Upstream project | [plasma-desktop](https://invent.kde.org/plasma/plasma-desktop) |
| Upstream path | `applets/taskmanager/` |
| Upstream branch | `Plasma/6.7` |
| Upstream commit | `fda2a22c081b5baad4c8348eaf3693af0d6cc6ce` |
| Taken on | 2026-08-31 |
| Licence | GPL-2.0-or-later, unchanged |

Every file keeps its original `SPDX-FileCopyrightText` and `SPDX-License-Identifier`
lines. Where we changed a file we added our own copyright line under KDE's; we did
not remove theirs, and we did not relicense anything.

The stock **Icons-Only Task Manager** is not a separate program. It is this same
code, with a small settings file that says "draw me without text labels". We did
the same thing, so this widget behaves as the icons-only one and reads the same
settings.

## The layout of this folder

Plasma expects a widget to be laid out one particular way, which is not the way
KDE's own source tree is laid out. So the files moved:

| Upstream | Here |
|---|---|
| `qml/*.qml` | `contents/ui/*.qml` |
| `qml/code/*.js` | `contents/ui/code/*.js` |
| `qml/config.qml` | `contents/config/config.qml` |
| `main.xml` | `contents/config/main.xml` |
| `metadata.json` | `metadata.json` (rewritten — see below) |

Nothing else moved and nothing was renamed.

## Files carried across untouched

These are **byte-for-byte identical** to upstream. Do not edit them. If one needs
a change, add an entry to the table further down at the same time, or the next
person re-syncing will overwrite your work without noticing.

```
contents/ui/AudioStream.qml
contents/ui/GroupExpanderOverlay.qml
contents/ui/PipeWireThumbnail.qml
contents/ui/PlayerController.qml
contents/ui/PulseAudio.qml
contents/ui/ScrollableTextWrapper.qml
contents/ui/ToolTipDelegate.qml
contents/ui/ToolTipInstance.qml
contents/ui/ToolTipWindowMouseArea.qml
contents/ui/code/TaskTools.js
contents/config/config.qml
contents/config/main.xml
```

That is **12 files carried, 11 modified, 2 written by us**
(`contents/ui/AquariusBackend.qml` and this file).

`contents/config/main.xml` being untouched is the important one: it is the list of
every setting this widget has. Because it did not change, the widget reads and
writes exactly the settings the stock one does, under the same names — including
`launchers` (the pinned apps) and `iconSpacing`. That is what lets the desktop
layout script switch to this widget by changing a single word.

---

## The changes, in full

There are **two kinds**. Knowing which is which is the whole point of this file:

- **Kind A — plumbing.** Changes forced on us by shipping as a folder of QML
  instead of as part of Plasma. They add no features. On a re-sync they are
  re-applied mechanically, mostly by search-and-replace.
- **Kind B — the design.** The three things we actually wanted. On a re-sync
  these are re-applied by hand.

### Kind A — plumbing

#### A1. The widget's own identity

**File:** `metadata.json` (rewritten)

Upstream's `metadata.json` is a stub — Plasma's build system fills in the rest
when it compiles the applet. Ours is a complete, ordinary widget metadata file.

- `Id` is `com.aquariusos.dock`
- `Name` is "Aquarius Dock"
- `X-Plasma-RootPath` is **absent**. In the stock icons-only widget that key means
  "I have no code of my own, use the task manager's". We *are* the code, so the key
  must not be here — with it, every change in this folder would be ignored.
- Eike Hein's authorship is kept, ours added alongside.
- Three `X-AquariusOS-Fork-*` keys record the upstream commit, so the machine
  itself can tell you what it was built from.

#### A2. Recognising ourselves as an icons-only dock

**Files:** `main.qml`, `ConfigAppearance.qml`, `ConfigBehavior.qml`,
`TaskBadgeOverlay.qml`, `code/LayoutMetrics.js` — **11 occurrences**

Upstream decides "am I the icons-only version?" by comparing its own name against
the literal text `"org.kde.plasma.icontasks"`. Our name is different, so every one
of those tests would answer "no" and we would get the wide, text-labelled taskbar
instead of a dock — including losing the `iconSpacing` setting, which is only read
in icons-only mode.

Each occurrence has the literal swapped to `"com.aquariusos.dock"`. Nothing else
about those lines changed.

> **Re-sync:** this is a plain search-and-replace of the old string for the new
> one across `contents/`. If a re-sync leaves the dock looking like a Windows
> taskbar, this is the change that was missed.

#### A3. Standing in for the C++ half

**Files:** `main.qml`, `Task.qml`, `ContextMenu.qml`, `TaskList.qml`,
`GroupDialog.qml`, `MouseHandler.qml`, `TaskProgressOverlay.qml`
**Plus one new file:** `contents/ui/AquariusBackend.qml`

This is the deviation with real consequences. Read this one properly.

On Plasma 6.7 the stock task manager is **not** a folder of QML files. It is a
compiled program file that carries its QML *inside itself*, together with a C++
helper class. Its QML reaches that helper by writing

```qml
import plasma.applet.org.kde.plasma.taskmanager as TaskManagerApplet
```

That import only works from inside that compiled file. A widget shipped as a
folder — the ordinary, stable way, and the way we ship — cannot use it.

So the import is gone from all seven files, replaced by:

| Upstream wrote | We write | What it is |
|---|---|---|
| `TaskManagerApplet.LayoutMetrics.…` | `LayoutMetrics.…` | `import "code/LayoutMetrics.js"` — the same file, imported directly |
| `TaskManagerApplet.TaskTools.…` | `TaskTools.…` | `import "code/TaskTools.js"` — the same file, imported directly |
| `TaskManagerApplet.Backend` | `AquariusBackend` | **our stand-in**, `contents/ui/AquariusBackend.qml` |

The first two cost us nothing at all: those two files are plain JavaScript, we
carry them, and importing them directly is how this same code did it before KDE
started compiling the applet.

The third is a genuine loss, because the helper was C++ and some of what it did
cannot be done from QML. `AquariusBackend.qml` provides every method under the
same name so nothing breaks, and each one documents what it can and cannot do.
In short:

| What it did | Now |
|---|---|
| `globalRect` — where an icon is on screen | **works**, done in QML |
| `tryDecodeApplicationsUrl` | returns the URL unchanged; affects only drag-out to other apps |
| `isApplication` | guesses from the URL's shape instead of asking the system |
| `parentPid` | **gone** — the speaker badge may not appear for apps that play sound from a helper process (Chromium, Electron) |
| `applicationCategories` | **gone** — a browser's tooltip will not add the media title |
| `jumpListActions`, `placesActions`, `recentDocumentActions` | **gone** — see below |
| `setActionGroup` | **gone** — virtual-desktop menu entries no longer un-tick each other |

**The jump lists are the real loss.** Right-clicking an app no longer shows the
app's own shortcuts ("New Private Window", "Compose Message"), its recent files,
or Dolphin's bookmarked folders. Those were built from C++ objects that QML has
no way to create.

Everything *else* in the right-click menu is untouched, because it comes from the
window manager rather than from that helper: Close, Minimise, Maximise, Move to
Desktop, Move to Activity, Pin/Unpin, More Actions, and the media-player controls.
`ContextMenu.qml` already drops a menu section that has no entries, so no empty
headings are left behind.

This was predicted. `docs/v2-shell-tier2-research.md` notes that a private-plugin
removal had broken a dock fork's jump lists before. It is the price of not
compiling the applet ourselves; `docs/aquarius-dock.md` explains why we judged
that price worth paying.

> **Re-sync:** if upstream adds a new `Backend` call, the dock will fail quietly
> at that spot. Add a matching function to `AquariusBackend.qml` — even one that
> returns nothing — and document it in the table above.

#### A4. The "smart launcher" — badge counts and progress bars

**File:** `Task.qml`, in `onSmartLauncherEnabledChanged` (now empty)

Same root cause as A3, but a separate place in the code, so it gets its own entry.

Upstream builds a helper here that listens for two extras an app can broadcast
about itself:

- **a count** — the little number badge on an icon, "3 unread"
- **a progress bar** — a bar across the icon while a copy or download runs

Both come from a C++ class, `SmartLauncherItem`, reached with:

```qml
Qt.createComponent("plasma.applet.org.kde.plasma.taskmanager", "SmartLauncherItem")
```

We cannot reach it, and QML cannot build one. Leaving the line in would not fail
loudly — it would throw inside a signal handler every time an icon appeared and
quietly fill the log — so the body is empty and `smartLauncherItem` stays `null`.

**Nothing else needed changing.** Every place that draws a badge or a progress bar
already checks `task.smartLauncherItem` first, so those overlays are never asked
for. `TaskBadgeOverlay.qml` and `TaskProgressOverlay.qml` are still here, so
restoring this means restoring one function rather than three files.

**Cost:** no unread-count badges and no progress bars on dock icons. Both are
opt-in — an app has to broadcast them, and most do not.

> **Re-sync:** `build_files/dock-check.sh` fails the build on any
> `plasma.applet.*` string, so a paste-over of this function is caught
> automatically. It is how this one was found in the first place.

---

### Kind B — the design

All three come from `branding/design-system/AquariusOS Desktop Shell.html`,
the dock section, and its `--dur-fast` (120ms) and `--ease-out`
(`cubic-bezier(.22, 1, .36, 1)`) tokens.

#### B1. The hover lift

**File:** `Task.qml` — on `iconBox`

The icon rises 4px and grows to 108% when the pointer is over it, over 120ms,
using the design's easing curve.

Three deliberate decisions:

- **The icon moves, the tile behind it does not.** Moving the tile too would drag
  the highlight off the dock's hairline border — the exact problem the theme's 4px
  artwork inset exists to prevent (see the long comment in the theme's `tasks.svg`).
- **No lift while dragging.** The icon is already following the pointer; a second
  animation fighting that looks broken.
- **Tied to the stock `taskHoverEffect` setting**, so turning hover effects off in
  the widget's settings turns the lift off too, as a user would expect.

#### B2. The running dot

**File:** `Task.qml` — new `aqRunningDot` element

A small round mark centred under any app that is running.

**Why it is in QML and not in the theme.** The theme's `tasks.svg` explains this
at length and it is worth not re-discovering: Plasma builds a tile from nine
pieces and stretches the middle ones, so a dot drawn in the middle becomes a bar
as wide as the tile, and a dot drawn in a corner stays pinned to that corner.
There is no piece that is both fixed-size and centred. A QML rectangle has
neither problem.

**Its colour comes from the colour scheme's highlight role**, not from a
hard-coded `#8AB4FF`. In the AquariusOS scheme that role *is* starlight, so out of
the box it matches the design exactly — and someone who switches colour schemes
gets a dot that still belongs.

**Judgement call: the dot does not lift with the icon.** In the design's HTML it
does, but only because it is a CSS child of the tile and inherits the tile's
transform. A running mark that jumps around reads as noise, and the dock this
design is modelled on keeps it still. Easy to change: move it inside `iconBox`.

**It is drawn only on a bottom dock.** AquariusOS ships one dock and it is at the
bottom — the same assumption `tasks.svg` makes. A side dock needs a side-aware
anchor here *and* new artwork in the theme.

> ### Follow-up: the theme's underline is now redundant
>
> **This branch does not touch the theme** — another agent owns it. But once this
> dock ships, the theme is drawing a second running mark underneath ours.
>
> Before we had the dot, `tasks.svg` marked a running app with a 2px starlight
> underline as a stopgap. With the dot drawn here, that underline should go, or
> every running app gets both a line and a dot.
>
> The elements to delete are in
> `system_files/usr/share/plasma/desktoptheme/aquarius/widgets/tasks.svg` — the
> starlight `<rect>`s at `y="29"`, three per state, in **seven** states:
>
> | State | Group ids | Line numbers | Opacity |
> |---|---|---|---|
> | `normal` | `normal-bottomleft`, `normal-bottom`, `normal-bottomright` | 171, 176, 181 | 0.55 |
> | `hover` | `hover-bottomleft`, `hover-bottom`, `hover-bottomright` | 214, 219, 224 | 0.55 |
> | `focus` | `focus-bottomleft`, `focus-bottom`, `focus-bottomright` | 302, 307, 312 | 0.8 |
> | `focus-hover` | `focus-hover-bottomleft`, `focus-hover-bottom`, `focus-hover-bottomright` | 347, 352, 357 | 0.8 |
> | `minimized` | `minimized-bottomleft`, `minimized-bottom`, `minimized-bottomright` | 390, 395, 400 | 0.3 |
> | `attention` | `attention-bottomleft`, `attention-bottom`, `attention-bottomright` | 436, 441, 446 | 0.9 |
> | `progress` | `progress-bottomleft`, `progress-bottom`, `progress-bottomright` | 480, 485, 490 | 0.55 |
>
> Delete **only** those `<rect>` elements. Everything else in those groups —
> including the invisible `fill="none"` sizing rectangles — must stay, or the 4px
> inset silently collapses and the highlight goes back to painting over the dock's
> border. The `tasks.svg` header explains that trap.
>
> Line numbers are as of the version of `tasks.svg` in this branch. Confirm by the
> group ids, not by counting lines.
>
> Consider keeping `attention` (0.9): a flashing "this app wants you" underline is
> a different signal from "this app is running", and losing it costs something.
> That is a design call for Royce, not a mechanical deletion.

#### B3. The "add an app" tile

**Files:** `main.qml` — new `aqAddTile` element, plus two terms in
`Layout.preferredWidth` / `Layout.preferredHeight`

A dashed outline of a tile with a `+` in it, after the last app. Clicking it opens
the full-screen app grid.

The outline is painted with a `Canvas` because a plain QML rectangle cannot draw
a dashed border. Its corner radius and inset are derived from the tile size so it
lines up with the app tiles at any dock height.

The two `Layout.preferred*` terms add one tile's width to what the widget asks
for. The dock panel is set to "fit" length — it is exactly as wide as this widget
requests — so without them the panel would end at the last app and the `+` tile
would hang off the end, outside the dock's background.

##### How the click works, and what we rejected

**What we do:** call `activateLauncherMenu` on plasmashell over D-Bus.

```
service  org.kde.plasmashell
path     /PlasmaShell
iface    org.kde.PlasmaShell
member   activateLauncherMenu
```

This is Plasma's own published way of saying "open the app launcher". The shell
walks its panels, finds the widget that advertises `X-Plasma-Provides:
org.kde.plasma.launchermenu`, and activates it. (Verified in plasma-workspace
`Plasma/6.7`: `shell/dbus/org.kde.PlasmaShell.xml` declares it, and
`ShellCorona::activateLauncherMenu` in `shell/shellcorona.cpp` implements exactly
that search.)

On AquariusOS the widget it finds is the AquariusOS mark in the top bar, which the
layout script sets to **Application Dashboard** (`org.kde.plasma.kickerdash`) —
the full-screen grid with a live search box, which is what the design draws. Its
metadata declares the `launchermenu` capability, so the match is guaranteed.

Two things make this the right mechanism rather than merely a working one:

- It opens **the same** launcher the logo opens, not a second copy of it.
- If Royce ever swaps the top-bar launcher for a different one, this tile follows
  it automatically, because the shell resolves "the launcher" at click time
  rather than us naming one here.

**Rejected, with reasons:**

| Option | Why not |
|---|---|
| `plasma-open-applet` | **Does not exist.** No such binary in plasma-workspace `Plasma/6.7`. |
| `plasmawindowed org.kde.plasma.kickerdash` | Real binary, wrong result. It launches a *second*, separate copy of the dashboard in an ordinary window — with a title bar, in the task list, not full-screen, and not sharing state with the top bar's. |
| KRunner | A search box, not an app grid. Different surface, and AquariusOS already has its own plan for search (Flow Search). |
| systemsettings' widget page | That is the "add a *widget* to the panel" chooser. The tile says "add an app". |
| `kmenuedit` | The menu *editor*. Edits which apps exist in menus; does not launch anything. |
| KGlobalAccel `invokeShortcut` | The shortcut's name embeds the launcher widget's instance number, which differs per install and changes if the layout is rebuilt. Fragile in exactly the way that is hard to notice. |
| Launching a `.desktop` file | There isn't one. The dashboard is a panel widget, not an application. |

---

## Re-syncing with a newer KDE

Short version: fetch the same folder at the new tag, diff it against the upstream
commit recorded at the top of this file, and re-apply the tables above. The long
version — including how to tell whether a re-sync is even needed — is in
`docs/aquarius-dock.md`.

Two things to check every time, because they fail silently:

1. **`build_files/dock-check.sh` must still pass.** It reads the import list
   straight out of this folder and confirms every module is installed in the
   image. It is what catches a Plasma release that renamed something out from
   under us.
2. **Nothing may import `plasma.applet.*`** — the check fails the build on this
   for the reason in A3. It is the most likely thing to get pasted back in.
