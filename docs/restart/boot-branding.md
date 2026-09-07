# The boot screen, and everything else that used to say Fedora

*Written 2026-09-03. The boot-screen section was rewritten on 2026-09-06, when
the still logo became an animation. Assumes you have never used Linux.*

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
| The screen while it starts up | Your computer maker's badge — ASUS, MSI, Dell — or a small grey spinning circle | **The Aquarius mark being poured out of falling water, and the word AquariusOS** |
| The screen while it shuts down | The same badge again | **The mark being taken apart and blown away by the wind** |
| The text banner over a text login | Fedora Linux 44 | **AquariusOS** |
| `cat /etc/system-release` in a terminal | Fedora release 44 | **AquariusOS release 44** |

---

## The boot animation (the important one)

*Rewritten 2026-09-06, when the boot screen stopped being a picture and became
an animation.*

### What you should see

**Starting up — the pour.** A deep-ocean navy screen: Midnight's `bg`,
`#0B1220`, the same colour the desktop uses in dark mode, so the machine does
not change colour between the boot screen and the desktop.

Then, over 2.2 seconds:

1. A thin stream of water falls from above the screen into a point in the middle.
2. Out of that point, both legs of the letter **A** run downward, like water in
   two channels.
3. The wave that crosses the A spills out from left to right.
4. The word **AquariusOS** fades in underneath.

Then it **holds** — stands perfectly still — until the login screen takes over.

AquariusOS is named after Aquarius, the water-bearer. That is the whole idea: the
mark is not drawn, it is **poured**.

**Shutting down or restarting — the wind.** The opposite, over 1.9 seconds. The
word fades out first. Then the wind takes the mark apart — the left leg wears
away from its foot upward, the right leg from the point downward, the wave last
— and each stroke breaks into drops that stream off to the right and fade. Then
the screen is dark.

**Installing updates.** The pour and the hold as usual, and underneath it: what
is being installed, "Please do not turn the computer off.", a thin progress bar
and a percentage. When it reaches the end the line changes to "Turning off." and
the wind plays.

**Unlocking an encrypted disk.** The pour, then "Unlock the disk", a box to type
into with one dot per character, and "Type the disk password to start."
underneath. A wrong password shakes the box once and says so in plain words.

(Until 2026-09-06 all of this was one still picture of the mark with three
pulsing dots under it, and the ground was near-black `#06070C` from the retired
Starlight palette. `branding/tokens.md` is the record of what replaced the
colour; the rest of this section is the record of what replaced the picture.)

---

### ⚠️ The reversal: this used to be a `two-step` theme, deliberately

This is worth reading before changing anything here, because the *old* choice
was argued for at length and it was not wrong.

Plymouth — the program that draws the boot screen — draws a theme using one of
several **plug-ins**. Until this rewrite, ours named `two-step`, and the reasons
were good ones:

- `two-step` is the plug-in **Fedora's own default themes use** (`bgrt`, which a
  stock Fedora machine boots with, and `spinner`). So it is the code path that
  Fedora, Red Hat and Universal Blue test on every graphics card there is, on
  every release. That matters most on NVIDIA, where the boot splash is
  historically the first thing to break.
- It already knew how to draw the screens a boot screen occasionally has to draw
  and that are easy to forget: **the disk-password box**, the shutdown screen,
  the "installing updates" screen. Those came free, and they were correct.
- The cost was that `two-step` can only play a fixed loop of pictures in one
  place. It cannot play something **once and then stop**, and it cannot tell
  starting up from shutting down.

**What changed.** On 2026-09-06 Royce approved a designed boot *animation*
rather than a still logo — and, in as many words: **a story needs a sequence.**
The pour has to play once, in order, and then hold. The wind has to be a
different story from the pour. `two-step` cannot do either of those things, with
any pictures and any settings. Only Plymouth's `script` plug-in can.

**So the trade was taken, with eyes open:**

| | |
| --- | --- |
| **What we gave up** | The screens that used to come free now have to be drawn by hand. The one that matters is the **disk-password box** — the piece nobody would notice was missing until the day somebody turned on disk encryption and the machine appeared to hang at a blank screen. It is written, it is in `aquarius.script`, and it is on the bench-test list below precisely because a build cannot prove it. |
| **What we kept** | **The update screen was kept, not dropped** — because we now draw it ourselves, with the same headings and the same "Please do not turn the computer off." the old theme carried. |
| **What we gained** | The pour, the hold, the wind — a boot screen that is our own design rather than Fedora's design in our colours. |
| **The risk we accept** | `script` is a less-travelled code path than `two-step`. It is not exotic — it ships in Fedora as `plymouth-plugin-script`, it is what most custom boot themes in the world use, and Plymouth's own example theme is written for it — but it is not what Fedora's default theme exercises. **If a machine ever shows a black screen where the animation should be, this is the first thing to suspect.** See "If it ever goes wrong" at the end of this section. |

---

### Where it lives

| Thing | Where |
| --- | --- |
| **The animation itself**, written down as arithmetic | `branding/pour.mjs` |
| The script that turns that into picture files | `branding/render-plymouth-assets.sh` |
| The tool that reads the colours back out of a picture | `branding/png-colours.py` |
| The 66 frames of the pour | `system_files/usr/share/plymouth/themes/aquarius/boot-0001.png` … `-0066.png` |
| What holds on screen afterwards | `…/themes/aquarius/hold.png` |
| The 57 frames of the wind | `…/themes/aquarius/shutdown-0001.png` … `-0057.png` |
| The update and password screens' furniture | `…/themes/aquarius/box.png`, `bullet.png`, `bar-track.png`, `bar-fill.png` |
| **What the boot screen DOES** — the little program that plays it all | `…/themes/aquarius/aquarius.script` |
| The three lines naming the plug-in and pointing at the two above | `…/themes/aquarius/aquarius.plymouth` |
| The build step that installs and checks it | `build_files/80-boot-branding.sh` |

A set of pictures plus a settings file is called a **theme**. Ours is called
`aquarius`.

**Which file do I want?**

- To change what the animation **looks like** — the shapes, the timing, the
  colours of the mark — that is `branding/pour.mjs`, and then you re-render.
- To change what the boot screen **does** — the words on the update screen, where
  things sit, how the password box behaves — that is `aquarius.script`, and
  nothing needs re-rendering.

---

### How to change the animation, and re-draw the frames

Once, ever, on the Mac (it downloads the one small library that reads the Sora
font file):

```bash
npm --prefix branding/icons install
```

Then, every time:

```bash
# 1. Change the animation. That is branding/pour.mjs — read its header first;
#    it explains what happens at each moment of the pour and of the wind.

# 2. Re-draw all 124 pictures. About four minutes. It checks its own work.
bash branding/render-plymouth-assets.sh

# 3. Look at a few of them, then commit.
open system_files/usr/share/plymouth/themes/aquarius/boot-0033.png
git add system_files/usr/share/plymouth/themes/aquarius
git commit -m "Change the boot animation"
git push
```

GitHub rebuilds the OS, and the next update on the bench brings the new
animation down with it — `sudo bootc upgrade` once the bench is on the new image
(see [`bench-rebase.md`](bench-rebase.md) for getting it there). You never have
to touch the machine itself.

**To watch the animation before committing:** open
`system_files/usr/share/plymouth/themes/aquarius/` in Finder, select
`boot-0001.png`, press space to open Preview, and hold the down arrow. It plays.

**Do not edit the PNG files by hand.** They are output. The next person to run
the render script would silently throw your edit away.

**What the render script proves before it lets you commit:** every frame is
present, numbered with no gaps and 288×389; `hold.png` is byte-for-byte the
pour's last frame (a hold that differs by one pixel is a visible flicker at the
moment the animation stops); the four small shapes are their exact sizes; and —
by opening the pictures and reading the actual pixels — that no retired colour
appears in any of the 124 frames and that the progress bar really is the Aquarius
blue rather than something close to it.

---

### Moving things around, without redrawing anything

Everything about *where things sit* is in `aquarius.script`, near the top, under
"**WORKING OUT WHERE THINGS GO**". Positions are worked out from the size of the
screen rather than typed in as pixels, so one file is right on a small laptop
panel and on the 4K monitor:

```
mark.y = Window.GetY() + Window.GetHeight() * 0.44 - FRAME_HEIGHT / 2;
```

`0.44` is 44% of the way down the screen — the same 44% the old boot screen used,
so the mark does not appear to jump between the two. Everything else hangs off
the **bottom of the mark** rather than off the screen, so nothing can ever land
on top of the logo however tall or short the screen is.

Colours there are written as their three 0-to-255 parts, put through a helper
called `channel`:

```
#   bg        #0B1220 = 11, 18, 32
BG_RED = channel(11);   BG_GREEN = channel(18);   BG_BLUE = channel(32);
```

Copy the numbers out of `branding/tokens.md`. Never pick one by eye.

---

### Why there is only one set of pictures, and not a bigger set for 4K

Plymouth draws a theme's pictures at their own pixel size — it does not scale
them up for a big screen or down for a small one. It *does* know about
high-density screens in general, so the question of whether we owed it a second
set of pictures at twice the size was a real one.

It was answered by reading the source of **the exact Plymouth this image ships,
24.004.60**, rather than assumed. Two answers, both no:

- The `script` plug-in never touches "device scale" at all — the words do not
  appear anywhere in its source.
- There would be no way to hand it two sets even if we wanted to. A picture is
  loaded by file name and drawn; there is no "and use this one on a dense
  screen" anywhere in the interface it offers.

So: one set, at 288×389, which reads as a confident centred mark on a 1280-wide
laptop panel and a modest one on the 4K monitor. The reasoning is written into
`branding/render-plymouth-assets.sh` too, so nobody has to find this document.

---

### ⚠️ If it ever goes wrong: how to get a boot screen back in one line

If the bench ever boots to a black screen where the animation should be, the
first thing to suspect is the `script` plug-in on that particular graphics card.
From a text console (`Ctrl+Alt+F3`) or over ssh:

```bash
sudo plymouth-set-default-theme spinner
sudo dracut --force --no-hostonly --kver "$(uname -r)" \
     /usr/lib/modules/$(uname -r)/initramfs.img
sudo reboot
```

That puts Fedora's own plain boot screen back. If the machine then boots
normally, the animation is the problem and it is worth saying so in the repo. If
it still black-screens, the boot screen was never the problem and the fault is
somewhere else entirely.

To go back: `sudo plymouth-set-default-theme aquarius` and rebuild the ramdisk
the same way — or just `sudo bootc upgrade`, which reinstalls the whole image
including its own ramdisk.

---

### How to prove the script is even valid, without a Linux machine

`aquarius.script` is written in Plymouth's own little language, and a syntax
error in it means one thing on a real machine: **a black boot screen.** Nothing
in the build can catch that, because parsing only happens when Plymouth actually
starts drawing, and nothing in a container has a screen.

So it was checked a different way, on the Mac, and this recipe is repeatable
whenever the script changes in a big way. It builds **Plymouth's own parser** —
the real one, from the version this image ships — as a small command that reads a
script file and says whether it is valid:

```bash
cd /tmp
curl -sL -o plymouth.tar.gz   https://gitlab.freedesktop.org/plymouth/plymouth/-/archive/24.004.60/plymouth-24.004.60.tar.gz
tar xzf plymouth.tar.gz
S=plymouth-24.004.60/src

# Two headers a Mac does not have, and two stubs the parser never reaches.
mkdir -p shim && printf '#include <limits.h>
#include <float.h>
' > shim/values.h
cat > parsetest.c <<'EOF'
#include <stdio.h>
#include <stdbool.h>
#include <unistd.h>
#include "script.h"
#include "script-parse.h"
bool ply_fd_has_data(int fd) { (void)fd; return false; }
ssize_t ply_write(int fd, const void *b, size_t n) { return write(fd, b, n); }
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: parsetest <file.script>
"); return 2; }
    if (!script_parse_file(argv[1])) { fprintf(stderr, "PARSE FAILED
"); return 1; }
    printf("PARSE OK: %s
", argv[1]);
    return 0;
}
EOF

clang -o parsetest parsetest.c   $S/plugins/splash/script/script-parse.c $S/plugins/splash/script/script-scan.c   $S/plugins/splash/script/script-debug.c $S/plugins/splash/script/script.c   $S/plugins/splash/script/script-object.c   $S/libply/ply-bitarray.c $S/libply/ply-list.c $S/libply/ply-hashtable.c   $S/libply/ply-logger.c $S/libply/ply-buffer.c $S/libply/ply-array.c   -Ishim -I$S -I$S/libply -I$S/plugins/splash/script   -DPLYMOUTH_LOG_DIRECTORY='"/tmp"' -Wno-everything

./parsetest .../themes/aquarius/aquarius.script
```

It prints `PARSE OK` or names the line and column of the mistake. It was run
against this script on 2026-09-06 and it passed — and it was run against a
deliberately broken file first, to be sure a pass means something.

**What it does NOT prove:** that the script *works*. A name that Plymouth does
not have — `Plymouth.SetSomethingThatIsNotReal` — parses perfectly and then does
nothing at all on the machine. That is what the build's own check is for: it
reads the real instruction names out of the plug-in's compiled file and compares.
Between the two, the only things left are the ones a bench test finds.

---

### What a build can prove, and what it cannot

GitHub Actions checks a great deal of this on every push — the frame counts, the
numbering, the sizes, the colours **inside** the pictures, that the hold is the
pour's last frame, that every Plymouth instruction the script uses really exists
in this Plymouth, and that the theme, the script, the frames, the password box,
the plug-in and the three font files are all inside the boot ramdisk.

**What it cannot prove, and what the bench is for:**

| What | Why a build cannot see it |
| --- | --- |
| That the animation actually *plays*, at the right speed | Nothing in a container has a screen |
| That the pour reads as a pour and the wind as a wind | It is a judgement about a moving picture |
| The disk-password box | It only appears on a machine with an encrypted disk |
| The update screen in real use | It only appears during a real update |

---

### The bench test

On the bench machine, after `sudo bootc upgrade` and a restart:

**1. Watch it start up.** You should see the stream fall, the A pour out of it,
the wave spill across, the word fade in — and then **stillness** until the login
screen appears.

> ⚠️ **If the pour re-plays** — if it pours, holds, and then pours again — that
> means Plymouth restarted the theme rather than the animation looping. Our
> script has no loop in it at all: once the pour finishes, the code that advances
> the frames does nothing for the rest of the boot. So a second pour is Plymouth
> starting a fresh copy of the theme, which happens when the boot screen is
> stopped and started again mid-boot (a display handover, or a second Plymouth
> being asked for). Worth reporting with a note of what was on screen in between.

**2. Watch it shut down.** Choose Shut Down and watch: the word should fade, then
the mark should be taken apart from the left and blown off to the right, then
darkness. Restart should do exactly the same thing.

> **Before tests 3, 4 and 5:** `plymouth --show-splash` puts the boot screen
> **over the top of your desktop** and it stays there until you say
> `plymouth quit`. So do these over ssh from the Mac, or from a text console
> (`Ctrl+Alt+F3`, log in, and `Ctrl+Alt+F2` to get back) — not from a terminal
> window you are looking at, because the boot screen will cover it and you will
> not be able to type the next command.

**3. The update screen, without waiting for a real update.** From that terminal:

```bash
sudo plymouth --show-splash          # bring the boot screen up over the desktop
sudo plymouth system-update --progress=15
sudo plymouth system-update --progress=60
sudo plymouth system-update --progress=100    # this one plays the wind
sudo plymouth quit                   # put it away again
```

You should see the pour, then "Installing updates", "Please do not turn the
computer off.", a thin blue bar filling, and the percentage. At 100 the line
should change to "Turning off." and the wind should play with the heading and
the full bar still behind it.

*(The script deliberately draws that screen whenever a percentage arrives,
whatever the machine says it is doing, precisely so this test works.)*

**4. A message.**

```bash
sudo plymouth --show-splash
sudo plymouth display-message --text="Checking the disk. This can take a while."
sudo plymouth hide-message --text="Checking the disk. This can take a while."
sudo plymouth quit
```

The line should appear near the bottom of the screen and go away again.

**5. The disk-password box.** The real test needs a machine with an encrypted
disk. Short of that:

```bash
sudo plymouth --show-splash

# --command is where the typed password gets sent. /usr/bin/false rejects
# everything, which is exactly what we want: every attempt "fails", so Plymouth
# asks again, and asking again with nothing typed is the ONLY signal a boot
# theme ever gets that a password was wrong. That is what fires the shake.
# --number-of-tries is not optional here; Plymouth refuses it without --command.
sudo plymouth ask-for-password --command=/usr/bin/false --number-of-tries=3

# Type anything and press Enter. The box should shake once, and the line under
# it should change to "That password did not work. Try again."
sudo plymouth quit
```

What to look for: a **420×48 box with soft corners in Midnight's surface colour
with a hairline around it** — never Fedora's plain grey box — "Unlock the disk"
above it, a dot per character typed, and "Type the disk password to start."
underneath.

**6. Photographs.** One of the hold, one of the update screen, one of the
password box. They are the only record of what this actually looks like.

## Why there is no computer-maker's badge any more

This is worth understanding, because it is the single setting that does it.

Modern computers leave a picture of their own logo sitting in memory when they
hand control to the operating system. It is called the **BGRT**, and Fedora's
default boot theme — which is literally named `bgrt` — exists to pick that
picture up and use it as the background. That is why a stock Fedora machine
shows an ASUS or Dell logo while it starts rather than showing Fedora's own.

**How the old theme dealt with it.** Plymouth's `two-step` plug-in has a switch
for it, and the switch is **per screen** rather than global — the start-up
screen, the shutdown screen and the update screen each have their own. The old
theme turned it off in all six of its sections, and missing one would have let
the badge back in on that screen only, which is the kind of thing you find out
about six weeks later.

**How it works now, since 2026-09-06, and why this is better.** The `script`
plug-in **has no such setting at all.** It does not read the firmware's picture
and has no code to draw it — verified by reading the plug-in's own source for the
Plymouth this image ships (24.004.60): the only two settings it reads out of the
theme file are `ImageDir` and `ScriptFile`. And our script paints its own flat
Midnight ground over the whole screen on every single frame, so there is nothing
for a badge to show through.

So the badge is now gone **by construction** rather than by remembering to switch
it off in six places. The build checks that the theme file names no such setting
at all — a left-over `UseFirmwareBackground` line would do nothing, which is
exactly why it must not be there to mislead somebody reading the file.

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
       --add ostree --add bootc --add plymouth -v \
       /usr/lib/modules/<version>/initramfs.img
```

- `--kver` states the kernel version **explicitly**. Inside a build there is no
  running computer for the tool to ask, so left to itself it reads the version of
  the GitHub machine doing the building and produces something useless. Red Hat's
  own documentation makes the same point.
- `--no-hostonly` means "build one that works on any computer" rather than
  tailoring it to the machine doing the build.
- `--add ostree` and `--add bootc` are the two parts that know how to find and
  start an image-based system. Neither is optional. Leave one out and you get an
  image that installs perfectly and then stops at a black screen. Both are in
  the ramdisk this base image ships, and the build checks that both are still in
  ours afterwards.

### Why the ramdisk got much bigger, and why that is fine

Fedora's own ramdisk for this base image is about **121 MB**. Ours is about
**281 MB**. That is not a mistake and it is not a compression setting — dracut
already picks zstd on its own, and the build log says so.

It is the honest cost of `--no-hostonly` on a full desktop image. The base image
has almost no hardware support installed, so a ramdisk that works on "any
computer" is small. Ours has every graphics driver, all the wireless firmware,
and the full set of kernel modules, and a portable ramdisk has to be able to
carry all of it — because the one thing worse than a large download is an image
that will not start on the machine somebody installed it on.

The cost lands once per update on the layer that holds that file. Making it
smaller would mean leaving hardware out, which is the wrong trade for a machine
that gets plugged into cameras, capture cards and external GPUs.

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

# ⚠️ And the plug-in that PLAYS the animation. This is the one that would be
# easiest to miss: every picture can be inside the ramdisk and the boot screen
# is still black if the thing that knows how to play them was left out.
sudo lsinitrd /usr/lib/modules/$(uname -r)/initramfs.img | grep script.so
# → should list a plymouth .../script.so
```

GitHub Actions runs all four of those on every build, inside the finished image,
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
| `/usr/share/plymouth/themes/spinner/watermark.png` | Fedora's own boot themes | our logo — so if the boot screen is ever switched back to Fedora's plain theme (see "If it ever goes wrong" above), the logo on it is still ours |
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
the audit in `.github/workflows/build.yml` with its reason:

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

`volume_id` is the name written onto the disc image — what shows up when the
stick is plugged into a Mac or a Windows machine, and what the installer uses to
find its own files. (Only capital letters, digits, `-` and `_` are allowed there.
It is an old format with old rules.)

### What the finished ISO actually says — measured, not assumed

The first ISO built with this configuration was read back out of the build log
(run 33775709207), and it is better than expected. The ISO builder takes the
product name straight out of our image's own `/etc/os-release`, so:

```
org.osbuild.grub2.iso        "product": { "name": "AquariusOS", "version": "44" }
org.osbuild.grub2.iso.legacy "product": { "name": "AquariusOS", "version": "44" }
org.osbuild.buildstamp       "product": "AquariusOS", "version": "44"
                             "isolabel": "AQUARIUSOS"
```

- Both boot menus on the stick — the modern UEFI one and the older BIOS one —
  are titled **AquariusOS 44**.
- `buildstamp` is the file Anaconda itself reads to learn what it is installing,
  so **the installer calls itself AquariusOS** in its own headings and text.
- The disc label is **AQUARIUSOS**, which is what a Mac or a Windows machine
  shows when the stick is plugged in.

### What could NOT be rebranded, and what it would take

Two things, and both are narrower than they sound.

**1. The installer's pictures are still Fedora's.** `fedora-logos-42.0.1` is
installed into the installer's own runtime (confirmed in the same log), so the
sidebar logo and the header artwork on Anaconda's pages are Fedora's, even though
every word on those pages says AquariusOS.

The reason is a boundary, not an oversight, and it was confirmed against how the
ISO is actually built (2026-09-05). For an `anaconda-iso`, osbuild's
image-builder assembles a **separate little system** for the installer to run in
— a `anaconda-tree` — and fills it by reading this image's repository files and
then **downloading `fedora-logos` fresh from Fedora**. It does *not* copy the
files we replace inside our own image. Our image is the thing being installed,
not the thing doing the installing, so nothing we put in our image reaches the
stick's installer. (Source: osbuild's own description of the `anaconda-iso`
type — "we inspect the bootable container to find the repository definitions and
then download and install the relevant package from there".)

So the R1 hope — that replacing the artwork *in the image* would carry into the
installer — does not hold for `anaconda-iso`. It was tested and it does not.

What the in-image replacement DOES cover is the other way somebody meets
Anaconda: **running it on a machine that is already up**, where the installer is
part of this image's own files. `build_files/80-boot-branding.sh` replaces the
Fedora artwork there — and on 2026-09-05 that replacement was corrected: Fedora
44 moved the installer's `sidebar-logo.png` out of the old flat
`/usr/share/anaconda/pixmaps/` path and into per-product folders
(`/usr/share/anaconda/{atomic,cloud,server,silverblue,workstation}/`), so the old
loop, which named only the flat path, had been replacing nothing. It now finds
every `sidebar-logo.png` under `/usr/share/anaconda/`, plus `anaconda_header.png`
and the two boot splashes, and the build asserts each present file is ours. The
plain `topbar-bg.png` background strip is left alone on purpose.

Fixing the **USB-stick** installer's pictures properly is a separate job with two
real routes, scoped with the cost of each in
[`installer.md`](installer.md): ship a small `aquarius-logos` package that
`Obsoletes` `fedora-logos`, or switch from `anaconda-iso` to the newer
`bootc-installer` image type and bake our artwork into a custom installer
container. `bootc-image-builder` has no setting to swap artwork into the
`anaconda-iso` runtime — its config covers the kickstart, which installer screens
to show, the disc label, application id and publisher, and stops there.

**2. The boot-loader folder on the stick is named `fedora`.** The ISO carries
`"vendor": "fedora"`, which is the name of the directory the boot files sit in
(`/EFI/fedora/`). It is a path, not a caption — nobody reading the screen ever
sees it, and changing it would mean signing our own boot-loader files, which is a
Secure Boot project and not a branding one.

**The call:** not worth it now. It is a logo on a handful of screens, seen once,
on the way to a machine that then says AquariusOS everywhere for the rest of its
life. Worth revisiting if AquariusOS is ever handed to somebody who is not Royce.

---

## Where to go next

- **Moving the bench machine over, and what to look for on first boot:**
  [`bench-rebase.md`](bench-rebase.md)
- **Why the NVIDIA step is delicate, and why this one has to run after it:**
  [`nvidia-notes.md`](nvidia-notes.md)
- **How the whole build is put together:** [`README.md`](README.md)
- **The colours and fonts everything here uses:** `branding/tokens.md`
