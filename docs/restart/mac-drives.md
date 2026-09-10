# Reading a Mac drive on AquariusOS

*Written 2026-09-09. Assumes you have never used Linux.*

---

## The one-paragraph version

Plug a drive that was formatted on a Mac into this computer and it appears — in
the dock, and in Files — exactly like any other drive. You can open it, look
through it, and copy everything off it.

**You cannot write to it.** Not save, not rename, not delete, not "just this one
small change". That is not a setting waiting to be switched on and it is not a
half-finished feature: it is the honest ceiling, and the rest of this page
explains why, so that you never wonder whether you are missing something.

---

## Why read-only, in plain English

Apple has never published how APFS — the way a Mac lays files out on a disk —
actually works. Every program on Linux that can read a Mac drive was written by
people who took Mac drives apart and worked it out. Reading something you have
worked out is fine: if you get it wrong, a file fails to open and you know.

Writing is different. If you get *writing* wrong, the drive still looks perfect.
The damage shows up weeks later, on the drive that had the only copy of
something. Nobody on Linux — not the free programs, not the paid ones — can
promise otherwise, because none of them has ever seen Apple's real rules.

So AquariusOS makes the promise it can keep: **a Mac drive is a rescue path.
Plug it in, take your files off it, and do your actual work on a drive this
computer is allowed to write to.**

### The storage rule, once, so you never have to think about it again

| Format | Use it for | AquariusOS can |
| --- | --- | --- |
| **APFS** (Mac) | drives coming *off* a Mac | **read only** |
| **exFAT** | shuttle drives, camera cards — anything that has to work on a Mac AND a PC | read and write |
| **btrfs / ext4** (Linux) | drives that live on this computer | read and write |

If a drive is going back and forth between your Mac and AquariusOS, **format it
exFAT on the Mac.** That is the whole answer. Both computers write it happily,
cameras and card readers understand it, and nothing on this page applies.

---

## What actually happens when you plug one in

1. You plug it in.
2. This computer notices it is a Mac drive and quietly gives *you* — the person
   sitting at the keyboard — permission to read that one drive. (No password.
   The same thing happens with your webcam.)
3. AquariusOS looks at what is inside it. A Mac drive is a box that can hold
   several **volumes**; an external drive you formatted on a Mac normally holds
   exactly one. A Mac's own internal disk holds five or six, and four of those
   are Apple's own machinery — Preboot, Recovery, VM — which are skipped,
   because there is nothing on them anybody would open.
4. Each real volume appears as its own tile in the dock, and in Files, under the
   name it has on the Mac.
5. When you are finished: right-click its tile → **Eject**, same as any drive.

No terminal. No password. Nothing to set up.

---

## If it is locked (FileVault)

If you switched FileVault on for that drive on the Mac, nothing on earth can
read a byte of it without the password — that is the point of FileVault.

So instead of nothing happening, a notification appears:

> **This Mac drive is locked**
> *Archive* is protected with FileVault. Open Aquarius Drive Unlock to type its
> password and read it.

Press **Unlock…**, type the password you use for it on the Mac, and it opens —
read-only, like any other Mac drive.

**The password is never saved.** Not in a file, not in a keyring, not between
plug-ins. Next time you plug it in, you type it again. That is deliberate: a
password kept on a computer that is not the one it protects is a password that
has escaped.

If you prefer to type, `aq drive unlock "Archive"` asks the same question in a
terminal.

---

## The one kind of Mac disk that will never work

**The built-in disk out of a Mac with a T2 chip, or any Apple-silicon Mac
(M1, M2, M3, M4 …).**

Those disks are encrypted by a key that lives *inside Apple's own hardware* and
never leaves it. It is not a password you have and forgot; there is no password.
The only machine that can read one is the Mac it came out of.

If you have files on one, get them off using that Mac — over the network, or
onto an exFAT drive. Nothing on a PC, running any operating system, can help.

## Two smaller things that can go wrong, and are not your fault

- **A file will not open, and the others do.** APFS can squeeze a file down
  using a method (LZFSE) that the reader AquariusOS uses does not understand.
  It is rare, and it affects individual files rather than the drive. Copy that
  one off using the Mac.
- **A folder is empty here and is not on the Mac.** Very likely a "firmlink" —
  a Mac trick that makes one folder appear in two places. The reader ignores
  them. The real folder is somewhere else on the same drive.

---

## The bench checklist

*Run this on the bench PC after `bootc upgrade`. It is written to be followed in
order; every step says what "good" looks like.*

**You will need:** one Mac-formatted external drive with at least one large
video file on it (a few gigabytes), and the Mac that formatted it.

1. **Plug it in.** Within a few seconds a tile should appear at the right-hand
   end of the dock.
   *If nothing appears, stop here and go to "If it does not appear" below.*

2. **Open it from the dock.** Click the tile. Files should open on the drive's
   contents, with the folders you expect.

3. **Check it says read-only.** In a terminal:
   ```bash
   aq drive list
   ```
   The drive should be listed as **"Mac drive — read only"**, with a mount point
   under `/run/media/<you>/`.

4. **Prove it really is read-only.** In Files, try to make a new folder on the
   drive, or drag a file onto it. It must refuse. *This is a pass, not a
   failure.*

5. **Copy a large video file off it, and prove the copy is perfect.** This is
   the step the whole feature exists for.
   ```bash
   # On AquariusOS — copy it to your home folder:
   cp "/run/media/$USER/<drive>/<big file>.mov" ~/Videos/

   # Then compare the two, byte for byte:
   sha256sum "/run/media/$USER/<drive>/<big file>.mov"
   sha256sum ~/Videos/"<big file>.mov"
   ```
   **The two long strings of letters and numbers must be identical.** If they
   are, the copy is exact — not "looks fine", exact.

   For extra confidence, run `shasum -a 256 "<big file>.mov"` on the Mac against
   the original and check it matches too.

6. **Open the copy in an editor.** Drop `~/Videos/<big file>.mov` into DaVinci
   Resolve or Aquarius Editor and scrub through it. It should behave exactly
   like a file that never went near a Mac drive.

7. **Eject it properly.** Right-click the tile → **Eject**. The tile should
   disappear. Then check the folder is gone too:
   ```bash
   ls /run/media/"$USER"/
   ```
   *If Eject does nothing, try `aq drive eject "<drive>"` and note which one
   worked — that difference matters and is written up below.*

8. **Unplug it, and plug it back in.** The tile should come back.

9. **⚠️ The nasty one: unplug it DURING a copy.** Start copying a big file off
   it and pull the cable out half way.
   - The copy must fail with an error, not hang the machine.
   - The tile must disappear from the dock within a few seconds.
   - `ls /run/media/"$USER"/` must show the folder is gone.
   - Plugging it back in must bring it back, and a fresh copy must succeed.

   Write down anything that hangs, needs a reboot, or leaves a folder behind.

10. **If you have a FileVault drive, do 1–8 with it too**, plus: the
    notification appears, **Unlock…** opens the window, a *wrong* password says
    so and lets you try again, and the right one opens the drive.

11. **Restart with the drive still plugged in.** After logging back in, the tile
    should be there without touching anything.

Record what you find in `docs/design/bench-run-<date>.md`, as usual.

---

## If it does not appear

Work down this list. Each command's answer tells you which step to read next.

```bash
# 1. Does this computer see the drive at all?
lsblk -o NAME,SIZE,FSTYPE,LABEL
```
Look for a line whose **FSTYPE is `apfs`**.
*Nothing there at all?* Then the drive is not reaching the computer, and this
page is the wrong one — go to [`usb4.md`](usb4.md), which is about exactly that.

```bash
# 2. What does AquariusOS think is mounted, and what is locked?
aq drive list
```

```bash
# 3. What did the drive-mounting agent actually do? One line per drive.
journalctl --user -b -u aquarius-automount
```
This is the most useful command on the page. It says, in plain sentences, what
it found and what it could not do — "Archive on /dev/sdb2 is locked with
FileVault", "could not mount SHOOT 2026 (/dev/sdb2): …".

```bash
# 4. Can the reader itself see the drive? (put your own device name in)
apfsutil /dev/sdb2
```
It should print one paragraph per volume. If it says **"Error opening device"**,
this computer has not given you permission to read that drive — which usually
means the udev rule did not apply. Check it is there:
```bash
ls -l /usr/lib/udev/rules.d/70-aquarius-apfs.rules
ls -l /dev/sdb2          # you should appear in a "+" ACL: use `getfacl /dev/sdb2`
```

```bash
# 5. Does the folder drives appear in exist, and is it yours?
ls -ld /run/media/"$USER"
```
It should exist and belong to you. If it does not exist, the little program that
makes it at login did not run:
```bash
systemctl status "user@$(id -u).service" | head -20
```

```bash
# 6. Is the agent running at all?
systemctl --user status aquarius-automount
```

```bash
# 7. And the rehearsal, which changes nothing and states its own rules:
/usr/libexec/aquarius-automount --dry-run
```

---

## How it is built (for whoever maintains this)

Seven small pieces, none of them privileged:

| | |
| --- | --- |
| `apfs-fuse`, `apfsutil` | Fedora's own package — a 2020 snapshot of sgan81/apfs-fuse. Read-only by design. `apfsutil` lists a drive's volumes and says which are FileVault; `apfs-fuse` does the mounting. |
| `/usr/lib/udev/rules.d/70-aquarius-apfs.rules` | one line: an APFS device gets `TAG+="uaccess"`, so logind gives the person at the screen an ACL on it. **The number matters** — after 60 (which works out the filesystem type), before 73 (which acts on the tag). |
| `/usr/libexec/aquarius-media-dir` + a `user@.service` drop-in | makes `/run/media/<you>` at login and makes it *yours*, so an unprivileged program can create a folder to mount onto. udisks2's own version is read-only to you. |
| `/usr/lib/aquarius/python/aquarius_apfs.py` | reads what `apfsutil` prints, and decides which volumes are Apple's machinery. Shared, so the mounting side and the unlocking side can never disagree. |
| `/usr/libexec/aquarius-automount` | the drive agent. An APFS device takes the Mac path instead of asking udisks2, and unplugging closes the mount — nothing else on the computer would. |
| `/usr/libexec/aquarius-drive-unlock` | the FileVault notification, window and terminal prompt. The password goes in through a pretend terminal, never on a command line. |
| `aq drive list / eject / unlock` | the typed front door. |

Built and checked by `build_files/82-apfs-drives.sh`; exercised by
`tests/test-automount-mount.py` (against three captured `apfsutil` listings and
a fake bus) and `tests/test-media-dir.sh`.

### Why no privilege anywhere

AquariusOS is never installed on APFS — Linux cannot write it, so no installer
can offer it. So *"this device is APFS"* is, on this computer, the same
statement as *"this device is not the system disk"*. That is what makes it safe
to hand an APFS device to the person at the keyboard, and it is why this feature
needs no service of ours, no polkit rule, no setuid program of ours and no
password.

### The one thing to watch on the bench

Putting a Mac drive away from the dock goes `gio mount -u -f <folder>` →
`umount <folder>`, and that only works because of a rule in util-linux: since
version **2.34**, `umount` lets you unmount a FUSE filesystem when the kernel's
mount table says the mount is yours (`user_id=`). apfs-fuse's mounts always
carry that, Fedora 44 is far past 2.34, and `build_files/82-apfs-drives.sh`
reads both the version and the setuid bit back out of the finished image.

If step 7 of the checklist above shows that the dock's Eject does *not* work
while `aq drive eject` does, that rule is not applying, and the fix is one line
in the shell: `aquarius-shell/components/dock/DockDrive.qml` currently runs

```qml
Quickshell.execDetached(["gio", "mount", "-u", "-f", root.mountPath]);
```

and would become

```qml
Quickshell.execDetached(["aq", "drive", "eject", root.mountLabel]);
```

which routes both kinds of drive through the one command that handles both.
Nothing else in the shell would change.
