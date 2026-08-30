# Why the login screen was too big, and what we did about it

*Written 2026-08-30, after Royce reported it on the ROG Xbox Ally.*

**The symptom.** On the Ally, the login screen came up enormous and cut off at
the edges — you could not see the whole of it. Once past it, the desktop was
fine.

**That combination is the whole clue**, and it is why this took reading source
code rather than guessing at settings.

---

## What is actually going on

The login screen on Fedora and Bazzite is not one simple program drawing on the
screen. It is a whole little desktop: SDDM (the login manager) starts **KWin** —
the same window manager the real desktop uses — and runs the login box inside it.

KWin decides how much to magnify a screen by working it out from the screen's
physical size, which the screen itself reports. The rule has two branches for a
built-in display:

| Kind of machine | KWin aims for | ...and will not go below |
|---|---|---|
| Something with a laptop lid | 125 DPI | 800 pixels of height |
| Something **without** a lid | 150 DPI | **360** pixels of height |

The second row is meant for phones — KWin's own comment there says *"phone
screens: even closer than laptops"*. A handheld has no lid, so it lands in that
row.

Now do the sum for the Ally. A 7-inch 1920×1080 panel is about 155 × 87 mm, which
works out at roughly **315 dots per inch**. 315 ÷ 150 = **2.1**, and the 360-pixel
floor is far too low to stop it. So KWin magnifies the login screen by **210%**,
leaving it a usable area of about **914 × 514 pixels** — and the login box simply
does not fit in that. Hence: too big, cut off at the edges.

**So why is the desktop fine?** Because your own account has a saved answer —
a file that says "this screen is 100%, don't guess". The login screen runs as a
*different* account (a system account called `sddm`), that account has no such
file, and so KWin guesses from scratch. Same code, two answers, and the one that
guesses is the one you see first.

> Source: `kwin/src/outputconfigurationstore.cpp`, `chooseScale()` — the two
> branches, the 150 DPI target and the `minSize = 360` are all in that function.
> The file KWin looks for is found by
> `QStandardPaths::locate(QStandardPaths::ConfigLocation, "kwinoutputconfig.json")`
> in `load()` in the same file.

---

## The fix

Give the login screen a saved answer too.

That is the only mechanism available, and it is worth saying why: **KWin has no
setting and no environment variable for screen scale.** There is no line you can
put in a config file, and none of the Qt scaling variables people suggest online
touch it — the scale is decided by the compositor before Qt ever sees the screen.
KWin reads exactly one file, and that file is what we write.

So AquariusOS now ships:

```
/usr/share/aquarius/greeter/kwinoutputconfig.json    the answer: 100%
/usr/libexec/aquarius-greeter-scale                  the script that installs it
/usr/lib/systemd/system/aquarius-greeter-scale.service   runs it before login
```

The service runs just before the login screen appears, copies that one small file
into the login screen's own home folder, and finishes. That is the entire change.

### It is decided by the SCREEN, not by which AquariusOS you installed

This is the important design decision on this page.

The obvious move would have been "do this on the handheld image only". That would
be wrong in both directions: a *desktop* AquariusOS installed on an Ally has
exactly the same small screen and exactly the same problem, and the *handheld*
image plugged into a television does not have it at all.

So the script asks the hardware what it is:

1. **Bazzite's own list first.** `/usr/libexec/hwsupport/needs-100-scale` already
   answers "does this machine's screen need to be left at 100%?" for every Valve
   device and a long list of handhelds — the ROG Ally RC71L, the Ally X RC72LA,
   the AYANEOs, the ONEXPLAYERs, the Legion Go family. Bazzite uses that answer to
   fix the *desktop's* scale. We are asking the same question about the same
   screen, so we ask them rather than keeping a second list that would drift.
2. **Plus the ROG Xbox Ally, which is missing from that list.** Bazzite knows this
   device elsewhere — its power-management script has a specific branch for it —
   but the scale list has never been updated for the newest board. So we add it,
   in the same style: a match on the start of the machine's own name, which
   covers both the base model (RC73YA) and the Ally X (RC73XA).

**On every other machine the service records itself as skipped and writes
nothing.** Your desktop PC's login screen is not touched, ever.

### It overwrites, every boot, on purpose

Worth knowing, because it looks heavy-handed until you know why. The login
screen's KWin **saves its own wrong answer** into that same file the first time it
runs. So "leave it alone if a file is already there" would fail on exactly the
machines that have the problem — every machine that has ever been switched on.

### The off switch

One file, and it never touches your login screen again:

```bash
sudo mkdir -p /etc/aquarius
sudo touch /etc/aquarius/no-greeter-scale
```

---

## What Royce must check on the Ally

**None of this has been run on the hardware.** It was worked out by reading KWin's
source, SDDM's source and Bazzite's own scripts. What the Ally has to confirm:

1. **Does the login screen fit on the screen now?** You will see it when you lock
   the session or log out. (If the handheld starts in Game Mode as it should, you
   will not see it on a normal boot at all — which is fine, but it still needs to
   be right for the times you do.)
2. If it still does not fit, the two commands that say what happened:

```bash
# Did our service run, and what did it decide?
systemctl status aquarius-greeter-scale
journalctl -u aquarius-greeter-scale

# Did the file land, and is it still ours?
sudo cat /var/lib/sddm/.config/kwinoutputconfig.json
```

3. **If the service says it skipped**, the machine's name is not being matched.
   Send back what this prints and it is a one-line change:

```bash
cat /sys/devices/virtual/dmi/id/product_name
```

4. **If the file is there and correct but the screen is still wrong**, the likely
   cause is that the built-in display is not called `eDP-1` on this machine. This
   prints what it really is called, from inside the desktop session:

```bash
kscreen-doctor -o
```

### The fallback, if the proper fix does not work

There is a second, cruder lever, and it is written down here so it is ready
rather than needing another research session. It tells the *login box* to draw
itself smaller instead of fixing the screen it is drawn on — worse-looking text,
but it un-crops the screen. Create this file and restart:

```ini
# /etc/sddm.conf.d/20-aquarius-greeter-scale.conf
[General]
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=eDP-1=0.5;,QT_WAYLAND_SHELL_INTEGRATION=layer-shell
```

Three traps in those two lines, all of them verified in SDDM's and Qt's source:

* `GreeterEnvironment` is a **comma**-separated list, while
  `QT_SCREEN_SCALE_FACTORS` is itself **semicolon**-separated. The punctuation
  above is not a typo.
* `QT_WAYLAND_SHELL_INTEGRATION=layer-shell` has to be repeated. Your file
  *replaces* the whole setting that Plasma ships, and leaving that part out breaks
  the greeter in a different way.
* `QT_AUTO_SCREEN_SCALE_FACTOR` — the variable most search results recommend —
  was **removed in Qt 6** and does nothing at all here. So was
  `QT_DEVICE_PIXEL_RATIO`. `PLASMA_USE_QT_SCALING` is a Plasma 5 relic and appears
  nowhere in Plasma 6.

Do not apply this at the same time as the proper fix. If both work, the screen
shrinks twice.

---

## Sources

Read from the projects themselves:

* KDE/kwin — `src/outputconfigurationstore.cpp`: `chooseScale()` (the 150 DPI /
  360 px "phone" branch) and `load()` (the one file it reads)
* sddm/sddm — `src/common/ConfigReader.cpp` (which config folder beats which),
  `src/helper/Backend.cpp` and `src/helper/waylandhelper.cpp` (how
  `GreeterEnvironment` is applied, and that it reaches the compositor too)
* KDE/plasma-workspace — `sddm-wayland-session/plasma-wayland.conf`, which is what
  makes the greeter run under `kwin_wayland` in the first place; Fedora enables it
* qt/qtbase — `src/gui/kernel/qhighdpiscaling.cpp` for which scaling variables
  still exist in Qt 6 and the exact syntax of `QT_SCREEN_SCALE_FACTORS`
* qt/qtwayland — `src/client/qwaylandscreen.cpp`, which reports a fixed 96 DPI on
  Wayland and is why the Qt auto-scaling variables cannot help here
* ublue-os/bazzite — `usr/libexec/hwsupport/needs-100-scale` (the device list we
  reuse), `hwsupport/sysid`, `hwsupport/steamos-manager-hardware` (which does know
  the ROG Xbox Ally), and every SDDM file Bazzite ships, which is two files and
  neither of them mentions scaling
* KDE bug [467039](https://bugs.kde.org/show_bug.cgi?id=467039) — the same problem
  on ordinary machines, fixed in Plasma 6.0.3 by teaching System Settings to copy
  this exact file into the login screen's home folder. We are doing by hand what
  that button does, because Bazzite hides that page from System Settings on
  handheld images.

**One honest note.** There is no upstream bug report about the login screen being
oversized on a handheld panel; searches of KDE's bug tracker and Bazzite's issues
turn up nothing. This is not a known bug somebody is fixing — it is hardware that
nobody has enabled yet, and until upstream does, it is ours to own.
