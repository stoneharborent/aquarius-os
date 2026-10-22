# The handheld image — AquariusOS on the ROG Xbox Ally X

*Written 2026-09-19 for Phase G2. Assumes you have never used Linux. Read
[`game-mode.md`](game-mode.md) first if you have not — this page builds on it.*

---

## The one-paragraph version

There is now a **third AquariusOS image**, `aquarius-os-handheld`. It is the
ordinary AMD/Intel AquariusOS — the same desktops, the same DaVinci Resolve,
the same Steam — built for **one computer**: the ROG Xbox Ally X. Two things
are different and nothing else is. It **turns on straight into Game Mode**,
because a handheld with no keyboard cannot get past a password box. And it
carries the handful of small programs that machine needs so its built-in
controller, its gyro, its speakers and Steam's power sliders all work.

### Power button and first boot — repair prepared 2026-10-15

A quick press should sleep the handheld, not shut it down. Steam's button
service now holds a systemd inhibitor while Game Mode runs: this tells Linux
that Steam is handling the button, so Linux must not also act on the same
press. The service stops when you leave Game Mode. If the service is absent
or exits, the handheld's fallback action is suspend. Desktop power settings
continue to handle the button when a desktop is running.

The repair was checked against [Valve's powerbuttond 4.2 source](https://gitlab.steamos.cloud/holo/powerbuttond/-/tree/v4.2)
and [Terra's packaging](https://github.com/terrapkg/packages/blob/frawhide/anda/games/powerbuttond/powerbuttond.spec).
The daemon sends button events to Steam but does not itself acquire a logind
inhibitor. The source explains the conflicting handlers; a device journal is
still needed to confirm the exact shutdown path on the affected handheld.

This change needs a new image and a restart. It has passed a systemd service
check, but physical sleep, wake, and the long-press menu still need an Ally
bench test. Check these in both Steam's home screen and a running game, then
switch to the desktop and back and repeat. After waking, confirm the same
game is still open and the controller works. While in Game Mode,
`systemd-inhibit --list` should show Steam holding `handle-power-key`.

A **fresh handheld install** already ships with `mode=game`. The boot helper
runs before both the account service and the login screen, picks the first
ordinary account created during installation, and sets Steam as its session
with automatic login. Seven automated rehearsals check this path, repeated
boots, account selection, desktop defaults, and failure handling. A missing
Game Mode session now leaves automatic login off rather than opening a
leftover desktop. These rehearsals do not replace a real clean installation.
The regular AMD/Intel desktop image still defaults to the login screen;
choose the **handheld** installer for automatic Game Mode on first boot.

**Steam intro: still under investigation.** No animation fix is included in
this repair. The installed Steam client can end the movie on input, a video
error, or a window restart. We need logs and playback observation from the
affected handheld to identify the cause of the stutter and early cutoff.

---

## The built-in speakers (ROG Xbox Ally X20)

*Added 2026-10-21. Status: **builds and passes every automated check; needs a
bench test on the handheld.** Nothing here has made a sound yet on an image
built this way — only the 2026-10-16 bench experiment has.*

### What was wrong, in plain words

Royce's handheld is the **ROG Xbox Ally X20**. Its motherboard calls itself
**`RC74XA`**, made by **`ASUSTeK COMPUTER INC.`** With Fedora's kernel exactly as
Fedora ships it, the built-in speakers make no sound, and the sound menu shows
**"Dummy Output"**. Two things go wrong, and neither is ours:

1. The machine's own firmware tells Linux "this machine only has digital
   microphones" (a table called SSDT8 sets `acp-audio-config-flag=0x10`). That is
   not true — the speakers and headphone socket sit on newer wiring called
   **SoundWire**. Linux believes the firmware and picks the wrong sound path.
   Linux keeps a short list of laptops whose firmware says this wrongly;
   `RC74XA` is not on it yet.
2. Even on the right path, Linux's list of "which SoundWire parts are on which
   wire" does not describe this machine: here the two speaker amplifiers (TI
   **TAS2783**, addresses 8 and B) are on wire 0, and the headphone chip
   (Realtek **RT721**) is on wire 1.

On top of that, the amplifiers need the right TI firmware for this unit (it is
chosen by a number the machine stores, its **speaker ID** — `1` on the bench
unit), and ALSA needs a small speaker profile (`sof-soundwire/tas2783.conf`)
that Fedora's `alsa-ucm` package does not have yet.

On **2026-10-16** a bench experiment fixed all four by hand and the owner heard
the **left and right speakers separately**. That experiment was compiled for one
kernel, **7.2.10**. The image of 2026-10-21 (`20261021-91affcf`) moved to
**7.2.11**, the workaround correctly stepped aside for the new kernel, and the
speakers went silent again.

### What the image does now

**Fedora's kernel is not changed or replaced.** The handheld image (only) adds
two small **patched copies of two of Fedora's own sound drivers**, and a little
program that decides when to use them:

| Piece | What it is |
| --- | --- |
| `snd-acp-config` (patched) | Adds `RC74XA` to Linux's list of "the firmware is wrong, use SoundWire". |
| `snd-soc-acpi-amd-match` (patched) | Adds this machine's exact speaker wiring. |
| `/usr/libexec/aquarius-x20-audio` | The loader. Decides, every start-up, between our two drivers and Fedora's. |
| `/usr/share/alsa/ucm2/sof-soundwire/tas2783.conf` | The ALSA speaker profile, so a **Speaker** output appears. Only added if Fedora's package does not have one. |

**The two drivers are compiled fresh in every build, for whatever kernel that
build ships.** The build reads the kernel version from the same place the kernel
pin does ([`kernel.md`](kernel.md)), downloads **Fedora's own signed source code
for that exact kernel**, applies two small patches, and compiles. When the kernel
moves, the drivers move with it — there is no pinned version to go stale. If a
patch ever stops fitting the new source exactly, **the build stops** with a
message saying so; it never quietly ships a silent handheld.

**The loader only uses our drivers when everything checks out.** At start-up,
when Linux asks for those two sound drivers, the loader checks: this is an
`RC74XA` by ASUSTeK; neither driver is already running; Secure Boot is not
blocking unsigned drivers; our drivers exist for the running kernel; the
machine's speaker ID is one this image has firmware for; and that firmware
unpacks to exactly the bytes recorded when the image was built. If **any**
check fails, it loads **Fedora's normal drivers** instead — the machine then
behaves like stock Fedora (no speaker sound, but everything else normal). It
never guesses a firmware variant, and it never swaps a driver that is already
running (doing that on 2026-10-16 froze the handheld; never repeat it).

### ⚠️ Secure Boot must stay OFF on the X20

These two drivers are compiled by us and **not signed**. With Secure Boot
**on**, Linux refuses unsigned drivers. The loader sees that, uses Fedora's
drivers, and the result is: **no speaker sound, everything else working.**
Nothing breaks, nothing loops. Secure Boot is off on the bench unit today. To
check it at any time:

    mokutil --sb-state

It should say `SecureBoot disabled`.

### How to see which way it went

    cat /run/aquarius-x20-audio-status

The good answer on the X20 is a line saying **`patched RC74XA speaker drivers
loaded`**. Any line starting **`Fedora's stock`** says exactly why it fell back.
`aq handheld status` prints the same thing, and warns if pieces of the old bench
workaround are still on the machine. The kernel log has it too:

    journalctl -k -b | grep aquarius-x20-audio

To **switch it off** (back to Fedora's drivers) without changing the image:

    sudo touch /etc/aquarius/x20-audio-off
    sudo systemctl reboot

and to switch it back on: `sudo rm /etc/aquarius/x20-audio-off`, then restart.

### After you update: remove the old bench workaround

The 2026-10-16 experiment left files in `/etc` on the handheld. `/etc` is yours
and survives every update, so the new image does not remove them. The new image
already **wins over them** (its setting file sorts first), so nothing is urgent
— but they should go, so there is exactly one way the speakers are set up.

**Step 1.** Update and restart into the new image, the usual way:

    sudo bootc upgrade
    sudo systemctl reboot

**Step 2.** Check the new loader ran:

    cat /run/aquarius-x20-audio-status

You want `patched RC74XA speaker drivers loaded`. (If it says `Fedora's stock`,
stop here and paste the line into the bench log — do not remove anything yet.)

**Step 3.** Remove the old pieces, **in this order**. The order matters: the
old sound-profile service has to be switched off *before* its files go, or
the next start-up would point the sound system at a folder that no longer
exists. Copy these one line at a time:

    sudo rm -f /etc/systemd/user/wireplumber.service.d/81-aquarius-x20-ucm.conf
    sudo systemctl disable aquarius-x20-ucm.service
    sudo rm -f /etc/systemd/system/aquarius-x20-ucm.service
    sudo rm -f /etc/modprobe.d/99-aquarius-x20-audio-test.conf
    mkdir -p ~/x20-audio-old-workaround
    sudo mv /etc/aquarius/x20-audio-persistent ~/x20-audio-old-workaround/
    sudo systemctl daemon-reload

If they are there, the two earlier experiment folders can go the same way (an
error saying "No such file or directory" just means it was never there):

    sudo mv /etc/aquarius/x20-audio-v2 ~/x20-audio-old-workaround/
    sudo mv /etc/aquarius/x20-audio-test ~/x20-audio-old-workaround/

The old files are **moved, not deleted**, into a folder in your home, in case
anything needs comparing later. Delete that folder once the bench list below is
done: `sudo rm -r ~/x20-audio-old-workaround`.

**Step 4.** Restart, and check again:

    sudo systemctl reboot
    cat /run/aquarius-x20-audio-status
    aq handheld status

The status should say `patched RC74XA speaker drivers loaded`, and
`aq handheld status` should **not** list any "old bench workaround" lines.

### Bench checklist — the speakers (Royce, on the X20)

Put the answers in `docs/design/bench-run-<date>.md`. Use a moderate volume:
on 2026-10-16 a very quiet first test was inaudible and looked like a failure.

- [ ] `cat /run/aquarius-x20-audio-status` says **patched RC74XA speaker
      drivers loaded**
- [ ] The sound menu shows a **Speaker** output, not "Dummy Output"
- [ ] **Both channels**, headphones unplugged. In a terminal:
      `speaker-test -c 2 -t wav -l 1` — a voice says "Front Left" from the
      **left** speaker and "Front Right" from the **right** one
- [ ] **Headphone jack switching:** plug headphones in → sound moves to them;
      unplug → sound comes back to the speakers. Do it three times
- [ ] **Suspend and resume:** play something, sleep the handheld (Steam →
      Power → Suspend), wake it, and the speakers still play. Three times
- [ ] **Steam intro sound:** cold boot into Game Mode; the Steam start-up
      animation plays **with sound**
- [ ] **Two cold boots in a row**, speakers working after each (this is what
      broke on 2026-10-21)
- [ ] Paste `aq handheld status` and
      `journalctl -k -b | grep -iE 'aquarius-x20|tas2783|sdw'` into the bench log

Still unexplained from 2026-10-16, worth a line in the log if seen: boot-time
errors about `SDW0-PIN4-CAPTURE-SmartAmp`. Speaker playback working does not
prove that capture path.

### When this can be retired

When Fedora's kernel itself contains both changes (an `RC74XA` entry in
`sound/soc/amd/acp-config.c` and the RC74XA wiring in
`sound/soc/amd/acp/amd-acp70-acpi-match.c`) the patches will stop applying and
the build will say so. Then: delete `build_files/78-handheld-audio-build.sh`,
`build_files/x20-audio/`, the `x20-audio-src` stages in the `Containerfile`,
section 7b of `78-handheld.sh` and the X20 files under `handheld_files/` — and
bench-test again on Fedora's own drivers. The same goes for `tas2783.conf` once
Fedora's `alsa-ucm` ships it (the build already prefers Fedora's copy).

---

## ⚠️ Before you do anything: check the controller chip's firmware, in Windows

**Do this while Windows is still on the machine. Once it is gone, you cannot.**

The Ally's built-in controller has a small chip of its own, which ASUS call the
MCU. It has its own firmware, and **if that firmware is older than version 313,
waking the handheld from sleep leaves the controller dead** — the screen comes
back and nothing you press does anything.

The only tool that can update it is **ASUS's own Armoury Crate, in Windows**.
There is no Linux equivalent, and there is unlikely ever to be one.

So, before you wipe anything:

1. Boot Windows.
2. Open **Armoury Crate** → **Settings** → **Update Centre**.
3. Let it install everything it offers, including the "MCU" or "controller"
   firmware.
4. Restart, and check it says it is up to date.

Later, on AquariusOS, `aq handheld status` prints what the Linux kernel saw of
that version, so you can confirm it took.

---

## Installing it on the Ally

### What you need

- A **USB-C dock or hub** with at least one ordinary USB socket.
- A **USB stick** with the installer on it.
- A **keyboard**, and ideally a **mouse**. The installer's touch support works
  but its text is very small on a 7-inch screen.

⚠️ **The SD card slot cannot boot.** It is not an option and it is not a
setting. The installer has to arrive over USB-C.

### Getting the installer

The ISO is built by the **Build AquariusOS ISO** workflow in GitHub Actions.
Press "Run workflow", choose **handheld**, wait twenty to forty minutes, and
download the file from the Artifacts section at the bottom of the run's page.
Write it to a USB stick the same way you would any other installer.

### In Windows, first

- **Turn BitLocker off.** If you leave Windows' disk encryption on and then
  change the machine's boot settings, Windows will demand a recovery key you do
  not have. Turn it off, let it finish decrypting, then carry on.
- **Update the BIOS to the latest ASUS release.** Valve's own SteamOS guide for
  this machine insists on this and so do we — several of the things that make
  Linux behave on this hardware are BIOS fixes.
- **Update the MCU firmware**, as above.

### In the BIOS

Hold **Volume Down** while you press the power button. That is how you get into
the BIOS on this machine; there is no key to press.

Set these:

| Setting | To | Why |
| --- | --- | --- |
| **Secure Boot** | **off** | Fedora's boot loader is signed, but the NVIDIA-style extra modules and a self-made installer stick are much less trouble with it off. You can turn it back on later. |
| **UMA Frame Buffer Size** | **4 GB** or **8 GB** — *not* Auto | This is how much memory is set aside for graphics. "Auto" is the setting most closely associated with games that stutter or refuse to start on this machine. 4 GB is the safe default; 8 GB if you mostly play. |
| **SMT** | **on** | Leaving it on is not a performance preference. With SMT off, suspend and resume misbehave on Ally hardware. |
| **Animation Post Logo** | off, if you see it | Cosmetic, and it delays every boot. |
| **Boot order** | the USB stick first | Windows Boot Manager will try to put itself back at the top. Check it again after the first restart. |

Then boot from the stick through the dock and install as normal.

---

## What happens the first time it starts

The machine turns on and goes **straight into Steam's Game Mode**. There is no
login screen and no password, because there is nothing to type one with.

### ⚠️ If Steam says "connect a controller"

This is the one known first-run trap, and it is Steam's, not ours
(ublue-os/bazzite issue #3761). Steam asks "is there a controller?" once, very
early, the first time it ever runs — and on some Steam releases it asks before
anything can answer, then shows a setup screen you cannot get past **on a
machine whose controller is bolted to its sides**.

AquariusOS already does the thing that prevents it: the program that assembles
the built-in controller is started **before** the login screen, so it is ready
before Steam ever looks. If it still happens:

- **Plug any USB controller into the dock, once.** Steam sees it, the setup
  screen finishes, and the built-in controller works from then on. Unplug it
  again.
- Or press **Ctrl+Alt+F3** on a keyboard for a text login, and type:

      aq game boot off
      sudo systemctl reboot

  which brings the ordinary login screen back so you can sort it out from a
  desktop.

---

## What is actually on this image that is not on the desktop one

Five things, and that is all.

| What | What it is for |
| --- | --- |
| **InputPlumber** | The important one. Linux sees the built-in pad as *three* separate devices — the sticks and buttons, the paddles and the Armoury/Library buttons, and the motion sensor — and Steam has no idea they belong together. InputPlumber stitches them into **one Xbox Elite controller** with the paddles and the gyro attached. Without it you get a plain gamepad and no gyro. |
| **steamos-manager** (Terra's powerstation build) | What Steam's Quick Access Menu talks to when you move the **power limit** ("TDP") or the **battery charge limit**. On the two desktop images this is installed and left asleep; here it is switched on. |
| **powerstation** | A small service steamos-manager writes the power limit through on AMD. It comes as a required part of the above. |
| **steamos-powerbuttond** | Makes the power button behave like a console's: a short press sleeps through Steam, a long press opens the power menu. |
| **Two udev rules** | One stops a nudged thumbstick waking the handheld in your bag. The other lets the controller's chip sleep properly, so the pad is alive again after a resume. |

Plus the one-line setting that makes it start in Game Mode, and
`aq handheld status`.

**Fedora's kernel is not changed.** Fedora's own kernel drives this machine's
controller, gyro, power limits, Wi-Fi and Bluetooth as it is. The one addition,
since 2026-10-21, is sound on the **X20** (board `RC74XA`): two patched copies
of Fedora's own sound drivers, compiled for the image's exact kernel, used only
on that board — see [The built-in speakers](#the-built-in-speakers-rog-xbox-ally-x20).

---

## What works, and what does not yet

| Thing | Expect |
| --- | --- |
| Boot, screen, touch, battery, storage | works |
| Sticks, face buttons, triggers, bumpers, stick clicks, View, Menu, Xbox button | works — through our button map (see "The button map" below) |
| Back paddles | work, **as one button**: the chip sends the same signal for left and right without the ASUS driver |
| The `...` button | **not yet.** Without the ASUS driver nothing reads it. Steam's **Xbox + A** opens the Quick Access menu instead |
| Gyro in Steam | works |
| Speakers, at full volume | **X20 (`RC74XA`): needs a bench test** of the image-built drivers — see [The built-in speakers](#the-built-in-speakers-rog-xbox-ally-x20). Proven by hand on 2026-10-16 only |
| Wi-Fi and Bluetooth | works |
| Steam's TDP slider and battery charge limit | works |
| Brightness slider | works |
| Sleep and wake, with the controller alive afterwards | works **if the MCU firmware is 313 or newer** |
| Switch to Desktop → GNOME, and back | works (phase G1) |
| RGB on the stick rings | brightness: GNOME's quick settings → **Keyboard** slider (off, low, medium, high). Colour: white on the desktop; Steam may set its own in Game Mode. There is no colour setting on purpose |
| The controller on the desktop | works as a mouse and a few keys — see "The desktop on the handheld" |
| Variable refresh rate (VRR) | **unverified.** One report on another distribution says it misbehaves. |
| **Rumble strength, stick dead zones, response curves, button remapping** | **not yet.** These need a kernel patch series that is still being reviewed upstream (`hid-asus` v6). It is a separate decision whether to go and get it. |
| Custom fan curves | not yet, same reason |

### ⚠️ The one version number that matters: InputPlumber

- **Below 0.79.0**, the back paddles and the Armoury and Library buttons are
  mapped and labelled wrongly in Steam on this exact device. Fixed upstream by
  InputPlumber PR #688 on 3 September 2026.
- **0.79.5** shortened the thumbstick range on Ally hardware (InputPlumber
  issue #724). If a stick feels like it will not reach the corners, this is the
  first thing to suspect.

So the version worth having is **0.79.0 or newer and below 0.79.5**. Terra — the
repository this comes from — publishes one version at a time, so on most days
there is no choice to make. The build takes a version inside that window if one
is offered, otherwise it takes what there is, **says so in the build log, and
writes the version and the known issue into the image itself** at
`/usr/share/aquarius/gaming/handheld.txt`. `aq handheld status` prints it.

This is a plain userspace package. Changing which version the image carries is a
one-line change and a rebuild — no kernel, no modules, nothing delicate.

---

## The desktop on the handheld

*Added 2026-10-04.* What changes when you press **Switch to Desktop**.

### The dock

- It holds **Files, Steam, Game Mode, Aquarius Editor (once installed),
  Firefox, Terminal, Software and Settings**. DaVinci Resolve, Aquarius Writer
  and Text Editor are off the dock but still in the app grid.
- It **slides away whenever a window covers it** and comes back when nothing
  does.
- To bring it back over a window: **three fingers swiped up** (the Activities
  overview, which always shows the dock), the controller's **Menu** button
  (the same thing), or a mouse pushed against the bottom edge.
- A **one-finger** swipe up from the bottom edge is GNOME's on-screen keyboard,
  not the dock. Dash to Dock has no touch support at all, and Royce chose to
  leave that swipe to the keyboard.

These are defaults. An account that has already changed its dock keeps its
own. To take the handheld's:

    gsettings reset org.gnome.shell favorite-apps
    gsettings reset-recursively org.gnome.shell.extensions.dash-to-dock

### The app grid

GNOME runs this screen at 200 %, which makes the desktop 960×540 in GNOME's
units, and in a wide, short space its app grid always chooses 3 rows of 8 and
shrinks the icons to fit — too small to read or to aim at. A small extension
of ours, `aquarius-handheld@stoneharborent.github.io`, makes it **one row of
five icons at 128 points** — four times GNOME's size here. (2 rows of 5 at 64
points, the first try, was still too small on the bench.) It is a strip you
page through: the D-pad moves between apps and **Y** opens one. It is switched on once per
account, so turning it off in the Extensions app sticks.

### Back to Game Mode

The switch from the desktop to Game Mode used to stop on a black screen until a
restart (bench, 2026-10-04). GNOME's logout shuts down the account's message
bus; Steam's helper (`steamos-manager`), which runs in the desktop session on
the handheld, was left talking to that dead bus, and Game Mode's start-up
clean-up waited on it for ever. Now that helper ends with the session, the
clean-up gives up after 15 seconds, and every switch starts a fresh account
manager the way a boot does (`UserStopDelaySec=0`).

### The controller is a mouse

When a desktop starts, InputPlumber switches the built-in controller to
`/usr/share/aquarius/inputplumber/desktop.yaml`. When Game Mode starts, it is
put back to an ordinary Xbox controller **before Steam opens**.

| Control | On the desktop |
| --- | --- |
| Right stick | the pointer |
| Left stick | scroll, one notch per push |
| RT, A | left click |
| LT | right click |
| LB | middle click |
| RB | Alt+Tab |
| B / X / Y | Escape / Backspace / Enter |
| D-pad | arrow keys |
| View / Menu | Tab / Super (Activities) |
| Xbox button | unchanged |

**Why not Steam in the background**, which is what some other systems do: on
GNOME Steam has to ask "Allow Remote Interaction" before it can move the
pointer, and asks again every time it restarts — every switch out of Game
Mode. It also needs an extra library Fedora does not ship to reach GNOME's own
apps, and it sits in memory the whole time.

The switch is done by `/usr/libexec/aquarius-handheld-input`, which only works
for an administrator (the `wheel` group), and logs to
`journalctl -t aquarius-handheld-input`. `aquarius-handheld-input status` says
which map is loaded.

### Typing

GNOME's own **on-screen keyboard comes up in any text box**, including one
chosen with the stick. On the handheld its keys fill the **whole width** of the
screen (GNOME left 200 empty points either side) and it is a little taller.
**Swipe down across it to put it away**; a one-finger swipe up from the bottom
edge brings it back. With a real keyboard plugged in, switch it off in
Settings → Accessibility → Typing → Screen Keyboard.

### The stick rings' colour

Quick settings → **Rings**: the switch turns them off and on, and its menu
picks a colour (white, AquariusOS blue, Steam blue, Xbox green, X20 gold, cyan, green, red, orange,
pink, purple) or an effect (a turning rainbow, every colour in turn, breathing). The
same from a terminal, with no password:

    aq handheld rings blue
    aq handheld rings '#ff8800'
    aq handheld rings breathe pink
    aq handheld rings rainbow
    aq handheld rings off

The choice is saved in `~/.config/aquarius/rings.conf` and the ring service
applies it at once. In Game Mode Steam may set its own colours.

The LEDs' red is weaker than their green and blue — plain white came out light
cyan on the bench — so every colour is white-balanced first. If white still
looks tinted, the three numbers are `WHITE_BALANCE` in
`/usr/libexec/aquarius-ally-rings`.

### The stick rings' brightness

GNOME's quick settings has a **Keyboard** slider. On the Ally it is the stick
rings. On its own it only turned them off and on: the controller chip treats
every level above 0 as "on" in its one-colour mode. So
`aquarius-ally-rings.service` watches the level and dims the rings by darkening
their colour instead — 15 %, 45 % and 100 % — the same way HHD does it. On the
very first boot a saved level of 0 is turned into medium; after that your
choice, including off, is kept. Its log: `journalctl -u aquarius-ally-rings`.

---

## `aq handheld status` — the one command

    aq handheld status

It changes nothing, never asks for a password, and prints, in one screen:

- which machine this is (board `RC73XA` is the Xbox Ally X);
- what the kernel said about the controller chip's firmware version;
- which InputPlumber is installed, whether it is running, and what controller it
  built;
- the **power limit right now** in watts — move Steam's TDP slider and run this
  again, and the number should change. That is the proof the slider is real;
- whether the controller chip's power saving is on;
- brightness and battery;
- whether the speakers' and the radio's firmware loaded.

**Paste all of it into the bench log.** If something needs reading that only an
administrator can see, `sudo aq handheld status` says more.

---

## If something goes wrong

### The screen is black, or scrambled, or Steam will not start

Press **Ctrl+Alt+F3** on a keyboard. That gives you a plain text login on this
machine, which does not need graphics at all. Log in, then:

    aq game boot off
    sudo systemctl reboot

and the machine comes back to the ordinary login screen, where you can pick
GNOME and work out what happened from a desktop.

### I want it to stop starting in Game Mode

    aq game boot off

### I want it back

    aq game boot on

### It wakes up in my bag

Check `aq handheld status` says `mcu_powersave` is `1`, and check the MCU
firmware version. Those two, in that order, are the whole of this fault.

### The controller is dead after waking up

Almost certainly MCU firmware below 313. See the top of this page: the fix is in
Windows, with Armoury Crate, and there is no Linux route to it.

---

## The bench list

Royce, on the Ally. Work down it and put the answers in
`docs/design/bench-run-<date>.md`.

### A. It turns on and the controller drives it

- [ ] Cold boot goes straight into **Game Mode** with no password 📸
- [ ] Steam's interface is at the screen's own **1080p**, not stretched or
      letterboxed
- [ ] **The built-in controller drives it** — sticks, face buttons, triggers,
      D-pad
- [ ] The **back paddles** do something sensible in Steam Input, and are
      labelled as paddles
- [ ] The **Armoury** and **Library** buttons do something sensible
- [ ] The **gyro** moves in Steam's controller test

### B. Sound and radio

- [ ] Sound from **both speakers** at full volume, no crackle, no dropouts
      (on the X20, work through [the speaker checklist](#bench-checklist--the-speakers-royce-on-the-x20) first)
- [ ] **Wi-Fi** connects
- [ ] **Bluetooth** pairs with something

### C. The sliders

- [ ] Steam QAM → Performance: the **TDP slider moves**, and
      `aq handheld status` shows a different `ppt_pl1_spl` afterwards
- [ ] The **brightness** slider works
- [ ] The battery charge limit, if Steam offers it

### D. Sleep — three times

- [ ] Steam → Power → **Suspend**; wake with the power button; **the controller
      still works** — repeat three times
- [ ] A **stick twitch does not wake it** from a bag

### E. The switch, both ways

- [ ] Power → **Switch to Desktop** → lands in **GNOME**
- [ ] **Touch works** in GNOME
- [ ] **Game Mode** → back into Steam
- [ ] `aq game boot off` → restart → **login screen**
- [ ] `aq game boot on` → restart → **Game Mode**

### E2. The desktop (2026-10-04)

- [ ] Switch to Desktop → the **right stick moves the pointer**, A and RT click,
      LT right-clicks, the left stick scrolls
- [ ] `aquarius-handheld-input status` says **AquariusOS Desktop**
- [ ] Click a text box with the stick → the **on-screen keyboard** comes up
- [ ] Open Firefox maximised → the **dock slides away**; three fingers up
      brings it back; close Firefox → the dock returns
- [ ] Sleep and wake **on the desktop** → the stick still moves the pointer
- [ ] **Game Mode** from the dock → Steam sees an ordinary controller (A
      selects, the stick does not move a pointer)
- [ ] Show Apps → **one row of five 128-point icons**, readable from arm's
      length; the D-pad pages through them and Y opens one 📸
- [ ] The on-screen keyboard **fills the screen's width**; a **swipe down**
      across it closes it without typing anything
- [ ] Desktop → **Game Mode** five times in a row, never a black screen
- [ ] The **Keyboard** slider in quick settings: four positions give
      **off, dim, medium, bright** rings, not just off and on
- [ ] After a restart the rings come back at the brightness you left them
- [ ] Quick settings → **Rings** → each colour; **white looks white**, not cyan
- [ ] **Rainbow**, **every colour in turn** and **breathing** all animate; the
      Keyboard slider still dims them
- [ ] The Rings switch turns them off, and on again to the same effect

### F. Living with it

- [ ] Run **one game for ten minutes**. Note how it plays, how hot it gets and
      what the fan does
- [ ] Note whether **VRR** behaves (this is the genuinely unknown one)
- [ ] Paste the whole of `aq handheld status` into the bench log

### The button map (bench, 2026-10-04)

The first boot on the Ally found the controller *detected* but wrong: Steam saw
an Xbox Elite pad on which X and RB did nothing, LB pressed X, View pressed LB,
Menu pressed RB and the Xbox button pressed View. The chip and the kernel were
fine. What was wrong was the **button order**.

InputPlumber's own config for this machine assumes an ASUS kernel driver
(`asus_rog_ally`) that puts the controller in Xbox order. Fedora's kernel does
not have that driver yet, so the controller arrives as a plain "DInput" pad, in
a different order, and InputPlumber read it as if it were in Xbox order.

Two pieces fix it. Both were measured and proven on the Ally before they went
into the image:

1. **`aquarius-ally-controller`** writes a known button layout to the
   controller chip, at boot and after every sleep. Without it, View sends
   nothing at all. The bytes are HHD's, unchanged.
2. **`aquarius_ally_x_dinput.yaml`** (map id `aqx1`) tells InputPlumber what
   each signal in that layout really is. It was written from a
   press-every-button test, not copied: HHD's map has the triggers the other
   way round.

To see the controller set itself up: `journalctl -b -u aquarius-ally-controller`.

---

## Where the pieces are, for the record

| File | What it is |
| --- | --- |
| `build_files/78-handheld.sh` | The whole of this phase. On the two desktop images it installs nothing and instead proves that none of it arrived. |
| `handheld_files/` | The files that go **only** on this image. They are kept out of `system_files/`, which is copied onto every image with no filter. |
| `handheld_files/etc/aquarius/login-mode` | The one line that makes it start in Game Mode. |
| `handheld_files/usr/lib/udev/rules.d/50-ally-x-controller.rules` | The wake-source rule. **Copied byte-identically from ublue-os/bazzite PR #5735** — do not tidy it, so a future upstream change is one `diff`. |
| `handheld_files/usr/lib/udev/rules.d/70-aquarius-ally-mcu-powersave.rules` | Ours: switches the controller chip's power saving on where the kernel has not. |
| `handheld_files/usr/libexec/aquarius-handheld-status` | The report `aq handheld status` runs. |
| `handheld_files/usr/libexec/aquarius-ally-controller` | Writes the known button layout to the controller chip. |
| `handheld_files/usr/lib/systemd/system/aquarius-ally-controller.service` | Runs it: started by the udev rule below, and at the end of every sleep. |
| `handheld_files/usr/lib/udev/rules.d/71-aquarius-ally-controller.rules` | Starts that service whenever the controller chip appears (boot, and after sleep). |
| `handheld_files/usr/share/inputplumber/capability_maps/aquarius_ally_x_dinput.yaml` | The measured button map. The build attaches it to InputPlumber's Xbox Ally config (`78-handheld.sh`, section 2b). |
| `handheld_files/usr/share/glib-2.0/schemas/zz1-aquarius-90-handheld.gschema.override` | The handheld's dock and the on-screen keyboard default. |
| `handheld_files/usr/share/aquarius/inputplumber/desktop.yaml` | The controller as a mouse on the desktop. |
| `handheld_files/usr/libexec/aquarius-handheld-input` | Loads that map when a desktop starts (`etc/xdg/autostart/aquarius-handheld-input.desktop`) and puts the ordinary one back before Game Mode's Steam (`usr/lib/systemd/user/gamescope-session-plus@.service.d/60-aquarius-handheld-input.conf`). |
| `handheld_files/usr/share/gnome-shell/extensions/aquarius-handheld@stoneharborent.github.io/` | The large app grid. |
| `handheld_files/usr/libexec/aquarius-ally-rings` | Makes the Keyboard slider dim the stick rings. Run by `aquarius-ally-rings.service`, started by `72-aquarius-ally-rings.rules`. |
| `build_files/78-handheld-audio-build.sh` | The X20 speaker-driver workshop: compiles the two patched sound drivers for the image's exact kernel from Fedora's signed source. Handheld image only. |
| `build_files/x20-audio/rc74xa-acp-config.patch`, `rc74xa-soundwire-links.patch` | The two bench-proven patches (2026-10-16), byte-identical to the experiment's. |
| `handheld_files/usr/libexec/aquarius-x20-audio` | The loader: our drivers on an RC74XA when every check passes, Fedora's otherwise. |
| `handheld_files/usr/lib/modprobe.d/10-aquarius-x20-audio.conf` | Routes the two driver names through the loader. |
| `handheld_files/usr/lib/depmod.d/aquarius-x20-audio.conf` | Keeps our two copies out of Linux's normal driver index, so "Fedora's driver" always means Fedora's. |
| `handheld_files/usr/lib/dracut/dracut.conf.d/90-aquarius-x20-audio.conf` | Keeps both drivers out of the boot ramdisk, where the loader cannot run. |
| `handheld_files/usr/share/aquarius/audio/tas2783.conf` | The upstream ALSA speaker profile; copied into ALSA's folder only if Fedora's package lacks it. |
| `tests/test-x20-audio-loader.py` | Runs the loader against a fake machine for every reason it must fall back. Logic only. |
| `.github/workflows/build.yml` | Builds all three images, and runs the handheld checks on **all three** — half of what they prove is that the other two are untouched. |
| `.github/workflows/build-iso.yml` | Has **handheld** as a choice. That ISO is the only way onto the Ally. |

Research that decided all of it: `../g2-xbox-ally-x-research-2026-09-19.md` (the
device) and `../g2-ally-research-2026-09-19.md` (the family). The spec is
`../game-mode-g2-spec.md`; the decision is
`../decision-2026-09-17-game-mode-and-handheld.md`.

---

## ⚠️ One device, on purpose

This image targets the **ROG Xbox Ally X, board `RC73XA`**, and nothing else.
Not the Xbox Ally Z2 A, not the 2023 Ally, not a Legion Go, not a Steam Deck.

That is not timidity. Every one of those machines has a different controller
wiring, a different power-limit table and a different set of things that are
broken this month, and the only honest way to say "this works" is to have the
machine on the bench and try it. Royce owns one handheld. That is the list.

If another one ever joins it, the work is: add its board name to the device
profile checks in `78-handheld.sh`, find out which `steamos-manager` device
table it is in, and run the bench list above from the top.
