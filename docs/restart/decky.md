# Decky Loader — plugins inside Game Mode

*Written 2026-09-19, for Phase G3. Assumes you have never used Linux.*

---

## The one-paragraph version

**Decky Loader adds a plugins menu to Game Mode.** In Game Mode (Steam owning
the whole screen — see [`game-mode.md`](game-mode.md)) there is a button marked
**"..."** on the right of the screen. Press it and you get Steam's quick-access
menu: brightness, performance, notifications. Install Decky and that menu grows
**one more tab, with a plug on it**, and behind the plug is a small shop of
add-ons other people wrote — a battery readout, a per-game power profile, a
screen recorder, a music player, frame generation.

It is not part of AquariusOS. It is **offered**: nothing of it is in the image,
and it arrives only when you ask for it. One command, or one click.

⚠️ **It only ever appears in Game Mode.** Open Steam in a window on your desktop
and there is no plug icon and no plugins menu, no matter what you do. That is
not a fault and there is no setting for it — it is what Decky is.

---

## Installing it

**From the app grid:** an icon called **Decky Loader**. Clicking it opens a
terminal window and does the whole thing there, so you can see what is
happening.

**From a terminal:** `aq decky install`.

Either way it takes about a minute:

1. it asks GitHub which Decky is newest and downloads it (about 26 MB);
2. it makes the two folders Decky keeps its things in, inside your home folder;
3. it asks for **your password, once**, to switch the background service on.

Then:

> **TO SEE IT:** go to Game Mode — type `aq game`, or use **Return to Game
> Mode** in the app grid — press the **"..."** button on the right of Steam's
> screen, and look for the tab with a **plug** on it.

If Steam was already open when you installed, close it and open it again first.

---

## Where the plugins menu is, exactly

In Game Mode, the buttons down the right of the screen are Steam's quick-access
menu. The one you want is **"..."** — on a controller it is the button with
three dots on it, below the Steam button.

The tabs along the top of that menu are Steam's own: notifications, friends,
performance, settings. **Decky's tab is the one with the plug**, at the end.
Inside it:

- the plugins you have, at the top;
- a **shop** (Decky calls it the store) where you find more;
- a settings cog for Decky itself.

---

## Keeping it up to date, and taking it off

    aq decky update     Get a newer Decky, if there is one.
    aq decky status     Is it installed, which version, is it running.
    aq decky remove     Take it off again.

`aq decky update` asks GitHub what the newest version is and **compares it with
what you have**. If they are the same it says so and downloads nothing. If they
differ it downloads the new one and restarts the service, asking for your
password once.

`aq decky remove` switches the service off, deletes it, and deletes the
downloaded loader. ⚠️ **Your plugins are not deleted.** They stay in
`~/homebrew/plugins`, so installing Decky again finds them exactly as they were.
Delete that folder yourself if you want them gone.

---

## Two things to know before you install it

Neither of these is a reason not to install Decky. They are things you should
know once, plainly, because nobody else will tell you.

### It runs as the administrator

Decky's loader is a background service running **as root** — the administrator.
That is not a corner anybody cut: plugins exist to change things a normal
program is not allowed to change, like screen brightness on a handheld, a power
limit, or a fan speed. A plugin system that could not do those would be a
plugin system nobody wanted.

So the honest summary is: **installing Decky means trusting Decky, and trusting
the plugins you install through it**, in the way you trust anything you install
on a computer. AquariusOS does not review them and does not ship them.

### It listens, but only to this computer

The loader waits for instructions on **port 1337**, and only on
`127.0.0.1` — this computer's own internal address, which nothing on your
network and nothing on the internet can reach. Somebody sitting at another
machine on your Wi-Fi cannot talk to it.

---

## The `/home/deck` signpost

Some Decky plugins were written for a Steam Deck, where everybody's home folder
is called `/home/deck`, and a few of them have that name typed straight into
them rather than asking the computer where your home folder is. On your PC your
home folder is called something else, so those plugins would look in a place
that does not exist and quietly do nothing.

So the install makes a **signpost**: a little pointer at `/home/deck` that says
"the real folder is over there", pointing at yours. Nothing is copied and
nothing is moved; it is one pointer.

It is careful about it in both directions:

- it is **only made if nothing is already at that name**. If you happen to have
  a real `/home/deck`, or an account actually called `deck`, it is left
  completely alone;
- `aq decky remove` **only deletes it if it is the one we made**, pointing at
  your home folder. Anything else stays where it is.

`aq decky status` tells you which of those you have.

---

## What can go wrong

### "Steam had never been opened on this account"

Decky needs to leave a small flag file inside **Steam's own folder**, and that
folder does not exist until Steam has been run once. If you install Decky
first, `aq decky install` makes the folder for you and says so — but **open
Steam once and sign in** before you go looking for the plug icon. Until you
have, there is nothing for Decky to attach itself to.

### The plug icon is not there

In this order:

1. **Are you in Game Mode?** Not Steam's Big Picture inside your desktop —
   actual Game Mode, which you reach with `aq game`. `aq decky status` says this
   too, every time, because it is far and away the most common answer.
2. **Close Steam and open it again.** Decky attaches itself when Steam starts.
3. `aq decky status` — if the background service says **NOT running**, the fix
   is `sudo systemctl restart plugin_loader.service`.
4. If it says the **plugin flag file is MISSING**, run Steam once and then
   `aq decky remove` followed by `aq decky install`.

### "could not ask GitHub what the newest Decky is"

The computer is not on the internet, or GitHub is having a bad day, or you have
asked it a great many times in a short while and it is making you wait. Nothing
has been changed — try again later.

### It installed, but the service will not start

This is almost always **SELinux**, the part of Linux that decides which programs
are allowed to be programs. A file downloaded into your home folder is labelled
as ordinary data, and systemd will not start ordinary data as a service. The
install gives it the right label; if something has stripped it, put it back:

    sudo chcon -t bin_t ~/homebrew/services/PluginLoader
    sudo systemctl restart plugin_loader.service

### It asks for a password and will not take it

Decky needs an **administrator** for one part of its install — writing the
service file and switching it on. That is your own login password, and your
account has to be an administrator (on a machine you installed yourself, it is).

⚠️ **Do not run `sudo aq decky install`.** Decky installs into *your* home
folder, and under `sudo` that would be the administrator's home folder, where
you would never find it. The command refuses to run that way and says so.

### "not allowed to write" — a Decky that Decky's own installer put there

If you installed Decky yourself before AquariusOS had this command, by running
Decky's installer script, some files in `~/homebrew/services` belong to the
**administrator** rather than to you — that installer hands them over. `aq
decky update` will stop before it downloads anything and tell you so, rather
than half-updating and claiming it worked. Give the folder back to yourself
and run the update again:

```
sudo chown -R "$USER" ~/homebrew/services
aq decky update
```

From then on `aq` keeps that folder yours: the administrator's half of an
install or an update writes the version file last, once the service has really
restarted, and hands it straight back to you.

---

## What this is made of, for the record

Nothing of Decky is in the AquariusOS image, and the build **fails** if any of
it ever is — no service file, no `/home/deck`, no downloaded loader, no
`~/homebrew`. What is in the image is three things: the `aq decky` command, the
"Decky Loader" entry in the app grid, and `jq`, the small program that reads
GitHub's answer about which release is newest.

| Where | What |
| --- | --- |
| `~/homebrew/services/PluginLoader` | The loader itself, downloaded when you ask. About 26 MB. |
| `~/homebrew/services/.loader.version` | Which version that is. `aq decky update` compares against it. |
| `~/homebrew/plugins/` | Your plugins. Never deleted by `aq decky remove`. |
| `~/.steam/steam/.cef-enable-remote-debugging` | The empty flag file that lets Decky talk to Steam's interface. |
| `/etc/systemd/system/plugin_loader.service` | What starts the loader with the computer. |
| `/home/deck` | The signpost, if we made it. |

⚠️ **Why that service file is in `/etc`, when nothing else of AquariusOS is.**
Everything AquariusOS switches on ships as a link under `/usr`, for the reason
set out at length in `build_files/aq-lib.sh`: `/usr` is replaced whole by every
update, so a switch-on there can never be lost. Decky is the opposite case. It
is not part of the image at all, it is a thing **this machine** was asked to
add, and the file even names **this machine's own home folder**. `/etc` is where
a machine's own decisions belong, it is writable on this kind of Linux, and an
update keeps it. So `systemctl enable` is right here — and only here.

The build step is `build_files/81-decky.sh`. Almost all of it exists to prove
the absence of things.

---

## The bench list

Nothing below can be tested by the build. It needs the internet, a real Steam
and a real screen.

1. **`aq decky status` on a machine with no Decky** says "NOT installed" and
   still explains where Decky would appear.
2. **`aq decky install`** downloads, asks for a password exactly once, and ends
   with the "TO SEE IT" instructions.
3. **`sudo aq decky install` is refused**, with a sentence explaining why.
4. **Game Mode** (`aq game`) → **"..."** → the **plug** tab is there, and its
   store loads.
5. **Install one plugin** from the store — something harmless, like a battery
   or clock readout — and it appears in the menu.
6. **Back on the desktop**, Steam in a window has **no** plug icon. This is the
   expected answer, not a fault.
7. **`aq decky install` a second time** says "already installed" and points at
   `update`. It does not download anything.
8. **`aq decky update`** with nothing newer available says so and downloads
   nothing.
9. **Restart the computer.** `aq decky status` says the service is running
   again by itself, and the plug tab is still in Game Mode.
10. **`aq decky remove`**, then check: `~/homebrew/plugins` still has the plugin
    from step 5 in it, `/home/deck` is gone, and Steam and the games are
    untouched.
11. **`aq decky install` again** — the plugin from step 5 is still there.
12. **On the handheld image** (the ROG Xbox Ally X), all of the above, since
    that is the machine Decky was originally written for.
