# Aquarius Keys — Mac-style keyboard shortcuts

*Written 2026-09-03, for Phase R2's "Aquarius Keys" follow-up. Assumes you have
never used Linux.*

---

## The one-paragraph version

AquariusOS types like a Mac. **Copy is Command-C.** Quit is Command-Q. Search is
Command-Space. This is switched on out of the box, on every account, and one
command turns it off again:

```
aq keys windows
```

No other Linux operating system does this. It is one of the reasons to use
AquariusOS instead of Fedora with a nice wallpaper.

---

## Which key is Command?

On a PC keyboard, **the key immediately to the left of the space bar** — the one
printed `Alt`. That is Command now.

The key printed with the Windows logo becomes **Option**.

```
     Before        Ctrl  |  Win  |  Alt  |     SPACE     |  Alt  |  Win  | Ctrl
     After         Ctrl  | Option| Command|    SPACE     |Command| Option| Ctrl
     On a Mac      Ctrl  | Option| Command|    SPACE     |Command| Option
```

**Why the position and not the label.** Royce decided this on 3 September 2026,
and it is worth understanding, because the other answer is also defensible.
Muscle memory for Command lives in the thumb, not in the eye: a Mac user's left
thumb drops onto the key beside the space bar without looking. On a PC keyboard
that key is Alt. If we had made the *Windows* key Command — matching the label,
because both are the "Super" key underneath — every copy and paste would need a
conscious decision for the first month.

So the keys are swapped by position, and the printing on them is wrong. Royce's
bench keyboard is labelled for both Command and Alt, which is the easy case.

**Apple keyboards are detected and left completely alone.** If you plug in an
Apple keyboard — wired or Bluetooth — nothing is swapped, because Linux already
reads its Command key as Command and its Option key as Option. The detection is
by manufacturer number and by name, and it happens per keyboard, so an Apple
keyboard and a PC keyboard plugged into the same machine both behave correctly
at the same time.

---

## The fifteen you will actually use

| You press | It does | Notes |
| --- | --- | --- |
| **Command-C** | Copy | In a terminal this copies too — see below |
| **Command-V** | Paste | |
| **Command-X** | Cut | |
| **Command-Z** | Undo | Command-Shift-Z redoes |
| **Command-A** | Select all | |
| **Command-S** | Save | Command-Shift-S is Save As |
| **Command-F** | Find | Command-G finds the next one |
| **Command-W** | Close the tab | |
| **Command-Q** | Close the window | See "Command-Q is not quite Quit" |
| **Command-T** | New tab | Command-Shift-T reopens the one you closed |
| **Command-Space** | The Aquarius search palette | The Mac's Spotlight key, doing the Mac's Spotlight job |
| **Command-Tab** | Switch apps | |
| **Command-Left / Right** | Start / end of the line | Add Shift to select on the way |
| **Option-Left / Right** | One word at a time | "Option" is the Windows key now |
| **Command-Shift-3 / 4** | Screenshot / screenshot an area | Opens the normal screenshot window |

A few more that are there and worth knowing: Command-B, Command-I and Command-U
for bold, italic and underline; Command-plus, Command-minus and Command-0 for
zoom; Command-comma for an app's settings; Command-P to print; Command-R to
reload; Command-L to jump to a browser's address bar; Command-Backspace to
delete the word behind the cursor; Command-Up and Command-Down for the top and
bottom of a document.

The complete list, with a plain-English note on every single rule, is the file
itself: `system_files/usr/share/aquarius/keys/mac.yaml`.

---

## Switching it off, and back on

```
aq keys windows     the normal Linux and Windows shortcuts — Copy is Control-C
aq keys mac         back to Mac shortcuts
aq keys status      which one am I on, and is it actually working?
```

**It takes effect immediately.** You do not log out, you do not restart, you do
not close your apps. The next key you press uses the new rules.

The setting is **yours alone**. It is one line in a file in your own home
folder, `~/.config/aquarius/keys.conf`, so two people sharing the machine can
have different answers.

### Turning it off completely

`aq keys windows` already means nothing is remapped at all — there is genuinely
nothing between your keyboard and your computer in that mode. But if you want
the machinery gone as well:

```
systemctl --user mask --now aquarius-keys
```

and to bring it back:

```
systemctl --user unmask aquarius-keys
systemctl --user start aquarius-keys
```

`mask` rather than `disable` is deliberate, and the reason is in the next
section.

---

## Why terminals behave differently

In a terminal, **Control-C does not mean copy. It means stop.** It is how you
interrupt a program that is running away with itself, and it has meant that for
fifty years. Every rendering job, every long copy, every stuck command is ended
with Control-C.

So if Command-C simply became Control-C everywhere, then copying a line of
output in a terminal would kill whatever was running in it.

macOS solved this decades ago by keeping the two separate: Command-C copies,
Control-C interrupts. Linux terminals solved it differently, with Control-Shift-C
to copy. AquariusOS gives you the Mac's answer on top of the Linux one:

| In a terminal | What happens |
| --- | --- |
| **Command-C** | Copies the selected text |
| **Control-C** | Interrupts the running program, exactly as always |
| **Command-V** | Pastes |
| **Command-T / W / N** | New tab / close tab / new window |

**The physical Control key is never touched by any of this.** Not in terminals,
not anywhere. Nothing that was a Control shortcut before has been taken away —
the Mac shortcuts are added alongside.

The apps treated as terminals are listed by name in `mac.yaml`: Ptyxis (the one
AquariusOS ships), GNOME Console, Alacritty, foot, kitty, ghostty, Konsole,
GNOME Terminal and xterm.

### The piece this depends on

Knowing that the focused window *is* a terminal is the hard part, and each
desktop answers it differently:

- **In the Aquarius Session** the compositor is asked directly. It works.
- **On GNOME** nothing is allowed to ask — GNOME closed that door for everyone,
  for security reasons. The answer is a small GNOME add-on called "Xremap",
  which AquariusOS ships and switches on for your account automatically the
  first time you log in. You will see it in the Extensions app. **If you turn it
  off there, the terminal exception stops working**, and Command-C in a terminal
  becomes an interrupt.

---

## Files (the file manager) behaves differently too

Four shortcuts that mean something specific in a file manager:

| You press | It does |
| --- | --- |
| **Command-Backspace** | Move to the Bin |
| **Command-Down** | Open the selected item |
| **Command-Up** | Go up to the folder above |
| **Command-I** | Get Info (Linux calls it Properties) |

Everything else about Files — copy, paste, select all, new window — is the same
as everywhere.

---

## Command-Q is not quite Quit

On a Mac, Command-Q quits the whole application. On Linux there is no such
thing: an app is its windows.

So Command-Q sends **Alt-F4**, which is the "close this window" instruction the
window manager itself listens for. That works even in apps that have no Quit
shortcut of their own, which is why it was chosen over sending Control-Q. In
practice almost every Linux app quits when its last window closes, so the two
behave the same. An app with three windows open needs three Command-Qs.

---

## How to exclude an app

Some programs should be left alone entirely: professional apps where you already
have years of Control-key muscle memory, and games, which read the keyboard
directly and expect the keys the player configured.

Already excluded, out of the box:

- DaVinci Resolve
- Blender
- OBS Studio
- Steam, **and every game Steam launches**
- gamescope, Lutris, Heroic

To add one, edit the `not:` list in the block named *"The Mac shortcut set"* in
`system_files/usr/share/aquarius/keys/mac.yaml`, and rebuild the image. The list
is commented and it is meant to be edited.

To find out what an app calls itself, click on its window and then:

```
xremap-wlroots --list-windows        # in the Aquarius Session
```

On GNOME that command cannot work (the closed door again). There, watch the
service's log while you click between windows:

```
journalctl --user -u aquarius-keys -f
```

and temporarily remove `--no-window-logging` from
`/usr/libexec/aquarius-keys-run` so it prints the names.

---

## What this costs you

Written down honestly, because every one of these is a real trade:

- **Super-Left and Super-Right no longer tile a window.** GNOME uses those to
  snap a window to half the screen; we use them for start-of-line and
  end-of-line, which a Mac user reaches for far more often. Drag a window to the
  edge of the screen instead, or use the window menu.
- **Super-A no longer maximises a window** in the Aquarius Session, because
  Command-A has to be Select All.
- **The right-hand Alt key becomes a second Command key.** On a US layout that
  key does nothing anyway. On an international layout it is AltGr and it is how
  accented characters are typed — if you use one, delete the two lines marked in
  `mac.yaml`.
- **Anyone sitting at the machine can read every key typed on it.** That is what
  remapping keys *is*, and every tool that does this has the same property. See
  "How the permission works" below for why our version is the narrow one.

---

## Testing it on the bench

Royce's bench keyboard is labelled for both Command and Alt, so the physical key
is easy to find. Work down this list; it is the exit test for this piece of
work.

1. **Firefox** — Command-C and Command-V copy and paste. Command-T opens a tab,
   Command-W closes it, Command-L jumps to the address bar.
2. **Files** — Command-C on a file, Command-V in another folder. Command-Down
   opens a folder, Command-Up goes back. Command-Backspace moves to the Bin.
3. **Ptyxis (the terminal)** — the important one:
   - run something long, e.g. `sleep 300`
   - press **Control-C**. It must stop. If it does not, stop and read the
     "terminals behave differently" section above.
   - select some text, press **Command-C**, then **Command-V**. It must paste
     rather than interrupt.
4. **Command-Space** opens the search palette.
5. **Command-Tab** switches apps. **Command-`** switches between windows of the
   same app. (Both work on GNOME today. See the known gap below for the Aquarius
   Session.)
6. **Command-Q** closes the front window.
7. **Command-Shift-4** opens the screenshot tool with an area selection.
8. **Switch live**: `aq keys windows`, then immediately Control-C to copy in
   Firefox — no logging out. Then `aq keys mac` and check Command-C again.
9. **DaVinci Resolve** — its own shortcuts must be completely unaffected.
10. **`aq keys status`** — should say Mac, say it is running, and name the
    desktop.

If something does not work, the first thing to read is always:

```
journalctl --user -u aquarius-keys -b
```

It is written in sentences.

---

## Known gap in the Aquarius Session (labwc)

**On GNOME — which is what AquariusOS boots into today — everything above
works.** GNOME already listens for Super-Tab and Super-` and does exactly the
Mac thing with them.

labwc, the compositor behind the Aquarius Session, puts window switching on
Alt-Tab instead, so **Command-Tab and Command-` do nothing there yet.**

The fix is two lines in the `aquarius-shell` repository, which is not this one's
to edit. The proposal, for whoever picks it up:

```xml
<!-- in session/labwc/rc.xml, in the <keyboard> block -->
<keybind key="W-Tab">
  <action name="NextWindow" />
</keybind>
<keybind key="W-S-Tab">
  <action name="PreviousWindow" />
</keybind>
```

A second, smaller proposal for the same repository — this one AquariusOS already
works around, so it is a tidiness fix rather than a bug:

```bash
# in session/labwc/autostart, BEFORE the line that starts labwc-session.target
dbus-update-activation-environment --systemd --all
```

Without it, services that start with the graphical session — ours, and the
portals — do not inherit `WAYLAND_DISPLAY` or `XDG_CURRENT_DESKTOP` from the
session. `/usr/libexec/aquarius-keys-run` finds them itself rather than failing,
but every other session service has to solve the same problem on its own.

---

## How the permission works

To do its job the remapper has to read your keyboard directly and invent a
keyboard of its own. Linux normally reserves both for the administrator. Running
a program that sees every key you type as the administrator, forever, is exactly
the thing not to do — so AquariusOS grants the permission a narrower way.

The usual advice, including xremap's own, is to put your account in a group
called `input`. That works, and the permission is then **permanent**: that
account can read the keyboard whether it is logged in or not, from an SSH
connection, while the screen is locked.

AquariusOS uses **`uaccess`** instead — systemd's own mechanism for "give this to
whoever is physically logged in at this screen, right now". It is the same
mechanism that already hands you your webcam, your microphone and your graphics
card. The permission appears at login and **disappears at logout**, nobody is
added to any group, and an SSH connection never gets it at all.

The rule is one file: `/usr/lib/udev/rules.d/70-aquarius-input.rules`, and it is
commented at length.

**If it ever does not work** — the sign is `aq keys status` saying it is not
running, and the log saying it cannot write to `/dev/uinput` — the fallback is
the group, and the image is built so that it works with no other change:

```
sudo usermod -aG input $USER
```

then log out and back in.

---

## How the pieces fit together

| Piece | Where it lives | What it does |
| --- | --- | --- |
| The remapper | `/usr/bin/xremap-wlroots`, `/usr/bin/xremap-gnome` | Reads your keyboard, types the replacements. Two copies because no one program can ask both desktops which window is focused. |
| The rules | `/usr/share/aquarius/keys/mac.yaml`, `windows.yaml` | Which key becomes which. Read-only; edit in this repository and rebuild. |
| Your choice | `~/.config/aquarius/keys.conf` | One line: `mode=mac` or `mode=windows`. Missing means Mac. |
| The starter | `/usr/libexec/aquarius-keys-run` | Reads your choice, picks the right remapper for the desktop you logged into, starts it. |
| The service | `/usr/lib/systemd/user/aquarius-keys.service` | Starts the starter when you log in, stops it when you log out. |
| The switch | `/usr/bin/aq` | `aq keys mac|windows|status`. |
| The permission | `/usr/lib/udev/rules.d/70-aquarius-input.rules` | Lets it run as you instead of as the administrator. |
| The GNOME add-on | `/usr/share/gnome-shell/extensions/xremap@k0kubun.com` | Tells the remapper which app is focused, on GNOME only. |

It is built by `build_files/74-xremap-build.sh` (compiles the remapper in a
throwaway container) and `build_files/75-aquarius-keys.sh` (installs it and
checks the whole thing).

---

## Where the software comes from

**xremap**, by Takashi Kokubun. MIT licensed, written in Rust, and not packaged
by Fedora — so AquariusOS compiles it, at one pinned version, in a container
that is thrown away afterwards. Version and commit id are in the `Containerfile`
next to every other version this project pins.

**Toshy** is the project that proved this whole idea works on Linux, and its
behaviour is what these rules are modelled on — the keyboard detection, the
terminal exception, the shape of the shortcut table. It is licensed GPL-3, which
is incompatible with this repository's licence, so **not one line of it was
copied**. It was read the way you read a specification. Every rule here was
written from scratch.

---

## Still to come

- **A first-boot question.** Phase 3's welcome screen gets one more step: *"How
  should keyboard shortcuts work?"*, with Mac pre-selected and a live example
  underneath. Until then the default is Mac and this page is the switch.
- **A toggle in Quick Settings**, so it is a click rather than a command. That
  is work in the `aquarius-shell` repository.
- **Command-Tab in the Aquarius Session**, once the shell takes the two-line
  proposal above.
