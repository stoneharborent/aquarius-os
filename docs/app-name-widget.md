# The app name in the top bar

*Written 2026-08-31. Tier 2 Wave 2, track T2-G. The research this implements is
`docs/v2-shell-tier2-research.md`, "Layer 3", the **Top bar app name** row.*

## What this is, in one paragraph

Look at the top-left of the AquariusOS desktop. There is the logo, then one
short word in **bold** — "Dolphin", "Firefox", "Steam" — and then the File /
Edit / View menus. That bold word is the name of the app you are using right
now, and it changes the instant you click into a different window. It is what
tells you whose menus those are, and it is the single detail that makes the bar
read as a Mac menu bar rather than a Windows taskbar. Click the desktop and it
disappears, and the bar closes up around the gap.

It is a widget of our own — about fifty lines of code under a lot of comments
— living at:

```
system_files/usr/share/plasma/plasmoids/com.aquariusos.appname/
├── metadata.json          its name, its id, its licence
├── contents/ui/main.qml   the widget
└── README.md              the short version of this file, kept beside the code
```

Nothing is compiled and no package is installed. Those files are copied into the
image and read by KDE at login, which is why this track carries almost none of
the maintenance risk that the KWin effects layer does.

## The design it comes from

`branding/design-system/AquariusOS Desktop Shell.html`, the top bar. The sample
app in the mock is "Files". The relevant line of the mock is:

```html
<span class="bar-item" style="font:600 12px var(--font-body)">Files</span>
<span class="bar-item menu">File</span><span class="bar-item menu">Edit</span>…
```

Reading that literally, and against `branding/tokens.md`:

| Design says | What we do | Why |
|---|---|---|
| weight `600` | `font.weight: Font.DemiBold` | DemiBold **is** 600 in Qt's spelling. This is the only visual thing the widget changes. |
| `12px`, same as the menus beside it | leave the size alone | Same size as the menus means "do not touch it". The panel's font size is the user's choice. |
| `var(--font-body)` = Inter | leave the family alone | The label inherits the desktop's interface font, which on a stock AquariusOS *is* Inter. Naming Inter here would override anyone who changes their font, or needs a bigger one to read it. |
| `--text-1` (`#FFFFFF`), the primary text colour | leave the colour alone | KDE labels already paint themselves in the theme's normal text colour, which is our `#FFFFFF`. Hardcoding it would be the one thing in the bar that ignored a light or high-contrast theme. |
| `padding: 0 8px` | `Kirigami.Units.largeSpacing` either side | That unit is 8 pixels, matching the token scale (4 · 8 · 12 · 16 · …), but it *scales* on a high-DPI screen where a literal 8 would go hair-thin. |
| vertically centred in a 30px bar | `anchors.centerIn: parent` | — |

The one thing the design shows that we do not draw is the hover highlight
(`.bar-item:hover` puts a faint panel behind the label). The app name in the
mock is not clickable, and ours is not either, so a hover state would be
promising a click that does nothing. Left out on purpose.

## The call: write our own, or adopt somebody's

The Tier 2 research leaned "adopt `antroids/application-title-bar`, or absorb it
as a tiny custom plasmoid later". Having read all three candidates properly, we
did the second thing. Here is the working, so it can be argued with.

### What was actually compared

| | **Our widget** | **antroids/application-title-bar** | **dhruv8sh/plasma6-window-title-applet** |
|---|---|---|---|
| Files to own | **3** (two of them code) | 59 (48 of them QML) | 19 |
| Licence | Apache-2.0, same as this repo | GPL-3.0-or-later | GPL-2.0 |
| Last release | — | v0.10.0, 2026-07-05 | v0.21; last commit July 2024 |
| Shows the app NAME? | yes, always | yes, but only on one of its four title modes | yes, via a `%a` format string |
| Window buttons, hover effects, title-rewriting rules | none | all of it | most of it |
| Settings screens | none | 4 | 3 |
| Uses any `private` KDE import? | no | no | **yes** — `org.kde.plasma.private.appmenu` |
| Data source | `org.kde.taskmanager`, `AppName` role | **the same** | **the same** |

### Why the "adopt for robustness" argument fell over

The reason to adopt somebody else's widget is that they have already solved the
hard parts and absorbed the breakages. That argument only works if there *are*
hard parts. There are not.

All three of these widgets — and a widget inside KDE itself — read the app name
in exactly the same way, through exactly the same published library, in about
three lines. There is no private API, no D-Bus dance, no compositor-specific
branch. Once that was verified (the table further down is the verification),
"adopt it because it is more robust" had nothing holding it up, and what was
left was: carry fifty QML files and a hand-re-copied pinned release, in order to
switch nearly all of them off through config defaults.

Two more things pushed the same way:

* **`antroids` has a real bug in the exact code we would have been relying on.**
  Its `ActiveTasksModel.qml` asks for roles called `GenericAppName` and
  `Decoration`. Neither exists in KDE's list of roles. They come back as
  nothing, and nothing gets read as role number 0 — which is the window title.
  That is very likely why its default "generic application name" mode shows a
  window title instead. A good widget, actively maintained, and still wrong in
  the fifty lines we cared about. Vendoring it would have meant inheriting that
  and probably not noticing.
* **`dhruv8sh` imports a private KDE module it never uses.** A dead import of a
  `private` module still stops the whole widget loading if KDE ever drops that
  module — which is exactly the failure mode the Tier 2 research flags as the
  thing to watch for in plasmoids.

### What we give up by not adopting

Stated plainly, so nobody discovers it later:

1. **"Show desktop" is not handled.** If you press the show-desktop shortcut,
   which minimises everything at once, a window can technically stay marked as
   focused. Our label would keep showing its name. `antroids` handles this by
   also asking KWin whether the desktop is being shown. If it turns out to
   matter on the bench, that is one extra small file, and their approach is the
   one to copy.
2. **No settings.** No way for a user to switch it to the window title, pick a
   font size, or add window buttons. That is the design's intent, not an
   oversight, but it is a real difference from the alternatives.
3. **We own the bugs.** Two files' worth.

## How it works, and what every claim was checked against

Everything below was read out of KDE's published source for `Plasma/6.7` — the
branch Bazzite builds against — not out of documentation, and not from memory.
KDE's own documentation site is stale on two of these points and says the
Plasma 5 thing; where they disagree, the source wins.

### The three lines that matter

KDE ships a widget called **Window List** that already asks this exact question.
This is its code, verbatim, from
`plasma-desktop/applets/window-list/main.qml` on the `Plasma/6.7` branch:

```qml
} else if (tasksModel.activeTask.valid) {
    return tasksModel.data(tasksModel.activeTask, TaskManager.AbstractTasksModel.AppName) ||
           tasksModel.data(tasksModel.activeTask, 0 /* display name, window title if app name not present */)
} else {
    return i18nc("@title:window title shown e.g. for desktop and expanded widgets", "Plasma Desktop")
}
```

Our `refreshAppName()` is that, with one extra rung in the fallback ladder. So
this widget is not a clever thing we invented; it is the boring supported way,
maintained by KDE, inside the desktop we ship.

### The verification table

| # | The claim | Verified against (all `Plasma/6.7` unless noted) | Result |
|---|---|---|---|
| 1 | The import line is unversioned: `import org.kde.taskmanager as TaskManager` | `plasma-desktop/applets/taskmanager/qml/main.qml`, line 20 — KDE's own Task Manager. Both community widgets use the same form. | ✅ The versioned `0.1` form would also resolve (the library declares `VERSION 0.1` in its CMake), but nothing inside Plasma 6 uses it. |
| 2 | `TasksModel` has an `activeTask` property, and it is a position in the list, not a number | `libtaskmanager/tasksmodel.h`, line 89: `Q_PROPERTY(QModelIndex activeTask READ activeTask NOTIFY activeTaskChanged)` | ✅ |
| 3 | When no window has focus, `activeTask` comes back invalid, and `.valid` is how you ask | `libtaskmanager/tasksmodel.h`, line 674, doc comment: *"…or a null QModelIndex if no active task is found."* Implementation in `tasksmodel.cpp` ends `return {};`. `.valid` is what `window-list/main.qml` line 357 tests. | ✅ |
| 4 | **`AppName` is the APP name; `display` is the WINDOW TITLE.** They are different, and we want the first | `libtaskmanager/abstracttasksmodel.h`: `AppName, /**< Application name. */`. Then in `waylandtasksmodel.cpp` line 898: `if (role == Qt::DisplayRole) { return window->title; } … else if (role == AppName) { return d->appData(window).name; }` — and the same pair in `xwindowtasksmodel.cpp` line 611. | ✅ This is the load-bearing fact of the whole track. |
| 5 | That name is the app's own name, from its launcher entry | `libtaskmanager/tasktools.cpp` line 76: `data.name = service->name();` — i.e. the `Name=` line of the app's `.desktop` file. | ✅ So "Dolphin", not "org.kde.dolphin" and not "Documents — Dolphin". |
| 6 | `AppName` is a public role usable from QML, not a private one | `abstracttasksmodel.h`, the comment above the enum: *"Expose the AbstractTasksModel::AdditionalRoles enum to Qt Quick for use with the TasksModel::data invocable."* Marked `QML_ELEMENT` and `Q_ENUM`. | ✅ Public, and explicitly intended for this. |
| 7 | You can call `data()` from QML at all | Qt itself declares it invocable: `qtbase/src/corelib/itemmodels/qabstractitemmodel.h` line 280, `Q_INVOKABLE virtual QVariant data(const QModelIndex &index, int role = …)`. | ✅ |
| 8 | Grouping must be switched off | `tasksmodel.cpp`, `activeTask()`: when grouping is on it descends into a group's children, so "the active row" stops being a simple thing. `GroupDisabled` is 0 in the enum in `tasksmodel.h` line 103. Both community widgets set it. | ✅ We set `groupMode: GroupDisabled`. |
| 9 | Listening to `activeTaskChanged` alone is not quite enough | `tasksmodel.cpp` lines 165 and 180 emit it when any window's "is active" flag flips — which covers ordinary focus changes. It does **not** fire when the *same* window's name arrives late, which happens at app start-up. `antroids` hooks `onDataChanged` and `onCountChanged` as well. | ✅ We hook all three. |
| 10 | A panel-only widget with no popup is `PlasmoidItem` + `preferredRepresentation: fullRepresentation` | `plasma-desktop/applets/taskmanager/qml/main.qml` line 45. ⚠️ KDE's own docs site still shows the Plasma 5 spelling (`Plasmoid.preferredRepresentation`) — it is wrong for Plasma 6. | ✅ Source over docs. |
| 11 | `X-Plasma-API-Minimum-Version` must be `"6.0"` | `plasma-workspace/applets/digital-clock/metadata.json` and `applets/appmenu/metadata.json` both say `"6.0"`; so does the third-party template in KDE's own widget guide. It is a floor, not a target — there is no `"6.7"`. | ✅ Without it, Plasma treats a widget as Plasma-5-only and never lists it. |
| 12 | A third-party widget's metadata needs `KPackageStructure: Plasma/Applet` and an `Id` matching its folder | `dhruv8sh/plasma6-window-title-applet/metadata.json` — a real shipped third-party widget — has exactly that shape. | ✅ Both are checked at build time and again in CI. |
| 13 | A KDE label already uses the theme's font and text colour, so we should set neither | `libplasma/src/declarativeimports/plasmacomponents3/Label.qml`: `//font data is the system one by default` / `color: Kirigami.Theme.textColor`. And `kirigami/src/platform/platformtheme.h` line 90: the colour set is inherited from the surrounding item by default. | ✅ Setting either would break the user's own choices. |
| 14 | The name must be drawn as text, never as markup | A KDE label defaults to guessing whether its text is HTML. The text here comes from a window, and a window can call itself anything. KDE's own clock sets `textFormat: Text.PlainText` for the same reason. | ✅ We set it too. |

### What could NOT be checked from a Mac

Honest list. Everything above that is not a source quotation belongs here.

- **Nothing in this track has been run.** There is no Plasma, no KWin and no
  Linux on the machine this was written on. Every claim above is read out of
  published KDE source for the branch we build against.
- **`qmllint` was not run, and could not be.** It ships with Qt's QML tooling,
  which is not installed on macOS here, and there is no Linux build machine in
  this project. What *was* run instead: the file's brackets, braces and
  parentheses were counted and balance-checked with comments and string
  literals stripped out, and `metadata.json` was parsed. That catches a typo; it
  does not catch a wrong property name. The bench checklist below is what
  catches those, and until somebody walks it, treat this widget as unproven.
- **`node --check` was run on the layout script** and passes — but that only
  proves the file is valid JavaScript, not that KDE accepts every line of it.
- **Whether the widget's own tooltip really goes away.** We set its two tooltip
  texts to empty, which is how a widget asks for no tooltip. If a small bubble
  still appears when you hover the app name, that is a one-line follow-up, not
  a design problem. Check 5 below.
- **Whether `Kirigami.Units.largeSpacing` is 8 pixels on the shipped image.**
  Kirigami's own source initialises it to 8, but a platform is allowed to
  recompute it from the font. If the padding looks wrong on the bench, that is
  where to look — not at the design.

## How to test this

Needs an x86 machine (a VM, a spare PC, or the handheld) with a **freshly
installed** image or a **brand-new user account**. The desktop layout script
only runs for an account that has never had a desktop before, so logging out and
back in on an existing account will not show the change. This is the same
caveat as every other layout-script change in this repo.

1. **It is there at all.** Log in. Top-left, between the logo and the File menu,
   there should be a bold app name. On a fresh desktop with nothing open there
   should be **nothing** there, and no gap — the menus should sit right next to
   the logo.
2. **It follows focus.** Open Files (Dolphin) — the bar should say **Dolphin**.
   Open Firefox on top of it — **Firefox**. Click back to the Dolphin window —
   back to **Dolphin**. It should change immediately, not after a beat.
3. **It is the app name, not the window title.** Inside Dolphin, navigate to a
   few different folders. The bar must keep saying **Dolphin** and must never
   grow into "Documents — Dolphin". This is the single most important check: it
   is what separates this widget from every window-title widget on the internet.
4. **It goes away.** Click an empty part of the desktop wallpaper. The name
   should disappear and the menus should shuffle left to close the gap. Click
   back into a window and it should come back.
5. **No tooltip, no popup.** Hover the name for a few seconds — no bubble should
   appear. Click it — nothing should happen, no menu, no popup.
6. **It looks right.** The name should be visibly bolder than File / Edit /
   View next to it, the same size as them, the same white, and sitting on the
   same line. Roughly 8px of clear space either side.
7. **It survives a restart.** `systemctl --user restart plasma-plasmashell`,
   then check 2 again.
8. **Awkward apps.** Open Steam, and something installed as a Flatpak. Both
   should show a sensible name. If one shows something like
   `com.valvesoftware.Steam` instead of `Steam`, that is the second rung of the
   fallback ladder doing its job — the app could not be matched to a launcher
   entry. Worth noting, not worth panicking about.
9. **A long name.** If any app produces a name long enough to be cut off with an
   ellipsis, note which — the ceiling is deliberately generous and should never
   fire in practice.
10. **The bar still works.** The File / Edit / View menus, the tray and the
    clock should all behave exactly as before. This widget sits between the
    logo and the menus and should have moved nothing else.
11. **Both images build.** `aquarius-os` and `aquarius-os-nvidia` green in
    GitHub Actions, with the "Verify the top-bar app name widget" step passing.

### If it does not appear at all

In that order:

1. `ls /usr/share/plasma/plasmoids/com.aquariusos.appname/` — is it installed?
   (CI checks this, so it should be.)
2. Right-click the top bar → Add Widgets, and search for "Active Application
   Name". If it is not listed, KDE has rejected the widget's `metadata.json`.
3. If it *is* listed but the bar is empty, the widget loaded and then failed
   while running. `journalctl --user -b -u plasma-plasmashell | grep -i qml`
   will have the QML error, with a line number in `main.qml`.
4. Remember the fresh-account rule at the top of this section. An existing
   account will never pick up a layout change.

## What this track did *not* touch

- **The window buttons.** The genuine macOS bar also carries close / minimise /
  maximise on the left. KDE ships no widget for those and the good community one
  is C++, which would mean adding a compiler stage to this repo's build. Still
  a real piece of work, still not done — the note at the bottom of the layout
  script is the record of that.
- **The Plasma Style.** No artwork changed. The label picks up its colour from
  the theme already in the image.
- **The `appmenu` widget.** Untouched. It still handles File / Edit / View, and
  it still shows nothing for apps that do not export their menus.
