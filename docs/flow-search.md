# Flow Search — phase 1

*Built 2026-08-30 as Tier 2 track **T2-C**. Implements the Flow Search row of
`docs/v2-shell-tier2-research.md`. Everything here assumes zero Linux experience.*

## What Flow Search is, in one paragraph

One box that finds everything. Press **Alt+Space**, start typing, and the answer
appears — an app, a file, a settings page, the answer to a sum, or an action like
"shut down". The design mock's own caption says it best: *apps · files · settings
· math · actions — one box, no commands to learn.* Underneath it is KRunner, the
search box KDE has always had. Our job is not to rebuild it. Our job is to move
it to the middle of the screen, take away the handful of results that only make
sense if you already speak Linux, and let everything else through untouched.

**Phase 1 — this change — is pure configuration.** One new file, no code, no
custom window, nothing compiled. Every single setting is a **starting point** a
person can change in System Settings, and once they change it, it stays changed:
no OS update will ever put it back.

---

## What shipped

| # | What you get | Where it is set |
|---|---|---|
| 1 | Flow Search floats in the middle of the screen instead of dropping out of the top edge | `system_files/usr/share/aquarius/xdg/krunnerrc` — `[General] FreeFloating=true` |
| 2 | Three "you need to be a Linux person" result types no longer appear | the same file — `[Plugins]` |
| 3 | The Overview's search box gets both of the above for free | nothing extra; see "One file, two boxes" below |

And one thing deliberately **not** shipped: any change to keyboard shortcuts.
Explained under "How you open it".

That is the whole of phase 1. It is a small change on purpose — the visual half
(the glass, the rounded corners, the palette) arrives from a different track and
is not this file's business.

---

## 1. Why a file in that folder works

`krunnerrc` goes in `/usr/share/aquarius/xdg/`, alongside the `kdeglobals` that
carries our colours and fonts and the `kwinrc` that carries the hot corner. KDE
reads settings from a stack of folders, top to bottom, first match wins, and that
folder is a level we add above Bazzite's — so a user's own choices still sit above
ours and always win. The full explanation of that stack is at the top of
`system_files/usr/share/aquarius/xdg/kdeglobals`.

The thing worth verifying, because it bit us once already on this project, is
whether KRunner reads that stack at all. It does — and there are **two** readers,
which had to be checked separately:

- **The window itself** (`krunner/view.cpp`, Plasma/6.7, line 47) opens
  `KSharedConfig::openConfig()` with no arguments. No arguments means "my own rc
  file, fully cascading" — same mode as `kdeglobals` and `kwinrc`.
- **The plugin list** (KRunner framework, `src/runnermanager.cpp`) opens
  `krunnerrc` with the flag `KConfig::NoGlobals`.

That second flag is the trap. `NoGlobals` sounds like it might switch the cascade
off. It does the opposite — in KConfig's own enum, `NoGlobals` **is**
`CascadeConfig`:

```cpp
IncludeGlobals = 0x01,          // blend kdeglobals in
CascadeConfig  = 0x02,          // cascade to system-wide config files
SimpleConfig   = 0x00,          // just one file — no cascade at all
NoGlobals      = CascadeConfig, // cascade to system settings, omit user globals
```

So `NoGlobals` means "do cascade, just don't blend in kdeglobals". Our file is
read. The flag to be afraid of is `SimpleConfig` — that is the one the
keyboard-shortcut daemon uses, and it is exactly why the Super-key default had to
be shipped from `/etc/skel` instead (see
[`gnome-flow-behavior-layer.md`](gnome-flow-behavior-layer.md)). KRunner has no
such problem.

- `krunner/view.cpp` (Plasma/6.7): <https://invent.kde.org/plasma/plasma-workspace/-/blob/Plasma/6.7/krunner/view.cpp>
- `runnermanager.cpp`: <https://invent.kde.org/frameworks/krunner/-/blob/master/src/runnermanager.cpp>
- `kconfig.h` `OpenFlag` enum: <https://invent.kde.org/frameworks/kconfig/-/blob/master/src/core/kconfig.h>

### One file, two boxes

A bonus nobody planned. KWin's Overview — the thing that opens when you tap Super
or throw the mouse into the top-left corner — does not have a search engine of its
own. Its `Main.qml` imports `org.kde.milou` and drops in a `Milou.ResultsView`,
which is the same KRunner engine reading this same file. So the curated runner
list and the tidier results apply in *both* places, from one file, with no extra
work.

- <https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.7/src/plugins/overview/qml/Main.qml>

---

## 2. The shape — floating in the middle

```ini
[General]
FreeFloating=true
```

Out of the box KRunner is a wide bar that slides down from the top edge and
touches the bezel. `FreeFloating=true` makes it a self-contained card floating
over the desktop instead — the Spotlight / command-palette shape the design draws.
In KRunner's code the switch drops the slide-down animation, puts a border on all
four sides rather than three, and re-runs the positioning maths.

KRunner's own default is `false`, so this line is doing real work — it is not a
restatement of an existing default.

Anyone who prefers the bar can put it back: **System Settings → Search → KRunner →
Position on screen**.

---

## 3. The runner curation

KDE calls each source of search results a **runner**. Roughly twenty ship on a
Fedora/KDE image, and three of them break the design's promise. Those three are
switched off. Nothing else is touched — and, importantly, the file contains **no
`…Enabled=true` lines either**, because writing one would freeze a decision that
is currently KDE's to make and KDE's answer already matches ours.

**How the key is built:** `<pluginId>Enabled=false`. For a C++ runner the plugin
id is *derived from the plugin's filename*, which is the target name in its
`CMakeLists.txt` — not the folder name, and several of them differ (the folder
`characters` builds `krunner_charrunner`; the folder `calculator` builds plain
`calculator`). Every id in the table below was read from the
`kcoreaddons_add_plugin(<target> … INSTALL_NAMESPACE "kf6/krunner")` line in that
runner's own build file.

- `KPluginMetaData::pluginId()` — "For C++ plugins, this ID is derived from the
  filename. It should not be set in the metadata explicitly."
- `KPluginMetaData::isEnabled()` —
  `config.readEntry(pluginId() + QLatin1String("Enabled"), isEnabledByDefault())`
- <https://invent.kde.org/frameworks/kcoreaddons/-/blob/master/src/lib/plugin/kpluginmetadata.h>

### The table

Ships-with column: **PW** = plasma-workspace, **KPA** = kdeplasma-addons,
**PD** = powerdevil, **KWin** = kwin (over D-Bus).

| Runner (name you see) | Plugin id | Ships with | Kept / disabled | Why |
|---|---|---|---|---|
| Command Line | `krunner_shell` | PW `runners/shell` | **DISABLED** | Turns whatever you type into a shell command and offers to run it. It fires on ordinary words — type `make`, `top` or `mount` while hunting for an app and the top result invites you to execute a program you have never heard of, with no undo. The single biggest source of command-line jargon in the box. Console is in the dock for anyone who wants a shell. |
| Terminate Applications | `krunner_kill` | PW `runners/kill` | **DISABLED** | Matches running programs by name and force-quits them — and it matches the *same words* as the ordinary "open this app" result, so it sorts right next to it. Typing "kdenlive" to open Kdenlive should not put "kill Kdenlive" one arrow-key away; force quitting discards unsaved work with no confirmation. Still available deliberately in System Monitor. |
| Special Characters | `krunner_charrunner` | KPA `runners/characters` | **DISABLED** | You type a hexadecimal Unicode code point (`#20AC`) and get the character (€). Unusable unless you already know what a code point is and the hex number for your symbol — a lookup table you must memorise, which is the definition of "a command to learn". KDE's emoji and symbol picker (**Meta+.**) does the same job in plain language. |
| Sessions (Log Out / Shut Down / Restart / Lock / Switch User) | `krunner_sessions` | PW `runners/sessions` | **KEPT — and this one matters** | The name suggests it only switches users. Reading `sessionrunner.cpp`, this one runner produces *all* of Log Out, Shut Down, Restart, Lock Screen, Save Session and Switch User. That IS the design's "actions" pillar. The research brief listed it as a disable candidate; disabling it would have deleted an advertised feature. |
| Web Shortcuts | `krunner_webshortcuts` | PW `runners/webshortcuts` | **KEPT** | It does surface `keyword:` syntax, which is why it was flagged. But it is silent until you have already typed a keyword and a colon: it never volunteers itself and never appears while you type an app name. A beginner will never meet it; the person who types `wiki:aquarius` gets what they asked for. Nothing gained by removing it. |
| Help Runner | `helprunner` | PW `runners/helprunner` | **KEPT** | Answers `?` or `help` with a list of what the other runners do. It looks like "commands to learn" and is in fact the opposite — the escape hatch that *tells* you the syntax so nothing has to be memorised. Only appears when deliberately asked for. |
| Konsole Profiles | `krunner_konsoleprofiles` | KPA | **KEPT** | Sounds technical; isn't. Lists saved Konsole profiles as ordinary launch results, shows no syntax, does nothing destructive, and produces nothing at all until you have saved a profile. |
| Kate Sessions | `krunner_katesessions` | KPA | **KEPT** | Same reasoning as Konsole Profiles. |
| Windows | `windows` (D-Bus runner) | KWin `src/plugins/krunner-integration` | **KEPT** | Finds your open windows and switches to them. Plain, useful, non-destructive, and consistent with how the Overview already behaves. |
| Applications | `krunner_services` | PW `runners/services` | **KEPT** | The "apps" pillar. |
| File Search | `baloosearch` (D-Bus runner) | PW `runners/baloo` | **KEPT** | The "files" pillar. |
| Calculator | `calculator` | PW `runners/calculator` | **KEPT** | The "math" pillar. |
| Unit Converter | `unitconverter` | KPA `runners/converter` | **KEPT** | The unit-and-currency half of "math"; the mock shows it explicitly. |
| Power Management | `krunner_powerdevil` | PD `runners/powerdevil` | **KEPT** | Screen/sleep actions — this is what produces the mock's "Keep display on · System action" row. |
| Locations | `locations` | PW `runners/locations` | **KEPT** | Recognises a typed path or web address. |
| Places | `krunner_placesrunner` | PW `runners/places` | **KEPT** | Your bookmarked folders. |
| Recent Files | `krunner_recentdocuments` | PW `runners/recentdocuments` | **KEPT** | Part of the "files" pillar. |
| Bookmarks | `krunner_bookmarksrunner` | PW `runners/bookmarks` | **KEPT** | Browser bookmarks. |
| Software Center | `krunner_appstream` | PW `runners/appstream` | **KEPT** | "Install this app" results — genuinely friendly for a new machine. |
| Spell Check | `krunner_spellcheck` | KPA `runners/spellchecker` | **KEPT** | The design brief named spell/define as a keep. |
| Dictionary | `krunner_dictionary` | KPA `runners/dictionary` | **KEPT** | As above. |
| Colours | `krunner_colors` | KPA `runners/colors` | **KEPT** | Harmless; useful to a designer. |
| Date and Time | `org.kde.datetime` | KPA `runners/datetime` | **KEPT** | Note the unusual id — this one really is `org.kde.datetime`, not `krunner_datetime`. |
| System Settings pages | *(from the `systemsettings` package)* | — | **KEPT** | The "settings" pillar. Not disabled, so its exact id was not needed and is **not** verified here — see the open questions. |

**To turn any disabled runner back on:** System Settings → **Search → Plasma
Search**, tick the box next to its name. That writes `…Enabled=true` into the
user's own `~/.config/krunnerrc`, which outranks our file forever after. Nothing
here is removed from the system — the plugins are all still installed, just not
loaded by default.

---

## 4. How you open it

**We changed no shortcuts in this track, and could not have.** The daemon that
owns keyboard shortcuts reads exactly one file in the user's home folder and
ignores every system-wide folder, which is the whole reason our Super-key default
lives in `/etc/skel` (see
[`gnome-flow-behavior-layer.md`](gnome-flow-behavior-layer.md) §1). So this is a
statement of what the defaults already are, for the Phase-3 welcome app to teach
from — not a list of things we set.

| Key | What opens | Where the default comes from |
|---|---|---|
| **Alt+Space** | Flow Search | KRunner's own desktop file, `X-KDE-Shortcuts=Alt+Space,Alt+F2,Search` |
| **Alt+F2** | Flow Search | same line |
| **Search key** (the magnifying-glass key some keyboards have) | Flow Search | same line — the third entry is the `Search` media key |
| **Alt+Shift+F2** | Flow Search, pre-filled with whatever you copied | the `RunClipboard` action in the same desktop file (`krunner -c`) |
| **Super** (tap) | The Overview — whose search box is the same engine | our `/etc/skel/.config/kglobalshortcutsrc` |
| **Mouse into the top-left corner** | The same Overview | our `xdg/kwinrc`, `[Effect-overview] BorderActivate=7` |

Two corrections to earlier notes, worth writing down:

- **`Meta+Space` is not a KDE default and we do not add it.** The brief listed
  "Alt+Space / Meta+Space — verify"; verified, it is Alt+Space (plus Alt+F2 and
  the Search key). Meta+Space is a macOS habit, not a Plasma one.
- Our GNOME-flow layer gave the **Super** key to the Overview and took it away
  from the app launcher. That does not touch KRunner's own keys at all — Alt+Space
  still opens Flow Search exactly as it always did.

Source: `krunner/org.kde.krunner.desktop.cmake` (Plasma/6.7) —
<https://invent.kde.org/plasma/plasma-workspace/-/blob/Plasma/6.7/krunner/org.kde.krunner.desktop.cmake>

---

## 5. Honest gaps versus the design mock

The mock is `branding/design-system/AquariusOS Shell Search.html` (which frames
the `#search` overlay inside `AquariusOS Desktop Shell.html`). Phase 1 ships the
*behaviour* it describes, not its pixels. The differences, all of them:

| The mock draws | Phase 1 gives | Why, and when it closes |
|---|---|---|
| Palette top edge at **y = 170** on an 800px-tall screen | **One third of the way down** — 266px on that screen, so a bit lower | Hard-coded in KRunner: `margins()` returns `QMargins({0, r.height() / 3, 0, 0})` when floating (`view.cpp` lines 85–91). No config key, no KCM option, no environment variable. Closes in **phase 2**. |
| Palette **560px** wide | Whatever KRunner picks | Not a setting either. Closes in **phase 2**. |
| Sora/Inter type at the mock's exact sizes and the three-tier text greys (`#FFFFFF` / `#B4BACD` / `#848CA6`) | System fonts, and KDE's own single-foreground-plus-opacity convention | KColorScheme has one foreground colour per group; three tiers are a QML trick, not a themable value. Documented as gap 5 in `v2-shell-tier2-research.md`. Closes in **phase 2**. |
| Glass card: `rgba(13,15,24,.76)`, 16px corners, blur, big soft shadow | Whatever the current Plasma Style draws | Not this file's job at all. KRunner's chrome comes from the Plasma Style's `dialogs/background.svg`, which is **track T2-A** — one SVG covers KRunner along with every other popup. Closes when T2-A lands. |
| Dimmed, blurred desktop behind the palette | Not reproduced | The mock's full-screen scrim is a design device; KRunner has no scrim. Would need phase 2's own window. |
| The exact four result rows | Real results from the kept runners | The mock's rows map onto Applications, File Search, Unit Converter and Power Management — all kept, so the *kinds* of result are right. |

### What phase 2 adds

Pixel parity, by writing our own small QML window on top of KRunner's engine
rather than using KRunner's window. The engine for that is
`KRunner::RunnerManager`, and the research pass verified it as **public, stable,
LGPL framework API** — KRunner's own interface is just Milou QML sitting on top of
the same class, so we are not reaching into anything private. See the Flow Search
row of [`v2-shell-tier2-research.md`](v2-shell-tier2-research.md). Phase 2 is not
scheduled in Tier 2 Wave 1; it belongs with the Wave 2 custom-QML work.

Everything in phase 1 survives phase 2 unchanged — the runner curation is engine
configuration, so a custom window inherits it automatically.

---

## 6. What this track did *not* touch

Three Tier-2 tracks were built in parallel and the boundaries were kept clean:

| File | Owner |
|---|---|
| `system_files/usr/share/aquarius/xdg/krunnerrc` + this doc | **T2-C (this track)** — nothing else |
| `system_files/usr/share/aquarius/xdg/kwinrc` and the KWin effects | T2-B |
| The Plasma Style / look-and-feel package | T2-A |

No key collisions are possible: `krunnerrc` is a brand-new filename that appears
nowhere else in the repository, and KDE keys are scoped per file. The one
same-named group elsewhere — `[Plugins]` in
`system_files/usr/share/aquarius/xdg-handheld/kwinrc` — is in a *different file*
read by a *different program*, so it does not interact with ours.

No change was needed in `Containerfile` or `build_files/build.sh` either: the
whole `system_files/` tree is copied into the image wholesale (`COPY system_files
/system_files`), so a new file in `xdg/` ships automatically.

---

## 7. How to test this

You need an x86 machine running the actual image — everything below is a live
check, not a source read.

1. **Press Alt+Space.** A card should appear floating over the desktop, roughly a
   third of the way down, *not* a bar glued to the top edge. If it is still a top
   bar, `FreeFloating` did not take.
2. **Type `kd`** (or any app name). You should get the app, matching files, and
   nothing that looks like a command.
3. **Type `top`.** You should get results *about* things called top — you should
   **not** get an offer to run `top` as a command. That proves `krunner_shell` is
   off.
4. **Type the name of something you have open**, e.g. `dolphin`. You should get
   "switch to this window" and "open this app" — and **no** "kill" or "terminate"
   row. That proves `krunner_kill` is off.
5. **Type `#20AC`.** You should get nothing useful, rather than a € character.
   That proves `krunner_charrunner` is off.
6. **Type `24*60`.** You should get `1440`. Calculator is untouched.
7. **Type `shut down`.** You should get the Shut Down action. This is the check
   that the "actions" pillar survived the curation — if it is missing, something
   disabled `krunner_sessions` and that is a bug.
8. **Tap Super, then type.** The Overview's search box should behave identically —
   same results, same three absences. That is the "one file, two boxes" claim.
9. **Prove nothing is forced.** System Settings → Search → Plasma Search → tick
   **Command Line**. Close, press Alt+Space, type `top` — the command result
   should be back. Log out, log back in; it must still be back.
10. **Prove the position is not forced.** System Settings → Search → KRunner →
    Position on screen → Top. It should stick across a logout.
11. **Both images still build.** `aquarius-os` and `aquarius-os-nvidia` green in
    GitHub Actions.

Unlike the Super-key change, **this one does not need a fresh user account.**
`/usr/share/aquarius/xdg/` is read live at every login, so an existing account
gets it too — as long as that account has not already written its own
`~/.config/krunnerrc` for the same keys.

---

## 8. What could not be checked from a Mac

Honest list. Everything above that is not a source quote belongs here.

- **Nothing in this change has been run.** Every claim is read out of KDE's
  published source for the branch we build against (`Plasma/6.7`, and KRunner /
  KCoreAddons / KConfig `master` for the framework files, which have not changed
  these APIs in 6.x).
- **The exact runner set on the shipped image.** The list above is "what
  plasma-workspace, kdeplasma-addons, powerdevil and kwin build". Which of those
  packages Bazzite actually installs was not verified package-by-package —
  `kdeplasma-addons` we know is installed, because `build.sh` asks for it by name
  for the app-grid widget. On a test image, `ls /usr/lib64/qt6/plugins/kf6/krunner/`
  gives the real answer in one command, and System Settings → Search → Plasma
  Search lists them with their friendly names.
- **The three disabled ids, against a live install.** They were derived correctly
  (filename → plugin id, and the filename is the CMake target), but not observed.
  The failure mode is gentle: a key that names a plugin which does not exist is
  simply ignored, so a wrong id means "that runner is still on", never a broken
  session. Check by looking at System Settings → Search → Plasma Search — the
  three should be unticked.
- **The System Settings runner's plugin id.** It lives in the `systemsettings`
  repository rather than the four above, and since we are not disabling it the id
  was never needed. Left unverified on purpose.
- **Whether `Milou.ResultsView` inside the Overview honours the same
  `[Plugins]` group.** It uses the same `RunnerManager`, which has one config
  source, so it should — but "should" is doing work in that sentence. Test 8 is
  the check.
- **Whether the design's y=170 really reads as wrong at 1/3.** 266px vs 170px on
  a 800px screen is a 12% difference in a screen-height fraction. It may well look
  fine in the flesh; the mock was drawn, not measured. Worth a look before phase 2
  is scoped around it.
