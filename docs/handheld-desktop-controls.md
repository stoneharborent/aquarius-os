# Using the desktop on a handheld, with nothing plugged in

*Written 2026-08-30, for the ROG Xbox Ally. Zero Linux experience assumed.*

Your Ally normally lives in **Game Mode** — Steam's big controller interface. Press
"Switch to Desktop" and you get the full AquariusOS desktop, with Aquarius Editor,
DaVinci Resolve, a browser and everything else.

The catch: an Ally has **no mouse, no keyboard and no trackpad**. Two thumbsticks,
a touchscreen and a gyro is the whole list. This page is what AquariusOS now does
about that, and exactly which button does what.

---

## The short version

**Your controller is the mouse.** Move either thumbstick and the pointer moves.
Squeeze the **right trigger** to click. That is it — nothing to plug in, nothing
to set up, nothing to turn on.

**Your finger also works, and often better.** The Ally's screen is a touchscreen
and the desktop treats it as one: tap to click, press-and-hold for a right-click,
drag to scroll. For anything fiddly — dragging a clip, hitting a small button —
your finger is the faster tool. Use both.

---

## The full button map

| You press | It does |
|---|---|
| **Either thumbstick** | Move the mouse pointer |
| **Right trigger (R2)** | **Left click** — this is "click" |
| **Left trigger (L2)** | Right click (the menu you get from a long press) |
| **A** | Enter / confirm |
| **B** | Escape — close a menu, cancel, go back |
| **Y** | Space |
| **D-pad** | Arrow keys — move through a list or a menu |
| **L1** | Hold down Ctrl (so L1 + a key = a keyboard shortcut) |
| **R1** | Hold down Alt |
| **Start** | The Super key — opens the AquariusOS app grid |
| **Select** | Nothing |
| **X** | *Meant* to show the on-screen keyboard. It does not work — see below. |

Two things in that table trip people up, so they are worth saying out loud:

- **Click is the right trigger, not the A button.** A is Enter. They usually do
  the same thing on a button or a menu item, and are completely different on a
  file or a canvas.
- **B is escape, not "back one page".** In a browser, B closes a menu; it does not
  go back a page.

---

## Typing: the on-screen keyboard

**Tap into a text box and the keyboard comes up on its own.** That is the route to
use, and it is the one that works.

**The X button is supposed to summon it and does not.** That is a bug in KDE
Plasma 6.7 itself, not in AquariusOS, and KDE know about it — their own source
code has a note next to that button reading *"toggle Virtual Keyboard not
working.. Activated but does not show on-screen"*. Nothing we can ship fixes it.
If a future Plasma fixes it, the button will simply start working.

If you spend real time on the desktop, a small Bluetooth keyboard is still worth
having. This is meant to make the desktop usable, not to make a 7-inch handheld
a good place to write a screenplay.

---

## If the pointer feels sticky, doubled, or too fast

There is one known cause and it has a one-time fix.

**Steam starts up on the desktop too, and Steam can also turn your controller into
a mouse** — its "Desktop Layout" feature. When both Steam and the desktop are
pushing the same pointer, it stutters or races. Bazzite's own documentation warns
about the same clash.

Turn Steam's one off and keep ours:

1. In Steam on the desktop: **Steam → Settings → Controller**
2. Find **Desktop Layout** (sometimes under "Non-Game Controller Layouts")
3. Turn it **off**

Ours is the one to keep: it is part of the desktop itself, it is on for every
account, and it needs no setting up. Steam's has to be configured by hand per
account, and Bazzite records that on handhelds that are not Steam Decks it "may
not exist by default" anyway.

---

## Getting back to Game Mode

Double-tap (or R2 twice on) the **"Return to Gaming Mode"** icon on the desktop.

If that icon is missing, you are on a build from 2026-08-30 that briefly tidied it
away by mistake. Updating puts it back automatically. The whole story is in
`game-mode-regression.md`.

---

## How this works, for the record

Nothing was written for this. KDE Plasma 6.7 added a component of its own — a KWin
plug-in called `gamecontroller` — that turns any game controller into a mouse and
keyboard at the lowest level of the desktop. It is finished, it ships with Plasma,
and it is simply switched off out of the box.

AquariusOS switches it on, with one line in one file:

```ini
# /usr/share/aquarius/xdg-handheld/kwinrc
[Plugins]
gamecontrollerEnabled=true
```

Like every other default in AquariusOS, that is a starting point and not a lock:
your own settings sit above it and win.

**It only reaches the handheld image.** On a desktop PC the same setting would
mean that a controller plugged in for a game starts shoving the mouse pointer
around, which nobody wants. The folder is shipped to all three images and then
deleted again on the two desktop ones, in `build_files/build.sh`.

**What was considered and not used**, briefly, because both come up in every
search on this subject:

- **Handheld Daemon (HHD)** — gone. Bazzite Deck 44 removed it in favour of
  InputPlumber and OpenGamepadUI. Do not follow HHD advice found online; it does
  not apply to this OS.
- **An InputPlumber profile.** InputPlumber is running on the Ally and does ship a
  `Mouse and Keyboard (WASD)` profile, but there is no way to make a profile the
  default from a config file — the only supported route is a command run at login,
  the profile is aimed at playing keyboard-and-mouse games rather than at using a
  desktop (the left stick types W/A/S/D), and it would have to be unloaded again
  on the way back into Game Mode. A single config line in the desktop's own
  compositor is a better answer by every measure.

Sources, all read from the projects themselves rather than from forums:

* KDE/kwin, `Plasma/6.7` — `src/plugins/gamecontroller/metadata.json` (off by
  default), `src/pluginmanager.cpp` (how the setting's name is built),
  `src/plugins/gamecontroller/emulatedinputdevice.cpp` (the button map, and the
  upstream note about the X button)
* ublue-os/bazzite — `Containerfile` (Steam autostarts on the deck desktop via
  `/etc/xdg/autostart/steam.desktop`; `inputplumber` installed and enabled),
  `spec_files/steamdeck-kde-presets/kwinrc` (the on-screen keyboard lines)
* ShadowBlip/InputPlumber — `rootfs/usr/share/inputplumber/profiles/`, and
  `src/config/` for the absence of a default-profile setting
* docs.bazzite.gg, "Handheld Compatibility" and "Common Issues & Resolutions"
* ASUS ROG Xbox Ally (RC73YA) specifications — no trackpad on this device

---

## What has NOT been tested

All of the above was worked out by reading source code. **None of it has been run
on the Ally.** When Royce next boots it, the things to check, in order:

1. In Desktop Mode with nothing plugged in: **does a thumbstick move the
   pointer?** That is the whole fix in one question.
2. Does the **right trigger** click?
3. Does the **on-screen keyboard** appear when you tap into a text box (try the
   browser's address bar)?
4. Does the pointer feel **doubled or racing**? If so, do the Steam step above and
   say whether it fixed it.
5. Does **B** get you out of menus?

If the pointer does not move at all, the single most useful thing to send back is
the output of this, run in a terminal on the desktop:

```bash
kwriteconfig6 --file kwinrc --group Plugins --key gamecontrollerEnabled true
# then log out and back in — if THAT works, the shipped default is not being read,
# which is a different bug from the plug-in not working.
```
