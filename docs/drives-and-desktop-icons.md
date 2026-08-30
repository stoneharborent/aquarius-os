# Drives that mount themselves, and drives on the desktop

*Decisions taken by Royce, 2026-08-30. Implemented the same day.*

This is the write-up for three changes that all landed together, because they are
really one idea: **a drive that is in this machine should just be there, and you
should be able to see it.** The Mac has felt this way for twenty years; Linux
mostly has not.

If you only read one section, read **"What you will actually notice"** and
**"The three honest catches"**.

---

## The three changes

| # | What Royce asked for | What ships |
|---|---|---|
| 1 | Every internal data drive mounts itself at boot — **especially the Windows game drive** on a dual-boot PC | A small boot-time service, plus KDE's "mount at login" switch turned on |
| 2 | Every mounted drive shows as an icon on the desktop, **including the OS drive itself**, like "Macintosh HD" | A small background program that keeps shortcut files in your Desktop folder |
| 3 | The desktop never holds application icons | The same program quietly moves them into a holding folder |

---

## What you will actually notice

**On the desktop, down the right-hand edge**, you now get an icon for every drive
in the machine. The first one is called **AquariusOS** — that is the disk the
system is installed on, and it is the equivalent of the Mac's "Macintosh HD".
Below it, one icon per data drive: your footage drive, your Windows game drive,
the camera card in the reader. Double-click any of them and the Files app opens
on that drive.

They appear the moment a drive is mounted and disappear the moment it is
unplugged, without you doing anything.

**Your Windows drive is now readable and writable** from AquariusOS the moment
you log in, without clicking it first. On a dual-boot gaming PC that means a
Steam library on the Windows disk is simply available.

**If you drag an app onto the desktop** — or use the app grid's "Add to Desktop"
— the icon will appear and then quietly vanish a second later, with a
notification telling you where it went. It has not been deleted. See change 3
below.

---

## Change 1 — internal drives mount themselves

### Where the drives appear

`/run/media/system/<the drive's own name>`

That folder is not something we invented. It is where Bazzite's automounter
already puts fixed disks and where `systemd-mount` puts a disk when it is not
told otherwise, so everything on the machine already agrees about it.

### What was already there, and what was missing

Bazzite ships an automounter of its own, `ublue-os-media-automount`. It runs at
boot and mounts fixed disks — but only **ext4 and btrfs**, and only ones that
have been given a name. Everything else it walks past, by design. That leaves out
the single most common drive on a gaming PC: the **NTFS** partition Windows lives
on. It also leaves out exFAT (the format most big portable SSDs ship in), XFS,
F2FS and any ext4 drive nobody bothered to name.

### What ships

| File | What it is |
|---|---|
| `system_files/usr/libexec/aquarius-internal-automount` | The script that decides what to mount and mounts it |
| `system_files/usr/lib/systemd/system/aquarius-internal-automount.service` | The note telling the machine to run it at boot |
| `build_files/build.sh` | One line switching the service on |
| `system_files/usr/share/aquarius/xdg/kded_device_automounterrc` | KDE's "mount everything at login" switch, flipped on |

The script's own comments are the real documentation — it explains every rule it
follows and why, and it is written to be read.

### Why a boot service, and not one of the other four options

Four mechanisms were considered. Written out honestly:

**A boot-time system service — chosen.**
- Works for **every account on the machine, including ones that already
  existed**. Nothing has to be copied into a home folder and nothing clicked
  once. This is the requirement that killed most of the alternatives.
- Lives entirely in `/usr`, which *is* the OS image, so an OS update updates it
  and nothing local can drift.
- We write the skip rules ourselves, so "never touch swap, the EFI boot
  partition, Windows' recovery partition or the disk we are booted from" is
  something we can guarantee and can read in one file.
- Same shape as the thing Bazzite already ships, so there is one pattern on the
  machine rather than two.
- **Cost:** an internal drive connected while the machine is *running* is not
  picked up until the next boot. `sudo systemctl restart
  aquarius-internal-automount` does it without rebooting.

**Just flipping KDE's "mount at login" switch — rejected as the primary
mechanism, shipped as a second belt.**
- It is per-user. It does nothing until somebody logs in, and nothing at all for
  a machine sitting at the login screen.
- It mounts through udisks2, which picks the NTFS driver itself — and we want to
  name the driver (see below).
- But it *does* usefully catch one thing the boot service cannot: a camera card
  that was already in the reader when the machine was switched on. So it is on
  too. The two do not fight — whichever gets there first mounts the drive, and
  the other sees it is already mounted and does nothing.

**A systemd mount generator, or `/etc/fstab` entries — rejected.**
- `/etc/fstab` is per-machine; it cannot be shipped in an OS image, because the
  image does not know what disks your machine has.
- A generator would need the same skip rules, so it would be a harder-to-read
  version of the same file, running at a far more dangerous moment: a generator
  that gets something wrong can stop the machine booting. The chosen service
  cannot — every mount it makes is a transient unit that nothing depends on, and
  carries the `nofail` option.

**A udisks2 policy file — rejected.**
- udisks2 policy says who is *allowed* to mount what. It never mounts anything
  itself. Wrong tool.

### Why `ntfs3` and not `ntfs-3g`

There are two ways to read a Windows disk on Linux. `ntfs-3g` is the old one and
runs outside the kernel through FUSE; `ntfs3` is a driver inside the Linux kernel
itself, contributed by Paragon Software and merged in Linux 5.15. The kernel one
is dramatically faster, which is the whole ballgame when the drive holds a Steam
library, and it is what a modern Fedora kernel ships.

The script names it explicitly rather than saying "ntfs" and letting the system
choose, because "let the system choose" can land on `ntfs-3g` and quietly halve
the drive's read speed.

Source: Linux kernel `Documentation/filesystems/ntfs3.rst`.

### What is deliberately never mounted

Two independent safety nets, because getting this wrong is not cosmetic.

**By what is on the drive:** swap, LUKS and BitLocker encrypted containers, LVM
and RAID member disks, ZFS members, read-only system images.

**By what the partition table says it is:** the EFI System Partition, the BIOS
boot partition, the Microsoft Reserved partition, the Windows Recovery
partition, Linux swap, and LVM/RAID/LUKS containers named a second way. The
old-style MBR equivalents are on the list too.

**And three more rules:** anything already mounted is skipped (which is what
keeps us off the disk AquariusOS is booted from, and off anything Bazzite's own
automounter got to first); anything `/etc/fstab` already has an entry for is
skipped, because somebody has already said how they want it; and anything
removable is skipped, because that is KDE's job.

---

## Change 2 — drives on the desktop

### Why this needs a program at all

On a Mac this is a checkbox. On KDE Plasma 6 there is no such checkbox and no
hidden setting either — **the feature genuinely does not exist.** What Plasma
gives us instead is a desktop that *is* a folder: the icons you see are the real
files in your Desktop folder, drawn by a component called Folder View.

So the way to put a drive on the desktop is to put a **file** in the Desktop
folder that stands for that drive. That is all this program does.

### What ships

| File | What it is |
|---|---|
| `system_files/usr/libexec/aquarius-desktop-volumes` | The program |
| `system_files/usr/lib/systemd/user/aquarius-desktop-volumes.service` | The note telling each logged-in person's session to run it |
| `build_files/build.sh` | One line switching it on **for every account** |

Each drive gets a small shortcut file, `Game Drive.desktop`, containing:

```
[Desktop Entry]
Type=Link
Name=Game Drive
Icon=drive-harddisk
URL=file:///run/media/system/Game%20Drive
X-Aquarius-Volume=true
```

`Type=Link` matters: KDE follows a shortcut-to-a-place straight to its
destination, with no "are you sure you want to run this?" warning and no need for
the file to be marked executable — unlike a shortcut to a *program*, which is
checked carefully first. So a double-click just opens the drive in Dolphin.

`X-Aquarius-Volume=true` is a marker KDE ignores entirely. It is how the program
recognises its own files, and it is the reason it can tidy away icons for drives
that have been unplugged **without ever being able to touch one of your files.**
It only deletes a file carrying its own mark. There is a test for that.

### Icons and names

| Drive | Icon | Name |
|---|---|---|
| The one AquariusOS is on | `drive-harddisk-root` | **AquariusOS** |
| A fixed internal disk | `drive-harddisk` | the drive's own label |
| A USB stick or external disk | `drive-removable-media-usb` | the drive's own label |
| An SD card | `media-flash-sd-mmc` | the drive's own label |
| A CD or DVD | `media-optical` | the disc's label |

Every one of those is a real icon in Breeze, the icon set AquariusOS uses, so
none of them can come out as a blank square.

### Existing accounts vs. fresh accounts

**This works for both**, and that was a hard requirement.

The desktop layout script that builds the AquariusOS top bar and dock runs
**once, for a brand-new account, and then never again** — KDE will not rearrange
a desktop somebody already has. Anything shipped that way would reach Royce's
next fresh install and nobody else.

A systemd *user* service does not work like that. The build enables it with
`systemctl --global enable`, which registers it for **every account on the
machine** — the ones that exist today and the ones made tomorrow. Nothing is
copied into anybody's home folder and nothing has to be clicked once. An OS
update refreshes it like any other file in `/usr`.

There is a CI check that fails the build if that `--global` ever goes missing,
because losing it would silently reduce the feature to "fresh installs only".

### How it stays cheap

The program sleeps until the kernel wakes it. `/proc/self/mountinfo` is a special
file that notifies a waiting program the instant anything is mounted or
unmounted, so noticing a drive is genuinely event-driven, not a poll. It also
glances at the Desktop folder's timestamp every two seconds — one very cheap
question — so that it notices a new file appearing there.

It runs at `Nice=10` with idle disk priority, so it can never be the reason
something you are actually doing feels slow.

### What was considered and rejected

- **A third-party Plasma widget.** The desktop spec (`gnome-principles-kde-spec.md`,
  item B7) rules out compiled add-ons, and every "volumes on desktop" widget for
  Plasma is one.
- **Symbolic links instead of shortcut files.** A link to a folder gets a plain
  folder icon with the folder's name. We want real drive icons with real drive
  names.
- **Naming the files something other than `.desktop`.** Tried, because it would
  have made change 3 much easier (see below) — but KDE only reads the `Name=`
  line out of a file whose name ends in `.desktop`, so the icons would have shown
  their raw filenames instead of the drive's proper name.

---

## Change 3 — no app icons on the desktop

### The honest finding: Plasma will not let us prevent this cleanly

We went and read the code. **"Add to Desktop" is offered whenever exactly one
condition is true: the desktop is not locked.** There is no setting, and no
system-administrator override, that turns off just this one thing.

```cpp
// plasma-workspace/applets/kicker/containmentinterface.cpp — mayAddLauncher()
case Desktop: {
    containment = corona->containmentForScreen(containment->screen(), QString(), QString());
    if (containment) {
        return (containment->immutability() == Plasma::Types::Mutable);
    }
```

The two things that *would* stop it are both locked doors, and AquariusOS does
not ship locked doors:

- **Locking the desktop** (`plasma/plasmoshell/unlockedDesktop` in KDE's
  administrator settings). Also stops you moving any icon, rearranging any
  widget, or editing your launcher's favourites.
- **Making the Desktop folder read-only**, which [KDE's own documentation
  suggests](https://develop.kde.org/docs/administration/kiosk/keys/) — and which
  would also stop you saving a file to your desktop.

**Hiding all shortcut files was also considered and rejected.** Folder View has a
file filter that can hide every `.desktop` file — but our drive icons *are*
`.desktop` files, so that setting would hide the drives too. There is no way to
write the filter so it catches one and not the other: its patterns have no way to
say "except these". (`foldermodel.cpp`'s `filterAcceptsRow()` hides an item when
`!(matchPattern(item) && matchMimeType(item))`, and `matchMimeType()` compares the
file's real type, which for every shortcut file — ours included — is
`application/x-desktop`.)

**One thing genuinely cannot happen:** the Task Manager in the dock has no "Add
to Desktop" at all — only "Pin to Task Manager". So the dock can never put an app
on your desktop.

### So: a tidy-up, with the front door left unlocked

Nothing stops you putting an app icon on the desktop. The program simply picks it
up again, puts it in `~/.local/share/aquarius/desktop-app-icons/`, and tells you
it did.

- **Nothing is deleted.** The file is moved, and the folder has a `README.txt`
  in it explaining what happened.
- **The app itself is untouched** — still installed, still in the app grid, still
  pinnable to the dock.
- **Only application shortcuts are moved.** Documents, folders, website
  bookmarks (`Type=Link`) and our own drive icons are all left exactly alone.
  There are tests for every one of those.
- **⚠️ And shortcuts that are part of how the machine works are never moved.**
  This one was learned the hard way, later the same day. On the handheld image,
  "Return to Gaming Mode" is an application shortcut sitting on the desktop —
  and it is the only way back to Game Mode on a device with no keyboard. The
  first version of this program filed it away, which stranded Royce's Ally on
  the desktop. It is now protected by name, by what it runs, and by a
  `X-Aquarius-Keep-On-Desktop=true` line anyone can add to a shortcut of their
  own. If an older build already moved yours, updating puts it back for you.
  Full story: `game-mode-regression.md`.
- **It never runs in Game Mode at all.** The service asks "am I on a Plasma
  desktop?" before it starts, and skips itself if not.
- **It is one line to switch off.** Put this in `~/.config/aquarius-desktop.conf`:

  ```
  KeepAppIconsOffDesktop=false
  ```

  The change takes effect within a couple of seconds; there is nothing to
  restart. (`ShowDrivesOnDesktop=false` turns off the drive icons the same way.)

It is a plain config file rather than a System Settings page because Plasma has
no page to put it on — these are behaviours Plasma does not have, so there is no
existing checkbox to hang them off.

### What a user could still do manually

Being precise about this, since it is the part that is *not* prevented:

1. **"Add to Desktop" from the app grid** — works, and then the icon is tidied
   away a second later with a notification.
2. **Dragging an app from the app grid or from Dolphin onto the desktop** — same.
3. **Right-clicking the desktop → Create New → Link to Application…** — same.
4. **Copying a `.desktop` file into the Desktop folder from a terminal** — same.
5. **Turning the tidy-up off** with the config line above — then all four of the
   above stick, permanently, which is exactly as it should be.

---

## The three honest catches

### 1. Encrypted drives may ask for a password shortly after you log in

Turning KDE's "mount everything at login" switch on means KDE will now try to
open an encrypted drive as you log in, and opening one means asking for its
password. So you may get a prompt for a drive you were not thinking about.

Nothing is unlocked without that password, and cancelling is harmless — the drive
stays locked and you can unlock it later by clicking it in the Files app.

The boot-time service deliberately does not touch encrypted drives at all, for
the same reason: it runs before anyone is logged in, so it has nobody to ask.

If the prompt is unwelcome, it is one tick-box: **System Settings → Removable
Storage → Removable Devices → "Automatically mount all removable media at
login"**. Untick it and your choice wins from then on, permanently.

### 2. A hibernated Windows drive mounts read-only

Windows 10 and 11 ship with **Fast Startup** switched on, and what that setting
actually does is: shutting down does not shut down. Windows hibernates instead,
leaving the disk marked "I am still using this, do not touch".

The `ntfs3` driver honours that mark and refuses to mount the drive for writing —
which is correct and careful, because writing to a disk a sleeping Windows still
believes it owns is how people lose files. There is a `force` option that
overrides it; **we do not use it**, and the kernel's own documentation says why:

> force — Forces the driver to mount partitions even if volume is marked dirty.
> Not recommended for use.

So instead AquariusOS mounts it **read-only** and says so in the log. You can
open your files and copy footage off it; you just cannot write to it.

**The fix, in Windows:** Control Panel → Power Options → "Choose what the power
buttons do" → untick "Turn on fast startup". Or hold **Shift** while clicking
Shut Down, once.

### 3. A BitLocker drive is skipped entirely

`ntfs3` cannot read BitLocker, so a BitLocker-encrypted Windows drive is on the
never-touch list. It will not appear. Unlocking one on Linux needs `dislocker` or
`cryptsetup`, neither of which is something a boot service should be doing
without being asked.

---

## Checking it worked

```bash
# What did the boot-time mounter do, and why did it skip what it skipped?
systemctl status aquarius-internal-automount
journalctl -u aquarius-internal-automount

# Run it again without rebooting (safe at any time — anything already
# mounted is skipped).
sudo systemctl restart aquarius-internal-automount

# What is mounted now?
lsblk -o NAME,FSTYPE,LABEL,SIZE,MOUNTPOINTS

# What is the desktop-icon program doing?
systemctl --user status aquarius-desktop-volumes
journalctl --user -u aquarius-desktop-volumes
```

## Running the tests

```bash
./tests/test-aquarius-automount.py          # which drives are safe to mount
./tests/test-aquarius-desktop-volumes.py    # which icons appear, whose files are safe
```

Both also run in CI on every pull request that touches either script —
`.github/workflows/drive-tests.yml`.
