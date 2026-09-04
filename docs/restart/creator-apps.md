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
| **Preinstalled** | OBS Studio, Kdenlive, Krita, GIMP, Inkscape, Blender, Ardour, Audacity, Obsidian, LocalSend, Google Chrome, and four OBS plug-ins | They come from Flathub, the Linux app store, and are downloaded the first time the machine is online. |

Firefox is neither: it is an ordinary system package, so it is *inside* the
image and works from the very first second, with nothing to download.

Nobody has to open a terminal for any of it.

---

## What "preinstalled" means in practice, honestly

**The apps are not in the installer.** On a brand-new machine, once you are
connected to the internet, AquariusOS spends roughly **ten to twenty minutes**
downloading them in the background.

You can use the computer the whole time. You will see:

> **Setting up your creator apps**
> AquariusOS is downloading 17 apps in the background. You can carry on using
> the computer — this takes about ten to twenty minutes on a normal connection.

then a count that updates in place — *"6 of 17 installed. Still working."* —
and finally:

> **Your creator apps are ready**
> All 17 apps are installed. You will find them in the app grid.

If the machine is not online yet, **nothing breaks and nothing is lost.** It
tries again at every start-up, forever, until the list is satisfied. If one app
fails and the rest succeed — Google Chrome does this occasionally, for a reason
explained below — it says which one, and retries only that one.

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
into place on the machine, once, by the same service that installs the apps —
and **it never overwrites a file that is already there**, so anything you set
yourself survives every update.

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

---

## Bench test, for Royce

After rebasing the 4090 to an image built from this branch:

1. **Log in and wait.** Within a minute or two you should see *"Setting up your
   creator apps"*. Leave it alone and use the machine.
2. **Check it finished.** `flatpak list --system --columns=application` should
   list all seventeen. Or: `journalctl -u aquarius-flatpak-preinstall -b`.
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
