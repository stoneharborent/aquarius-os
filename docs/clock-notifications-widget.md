# The clock and notifications widget

*Written 2026-08-31. Tier 2, track T2-E. The research this implements is
`docs/v2-shell-tier2-research.md`, "Layer 3". The design it implements is
`branding/design-system/AquariusOS Desktop Shell.html` (the block with
`id="ovNotif"`), published on its own as
`branding/design-system/AquariusOS Shell Notifications.html`.*

## What this is, in one paragraph

The thing at the right-hand end of the top bar — the one that reads
**Sat Aug 30 21:47** and drops a notifications panel out of itself when you click
it — is a small program AquariusOS writes. Until now it was KDE's own clock with
four settings written onto it, and that arrangement had a ceiling: KDE's clock
paints the date and the time in the *same* colour, and it opens a *calendar*. The
design wants a dimmer date and a notifications panel. Neither is a setting
anywhere, in any version of KDE. So the widget is ours now.

It lives at `system_files/usr/share/plasma/plasmoids/com.aquariusos.clock/` and
is installed into the OS at `/usr/share/plasma/plasmoids/com.aquariusos.clock/`.

## Why writing our own was the right call, and what it cost

The Tier 2 research put it plainly (`docs/v2-shell-tier2-research.md`, "Honest
gaps", item 3):

> Clock date can't be dimmer than the time (single foreground role) until the top-bar area gets custom widgets.

This is that widget. Along the way it also closes gap 5 for this surface — the
panel's secondary text now comes from the colour scheme rather than from KDE's
generic opacity conventions.

The cost is that QML widgets, unlike the Plasma Style, are *code*. They can break.
The research is reassuring about how much:

> Stability story is much better than KWin effects: public plasmoid QML is stable across 6.x minors, no per-release rebuilds. The break points are the `org.kde.plasma.private.*` imports.

We import no private plugin. That was the design constraint, and it is why this
widget is not a fork of KDE's notifications applet — that applet leans on a
private C++ plugin (`plasma.applet.org.kde.plasma.notifications`) for its
Globals singleton, its drag helper and its job aggregator. We build directly on
`org.kde.notificationmanager`, which is a properly installed, public QML module.

## Which file does what

Everything lives under
`system_files/usr/share/plasma/plasmoids/com.aquariusos.clock/`.

| File | What it does |
|---|---|
| `metadata.json` | Makes the folder a widget. Its `Id` is what the desktop layout script asks for by name. |
| `contents/ui/main.qml` | The wiring. Owns the clock, owns the data, decides which popup to show. |
| `contents/ui/CompactClock.qml` | What you see in the bar: the dim date, the bright time, the hover wash. |
| `contents/ui/NotificationsSource.qml` | **The only file that talks to KDE's notification library.** The model, the settings, and the handful of verbs (clear all, close one, Focus on/off). |
| `contents/ui/NotificationsPanel.qml` | The popup's looks. Pure drawing; asks the source above for everything. |
| `contents/ui/NotificationRow.qml` | One notification: icon chip, title, body, age. |
| `contents/ui/PanelUnavailable.qml` | A polite message, shown instead of the panel if the notification library is missing. |
| `contents/ui/AlignedClock.qml` | The good clock tick — rides KDE's shared, minute-aligned timer. |
| `contents/ui/TickingClock.qml` | A backup timer, used only if the above cannot load. |

Two files outside the widget belong to it:

| File | What it does |
|---|---|
| `build_files/shell-widgets.sh` | Runs inside the finished image: are all the widget's files here, is it actually placed on the top bar, are the KDE libraries it imports installed. |
| `tests/test-aquarius-plasmoid.sh` | Runs in ten seconds on every pull request: metadata parses, files exist, brackets balance, no machine-specific paths, layout script still valid JavaScript. |

## Every KDE thing we use, and where we checked it

Nothing below was taken on trust. Each row was read in the Plasma **6.7** source
at `invent.kde.org/plasma/`. The private-plugin row is the one to re-check on
every Bazzite Plasma rebase — that is the class of thing that breaks.

| What we use | How it is written | Where it was verified |
|---|---|---|
| The notification library's import name | `import org.kde.notificationmanager as NotificationManager` | `plasma-workspace/libnotificationmanager/CMakeLists.txt` — `ecm_add_qml_module(notificationmanager URI org.kde.notificationmanager GENERATE_PLUGIN_SOURCE)` |
| The history model | `NotificationManager.Notifications { … }` | `libnotificationmanager/notifications.h` (`QML_ELEMENT`) |
| Model settings we set | `showExpired`, `showDismissed`, `showJobs`, `sortMode`, `groupMode`, `blacklistedDesktopEntries`, `blacklistedNotifyRcNames`, `ignoreBlacklistDuringInhibition`, `urgencies` | `notifications.h` `Q_PROPERTY` list; usage cross-checked against `applets/notifications/main.qml` |
| Model counts we read | `count`, `unreadNotificationsCount`, `expiredNotificationsCount` | `notifications.h` `Q_PROPERTY` list |
| Enum values | `SortByDate`, `GroupDisabled`, `ClearExpired`, `LowUrgency`/`NormalUrgency`/`CriticalUrgency`, `InvokeBehavior.Close`, `ReadRole`, `HasDefaultActionRole` | `notifications.h`, the `enum SortMode / GroupMode / ClearFlag / Urgency / InvokeBehavior / Roles` blocks |
| Row properties in the list (`summary`, `body`, `created`, `updated`, `applicationName`, `iconName`, `applicationIconName`, `closable`) | plain delegate properties | `libnotificationmanager/utils.cpp`, `Utils::roleNames()` — KDE builds these names from the `Roles` enum by lower-casing the first letter and dropping the `Role` suffix, so `SummaryRole` becomes `summary` |
| "Clear all" | `model.clear(NotificationManager.Notifications.ClearExpired)` | `applets/notifications/main.qml`, the `clearHistory` action |
| Closing one row | `model.close(model.index(row, 0))` | `notifications.h` — `Q_INVOKABLE void close(const QModelIndex &idx)` |
| Clicking a row | `model.invokeDefaultAction(idx, …Close)` | `notifications.h` — `Q_INVOKABLE void invokeDefaultAction(const QModelIndex &idx, InvokeBehavior behavior = None)` |
| Marking everything read | `model.setData(idx, true, …ReadRole)` | `applets/notifications/FullRepresentation.qml`, the `onExpandedChanged` Connections block |
| "Older than this is not new" | `model.lastRead = undefined` | `applets/notifications/main.qml`, `onExpandedChanged` |
| Notification settings | `NotificationManager.Settings { }` | `libnotificationmanager/settings.h`; instantiated the same way in `applets/notifications/main.qml` |
| **Focus / Do Not Disturb** | `settings.notificationsInhibitedUntil = <date>; settings.save()` | `settings.h` — `Q_PROPERTY(QDateTime notificationsInhibitedUntil READ notificationsInhibitedUntil WRITE setNotificationsInhibitedUntil RESET resetNotificationsInhibitedUntil NOTIFY settingsChanged)`. Written exactly this way in `FullRepresentation.qml` (the DND switch and its menu). **This confirms the property name the research flagged as needing confirmation.** |
| Turning Focus off | `notificationsInhibitedUntil = undefined; revokeApplicationInhibitions(); save()` | `applets/notifications/global/Globals.qml`, `revokeInhibitions()`. Assigning `undefined` fires the property's `RESET`. |
| Is Focus on right now | future `notificationsInhibitedUntil`, or `notificationsInhibitedByApplication` | `Globals.qml`, `checkInhibition()` |
| 06:00 as "morning" | our `morningHour: 6` | `FullRepresentation.qml` — `readonly property int dndMorningHour: 6` |
| Is the service running | `NotificationManager.Server.valid` | `applets/notifications/main.qml` |
| Settings changed by another program reach us | (no code — it just works) | `libnotificationmanager/settings.cpp` uses `KConfigWatcher`, so System Settings and KDE's own tray applet stay in step with our button |
| The clock tick | `import org.kde.plasma.clock` → `Clock { }` → `dateTime` | `plasma-workspace/libclock/CMakeLists.txt` (`URI "org.kde.plasma.clock"`), `libclock/clock.h`, `libclock/alignedtimer.h` |
| The dim text colour | `Kirigami.Theme.disabledTextColor` | `qqc2-desktop-style/kirigami-plasmadesktop-integration/plasmadesktoptheme.cpp` — `setDisabledTextColor(colors.scheme.foreground(KColorScheme::InactiveText).color())` |
| Where the widget folder goes | `/usr/share/plasma/plasmoids/<id>/contents/ui/main.qml` | `libplasma/src/plasma/packagestructure/packages.cpp` — `addFileDefinition("mainscript", "ui/main.qml")` |
| The translation domain | `plasma_applet_com.aquariusos.clock` | `libplasma/src/plasma/applet.cpp`, `Applet::translationDomain()` — `"plasma_applet_" + pluginId` |
| **What we deliberately do NOT import** | `plasma.applet.org.kde.plasma.notifications` | KDE's own applet's private C++ plugin. This is the fragile thing the research told us to avoid, and we do. |

## How the clock keeps time

The lazy way to build a clock is to wake up every second and look. On a laptop or
a handheld that is wasteful: every wake-up costs battery and 59 out of 60 of them
change nothing, because we do not show seconds.

KDE solved this properly and we use their solution. `Clock`, from
plasma-workspace's `libclock`, rides **one** timer shared by every clock on the
desktop, built on a kernel timer rather than a polling loop, and aligned to tick
*exactly* on the minute. Our widget therefore adds no wake-ups at all — it is a
passenger on the same tick KDE's own clock uses. `libclock/clock.h` says so in
its own words:

> Clock represents a time on a given timezone. Underneath Clock operates on a shared timer that is aligned to update exactly on the second or minute (as appropriate) tracking skews and offsets.

`TickingClock.qml` is the backup for a Plasma that does not have that library
(it arrived in Plasma 6.6). It is still not a once-a-second poll: it works out
how many milliseconds remain until the top of the next minute, sleeps exactly
that long, redraws, and works it out again. What it loses is following a system
clock change — a time-zone switch, a resume from sleep — until its next tick. Up
to a minute stale, then right again.

## What happens if KDE takes something away

Two of the widget's files open with an import of a KDE library. In QML, an import
that cannot be resolved kills the whole file it is written in. So each risky
import is quarantined in its own small file, pulled in through a `Loader`:

- `org.kde.notificationmanager` gone → `NotificationsSource.qml` fails to load →
  the clock keeps working and the popup shows *"Notifications are unavailable —
  this version of the desktop does not provide the notification service this
  panel is built on. The clock is unaffected."*
- `org.kde.plasma.clock` gone → `AlignedClock.qml` fails to load →
  `TickingClock.qml` takes over and nothing visible changes.

Neither should ever happen, because `build_files/shell-widgets.sh` checks for
both inside the finished image, and **fails the build** if the notification one is
missing. That is the mechanism the research asked for:

> add a CI grep-level presence check for the private plugin dirs so a rebase that drops one fails loudly.

A build that fails is a good outcome here: the previous image keeps working, the
rollback is clean, and we find out before anybody installs anything.

## The decisions worth arguing about

### 1. There is no calendar. *(flag for Royce)*

KDE's clock opens a calendar. This one opens notifications, because that is what
the design draws and because a calendar would push the panel to roughly twice the
width, which the design does not have room for.

**If you miss it:** right-click the top bar → Add Widgets → Digital Clock, and
drop KDE's clock in beside ours. Both can live there. If it turns out you use the
calendar constantly, the honest next move is not to cram it into this panel but
to give the panel a second tab — which is a real piece of design work, not a
tweak.

### 2. "Clear all" clears the history, not everything on screen

The library offers exactly one clearing option. Its own source says so:

```
enum ClearFlag {
    ClearExpired = 1 << 1,
    // TODO more
};
```

So "Clear all" empties the history, and a notification that is still live is
dismissed from its own row. KDE's applet has precisely the same limitation. Like
KDE, we only show the "Clear all" text when there is something it could actually
clear — a button that does nothing is worse than no button.

### 3. There is a close button on each row, and the design draws none

Following from the point above: without a per-row control there would be no way
at all to dismiss a live notification. The close button is hidden until the
pointer is over the row, so the panel *at rest* looks exactly like the mock.

### 4. The list is flat — no grouping by application

KDE groups notifications by app because its history can run to dozens of items
and needs folding. Our panel is the design's short, flat, newest-first list, and
grouping would introduce header rows the design has no drawing for. If real use
turns out to be noisy, switching `groupMode` to `GroupApplicationsFlat` is a
one-line change plus a header row.

### 5. Progress jobs (file copies, downloads) are hidden

A job row without a progress bar would be worse than no job row, and the progress
bar is exactly the part of KDE's applet that needs the private plugin. Left for
later, deliberately.

### 6. Attached pictures are not drawn yet

A screenshot notification carries a thumbnail on the model's `image` role. We
draw the notification's icon instead. Doing images properly means handling three
different shapes of icon data, which is a chunk of work KDE has a whole component
for. On the list, not in this pass.

### 7. 12-hour vs 24-hour still follows the user's country

Unchanged from the old layout-script decision, and deliberately so. The design
mock shows 21:47; a German install shows 21:47 and an American one shows 9:47 PM,
and both are right for the person sitting there. The widget reads the locale's
own short time format and trims the seconds off it — the same trimming KDE's
clock does, and for the same reason.

### 8. "Until morning" can mean *this* morning

KDE's own menu only offers "until tomorrow morning", so between midnight and
06:00 it silences you for thirty hours. We take whichever 06:00 comes next, which
between midnight and 06:00 is the one a few hours away. "Until morning" ought to
mean the morning that is about to happen.

### 9. The dim date uses `text-2`, where the design used `text-3`

A colour scheme has one bright foreground and one quiet one. There is no third.
`Kirigami.Theme.disabledTextColor` is the quiet one, and in our own scheme it is
`180,186,205` — which *is* the design's `text-2` (`#B4BACD`) exactly. The design
tints the top-bar date one step quieter still. Using a scheme role means the
widget also looks right under somebody else's colour scheme, which a hard-coded
`#848CA6` would not. That trade is worth making; hard-coding is not.

### 10. It is GPL

The widget contains no KDE code. It was written, however, while reading KDE's
GPL-licensed notifications applet as documentation, so it ships under
`GPL-2.0-or-later` rather than claiming a permissive licence. The library it
builds on (`libnotificationmanager`) is LGPL, which places no requirement on us
either way — this is our own choice, made because it is the plainly honest one.

## Nothing here is see-through

Worth stating, because the row tints look like glass in a screenshot and are not.
The popup's surface is drawn by the Aquarius Plasma Style
(`desktoptheme/aquarius/dialogs/background.svg`) and is **solid** — the glass came
out on 2026-08-30, recorded in `docs/plasma-style.md` under "Glass removed". The
widget paints no background of its own. Its row slabs, icon chips, hover washes
and the Focus pill are tints laid *on top of* an opaque surface. Do not add
translucency here; it would be the one see-through surface left on the desktop.

## Translations

Nothing is translated yet, but every user-visible string in the widget is wrapped
in `i18n()`, `i18nc()` or `i18np()`, so the work is extraction rather than
rewriting. Plasma resolves those calls in the domain
`plasma_applet_<plugin id>` automatically (`libplasma`, `Applet::translationDomain()`),
which for us is `plasma_applet_com.aquariusos.clock`. When translations become a
real job, the extraction command is the standard KDE one:

```
xgettext --from-code=UTF-8 -C -kde -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 \
    system_files/usr/share/plasma/plasmoids/com.aquariusos.clock/contents/ui/*.qml \
    -o plasma_applet_com.aquariusos.clock.pot
```

## What still needs a real machine

None of this has run. It cannot: the repo lives on an Apple Silicon Mac, there is
no Qt here, and even `qmllint` — the tool that would catch a typo before boot —
needs Qt, Kirigami and the Plasma QML modules installed to resolve the imports.
So the automated checks are deliberately modest (metadata parses, files exist,
brackets balance, the layout script is valid JavaScript) and everything below is
**bench work on x86 hardware**.

Remember that the desktop layout script only runs for a user who has **no saved
layout**, so all of this needs a **fresh user account or a fresh install** — a
log-out and back in will not do it.

**Does it appear at all**
- [ ] The clock is at the right-hand end of the top bar, and there is only one clock.
- [ ] It reads `Sat Aug 30 21:47` — date first, then time, one line.
- [ ] The date is visibly dimmer than the time.
- [ ] Nothing in `journalctl --user -u plasma-plasmashell` mentions our widget.

**Does it keep time**
- [ ] It flips over at the top of the minute, not a second late.
- [ ] Change the system time zone in System Settings — it follows without a restart.
- [ ] Suspend and resume — it shows the right time immediately.
- [ ] Set the machine to a 12-hour locale (`en_US`) → `9:47 PM`. Set it to a 24-hour one (`en_GB`, `de_DE`) → `21:47`.

**The popup**
- [ ] Clicking opens the panel; clicking again closes it.
- [ ] It is about 350px wide and the background is **solid**, not see-through.
- [ ] Send some test notifications (`notify-send "Screenshot saved" "Added to Pictures."`) — they appear, newest at the top.
- [ ] Icon chip, title, body and age all look like the design.
- [ ] The age creeps up on its own while the panel sits open (`now` → `1 m` → `2 m`).
- [ ] Hovering a row reveals the close button; clicking it removes that row.
- [ ] Clicking a row with a default action does the thing and closes the row.
- [ ] "Clear all" appears when there is history, empties it, and then disappears.
- [ ] With nothing in the list: *"You're all caught up."*
- [ ] A very long notification body wraps and stops at three lines rather than stretching the panel.
- [ ] Twenty notifications: the list scrolls instead of running off the screen.

**Focus**
- [ ] Tapping "Focus until morning" turns the pill accented.
- [ ] KDE's own tray notification icon switches to its do-not-disturb state at the same moment. **This is the important one** — it proves the setting we write is the setting the system reads.
- [ ] With Focus on, `notify-send` produces no popup on screen but the item is still in our panel afterwards.
- [ ] Tapping the pill again turns Focus off, and KDE's icon follows.
- [ ] Turn "Do not disturb" on in KDE's own tray applet — our pill lights up on its own, without reopening the panel.
- [ ] Set the machine's clock to 05:59, turn Focus on, wait — the pill switches itself off at 06:00.
- [ ] Turn Focus on between midnight and 06:00 and check it ends *this* morning, not tomorrow.

**The things that are only true on other people's machines**
- [ ] A light colour scheme: the row tints go dark-on-light, the dim text is still readable.
- [ ] A different accent colour: the icon chips and the Focus pill follow it.
- [ ] The interface font at 12pt: the panel gets wider rather than cramped.
- [ ] A HiDPI display at 1.5× scaling: nothing is blurry or clipped.
- [ ] The handheld (deck) image: it still fits on a small screen.

**Things worth watching for that we cannot predict**
- [ ] Whether the popup honours our 350px width. The research says standalone panel widgets do and system-tray-hosted ones do not; ours sits directly on the top bar, so it should. Measure it.
- [ ] Whether the padding doubles up. The widget draws its own 16px inset, and the Plasma popup window adds margins of its own from the theme's `dialogs/background.svg`. If the result looks too airy, the fix is to reduce ours, not to fight the theme.
- [ ] Whether marking everything read on open makes KDE's own unread badge clear too.
- [ ] Memory over a long session with a chatty application — the model is KDE's, but the list is ours.
