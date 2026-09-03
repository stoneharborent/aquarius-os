# The boot screen, and everything else that used to say Fedora

*Written 2026-09-03. Assumes you have never used Linux.*

---

## What this is about

Royce asked for one thing, in plain words: *change the boot logo to Aquarius,
make it say Aquarius on all boot images, and anything that still says Bazzite
should say Aquarius.*

Everything up to now had branded the parts of the machine you see **after** it
has started — the login screen, the desktop, the About page. This covers the
parts you see **before** that, which are the parts nobody thinks about until
they watch someone else turn the machine on.

There were four of them, and all four said something other than AquariusOS:

| What you see | What it said before | What it says now |
| --- | --- | --- |
| The boot menu, if you press a key | Fedora Linux 44 | **AquariusOS 44.\<date\>** |
| The screen while it starts up | Your computer maker's badge — ASUS, MSI, Dell — or a small grey spinning circle | **The Aquarius mark, the word AquariusOS, three blue dots** |
| The text banner over a text login | Fedora Linux 44 | **AquariusOS** |
| `cat /etc/system-release` in a terminal | Fedora release 44 | **AquariusOS release 44** |

---

## The boot screen (the important one)

### What you should see

A near-black screen — the `void` colour, `#06070C`, the same one the whole
design is built on. Just above the middle, the Aquarius mark with a soft blue
glow around it and the word **AquariusOS** underneath. Below that, three blue
dots with a pulse travelling left to right, so the screen is visibly alive
rather than frozen.

It is the same picture as step 02 of the "Boot to desktop · one journey" strip
in `branding/design-system/AquariusOS Core Identity.html`, with the word added
because Royce asked for the boot screen to say Aquarius.

### Where it lives

| Thing | Where |
| --- | --- |
| The picture in the middle | `system_files/usr/share/plymouth/themes/aquarius/watermark.png` |
| The 36 frames of dots | `system_files/usr/share/plymouth/themes/aquarius/throbber-0001.png` … `-0036.png` |
| The settings — colours, positions | `system_files/usr/share/plymouth/themes/aquarius/aquarius.plymouth` |
| The script that draws the pictures | `branding/render-plymouth-assets.sh` |
| The build step that installs it all | `build_files/80-boot-branding.sh` |

The program that draws the boot screen is called **Plymouth**, and a set of
pictures plus a settings file is called a **theme**. Ours is called `aquarius`.

### How to change the picture later

Three steps, on the Mac:

```bash
# 1. Change something. Either the mark itself…
#      branding/logo.svg
#    …or the sizes and colours at the top of the render script.

# 2. Re-draw the pictures.
bash branding/render-plymouth-assets.sh

# 3. Look at what it made, then commit it.
open system_files/usr/share/plymouth/themes/aquarius/watermark.png
git add system_files/usr/share/plymouth/themes/aquarius
git commit -m "Change the boot screen picture"
git push
```

GitHub rebuilds the OS, and the next `bootc upgrade` on the bench brings the new
picture down with it. You never have to touch the machine itself.

**Do not edit the PNG files by hand.** They are output. The next person to run
the render script would silently throw your edit away.

### Moving things around, without redrawing anything

The positions in `aquarius.plymouth` are **fractions of the screen**, not pixels.
`.5` is the middle, `0` is the top or left edge, `1` is the bottom or right. That
is what makes one file work on a handheld and on a 4K monitor.

```
WatermarkVerticalAlignment=.44     # the mark and the word — 44% down the screen
VerticalAlignment=.66              # the dots — 66% down
```

Colours in that file are written `0xRRGGBB` — the same six hex digits used
everywhere else in the project, with `0x` in front instead of `#`. Copy them out
of `branding/tokens.md`. Never pick one by eye.

---

## Why there is no computer-maker's badge any more

This is worth understanding, because it is the single setting that does it.

Modern computers leave a picture of their own logo sitting in memory when they
hand control to the operating system. It is called the **BGRT**, and Fedora's
default boot theme — which is literally named `bgrt` — exists to pick that
picture up and use it as the background. That is why a stock Fedora machine
shows an ASUS or Dell logo while it starts rather than showing Fedora's own.

Plymouth has a switch for it, and it is **per screen** rather than global — the
start-up screen, the shutdown screen and the update screen each have their own.
Our theme turns it off in every one of them:

```
[boot-up]
UseFirmwareBackground=false
```

Miss one of those sections and the badge comes back on that one screen only,
which is the kind of thing you find out about six weeks later. So the check in
`.github/workflows/build-next.yml` fails the build if the word `true` ever
appears next to that setting anywhere in the theme.

---

## ⚠️ The boot ramdisk — the part that makes this fragile

This is the one thing to understand from this whole document, because it is how
a change here can appear to do nothing at all.

### What it is

When a computer starts, it cannot read its own hard disk yet — it does not have
the drivers loaded. So it first loads a tiny, self-contained mini-system into
memory, whose only job is to find the real system and hand over to it. That
mini-system is one file, and its name is the **initramfs**:

```
/usr/lib/modules/<kernel version>/initramfs.img
```

**The boot screen lives inside that file.** A copy of the whole theme — the
pictures, the settings, the drawing plug-in — is baked into it, because the boot
screen has to appear long before the real disk is readable.

### Why that matters

Change the theme on disk and *not* rebuild that file, and the machine goes on
showing the old boot screen forever. Every file you can look at is perfect. The
build is green. Nothing warns you. This is the single most common way a custom
boot splash "silently doesn't work", and Universal Blue's own documentation calls
it out by name as the reason their `initramfs` module exists.

So `build_files/80-boot-branding.sh` rebuilds it, every build, with the same
command Universal Blue and Bazzite use:

```bash
dracut --force --no-hostonly --reproducible --kver "<version>" \
       --add ostree --add plymouth -v \
       /usr/lib/modules/<version>/initramfs.img
```

- `--kver` states the kernel version **explicitly**. Inside a build there is no
  running computer for the tool to ask, so left to itself it reads the version of
  the GitHub machine doing the building and produces something useless. Red Hat's
  own documentation makes the same point.
- `--no-hostonly` means "build one that works on any computer" rather than
  tailoring it to the machine doing the build.
- `--add ostree` is the part that knows how to start an image-based system. It is
  not optional. Leave it out and you get an image that installs perfectly and
  then stops at a black screen.

### ⚠️⚠️ Why this step runs LAST, and must keep running last

`build_files/60-nvidia.sh` sometimes **replaces this image's kernel.** It has to:
an NVIDIA driver only works with the exact kernel it was compiled against, and
`docs/restart/nvidia-notes.md` is the whole story.

A boot ramdisk is built for **one exact kernel version.**

So if the boot-branding step ran before the NVIDIA step, it would build a ramdisk
for a kernel that is then thrown away — and the NVIDIA image would have no usable
ramdisk at all. It would build, publish, and refuse to start.

That is why the step is numbered `80`, after `60`, and why the `Containerfile`
carries a warning above it. **Do not reorder those steps.**

### A bug this fixed on the way past

`60-nvidia.sh` has always written a setting that forces the NVIDIA driver into the
boot ramdisk, so the screen does not go black and come back during start-up.
Until this step existed, nothing ever rebuilt the ramdisk — so that setting was
written every build and never once acted on. Now it is.

### How to check it on a real machine

```bash
# Which theme is this machine set to?
plymouth-set-default-theme
# → aquarius

# Is it really inside the boot ramdisk?
sudo lsinitrd /usr/lib/modules/$(uname -r)/initramfs.img | grep plymouth/themes
# → should list usr/share/plymouth/themes/aquarius/…

# And what does the ramdisk's own copy of the setting say?
sudo lsinitrd -f /etc/plymouth/plymouthd.conf /usr/lib/modules/$(uname -r)/initramfs.img
# → Theme=aquarius
```

GitHub Actions runs all three of those on every build, inside the finished image,
and refuses to publish if any of them is wrong.

---

## The two words that make the boot screen appear at all

Plymouth starts on every boot, but it only draws the **graphical** screen if the
kernel is asked for one. Reading Plymouth's own source code
(`plymouth_should_show_default_splash` in `src/main.c`), either of two words does
it: `splash` or `rhgb`. And `quiet` is what stops kernel log messages scrolling
over the top of it.

We pass all three, in `/usr/lib/bootc/kargs.d/05-aquarius-boot.toml`:

```toml
kargs = ["quiet", "splash", "rhgb"]
```

`splash` is the modern name and `rhgb` is the older Red Hat one that some tooling
still looks for. Passing both is free. That folder is how an image ships kernel
options — a machine picks them up when it installs or updates from this image, so
nobody types anything.

---

## The boot menu

This one surprises people.

On an ordinary Linux computer, the boot menu text comes from a setting called
`GRUB_DISTRIBUTOR` in `/etc/default/grub`.

AquariusOS is not an ordinary Linux computer. On an image-based system the menu is
not generated from that file at all. Each entry is a small file under
`/boot/loader/entries/`, written fresh every time a new version of the OS is
installed, and the line you read is the `title` line inside it. **That title is
built from `PRETTY_NAME` in `/etc/os-release`** — which is what the
boot-loader specification recommends, and what the deployment tooling does.

`build_files/70-image-info.sh` already sets that to `AquariusOS`. So the menu
reads:

```
AquariusOS 44.20260903 (ostree:0)
AquariusOS 44.20260902 (ostree:1)      ← the rollback entry
```

We set `GRUB_DISTRIBUTOR="AquariusOS"` as well. It costs one line, it is the
first place somebody will go looking, and it is what would be used if the machine
were ever started through a path that does read it. But `PRETTY_NAME` is the real
control — if the menu ever says the wrong thing, that is the file to look at.

**How this was verified without booting a machine:** by reading the code path
rather than the screen. The specification says the title comes from
`PRETTY_NAME`; the build checks that `PRETTY_NAME` is `AquariusOS`, that
`GRUB_DISTRIBUTOR` is too, and prints which of the deployment programs on the
image name `PRETTY_NAME` internally. A real boot menu photograph is the bench's
job, and `bench-rebase.md` now asks for it.

---

## Everything else that got renamed

| File | What reads it | Now says |
| --- | --- | --- |
| `/etc/issue` | printed above the login prompt on a text console — the screen you land on if the desktop ever fails to start | `AquariusOS`, then the kernel version |
| `/etc/issue.net` | the same, for a login over the network | `AquariusOS` |
| `/etc/motd` | printed *after* logging in over ssh | **empty, on purpose.** A machine that greets you by name on every single connection gets old fast, and the name is already on the screen above the prompt |
| `/etc/fedora-release` | old programs that grew up reading a one-line description | `AquariusOS release 44` |
| `/etc/system-release`, `/etc/redhat-release` | the same | they are **links** to the file above, so they follow automatically |
| `/usr/share/plymouth/themes/spinner/watermark.png` | Fedora's own boot themes | our logo, so even if something switched the boot screen back to a Fedora theme, the logo on it would still be ours |
| `/usr/share/pixmaps/fedora-logo.png`, `fedora-gdm-logo.png`, `bootloader/bootlogo_*.png`, every `fedora-logo-icon.png` in the icon theme | programs that open a logo by its exact file path instead of looking it up by name | our mark |
| `gnome-tour`, `gnome-initial-setup` | would show a "Welcome to Fedora" screen on a new account | **removed if present**, and the build fails if either sneaks back in |

### The two files deliberately left alone in that list

`/usr/share/pixmaps/fedora_logo_med.png` and `fedora_whitelogo_med.png` are
**not** touched by the boot-branding step. They belong to `build_files/50-aquarius-desktop.sh`,
which puts a specific 279×80 picture there for GNOME's Settings → About page.
Overwriting them with a differently-shaped picture would quietly break that page.
The build checks, after the sweep, that they are still the About page's.

---

## What still says Fedora underneath, and why that is right

AquariusOS **is** Fedora 44 with our choices on top. Pretending otherwise in the
places a *program* reads breaks real things. Every one of these is deliberate,
none of them is visible to somebody using the machine, and each is written into
the audit in `.github/workflows/build-next.yml` with its reason:

| Still says Fedora | Why it must |
| --- | --- |
| `ID=fedora` in `/etc/os-release` | Hundreds of programs and install scripts branch on this to decide which package manager to use and which paths to look in. Change it and this machine becomes unrecognisable to all of them. |
| `VERSION_ID`, `VERSION`, `CPE_NAME` in the same file | The same reason. They describe what it is built on, which is a fact. |
| `/etc/system-release-cpe` | Not a sentence for a person — a machine-readable identifier (`cpe:/o:fedoraproject:fedora:44`) that security scanners use to work out which published vulnerabilities apply. This machine really is Fedora 44 underneath, so telling a scanner otherwise makes it check the wrong list. That is a security problem, not a branding one. |
| `/etc/yum.repos.d/*` | These really are Fedora's and RPM Fusion's servers. |
| Package names — `fedora-release`, `fedora-logos`, `fedora-gpg-keys` | They are Fedora's packages. Renaming a package does not rename anything a person sees, and removing `fedora-release` would break software installation outright. |
| `"base-image-name"` in `/usr/share/aquarius/image-info.json` | A factual record of what this image was built from. Useful when something goes wrong. |
| The **filenames** `fedora_logo_med.png` and `fedora_whitelogo_med.png` | The Settings → About page opens those exact paths, so the only way to brand that page is to put our picture at Fedora's filename. The bytes are ours; the name is not. |

Everything not on that list is checked, and the build fails if the word Fedora
turns up in it.

**The word Bazzite is allowed nowhere at all** — not in a file name, not in an
installed package, not in the text of any file the build can write to, comments
included. This branch is built from bare Fedora and has no relationship to
Bazzite, so any occurrence is a mistake by definition.

That rule is deliberately stricter than the Fedora one, and the first time the
check ran it found five real hits — all of them historical notes in the comments
of two GNOME settings files, along the lines of *"the old Bazzite line pinned all
three."* Those notes are useful and they were kept, but reworded to say *"the
line this replaced"*, because settings files are installed onto every machine and
the instruction was that a machine should not say Bazzite anywhere. This
repository's own documentation does not ship to anybody, so it still tells the
story by name — as this paragraph does.

---

## The installer USB stick

The ISO gets what it can:

```toml
[customizations.iso]
volume_id = "AQUARIUSOS"
application_id = "AquariusOS"
publisher = "Stone Harbor Entertainment"
```

`volume_id` is the name written onto the disc image. It is what shows up when the
stick is plugged into a Mac or a Windows machine, and the installer's own boot
menu is built from it too — so the first screen when booting the stick says
AQUARIUSOS rather than `Fedora-bootc-…`. (Only capital letters, digits, `-` and
`_` are allowed there. It is an old format with old rules.)

### What could NOT be rebranded, and what it would take

**The installer program's own pages still show Fedora's logo.** Once you are past
that first menu and Anaconda — the Fedora installer — is drawing its screens, the
header artwork and the sidebar logo are Fedora's.

The reason is a boundary, not an oversight. That artwork does not come from
AquariusOS. It lives inside the *installer's own* runtime, a separate mini-system
that the ISO builder assembles from Fedora's packages. Our image is the thing
being installed, not the thing doing the installing, so nothing we put in our
image can reach it. The build does replace those paths *inside our image*
(`/usr/share/anaconda/pixmaps/*`, if the installer software is present at all),
which covers a machine that runs the installer after it is already up — but not
the USB stick.

Changing it properly would mean building a replacement for Fedora's `fedora-logos`
package, with our pictures at Fedora's filenames, and getting the ISO builder to
install that package into the installer runtime. The ISO builder
(`bootc-image-builder`) has no setting for adding a package to that runtime — its
configuration covers the kickstart, which installer screens to show, and the disc
label, and stops there. So it would mean either building our own ISO a different
way, or waiting for the ISO builder to grow the option.

**The call:** not worth it now. It is a handful of screens, seen once, on the way
to a machine that then says AquariusOS everywhere for the rest of its life. Worth
revisiting if AquariusOS is ever handed to somebody who is not Royce.

---

## Where to go next

- **Moving the bench machine over, and what to look for on first boot:**
  [`bench-rebase.md`](bench-rebase.md)
- **Why the NVIDIA step is delicate, and why this one has to run after it:**
  [`nvidia-notes.md`](nvidia-notes.md)
- **How the whole build is put together:** [`README.md`](README.md)
- **The colours and fonts everything here uses:** `branding/tokens.md`
