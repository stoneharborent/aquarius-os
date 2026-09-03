# Moving the 4090 bench onto the new AquariusOS

*Step by step. Assumes no Linux experience. Nothing here erases your disk, and
every step is reversible.*

---

## What you are about to do

Your bench PC currently runs `aquarius-os-gnome-nvidia` — the Bazzite-based
image. You are going to point it at `aquarius-os-next-nvidia` — the new
Fedora-based one — reboot, and look at it.

**This is not an install and it does not erase anything.** Your files, your home
folder, your user account, your Wi-Fi passwords: all untouched. The operating
system on an image-based machine is a swappable layer sitting under your stuff,
and this swaps it.

**If you do not like it, one command puts it back.** The old system is kept on
the disk, whole, and the machine can boot into it again. That is the point of
building it this way.

Set aside about fifteen minutes. Most of that is downloading.

---

## Before you start

**Check the image exists.** Go to
<https://github.com/stoneharborent/aquarius-os/actions> and find the most recent
run of **Build AquariusOS (next)**. It must have a green tick. If it is still
running, or red, stop here — there is nothing to switch to yet.

**Check the package is public.** The first time a new image name is published,
GitHub keeps it private until somebody makes it public. It is a one-time click:

1. Go to <https://github.com/orgs/stoneharborent/packages>
2. Find `aquarius-os-next-nvidia`
3. Package settings → Danger Zone → **Change visibility** → Public

If you skip this, step 1 below fails with a message about authentication.

---

## Step 1 — Tell the machine to become the new one

Open the terminal on the bench PC and type this, exactly:

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-next-nvidia:latest
```

It will ask for your password. Then it downloads — several gigabytes, so give it
a few minutes. It will print a lot of lines about layers; that is normal.

When it finishes it will say something about the new deployment being staged.
**Nothing has changed yet.** The new system is written to the disk beside the
old one; neither is running.

### What `bootc switch` means

`bootc` is the tool that manages the operating system as a whole. `switch` means
"from now on, be this image instead, and get your updates from there". It is the
same mechanism as `bootc upgrade`, which is what has been quietly updating this
machine all along — it is just pointed somewhere new.

---

## Step 2 — Restart

```bash
sudo systemctl reboot
```

---

## Step 3 — What you should see

**At the boot menu.** There will be two entries. The top one is the new system;
the one below it is the old Bazzite AquariusOS, still there, still bootable. If
you do nothing, the top one starts.

**At the login screen.** The AquariusOS logo. Your username, as before.

**After logging in.** A light, ice-blue GNOME desktop:

- **The Pour** wallpaper, in its pale Ice colourway
- a **dock along the bottom**, in the middle, always visible, with six icons:
  Files, Firefox, Terminal, Text Editor, Software, Settings
- **Inter** as the interface font, **JetBrains Mono** in the terminal
- the accent colour on switches and selected text is blue

**Check it is really the new one.** Settings → System → About. It should say
**AquariusOS**, with the AquariusOS logo above it, and **NVIDIA Edition**
underneath.

Or in the terminal:

```bash
cat /etc/os-release
```

The first lines should say `NAME="AquariusOS"` and
`VARIANT="NVIDIA Edition"`, and `ID=fedora` further down. That last one is
deliberate — see the note at the top of `build_files/70-image-info.sh`.

### ⚠️ If the desktop comes up DARK

This is expected, it is not a bug, and it happened the first time too (31 August
2026).

Ice-light is the *default*, and a default only applies to a setting nobody has
ever touched. Your account has touched it — KDE wrote that setting into your
profile back when the bench ran Plasma, because KDE syncs its own light/dark
choice into GNOME's. Your old answer, quite correctly, beats our new default.

One command, once, for your account:

```bash
gsettings reset org.gnome.desktop.interface color-scheme
```

The desktop turns light immediately. A brand-new user account gets Ice-light
without doing anything.

---

## Step 4 — Have a proper look

Worth checking while you are in there, because these are the things R1 is
supposed to have got right:

- **Sound.** Play something. Settings → Sound should list your outputs.
- **Wi-Fi and Bluetooth.** (Wi-Fi on this machine has a *hardware* problem that
  predates all of this — the card does not appear on the PCI bus at all. That is
  the BIOS ladder on the bench list, not something an image can fix. Bluetooth
  works, which is the other half of the same module.)
- **A camera file.** Copy an MP4 off a card and double-click it. It should play,
  with sound. That is the whole codec layer working.
- **Right-click a video file** in Files. There should be a **Make Editor-Ready**
  item.
- **The graphics card.** In the terminal: `nvidia-smi`. It should print a table
  with your 4090 in it. If that command is not found, or errors, the driver did
  not load — see below.

---

## If you want to go back

```bash
sudo bootc rollback
sudo systemctl reboot
```

That is it. The machine boots the previous system — the Bazzite one — exactly as
it was. Nothing was lost, because nothing was overwritten.

You can also just pick the older entry at the boot menu without running anything,
if the desktop will not start.

### Going back permanently

`rollback` swaps which of the two is default. If you want to stop following the
new image entirely and go back to the old one for good:

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-gnome-nvidia:latest
sudo systemctl reboot
```

---

## What is deliberately not there yet

R1 is *"it boots and it's ours"*. It is genuinely bare compared to what the
Bazzite line had. None of the following is broken — none of it has been built on
this base yet:

| Not there | Coming in |
| --- | --- |
| **The Aquarius Desktop** — our own shell, on labwc | R2 |
| **The AquariusOS logo button** in the top-left of the top bar | R2 |
| **DaVinci Resolve** and its Rocky Linux container | R3 |
| **Aquarius Editor and Aquarius Writer** | R3 |
| **OBS, Blender, Kdenlive, Krita, Ardour** | R3 (installable from Software now) |
| **Steam, Proton, MangoHud** — gaming | R4 |
| **Printing** | not planned; one command if wanted |

The app store (Software) works and is connected to Flathub, so anything from
that list you want *today* can be installed from it by hand. It just is not
preinstalled or preconfigured yet.

---

## If something goes wrong

**The machine will not boot at all.** Pick the second entry at the boot menu.
That is the old system and it is untouched.

**Black screen after the login screen, on the NVIDIA machine.** This is the
classic driver-and-kernel mismatch. The build goes to considerable trouble to
make it impossible (see [`nvidia-notes.md`](nvidia-notes.md)), but if it happens:
reboot, pick the old entry, and say so — the useful information is what
`nvidia-smi` and `journalctl -b -1 -p err` print once you are back on a working
system.

**`bootc switch` says "unauthorized" or "manifest unknown".** The package is
still private. See "Before you start" above.

**Everything works but it looks wrong.** Screenshots are genuinely the fastest
way to sort that out — the look is the one thing CI cannot check.
