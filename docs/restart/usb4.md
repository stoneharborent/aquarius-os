# USB4 and Thunderbolt — when an external drive is not there at all

*Written 2026-09-07. Assumes you have never used Linux.*

---

## The one-paragraph version

On 7 September 2026 Royce's external drive stopped being discoverable on the
bench PC. Nothing was wrong with the drive, the dock, the cable, or with the
part of AquariusOS that mounts drives. What had failed was **the chip on the
motherboard that runs the fast USB-C sockets** — it did not get its driver
during boot, so everything plugged into those sockets was invisible to the whole
computer. AquariusOS now notices that and asks the computer to try again, at
every boot, automatically. **It is a retry, not a cure**, and as of the day this
was written it has never yet been seen to rescue a real machine.

---

## What USB4 and Thunderbolt actually are

Your PC has several kinds of socket that all look the same from the outside.

- **Ordinary USB** — a keyboard, a mouse, a USB stick. Simple, and none of this
  page applies to it.
- **USB4 / Thunderbolt** — the fast ones. A Thunderbolt dock, a USB4 SSD, an
  external graphics card, a monitor over USB-C. These are much closer to
  "plugging a card into the inside of your computer" than to plugging in a USB
  stick, and that is the important part.

USB4 and Thunderbolt are, for our purposes, the same thing. Thunderbolt is
Intel's name for it; USB4 is the standard that grew out of it. Modern AMD boards
like Royce's use a chip made by ASMedia that speaks both.

**All of those sockets are run by one chip on the motherboard.** Linux calls
that chip the **USB4 host router**. On the bench PC it is an ASMedia ASM4242,
and Linux knows it by an address: `0000:70:00.0`.

That chip needs a **driver** — a piece of the kernel that knows how to talk to
it — exactly the way a graphics card does. The driver is called `thunderbolt`.

**And here is the whole problem in one sentence:**

> Everything plugged into those sockets hangs off that one chip. If the chip
> does not come up, nothing plugged into it comes up either.

Not "fails to mount". Not "needs a password". **Invisible.** It does not appear
in Files, it does not appear in the Aquarius dock, and it does not appear in any
list of disks — because as far as the rest of the computer is concerned, you
never plugged anything in.

---

## What went wrong on the bench

Royce's setup: a **Corsair EX400U USB4 SSD**, attached to a **Satechi
Thunderbolt 5 CubeDock**, plugged into the bench PC (MSI MAG X870 TOMAHAWK WIFI,
BIOS 1.A70, running the AquariusOS image `latest.20260907-ea5fab6` on kernel
7.1.13).

On the eleven boots before it, this worked perfectly. The drive appeared as a
disk called `nvme2`, and the automatic mounting picked it up with no password,
exactly as AquariusOS is meant to (that part is `build_files/76-automount.sh`).

On the twelfth boot, the kernel said this — and only this:

```
thunderbolt 0000:70:00.0: enabling device (0000 -> 0002)
thunderbolt 0000:70:00.0: probe with driver thunderbolt failed with error -110
```

"Probe" is the kernel trying a driver on a piece of hardware. **`-110` is the
number Linux uses for "I asked, and nothing answered in time"** — five seconds,
in this case. The driver gave up. The chip was left with no driver at all. Every
USB4 socket on the machine went quiet, `boltctl list` showed both the dock and
the drive as *disconnected*, and the drive was gone from everywhere.

**Everything else was healthy.** The drive-mounting service (udisks2), the rule
that lets you mount without a password, the AquariusOS auto-mount agent and the
dock were all working correctly. There was simply no drive for any of them to
see. That is why this looked so much like a broken drive and was not one.

One earlier boot on the same machine had also logged a burst of `timeout reading
config space` lines, which is the same chip failing to answer in a different
place. **This controller is flaky at startup.** That is a hardware/firmware
behaviour, not something an operating system causes.

---

## What AquariusOS does about it now

Linux is perfectly happy to be told "try that driver again". So AquariusOS asks.

At every boot, on a machine that has a USB4 controller, a small program runs:
`/usr/libexec/aquarius-usb4-rescue`. For every USB4 controller that has **no
driver attached**, it:

1. Makes sure the `thunderbolt` driver is loaded at all.
2. **Waits about 15 seconds**, in case the kernel is still in the middle of its
   own first attempt. Interrupting a probe that is still running would be the
   worst thing it could do.
3. Then, up to three times: tells the driver to take that chip. If that does not
   work, and the kernel says this chip can be **reset**, it resets it (which
   power-cycles that one chip and nothing else on the machine) and tries once
   more.

**A controller that already has its driver — which is the case on almost every
boot of almost every machine — is left completely alone.** That is deliberate
and it is checked by a test, because resetting a *working* USB4 controller would
take out somebody's dock, their screen and their drive in one go, in the name of
fixing them.

It is switched on in an unusual way, and the reason is worth a sentence: instead
of the symlink AquariusOS normally uses to enable a service, a **udev rule**
(`/usr/lib/udev/rules.d/76-aquarius-usb4.rules`) starts it whenever a USB4
controller turns up. Linux replays "this hardware turned up" for hardware that
is already there at every boot, so the rescue runs on every boot of a machine
that has such a chip — and never at all on a laptop or handheld that does not.

---

## How to check it on a real machine

Open **Terminal** and type these one at a time.

### 1. Is the driver attached?

```
aq usb4 status
```

Good looks like this:

```
  0000:70:00.0
    driver attached : yes (thunderbolt) — this chip is working
    can be reset by : pm bus
```

Bad looks like this — and this is the fault this whole page is about:

```
  0000:70:00.0
    driver attached : NO — anything plugged into the USB4 sockets is invisible
                      Try:  sudo aq usb4 retry
```

The same command also prints `boltctl list`, which names your dock and your
drive. **`disconnected` beside everything, with no driver attached above, is the
fault.**

### 2. Did the rescue run, and what did it find?

```
journalctl -b -u aquarius-usb4-rescue
```

Every line begins `[usb4-rescue]` and is written in plain English. On a healthy
machine you will see it look, find everything already working, and stop:

```
[usb4-rescue]   0000:70:00.0: already has the thunderbolt driver — leaving it alone
[usb4-rescue] every USB4 controller on this computer has its driver. Nothing to rescue.
```

If you see nothing at all, the rescue did not run — which on a computer with no
USB4 controller is correct and expected.

### 3. What did the kernel say while booting?

```
journalctl -k | grep thunderbolt
```

This is where the original fault showed up. The line to look for is the one with
`probe with driver thunderbolt failed`.

### 4. What does the Thunderbolt device manager see?

```
boltctl list
```

This lists the Thunderbolt devices this computer has ever seen, by name — the
dock and the drive — and whether each one is connected right now.

---

## Try it by hand

```
sudo aq usb4 retry
```

That runs the same rescue immediately. It is safe to run at any time: a chip
that already has its driver is left alone. It prints what it does, and it tells
you plainly whether it worked.

---

## ⚠️ The honest limits

**This has never been seen to rescue a real machine.** It was written on
7 September 2026, the day the fault was diagnosed, and its logic is proved
against a fake set of files by `tests/test-usb4-rescue.sh`. That is not the same
thing as watching a bench PC come back. Until Royce sees a bind succeed on real
hardware, this page will keep saying so, and nobody should describe this feature
as fixed.

**A rebind and a reset ask the chip to start again from software.** If the
chip's own firmware has genuinely locked up, nothing software can say will reach
it. The only thing that clears that is taking the power away:

> **Shut the computer down. Wait ten seconds. Switch it on.**
>
> A *restart* is not the same thing — a restart usually leaves that chip
> powered, which is why a machine can restart five times and still not see the
> drive.

**A BIOS update is the other lever.** USB4 controllers are half firmware, and
board makers fix exactly this kind of startup flakiness in BIOS releases. The
bench PC is on MSI's BIOS 1.A70; if this keeps happening, checking MSI's support
page for the MAG X870 TOMAHAWK WIFI is a real fix in a way that a software retry
is not.

---

## If it still fails

In order, stopping as soon as the drive appears:

1. **`sudo aq usb4 retry`** — the rescue, on demand.
2. **Unplug the dock, wait ten seconds, plug it back in.** Some chips come back
   on a fresh connection when they will not come back on a bind.
3. **Full power-off.** Shut down, wait ten seconds, switch on. Not a restart.
4. **Try the drive in a different socket**, ideally one that is not USB4 at all.
   If it appears there, the drive is fine and this page is your problem. If it
   does not, the drive or the cable is the problem and this page is not.
5. **Check MSI's BIOS page** for a newer release than 1.A70.
6. **Tell Fable which of steps 1–5 changed anything.** That is the information
   that would let this be fixed properly rather than retried.

---

## For whoever changes this next

- The program is **`system_files/usr/libexec/aquarius-usb4-rescue`**. Its header
  is the long-form version of this page.
- It is started by **`system_files/usr/lib/udev/rules.d/76-aquarius-usb4.rules`**,
  which is the switch-on mechanism. There is deliberately **no `.wants` symlink
  and no `[Install]` section** in
  `system_files/usr/lib/systemd/system/aquarius-usb4-rescue.service`; the build
  fails if either appears. Both files explain why at length.
- The build step that checks all of it is **`build_files/79-usb4-rescue.sh`**,
  wired into the `Containerfile` as step 7i, right after the Bluetooth one.
- The tests are **`tests/test-usb4-rescue.sh`**. They run twice in CI: once
  before the build against the repository's copy, and once against the copy
  installed in the finished image.
- `AQ_SYSFS_ROOT` points the program at a fake folder of files instead of the
  real kernel. It exists for the tests and for nothing else.
- **The PCI class number `0x0c0340` is the feature.** It is what "this is a USB4
  host controller" means, for every maker. Get it wrong and the program searches
  for hardware that does not exist, finds nothing, reports success, and rescues
  nobody — silently, forever. It is checked by name in the build step and twice
  in the tests.
