# Check for Update — how AquariusOS updates itself

*Updated 2026-10-21.*

## GNOME Software is the one place updates come from

*Decided 2026-10-21 (Royce: system updates should come through the Software
app).*

Open **Software → Updates**. That one page updates AquariusOS itself, your
Flatpak apps, and supported device firmware. **Check for Update** and typing
`aq update` both open that page now.

What happens, in order:

1. Software checks in the background and **downloads** a new AquariusOS on its
   own — but never over a connection marked as metered (a phone hotspot).
2. When it is downloaded, Software shows a notification and a
   **Restart to update** button.
3. **You choose when to restart.** Nothing on AquariusOS restarts the computer
   by itself. Your work, files and home folder are untouched; the old version
   stays on the disk and is in the boot menu if you ever need it.

### What we switched off, and why

Fedora's base image switches on a timer called
`bootc-fetch-apply-updates.timer`. It downloads a new system **and reboots the
machine without asking** — in the middle of an export, if that is when it
fires. On the bench (2026-10-21) it also sat for 46 hours waiting behind a
stuck Software job, holding the update lock the whole time.

AquariusOS switches it off two ways, both checked by
`build_files/77-updater.sh` on every build:

* `/usr/lib/systemd/system-preset/10-aquarius-updates.preset` says *disable* —
  what a fresh install reads;
* the timer and its service are **masked** in the image's `/etc` — that is
  what reaches a machine installed before 2026-10-21, because a mask beats the
  "switched on" link Fedora already left there.

Software's own settings are written down in
`system_files/usr/share/glib-2.0/schemas/zz1-aquarius-50-software.gschema.override`
(`allow-updates`, `download-updates`, `download-updates-notify` on;
`refresh-when-metered` off). They match GNOME's defaults today; writing them
down means a future GNOME cannot quietly change how AquariusOS updates.

### The terminal uses the same engine — the choice, written down

There were two ways to make Software and our own updater agree: make our
window open Software, or make both use the same engine. **We did both**, because
each closes a different hole:

| | What it runs now | What it ran before |
| --- | --- | --- |
| **Check for Update** / `aq update` | Opens Software's Updates page (`gnome-software --mode=updates`) | Our own window, running `bootc upgrade` |
| `aq update check` | Reads only, no password (unchanged) | Same |
| `aq update apply` | `pkexec rpm-ostree upgrade` | `pkexec bootc upgrade` |

Why `rpm-ostree upgrade` and not `bootc upgrade`:

* **It is Software's own engine.** Software's image plug-in and
  `rpm-ostree upgrade` both hand the job to the same system service
  (`rpm-ostreed`), which does one job at a time. A terminal update started
  while Software is busy waits its turn instead of fighting it for the lock.
  `bootc upgrade` is a second engine beside it — the one that sat for 46 hours.
* **It works on a machine with layered packages.** `bootc upgrade` refuses
  outright ("Deployment contains local rpm-ostree modifications").
  `rpm-ostree upgrade` carries the layers along.

`aq update apply` also looks first: if the update service is already busy
(usually Software refreshing), it says so in plain words and stops, rather than
sitting silently in a queue. `aq update check` and `aq update apply` both name
any layered packages and point at the guide for removing them
(`bench-rebase.md`, *"Extra packages layered on top of the image"*).

The old AquariusOS window still exists as `aquarius-updater --window`, for the
bench and as a fallback if Software were ever missing. Its Update button uses
the same `rpm-ostree upgrade`.

### History

*2026-10-18:* the image gained `gnome-software-rpm-ostree` (step 40), and step
90 removes GNOME Software's DNF5 and PackageKit plug-ins, which try to write to
the read-only system. Authentication uses the existing system policy; no
password-free rule was added. On the bench the plug-in was first installed as a
local layer; once an image containing it is running, that layer is redundant —
see `bench-rebase.md` for how to drop it.

---

## The one-paragraph version

AquariusOS updates as **one whole sealed thing**, not as hundreds of little
pieces. Open **Software → Updates** (or pick **Check for Update**, or type
`aq update`). In a terminal, `aq update check` tells you which version you
have and whether there is a newer one. **Checking never asks for a password.**
If there is an update, one button installs it, and *that* asks for your password
once. Then you restart when you feel like it. The old version stays on the disk,
so if a new one ever misbehaves you pick the previous one from the boot menu.

---

## The two halves, and which one costs you a password

| | Checking | Updating |
| --- | --- | --- |
| What it does | Reads two things and compares them | Downloads and writes the new system |
| Password? | **No. Never.** | **Yes — once.** |
| How long | A second or two | A few minutes |
| Changes anything? | No | Yes, but not until you restart |

That split is the whole design. Looking is free; changing your computer asks
permission. A window that made you type a password just to *look* would be a
window nobody opens.

---

## What "checking" actually does

Your computer is running one specific sealed image, and that image has a
fingerprint — a long unique code that belongs to that exact build and no other.
So the check is two ordinary questions:

1. **What am I running?** The system is asked which image it booted and what its
   fingerprint is. Any account is allowed to ask; nothing is downloaded.
2. **What is published?** The place the image comes from is asked for the
   fingerprint of the newest build, and its version label.

Two fingerprints the same → you are up to date. Different → there is an update,
and the window can tell you which version is on offer.

Comparing fingerprints rather than dates or names matters: a name can be reused,
a date can be wrong, but two builds with the same fingerprint are the same
build. It is the only comparison that cannot quietly lie to you.

---

## The five things it can say

| It says | It means | What to do |
| --- | --- | --- |
| **You're up to date** | Your fingerprint and the published one match. | Nothing. |
| **An update is available** | They differ. It shows the version you have and the one on offer. | Press **Update** (one password), then restart when convenient. |
| **An update is ready** | A newer version is already downloaded and waiting. | **Restart** to finish. No password, no download. |
| **Couldn't check** | The update server could not be reached — usually the internet is off or a network is blocking it. | Reconnect and choose **Check again**. |
| **Couldn't confirm the update status** | Something about the check itself could not be read. | Try again later, or just press Update — it is always safe. |

⚠️ **The last two are deliberately different sentences.** Only a genuine network
failure is ever called an internet problem. Anything else the check cannot read
says so honestly. An unreadable check is **never** reported as "you're up to
date" — a machine silently sitting on an old version because a check failed
quietly is worse than a machine that admits it does not know.

### Why that rule is written down here

On 13 September 2026 the bench found the check telling an online machine that
its internet was down (finding U1). The check was running a command that quietly
refuses to run unless you are the administrator, and the refusal was being read
as "could not reach the server". The fix was both halves of the rule above:
check without ever needing to be the administrator, and never turn a
"you're not allowed" into a "your internet is broken".

---

## Doing the update

*This section describes the terminal (`aq update apply`) and the fallback
window (`aquarius-updater --window`). In Software, press **Download** /
**Restart to update** instead.*

Press **Update**. One password prompt appears — the standard system one — and
then the download and install run with their full text visible under
**Details** if you want to watch. Nothing about your running computer changes
while it works; the new version is prepared beside the old one.

When it finishes the window says **Update ready** and offers **Restart now** or
**Later**. Later is a real option: you can keep working for days. The new
version takes effect the next time the machine starts.

In a terminal the same two halves are:

```
aq update check      # no password
aq update apply      # one password, then: sudo systemctl reboot
```

---

## If something goes wrong after an update

Restart, and at the boot menu pick the previous entry. The old version was never
deleted. Your files, settings and home folder are untouched by any of this —
updates replace the system, not your work.

---

## For whoever maintains this

* The window and the terminal are **one program**:
  `system_files/usr/libexec/aquarius-updater`. With no arguments it opens
  GNOME Software's Updates page; `--window` draws our own window; it also
  runs headless for `aq update check` / `aq update apply` and for the build's
  `--dry-run` rehearsal.
* The decision lives in three pure functions — `parse_local`,
  `parse_published`, `decide` — that take the two answers as text and return one
  of five states (`up-to-date`, `available`, `restart-required`, `offline`,
  `unknown`). They touch nothing, so `tests/test-updater.py` can prove the
  wording rule above with canned answers and no system underneath.
* Applying is `pkexec rpm-ostree upgrade` (since 2026-10-21; it was
  `pkexec bootc upgrade`), one prompt — the same engine as GNOME Software.
  `apply_command()` is the one place it is spelled, and the test proves it
  never goes back to bootc.
* `parse_local` also reads two more facts: `layered` (anything added on top of
  the image) and `busy` (the update service is mid-job). Both are covered by
  `tests/test-updater.py`.
* Step `build_files/77-updater.sh` checks all of it in the image and runs the
  test there.
* Nothing a person reads may name another Linux or the tools underneath. Those
  names belong only in the collapsed **Details** log.
