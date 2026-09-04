# Moving the 4090 bench onto the new AquariusOS

*Step by step. Assumes no Linux experience. Nothing here erases your disk, and
every step is reversible.*

> ### ⚠️ Every command in this document runs on the BENCH PC — never on the Mac
>
> `bootc` and `rpm-ostree` are Linux tools for managing a Linux machine's
> operating system. They do not exist on macOS. Typing one into a Mac terminal
> gets you `sudo: bootc: command not found`, which is the Mac correctly saying
> it has never heard of the tool — nothing is broken and nothing was changed.
> Sit down at the bench, or SSH into it, before you type anything below.

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

**The package should already be public** — confirmed 3 September 2026, so there
is nothing for you to do here. If Step 2 comes back saying *unauthorized* or
*manifest unknown*, it means the package went private: open
<https://github.com/orgs/stoneharborent/packages>, click `aquarius-os-next-nvidia`,
then **Package settings → Danger Zone → Change visibility → Public**, and run the
command again.

---

## Step 1 — Find out which tool this machine has

On the bench, open the terminal and type:

```bash
command -v bootc
```

- **It prints a path** (something like `/usr/bin/bootc`) → use **Step 2a**.
- **It prints nothing at all** → use **Step 2b**.

That is the whole test. Take the ten seconds; it saves guessing later.

### Why there are two commands

An image-based Linux machine can be managed by either of two tools, and both can
move this machine onto our image: `rpm-ostree` is the older one that every Fedora
Atomic system (including the Bazzite-based AquariusOS on the bench today) has
had for years, and `bootc` is the newer container-native replacement that our new
image uses. Most recent images ship both — you are just checking which one this
particular machine actually has before you type a command at it.

---

## Step 2 — Point the machine at the new image

### Step 2a — if `command -v bootc` printed a path

```bash
sudo bootc switch ghcr.io/stoneharborent/aquarius-os-next-nvidia:latest
```

### Step 2b — if it printed nothing

<!-- Migration path verified against rpm-ostree's own container docs
     (https://coreos.github.io/rpm-ostree/container/ — "rpm-ostree rebase
     ostree-unverified-registry:…") and bootc's upgrade/switch/rollback reference
     (https://bootc.dev/bootc/upgrades.html). -->

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/stoneharborent/aquarius-os-next-nvidia:latest
```

**Either way:** it will ask for your password, then download several gigabytes,
so give it a few minutes. It prints a lot of lines about layers; that is normal.

When it finishes it says the new deployment is staged. **Nothing has changed
yet.** The new system is written to the disk beside the old one; neither is
running until you reboot.

### What `ostree-unverified-registry:` means

It is a prefix telling the older tool two things: `registry` — this is a
container image on a registry (ghcr.io, GitHub's) — and `unverified` — for this
one download, skip the cryptographic signature check.

Skipping it is fine here, for this hop, because you are naming **our own image on
our own GitHub organisation**, and the download still happens over HTTPS, which
nobody can tamper with in transit. It is also a one-off: you type it once, to
cross from the old tool's world into the new one. From the next boot onward the
machine is managed by `bootc`, and signature checking is a `bootc`-side setting
configured in one place on the new system — every image is signed in CI with our
key (`cosign.pub` in this repo). You are not living with `unverified`; you are
passing through it.

### What `bootc switch` / `rpm-ostree rebase` mean

Both mean the same thing in plain words: *"from now on, be this image instead,
and get your updates from there."* It is the same machinery that has quietly been
updating this machine all along — just pointed somewhere new.

---

## Step 3 — Restart

```bash
sudo systemctl reboot
```

---

## Step 4 — What you should see

**At the boot menu.** There will be two entries, and both of them start with the
words **AquariusOS**. The top one is the new system; the one below it is the old
Bazzite-based AquariusOS, still there, still bootable. If you do nothing, the
top one starts.

**While it starts.** This is new since 3 September 2026. You should see the
**Aquarius mark on a near-black screen with the word AquariusOS under it, and
three blue dots pulsing left to right below that.** No Fedora logo, and — this
is the one to look for on a machine with a manufacturer's badge — no ASUS or MSI
or Dell logo either.

If instead you see a manufacturer's logo, or a small grey spinning circle, then
the boot splash did not take. That means the boot ramdisk was not rebuilt, and
[`boot-branding.md`](boot-branding.md) explains what that is and how to check it.

**At the login screen.** The AquariusOS logo. Your username, as before.

**After logging in.** A light, ice-blue GNOME desktop:

- **The Pour** wallpaper, in its pale Ice colourway
- a **dock along the bottom**, in the middle, always visible, with six icons:
  Files, Firefox, Terminal, Text Editor, Software, Settings
- **Inter** as the interface font, **JetBrains Mono** in the terminal
- the accent colour on switches and selected text is blue

**Check it is really the new one.** Settings → System → About. It should say
**AquariusOS**, with the AquariusOS logo above it, and **NVIDIA Edition**
underneath. For the terminal version of that check, see the next section.

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

## Optional: confirm the new image booted

Two commands, ten seconds, and you know for certain which system you are on.

```bash
cat /etc/os-release | head -3
```

**Expect** the first line to be `NAME="AquariusOS"`. Further down the same file
you should also see `VARIANT="NVIDIA Edition"` and `ID=fedora` — that last one is
deliberate, see the note at the top of `build_files/70-image-info.sh`.

```bash
bootc status
```

**Expect** it to print a block describing the *booted* image, and for that image
to be `ghcr.io/stoneharborent/aquarius-os-next-nvidia:latest`.

**What a wrong result looks like:**

| You see | What it means | What to do |
| --- | --- | --- |
| `NAME="Bazzite"` or `NAME="Fedora Linux"` | You are still on the old system | Reboot and pick the **top** entry at the boot menu |
| `bootc: command not found` | You are not on the new image at all (the new one always has `bootc`) — or you typed it on the Mac | Check you are on the bench, then reboot and take the top entry |
| `bootc status` shows `aquarius-os-gnome-nvidia` as booted | The switch was staged but you booted the old entry | Reboot, take the top entry |
| The image line says `aquarius-os-next-nvidia` but `NAME=` is wrong | Shouldn't happen — say so, that is a build bug | Send both outputs |

---

## Once you are on the new image

The new image ships `bootc`, so from here on it is one tool for everything. You
never need `rpm-ostree` again.

| What you want | Command |
| --- | --- |
| Get the latest AquariusOS | `sudo bootc upgrade` |
| Move to a different image | `sudo bootc switch ghcr.io/stoneharborent/<image-name>:latest` |
| Undo the last one of those | `sudo bootc rollback` |

Every one of them only *stages* the change — nothing happens until
`sudo systemctl reboot`.

---

## Step 5 — Have a proper look

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

**From the new image** — this is the normal case, and `bootc` is definitely
present once you have booted it:

```bash
sudo bootc rollback
sudo systemctl reboot
```

**If `bootc` is somehow not there** (which would mean you never got onto the new
image), the older tool does the same job:

```bash
sudo rpm-ostree rollback
sudo systemctl reboot
```

**If the desktop will not start at all**, you do not need any command: restart the
machine and pick the older entry at the boot menu by hand.

Any of the three boots the previous system — the Bazzite one — exactly as it was.
Nothing was lost, because nothing was overwritten.

### Going back permanently

`rollback` swaps which of the two is default. If you want to stop following the
new image entirely and go back to the old one for good, from the new image:

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

**`sudo: bootc: command not found` or `sudo: rpm-ostree: command not found`.**
Either you are typing on the Mac (see the warning at the top — these are Linux
tools), or you are on the bench and picked the wrong branch of Step 2. Run
`command -v bootc` again and follow what it tells you.

**The machine will not boot at all.** Pick the second entry at the boot menu.
That is the old system and it is untouched.

**Black screen after the login screen, on the NVIDIA machine.** This is the
classic driver-and-kernel mismatch. The build goes to considerable trouble to
make it impossible (see [`nvidia-notes.md`](nvidia-notes.md)), but if it happens:
reboot, pick the old entry, and say so — the useful information is what
`nvidia-smi` and `journalctl -b -1 -p err` print once you are back on a working
system.

**Step 2 says "unauthorized" or "manifest unknown".** The package went private.
See "Before you start" above — it is a one-time click on GitHub.

**The update refuses to run: "Deployment contains local rpm-ostree
modifications".** Something added a package on top of the operating system
image, and this machine only updates when nothing has. This is not a fault you
caused — on 2026-09-04 it was GNOME itself, which noticed the English language
pack was missing, offered in a notification to install it, and then layered it.
(That specific cause is fixed: `langpacks-en` is now baked into the image, so
GNOME has nothing to offer.)

Find out what was added:

```
rpm-ostree status -v | grep LayeredPackages
```

Then take it all off again and reboot:

```
sudo rpm-ostree reset
sudo systemctl reboot
```

`reset` removes every layered package and every local override, and puts the
machine back to the plain image. It does not touch your home folder, your
files, your Flatpaks or your Resolve container — none of those are part of the
operating system image. After the reboot, `sudo bootc upgrade` works again.

If you genuinely wanted the thing that was layered, say so rather than layering
it again: on this operating system the right answer is to add it to the image,
where it survives every update.

**Everything works but it looks wrong.** Screenshots are genuinely the fastest
way to sort that out — the look is the one thing CI cannot check.
