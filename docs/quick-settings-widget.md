# The Quick Settings widget — one drawer for the switches you actually use

*Written 2026-08-31. Tier 2, track T2-D. The research this implements is
`docs/v2-shell-tier2-research.md`, "Layer 3". The design is
`branding/design-system/AquariusOS Shell Quick Settings.html`.*

## What it is, in one paragraph

Click the sliders icon at the right-hand end of the top bar and a small panel
drops down: Wi-Fi, Bluetooth, Focus and Game Mode as four square buttons, a
sound slider, a brightness slider, how much battery is left, and a link into the
full Settings app. It is the drawer macOS calls Control Centre and Windows calls
Quick Settings. **KDE does not ship one** — out of the box each of those things
lives in its own little popup hanging off its own tray icon, so turning
Bluetooth off and turning the volume down are two separate clicks in two
separate places. This widget is those controls in one place.

It does not take anything away. KDE's own network, Bluetooth and volume icons
are still in the system tray immediately to the right of it, and still work. If
somebody dislikes this widget they can right-click and remove it and lose no
function at all.

## Where the files are

Everything lives in one folder, which is the whole widget:

```
system_files/usr/share/plasma/plasmoids/com.aquariusos.quicksettings/
├── metadata.json              name, id, icon — Plasma reads this first
└── contents/ui/
    ├── main.qml               the root: the bar icon, and the panel
    ├── CompactRepresentation.qml   the icon in the top bar
    ├── FullRepresentation.qml      the panel that drops down
    │
    ├── AqTile.qml             what one toggle square looks like
    ├── AqSlider.qml           what one labelled slider looks like
    ├── AqTileSlot.qml         the safety net that loads a tile
    ├── AqPlatform.qml         "is this a handheld?", and launching things
    ├── AqRunner.qml           the one place that can run a command
    │
    ├── TileWifi.qml           ─┐
    ├── TileBluetooth.qml       │ one file per thing being controlled.
    ├── TileFocus.qml           │ each names the KDE source it was
    ├── TileGameMode.qml        │ written from, at the top.
    ├── TilePowerProfile.qml    │
    ├── SliderSound.qml         │
    ├── SliderBrightness.qml    │
    └── BatteryLine.qml        ─┘
```

Two files outside that folder complete it:

| File | What it does |
|---|---|
| `system_files/usr/share/plasma/look-and-feel/org.aquariusos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js` | Puts the widget in the top bar, just left of the system tray. One line plus its comment. |
| `build_files/quick-settings-check.sh` | Fails the OS build if anything the widget needs is missing from the image. Run from `build.sh`. |

## Why there are so many small files

This is the one design decision worth understanding before changing anything.

The widget is built on KDE's own plumbing — the Wi-Fi tile drives the same code
as the stock Wi-Fi applet, the sound slider the same code as the stock volume
applet, and so on. Those pieces are QML "modules", and several have the word
**`private`** in their name: `org.kde.plasma.private.volume`,
`org.kde.plasma.private.battery`, and two more.

`private` is KDE saying *this is our internal wiring; we may rename or delete it
in any release and we owe you no warning*. AquariusOS does not get a say in when
that happens, because Plasma arrives with Bazzite and a rebase can move it
overnight.

And QML fails hard here: **a file that imports a missing module does not partly
work, it does not load at all.** If every tile lived in one file, one deleted
module upstream would turn the whole panel into an empty rectangle.

So each risky import is quarantined in its own file, and those files are never
referenced directly — they are pulled in at runtime by a `Loader`, which reports
failure instead of propagating it. When a module disappears, exactly one tile
goes quiet and everything else keeps working. `AqTileSlot.qml` puts a dimmed
placeholder in the gap so the 2×2 grid keeps its shape.

That is a safety net, not a fix. A quietly dead tile is still a broken feature —
it is just not a broken desktop. Catching it properly is the build check's job,
below.

## What the widget depends on, and where each came from

Every row was read out of KDE's own source on the `Plasma/6.7` branch, not from
memory or documentation. Each tile file repeats its own row at the top, with the
exact lines quoted.

| Tile / row | QML module | Risk | Read from |
|---|---|---|---|
| Wi-Fi | `org.kde.plasma.networkmanagement` | Medium — a Plasma module, no formal promise, but the stock Wi-Fi applet is built on it | plasma-nm `applet/main.qml` |
| Bluetooth | `org.kde.bluezqt` | **Low** — this is KDE *Frameworks*, which carries real compatibility promises | bluedevil `src/applet/qml/main.qml` |
| Focus | `org.kde.notificationmanager` | Medium — Plasma module, not private | plasma-workspace `applets/notifications/` |
| Game Mode | `org.kde.plasma.plasma5support` | **High** — a Plasma 5 → 6 migration aid; see the note below | plasma5support `src/dataengines/executable/` |
| Performance | `org.kde.plasma.private.batterymonitor` | **High** — `private` | powerdevil `applets/batterymonitor/` |
| Sound | `org.kde.plasma.private.volume` | **High** — `private` | plasma-pa `applet/main.qml` |
| Brightness | `org.kde.plasma.private.brightnesscontrolplugin` | **High** — `private` | powerdevil `applets/brightness/` |
| Battery line | `org.kde.plasma.private.battery` | **High** — `private` | plasma-workspace `components/batterycontrol/` |
| Battery line | `org.kde.coreaddons` | Low — Frameworks | powerdevil `applets/batterymonitor/main.qml` |
| Everything | `org.kde.kirigami`, `org.kde.plasma.plasmoid` | Low — Plasma itself would not start without these | — |

**A note on `plasma5support`.** It is how a QML widget runs a command, and it is
what the "All settings" link and the Game Mode tile use. KDE formally lists it as
not deprecated, but its own README calls it a migration aid, a comment in its
source says *"This class will hopefully be removed in KF6"*, and by Plasma 6.7
upstream KDE has stopped using its `executable` engine anywhere. It is safe for
the 6.x series and it is the only pure-QML option. If AquariusOS is still going
at Plasma 7, the replacement is a small piece of C++ compiled into the widget —
which would mean adding a compiler stage to this repo, and is not worth doing
before it is necessary.

### Two traps that cost real time, recorded so nobody pays twice

1. **Plasma 6.7 applet QML is flat.** It is `applets/notifications/main.qml`, not
   `applets/notifications/package/contents/ui/main.qml`. plasma-nm and plasma-pa
   went further still — `applet/main.qml`. Several paths in
   `docs/v2-shell-tier2-research.md` point at the Plasma 5 layout and 404.

2. **Brightness and battery are not in plasma-workspace.** Both applets live in
   the `powerdevil` repository. The battery *model* is in plasma-workspace but
   the battery *applet* is not, and they are two different QML modules.

### Where the research note was wrong

Written down because the note is otherwise good and will be trusted again:

| The note said | Actually |
|---|---|
| `org.kde.plasma.networkmanagement` **or** `org.kde.networkmanager` | Both are real and serve different purposes; the second is a Frameworks module the first depends on |
| `org.kde.plasma.private.bluetooth` for Bluetooth | Only needed for the pairing wizard. The public Frameworks module `org.kde.bluezqt` does everything a toggle needs, so the private one is deliberately not imported |
| `ScreenBrightnessControl.brightness` / `.brightnessMax` | Do not exist. 6.7 made brightness per-display; it is a `displays` model with `brightness` / `maxBrightness` roles and a `setBrightness(displayName, value)` method |
| `org.kde.plasma.private.powerprofiles`, type `PowerProfileMonitor` | Neither exists. It is `PowerProfilesControl`, in `org.kde.plasma.private.batterymonitor` |
| `Settings.notificationsInhibited` (a bool) | Does not exist — see below |
| `steamosctl switch-to-gamemode` | Wrong spelling (`switch-to-game-mode`), and Bazzite ships a wrapper that should be used instead |

## Three things that are not what they look like

**Do Not Disturb is a date, not a switch.** There is no `notificationsInhibited`
boolean anywhere in KDE. There is one property, `notificationsInhibitedUntil`,
and the rule is "Focus is on if that date is in the future". Switching Focus on
*indefinitely* therefore means writing a date far enough away that it may as well
be forever — KDE picks one year and says so in a comment in its own code, and
`TileFocus.qml` copies that convention exactly. Inventing a different one would
make our tile and KDE's own Do Not Disturb switch disagree about whether Focus is
on.

**Bluetooth needs two operations, not one.** `bluetoothBlocked` is the rfkill
soft block (aeroplane mode); `adapter.powered` is the per-adapter switch, and a
machine can have more than one adapter. Unblocking without powering leaves
Bluetooth off; powering without unblocking silently fails. The stock applet does
both, and so does ours.

**Running the same command twice is a silent no-op.** Plasma's command runner is
a subscription, not a function call, and connecting to a command that is already
connected returns early without doing anything. Both places that run commands
disconnect as soon as the result arrives, which is what lets the same command run
a second time. Without that line, "All settings" would work exactly once per
login.

## The fourth tile adapts, and here is why

The design's grid is Wi-Fi, Bluetooth, Focus and **Game Mode**. Three of those
are on every computer; the fourth is not. Game Mode is the Steam big-picture
session a handheld boots into, and it does not exist on a desktop or a laptop.

So the fourth square is:

| Machine | Tile | What pressing it does |
|---|---|---|
| `aquarius-os-deck` (handheld) | **Game Mode** | Runs `/usr/bin/return-to-gamemode` — Bazzite's own wrapper, which runs `steamosctl switch-to-game-mode` |
| `aquarius-os`, `aquarius-os-nvidia` | **Performance** | Switches the power profile between `performance` and the user's configured default |

Performance was chosen as the stand-in because it is the nearest thing a desktop
has to the same *idea*: one switch that says "stop being careful, go fast". A
gamer presses Game Mode to play; a creator presses Performance before a render.
The tile keeps its meaning even though the mechanism differs. (Night Light was
considered — it is a comfort setting, not a the-machine-is-about-to-work-hard
one. Airplane mode was considered — it duplicates the two tiles either side of
it, which a four-tile grid cannot afford.)

**The choice is made when the panel opens, not when the image is built.** That
matters: the Containerfile's standing rule is that all three images come from one
recipe with no per-variant branching, and the handheld build needed no branch at
all when it was added. Deciding this in the build would break that rule for one
square in one widget. Instead the widget ships identically everywhere and asks,
at runtime, whether `image-name` in `/usr/share/ublue-os/image-info.json`
contains "deck" — which is the same test Bazzite itself uses to decide whether a
machine is a handheld.

## How the build stops this rotting

`build_files/quick-settings-check.sh` runs inside every image build. If anything
the widget needs is missing, the build goes red and nothing is published.

It does **not** contain a list of what to check. A hardcoded list would be
correct the day it was written and wrong the first time somebody added a tile and
forgot to update it — and a check that quietly stops covering things is worse
than no check, because it still reports success. So the script reads the widget's
own QML, pulls the `import org.kde.…` lines out of it, and checks whatever it
finds. Add a tile and it is covered automatically.

It also checks three things the imports cannot tell it:

- that the widget is installed and its id matches its folder name (when those
  disagree, Plasma indexes it under one name while the layout script asks for the
  other, and the bar comes up without it, silently);
- that the layout script actually adds it;
- that the `executable` data engine is present. This one matters: the QML module
  can be perfectly installed, the import succeeds, and clicking "All settings"
  still does nothing, because the engine is a separate plug-in loaded by name.
  No import scan could catch that.

Finally it refuses to pass if it found fewer than six modules — because if the
grep ever stops matching, every check would be skipped and the script would
cheerfully report success while testing nothing.

**Known limit:** the check verifies the modules we import, not the modules
*those* modules depend on. `org.kde.plasma.networkmanagement` declares a
dependency on `org.kde.networkmanager`; if that went missing on its own, the
build would pass and the Wi-Fi tile would go quiet. The two ship together, so
this is a small risk, and closing it would mean hardcoding a list — the exact
thing the script avoids.

## Colours: why there is almost no hex in the QML

The design names exact colours — the lit tile is `rgba(138,180,255,.16)`, which is
the `starlight` token at 16%. The QML does not write those numbers. It asks the
colour scheme for its highlight colour instead.

On a stock AquariusOS machine that *is* `138,180,255`, because our own scheme sets
it: see the `[Colors:Selection]` block in
`system_files/usr/share/color-schemes/AquariusDark.colors`, where
`BackgroundNormal` is starlight and `ForegroundNormal` is the near-black
`on-accent`. So the panel matches the design exactly out of the box. The
difference is what happens when somebody changes their accent colour in System
Settings, which KDE users very much do — with hardcoded hex the panel would be
the one blue thing left on a green desktop.

The mapping used:

| Design token | Scheme role asked for |
|---|---|
| `starlight` (accent, lit tile, slider fill) | `Kirigami.Theme.highlightColor` |
| `on-accent` (icon on a lit chip) | `Kirigami.Theme.highlightedTextColor` |
| `text-1` | `Kirigami.Theme.textColor` |
| `success` / `warning` / `danger` (battery) | `positiveTextColor` / `neutralTextColor` / `negativeTextColor` |
| `border-1`, and the tile/track washes | the text colour at the design's own opacity |

Second-tier text (the subtitle under each tile) is the primary colour at 72%
opacity rather than a colour of its own. That follows both the design and KDE's
own convention: a colour scheme has exactly one foreground per group, so
dimmer text is an opacity trick everywhere in Plasma.

**The panel paints no background at all.** The design's CSS gives it
`rgba(13,15,24,.76)` and a blur; do not copy that. AquariusOS surfaces went solid
on 2026-08-30 (`docs/plasma-style.md`, "Glass removed"). The popup's surface,
its 16px corners, its hairline and its shadow all come from the Plasma style's
`dialogs/background.svg`. Painting a rectangle here would put a second surface on
top of that one and the two would not match.

## Translation

Every word a person can see is wrapped in `i18n()` — or `i18nc()` where a
translator needs to be told what the string is for, or `i18np()` where it has to
count ("1 device" / "3 devices"). There are no bare strings in the QML.

No translations are shipped, and none are needed yet: with no catalogue present
`i18n()` simply returns the English it was given, which is exactly what should
happen. The groundwork is done so that adding a language later is a matter of
supplying files, not of editing the widget.

The translation domain is `plasma_applet_com.aquariusos.quicksettings`. That is
not written anywhere — Plasma derives it from the `KPlugin.Id` in
`metadata.json`, so the id and the domain are the same fact and cannot drift
apart.

## Where we knowingly differ from the design

| Design | Shipped | Why |
|---|---|---|
| Top-bar button is a Wi-Fi arc + a battery glyph | A single sliders icon | In the design this cluster **is** the tray — there is nothing else showing Wi-Fi or battery. Our bar still has the stock system tray right beside this widget, already showing both. Drawing them again an inch away would show them twice. Revisit if the tray is ever removed. |
| Fourth tile is always "Game Mode" | Game Mode on handhelds, Performance elsewhere | Game Mode does not exist on a desktop. See above. |
| One brightness slider for "the screen" | One slider, driving the internal display (or the first one) | Plasma 6.7 made brightness per-display. The design has one row, so the widget picks the built-in panel — the one a laptop's brightness key affects. On a multi-monitor desktop this moves one monitor, not all of them. |
| Battery icon is green | Green above 25%, amber below, red below 10% | The design's single mock could only show one state. Green at full charge matches it. |
| Sliders show a fixed percentage | Live value, 5% steps by keyboard and scroll wheel | 5% is what KDE's own volume and brightness controls use. |

## What still needs a bench

Nothing here has been run. AquariusOS's own note applies: `qmllint` cannot be run
on Royce's Mac (it is part of the Qt tooling and the widget's imports only exist
on a Linux Plasma machine), so **the QML in this widget has never been parsed by
a QML engine.** It has been checked for balanced brackets and for correct API
names against upstream source, and that is all. Expect the first boot to find
typos.

In rough order of "most likely to be wrong":

1. **Does it appear at all?** Needs a *fresh user account* — the layout script
   runs once, for a new account, and never again. Logging out is not enough.
2. **Does the panel open at 330px**, or does the system tray's size rule apply
   anyway? This is the assumption the whole widget shape rests on.
3. **Padding.** The panel adds its own 16px inset. The Plasma style's popup
   drawing also carries content-inset markers. If the panel looks over-padded,
   that is the two of them adding up, and this widget's margin is the one to
   reduce.
4. **Every icon.** All names were verified to exist in breeze-icons, but "exists"
   and "looks right at 15px in a round chip" are different claims.
5. **Each tile in turn**, on a machine that has the hardware: does Wi-Fi toggle,
   does the SSID show, does Bluetooth need two clicks or one, does Focus agree
   with KDE's own Do Not Disturb switch (turn it on here, look there).
6. **`PlasmaNM.WirelessStatus`** — the SSID subtitle. It is in the public module
   but the stock Wi-Fi applet does not use it; only the hotspot settings page
   does. If one line in this widget is going to be wrong, it is this one.
7. **The brightness slider on a desktop** — should hide itself entirely, not show
   a dead slider.
8. **"All settings"** opens System Settings.
9. **On a handheld:** does the fourth tile become Game Mode at all (the
   `image-info.json` test), and does pressing it return to the Steam session.
   Nobody has yet booted `aquarius-os-deck`, so this whole column is untested.

### One open question for Royce

**Should Game Mode ask before it leaves?** Pressing that tile ends the desktop
session and anything with unsaved work goes with it. There is no confirmation,
which matches the design (an ordinary toggle) and Bazzite's own "Return to Gaming
Mode" launcher (one double-click, no prompt).

But a desktop icon takes a deliberate double-click, and this is a single click in
a panel somebody opened to change the volume. Those are not equally easy to hit
by accident. It was left matching the design rather than settled unilaterally —
it needs a decision, and the change is small either way.
