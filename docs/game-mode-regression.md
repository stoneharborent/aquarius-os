# The day the handheld stopped starting in Game Mode

*Written 2026-08-30, the same day it broke and the same day it was fixed.*

Royce updated his ROG Xbox Ally to the AquariusOS build from commit `f7308cc` and
reported that the handheld **no longer starts in Steam's Game Mode**. It had done
so on the previous build.

This is the write-up: what actually happened, how we know, what changed, and what
is now in place so that it cannot happen again quietly.

**Short version.** We shipped a program whose job is to keep application icons off
the desktop. Bazzite's "Return to Gaming Mode" icon *is* an application icon. We
took it away. On a handheld with no keyboard and no mouse, that icon is the only
way home — so the Ally got stuck on the desktop, and stayed stuck across every
restart, which to its owner looks exactly like "it stopped booting into Game
Mode".

---

## How a handheld decides which mode to start in

Four pieces, all of them Bazzite's, none of them ours. Everything in this section
was read out of `ublue-os/bazzite` at commit `9339ca91` (2026-08-29) — the
revision the base image Royce is running was built from.

**1. A vendor default names the session.**
`/usr/lib/sddm/sddm.conf.d/holo.conf`, shipped in the image:

```ini
[General]
DisplayServer=wayland

[Autologin]
Relogin=true
Session=gamescope-session-ogui-steam.desktop
```

**2. A boot-time service writes the rest, every single boot.**
`bazzite-autologin.service` — a oneshot, `Before=display-manager.service`, with no
other ordering of any kind — runs `/usr/libexec/bazzite-autologin`, which writes
who to log in and which session to use into `/etc/sddm.conf.d/`.

**3. The mode is a file that either exists or does not.**

```bash
if [[ ! -f /etc/bazzite/desktop_autologin ]]; then
  SESSION="gamescope-session-ogui-steam.desktop"
elif [[ ${BASE_IMAGE_NAME} =~ "kinoite" ]]; then
  SESSION="plasma.desktop"
...
```

**4. And here is the part that makes this a trap.** The session file is only
written **if it is not already there**:

```bash
if [[ ! -f ${HOLO_CONF} ]]; then
  cat > ${HOLO_CONF} <<EOF
[Autologin]
Session=${SESSION}
EOF
fi
```

So once something else has written `/etc/sddm.conf.d/zz-holo-autologin.conf` —
and choosing "Switch to Desktop" in Steam does exactly that, through
`steamosctl switch-to-desktop-mode` — **rebooting does not undo it**. The machine
keeps landing on the desktop until something writes Game Mode back.

The one thing that writes it back, on screen, is a shortcut Bazzite puts on the
desktop and puts back if it goes missing:

```bash
# /usr/libexec/bazzite-user-setup
if [[ $IMAGE_NAME =~ "deck" ]]; then
  if [[ ! -f "$HOME/Desktop/Return.desktop" ]]; then
    cp "/etc/skel/Desktop/Return.desktop" "$HOME/Desktop/Return.desktop"
  else
    sed -i 's|Exec=.*|Exec=/usr/bin/return-to-gamemode|' "$HOME/Desktop/Return.desktop"
  fi
fi
```

And the file itself, from the `steamdeck-kde-presets` package (deck images only):

```ini
[Desktop Entry]
Name=Return to Gaming Mode
Exec=qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
Icon=gaming-return
Terminal=false
Type=Application
StartupNotify=false
```

`Type=Application`. Remember that line.

---

## What we shipped on 2026-08-30

Commit `f7308cc` added `/usr/libexec/aquarius-desktop-volumes`, a small per-user
program with two jobs: put every mounted drive on the desktop as an icon, and
keep the desktop clear of application icons. It was switched on for **every
account on the machine** with `systemctl --global enable`, deliberately, so that
it would reach installs that already existed rather than only new ones.

Its tidy-up rule, as written that morning, was one line long:

```python
if desktop_entry_type(path) != "Application":
    continue
```

Anything on the desktop that called itself an Application was moved into
`~/.local/share/aquarius/desktop-app-icons/`.

`Return.desktop` calls itself an Application.

So within a second or two of logging in, on a handheld, the icon that leads back
to Game Mode was filed away in a hidden folder — silently, because the program is
careful and never deletes anything, so there was nothing to notice.

---

## Why that reads as "it stopped booting into Game Mode"

Put the two halves together:

1. Desktop Mode is **sticky**: once chosen it survives restarts, because the file
   that names the session is only written when it is absent.
2. The **only on-screen way back** is an icon we removed.
3. The Ally has **no keyboard and no mouse** (that is problem #2 in the same
   report, and it is not a coincidence — it is what turns an annoyance into a
   dead end). There is no terminal to type `ujust set-default-game-mode` into,
   and nothing to click with.

From the owner's chair there is no difference between "my handheld is stuck in
Desktop Mode with the way home hidden" and "my handheld stopped starting in Game
Mode". It is the same experience.

### The honest part

This is the explanation the evidence supports, and it is the only mechanism in
the two commits that can touch Game Mode at all — but **it was reasoned out from
source, not read off the Ally's logs.** Nobody has seen this machine's journal.
There is a second possibility that cannot be ruled out from here, so both are
fixed:

* If instead the machine is showing a **login screen** (rather than logging
  straight into the desktop), then automatic login itself is not happening, which
  is a different fault with a different suspect — see the next section.

The checks Royce can run to tell the two apart are at the bottom of this page.

---

## The second mistake, fixed at the same time

The other new service, `aquarius-internal-automount.service`, was ordered
`Before=display-manager.service` — literally the same starting gate as
`bazzite-autologin.service`, the service that decides which session the machine
starts in. Ours is a oneshot that walks every disk in the machine, mounts what it
finds, and is allowed up to five minutes to do it.

Nothing about mounting a games drive is worth standing next to the machine's most
important boot decision. The line bought nothing, either: the desktop icons are
drawn by a program that watches for drives appearing and redraws within a second
of any mount, whenever that mount happens. It has been removed.

A hard `Requires=local-fs.target` went with it. `After=` is an order ("go
second"); `Requires=` is a demand ("and refuse to run at all if that failed"). We
only ever wanted the order.

---

## What ships now

| Change | File | What it does |
|---|---|---|
| Protected shortcuts | `usr/libexec/aquarius-desktop-volumes` | A shortcut that switches the machine between Game Mode and the desktop is not an app icon and is never moved. Matched three ways: by name (`Return.desktop`), by what its `Exec=` line runs (`return-to-gamemode`, `steamosctl`, `steamos-session-select`, `os-session-select`, `org.kde.Shutdown.logout`), and by a hand-written `X-Aquarius-Keep-On-Desktop=true` line. |
| **Repair, not just prevention** | same file | On every start, anything protected that a previous version already moved is walked back out of the holding folder and onto the desktop. Royce's Ally fixes itself on the update; he does not have to go looking. |
| Game Mode guard | `usr/lib/systemd/user/aquarius-desktop-volumes.service` | `ExecCondition=` asks the program "am I on a Plasma desktop?" before starting it. In Game Mode the unit is *skipped* — not failed, so nothing shows up red. |
| Out of the login path | `usr/lib/systemd/system/aquarius-internal-automount.service` | `Before=display-manager.service` and `Requires=local-fs.target` both removed. |
| Four build gates | `.github/workflows/drive-tests.yml` | The `ExecCondition` line must exist; `Before=display-manager.service` must not come back; `Return.desktop` must stay in the protected list; and no SDDM file of ours may ever set `Session=`, `User=` or an `[Autologin]` section. |
| Tests | `tests/test-aquarius-desktop-volumes.py` | 18 new checks covering all of the above, including that an *ordinary* app icon is still tidied away — so the protection cannot be quietly widened until the feature does nothing. |

### The rule this leaves behind

> **AquariusOS never has an opinion about which session the machine logs into.**
> Not in a config file, not in a service, and not by moving something on the
> desktop. That decision belongs to Bazzite's autologin, it is rewritten on every
> boot, and it is the whole reason the handheld image exists.

---

## What Royce must check on the Ally

None of this has been run on the hardware. In order:

1. **Update, then log in and look at the desktop.** The "Return to Gaming Mode"
   icon should be back on its own. Tap it — you should land in Game Mode.
2. **Restart.** It should come up in Game Mode by itself now.
3. If it does **not**, the second possibility above is the live one. Say which of
   these you see:
   * a **login screen asking for a password** → automatic login is not happening;
   * the **desktop, with no password asked** → the session is still set to
     desktop.
4. Either way, the two commands that answer it — from a terminal, or over SSH
   from the Mac:

```bash
# Which session is the machine set to log into?
cat /etc/sddm.conf.d/zz-holo-autologin.conf
cat /etc/sddm.conf.d/zz-bazzite-autologin.conf

# Did Bazzite's autologin service run, and what did it say?
systemctl status bazzite-autologin.service

# Force Game Mode back on from a terminal, any time:
ujust set-default-game-mode
```

---

## Sources

Every claim about Bazzite's behaviour above was read from the source, not from a
forum post. `ublue-os/bazzite` at `9339ca91` (2026-08-29):

* `system_files/deck/shared/usr/libexec/bazzite-autologin`
* `system_files/deck/shared/usr/lib/systemd/system/bazzite-autologin.service`
* `system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf`
* `system_files/deck/shared/usr/bin/return-to-gamemode`
* `system_files/deck/shared/usr/libexec/os-session-select`
* `system_files/desktop/shared/usr/libexec/bazzite-user-setup`
* `spec_files/steamdeck-kde-presets/steamdeck-kde-presets.spec`

And `Return.desktop` itself from Valve's `steamdeck-kde-presets`:
<https://gitlab.com/evlaV/steamdeck-kde-presets/-/blob/master/etc/skel/Desktop/Return.desktop>

**One thing checked and cleared:** the base image floats on `bazzite-deck:stable`,
so it was worth asking whether upstream broke this rather than us. Every commit to
`ublue-os/bazzite` between Royce's previous working build (`75cf7fe1`,
2026-08-25) and this one is either a CI change, a GNOME extension bump, or the
kernel moving from `7.2.0-ogc6` to `7.2.1-ogc2`. **Nothing upstream touched
autologin, the session files or the deck session in that window.** The kernel bump
is not nothing on hardware this new — `deck-variant-research.md` already lists four
open ROG Xbox Ally X regressions — but there is no session-related change to point
at, and pinning the tag stays the escape hatch if the Ally misbehaves in ways this
page does not explain.
