## Physical-device audit, 2026-10-15

On 2026-10-16 the owner confirmed the test device is the newly released
**ROG Xbox Ally X20 edition**. Its measured identifiers are board `RC74XA`,
system vendor `ASUS`, board vendor `ASUSTeK COMPUTER INC.`, product
`ROG XBOX Ally X RC74XA RC74XA`, and BIOS `RC74XA.301`. Use these identifiers
for compatibility checks; older RC73XA Ally X assumptions are not evidence
of X20 support.

The installed image `latest.20261015-4ed631a` contained the earlier Game Mode
boot changes. It was not a stale installation. The real handheld reports
`board_name=RC74XA` and `sys_vendor=ASUS`. Earlier RC73XA-only checks in this
document and the build were assumptions, not validation of this unit.
InputPlumber 0.82.0's shipped RC73XA/RC73YA matches do not cover that pair;
the build now adds RC74XA/ASUS to the same composite configuration.

Failed first-boot logs showed Steam's update manifest download failing, then
`Failed to load steamui.so`. The client was incomplete, and its exit returned
to GDM autologin. The handheld session wrapper now keeps that incomplete-client
recovery in the same session with Wi-Fi setup and an explicit Retry notice.
A completed Steam client still launches normally, including offline use.

GNOME's installed desktop had no monitor-scale default. The handheld-only
startup helper proposes 150% for an unconfigured 1080p internal display;
GNOME's Keep Changes confirmation saves it. Existing monitor settings and
docked/mirrored layouts are preserved. This is separate from installer scaling.

These changes require a rebuilt OS image, not just a customized installer.
The RC74XA/ASUS correction was tested on the physical handheld: InputPlumber
created CompositeDevice0, loaded AquariusOS Desktop, and the user confirmed
right-stick pointer movement and A/RT clicking. Gyro and an extra keyboard
source still reported errors (missing iio_trig_hrtimer and a busy device);
those are not validated by the pointer test. A subsequent physical reboot
confirmed direct Game Mode autologin, the controller compatibility service,
and the Default Game Mode controller profile. The user reached Steam sign-in
and then the library. Fresh offline-install recovery remains untested.

On 2026-10-16 the owner reported that most Game Mode controller inputs work,
but some do not. Complete Game Mode input coverage is an outstanding fix;
the earlier desktop pointer/click test does not validate it. Awaiting the
exact settings-button identities and whether failures occur in Steam, games,
or both. The owner narrowed the failures to extra settings buttons and rear
paddles. A timed read-only capture of ASUS 0b05:1b4c HID interfaces is staged
to establish actual reports before changing filters or hardware modes.
Current inspection shows CompositeDevice0 using the Default profile with an
Xbox Elite target and four evdev sources. Raw HID interfaces are rejected
because `asus_rog_ally` is absent, and the bmi323 IMU source fails because
`iio_trig_hrtimer` support is unavailable. These are investigation leads, not
proof of the cause of the owner's missing button inputs. No xremap process
was present in this Game Mode inspection.

The intro still stopped partway through and had no sound. The selected stock
`steam_os_startup.webm` is five seconds long and contains VP9 video and Opus
audio. PipeWire and WirePlumber ran, but ALSA exposed only HDMI and PipeWire
provided Dummy Output. The ACP audio driver logged `No matching ASoC machine
driver found` on `acp_asoc_acp70.0`. Firmware tables were collected and decoded
on 2026-10-16. SSDT8 sets `acp-audio-config-flag=0x10` (legacy DMIC-only),
despite describing SoundWire RT721 and two TAS2783 amplifier addresses.
The upstream ACP configuration code honors this flag unless a board-specific
exception applies; RC74XA is absent from its exception table. A scoped
driver-selection repair is under investigation. A normal post-sign-in startup
retest is also pending. No audio fix is claimed.

The first temporary RC74XA DMI-override module test loaded successfully, but
the live handover did not create a speaker card: `snd_pci_ps` failed to reserve
BAR 0 with error `-16` after the legacy driver was removed. The ACP PCI function
was left unbound and PipeWire still reported Dummy Output. The subsequent
audio PCI re-enumeration retry froze the device. The previous boot journal
shows a page fault in `string` / `r_show` while reading resource information
after the initial module swap, followed by a soft lockup in
`release_resource` / `pci_remove_bus_device` during the retry. This suggests
broken resource lifetime after the live unload; it does not establish that
the proposed boot-time DMI exception fixes audio. Do not repeat either live
driver swap or PCI removal test on this device.

Recovery verified on 2026-10-16 after the owner power-cycled the X20: SSH,
Game Mode, and InputPlumber are running; stock `snd_acp_pci` is bound again
and `snd_acp_config` has no module taint. The temporary test scripts are no
longer present after reboot. ALSA still exposes HDMI only and PipeWire still
uses `auto_null`. Audio remains unresolved. Any further driver test needs a
boot-time approach with a known-good rollback, not another live unload.

The single-boot DMI override subsequently booted successfully (boot ID
`50af8dee-bdee-45fd-a1fa-d6d96c8e39e8`). Its arm marker was consumed before
loading, `snd_pci_ps` bound the ACP function, and ALSA registered
`amd-soundwire`. RT721 enumerated on link 1; both TAS2783 amps enumerated on
link 0 at unique IDs 8 and B. No kernel fault was reported during the initial
inspection. This validates enumeration, not speaker playback or suspend.

Two additional gaps remain: the installed machine table has RT721 plus both
amps on link 1, whereas this unit has amps on link 0. The selected card exposes
only the RT721 headphone playback PCM (`cfg-amp:0`). Also, the TAS2783 driver
requests `1954-0-0x8.bin` / `1954-0-0xB.bin` (then fallback names without `0x`),
but the installed TI firmware contains four variant pairs named
`1954-{0,1}-{0,1}-0x{8,B}.bin.xz`. The correct variant selection must be
established; do not guess aliases or load another speaker's tuning. PipeWire
still uses Dummy Output with headphones unplugged. The experiment is consumed;
the next reboot returns to the stock configuration module.

The owner then plugged in 3.5 mm headphones. Jack detection selected the HiFi
profile automatically and replaced `auto_null` with the headphone sink.
Both low-volume spoken test samples played successfully and the owner
confirmed hearing them. Headphone playback is physically verified for this
boot; speaker playback and suspend/resume remain unverified.

The experimental split-link machine-table patch now compiles against the
exact Fedora kernel headers, but has not been deployed. ASUS's public RC74XA
support API lists TI Smart Amplifier V7.6.4.37 (2026-09-22) with hardware IDs
matching SUBSYS_19541043, link 0, UID 08/0B. Its downloaded installer SHA256
matches ASUS metadata: `d658a6b6ec15dbc504c69ea00b7a11d603f06e5c33165794872e678f3ab59733`.
Package inspection established speaker-ID selection as documented in
`tools/experimental/x20-audio/README.md`.

**Stereo speaker playback physically verified, 2026-10-16.** The combined
one-boot test booted successfully (`a5bbee28-61b9-4804-a81d-6849b4cbcbb9`),
loaded the speaker-ID 1 firmware pair, and exposed the SmartAmp playback PCM
at `hw:amdsoundwire,2`. A runtime-only copy of ALSA UCM with upstream
`sof-soundwire/tas2783.conf`, selected through a WirePlumber runtime service
drop-in, exposed separate Speaker and Headphones outputs. With headphones
unplugged, the owner confirmed hearing both spoken samples and then confirmed
that left and right played from separate corresponding speakers. The initial
heavily attenuated PipeWire test was inaudible; the repeat at moderate volume
was audible. Do not treat the initial silence as a driver failure.

This remains a temporary test: the next reboot restores stock modules and
removes the runtime UCM overlay. Firmware selection, boot driver selection,
split-link machine matching, and the missing UCM profile all require durable
integration. Headphone switching on the combined configuration, suspend/wake,
Steam intro playback with sound, and fresh-install behavior remain unverified.
Boot-time capture-probing errors on `SDW0-PIN4-CAPTURE-SmartAmp` also remain
to investigate; successful stereo playback does not validate that capture path.

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
- For older USB images, a **keyboard**, and ideally a **mouse**. New handheld
  ISO builds add larger text, controller navigation and an on-screen keyboard;
  see [the installer guide](handheld-installer.md), including pending bench checks.

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

**And no kernel change of any kind.** Fedora's own kernel already drives this
machine's controller, gyro, speakers, power limits, Wi-Fi and Bluetooth. That
is the whole reason this phase is small.

---

## What works, and what does not yet

| Thing | Expect |
| --- | --- |
| Boot, screen, touch, battery, storage | works |
| Sticks, face buttons, triggers, bumpers, stick clicks, View, Menu, Xbox button | works — through our button map (see "The button map" below) |
| Back paddles | work, **as one button**: the chip sends the same signal for left and right without the ASUS driver |
| The `...` button | **not yet.** Without the ASUS driver nothing reads it. Steam's **Xbox + A** opens the Quick Access menu instead |
| Gyro in Steam | works |
| Speakers, at full volume | works |
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

### RC74XA extra buttons — 2026-10-16 physical confirmation

The user identified the two captured presses as View, then Armoury Crate.
View emits the expected DInput BTN_TL report. Armoury emits exactly
`5a a6 00 00 00 00`, followed by `5a 00 00 00 00 00`. The user confirmed
that translating that press to InputPlumber's Guide+South chord opens Steam
Quick Access. The fallback `aquarius-ally-armoury.service` reads interface 2
without grabbing it or writing HID reports. It only handles RC74XA with the
generic `asus` driver and rediscovers the device after disconnect through
systemd restart. Native Ally driver devices are excluded to avoid duplicate
handling. Only captured reports activate it; repeats until release are ignored.
The helper and service are included in the handheld build. Physical reboot and
sleep/wake validation of the persistent service remains pending.

Paddle capture separately measured F17 (left) and F18 (right). The aqx1 map now
maps these to distinct Elite paddle buttons and the build adds both keys to
the package's evdev allowlist. Legacy F15 support is retained. The bench paddle
configuration has been installed; Steam paddle assignment still needs testing.

Paddle follow-up: the user reported the first patch did not appear to expose
paddles in Steam. Active InputPlumber capabilities still listed Keyboard:KeyF17
and Keyboard:KeyF18: the raw evdev mapping alone did not translate the keyboard
interface. The build now also extends the composite aly2 logical-key map with
F17→LeftPaddle1 and F18→RightPaddle1, retaining existing mappings. A second
bench update is staged; actual Steam detection remains unconfirmed.

Further paddle diagnosis: a timed virtual-device capture recorded A/B but no
paddles. Inspection of InputPlumber v0.82.0 commit
`d951ef9df713a3ad3a88645a8c07b79ea5592274` shows keyboard source translation in
`src/input/source/evdev/keyboard.rs` precedes `SourceDriver` filtering in
`src/input/source/mod.rs`. The earlier assertion that keyboard source mapping
was absent was incorrect. The source allowlist omitted the translated
Gamepad:Button:LeftPaddle1 and RightPaddle1 capabilities, dropping these events
before the composite map could see them. Build filtering now permits both
translated paddles; regression validation checks raw F17/F18 target capabilities
are in the source allowlist. Physical output after this correction is pending.

Status clarification: the user reported the paddles are assigned to A/B in a
per-game Steam layout. The virtual output capture cannot identify which
physical button produced those A/B events. Game testing is pending; the v3
filter update has been staged but the user was asked to hold installation.
No further device input changes were made while they test.

Other fixes prepared on 2026-10-16: an exact-kernel persistent audio workaround
is staged at `/tmp/aquarius-persistent-audio` on the bench device, not installed.
It preserves the verified two-module/firmware selection and reconstructs the
UCM tree before user sessions. No live driver replacement or Steam restart is
performed. Production kernel packaging remains outstanding. The handheld image
now fills the missing TAS2783 UCM profile only when ALSA does not provide it.

Installer keyboard layout now overrides both GNOME 50's `_relayout` and inner
AspectContainer ratio, restoring the methods on extension disable. This keeps
the key grid full width at 55% panel height, including layout/language changes.
Labels and GTK entry/button targets are enlarged. Controller regression tests
and JavaScript syntax pass; real ISO rendering and touch/controller validation
are still required. Installer flow simplification and the Steam intro cutoff
remain open. Read-only Steam logs did not expose an intro-specific error; the
current default sink is the verified Speaker sink. Do not restart Steam during
the user's paddle game test.

### Simplified handheld setup implementation

The USB runtime now hides only PasswordSpoke (the separate root account).
Drive selection, regular account creation, network and regional settings remain
available. `installer/simplify-setup.py` relabels the summary and its navigation
choices, adds short setup guidance and an explicit disk-erasure warning, and
preserves all signal handlers and backend validation. It refuses unknown GTK
source/UI layouts before writing changes. This runs only in the handheld ISO
customization container; desktop ISO kickstarts are unchanged.

Validation: transformation exercised on upstream Fedora 43 GTK files (the
upstream repository had no Fedora 44 branch available), two fixture tests cover
handler/confirmation preservation and refusal of changed layouts, and nine
controller/extraction tests pass. ISO assembly additionally verifies the actual
Fedora 44 runtime controls and configuration. The latter build and physical
handheld review have not yet run; source compatibility is not a visual signoff.
