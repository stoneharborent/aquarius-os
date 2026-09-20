# The Claw handheld image — AquariusOS on the MSI Claw 8 AI+

*Written 2026-09-20 for Phase G4. Assumes you have never used Linux. Read
[`game-mode.md`](game-mode.md) first if you have not, and
[`handheld.md`](handheld.md) if you want the sister machine's story — this page
builds on both.*

---

## The one-paragraph version

There is now a **fourth AquariusOS image**, `aquarius-os-handheld-claw`. It is
the ordinary AMD/Intel AquariusOS — the same desktops, the same DaVinci Resolve,
the same Steam — built for **one computer**: the MSI Claw 8 AI+ (A2VM), board
`MS-1T52`. Like the Ally image it **turns on straight into Game Mode**, because
a handheld with no keyboard cannot get past a password box, and it carries the
small programs that machine needs so its built-in controller reaches Steam as
one proper gamepad.

**This is round one, and round one is honest about what it cannot do.** The
Claw is an Intel machine and Linux support for it is younger than the Ally's. On
Fedora's kernel 7.2 — the kernel AquariusOS ships — the M1 and M2 paddles do
nothing, the controller's mode cannot be changed from Linux, there is no control
over the lights or rumble strength, and Steam's power slider will not move
anything. All of that is code that exists and is simply not in this kernel yet.
None of it is a fault to report. The table further down says exactly what is
what.

---

## ⚠️ Before you do anything: three things you can only do in Windows

**Do these while Windows is still on the machine. Once it is gone, you cannot.**

### 1. Update the firmware — all of it

Open **MSI Center M** → **Live Update** and install everything it offers:

- the **BIOS**,
- the **EC firmware** (the small chip that runs the fans, the keys and the
  power),
- the **gamepad / controller firmware**.

There is no Linux tool for any of these. Not one. If you skip this step and then
wipe Windows, the only way back is to reinstall Windows.

### 2. Set the controller to XInput mode — and leave it there

This is the single most important setting on the whole machine.

The Claw's built-in pad has four personalities, and it tells the computer which
one it is in by changing its USB identity:

| Mode | What it looks like to the computer |
| --- | --- |
| **XInput** | An ordinary Xbox controller. **This is the one you want.** |
| DInput | An older style of gamepad. Steam will be confused by it. |
| Desktop | The pad pretends to be a mouse and a keyboard. Games see no controller at all. |
| BIOS | Only while the machine is in its setup screen. |

**Linux on kernel 7.2 cannot change this.** The driver that could (`hid-msi`)
arrives in kernel 7.3. The mode is remembered by the controller's own chip, so
whatever you leave it on in Windows is what AquariusOS will find.

In MSI Center M, set it to **XInput**, and leave it.

Later, on AquariusOS, `aq handheld status` tells you which mode the pad is in,
in plain words.

### 3. Turn BitLocker off

Windows Settings → turn **BitLocker** off and **wait for it to finish
decrypting**. If you leave Windows' disk encryption on and then change the
machine's boot settings, Windows demands a recovery key you do not have.

---

## Installing it on the Claw

### What you need

- A **USB-C dock or hub** with at least one ordinary USB socket.
- A **USB stick** with the installer on it.
- A **keyboard**, and ideally a **mouse**. The installer's touch support works
  but its text is very small on an 8-inch screen.

### Getting the installer

The ISO is built by the **Build AquariusOS ISO** workflow in GitHub Actions.
Press "Run workflow", choose **handheld-claw** — not plain `handheld`, that is
the Ally's — wait twenty to forty minutes, and download the file from the
Artifacts section at the bottom of the run's page. Write it to a USB stick the
same way you would any other installer.

### In the BIOS

Hold **Volume Down** while you press the power button, or press **Del** on a
plugged-in keyboard.

| Setting | To | Why |
| --- | --- | --- |
| **Secure Boot** | **off** | Needed for a self-made installer stick. You can turn it back on later. |
| **Everything else** | **leave it alone** | ⚠️ This matters. Advice you will find online for the *older* Claw A1M — CPU topology tweaks, SpeedStep, Modern Standby — is for a different processor and does not apply to this machine. Lunar Lake's defaults are the tested configuration. |
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

**And if the controller genuinely does nothing at all**, the first thing to
check is which mode it is in. Run `aq handheld status` and look for the line
that says `1901 — XInput`. If it says anything else, that is the whole problem,
and the fix is in Windows.

---

## What is actually on this image that is not on the desktop one

| What | What it is for |
| --- | --- |
| **InputPlumber** | The important one. The Claw's pad works as a plain Xbox controller all by itself, but its extra buttons arrive as *keyboard* presses — the Guide button is an F15, the Quick Access button an F16. InputPlumber gathers the pad and those key presses into **one Xbox Elite controller** that Steam understands. ⚠️ It must be **version 0.80.0 or newer**, which is what carries the fix that makes the Guide button work at all. |
| **steamos-manager** (Terra's powerstation build) | What Steam's Quick Access Menu talks to for the power limit and the battery charge limit. It is switched on here. ⚠️ On this machine, on this kernel, it has nothing to write to — see below. |
| **steamos-powerbuttond** | Makes the power button behave like a console's: a short press sleeps through Steam, a long press opens the power menu. |
| **One udev rule** | Stops a nudged thumbstick waking the handheld in your bag. ⚠️ **This rule is ours and it is untested until the bench.** No distribution ships one for this machine; we wrote it on the same idea as the Ally's. |

Plus the one-line setting that makes it start in Game Mode, and
`aq handheld status`.

**And no kernel change of any kind.** That is a standing decision, not an
oversight. AquariusOS runs Fedora's kernel so that the machine Royce edits video
on stays boring and predictable. The cost is that this handheld gets its missing
pieces when Fedora does, and not before.

---

## What works, and what waits

| Part of the machine | Today, on kernel 7.2 |
| --- | --- |
| Boot, graphics, the screen, touch, storage, battery | **works** |
| Sticks, face buttons, triggers, D-pad (in XInput mode) | **works** |
| **Guide** button and the Quick Access keys | **works**, with InputPlumber 0.80.0 or newer |
| **M1 / M2 paddles** | **dead** — waits for kernel 7.3 |
| Switching the pad between XInput / DInput / Desktop | **not possible from Linux** — whatever the pad's own chip remembers. Set it in Windows. |
| Gyro | **none, and none is coming soon** — nothing on Linux exposes a motion sensor on this machine. Steam's gyro settings will be empty. |
| Sound | the Intel sound driver loads; **whether the speakers make a sound is a bench question** — the exact amplifier chip is not identified in any source |
| Wi-Fi and Bluetooth | **works** |
| **Steam's TDP / power slider** | **does nothing** — the kernel knob it writes through is an unmerged patch series. The raw power readings are visible in `aq handheld status`. |
| Fans | run themselves, from the machine's own firmware. Speed can be read; fan curves are not possible. |
| Lights (RGB), rumble strength, button remapping | **waits for kernel 7.3** plus userspace work |
| Sleep and wake | works in principle; ⚠️ watch for a known Lunar Lake problem where the processor sits at 400 MHz for a while after a long sleep, and for Wi-Fi or the controller not coming back |
| Variable refresh rate (VRR) | **unverified** — the screen advertises it; nobody has confirmed it under Linux |

### The one sentence to remember

**M1/M2, mode switch, RGB, rumble: kernel 7.3.** That line is printed inside the
image itself, in `/usr/share/aquarius/gaming/handheld.txt`, so it is readable on
the handheld with no internet and no copy of this page.

### What happens when kernel 7.3 arrives

Nothing, by itself — and then quite a lot, deliberately. The build watches for
it: every build of this image looks for the `hid-msi` driver and says in the
build log whether it is there. The day it appears, that is the signal to open
round two of this image and turn the paddles, the mode switch, the lights and
rumble on. Until then the build passes cheerfully without it.

---

## `aq handheld status` — the one command

    aq handheld status

It changes nothing, never asks for a password, and prints, in one screen:

- **which machine this is** — board `MS-1T52` is the Claw 8 AI+ A2VM;
- **which mode the controller is in**, spelled out: `1901 — XInput. This is the
  right one.` If it says anything else, it also tells you the fix is in Windows;
- whether **hid-msi** is loaded (expected: no, on kernel 7.2) and exactly what
  that costs you;
- which **InputPlumber** is installed, whether it is running, and what controller
  it built;
- the **read-only power numbers** from Intel's own accounting, so you can at
  least see what the machine is drawing;
- whether the **msi-wmi-platform** power knobs exist (expected: no) and whether
  fan speed can be read;
- brightness and battery;
- what the kernel said about the **sound processor** and the **Wi-Fi chip**.

**Paste all of it into the bench log.** If something needs reading that only an
administrator can see, `sudo aq handheld status` says more.

---

## If something goes wrong

### The controller does nothing, or behaves like a mouse

Run `aq handheld status` and read the mode line. If it is not `1901`, the pad is
in the wrong mode, and **only Windows can change it** on this kernel. That is
the whole fault, and it is the first thing to check every time.

### The screen is black, or scrambled, or Steam will not start

Press **Ctrl+Alt+F3** on a keyboard. That gives you a plain text login, which
does not need graphics at all. Log in, then:

    aq game boot off
    sudo systemctl reboot

and the machine comes back to the ordinary login screen, where you can pick
GNOME and work out what happened from a desktop.

### I want it to stop starting in Game Mode

    aq game boot off

### I want it back

    aq game boot on

### The M1 / M2 buttons do nothing

Expected. They need the `hid-msi` driver, which is in kernel 7.3 and not in
this one. Nothing is broken.

### Steam's power slider does nothing

Expected. See the table above. `aq handheld status` prints the real power
numbers if you want to know what the machine is actually doing.

### It wakes up in my bag

`50-aquarius-claw-controller.rules` is meant to stop exactly that, and it is
**our own rule, untested until the bench**. If it is still happening, say so —
that rule is the first thing to look at, and deleting it changes nothing else.

### It is slow for a while after waking up

Possibly the known Lunar Lake problem: after a long sleep the processor can sit
at about 400 MHz for seconds to tens of seconds. It is not specific to this
machine and it is not fixed upstream. **Note how long it lasts** — that number
is useful.

---

## The bench list

Royce, on the Claw. Work down it and put the answers in
`docs/design/bench-run-<date>-claw.md`.

- [ ] **Cold boot lands in Game Mode** with no password 📸
- [ ] `aq handheld status` says board `MS-1T52`, and pad product id **`1901`
      (XInput)**
- [ ] **Sticks, face buttons, triggers, D-pad** all move in Steam's controller
      test
- [ ] **Guide button** opens Steam's menu; the **Quick Access key** (F16 /
      Meta+G) opens the Quick Access menu
- [ ] **M1 / M2**: expected dead on kernel 7.2 — confirm and note it
- [ ] **Speakers make a sound**; the **headphone jack** works; the **volume
      keys** work
- [ ] **Wi-Fi joins** a network; **Bluetooth pairs** a controller
- [ ] **Steam's TDP slider**: expected inert — confirm and note it.
      `aq handheld status` prints the `intel-rapl` values
- [ ] **Sleep, then wake**: is the pad alive? is Wi-Fi alive? do the clocks sit
      at 400 MHz, and **for how long**?
- [ ] A **stick twitch does not wake it** in a bag (this is the test of our own
      udev rule)
- [ ] **Switch to Desktop**, then **Return to Game Mode** — both without a
      password
- [ ] **One game runs**: note the frame rate against Windows if you know it
- [ ] Paste the whole of `aq handheld status` into the bench log

Then the bench notes decide round two.

---

## ⚠️ One device, on purpose

This image targets the **MSI Claw 8 AI+ (A2VM), board `MS-1T52`**, and nothing
else.

MSI sell several machines with "Claw" in the name and they are **different
computers inside** — different processors, different graphics, different
firmware:

| Board | Machine |
| --- | --- |
| `MS-1T52` | **Claw 8 AI+ (A2VM)** — the one this image is for |
| `MS-1T41` | Claw A1M (an older Intel chip) |
| `MS-1T42` | Claw 7 AI+ |
| `MS-1T8K` | Claw A8 (AMD) |
| `MS-1T91` | Claw 8 EX AI+ |

None of the others is targeted and none is on the bench. `aq handheld status`
says so out loud if you run it on one. Widening the list without the hardware in
front of us is how a "supported device" becomes a bug report.

---

## Where the pieces are, for the record

| Thing | Where |
| --- | --- |
| The build step | `build_files/78-handheld.sh`, the `claw` half |
| The switch that picks the machine | `HANDHELD_TARGET=claw`, in the `Justfile` and `.github/workflows/build.yml` |
| Our udev rule | `handheld_files/claw/usr/lib/udev/rules.d/50-aquarius-claw-controller.rules` |
| Files both handhelds share | `handheld_files/` (the top level) |
| The report command | `handheld_files/usr/libexec/aquarius-handheld-status` |
| The note that ships inside the image | `/usr/share/aquarius/gaming/handheld.txt` |
| The spec | `../game-mode-g4-spec.md` |
| The research it rests on | `../g4-msi-claw-8-ai-plus-research-2026-09-20.md` |
| The sister machine | [`handheld.md`](handheld.md) |
