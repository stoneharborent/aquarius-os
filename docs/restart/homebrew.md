# Homebrew on AquariusOS — the `brew` command

*Written 2026-09-12 for Phase R8. Assumes you have never used Linux, and have
never typed a command on purpose.*

---

## The one-paragraph version

AquariusOS comes with **Homebrew** already on it, on both images. Homebrew is a
software shop you use by typing instead of by clicking: you open a terminal, you
type `brew install ffmpeg`, and a minute later `ffmpeg` is on your computer. It
is the thing a tutorial means when it says *"install it with brew"* — the same
`brew` you may already have on the Mac — and it is there so that following an
instruction you found on the internet does not turn into an afternoon.

You do not have to use it. Nothing on this computer needs it. It sits there
costing nothing until the day a tutorial asks for it.

---

## What it is FOR, and what it is not for

This matters, because AquariusOS now has several ways to get software and it
would be easy to reach for the wrong one.

| If you want… | Use… |
| --- | --- |
| **An app with a window** — OBS, Krita, Blender, Obsidian | The app chooser, or search in **Aquarius Installer**. See [`creator-apps.md`](creator-apps.md). |
| **Something you downloaded** — an `.rpm`, a `.deb`, an AppImage | Double-click it. **Aquarius Installer** opens. See [`installer-app.md`](installer-app.md). |
| **A command-line tool** — `ffmpeg`, `yt-dlp`, `jq`, `htop`, `node`, `python` | **`brew install <name>`**. This page. |

The rough rule: **if a tutorial tells you to type it, brew is probably the
answer. If you would expect to find it by clicking around, it is not.**

Homebrew is not a replacement for any of the others, and none of them is a
replacement for it. They do genuinely different jobs.

---

## Your first two minutes

1. Open a terminal. (In the Aquarius Session or GNOME: press the key with the
   Aquarius mark on it and type "Terminal".)
2. Type this and press Return:

   ```
   brew install yt-dlp
   ```

3. Watch it download, and then type `yt-dlp --version`. That is it. There is no
   password, no setup and no account.

A few more you will actually use:

```
brew install ffmpeg         # the swiss army knife of video
brew search <something>     # is there a brew package for this?
brew list                   # what have I installed?
brew uninstall <name>       # take one away again
brew upgrade                # bring everything up to date, when YOU decide to
brew update                 # just refresh the catalogue (happens weekly anyway)
```

If `brew` says **"command not found"**, the most likely reason is that your
terminal was already open before Homebrew was unpacked. Close it and open a new
one. If that does not fix it, jump to *[When it goes
wrong](#when-it-goes-wrong)*.

---

## Where it lives, and the strange thing about that

Homebrew installs itself at:

```
/home/linuxbrew/.linuxbrew
```

and it genuinely insists on that exact folder — all of its ready-built packages
expect to find themselves there, and putting it anywhere else means it has to
compile everything from source, slowly.

That creates a real problem on this kind of operating system, and the solution
is the reason there is a service involved at all.

### The problem, in four sentences

AquariusOS is a **sealed image**. When you update, the whole `/usr` half of the
machine is replaced with a new one, and the `/var` half — your home folder, your
files, your settings — is left completely alone. That is what makes an update
safe and a rollback possible.

But `/home` on this system is a signpost pointing into `/var`. So anything we
installed into `/home` while building the image would land on a computer that
installed AquariusOS **from a disc**, and would never arrive on a computer that
was already running and **simply updated**. Half the machines would have `brew`
and half would not, depending on how they got here, and nothing anywhere would
say so.

### The solution

The build does it in two halves:

1. **When the image is built:** Homebrew is really installed, then packed into a
   single compressed file that is put in `/usr` — the half every update
   replaces:

   ```
   /usr/share/aquarius/homebrew/homebrew.tar.zst
   ```

   and deleted from `/var` again, so none of it ships in the half we cannot
   rely on.

2. **On your computer, once:** a small service notices at boot that there is no
   Homebrew yet, unpacks that file into place, sets who owns it, and finishes.
   It takes a few seconds and you will most likely never see it happen.

   ```
   /usr/lib/systemd/system/aquarius-brew-setup.service
   /usr/libexec/aquarius-brew-setup
   ```

**The good consequence of doing it this way:** because the packed copy lives in
`/usr`, every update carries it. A computer that installed AquariusOS *before*
Homebrew existed gets `brew` on its first boot after taking an image that has
this. Nobody has to reinstall anything.

> This is the same shape Universal Blue (the Bluefin / Bazzite family) uses for
> Homebrew on their images. We did not invent it; we checked what they do first,
> and then wrote our own with our own names and one deliberate difference — see
> *Who owns it*, below.

### The service runs at every boot and does nothing

That is deliberate — it is what lets an update deliver Homebrew to an older
machine. The first thing the script does is look for `brew`, and if it is there
it prints one line and stops. It is checked by a test that runs the script twice
and fails the build if the second run touches anything, because the failure it
would cause is nasty and silent: a computer that re-unpacks Homebrew at every
boot, wiping everything you installed, with no error message anywhere.

---

## Who owns it

The Homebrew folder is owned by `root`, with its group set to **`wheel`** and
the group allowed to write.

`wheel` is Linux's name for *"the people who are allowed to administer this
computer"*. The account created when AquariusOS was installed is in it. The
practical effect:

- **`brew install` needs no password.** Which is what anyone coming from a Mac
  expects, and the whole point.
- On a computer with a **second, ordinary account**, that person can *use*
  everything brew installed and cannot change it. That is the correct answer,
  not a limitation.

> **Where we differ from Universal Blue, on purpose.** Theirs hands the folder
> to "user number 1000" — the first account made on the machine. That is simpler
> and right almost always. Ours uses the `wheel` group instead, because "1000"
> means one specific person and `wheel` means *all* the administrators, which is
> the right answer on a machine with two.

### Two honest limits

- **`brew doctor` may mention that the folder is not owned by you personally.**
  It is a remark, not a fault. Nothing stops working.
- On a machine with **two administrator accounts**, files one of them installs
  are readable and runnable by the other, but not always writable by them. If
  that ever bites, one command fixes it:

  ```
  sudo chmod -R g+w /home/linuxbrew/.linuxbrew
  ```

---

## How `brew` gets onto your PATH

"PATH" is the list of folders your computer searches when you type a command.
Homebrew is no use unless it is on that list, and there are two completely
different ways a program finds out what its PATH is — so there are two files.

| File | Covers |
| --- | --- |
| `/etc/profile.d/aquarius-brew.sh` | **Typing.** Every terminal window, every SSH session. |
| `/usr/lib/environment.d/70-aquarius-brew.conf` | **Clicking.** Every app started from the dock, the app grid or a menu — none of which involve a shell, so none of which ever read the file above. |

Without the second one you would get a genuinely baffling fault: a tool you
installed with brew works perfectly in a terminal, and an app you opened from
the dock insists it is not installed.

### ⚠️ The one deliberate oddity: brew goes at the END of PATH

Homebrew's own instructions put its folder at the **front** of PATH, so its copy
of any program beats the system's copy. On a Mac that is the entire point.

Here it is a trap. Homebrew will happily install its own `bash`, its own
`systemd`, its own `dbus`, its own `rpm` — usually as a dependency of something
else you asked for — and those copies are built for Homebrew, not for Fedora. If
one of them wins, the results run from *"this behaves oddly"* to *"I cannot log
in"*. It is a real failure that Universal Blue hit and wrote up before we did.

So AquariusOS adds Homebrew's folders at the **end**: brew's tools are found
when nothing else provides them, and never win against the operating system's
own. Everything you install with brew works exactly as you expect. The weekly
refresh also runs `brew unlink` on those particular names as a second belt.

### If you install fish

AquariusOS ships no fish shell, so there is no fish version of the file above.
If you install fish yourself (most likely with `brew install fish`), add this to
your own `~/.config/fish/config.fish`:

```fish
if test -x /home/linuxbrew/.linuxbrew/bin/brew
    /home/linuxbrew/.linuxbrew/bin/brew shellenv fish | source
    fish_add_path --move --append --path (brew --prefix)/bin (brew --prefix)/sbin
end
```

The second line is the fish way of saying the same "put it at the end" rule.

---

## The weekly refresh

Once a week, about half an hour after you log in, AquariusOS runs `brew update`
for you. That refreshes Homebrew's **list** of what is available and which
versions exist. It installs nothing and it changes no program on your computer.
The point is simply that `brew install <thing>` gets the current version when
you actually ask for it, without stopping to go and look first.

```
/usr/lib/systemd/user/aquarius-brew-update.timer
/usr/lib/systemd/user/aquarius-brew-update.service
/usr/libexec/aquarius-brew-update
```

### ⚠️ It deliberately does NOT run `brew upgrade`

Universal Blue's equivalent does. Ours does not, and that is a decision.

`brew upgrade` would quietly replace the command-line tools you are working
with — the exact version of Python, of ffmpeg, of a build tool your project
depends on — at three o'clock on a Sunday morning. The symptom is a project that
built on Friday and does not build on Monday, with nothing in between that
anybody did. That is a genuinely bad afternoon, and what it buys is saving you
from typing eight characters.

**So upgrading is yours to decide.** When you want it:

```
brew upgrade
```

### Turning the refresh off

It is your own session's timer, so this needs no password:

```
systemctl --user mask aquarius-brew-update.timer
```

(`systemctl --user disable` will *not* work, and that is not a bug — see the
comment at the top of the timer file. AquariusOS switches its own services on
with a link shipped inside the image, so that a local `disable` cannot silently
survive every future update. `mask` is the switch that beats everything.)

---

## Removing Homebrew

### Just for now, on this one computer

```
sudo systemctl mask aquarius-brew-setup.service
systemctl --user mask aquarius-brew-update.timer
sudo rm -rf /home/linuxbrew
```

Then close every terminal and open a new one. The first command is the one that
matters — without it the next boot would simply put Homebrew back.

To change your mind later, `unmask` both and reboot.

### Getting rid of it for everybody, in the image

Delete `build_files/69-homebrew.sh` and its step in the `Containerfile`, and the
five files under `system_files/` that this page names. The image loses about the
size of the packed copy (the build log prints the exact number under *"the box
is … bytes"*).

---

## When it goes wrong

### "brew: command not found"

**First, and it is nearly always this:** your terminal was open before Homebrew
was unpacked. Close it, open a new one.

If that does not do it, ask whether it is actually installed:

```
ls /home/linuxbrew/.linuxbrew/bin/brew
```

- **It is there** → your PATH is the problem. Check the snippet is present with
  `cat /etc/profile.d/aquarius-brew.sh`, then start a fresh login shell with
  `bash -l`.
- **It is not there** → the unpack has not happened or did not work. Next
  section.

### The unpack did not happen

Ask the service what it did:

```
systemctl status aquarius-brew-setup.service
journalctl -u aquarius-brew-setup.service
```

The three likely answers:

- **"condition failed"** — systemd skipped it because it believes Homebrew is
  already installed. That is the guard doing its job; combine with the `ls`
  above to see whether it is right.
- **The packed copy is missing** — check `ls -lh
  /usr/share/aquarius/homebrew/homebrew.tar.zst`. If that file is not there, the
  image you are running does not include Homebrew. Run `aq update`.
- **Something else** — run it by hand and watch, which is safe:

  ```
  sudo /usr/libexec/aquarius-brew-setup
  ```

### "Permission denied" when installing something

Your account is probably not in the `wheel` group. Check:

```
groups
```

If `wheel` is not in the list, that account is not an administrator of this
computer, which is the intended answer for a second account. An administrator
can add it with `sudo usermod -aG wheel <name>`, and it takes effect at the next
login.

### A brew package fails to compile

Most brew packages arrive ready-built and never compile anything. When one has
no ready-built version for this machine, brew builds it from source, and for
that it needs a compiler — `gcc`, which AquariusOS includes for exactly this
reason. If you see a wall of red text mentioning a missing compiler or missing
header files, that is worth reporting: it means something is missing from the
image, not from your computer.

---

## Bench check for Royce

On the bench PC, after `bootc upgrade` and a restart:

1. Open a terminal and type `brew --version`. It should print a Homebrew version
   and not "command not found".
2. `brew install yt-dlp` — it should finish with **no password prompt at all**.
   Then `yt-dlp --version`.
3. `which yt-dlp` should answer `/home/linuxbrew/.linuxbrew/bin/yt-dlp`.
4. **The PATH order check, which is the one most likely to be wrong:**
   `which bash` must still answer `/usr/bin/bash`, not a path inside
   `/home/linuxbrew`. The system's own copies must keep winning.
5. `systemctl status aquarius-brew-setup.service` should say it ran once and
   succeeded (or that its condition failed, on the second and later boots —
   both are correct).
6. Restart, and confirm the boot is **not** noticeably slower and that `yt-dlp`
   is still installed. This is the idempotency guard doing its job on real
   hardware; the test in CI proves the logic, this proves the machine.
7. `systemctl --user list-timers | grep brew` should show the weekly refresh
   scheduled.
8. The clicking half: open an app from the dock that runs a command-line tool,
   or simply run `systemctl --user show-environment | grep linuxbrew` and check
   the PATH there ends with brew's two folders.

Anything that fails goes in `docs/design/bench-run-<date>.md` like everything
else.

---

## What is checked before an image is published

`build_files/69-homebrew.sh` reads its own work back out of the finished image —
content, never timestamps, the rule in `build_files/aq-lib.sh`:

- The packed copy exists, is bigger than an empty archive could possibly be, and
  the build log prints its real size so a jump is visible.
- `.linuxbrew/bin/brew` **and** Homebrew's own program library are really inside
  it — a valid archive of the wrong thing passes every other check.
- `brew --version` was run during the build and said "Homebrew".
- Nothing of Homebrew is left in `/var`, and `/var/home` is empty. This is the
  check that catches the mistake that would split our users in half.
- The container marker the installer needed is not in the finished image.
- The setup service is switched on **from `/usr`** and *not* through `/etc`.
- `tests/test-brew-setup.sh` runs the real setup script twice against a fake
  machine and proves the second run changes nothing, that a broken packed copy
  installs nothing at all, and that no half-unpacked leftovers survive.
- Both PATH files are present and say what they should.
- The weekly timer is weekly, randomised, persistent, and switched on from
  `/usr`.
- `gcc` is in the image, for the packages that have no ready-built version.

---

## Where this came from

- Royce asked for Homebrew to be installed and included by default, both images,
  2026-09-12.
- The pattern — install at build time, ship a packed copy in `/usr`, unpack at
  first boot — is Universal Blue's, at
  [github.com/ublue-os/brew](https://github.com/ublue-os/brew). What we borrowed
  and what we deliberately changed is written out above: the ownership model
  (`wheel` rather than user 1000), no automatic `brew upgrade`, a user timer
  rather than a system one pinned to user 1000, and our own paths and names.
