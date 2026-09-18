# Game Mode

*Written 2026-09-17, for Phase G1. Assumes you have never used Linux.*

---

## The one-paragraph version

AquariusOS can show you two completely different faces on the same computer.
One is **the desktop** — GNOME or KDE Plasma, windows, Files, Resolve; what you
work in. The other is **Game Mode** — Steam owning the entire screen, big
tiles, driven with a controller from the sofa. It is the same thing a Steam
Deck shows, and it is the same computer underneath: the same games, the same
drives, the same save files. You move between them with one click, in either
direction, and you are never asked for a password.

**A cold boot is unchanged.** Switch this computer on and you get the login
screen, exactly as you always have. Game Mode is somewhere you go, not
somewhere you land — unless you ask for that, which is one command.

---

## Going to Game Mode

**From the app grid:** an icon called **Return to Game Mode**.
**From a terminal:** `aq game`.

Either way you get a warning first, and you should read it once:

> **This will close your desktop.** Every window shuts and anything you have not
> saved is lost.

That is not a corner AquariusOS cut. Two of these cannot share one graphics card
— the desktop and Game Mode each want to be the thing talking to your monitor —
and on an NVIDIA card the attempt does not merely look wrong, it freezes the
machine. We tried it on Royce's PC on 17 September 2026 and had to hold the
power button. So every Linux that has a Game Mode does the switch as a full
logout: SteamOS, Bazzite, ChimeraOS, Nobara, all of them. AquariusOS does the
same and says so before it happens.

**You are not asked for a password.** You cannot type a password with a game
controller in your hands, so the computer logs you straight in. How that is done
safely is at the bottom of this page.

---

## Coming back to the desktop

In Game Mode, press the **power button at the bottom-left of Steam's screen**,
then **Switch to Desktop**.

It puts you back in **the desktop you came from** — GNOME if you were in GNOME,
Plasma if you were in Plasma. AquariusOS writes that down on the way out and
reads it on the way back. No password there either.

---

## Starting the computer in Game Mode

| What you type | What happens |
| --- | --- |
| `aq game boot on` | From the next restart, this computer goes straight into Game Mode. No login screen. |
| `aq game boot off` | Back to normal: the login screen, asking who you are. **This is what AquariusOS ships.** |
| `aq game status` | Where you are now, what a restart will do, and whether Game Mode is installed at all. |

The setting lives in one small file, `/etc/aquarius/login-mode`, and it says
`mode=desktop` on every AquariusOS desktop image. Switching to Game Mode and
back **never touches it**. How you start your computer and what you did last
Tuesday evening are different questions, and the machine keeps them apart.

---

## If the screen is black, or the picture is scrambled

**Press Ctrl+Alt+F3.** That is the escape hatch for any graphical problem on
this machine: it gives you a plain text login on the same computer, running the
whole time behind whatever you are looking at. Type your name, type your
password (nothing appears as you type — that is normal), then:

```
aq game boot off
sudo systemctl reboot
```

and the login screen is back.

### Trying gamescope by hand, safely

If you want to test the thing that draws Game Mode without risking a frozen
machine, put a timer on it. This runs it for sixty seconds and then stops it,
whatever state it is in:

```
timeout -k 5 60 gamescope --backend drm -e -f -W 3840 -H 2160 -r 60 -- steam -gamepadui -steamos3
```

`timeout -k 5 60` means "give it sixty seconds, then ask it to stop, and five
seconds after that stop it the hard way". It is the difference between a test
and an afternoon lost to a power button. The `--backend drm` is not optional
when you are testing from a text terminal: without it gamescope opens as a
*window inside your desktop* and proves nothing.

---

## ⚠️ Why the NVIDIA image carries its own gamescope, and the AMD one does not

This is the one place where the two AquariusOS images are deliberately
different, so it is worth understanding.

**What gamescope is.** A very small program that Game Mode runs inside. Steam
and your games draw into it, and it puts the finished picture on your screen.

**What goes wrong on NVIDIA.** A picture that is about to go on screen has to
live in one unbroken run of graphics memory, because the display hardware reads
it straight through from the beginning. gamescope asks for that memory through
Vulkan; NVIDIA's driver can answer with memory that is *scattered* in pieces,
and does not check. The display hardware reads straight on past the end of the
first piece — into whatever happens to live next door.

What you see is Steam's interface drawing perfectly, and then a staircase-shaped
band across the middle of the screen showing **part of some other program's
window**, with the colours wrong. Royce photographed it four times on 17
September 2026 on an RTX 5080. It is NVIDIA's own bug, number 5240452, they have
acknowledged it, and there is no fixed driver.

**Why GNOME and Plasma are fine.** They ask for that memory a different way
(through something called GBM), which the driver always makes contiguous. AMD
and Intel graphics are unaffected entirely; their drivers never hand out
scattered memory for this.

**What AquariusOS does about it.** Somebody has written the fix for gamescope's
side — it makes gamescope ask the same way GNOME does — and it works, including
on the newest NVIDIA cards. It is not in upstream gamescope yet and not in
Fedora's package. So:

| Image | gamescope |
| --- | --- |
| `aquarius-os` (AMD / Intel) | **Fedora's**, unchanged. Nothing to fix. |
| `aquarius-os-nvidia` | Fedora's, **plus** our own copy compiled with the fix, installed beside it as `/usr/bin/aquarius-gamescope`. Game Mode uses ours. |

Ours goes *beside* Fedora's, never on top of it, so the package database stays
honest and everything else that uses gamescope on that machine — per-game launch
options, for instance, where gamescope runs inside the desktop and this bug
cannot happen — still gets Fedora's.

The exact version we built is written into the image at
`/usr/share/aquarius/gaming/gamescope-build.txt`. Read it with `cat`.

**When this retires:** the moment the fix reaches upstream gamescope and Fedora
ships a version with it. Then `build_files/72-gamescope-build.sh`, the builder
stage in the `Containerfile` and section 6 of `build_files/71-game-mode.sh` all
go, and the NVIDIA image uses Fedora's gamescope like the other one. Nothing
else has to change.

---

## How the switch actually works

You do not need this to use the machine. It is here because the next person to
touch it will need it.

**The problem.** GDM — GNOME's login screen, and the only one AquariusOS ships —
has no idea what Game Mode is. Valve's own switching code is hard-wired to a
different login screen called SDDM, and AquariusOS will not move to SDDM:
under SDDM, GNOME has *no lock screen at all*. That is not an opinion, it is
visible in GNOME's own source — it only makes a lock screen if the GDM daemon
answers — and losing the lock screen to gain a games menu is the wrong trade.

**The answer** is the one Nobara found, which is the single distribution that
does this with GDM. Three moving parts:

1. **Which session starts next** is written into the account's own file,
   `/var/lib/AccountsService/users/<your name>`, as `Session=gnome`,
   `Session=plasma` or `Session=gamescope-session-steam`. GDM reads it.
2. **Getting back in without a password** uses GDM's *timed* login — "log this
   person in one second after the login screen appears". Not GDM's *automatic*
   login, which looks like the same thing and is not: automatic login fires once
   per boot and is then spent, so it would take you into Game Mode and do
   nothing on the way back.
3. **`systemctl reload gdm`** so GDM re-reads that. Reload, never restart —
   restarting the login screen kills every session on the machine at once and
   reliably ends in a black screen.

Steps 1 and 2 need administrator rights, so they go through one tiny program,
`/usr/libexec/aquarius-session-root`, behind polkit. **For the person sitting at
this screen, in the session that owns it, who is an administrator, it is allowed
with no password** — the only place on this computer where that is true, for the
controller reason above. For anybody else — over SSH, from a switched-away
session, from a non-administrator — it is a flat no with no prompt at all. The
program itself refuses any account that is not an ordinary person's account and
any session name that is not a session file this image really ships.

**And you can only do it to yourself.** "No password" for any administrator at
the screen would otherwise mean one administrator could point *another person's*
account at a session and switch on a login that needs no password for it — a way
into somebody else's account on a machine where they had a password precisely so
that could not happen. pkexec tells the helper who asked (`PKEXEC_UID`), and the
helper refuses any account that is not theirs. The only caller exempt from that
is the boot-time service, which runs as real root before anybody has logged in
and has no "asking person" at all. Changing the machine-wide boot setting
(`aq game boot on|off`) is not covered, because that is a setting about the
computer rather than about a person.

### The files, for the record

| File | What it does |
| --- | --- |
| `/usr/libexec/os-session-select` | The hinge. Steam's own `steamos-session-select` looks for exactly this path and hands over to it. Writes down where you are going. |
| `/usr/libexec/aquarius-session-root` | The root half: the `Session=` line, the timed login, the GDM reload, the boot setting. Behind polkit. |
| `/usr/libexec/aquarius-game-mode` | The "Return to Game Mode" button: warn, switch, log out. |
| `/usr/libexec/aquarius-login-mode` | Runs once per boot, before the login screen, and makes it match `/etc/aquarius/login-mode`. |
| `/usr/libexec/ogc/os-update` | Answers Steam's "check for an OS update" with "no". Always. AquariusOS updates itself in one piece, from the desktop. |
| `/usr/share/applications/aquarius-return-to-game-mode.desktop` | The icon in the app grid. |
| `/etc/aquarius/login-mode` | The cold-boot setting. Ships as `desktop`. |
| `aquarius-login-mode.service` | Runs the boot-time program. |
| `aquarius-game-tidy.service` | See "Log Out", below. |
| `aquarius-bluetooth-wake.service` | See "Bluetooth", below. |

Everything from Terra — the session itself, its Steam half, and Valve's handheld
service — is taken **completely unmodified**. Not one line is patched. Every
AquariusOS behaviour is added alongside, through hooks those packages already
provide. A forked session script is a fork we would maintain for ever, and the
first upstream fix we missed would be a bench day nobody could explain.

### Why "Log Out" still works

The automatic login stays switched on after a switch has finished. Left alone,
that would mean choosing **Log Out** from the desktop menu logged you straight
back in — Log Out would look broken for the rest of the day.

So it is taken back off twice: once at every boot (`aquarius-login-mode.service`,
on a machine set to `mode=desktop`) and once whenever a desktop session starts
(`aquarius-game-tidy.service`). If you ever see `aq game status` mention that the
automatic login is on, that is normal in the middle of a switch and it will clear
itself; nothing needs doing.

### Bluetooth, and what we know

On 17 September 2026, moving the screen away from the desktop and back again
killed Bluetooth on the bench machine about four seconds later — and with it the
K780 keyboard. Since the keyboard you would type the fix with is the keyboard
that just died, that had to be dealt with before Game Mode could ship.

**What the journal shows, exactly:** the kernel notes that no program is holding
the radio switch any more (which is a *consequence* of the desktop's own radio
service losing the screen, not a cause); three seconds later BlueZ tidies up as
the adapter stops; one second after that the keyboard's input device disappears.
The radio is **not blocked** — this is not somebody's airplane mode — so
something asked BlueZ over D-Bus to power the adapter down. **We do not yet know
what.** The obvious suspect, GNOME's radio service restoring a saved airplane
mode, does not fit: the setting that feature used no longer exists in this
version of GNOME.

**So what ships is a repair, not a cure,** and it is written to be honest about
that. `aquarius-bluetooth-wake.service` watches the first half-minute of each
desktop session and, if the radio is off while nothing has asked for it to be
off, switches it back on once. It never fights somebody who really did turn
Bluetooth off in Settings — that path *blocks* the radio, and a blocked radio is
left alone. On a healthy machine it does nothing and says so.

If the cause is ever found, delete `/usr/libexec/aquarius-bluetooth-wake`, its
service, and this section.

### The keyboard, while the screen is elsewhere

A session that is not in front of you is not allowed to read the keyboard. That
is a rule of Linux and a good one — a background session must not be able to
watch what you type in the one you are using.

Before 17 September 2026, `aquarius-keys` did not know that. When the screen
moved to Game Mode it found no keyboard, gave up, and was restarted two and a
half seconds later, for ever, inventing a fresh virtual keyboard each time
round. On the bench it had restarted **903 times**. It now asks the machine
whether its session owns the screen, and if it does not, it waits quietly and
says so once. The moment you come back, it carries on. See
[`aquarius-keys.md`](aquarius-keys.md).

---

## The bench list

*Everything below is on the machine after a `bootc upgrade`; nothing needs
installing first.*

### A. It changes nothing until you ask it to

- [ ] Cold boot. **The login screen appears exactly as before.** No automatic
      login, no Game Mode, nothing different. This is the check that matters
      most: if it fails, stop and read `/etc/aquarius/login-mode`.
- [ ] `aq game status` says Game Mode is installed and that this computer starts
      at the login screen.
- [ ] The login screen's session button (click your name, then the small button
      bottom-right of the password box) now lists **three** things: GNOME, KDE
      Plasma and **Steam Big Picture**.

### B. The switch, from GNOME

- [ ] Log into GNOME. Find **Return to Game Mode** in the app grid.
- [ ] Click it. **A warning appears** saying this closes your desktop. Press
      *Stay here* — nothing happens, the desktop is untouched.
- [ ] Click it again, press *Close my desktop and go*.
- [ ] The desktop closes and **Game Mode appears with no password asked**.
      📸 Photograph the screen: at the Ark's native mode, with **no band and no
      corruption**. This is the NVIDIA fix being proved.
- [ ] A controller drives it. Play a game for five minutes.
- [ ] Steam's power menu → **Switch to Desktop** → back in **GNOME**, no
      password. Resolve opens and sees the graphics card.
- [ ] Repeat the round trip **five times** with no freeze.

### C. The same from Plasma

- [ ] Log into KDE Plasma. Switch to Game Mode and back. **You land back in
      Plasma, not GNOME.** That is the "remember where you came from" half.

### D. The boot setting

- [ ] `aq game boot on`, restart → **straight into Game Mode**, no login screen.
- [ ] `aq game boot off`, restart → **the login screen**, as normal.
- [ ] While set to `on`: Ctrl+Alt+F3, `aq game boot off`, reboot — prove the
      escape hatch works before you need it.

### E. Nothing else broke

- [ ] The lock screen still works on GNOME and on Plasma. *(This is the whole
      reason we did not move to SDDM; if it has gone, something has changed the
      login screen.)*
- [ ] **Log Out** from the desktop menu really logs out — it does not log you
      straight back in. Test this *after* a Game Mode round trip, which is when
      it used to break.
- [ ] Suspend and resume, from both desktops.
- [ ] The Bluetooth keyboard survives a switch, and so does a controller.
- [ ] `aq keys status` works after a switch, and the journal does **not** show
      `aquarius-keys` restarting over and over
      (`journalctl --user -u aquarius-keys -b | tail -40`).
- [ ] `bootc upgrade` is still clean and nothing is layered (`rpm-ostree status`).

### F. Worth noting, not blocking

- [ ] HDR and VRR toggles in Steam's settings: write down what happens. Both are
      known to be unreliable on NVIDIA with gamescope and neither is a G1
      promise.
- [ ] Steam's "check for updates" in Game Mode: it should say the system is up
      to date and do nothing. AquariusOS is updated from the desktop.

Log what you find in `docs/design/bench-run-<date>.md`, the same as every other
bench session.
