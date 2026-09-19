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

**And no kernel change of any kind.** Fedora's own kernel already drives this
machine's controller, gyro, speakers, power limits, Wi-Fi and Bluetooth. That
is the whole reason this phase is small.

---

## What works, and what does not yet

| Thing | Expect |
| --- | --- |
| Boot, screen, touch, battery, storage | works |
| Sticks, face buttons, triggers | works |
| Back paddles, Armoury button, Library button | works — *if* InputPlumber is 0.79.0 or newer (see below) |
| Gyro in Steam | works |
| Speakers, at full volume | works |
| Wi-Fi and Bluetooth | works |
| Steam's TDP slider and battery charge limit | works |
| Brightness slider | works |
| Sleep and wake, with the controller alive afterwards | works **if the MCU firmware is 313 or newer** |
| Switch to Desktop → GNOME, and back | works (phase G1) |
| RGB on the stick rings | should work, through InputPlumber — unverified |
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
- [ ] **Return to Game Mode** → back into Steam
- [ ] `aq game boot off` → restart → **login screen**
- [ ] `aq game boot on` → restart → **Game Mode**

### F. Living with it

- [ ] Run **one game for ten minutes**. Note how it plays, how hot it gets and
      what the fan does
- [ ] Note whether **VRR** behaves (this is the genuinely unknown one)
- [ ] Paste the whole of `aq handheld status` into the bench log

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
