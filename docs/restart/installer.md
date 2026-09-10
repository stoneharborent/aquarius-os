# The installer screens — what says AquariusOS, what still says Fedora, and why

*Written 2026-09-05. Assumes you have never used Linux. This is the companion to
[`boot-branding.md`](boot-branding.md), focused only on the **installer** — the
program that runs off the USB stick and writes AquariusOS onto a computer's disk.*

> **Not to be confused with [`installer-app.md`](installer-app.md)**, which is about
> **Aquarius Installer** — the app that installs *other apps* once AquariusOS is
> already running. This page is about installing the operating system itself.

---

## The one-paragraph version

When you boot the AquariusOS USB stick, the installer's **words** already say
AquariusOS — its title, its headings, its boot menu, and the name the stick shows
on a Mac or Windows machine. Its **pictures** — the small logo in the corner of
the installer's own pages — are still Fedora's. That is not a setting we forgot
to flip. It is a boundary in how the installer is built, and closing it is a
separate, larger job. This page explains exactly what is branded, what is not,
and what each of the two real fixes would cost, so the decision can be made on
purpose rather than by accident.

> **The rest of this page is about the installer's LOGO** — a cosmetic gap that
> is still open. There was also, briefly, a much bigger problem: no ISO could be
> built at all. That is fixed, and the fix is recorded in the next section so it
> cannot quietly come back.

---

## RESOLVED — the ISO could not be built at all (2026-09-06)

### What you saw

Every ISO build failed within the first minute, in the depsolve step, with:

```
Errors during downloading metadata for repository 'terra':
  - Curl error (37): Could not read a file:// file for
    file:///etc/pki/rpm-gpg/RPM-GPG-KEY-terra44
error: cannot build manifest: cannot depsolve: ... Failed to retrieve GPG key
for repo 'terra'
```

(The failing run was `34012037986`. Both variants failed the same way — this was
a total block on R5's whole premise that a stranger can install from a USB stick.)

### Why it happened, in plain English

As the section below explains, to build the installer image-builder assembles a
small scratch environment, and to do that it reads **this image's own repository
files** (the catalogues in `/etc/yum.repos.d/`) and asks each one for its
listing. It does this in an environment that does **not** carry this image's
local GPG key files.

Reading a repository's listing normally needs no key. But a repository can
**sign its listing** (`repo_gpgcheck=1`), and then the key is needed just to read
it. The **Terra** repository — added by the gaming layer (Phase R4) to install
Steam and `umu-launcher` — does exactly that, and names its key by a **local
file path**:

```
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-terra44
```

That file exists on a finished, installed machine. It does **not** exist in
image-builder's scratch environment. So the build tries to read a file that is
not there, gets "Curl error (37)", and stops before it really starts. This is
[osbuild/bootc-image-builder#1188](https://github.com/osbuild/bootc-image-builder/issues/1188)
— the same class of bug that forced the old Bazzite line onto Titanoboa. A
maintainer note on that issue explains the depsolver autodiscovers every
repository file under the mounted image's `/etc/yum.repos.d/`, so this bites
**even when the repository is switched off** — and indeed Terra was `enabled=0`
in the image and its listing was fetched anyway.

### Why RPM Fusion did NOT cause this (and is deliberately left alone)

RPM Fusion also uses a `gpgkey=file://` local key, and it has been enabled since
Phase R1 — yet the ISO only broke once the gaming layer was added. The reason is
one setting: RPM Fusion does **not** sign its listing (`repo_gpgcheck=0`). So
image-builder never needs RPM Fusion's key to read the listing, and that key is
only ever needed later, on the installed machine (where the file really is
present), when someone layers a package by hand. RPM Fusion is therefore useful
at runtime and harmless to the ISO, so it is kept exactly as it is. The exact
trap is the **pair**: a signed listing (`repo_gpgcheck=1`) with a local-path key
(`gpgkey=file://`), and nothing else.

### The fix

Terra has no runtime purpose on AquariusOS: a bootc machine updates by
downloading a whole new image we build, never from a repository on the user's
computer, and the two packages Terra provided are already baked in. So Terra is
now **removed from the image entirely** once Steam and `umu-launcher` are
installed — the `terra-release` package, its `terra*.repo` file and its key are
all taken back out. See [`build_files/68-gaming.sh`](../../build_files/68-gaming.sh),
step "3b", and [`gaming.md`](gaming.md). RPM Fusion was **not** changed:
converting its key to `https://` was considered and rejected as an unnecessary
change that would also weaken its offline package verification on the installed
machine.

### What stops it coming back

Two independent guards, both reading the real files in the finished image (never
timestamps):

1. **Inside the gaming step.** `68-gaming.sh` proves, right after removing Terra,
   that no Terra repo file or key survived and that no repository file pairs a
   signed listing with a local-path key.
2. **A dedicated CI step**, "Check no repository file can break the installer ISO
   build" in [`build.yml`](../../.github/workflows/build.yml), scans every
   `/etc/yum.repos.d/*.repo` in the built image on every build and fails if any
   section combines `repo_gpgcheck=1` with `gpgkey=file://`, or if any Terra repo
   file is still present. So even a new repository added years from now cannot
   re-break the ISO unnoticed.

> If a future feature genuinely needs a repository with a **signed** listing to
> stay in the shipped image, the guard will (correctly) stop the build; the fix
> then is to point that repository's `gpgkey=` at the upstream `https://` key URL,
> which image-builder *can* fetch. Terra did not need that because it did not need
> to stay at all.

---

## What a person actually sees, screen by screen

| When | What they see | Says AquariusOS? |
| --- | --- | --- |
| Plug the stick into a Mac/Windows PC | The disc's name in Finder/Explorer | **Yes** — `AQUARIUSOS` |
| Boot the stick (UEFI or BIOS) | The boot menu title | **Yes** — `AquariusOS 44` |
| The installer's own window | The **title / headings / button text** | **Yes** — driven by the product name, taken from our `/etc/os-release` |
| The installer's own window | The **logo picture** in the sidebar / header | **No** — still Fedora's mark |
| After it finishes, the installed machine | Everything — boot splash, login, desktop, About | **Yes** — this is the whole rest of the project |

So the gap is narrow and specific: **the logo picture on the installer's own
pages, seen once, while installing.** Everything else about the installer, and
everything about the machine afterwards, says AquariusOS.

---

## Why the words are ours but the pictures are not

The installer program is called **Anaconda**. When we build the USB stick, the
tool that does it (osbuild's **image-builder**, in its `anaconda-iso` mode) does
**not** just copy our operating system onto the stick. It builds a *second,
separate* little system next to it — a scratch environment whose only job is to
run Anaconda long enough to install the real thing. That scratch environment is
assembled fresh, and this is the crux:

> image-builder "inspects the bootable container to find the repository
> definitions and then downloads and installs the relevant package from there."
> — osbuild's own description of the `anaconda-iso` type
> (<https://supakeen.com/weblog/installer-types-for-bootc/>)

In plain words: to decorate Anaconda, image-builder reads *which Fedora servers
our image trusts*, and then **downloads Fedora's artwork package
(`fedora-logos`) brand new** into that scratch environment. It never looks at the
copy of the artwork sitting inside our image. So no matter what we put at those
picture paths in our own image, the stick's Anaconda keeps Fedora's picture.

The **words** are different because they do not come from a package. image-builder
reads the product **name** straight out of our image's `/etc/os-release` (which
says `AquariusOS`) and writes it into the file Anaconda reads to learn what it is
installing (its `.buildstamp`). That is why every heading already says AquariusOS.
Verified by reading it back out of the ISO build log (run 33775709207):

```
org.osbuild.buildstamp   "product": "AquariusOS", "version": "44"
                         "isolabel": "AQUARIUSOS"
org.osbuild.grub2.iso    "product": { "name": "AquariusOS", "version": "44" }
```

---

## What we DID do on the way past

Two things, both real, neither of which touches the stick's Anaconda picture.

1. **The ISO's own name is ours.** `disk_config/iso.toml` sets `volume_id`
   (`AQUARIUSOS`), `application_id` (`AquariusOS`) and `publisher` (`Stone Harbor
   Entertainment`). The build now checks all three, so they cannot quietly drift
   back to Fedora.

2. **The in-image installer artwork is complete and correct.** There is a *second*
   way to meet Anaconda that has nothing to do with the stick: running it on a
   machine that is already up (the installer is part of this image's files). That
   copy we CAN brand, and we do — but Fedora 44 had moved the target. It used to
   keep one `sidebar-logo.png` at `/usr/share/anaconda/pixmaps/`; Fedora 44's
   `fedora-logos` ships it inside per-product folders instead
   (`/usr/share/anaconda/{atomic,cloud,server,silverblue,workstation}/`), and puts
   nothing at the old flat path. Our replacement had been aimed at the old path
   and so had been doing nothing. `build_files/80-boot-branding.sh` now finds
   every `sidebar-logo.png` under `/usr/share/anaconda/`, plus
   `anaconda_header.png` and the two boot splashes, replaces each with our white
   wordmark, and the build asserts every present file is ours.

The `topbar-bg.png` in each of those folders is a plain background strip, not a
logo, so it is left as Fedora ships it — replacing a background with a logo looks
wrong.

---

## The two real ways to brand the stick's Anaconda — scoped, not built

Neither of these is done. Both are written down so the choice is deliberate.

### Route A — ship a small `aquarius-logos` package

**The idea.** Anaconda's picture comes from whatever package provides the artwork
in the scratch environment. Fedora's `fedora-logos` provides it and also claims
the virtual names other software asks for — it `Provides: system-logos`,
`gnome-logos`, `redhat-logos`. If we publish our own tiny RPM,
`aquarius-logos`, that carries our pictures at Fedora's exact filenames,
`Provides: system-logos` (and the others), and `Obsoletes: fedora-logos`, and we
add the repository that hosts it to our image, then when image-builder depsolves
the scratch environment it would pull **ours** instead of Fedora's.

**What it takes, honestly:**

- **Build an RPM.** A `.spec` file, our pictures at every path `fedora-logos`
  owns under `/usr/share/anaconda/` and `/usr/share/pixmaps/`, at the **right
  dimensions** for each (they are not all the same size), plus the `Provides` and
  `Obsoletes` lines. This is a real packaging task, not a one-liner.
- **Host it where the build can reach it.** A COPR project (Fedora's free build
  service) is the least-effort home; a self-hosted dnf repo is the other. Either
  way the repo file has to be added to our image so image-builder sees it.
- **Prove the depsolver actually picks ours.** `Obsoletes` usually wins, but the
  installer package set may name `fedora-logos` explicitly, in which case a
  conflict has to be resolved rather than assumed. This needs an actual ISO built
  and read back — it cannot be trusted on paper.
- **Carry it forever.** Every time Fedora reorganises `fedora-logos` (as F44 just
  did, moving the sidebar logo), ours has to follow or it silently goes stale.

**The risk that makes this "later, not now":** an `aquarius-logos` that is subtly
wrong — a missing provide, a filename Fedora renamed, a size mismatch — produces
either a failed ISO build or an installer with broken/blank artwork, and the
failure shows up only in a full 30-40 minute ISO build. This is exactly the
"fragile package built blind" that is not worth doing on spec. It is worth doing
**as its own ticket**, with a bench ISO test at the end.

**Cost estimate:** roughly half a day to build and host the package, plus one or
two full ISO build-and-inspect cycles to prove selection. Ongoing: a few minutes
each time Fedora reshuffles its logos.

### Route B — switch to the `bootc-installer` image type

**The idea.** osbuild has a newer installer type, `bootc-installer`, that is meant
to replace `anaconda-iso` (which is now marked deprecated). Instead of
image-builder assembling the scratch environment for you from downloaded
packages, **you** build a small installer container yourself — a `Containerfile`
that installs Anaconda and, crucially, **our artwork baked in** — and image-builder
wraps that. Because the artwork is in a container we control, it is simply ours.

**What it takes:**

- A new `Containerfile` for the installer environment (Anaconda + its install-env
  dependencies + our logos), built and published like any other image.
- Rewiring `.github/workflows/build-iso.yml` from the current
  `types: anaconda-iso` call to the `bootc-installer` flow, passing our installer
  container and the payload image reference.
- Re-testing the whole ISO path, because this changes how the stick is built, not
  just what is on it.

**Why it is the "right" long answer but not today's:** it is the direction the
tool is going, and it removes the download-Fedora's-artwork problem at the root.
But it is a change to the build *architecture*, it touches a Standing Decision
(the ISO is built by `bootc-image-builder`/`anaconda-iso` today — see the project
`CLAUDE.md`), and it is Royce's / Fable's call, not a polish-task change.

**Cost estimate:** one to two days, most of it in getting the installer container
right and re-proving the end-to-end ISO on the bench.

---

## The recommendation

**Leave the stick's Anaconda logo as Fedora's for now.** It is one small picture,
seen once, on the way to a machine that then says AquariusOS on every screen for
the rest of its life. The words on those same installer pages already say
AquariusOS. Revisit this — via **Route A** first, as a self-contained ticket with
a bench ISO test — if AquariusOS is ever handed to somebody who is not Royce, or
whenever the `bootc-installer` type is picked up for other reasons (then get it
for free via **Route B**).

---

## How to verify the current state

**On the Mac, in the repo** (the ISO's own name):

```bash
grep -E '^(volume_id|application_id|publisher)' disk_config/iso.toml
# volume_id = "AQUARIUSOS"
# application_id = "AquariusOS"
# publisher = "Stone Harbor Entertainment"
```

**On a built ISO, or in the ISO build log** (the installer's words):

```
org.osbuild.buildstamp   "product": "AquariusOS"
                         "isolabel": "AQUARIUSOS"
```

**On the bench, after booting the stick:** the installer's headings say
AquariusOS; the little logo in its corner is still Fedora's. That is expected and
is what this page is about.

---

## Where to go next

- **Everything else about branding the boot path and the running machine:**
  [`boot-branding.md`](boot-branding.md)
- **Moving the bench over and first-boot checks:** [`bench-rebase.md`](bench-rebase.md)
- **The ISO build workflow itself:** `.github/workflows/build-iso.yml`
- **The ISO configuration:** `disk_config/iso.toml`
