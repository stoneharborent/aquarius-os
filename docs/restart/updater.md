# Check for Update — how AquariusOS updates itself

*Written 2026-09-13. Assumes you have never used Linux.*

---

## The one-paragraph version

AquariusOS updates as **one whole sealed thing**, not as hundreds of little
pieces. Pick **Check for Update** from the Aquarius logo menu (or type
`aq update check` in a terminal) and a small window tells you which version you
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
  `system_files/usr/libexec/aquarius-updater`. It draws a window, and it also
  runs headless for `aq update check` / `aq update apply` and for the build's
  `--dry-run` rehearsal.
* The decision lives in three pure functions — `parse_local`,
  `parse_published`, `decide` — that take the two answers as text and return one
  of five states (`up-to-date`, `available`, `restart-required`, `offline`,
  `unknown`). They touch nothing, so `tests/test-updater.py` can prove the
  wording rule above with canned answers and no system underneath.
* Applying is unchanged and stays unchanged: `pkexec bootc upgrade`, one prompt.
* Step `build_files/77-updater.sh` checks all of it in the image and runs the
  test there.
* Nothing a person reads may name another Linux or the tools underneath. Those
  names belong only in the collapsed **Details** log.
