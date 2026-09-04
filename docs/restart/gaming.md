# Gaming on AquariusOS

*Written 2026-09-04 for Phase R4. Assumes you have never used Linux, and have
never tried to play a game on it.*

---

## The one-paragraph version

AquariusOS now comes with **Steam** already installed, along with everything a
Windows game needs to run on Linux. You turn the computer on, open Steam, log
in, install a game, and play it. There is nothing to set up and nothing to
read first. Xbox and PlayStation controllers work. A performance overlay is
there if you want it, and invisible if you do not.

What it does **not** have is a "Game Mode" — the console-like interface a Steam
Deck boots into — and it does not support handheld gaming PCs. That is a
decision, not a gap, and the reasoning is at the bottom of this page.

---

## Why Linux gaming works at all now, in three sentences

Almost every PC game is written for Windows. A piece of Valve software called
**Proton** translates what a Windows game asks for into what Linux understands,
fast enough that most games run at full speed — you turn it on once in Steam and
then forget it exists. Today the large majority of the Steam catalogue works
this way; the exceptions are mostly competitive shooters whose anti-cheat
software refuses to run on Linux at all, and no operating system can fix that.

---

## What is in the image, and what each thing is

Everything below is a **system program**: it is inside the operating system when
you install it, on both the AMD/Intel image and the NVIDIA one. Nothing here is
downloaded on first boot.

| Program | What it is for | Where it comes from |
| --- | --- | --- |
| **Steam** | The shop and the launcher. | Terra |
| **umu-launcher** | Runs a Windows game through Proton from *outside* Steam. Heroic and Lutris use it. | Terra |
| **gamescope** | Gives a game its own private screen — lock a resolution, cap a frame rate, upscale cleanly. | Fedora |
| **gamemode** | A temporary performance boost while a game runs. Starts when asked, stops after. | Fedora |
| **MangoHud** | The frame-rate/temperature overlay. Off unless you ask for it. | Fedora |
| **vkBasalt** | Optional sharpening and colour effects in games. Off unless asked for. | Fedora |
| **protontricks**, **winetricks** | Per-game fixes for awkward Windows titles. | Fedora |
| **steam-devices** | The USB rules that let a controller work without administrator rights. | Fedora |
| **32-bit graphics libraries** | Old and 32-bit Windows games need a parallel set of these. Missing them is the classic "the game starts and instantly closes". | Fedora (+ NVIDIA's own on the NVIDIA image) |
| **xone**, **xpadneo** | Xbox wireless dongle, and Xbox controllers over Bluetooth. | Universal Blue's signed module box |

And three **optional** game launchers appear in the app chooser window at your
first login, all unticked — tick any you want:

- **Heroic** — for games bought on Epic, GOG or Amazon.
- **Lutris** — for everything else: old discs, itch.io, emulators, Battle.net.
- **ProtonUp-Qt** — installs community versions of Proton, for the occasional
  game the built-in one will not run.

Steam is **not** on that list. It is already in the operating system, so the
chooser shows it at the top under "Included with AquariusOS" with an **Open**
button, next to Aquarius Editor and Aquarius Writer.

> **Bottles** is deliberately not offered. It does the same job as Lutris by a
> different route, and giving one question two answers makes the list harder to
> read rather than more useful. It is one click away on Flathub for anybody who
> wants it.

---

## Your first ten minutes

1. **Open Steam** from the app grid (or from the app chooser window's Open
   button).
2. **It will download itself.** The first launch fetches a few hundred megabytes
   of Steam's own runtime before the login window appears, with a progress bar
   and no explanation. That is Steam's design on every Linux, it is not a fault,
   and it happens once. If the window seems to hang for a minute, it is
   downloading.
3. **Log in.**
4. **Turn Proton on**: Steam → *Settings* → *Compatibility* → tick **"Enable
   Steam Play for all other titles"** and pick the newest Proton in the list.
   This is the one setting that matters and it takes five seconds.
5. **Install a game and play it.** The first launch of any game is slow while it
   compiles shaders; the second is normal. That is expected and is not a
   problem with the machine.

---

## Controllers

**PlayStation controllers — DualShock 4, DualSense — just work.** USB or
Bluetooth, no drivers, no setup. Linux supports them itself.

**Xbox controllers, three cases:**

| How it is connected | What happens |
| --- | --- |
| USB cable | Works with Linux's own driver, always. |
| **Xbox Wireless Adapter** (the little USB dongle) | Needs `xone`, which AquariusOS ships. |
| Bluetooth | Works without help, but with wrong buttons on some models, no rumble and no battery reading. `xpadneo` fixes all three, and AquariusOS ships it. |

**One thing about the dongle.** `xone` needs a small piece of firmware that
Microsoft owns and that nobody else is allowed to hand out. Universal Blue's
package extracts it during their build, so it should already be in the image; if
your dongle is not detected, that is the first thing to check and the driver
prints a message about it in the system log.

**Did the Xbox drivers make it into your image?**

```
cat /usr/share/aquarius/gaming/controllers.txt
```

`installed` means yes. `unavailable` means the ready-made drivers were built
against a different kernel than your image runs, so they were left out rather
than shipped broken — this happens for a day or two after a Fedora kernel
update, and the next AquariusOS update has them. Everything else about
controllers keeps working meanwhile.

---

## The performance overlay (MangoHud)

It is installed and it is **off**. To see frame rate, temperatures and load in a
game:

1. In Steam, right-click the game → **Properties** → **Launch Options**.
2. Type: `mangohud %command%`
3. Launch the game. The overlay appears in a corner.

Delete the launch option to turn it off again. The same box is where every other
per-game trick goes, and they combine — see the next section.

---

## The launch options worth knowing

All of them go in the same box: Steam → right-click a game → Properties →
Launch Options. `%command%` is a placeholder meaning "the game itself".

| Type this | What it does |
| --- | --- |
| `mangohud %command%` | Show the performance overlay. |
| `gamemoderun %command%` | Ask for the temporary performance boost. |
| `gamemoderun mangohud %command%` | Both. They stack, in any order. |
| `gamescope -W 2560 -H 1440 -f -- %command%` | Run the game inside its own screen at that size, full screen. Useful for a game that will not behave on an ultrawide monitor, or one you want to run at a lower resolution than your desktop. |
| `ENABLE_VKBASALT=1 %command%` | Turn on vkBasalt's sharpening for that game. |

**gamemode does not need switching on.** It starts when a game asks for it and
stops afterwards. Some games ask for it by themselves; `gamemoderun` is how you
ask on their behalf.

---

## NVIDIA

Nothing to do. The NVIDIA image already has the driver (that is Phase R1's
work), and R4 adds the 32-bit half of it that 32-bit Windows games need. The
boot setting `nvidia-drm.modeset=1`, which Wayland gaming on NVIDIA requires, has
been set since R1.

NVIDIA is deliberately the primary target of this project — it is the only
vendor with official DaVinci Resolve support, CUDA, and NVENC hardware encoding
on Linux (standing decision 5). The AMD/Intel image gets the same gaming layer,
minus that one NVIDIA-only piece, and AMD cards are generally the *easier* ones
for games.

---

## Two things we deliberately did not do

### 1. Terra's graphics driver

Steam and umu come from **Terra**, Fyra Labs' Fedora add-on repository — the
same place Bazzite gets its Steam. Terra also publishes a **Valve-patched Mesa**
graphics driver, which lands Valve's game fixes months before Fedora does.
Bazzite uses it. **We do not.**

The reason is what this machine is for. A graphics driver that changes on a
gaming schedule is a good trade for a gaming console and a bad one for the
computer somebody's paid colour grade happens on. A game that needs the very
newest Mesa is a disappointing afternoon; a driver regression in the middle of a
client delivery is a bad week.

So AquariusOS keeps Fedora's Mesa, and to make sure that stays true:

- Terra is added to the machine and then **switched off**, and only switched on
  for the single command that installs Steam and umu. It cannot replace a Fedora
  package by accident, on our build machine or on yours.
- Every build checks that `mesa-dri-drivers` and `mesa-vulkan-drivers` still say
  their maker is Fedora, and fails if they do not.

### 2. gamescope's extra permission

gamescope prints a warning at startup asking for a permission called
`CAP_SYS_NICE`, which would let it raise its own scheduling priority. Bazzite
grants it. We do not, because on NVIDIA cards — our primary target — granting it
has a long, documented history of making gamescope pick the wrong graphics card
and fail to start entirely
([gamescope #521](https://github.com/ValveSoftware/gamescope/issues/521),
[#1370](https://github.com/ValveSoftware/gamescope/issues/1370)). The underlying
cause is that a program holding an extra capability has some of its environment
stripped by the system for security reasons, and several of the variables that
tell a Vulkan program which card to use are among them.

What it buys is a small scheduling advantage that **gamemode already provides**
by a route with none of these problems.

If you want it anyway, on your own machine:

```
sudo setcap 'cap_sys_nice=eip' /usr/bin/gamescope
```

and to undo it: `sudo setcap -r /usr/bin/gamescope`. Note that an AquariusOS
update replaces the system files, so this does not survive one.

---

## What is NOT here, and why

**No Game Mode session.** There is no console-style interface at the login
screen, and the machine does not boot into Steam. Steam's own **Big Picture**
mode does the same job for a desktop — it is in the app grid as *Steam (Big
Picture)*, or the full-screen icon in Steam's top-right corner — and it needs no
separate session, no automatic login and no extra plumbing to keep working.

**No handheld support.** No Steam Deck, ROG Ally, Legion Go or Ayaneo device
drivers, no gyro, no TDP sliders, no fan curves.

This is Royce's standing decision 6, taken on 2026-09-02, and the argument is in
[`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md)
section 4. The short version: Valve's SteamOS 3.8 now installs on the Ally,
Legion and Claw families itself, and Bazzite covers everything else. Doing
handhelds properly means owning a device matrix and testing thirty machines we
do not have. Doing them badly is worse than not doing them. AquariusOS is a
creator's desktop that games extremely well, and that is the whole claim.

Boot-to-Game-Mode may come back later as an *optional variant*. It is not
cancelled; it is simply not what R4 is.

---

## The bench checklist (the 4090 PC)

*Adapted from `docs/gaming-test-checklist.md`, with the handheld and Game Mode
rows removed — they do not apply to this line. Everything below is on the
machine already after a `bootc upgrade`; nothing needs installing first.*

### A. Steam and a real game — the core loop

- [ ] Open **Steam** from the app grid. Confirm the first-launch download
      completes and the login window appears.
- [ ] Steam → Settings → Compatibility → **Enable Steam Play for all other
      titles** is on, with a Proton version chosen.
- [ ] Install and play a **native Linux** title for a few minutes: it launches,
      has sound, saves, quits cleanly.
- [ ] Install and play a **Windows-only** title. This is the Proton receipt —
      📸 a screenshot of it running is the single most useful artefact from this
      whole checklist.
- [ ] Check the games are installing to the drive you expect (Steam → Settings →
      Storage), given how much video is already on this machine.

### B. Big Picture

- [ ] App grid → **Steam (Big Picture)** launches straight into the full-screen
      interface. (Also reachable from Steam's top-right full-screen icon.)
- [ ] A controller drives the whole interface.
- [ ] Exiting returns to the desktop with everything intact.

### C. Controllers

- [ ] `cat /usr/share/aquarius/gaming/controllers.txt` first — note whether it
      says `installed` or `unavailable` for each driver, so the results below are
      interpreted correctly.
- [ ] An Xbox controller over **USB cable**: Steam sees it, it drives a game.
- [ ] An Xbox controller over **Bluetooth** (pair from the tray): buttons are
      right, rumble works, battery level shows.
- [ ] The **Xbox Wireless Adapter** dongle, if there is one: the controller
      pairs to it and works.
- [ ] A PlayStation controller, if there is one: USB and Bluetooth both.
- [ ] Steam → Settings → Controller lists each one correctly.

### D. The overlay and the boost

- [ ] Add `mangohud %command%` to a game's launch options — the overlay appears.
      📸 A screenshot of it over a game gives us the frame-rate baseline for
      every future test.
- [ ] Change it to `gamemoderun mangohud %command%` — the game still launches
      and the overlay still appears.
- [ ] Remove the launch option — the overlay is gone.

### E. gamescope

- [ ] `gamescope -W 1920 -H 1080 -f -- glxgears` (or any game, via launch
      options) opens and runs. It is expected to print a warning about
      `CAP_SYS_NICE` — that is the permission we deliberately do not grant, and
      it is a warning, not a failure.
- [ ] Note whether it feels worse than running the game directly. If it does,
      say so; that is the evidence that would reopen the CAP_SYS_NICE decision.

### F. The display, since the Samsung ultrawide earns its keep

- [ ] **VRR / adaptive sync**: on in the display settings; in-game motion is
      tear-free.
- [ ] **HDR**, if the monitor supports it: try a game with HDR. Note what you
      saw either way — this is one of the reasons labwc was chosen over niri.
- [ ] Ultrawide-aware games offer the native resolution.

### G. Did the gaming layer break anything else?

*This is the half that actually matters, because the creator side is the
product.*

- [ ] **Both sessions still log in**: the Aquarius Desktop *and* GNOME.
- [ ] The dock, the top bar and the app grid are unchanged, and stay out of a
      full-screen game's way.
- [ ] **Aquarius Editor and Aquarius Writer still open.**
- [ ] **DaVinci Resolve still opens** and still sees the 4090 — the 32-bit
      NVIDIA libraries added in R4 sit beside the 64-bit ones and must not have
      disturbed them.
- [ ] **"Make Editor-Ready" still works** on a camera MP4.
- [ ] The app chooser window shows a **Gaming** shelf with three unticked apps,
      and Steam under *Included with AquariusOS*.
- [ ] Audio still behaves after a game has had the sound device.
- [ ] `sudo bootc upgrade` still completes — nothing added here layers a package
      on top of the image.

### If something goes wrong

| Problem | What it means |
| --- | --- |
| One specific game will not run | Look it up on protondb.com. Per-game quirks are normal Linux gaming; the OS is only implicated if *everything* fails. Games with kernel anti-cheat genuinely do not run on any Linux. |
| Steam will not start at all | The first-launch download may have failed. `steam` in a terminal shows why. |
| A game starts and instantly closes | Usually a missing 32-bit library. Send the output of `steam` run from a terminal — the missing name is in it. This is exactly what R4's 32-bit packages are meant to prevent, so it is worth reporting. |
| Stutter or low frame rate | MangoHud screenshot plus the game name. The first run of any game is rough while shaders compile; the second is the real one. |
| Xbox dongle not detected | Check `controllers.txt` first (above). If it says `installed`, `sudo dmesg | grep -i xone` says what the driver thinks. |

Report the boxes and the photos. Green on A–D closes R4.
