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

**From the app grid:** an icon called **Game Mode**.
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

Steam shows a "Switching to Desktop…" card while that happens. It should be
gone within a few seconds. If it is not — see "What went wrong on
2026-09-19" below, which is exactly that — press **Ctrl+Alt+F3** for a text
login and run `loginctl terminate-user <your name>`; the login screen comes
back and takes you to the desktop.

### The resolution

Game Mode starts at **your screen's own resolution** — the mode the screen
itself calls preferred. Steam's own default for a screen that is not a
handheld's is 1080p, which on a 4K screen is a blurry picture; AquariusOS
reads the preferred mode from the kernel and hands it to the session
(`/etc/gamescope-session-plus/sessions.d/steam`). Steam's per-game resolution
setting still works on top of that. To choose something else for the whole
session, put `SCREEN_WIDTH=` and `SCREEN_HEIGHT=` in a file under
`~/.config/environment.d/`.

### The button pictures

Steam draws its button hints for **whichever input it saw last**: keyboard and
mouse hints when you are on those, and a controller's own buttons — Xbox,
PlayStation, Nintendo — the moment that controller speaks. If you see
PlayStation buttons and did not pick up a PlayStation controller, one is
connected and Steam can hear it: a DualSense on a USB cable, or a paired one
that Bluetooth reconnected on its own (AquariusOS switches Bluetooth back on
after a session change, precisely so paired controllers come back). Steam's
**Settings → Controller** lists every controller it can see. There is no
setting in AquariusOS for this, because there is nothing to set: it is
Steam's own behaviour, and it is the right one.

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

⚠️ **There is one image where it ships the other way round.** The handheld
image, `aquarius-os-handheld`, ships `mode=game` — because that machine is a
ROG Xbox Ally X with no keyboard, and a password box on it is a dead end. Same
file, same two commands, opposite starting point. See
[`handheld.md`](handheld.md).

---

## Plugins inside Game Mode (Decky Loader)

Game Mode has a **"..."** button on the right of the screen — Steam's
quick-access menu. **Decky Loader** adds one more tab to it, with a plug on it,
and behind that tab is a shop of add-ons other people wrote: battery readouts,
per-game power profiles, screen recorders, frame generation.

It is **offered, not included**. Nothing of it is in the image; it arrives when
you ask, with **Decky Loader** in the app grid or `aq decky install`, and
`aq decky remove` takes it off again.

⚠️ **Decky only exists here, in Game Mode.** Steam in a window on your desktop
will never show the plug icon, and there is no setting that changes that. It
also runs as an administrator in the background, and listens only to this
computer. Both of those, and what to do when the icon is not there:
[`decky.md`](decky.md).

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
   person in one second after the login screen appears" — **together with**
   GDM's *automatic* login, for the same person. Both, every time, since
   2026-09-19. They are different things and both are needed:

   * the *timed* login is the one that fires on a login screen shown after a
     logout, which is what a switch is;
   * the *automatic* login is what GDM honours at boot (`aq game boot on`),
     because GDM builds the first login screen of a boot with timed login
     *disallowed* (`gdm-local-display-factory.c`);
   * and since **GDM 50**, the daemon **refuses the timed login unless the
     automatic-login keys are set for that same person**. Writing only the
     timed ones — Nobara's recipe, and ours until 2026-09-19 — gives you a
     password box that also flickers, because the login screen retries every
     couple of seconds. See "Bench 2" below for the journal line that says so.

   All five lines are written by one job, `switch-login on <you>`, and all five
   are taken off by `switch-login off`.
3. **`systemctl reload gdm`** so GDM re-reads that. Reload, never restart —
   restarting the login screen kills every session on the machine at once and
   reliably ends in a black screen. (A reload is a SIGHUP, and GDM's `main.c`
   answers it by re-reading `custom.conf`; that was checked, not assumed.)
4. **Ending the session you are in.** From the desktop, the button does it in
   the desktop's own language. From Game Mode, Steam's `steamos-session-select`
   *replaces itself* with our script (`exec`), so ending Game Mode is our job
   too: we ask Steam to close (`steam -shutdown`), and the session ends with
   it.

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
| `/usr/libexec/os-session-select` | The hinge. Steam's own `steamos-session-select` looks for exactly this path and hands over to it. Writes down where you are going, and — from Game Mode — ends the session. Everything it decides goes to the journal: `journalctl -t os-session-select`. |
| `/usr/libexec/aquarius-session-root` | The root half: the `Session=` line, the password-free login for a switch (`switch-login`, which writes the timed **and** automatic blocks), the automatic login on its own for a cold boot (`auto-login`), the GDM reload, the boot setting. Behind polkit. |
| `/etc/gamescope-session-plus/sessions.d/steam` | Starts Game Mode at the screen's preferred resolution. Read by Terra's session script through a hook it already has. |
| `/usr/libexec/aquarius-game-mode` | The "Game Mode" button: warn, switch, log out. |
| `/usr/libexec/aquarius-login-mode` | Runs once per boot, before the login screen, and makes it match `/etc/aquarius/login-mode`. |
| `/usr/libexec/ogc/os-update` | Answers Steam's "check for an OS update" with "no". Always. AquariusOS updates itself in one piece, from the desktop. |
| `/usr/share/applications/aquarius-game-mode.desktop` | The icon in the app grid. |
| `/usr/share/icons/hicolor/*/apps/aquarius-game-mode.png` | That icon's picture: Steam's own icon with a small controller badge in the corner (like SteamOS's "Return to Gaming Mode" arrow). Put together during the build by `build_files/aq-game-mode-icon.py` from the badge drawn in `branding/icons/game-mode-badge.svg`, because Steam's icon is Valve's and is not in this repository. |
| `/etc/aquarius/login-mode` | The cold-boot setting. Ships as `desktop`. |
| `aquarius-login-mode.service` | Runs the boot-time program. |
| `aquarius-game-tidy.service` | See "Log Out", below. |
| `aquarius-bluetooth-wake.service` | See "Bluetooth", below. |

Everything from Terra — the session itself, its Steam half, and Valve's handheld
service — is taken **completely unmodified**. Not one line is patched. Every
AquariusOS behaviour is added alongside, through hooks those packages already
provide. A forked session script is a fork we would maintain for ever, and the
first upstream fix we missed would be a bench day nobody could explain.

### Bench 1, 2026-09-19 — what went wrong the first time

The first real use of the switch, on the bench machine with the Samsung
Odyssey Ark, found four things. Each is fixed; each is written down here so
the next person does not rediscover it.

1. **"Switch to Desktop" hung on its card and the machine had to be
   rebooted.** Steam's script does `exec /usr/libexec/os-session-select
   desktop` — it replaces itself with ours and nothing runs afterwards. Ours
   wrote the two settings and stopped, believing Steam's script would end the
   session; Steam's script had already ceased to exist. Now `os-session-select`
   ends Game Mode itself on the way back, by asking Steam to close.
2. **Game Mode came up at 1080p on a 4K screen.** gamescope was never told a
   size, and Steam's console mode picks 1080p for any screen it does not
   recognise as a handheld's. The session now starts at the screen's own
   preferred mode, read from `/sys/class/drm`.
3. **The login screen asked for a password on the way in.** Not reproduced
   from the source: GDM's timed login is allowed on a post-logout login screen
   and the reload does re-read the file — both checked in GDM's code. What the
   code *did* do was print a warning to a terminal that was about to close if
   the timed login could not be switched on, and go ahead anyway. That is now
   a hard stop on the desktop side (nothing is closed, the reason is on screen
   and in the journal), and every decision the switch makes is in the journal.
   If it happens again, `aq game status` and `journalctl -t os-session-select
   -t aquarius-session-root -t polkitd` are the two things to paste into the
   report.
4. **PlayStation button hints with no controller in hand.** Not a fault in the
   switch — see "The button pictures" above. Worth checking whether a paired
   controller came back when Bluetooth was switched back on.

And one thing found in the source while looking, not on the bench: **`aq game
boot on` could never have worked**, because it wrote a *timed* login and GDM
disallows timed login on the first login screen of a boot. It now writes the
*automatic* one, which is what GDM honours there.

### Bench 2, 2026-09-19 — the password box that flickered, and a dead controller

The second bench run, on image `44.20260920` with GDM 50.3 on Fedora 44. The
switch out of the desktop worked — the desktop logged out properly, which is
bench 1's fix holding — and then three separate things went wrong. All three
are fixed; here is what each one was, in plain language, so that the next
person recognises it instead of rediscovering it.

#### Bug 1 — the login screen asked for a password, and the box kept going dead

**What it looked like.** Pressing the "Game Mode" launcher logged the desktop
out and landed on the login screen asking for a password. While Royce typed,
the password box went inactive for a moment, twice.

**What it was.** GDM 50 changed the rule. The login screen asks the GDM daemon
to begin the timed login, and the daemon now checks the **automatic**-login
settings before agreeing (`daemon/gdm-session.c`,
`gdm_session_handle_client_begin_auto_login`):

```c
gdm_settings_direct_get_boolean (GDM_KEY_AUTO_LOGIN_ENABLE, &enabled);
gdm_settings_direct_get_string  (GDM_KEY_AUTO_LOGIN_USER, &allowed);
if (!enabled || allowed == NULL || g_strcmp0 (allowed, username) != 0) {
        ... "Autologin not permitted for user %s"
```

AquariusOS wrote only the `TimedLogin*` lines — Nobara's recipe, which worked
on older GDM. So the countdown fired, the daemon said no, and the login screen
tried again about every two seconds. Every keypress restarted its timer, and
each time the timer fired the password box was disabled for a moment while the
refusal came back. That is the flicker. In the greeter's journal it is this
line, over and over:

```
gnome-shell[14056]: Exception in callback for signal: release: Gio.DBusError:
GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: Autologin not permitted
for user rorobeckley
```

Everything else in the mechanism was fine and was checked in GDM's source: the
reload really is a SIGHUP and really does re-read `custom.conf`
(`daemon/main.c`, `on_sighup_cb`), and timed login is allowed on an ordinary
login screen.

**The fix.** A switch now writes **all five lines** — the three `TimedLogin*`
ones and the two `AutomaticLogin*` ones — in one job, `switch-login on <you>`,
and takes all five off again with `switch-login off`. (That job used to be
called `timed-login`; the name stopped being true.)

**What you will actually see.** Two different things, both password-free, and
both correct:

* the **first** switch after a boot where you typed your password lands you
  straight in the new session with no login screen at all. GDM allows its
  direct automatic login once in the life of the running GDM, on any login
  screen on this seat — not only the first of a boot
  (`daemon/gdm-manager.c`, `get_automatic_login_details`);
* **after that** it is spent, so later switches show the login screen for
  about a second and it logs you in by itself. That is the timed login, which
  now works because the automatic keys are there beside it.

#### Bug 2 — the login screen was running the tidy service

**What it looked like.** Nothing, on screen. In the journal, twelve seconds
after every logout and four seconds after every boot:

```
systemd[13964]: Starting aquarius-game-tidy.service - Take the Game Mode
automatic login back off once the desktop is up...
pkexec[16481]: gdm-greeter: The value for the SHELL variable was not found in
the /etc/shells file [USER=root] [CWD=/run/gdm/home/gdm-greeter]
[COMMAND=/usr/libexec/aquarius-session-root switch-login off]
os-session-select[16456]: NOTE: could not switch the automatic login back off.
```

**What it was.** The tidy service — the one that makes **Log Out** mean Log Out
again after a switch — is meant for people, never for the login screen, and it
was kept out with `ConditionUser=!@system`. That line stopped working at GDM
50. GDM 50 no longer runs the login screen as an account called `gdm`: it runs
it as a systemd **dynamic user** named `gdm-greeter`, with a throwaway home
under `/run/gdm` and a user number handed out from the 61184–65519 range. That
is *above* the ordinary range, not below it, so "not a system account" does not
catch it.

It only ever failed because pkexec refuses an account whose shell is not in
`/etc/shells`. After bug 1's fix it would no longer have failed — and it would
have taken the password-free login off *in the middle of the switch that login
exists for*, putting the password box straight back.

**The fix.** Two belts. The unit gets a second `ConditionUser=!gdm-greeter`
(several of those lines are ANDed), and `os-session-select --tidy` refuses,
before doing anything, for a caller whose user number is outside 1000–59999,
whose `$HOME` is under `/run/gdm`, or whose desktop calls itself a Greeter.

**And the same hole in Aquarius Keys.** The keyboard remapper is kept out of
the login screen by the same `!@system` line, for the 2026-09-03 reason (two
remappers fighting over the keyboard, which looks exactly like "Mac mode
stopped working"). The bench journal shows it running at the GDM 50 login
screen again — `aquarius-keys: desktop is 'GNOME-Greeter:GNOME'` — so
`aquarius-keys.service` gets the same second line. This was never intentional:
the unit's own comments say the login screen must not run it.

#### Bug 3 — the controller was seen by Steam and did nothing

**What it looked like.** In Game Mode, the Razer Raiju V3 Pro was listed by
Steam, lit up, and completely dead. No error message anywhere.

**What it was.** A controller shows up as two things at once. The simple view
(`/dev/input/event*`) is buttons and sticks, and Linux hands it to whoever is
at the screen automatically — that part was fine, and it is why the pad looked
present. The raw view (`/dev/hidraw*`) is the real conversation with the pad's
chip, and Linux keeps it for root unless a rule says otherwise. Steam drives
this pad over the raw view. On the bench machine:

```
/dev/hidraw5   crw------- root root  HID_ID=0003:00001532:00001027  (no ACL)
/dev/hidraw10  crw------- root root  HID_ID=0003:00001532:00001027  (no ACL)
/dev/input/event20  TAGS=:uaccess:seat:  user:rorobeckley:rw-        (fine)
```

Steam's own log says the same story from its side: it fell back to the simple
view with a generic mapping, could not read the pad's serial number
("Controller has an Invalid or missing unit serial number"), and then
"Controller device closed after hid_read failure" at the exact second the
kernel logged the pad re-appearing with a different product id — 1026 became
1027, because the mode switch on the pad had been moved.

Valve's list (`steam-devices`, which the image installs) covers Razer 0401,
1000, 1004, 1007, 1008, 1009, 100A and 100b. Not 1026 or 1027. The community
`game-devices-udev` rules do not have them either, and no such package exists
in Fedora 44 or in Terra, so there was nothing to install.

**The fix.** AquariusOS now ships its own rule file,
`/usr/lib/udev/rules.d/70-aquarius-controllers.rules`, with both of the
Raiju's ids in both of the shapes a rule needs — the USB one and the Bluetooth
one — each tagged `uaccess`, which is how Linux says "this belongs to whoever
is logged in at this screen". That file's header explains what hidraw is and
how to add the next controller; `build_files/68-gaming.sh` reads every id back
out of the finished image and runs `udevadm verify` over the file, because
udev ignores a rule file it cannot parse and says nothing about it.

#### And one thing that was not a bug: Aquarius Keys in Game Mode

In Game Mode the keyboard remapper waited thirty seconds for "the desktop's
screen", gave up, started anyway with no Wayland connection, and took hold of
four keyboards — including the Raiju's own keyboard interface. It did **not**
touch the pad's gamepad interface, so it was not the cause of bug 3. But a
keyboard remapper has no business in Game Mode at all: there is no desktop
there to remap for. It now recognises a gamescope session, says so in one
line, and stops in the way that tells systemd not to start it again.

### Bench 3, 2026-09-20 — Switch to Desktop always landed in Plasma

The third bench run, on an image carrying the bench 2 fixes. **The good half
first: the machine cold-booted straight into Game Mode and it worked
perfectly** — no login screen, no password, Steam on the whole screen. That is
the G1 promise, and it held.

Then Royce pressed Steam's power button → **Switch to Desktop**. He had come
from GNOME, and his machine remembered that correctly. It logged him into
**KDE Plasma** anyway — and Plasma, on his dual-graphics PC, could not put a
picture on any screen at all. Both outputs of the RTX 5080 went black and the
only way out was to restart with the monitor plugged into the motherboard.

Those are **two separate problems**, and only the first one is ours to fix
here.

#### Bug 1 — `plasma` is SteamOS's word for "the desktop", not for Plasma

**What it looked like.** Switch to Desktop put you in Plasma whatever desktop
you had left. The "remember where you came from" feature looked as though it
had never been written.

**What it was.** Steam's power menu has exactly one button out of Game Mode.
It never asks which desktop you want. But the script behind it comes from
SteamOS, where the desktop is *always* KDE Plasma, so the word it hands down is
hard-coded: `plasma`. In SteamOS's vocabulary that word simply means "the
desktop". Here is the line from Royce's journal (boot `9541937c`), where our
own program says out loud what it was told and what it decided:

```
09:02:34 steam[12934]: os-session-select: asked for 'plasma' from 'Game Mode'; next session: plasma
```

`os-session-select` had a branch that said, in effect, "if Steam names a
desktop and that desktop exists on this computer, believe the name". On a
SteamOS machine that branch never fires, because only one desktop is
installed. On AquariusOS **both** desktops ship, so `plasma.desktop` always
exists — and the branch fired on every single switch, overwriting the
remembered `gnome` with `plasma`.

**The fix.** All five words Steam can pass — `desktop`, `plasma`,
`plasma-wayland-persistent`, `plasma-x11-persistent`, `gnome` — now mean the
same thing: *the desktop I came from*. The note in
`~/.local/state/aquarius/desktop-session` is the only thing that decides, and
GNOME is the fallback when there is nothing written down. The literal-name
branch is gone, and `build_files/71-game-mode.sh` now fails the build if
anything like it comes back, because it is exactly the sort of line a future
reader would add thinking it was an improvement. The long version is in the
header comment inside `os-session-select` itself, with that journal line
quoted, so the next person recognises the symptom instead of rediscovering it.

Nothing in AquariusOS asks `os-session-select` for a desktop by name — `aq
game` and the app-grid launcher only ever go the other way, into Game Mode —
so no flag was invented to replace it. If a by-name switch is ever wanted, it
gets a spelling Steam cannot produce (`--to gnome`), never a bare word.

#### Bug 2 — Plasma itself lit no screen on this PC. OPEN, not fixed here.

Once he landed in Plasma, Plasma failed. This is a **Plasma-on-this-machine**
problem and it has nothing to do with Game Mode; it would have happened just
as much if he had chosen Plasma at the login screen. It is written down here
because it is what turned bug 1 from "wrong desktop" into "black monitor and a
hard restart".

The bench PC has two graphics chips: an **NVIDIA RTX 5080** with the monitor
on it, and the **AMD graphics built into the processor**. KWin — Plasma's
window manager — tried to drive the AMD one and was refused by the kernel:

```
09:02:41 kernel: amdgpu 0000:71:00.0: [drm] *ERROR* Unsupported screen format RA24 little-endian (0x34324152)
09:02:41 kwin_wayland[18846]: Atomic modeset commit failed! Invalid argument
```

In plain language: KWin asked for a picture in a pixel format that this AMD
chip does not accept, the kernel said no, and KWin then had no working screen
to put anything on — so both of the 5080's outputs stayed dark too.

**This is an open item for the Plasma bench, not for Game Mode.** Nobody
should try to fix it from the Game Mode side. When Plasma gets its own bench
session, the things to try are: whether Plasma behaves with the iGPU switched
off in the firmware, whether it behaves with only one monitor cable, and what
`KWIN_DRM_DEVICES` pinned to the NVIDIA card does. Until then, GNOME is the
desktop that is known to work on this machine, and it is also what a cold
Game Mode boot now returns to.

### Why "Log Out" still works

The automatic login stays switched on after a switch has finished. Left alone,
that would mean choosing **Log Out** from the desktop menu logged you straight
back in — Log Out would look broken for the rest of the day.

So it is taken back off twice: once at every boot (`aquarius-login-mode.service`,
on a machine set to `mode=desktop`) and once whenever a desktop session starts
(`aquarius-game-tidy.service` — for people's accounts only; the login screen is
itself a GNOME Shell, run since GDM 50 by a throwaway account called
`gdm-greeter`, and it is kept out twice over — see Bench 2, bug 2). If you ever see `aq game status` mention that the
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

- [ ] Log into GNOME. Find **Game Mode** in the app grid.
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

### B2. The way back, from Game Mode (added 2026-09-19)

- [ ] Steam's power menu → **Switch to Desktop**: the "Switching to Desktop…"
      card is gone within ten seconds and the desktop you came from is back,
      with no password box.
- [ ] `journalctl -t os-session-select` shows "asked for 'desktop' from 'Game
      Mode'" and "asking Steam to close".
- [ ] On the Ark, Game Mode's picture is sharp: Steam's **Settings → Display**
      shows 3840x2160, and the journal for the session
      (`journalctl --user -u gamescope-session-plus@steam`) says "Game Mode
      will run at the screen's own 3840x2160".
- [ ] With no controller in hand, Steam's button hints are keyboard and mouse.
      If they are not, **Settings → Controller** names the controller Steam is
      hearing.

### B3. No password, no greeter service, a live controller (added 2026-09-19)

*After `bootc upgrade` and a restart. The restart matters: the boot-time
program has to run once with the new code before the rest of this is honest.*

**The switch, twice each way, with no password**

- [ ] Press **Game Mode** in the app grid. You arrive in Steam without typing
      anything. (The first switch after a boot may skip the login screen
      entirely; that is the automatic login, and it is correct.)
- [ ] Steam's power menu → **Switch to Desktop**. You arrive back in the
      desktop you came from, without typing anything.
- [ ] Do both again, straight away. The second round trip is the one that used
      to ask: this time the login screen appears for about a second and logs
      you in by itself.
- [ ] At no point does the password box appear and go grey, appear and go
      grey. If it ever does again, `journalctl -b -u gdm` at the login screen
      is where "Autologin not permitted for user" would be.

**Log Out still means Log Out**

- [ ] From the desktop, choose **Log Out**. The login screen appears and asks
      who you are — it does NOT log you straight back in.
- [ ] Restart the machine. The login screen asks who you are. (Both of these
      prove the password-free login really was taken off again.)

**The login screen is not running our services**

- [ ] `journalctl -b | grep gdm-greeter` mentions **no** pkexec line about
      `aquarius-session-root`, and no `aquarius-game-tidy`.
- [ ] `journalctl -b -t aquarius-keys | grep Greeter` is empty — the remapper
      no longer starts at the login screen.

**The Raiju, in both of its modes**

- [ ] Plug the Raiju in **with its cable**, in Game Mode. Steam's
      **Settings → Controller** lists it, and it actually moves the Steam
      interface — sticks, buttons, the lot.
- [ ] Move it to its **wireless dongle**. It works there too, without
      unplugging anything else or restarting Steam.
- [ ] From a terminal, with the pad connected:
      `ls -l /dev/hidraw*` shows its file, and
      `getfacl /dev/hidrawN` names you with `rw-`. (Root-only means the rule
      did not fire; `udevadm info /dev/hidrawN` prints the ids to check
      against `/usr/lib/udev/rules.d/70-aquarius-controllers.rules`.)
- [ ] Play something with it for a few minutes. The pad does not go dead when
      it re-connects.

**The status command**

- [ ] `aq game status` prints, under "What the login screen has been told",
      both "timed login lines" and "automatic login lines" — **both empty**
      once you are settled in the desktop, and both filled in during a switch.
- [ ] Its wording no longer suggests the timed login alone is what a switch
      uses.

### B4. Switch to Desktop goes back where you came from (added 2026-09-20)

*This is the bench 3 fix. It needs both desktops, so do it in two halves.*

**From GNOME**

- [ ] Log into **GNOME**. Press **Game Mode** in the app grid and let it take
      you to Steam.
- [ ] Steam's power menu → **Switch to Desktop**. You land back in **GNOME**.
      (Before the fix this always landed in Plasma.)

**From Plasma**

- [ ] Log into **KDE Plasma**. Switch to Game Mode and back the same way. You
      land back in **Plasma**.
- [ ] ⚠️ If Plasma gives you a black screen rather than a desktop, that is the
      *other* bench 3 finding and it is not this fix failing — see Bench 3,
      bug 2. Check where you actually landed with the next item instead of
      judging by what you can see.

**What the machine thinks it remembers**

- [ ] `aq game status` prints a line reading `desktop to come back to:` and it
      names the desktop you last used — `gnome` or `plasma`. That single line
      is the whole feature; if it is right and you still land somewhere else,
      the bug is back.
- [ ] `journalctl -t os-session-select -b` shows the switch's own sentence,
      e.g. `asked for 'plasma' from 'Game Mode'; next session: gnome`. **The
      word after `next session:` is the one that matters** — it should match
      the desktop you came from, *not* the word Steam asked for.

**The controller, and a dongle that is not a controller**

- [ ] With the Raiju's **2.4 GHz dongle plugged in but the pad switched off**,
      Steam lists no controller. **That is correct, not a fault.** The dongle
      on its own (USB id `1532:1027`) announces itself to Linux as a keyboard,
      a mouse and a touchpad — it has no gamepad part at all until a pad is
      powered on and paired to it. There is nothing for Steam to list.
- [ ] Switch the **pad** on and pair it to the dongle. Now Steam lists it and
      it drives the Steam interface.
- [ ] Plug the pad in **with its cable** instead (id `1532:1026`): Linux calls
      it a `USB HID Gamepad` and Steam drives it there too.

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
