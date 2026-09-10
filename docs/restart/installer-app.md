# Aquarius Installer — the app that installs anything

*Written 2026-09-09, for somebody who has never used Linux.
Nothing here assumes you know what a package or a container is.*

> **Not to be confused with [`installer.md`](installer.md)**, which is about installing
> **AquariusOS itself** onto a computer. This page is about the app that installs
> **other apps**, once AquariusOS is already running.

---

## The three-second story

You downloaded something. You double-click it.

One window opens. It says what the thing is, and one sentence about where it is going
to go. You press **Install**. A moment later the icon is in your apps and you can open
it.

That is the whole thing, and it is the same three seconds whatever you downloaded.

---

## Why this is worth an app at all

On a Mac, you double-click the thing you downloaded and it installs. On Linux, the
same act has always been a research project. What you downloaded might be:

- an **`.rpm`** — a package
- a **`.deb`** — also a package, but built for a different family of Linux
- an **`.AppImage`** — one file that is the whole app
- a **`.flatpakref`** — a note saying "fetch this app from the app store"
- a **`.tar.gz`** or a **`.zip`** — a folder with a program in it
- a **`.run`** — a program whose job is to install another program
- an **`.exe`** — not Linux at all

...and until now, double-clicking most of those on AquariusOS did **nothing at all**.
No window, no message, no clue. That is the thing this app fixes.

**You never have to know which of those you have.** The window works it out and does
the right thing. There is no menu asking you to choose a method, because choosing a
method is not a thing anybody should be asked to do.

---

## What happens with each kind of file

| What you downloaded | What happens | Password? |
| --- | --- | --- |
| **`.flatpakref`**, **`.flatpak`**, or a link to a Flathub page | It is fetched from Flathub and installed for the whole computer. | Once, asked by the desktop itself |
| **`.AppImage`** | It is opened up and put in your own apps, with its own icon. | No |
| **`.tar.gz` / `.tar.xz` / `.zip`** with a program inside | Same as an AppImage: opened up and put in your own apps. | No |
| **`.rpm`** or **`.deb`** | **The same thing for both**: it is opened up and put in your own apps. Nothing is converted, and the package's own install scripts are never run. | No |
| **`.rpm`** or **`.deb`** that needs parts this computer does not have | It stops and says so, plainly, and offers to look for the app on Flathub instead. Nothing half-installs. | — |
| **`.rpm`** or **`.deb`** that wants to change the operating system | Refused, with the reason. See *What it refuses*, below. | — |
| **`.run`** or **`.sh`** | Refused politely. DaVinci Resolve is the exception and has its own guided flow — open **Install DaVinci Resolve** from your apps. | — |
| **`.snap`** | *"AquariusOS uses Flathub instead"*, with a search for the same app there. | — |
| **`.exe` / `.msi`** | *"This is a Windows program. AquariusOS cannot run it."* | — |
| **`.dmg` / `.pkg`** | *"This is a Mac download. Look for the Linux download on the same page."* | — |

**Dragging a file onto the window does exactly the same thing as double-clicking it.**

### Two file types it deliberately does *not* take over

A **`.zip`** (or a `.tar.gz`) and a **`.sh`** are not usually apps. A zip is far more
often a folder of footage, and a `.sh` is a text file people write and edit. So
double-clicking one of those still does whatever it did before, and Aquarius Installer
does not even appear in the list of apps for them — on purpose, because the desktop
would otherwise quietly make it the default. **Dropping one onto the window works
normally**, and so does `aq apps install <the file>`.

---

## What it refuses, and why that is a good thing

### "This package wants to change the operating system itself."

Some packages are not apps. They are drivers, printer software, VPN clients with a
background service, or pieces that go inside the system itself. On an ordinary Linux
those get installed into the operating system, as an administrator.

**AquariusOS never allows that, and that is why its updates always work.** The operating
system here is one sealed thing that gets replaced whole when it updates. Anything
squeezed into it locally either gets wiped out by the next update or stops the update
happening at all — which is exactly what happened on the bench in September 2026, when
one small extra package stopped a machine updating until it was undone by hand.

So the window says:

> *"This package wants to change the operating system itself. AquariusOS does not allow
> that, so updates always work. If it is a driver or a system service AquariusOS should
> have, it belongs in the image — ask for it."*

That last sentence is the real answer. Things that belong in the operating system get
**built into it**, where they survive every update forever. Ask, and it goes on the list.

### "This app needs parts AquariusOS does not have yet."

Before anything is installed, the window checks that every program inside the package
can actually find the pieces it needs on this computer. Most apps you download — Discord,
Slack, Zoom, Chrome, VS Code, Obsidian — carry everything with them and pass this easily.

A few do not. Rather than install one of those and leave you with an icon that does
nothing when clicked, the window stops and says so, and offers to look for the same app
on Flathub. A later version of AquariusOS will be able to run those apps in a small
environment of their own; that is not built yet, and the window does not pretend it is.

### "No conversion, ever."

There is an old trick on Linux for turning a `.deb` into an `.rpm`. AquariusOS does not
do it and never will: it rewrites the package's list of requirements by guesswork and
produces something that usually does not work and is very hard to tell apart from
something that does. The result you actually wanted — *double-click a `.deb`, it
installs* — is delivered here by opening it up, which is the same act as for an `.rpm`
and works better.

---

## The three things the window is for

### 1. Installing

Covered above. Drop a file on it, or double-click one, and press Install.

### 2. Removing

The main list — **On this computer** — is everything you have: apps you installed with
this window, apps from Flathub, and anything else that got here some other way. Each row
has a **Remove** button.

Pressing it opens one small window that says:

- how much space removing the app frees;
- one tick box: **"Also delete its settings and data"**, with the size beside it. It is
  **off** by default.

Two promises worth writing down:

- **The things you MADE with the app are never touched.** Projects, exports, documents —
  those are yours and are not part of the app, tick box or no tick box.
- **Removing never touches the operating system.** Nothing this window installs is in
  the operating system, so there is nothing in the operating system to remove.

If you leave the tick box unticked and reinstall the app later from the same file, your
settings are where you left them.

Two rows do not have a Remove button, and say why instead:

- **Aquarius Writer** and **Firefox** say *"part of AquariusOS"* — they are inside the
  operating system, the way the file manager is.
- **Aquarius Editor** says *"updates with AquariusOS"*.

### 3. Updating

At the top of the window there is an **Update All** button with a count beside it —
*"Update All (3)"*. Press it and everything that can be updated is, one after another,
with **one** password prompt for the whole run.

- **Apps from Flathub** update from Flathub.
- **Apps you installed from a downloaded file** say *"drop the new file on this window to
  update"*. Dropping a newer file on an app you already have is treated as an **update**,
  not a second copy — your settings stay.
- **The operating system itself is never updated by this button.** That is its own thing,
  with its own notification, because it needs a restart and an app update never does.

If one app fails to update, the rest still go, and the one that failed is named at the end.

---

## The search bar

There is a search bar across the top of the window, always. Type a name and the results
come in three labelled groups, in this order:

1. **On this computer** — what you already have.
2. **AquariusOS suggests** — the same list the first-login window offered you, so you can
   go back and pick up something you skipped. Each row has an **Install** button.
3. **On Flathub** — everything else on the Linux app store.

You can also **paste things into it**:

| You paste | What happens |
| --- | --- |
| a Flathub page link | that app, ready to install |
| a direct link to a `.rpm`, `.deb`, `.AppImage` or `.tar.gz` | it is downloaded, then treated exactly as if you had double-clicked it |

If nothing matches anywhere, it says the one useful thing:
*"Not on Flathub. If you have its Linux download, drop it here."*

---

## What “remove settings too” can identify

The settings checkbox starts unchecked. Installer estimates app settings from the
app's name and the names supplied in its menu entry. It excludes shared folders such
as the app menu, icons and desktop configuration, and ignores shortcuts to other
folders. Old installation notes are checked again when removing an app.

Those names are still estimates: two unrelated apps can use the same settings name.
Leave the checkbox unchecked if you want to preserve their settings. Your installed
program is removed either way.

---

## Where your apps actually live

Everything installed from a downloaded file goes **inside your own home folder**. Nothing
outside your account is touched, which is why it never asks for a password.

```
~/.local/lib/aquarius/versions/<app>/<version>-<unique-copy>/   the app itself
~/.local/lib/aquarius/<app>                       a shortcut to the version in use
~/.local/share/applications/<app>.desktop         its entry in your apps
~/.local/share/icons/hicolor/…/<app>-<unique-copy>.png          its icon
~/.local/share/aquarius/apps/<app>.ini            the note about how it got here
~/.cache/aquarius/installer/                      things it downloaded for you
```

**Why each copy has its own folder.** An update prepares a new copy *beside* the
working one, even when both downloads claim the same version number. It checks the
program and prepares its menu entry, icon and installation note before replacing the
current entries. If opening the file, writing those entries or replacing them fails,
it restores the previous entries and leaves the working app intact. The old copy is
removed only after the replacement succeeds.

If two Installer windows are open, or a terminal command runs at the same time, their
installs and removals wait their turn. An app cannot use the shared `versions` folder
as its own name, and Installer will stop if an unrelated file or folder already uses
its shortcut's name.

These checks cover failures the computer reports while Installer is running. They
are not a guarantee against losing power or forcibly stopping Installer between file
changes. If the filesystem also refuses to restore a previous entry, Installer keeps
both app copies and reports the failure instead of deleting a copy an entry may need.

Apps from Flathub are not in there — Flathub keeps its own, for the whole computer.

---

## How to see what happened

### The log for one install

Every window that is doing something has a **Details** section. It is shut while things
are going well and opens itself the moment something goes wrong, because that is the
moment you need it. There is a **Copy** button beside it.

### The note kept for every app

For each app installed from a file, AquariusOS keeps one small text file:

```
~/.local/share/aquarius/apps/<app>.ini
```

It records the route it came in on, the file it came from and that file's fingerprint,
the version, where it went, where its settings live, and a dated line for every install,
update and removal. You can open it in a text editor. It is what makes *"what happened to
that app?"* a question with an answer, and it is why removing an app is exact rather than
a hunt for files that look related.

### From a terminal, if you like

Everything the window does, `aq apps` does too — they are the same code, so they can
never disagree:

```
aq apps list                         everything on this computer
aq apps what ~/Downloads/thing.deb   what is this file, and what would happen?
aq apps install ~/Downloads/thing.deb
aq apps search obs
aq apps update                       what has something newer waiting
aq apps update --all                 update it all
aq apps remove <name>                take one away
aq apps remove <name> --with-data    ...and its settings too
```

---

## The rules this app follows, all of them

1. **It never changes the operating system.** Not with your permission, not with anybody's.
2. **It never runs a package's own install scripts.** On any other Linux those run as an
   administrator on your computer, at install time, and can do anything at all. Here they
   are not even read.
3. **It never runs `sudo`.** The only password it can ever ask for is the desktop's own
   prompt, once, for an app from Flathub that goes to the whole computer.
4. **It refuses to install or remove as an administrator**, and says why: under `sudo`
   everything would land in the administrator's home folder, where you could never find
   it, and the failure would look like success.
5. **It never converts one kind of package into another.**
6. **It never says an app is installed because a command finished quietly.** It goes and
   looks.
7. **It shows a file's signature and never blocks an unsigned one.** Most good software
   on the internet is unsigned. The window says what it knows, once, in plain words, and
   the decision is yours.

---

## What is deliberately not built yet

- **Running an app in an environment of its own**, for the packages that need libraries
  this computer does not have. The window recognises those today and stops honestly; it
  does not pretend to solve them.
- **Automatic updates for apps installed from a file.** Some downloads carry a "where to
  find a newer one" note; AquariusOS writes it down at install time and does not act on it
  yet. Dropping a newer file on the app's row is the update, today.
- **`.run` installers, and "add this repository" instructions.** Later.
- **Windows apps.** Running Windows software on Linux is a hobby, not a promise, and
  AquariusOS is not going to make one.

---

## If something goes wrong

**Double-clicking a download does nothing.**
Right-click it → **Open With** → **Aquarius Installer**. If that works but double-clicking
does not, something has overridden the default; say so, because it is a fault of ours.

**The window says the app needs parts AquariusOS does not have.**
That is honest, not a failure to try. Look for the same app on Flathub — the window offers
the search. If it is not there, say so and it goes on the list.

**An app installed but its icon does nothing when clicked.**
That is the fault this app was written to prevent, so it is worth reporting rather than
working around. Run `aq apps what` on the original file, and open the app's note in
`~/.local/share/aquarius/apps/`, and send both.

**You want an app that is really a driver or a system service.**
Ask for it. Things that belong in the operating system get built into it, where they
survive every update — which is better than installing it yourself would ever have been.

---

## Where the code is

| Path | What it is |
| --- | --- |
| `system_files/usr/lib/aquarius/python/aquarius_installer.py` | **The part that decides.** The sorter, the routes, the registry. No window in it at all, which is what lets the window, `aq apps` and the tests be one implementation. |
| `system_files/usr/libexec/aquarius-installer` | The window. Also runs with no screen at all — `--sort`, `--install`, `--list`, `--remove`, `--updates`, `--search`, `--dry-run`. |
| `system_files/usr/libexec/aquarius-creator-apps-install` | The one privileged helper, shared with the app chooser. Four jobs: install, install a file, uninstall, update — one password prompt each run. |
| `system_files/usr/share/applications/aquarius-installer.desktop` | The app grid entry, and the list of file types it can open. |
| `system_files/etc/xdg/mimeapps.list` | What makes it the app a double-click actually opens. |
| `system_files/usr/share/mime/packages/aquarius-installer.xml` | Names for the file types Linux has no useful name for. |
| `build_files/65-installer.sh` | The build step, which reads every one of the above back out of the finished image. |
| `tests/test-installer-sorter.py` | Builds real packages, really installs them into a throwaway home folder, and reads back what happened. |

The design of record is **FEATURES 010** in the folder above this repository.
