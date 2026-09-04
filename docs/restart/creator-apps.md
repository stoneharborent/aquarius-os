# The creator apps — what ships, how it gets here, how to change it

*Phase R3b, written 2026-09-04. Written for somebody who has never used Linux.
Nothing here assumes you know what a container or a systemd unit is.*

This is the part of AquariusOS that makes it a creator's operating system
rather than a nicely branded Fedora.

---

## The one idea to hold on to

There are **two ways** an app gets onto this machine, and which one an app gets
is a real decision.

| | Which apps | Why |
| --- | --- | --- |
| **Baked in** | Aquarius Editor, Aquarius Writer | They are ours. They are on no app store. They are part of the operating system the way the file manager is, and they work on a computer that has never been online. |
| **Offered** | OBS Studio, Kdenlive, Krita, GIMP, Inkscape, Blender, Ardour, Audacity, Obsidian, LocalSend, Google Chrome, and five OBS plug-ins | They come from Flathub, the Linux app store. AquariusOS suggests them; **you choose which ones you actually want**, in a window at your first login. |

Firefox is neither: it is an ordinary system package, so it is *inside* the
image and works from the very first second, with nothing to download.

Nobody has to open a terminal for any of it.

---

## The contract the chooser window is written against

*This section is for whoever builds or changes the app chooser. Skip it if you
just want to use the computer.*

The chooser must never contain its own copy of the app list. There is one
source of truth, and one command that reads it:

```
/usr/libexec/aquarius-flatpak-preinstall --catalog
```

It needs no special powers, changes nothing, and prints **one line per app**,
fields separated by a **single tab character**, always **eight fields**, always
in this order:

| # | Field | Example |
| --- | --- | --- |
| 1 | id | `com.obsproject.Studio` |
| 2 | name | `OBS Studio` |
| 3 | description | one sentence, never contains a tab |
| 4 | category | one of `Video` `Audio` `Design` `Streaming` `Utilities` |
| 5 | recommended | `recommended:yes` or `recommended:no` |
| 6 | runtime | `runtime:yes` or `runtime:no` |
| 7 | requires | `requires:com.obsproject.Studio`, or `requires:-` |
| 8 | branch | `branch:stable` |

Fields 5–8 carry their own name as a prefix, so a reader can assert it is
reading the field it thinks it is, and so that a ninth field added one day
cannot be mistaken for one of these.

**Four rules for whoever draws the window:**

1. **Never show a line whose field 6 is `runtime:yes`.** Those five entries are
   plug-ins, not applications. They belong to the app named in field 7 and must
   be installed silently alongside it — never offered as a separate tick box,
   and never installed when the app they belong to was not chosen. Today that
   means **11 apps to choose from and 5 plug-ins that follow OBS Studio**.
2. **Tick `recommended:yes` by default; leave the rest unticked.** The
   recommended set is deliberately the everyday one, not everything.
3. **Install what is ticked by handing the whole list to one privileged
   helper, through `pkexec`:**

   ```
   pkexec /usr/libexec/aquarius-creator-apps-install <ref> <ref> …
   ```

   ...where each `<ref>` is field 1 and field 8 joined as `id//branch`, and the
   plug-ins from field 7 have already been added to that list by the chooser.
   `aq apps install` is the same job from a terminal and reaches the same
   place; the window does not go through it, because it needs the per-app
   progress the helper reports back (`STEP`, `PERCENT`, `OK`, `FAILED`,
   `DONE`).

   It installs **system-wide**, on purpose — see *One thing worth knowing about
   how this works* below.

   **The chooser must never run as root itself, and never call `sudo`.**
   `pkexec` is the right tool and `sudo` is the wrong one: `sudo` is built for a
   terminal, wants a tty to type into, and from a window either fails with
   nothing on screen or asks again for every app. `pkexec` is the desktop's own
   permission prompt — **one prompt, at the moment Install is pressed, for the
   whole run** — and everything privileged happens inside that single
   authorisation, in the helper. The window itself has no special powers at any
   point.
4. **Anything the person did not tick is simply not installed.** Nothing is
   written down, nothing is remembered as refused, and they can install it
   later from the app store or with `aq apps install`. Ticking nothing at all
   is a valid answer and must leave a working computer.

If `--catalog` exits non-zero, **do not fall back to a built-in list** — show
that something is wrong with the operating system. An empty answer from it is
always a fault, never "there are no apps".

---

## What happens on a new machine, honestly

**The apps are not in the installer**, and **nothing downloads until you say
so.**

At your first login a window appears listing the eleven apps AquariusOS
suggests, with a sentence about each one and the everyday ones already ticked.
You untick what you do not want, press the button, and those are installed.
The five OBS plug-ins are not in the list — they come along with OBS Studio
if you keep it, because on their own they do nothing.

Depending on how many you keep, that download is roughly **ten to twenty
minutes** on a normal home connection, and you can use the computer throughout.
Keeping everything is about ten gigabytes; keeping the ticked default is
rather less.

**Ticking nothing is a perfectly good answer.** You get a working computer with
Aquarius Editor, Aquarius Writer and Firefox already on it, and you can add any
of the rest later from the app store or with `aq apps install`.

> **Why it asks instead of just doing it.** Until 2026-09-04 it did not ask: a
> new machine fetched all sixteen entries on its first boot, about ten
> gigabytes of other people's software, whether or not the person wanted a
> single one of them. That is not a decision an operating system should make
> for somebody. The apps have not changed and neither has the list — what
> changed is who presses go.

If the machine is not online when you answer, nothing breaks and nothing is
lost — run `aq apps install --all`, or open the chooser again, once you are
connected. If one app fails and the rest succeed — Google Chrome does this
occasionally, for a reason explained below — it says which one by name.

### Why not just put them in the image?

Three reasons, and they are the standing decision of this project:

1. **Updates arrive when their authors ship them.** A Blender release from next
   Tuesday reaches you next Tuesday, not whenever AquariusOS next builds.
2. **A broken app can never stop the computer from starting.** An app that
   lives outside the operating system cannot take the operating system with it.
3. **The installer stays about four gigabytes instead of about fifteen.**

The cost is that first-boot wait. It is a real cost and it is written down here
rather than hidden.

---

## The window — "Your creator apps"

*This is the window itself: what is on it, and what happens when you press the
button. The list it draws comes from the two files described in
[the contract section](#the-contract-the-chooser-window-is-written-against);
this section is about the window, not the list.*

It is `/usr/libexec/aquarius-creator-apps` — a normal application window, built
the same way as the DaVinci Resolve installer window next door, so the two feel
like parts of one operating system rather than two different projects.

### Three pages

**1. Choosing.** The Aquarius mark, the sentence *"AquariusOS comes with a
studio's worth of apps. Pick the ones you want — you can change this any time
from Aquarius Apps."*, and then the apps as cards, on shelves:

> **Included with AquariusOS** — Aquarius Editor and Aquarius Writer, with no
> tick beside them and an **Open** button instead. They are already here.
> They are listed because this window should be the one place that shows you the
> whole studio; a window that quietly left out two of the apps would make you
> wonder which list was lying.
>
> **Video · Audio · Design · Streaming · Utilities** — a card each: the app's
> icon, its name, one sentence, a **Recommended** tag where it has one, and a
> tick. Clicking anywhere on a card ticks it.

Above the shelves: **Select recommended · Select all · Select none**. At the
bottom: how many you have chosen and roughly how big the download is, a
**Skip for now** link, and **Install**.

**What is ticked when it opens:** the recommended ones, and only those — OBS
Studio, Kdenlive, Audacity, GIMP, Inkscape and LocalSend. Blender, Ardour,
Krita, Obsidian and Chrome start unticked, because they are either very large
or for a particular job. It is a suggestion, and every part of it can be
undone in one click.

**Where the icons come from.** The real app icons are fetched from Flathub the
first time the window opens and kept in `~/.cache/aquarius/app-icons/`. If there
is no internet, or Flathub is slow, you get a category symbol instead and the
window opens at exactly the same speed — **nothing about this window ever waits
for the network.** The same is true of the download size in the footer: it is
Flatpak's own figure, asked for in the background, and if the answer never
arrives the footer simply says how many apps you picked and no size at all. A
number that is missing is better than a number that is wrong.

**The plug-ins are not on the page.** OBS Studio's card says *"…and its
plug-ins"* and that is the whole of it. The five entries that make game capture
and per-app sound work arrive with OBS because you chose OBS. Nobody who wants
to record their screen should have to learn what a Vulkan layer is.

**2. Installing.** One line per app, each with a spinner that becomes a tick or
a cross, an overall bar, and a **Details** panel with the full log in it —
closed by default, and it opens itself the moment anything fails. **Cancel**
stops it, between apps: the app that is downloading right now finishes first,
because stopping in the middle is how you get a broken one, and the window says
so as soon as you press it.

**3. Done.** *"All set."*, with **Open <the first app>** and **Close**. If
anything failed it says which, by name, and offers to try those again. Nothing
is ever left half-installed.

### One password prompt, at the moment you press Install

The window has no special powers of its own. When you press Install it runs
`/usr/libexec/aquarius-creator-apps-install` through `pkexec`, which is the
standard Linux "may I?", and you are asked for your password **once**, for the
whole run. That script does the installing, one app at a time, and reports back
on two channels: the human words go into **Details** unchanged, and short
structured lines (`STEP`, `PERCENT`, `OK`, `FAILED`, `DONE`) move the ticks and
the bar.

The apps are installed **for the whole computer**, not just your account. That
is why permission is needed at all, and it is the right way round: the extra
permissions creator apps need are shipped as system-wide overrides, and
`aq apps status` reports on the system installation. One place, one answer.

> **⚠️ This is what failed on the bench on 2026-09-04, and it is now fixed.** A
> password prompt needs something to draw it — a "permission agent". GNOME has
> one built into GNOME Shell. The Aquarius Session had **none**, and this
> document used to say the shell was the agent, which was the plan rather than
> the fact. So pressing Install produced:
>
> ```
> Error creating textual authentication agent: Error opening current controlling
> terminal for the process ('/dev/tty'): No such device or address
> ```
>
> ...which is `pkexec` finding nobody able to ask the question and falling back
> to asking in a terminal, behind a window that has none.
>
> The image now installs `lxqt-policykit` and the session starts it at login
> through `/usr/libexec/aquarius-polkit-agent`. The reasoning, the alternatives
> considered, and the guard for the day the shell grows an agent of its own are
> in [`aquarius-session.md`](aquarius-session.md#asking-for-your-password).
>
> The window also tells the two failures apart now: "you said no" and "nothing
> was able to ask you" are different problems, and only the first is worth
> pressing Try again over.
>
> If it ever happens again, the way through is one line in a terminal:
>
> ```
> sudo /usr/libexec/aquarius-creator-apps-install <app id> <app id> …
> ```
>
> ...or `aq apps install --all`. Both do exactly what the window would have done.

> **Why one app at a time?** So that every line on the page can be true. One
> long command has one answer at the end; eleven short ones have eleven. It
> costs nothing — the same bytes are downloaded, and shared runtimes are still
> fetched once — and it means Google Chrome can fail on its own without taking
> the other ten with it. And after each one, the script does not believe the
> exit code: it asks `flatpak info` whether the app is really there.

### How it opens by itself, once

Two files, because the two desktops start things differently:

| Session | What starts it |
| --- | --- |
| GNOME (the fallback) | `/etc/xdg/autostart/aquarius-creator-apps-firstrun.desktop` |
| The Aquarius Desktop | a block at the end of `/usr/share/aquarius/labwc/autostart` |

**labwc does not read `/etc/xdg/autostart` at all.** It reads exactly one file,
its own `autostart`, and that is deliberate — it is what keeps a dozen GNOME
background programs out of the Aquarius session. The cost is that anything
which must run at login in both sessions is written down twice, and the build
checks that the two copies still say the same thing.

Both wait ten seconds, so the window arrives once the desktop has settled
rather than on top of a login screen. Both pass `--first-run`, which is what
makes it happen once: the window looks for `~/.config/aquarius/creator-apps-seen`
and returns silently if it is there. Delete that file to be asked again.

> **A note for whoever next syncs the `aquarius-shell` repository:** that repo
> is the home of the labwc `autostart` file and AquariusOS ships a copy. The
> first-run block has to be carried across, or a session built from the shell
> repo will never offer anybody their creator apps.

### Opening it again — "Aquarius Apps"

It is in the app grid as **Aquarius Apps**, and it is the same window. Apps you
already have show **Installed**, with **Open** and **Remove** instead of a tick.
Removing goes through the same single password prompt, and leaves your own files
and the app's settings alone.

### Looking at it without a screen

```
aquarius-creator-apps --dry-run
```

reads the real list, prints what it found and what it would tick, opens no
window and installs nothing. Add `--catalog-from FILE` to read a saved catalogue
instead of the system's, or `--select id,id` to see what choosing exactly those
would install. This is what the build runs, and it is the honest way to check
the reading without a desktop.

---

## The full list

### Video

| App | What it is for |
| --- | --- |
| **OBS Studio** | Recording and live streaming. |
| **Kdenlive** | The everyday video editor. Unlike the free DaVinci Resolve, it opens a camera file straight off the card with no conversion at all — so when Resolve refuses a file and you do not want to wait, this is the way in. |
| **Blender** | 3D and motion graphics, and quietly one of the better video editors on Linux. |

### Audio

| App | What it is for |
| --- | --- |
| **Audacity** | The quick one. Record a voiceover, top and tail a file, clean up a hiss. |
| **Ardour** | The full multitrack studio, for when Audacity is not enough. |

### Pictures

| App | What it is for |
| --- | --- |
| **Krita** | Digital painting and illustration. The best free tool here for a hand-drawn thumbnail. |
| **GIMP** | Photo and image editing — the Photoshop-shaped hole. |
| **Inkscape** | Vector drawing. Logos, titles, anything that must stay sharp at any size. |

### The desk

| App | What it is for |
| --- | --- |
| **Obsidian** | Notes and writing in plain Markdown files. |
| **LocalSend** | Send a file from your phone to this computer and back, over your own network. No cloud, no account, no cable. This is how footage shot on a phone gets onto the machine in ten seconds. |
| **Google Chrome** | Because plenty of creator tooling is written against it. |

### The OBS plug-ins

These are not applications, so you will not see them in the app grid. They add
abilities to OBS.

| Plug-in | What it adds |
| --- | --- |
| **OBS VkCapture** | Capture a game's own picture directly, instead of capturing the screen and everything on top of it. |
| **The VkCapture Vulkan layer** | The other half of the above, and **the part everyone forgets** — the piece that sits inside the game and hands the frames over. Without it, game capture silently records nothing. |
| **PipeWire Audio Capture** | Capture *one* application's sound — the game, the browser tab, the call — instead of everything the speakers are playing. This is the plug-in that makes a stream mixable, and OBS does not ship it built in. |
| **GStreamer** and **GStreamer VA-API** | Extra encoders, including hardware video encoding on AMD and Intel graphics. (On NVIDIA, OBS uses NVENC, which is built in and needs no plug-in.) |

---

## The two Aquarius apps

**Aquarius Editor v0.7.2** and **Aquarius Writer v0.5.5** are downloaded during
the *build*, checked against the fingerprints GitHub published with them,
unpacked, and put inside the image. By the time you install AquariusOS they are
already there.

Three details worth knowing:

- **They are unpacked, not left as AppImages.** An AppImage normally mounts
  itself every time it runs, using a system component called FUSE, and when
  FUSE is missing the app dies with a message nobody can act on. Unpacked,
  there is nothing to go missing.
- **They can update themselves.** `/usr` is read-only on this operating system,
  so the built-in copy can never change in place. Instead each app may download
  a newer copy of itself into your home folder, and at every launch the
  operating system decides which of the two is newer and starts that one. If
  the downloaded one is broken, it quietly falls back to the built-in one — a
  bad download must never leave you with a dead icon.
- **Aquarius Editor draws sharply on a 4K screen.** Electron apps normally go
  through a compatibility layer that cannot scale by a fraction, so at 125% or
  150% they look faintly out of focus. AquariusOS sets
  `ELECTRON_OZONE_PLATFORM_HINT=auto`, which fixes it, and falls back safely on
  a machine that is not running Wayland.

---

## Where the apps appear

### The Aquarius Desktop's dock

A brand-new account gets: **Files · Aquarius Editor · Aquarius Writer · OBS ·
Kdenlive · Firefox · Terminal · Settings**

That list is a plain file, and it is yours:

```
~/.config/aquarius-shell/dock.json
```

Edit it, save it, and **the dock reorders while you watch** — no restart. A
name that does not match anything installed is simply skipped, so nothing you
type there can leave a hole or break the dock.

> **If your account already existed before this update**, you will not have that
> file, because `/etc/skel` only furnishes *new* accounts. The dock still shows
> both Aquarius apps — the shell's own built-in default already names them. To
> get exactly the list above, copy it in:
>
> ```
> mkdir -p ~/.config/aquarius-shell
> cp /etc/skel/.config/aquarius-shell/dock.json ~/.config/aquarius-shell/
> ```

### GNOME's dock (the fallback desktop)

**Files · Aquarius Editor · Aquarius Writer · Firefox · Terminal · Text Editor
· Software · Settings**

The Flatpak creator apps are deliberately *not* pinned here. They are not
inside the image — they arrive over the internet — so pinning them would mean a
dock full of dead squares for the first ten minutes of a new machine's life,
and forever on a machine that is never online. They appear in the app grid the
moment they finish installing, and you can drag any of them to the dock.

The two docks are allowed to differ, and that is why.

---

## Changing the list

### Remove an app you do not want

Open **Software**, find it, press **Uninstall**. Or in a terminal:

```
flatpak uninstall com.obsproject.Studio
```

**And it stays gone.** Flatpak remembers that you removed a preinstalled app
and never puts it back. That is a guarantee of Flatpak's own mechanism, not
something we bolted on top. AquariusOS suggests; it does not insist.

### Stop one being installed in the first place

Useful when setting a machine up for somebody else:

```
sudo mkdir -p /etc/flatpak/preinstall.d
printf '[Flatpak Preinstall org.blender.Blender]\nInstall=false\n' \
  | sudo tee /etc/flatpak/preinstall.d/00-local.preinstall
```

### Add an app for everybody, in the operating system itself

Edit
`os-image/system_files/usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall`,
copy an existing block, change the ID, keep `Branch=stable`.

⚠️ **A typo in an app ID is completely silent** — the app simply never appears
and nothing anywhere says why. So the build asks Flathub whether every name on
the list is real, and refuses to publish an image containing a made-up one.

Note that the obvious way to check a name by hand does not work:
`https://flathub.org/apps/<id>` answers "yes" to almost anything, because that
page is drawn in your browser after it loads. The honest question — and the one
the build asks — is `https://flathub.org/api/v2/appstream/<id>`, which returns
nothing at all for a name that does not exist.

---

## The extra permissions

Flatpak apps run in a sandbox: they can only see what they have been given
permission to see. Flathub's defaults are written for a general audience and
they are wrong for a creator in two specific ways.

| App | What AquariusOS grants, and why |
| --- | --- |
| **OBS Studio** | `devices=all` — cameras, capture cards, and the virtual camera. Flathub's OBS asks only for the graphics card, because most people stream a game. Plug in a real camera or an Elgato-style capture card and, without this, OBS shows an **empty device list with no explanation**. |
| **Kdenlive, Blender, Krita, GIMP, Inkscape, Audacity, Ardour** | The card reader and external drives (`/run/media`, `/media`, `/mnt`), plus the relevant one of your Videos, Music and Pictures folders. Their own permissions cover your home folder; footage does not live in your home folder. |
| **Obsidian** | Your Documents folder and external drives, so a vault on a second drive opens instead of failing with "cannot open folder". |

**Never `filesystems=host`.** That means "the whole computer", which is the
same as having no sandbox at all. Every grant above names specific places, and
the build fails if any file asks for `host`.

### If you need something different

Do not edit our files — the next system update replaces them. Set your own,
which always wins and is never touched:

```
flatpak override --user --filesystem=/path/to/your/vault md.obsidian.Obsidian
```

### One thing worth knowing about how this works

Flatpak reads system-wide permissions from exactly one folder,
`/var/lib/flatpak/overrides/`, and **not** from either of the two places you
would guess (`/usr/share/flatpak/overrides/` or `/etc/flatpak/overrides/`) —
writing to those does nothing at all, silently. That was read out of Flatpak's
own source code rather than assumed.

On AquariusOS `/var` belongs to the machine rather than to the operating
system, so anything written there during a build is thrown away on first boot.
The permission files therefore ship read-only inside the image and are copied
into place on the machine by a small service of their own,
`aquarius-flatpak-overrides.service`, which runs at every boot — and **it never
overwrites a file that is already there**, so anything you set yourself
survives every update.

That service exists separately for a reason worth knowing. Until 2026-09-04 the
permissions were granted by the same service that installed the apps. Once the
chooser took over the installing, an app could arrive with no permissions behind
it: OBS would install perfectly and then not see a camera, with nothing anywhere
saying why. The permissions do not care who installed the app, or whether it is
installed yet — a permission file for an app you never chose simply sits there
doing nothing — so they were separated out and left switched on.

### And this is why the apps are installed for the whole computer

Flatpak can install an app either **for the whole computer** or **for one
person only**. AquariusOS installs for the whole computer, and the paragraph
above is the reason: the permissions that let OBS see your camera and your
capture card live in `/var/lib/flatpak/overrides/`, which applies to
computer-wide installs and to nothing else. Install OBS for yourself alone and
it is sandboxed away from your camera, with no message saying why.

The cost is that installing asks for a password once — the ordinary desktop
prompt, the same one the app store uses. Nothing runs as root beyond that, and
neither the chooser nor `aq apps` ever calls `sudo`. The prompt comes from the
system, not from us: the chooser asks through `pkexec`, `aq apps` lets Flatpak
ask, and either way it is Linux's own permission prompt putting the question to
you, once. The benefit is that the apps work for everybody who uses the
machine, and are downloaded once rather than once per person.

---

## The virtual camera

OBS has a button called **Start Virtual Camera**. Press it and OBS pretends to
be a webcam, so Zoom, Meet, Discord or a browser can use whatever OBS is
showing.

That button needs a piece of code inside the kernel, and a sandboxed app cannot
install one — so AquariusOS provides it. On this machine the virtual camera
appears as **AquariusOS Virtual Camera**.

**It is possible for a build to leave it out.** Kernel code has to be built
against one exact kernel version, and for a day or two after a Fedora kernel
update the ready-made module and our kernel are out of step. When that happens
the build says so loudly, leaves the module out rather than shipping something
that cannot load, and writes down what happened. To check any machine:

```
cat /usr/share/aquarius/virtual-camera.txt
```

`status=installed` means the button works. `status=unavailable` means it does
not, and says why. Everything else about OBS — screen recording, cameras,
capture cards, the plug-ins — is unaffected either way.

---

## Doing it from a terminal — `aq apps`

The chooser at first login is the main way to pick. Afterwards, this is the
same job typed out:

```
aq apps list                     what is suggested, and what you have
aq apps status                   how many you have, and what to do if some are missing
aq apps install org.kde.krita    add one you skipped
aq apps install --all            everything on the list (a large download)
```

`aq apps list` prints the app's ID on the left — that is what `install` wants.
The five OBS plug-ins are not listed, because they are not choices: they arrive
with OBS Studio and asking for one by name is refused, with a note saying which
app it belongs to.

You will be asked for your password once, by the desktop's own prompt. That is
the system asking, not us: the apps are installed **for the whole computer** for
the reason given under *One thing worth knowing about how this works*, and
nothing here ever runs `sudo` on your behalf.

---

## When something goes wrong

### "The apps never arrived"

**What you see.** The app grid has Aquarius Editor, Aquarius Writer and Firefox
and none of the apps you chose. `flatpak list --app` shows only what was
already there. Asking the computer what happened:

```
journalctl -u aquarius-flatpak-preinstall
```

shows a run that ended almost immediately, saying:

> AquariusOS creator apps: the shopping list is empty. Nothing to install.

**The rescue, which works today, on the machine in front of you:**

```
sudo flatpak preinstall -y --system
```

That is Flatpak's own command reading the same list, and it installs
everything on it. `aq apps status` will then show them as present.

**What caused it.** A bug in AquariusOS, fixed on **2026-09-04**, and worth
writing down because of the shape of it rather than the size.

The script read the list with a pattern covering two folders — the one the
operating system ships and the one you can put your own changes in. On a new
machine the second folder is *empty*, and when a pattern like that matches
nothing, the shell hands over the pattern itself as though it were a filename.
The reader was asked for a file that does not exist, gave up before printing a
single answer, and the script saw zero apps.

It then did the genuinely damaging thing: it treated "zero apps" as *"there is
nothing to install"*, said so cheerfully, and **wrote the marker that means
never look again** — so the machine was permanently finished with a job it had
never started. Nothing appeared to be wrong anywhere.

Three things changed, and only the first is the bug:

1. The list of files is built up by looking at each one, so a folder with
   nothing in it is simply a folder with nothing in it.
2. **An empty answer is now treated as a fault, never as an answer.**
   AquariusOS always ships a list, so "no apps" cannot honestly happen. It now
   says so in plain words, says it is our bug and not yours, tells you the
   rescue command above, writes **no** marker, and stops with an error — so the
   machine shows up in `systemctl --failed` instead of looking healthy.
3. The build now runs the real reader against the real list and refuses to
   publish an image unless it finds every app. The old checks looked at the
   list file and never once ran the code that reads it, which is exactly how a
   reading fault reached a real machine.

---

## What is checked before an image is published

Every one of these runs against the **finished** image, not against the build
scripts:

- Both Aquarius apps unpack, carry a version stamp that agrees with what the
  build recorded, and — asked the way an ordinary account experiences it, not
  the way root does — can actually be read, entered and run by somebody who is
  not root. *(This is the bug of 2026-08-28, where both apps shipped, both
  appeared in the app grid, and clicking either did nothing at all.)*
- Aquarius Editor's sandbox helper survived packaging as `root:root 4755`.
  Electron aborts instantly and silently when it has not.
- Both app-grid entries pass the freedesktop project's own validator.
- Flatpak is new enough to have the preinstall mechanism, and has it.
- Every app Royce chose is still on the list, every entry names a branch, and
  every plug-in is marked as a plug-in.
- Every permission file is read back **through Flatpak's own parser**, and none
  of them asks for the whole computer.
- Every app pinned to GNOME's dock is a real file in the image.
- The Aquarius dock's default list is valid and names both Aquarius apps.
- `aq ingest` is wired up and discoverable from `aq --help`.
- The ingest watch folder is **off**.
- The virtual camera's own record agrees with what is actually in the image.
- On the NVIDIA image, ffmpeg can really encode with `h264_nvenc` and
  `hevc_nvenc` — the difference between a three-minute export and a
  twenty-minute one.

And, for the chooser window specifically:

- The window is valid Python, the installer is valid shell, and **a Python
  program on the finished image can really load GTK 4, libadwaita and Pango** —
  which is how this particular thing breaks: the packages are installed and the
  import fails anyway, for want of a description file.
- The installer is root-owned and `0755` or tighter. `pkexec` refuses to run a
  program anybody could have edited, and if it refuses, the single password
  prompt this whole feature depends on never appears.
- Both menu entries pass the freedesktop validator, the app-grid one is called
  *Aquarius Apps*, and the first-login one has **no `OnlyShowIn`** — a session
  name there would be the only session that ever ran it.
- The Aquarius session's `autostart` carries the same first-run line, so the
  two copies cannot drift apart silently.
- **Nothing installs itself.** The installer service has no `[Install]` section
  and nothing has linked it into a `.wants` folder. *(Read from the files, not
  from `systemctl is-enabled`, which exits **zero** — success — for a unit whose
  state is "static", and would therefore report this as broken on every build
  forever.)*
- The window reads a small made-up catalogue in `tests/`: it must skip the one
  deliberately broken line instead of guessing at it, keep the two plug-ins out
  of the choices, and — **choosing OBS Studio on its own must produce three
  things to install**, including the Vulkan layer at branch `25.08`, the piece
  everyone forgets.
- The window reads **the real list this image ships**, with the real parser.
  More than none offered, more than none ticked, no line unread, and no plug-in
  belonging to an app nobody can choose. *(This is the check whose absence let
  an image ship on 2026-09-04 that could not read its own shopping list.)*
- The installer's rehearsal emits `STEP`, `PERCENT` and `DONE` in order, and run
  without permission it explains itself in words rather than failing obscurely.

---

## Bench test, for Royce

After rebasing the 4090 to an image built from this branch:

1. **Log in and wait about ten seconds.** The **"Your creator apps"** window
   should appear on its own, showing Aquarius Editor and Aquarius Writer as
   *Included*, then eleven apps as cards on five shelves, with six of them
   already ticked. Nothing has downloaded yet.
2. **Pick and install.** Untick anything you do not want, press **Install**, and
   enter your password when asked — **once**. Watch the lines tick over one at a
   time and open **Details** to see the log. Then press **Open OBS Studio** on
   the last page.

   *Then check the three claims this window makes.* `aq apps status` should agree
   with what you see on screen. Close the window, log out and back in — it must
   **not** come back. Open **Aquarius Apps** from the app grid: the apps you
   installed now say *Installed* with **Open** and **Remove**, and the ones you
   skipped are still there to tick.

   *And the two ways it is allowed to go wrong.* If nothing is ticked when the
   window opens, the catalogue is not being read — say so, that is a bug of
   ours, and `aq apps catalog` will show the same emptiness. If one app fails
   (Chrome is the likely one) the rest must still arrive, and the failed one
   must be named on the last page.
3. **Open Aquarius Editor and Aquarius Writer** from the dock. Both should open
   a window. If either does nothing, the log is
   `~/.local/state/aquarius/aquarius-editor.log`.
4. **Look at the Editor's text at 125%.** It should be crisp, not faintly
   soft. That is the Electron fix.
5. **Open OBS.** Add a **Video Capture Device** source — your camera should be
   in the list, not an empty box. Then press **Start Virtual Camera**; it
   should not error. Open a browser video-call test page and check
   *AquariusOS Virtual Camera* is offered as a camera.
6. **Open Kdenlive**, and use its file picker to browse to a USB drive or card
   reader. It should be reachable.
7. **Try LocalSend** from your phone to the machine — the fastest way to get a
   real phone clip onto it for the ingest test in
   [`ingest.md`](ingest.md).
8. **Remove something and check it stays removed.** Uninstall Obsidian in
   Software, reboot, and confirm it has not come back.
