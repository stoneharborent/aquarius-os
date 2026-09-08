# Desktop identity — the pointer, the icons and the sounds

*Phase R5 polish. Written 2026-09-05.*
*Updated 2026-09-06: the app icons are now ours, and so is the window frame.
Everything else stands.*

> **⚠️ WHAT CHANGED ON 2026-09-06, BEFORE YOU READ THE REST.** This page was
> written to explain why AquariusOS pointed at *other people's* themes for the
> pointer, the icons and the sounds, and it left a marked seam for our own
> artwork later. **The icon seam is now closed.** AquariusOS ships its own app
> icons — `Aquarius-Ice` (the default) and `Aquarius-Midnight` — drawn in
> `branding/icons/` and documented in
> [`branding/icons/README.md`](../../branding/icons/README.md).
>
> It is a *narrow* set on purpose: **nine icons**, the ones Royce looks at every
> day, and both themes say `Inherits=Adwaita,hicolor`, so every other icon on the
> machine still comes from GNOME. So the reasoning below about not drawing a
> whole icon set is still exactly right — we did not draw one.
>
> **The window frame is ours too, as of the same day** — the title bar, the
> border, the round window buttons and the desktop right-click menu. It is not
> a *theme* in the sense this page warns about: it is generated from the shell's
> own palette every time the desktop starts. See
> [The window frame](#the-window-frame) further down.
>
> The pointer is still Adwaita and the sounds are still freedesktop. Those two
> seams are still open, and everything this page says about them still holds.

## The one-paragraph version

AquariusOS now sets three more pieces of its look on a brand-new machine: the
**mouse pointer** (cursor theme), the **app icons** (icon theme) and the
**system sounds** (the log-in chime, the notification ping, the error bleep).
All three are set to themes that already ship with Fedora and are kept up to
date by other people — **Adwaita** for the pointer and the icons, **freedesktop**
for the sounds. AquariusOS does **not** draw its own set of any of these yet.
That is a deliberate choice, not a gap, and there is a clearly marked seam so
real Aquarius artwork can drop in later by changing one line each.

## Why we did not draw our own

Drawing a cursor set, an icon set or a sound set is a real art project, not a
build task:

- A **cursor theme** is dozens of little pictures — an arrow, a hand, a text
  bar, a dozen kinds of "busy" spinner — each drawn at several sizes.
- An **icon theme** is *hundreds* of pictures, one for every kind of file and
  every app, and it has to keep up as apps come and go.
- A **sound theme** is a small set of composed audio cues that have to sit
  together and not grate after the tenth time you hear them.

A half-finished set of any of these looks worse than a good, complete existing
one — you get a nice custom arrow and then a stock hand the moment you hover a
link, or a beautiful folder icon next to a generic grey square for every app we
did not draw. So the decision (which is the same decision the rest of the
desktop makes — see [`README.md`](README.md), "The rules that do not move") is:
**work with GNOME's grain.** Pick the best existing, packaged, well-kept theme,
set it as the default, and leave the door open for our own artwork later.

## What ships, and why each one

| Piece | Theme | Package | Why this one |
|---|---|---|---|
| Mouse pointer | **Adwaita** | `adwaita-cursor-theme` | GNOME's own pointer: clean, neutral, already in the image, and already the pointer the **login screen** uses — so the pointer does not change shape the instant you log in. |
| App icons | **`Aquarius-Ice`** (ours, since 2026-09-06) | built in this repo, from `branding/icons/` | Our own nine app icons, light set — AquariusOS is light-first. Everything we do not draw falls through to `adwaita-icon-theme`, which is still installed and still where the other several thousand icons come from. The dark twin `Aquarius-Midnight` is built and installed beside it; nothing selects it yet (see below). |
| System sounds | **freedesktop** | `sound-theme-freedesktop` | The standard, complete cross-desktop sound set. Safe, familiar, nothing missing. |

**How the shell finds them — and why it needed telling (2026-09-06).** Every
GTK application reads the `icon-theme` setting directly. Quickshell, which draws
the dock, the search results and the app switcher, is a Qt program, and Qt only
learns the icon theme from a "platform theme" it has for GNOME and for KDE.
Our session is neither by name (`XDG_CURRENT_DESKTOP=Aquarius:wlroots`, on
purpose), so Qt reports *no* icon theme and searches only `hicolor` — where the
Aquarius icons are not. On the bench that looked like the artwork had never
shipped. `/usr/bin/aquarius-session` now reads the same `icon-theme` setting
and hands it to the shell as `QS_ICON_THEME`; the greeter sets the image
default. Changing icon theme in Settings reaches the dock at the next login.

**Where the app icons turn up.** They are drawn from the icon theme above by
every part of the desktop that names an application: the app grid, Files, the
dock, and — since 2026-09-06 — **the Aquarius app switcher**, the panel
Command-Tab (or Alt-Tab, on the Windows keyboard style) puts in the middle of
the screen. The switcher draws one 96px icon per running application, so it is
the place where a missing or low-resolution icon shows up most obviously. If an
app comes up as two grey letters there, that is a gap in the icon theme rather
than a fault in the switcher. The switcher itself is written up in the
`aquarius-shell` repository at `docs/app-switcher.md`.

The pointer size is set to **24**, GNOME's own default (in "logical" pixels). On
the 4K bench the desktop scale makes the pointer the right physical size on its
own; this number is the sane fallback that GDM and the odd app which reads it
directly use.

### The alternatives we looked at, and passed on for now

- **Bibata** (a popular rounded cursor set). Nice, but it is only in a COPR
  (a third-party add-on repository), and this project does not pull cursor art
  from a COPR. Ruled out by that alone. If it ever lands in Fedora proper, it
  becomes a candidate.
- **Papirus** (`papirus-icon-theme`, a fuller icon set many creator distros
  ship). It *is* in Fedora and it covers more third-party apps than Adwaita, so
  fewer apps show a generic icon. We passed on it for the default because
  Adwaita keeps the desktop coherent with GNOME and is zero-maintenance, but it
  is the obvious swap if Royce ever wants fuller app-icon coverage — see below.

## Where these are set

Two places, on purpose kept in step with each other:

1. **The desktop session** (every normal login) —
   `system_files/usr/share/glib-2.0/schemas/zz1-aquarius-10-look.gschema.override`,
   in the `[org.gnome.desktop.interface]` group (cursor and icons) and the
   `[org.gnome.desktop.sound]` group (sounds).
2. **The login screen** (GDM, before you log in) —
   `build_files/50-aquarius-desktop.sh`, which writes
   `/etc/dconf/db/gdm.d/02-aquarius-look`. It sets the same Adwaita cursor and
   the same `Aquarius-Ice` icons, so the login screen and the desktop match and
   nothing visibly changes the instant you log in. (The greeter does not play
   event sounds, so there is no sound line there.)

The icons themselves are checked by their own build step,
`build_files/56-aquarius-icons.sh`, and by `tests/test-aquarius-icons.sh` before
a build even starts.

Both are **defaults**, not locks. The moment a person picks a different pointer,
icon set or sound theme, their choice is written into their own settings and
wins over these forever after. Nothing here is forced on anybody.

The packages are installed in `build_files/40-gnome-desktop.sh`.

## How a user changes them

Everything here is a normal GNOME setting, so a person can change it without
touching the system:

- **Sounds on or off:** Settings → Sound → *System Sounds* toggle. Or from a
  terminal: `gsettings set org.gnome.desktop.sound event-sounds false`.
- **A different pointer or icon set:** install one (from Software, or a
  Flatpak, or by dropping a theme folder into `~/.icons` or
  `~/.local/share/icons`), then pick it in **GNOME Tweaks → Appearance**
  (Tweaks is already on the machine). GNOME's own Settings app does not expose a
  cursor/icon picker; Tweaks is the standard place.

## The seam — dropping in real Aquarius artwork later

This is the whole point of naming the themes explicitly rather than leaving them
at Fedora's unstated default. When Aquarius cursor / icon / sound artwork
exists, it lands like this — and each is a **one-line** change:

### A real Aquarius cursor theme

1. Ship the cursor folder in the image at
   `/usr/share/icons/Aquarius/cursors/` (a folder of cursor files plus an
   `index.theme` that names the theme "Aquarius"). The natural home is a new
   `system_files/usr/share/icons/Aquarius/` tree, or a build step in
   `build_files/`.
2. Change **one line** in `zz1-aquarius-10-look.gschema.override`:
   `cursor-theme='Aquarius'` — and the matching line in
   `build_files/50-aquarius-desktop.sh`'s `02-aquarius-look` so the login screen
   follows.
3. Update the CI read-back and folder checks in `.github/workflows/build.yml`
   (search for `cursor-theme`) to expect `'Aquarius'` and
   `/usr/share/icons/Aquarius`.

### A real Aquarius icon theme — ✅ **done, 2026-09-06**

This is what actually happened, kept here as the worked example for the two
seams still open above.

Two themes ship at `/usr/share/icons/Aquarius-Ice/` and
`/usr/share/icons/Aquarius-Midnight/`. Each has an `index.theme` saying
`Inherits=Adwaita,hicolor`, so it only has to draw the icons it wants to change —
which is nine (twelve files: Files, Settings and the Console are each filed under
GNOME's name and ours). `icon-theme='Aquarius-Ice'` is set in the same two files as
everything else on this page, and CI expects it.

The drawings live in `branding/icons/` and are rebuilt with
`bash branding/render-app-icons.sh`. Read
[`branding/icons/README.md`](../../branding/icons/README.md) before touching any
of it.

**⚠️ TODO — not this repo's job: nothing switches to Midnight yet.** The dark
set is built, installed and checked, and nothing ever selects it. Following the
desktop's light/dark setting is the *shell's* job (the aquarius-shell repository
already watches the colour scheme), so: **when the shell switches the colour
scheme to dark it should set `org.gnome.desktop.interface icon-theme` to
`'Aquarius-Midnight'`, and back to `'Aquarius-Ice'` when it goes light.** Both
themes are already in the image, so that is a one-setting change with no image
work behind it. Until it lands, a person switches by hand:

```bash
gsettings set org.gnome.desktop.interface icon-theme 'Aquarius-Midnight'
```

### A real Aquarius sound theme

1. Ship the sounds at **`/usr/share/sounds/aquarius/`** — a folder of audio
   files (the standard is `.oga`/Ogg Vorbis) plus an `index.theme` naming the
   theme "aquarius". The freedesktop sound-naming spec lists the standard event
   names (`bell`, `message`, `device-added`, and so on).
2. Change **one line** in `zz1-aquarius-10-look.gschema.override`:
   `theme-name='aquarius'`.
3. Update the CI read-back and folder checks in `.github/workflows/build.yml`
   (search for `theme-name` and `/usr/share/sounds/freedesktop`).

### To fall back to Papirus instead (no new artwork needed)

Kept for the record. If Royce ever wants fuller *third-party* app-icon coverage
and is willing to give up our own eight:

1. Add `papirus-icon-theme` to the install list in
   `build_files/40-gnome-desktop.sh`.
2. Set `icon-theme='Papirus'` in `zz1-aquarius-10-look.gschema.override` and in
   `build_files/50-aquarius-desktop.sh`'s `02-aquarius-look`.
3. Update the CI checks in `.github/workflows/build.yml` to expect `'Papirus'`,
   the package `papirus-icon-theme`, and the folder `/usr/share/icons/Papirus`.

A better answer, if this ever comes up, is to set `Inherits=Papirus,Adwaita,hicolor`
in our own two `index.theme` files instead — that keeps the Aquarius icons and
gets Papirus's coverage underneath them.

## The window frame

*Added 2026-09-06.*

### What it is

Four things on an Aquarius screen are drawn by **labwc**, the window manager,
and not by the shell:

- the **title bar** at the top of every window;
- the **border** around it;
- the round **window buttons** — close, minimise, maximise;
- the **menu** that opens when you right-click the wallpaper.

Until 2026-09-06 labwc drew all four in its own default Openbox grey, next to a
shell that is entirely Ice blue. Royce's bench note was four words: *"the right
click menu does not have a design yet"*.

### Why this is not the kind of theme this page warns about

Everything above about not chasing GNOME's internals still stands. This is a
different situation: **labwc is ours**. We chose it, we compile it, and nothing
upstream is going to move underneath us. There is no treadmill because there is
nobody else's design to keep up with.

### How it works — generated, not typed

The colours of an Aquarius desktop live in exactly one place: the shell's
`theme/Ice.qml` (light) and `theme/Midnight.qml` (dark). labwc is a C program
reading flat text files and cannot read QML, so a program stands between them:

```
/usr/share/aquarius/labwc/generate-theme
```

It reads whichever palette is in force and writes out:

| What it writes | Where |
|---|---|
| `themerc-override` — every colour and size labwc draws with | `~/.config/aquarius/labwc/` |
| `rc.xml` — with three settings filled in | `~/.config/aquarius/labwc/` |
| `menu.xml`, `autostart`, `shutdown`, `environment` | copied there unchanged |
| the round window buttons, as SVG | `~/.local/share/themes/Aquarius/labwc/` |
| the GTK window chrome — window colour, header-bar colour, and the three window buttons, in **both** light and dark | `~/.config/gtk-4.0/gtk.css` + `gtk-3.0` |

`/usr/share/aquarius/labwc/` is the **template**. `/usr/bin/aquarius-session`
runs the generator before starting labwc and then starts labwc with the
generated folder. If generating ever fails, it starts labwc with the template
folder and says so in `~/.local/state/aquarius-session/session.log` — you get a
desktop either way.

The files go in your home rather than in `/usr` for two reasons, and both are
plain: `/usr` on an image-based operating system is read-only, and these files
have to be **rewritten while the desktop is running** — every time the machine
goes light or dark, and every time somebody moves the window buttons to the
other side.

### When it re-runs

1. **At login**, from `/usr/bin/aquarius-session`.
2. **When the machine goes light or dark.** The shell's
   `services/SystemAppearance.qml` runs it again and then runs
   `labwc --reconfigure`, which is labwc's own "re-read your files now" command.
   No logout.
3. **When you run `aq keys mac` or `aq keys windows`**, which is what moves the
   window buttons from one side to the other.

### How to change a colour

Edit `theme/Ice.qml` or `theme/Midnight.qml` **in the aquarius-shell
repository**. Nowhere else. There is no second copy of the palette to keep in
step, because the second copy is made rather than typed.

### The window buttons follow the Mac / Windows choice — one switch, not two

Royce's decision, 2026-09-06: which side the buttons sit on is **not a setting
of its own**. It follows the answer given in the Welcome window.

| `aq keys …` | Keyboard | Window buttons |
|---|---|---|
| `mac` (the default) | Copy is ⌘C | close, minimise, maximise on the **LEFT** |
| `windows` | Copy is Ctrl+C | minimise, maximise, close on the **RIGHT** |

Close is the outermost button either way — furthest from the title — because it
is the one press you cannot take back.

`aq keys` sets it on **both** desktops in one go: GNOME through its
`org.gnome.desktop.wm.preferences button-layout` setting, and the Aquarius
Desktop by re-running the generator. That matters, because a thing set for one
desktop and not the other looks like a bug in whichever one you happen to be
using — which is exactly how Command+Tab was lost earlier the same day.

### The one exception to the no-GTK-theme posture

`build_files/50-aquarius-desktop.sh` says AquariusOS ships no GTK theme. There
is one narrow, named exception: **the chrome of a GTK window, and only the
chrome.** Royce widened it on 7 September 2026; before that day it was two
colours, in dark mode only, and the file was deleted in light mode.

**What the bench showed.** GNOME's own applications — Files, Settings, Ptyxis,
Text Editor, Image Viewer, Document Viewer — draw their own title bar *inside*
the window and tell the window manager not to add one. So the Aquarius window
frame described above appeared on none of them. They sat on an Aquarius desktop
wearing libadwaita's grey bar and libadwaita's own flat buttons. The only thing
that can reach a window like that is GTK's own stylesheet.

**What the generated file now contains, in both light and dark:**

```css
/* Midnight shown; Ice is the same shape with Ice's colours. */
window    { background-color: #0B1220; }   /* the palette's bg    */
headerbar { background-color: #152033; }   /* the palette's panel */

windowcontrols > button > image        { /* a 20px round disc of ink */ }
windowcontrols > button:hover > image  { /* the disc deepens         */ }
windowcontrols > button.close:hover > image { /* close alone goes red */ }
windowcontrols > button:backdrop       { /* faded on a window you are not in */ }
```

and **nothing else**. No text colours. No widget theming. No borders. Not even
the header bar's height.

**Why the buttons are rebuilt in CSS rather than reusing the SVG files.** The
generator already draws those three buttons as pictures for labwc, and pointing
GTK at the same files would have been tidier. GTK will not do it: the only CSS
property that hands a file to a widget, `-gtk-icon-source`, is read by GTK's own
built-in icon shapes (the check mark, the expander arrow) and not by the kind of
picture a window button uses. So the disc is redrawn in plain CSS and the little
X, dash and square inside it stay GNOME's own. The colours, the opacities and
the sizes are the design; the exact stroke of the X is not.

**Why it is not a treadmill.** `window` and `headerbar` are the two most stable
selectors in GTK. The button selectors are libadwaita's and GTK's internals, and
they were read out of the libraries on a real Fedora 44 AquariusOS machine
rather than remembered. If a future GNOME renames them, the buttons quietly go
back to looking like GNOME's, which is where they started — nothing breaks.
Design rule 9 says it out loud: **check Files on the bench after every Fedora
bump.** The build prints the exact `gtk4`, `gtk3` and `libadwaita` versions the
assumption was made against.

**Why it is written into your home rather than shipped in `/etc`.** Ice and
Midnight need different colours, and GTK's CSS has no "only when dark" selector
— a stylesheet is loaded or it is not. So the file has to be rewritten every
time you flip between light and dark, which means it has to live somewhere
writable, and `/usr` on this operating system is read-only. The generator also
refuses to touch a `gtk.css` it did not write itself, so anybody's own GTK
customisation is left alone.

**The honest limit.** `~/.config/gtk-4.0/gtk.css` is not the Aquarius session's
private property — every GTK application you run reads it, including one started
from the GNOME fallback session. That is harmless (it is only chrome, in our own
quiet blues), but it does not follow GNOME's own light/dark switch: it keeps
whichever scheme the Aquarius session wrote last.

### Two things labwc 0.20 cannot do

Written down so they are not rediscovered as bugs:

- **There is no "pressed" button state.** The design asks for a darker disc
  while the mouse button is held down. labwc's button states are default, hover,
  toggled and rounded, and nothing else — there is no `close_pressed-active.svg`
  to ship. A button held down therefore looks like a hovered one. Nothing fakes
  it.
- **There is no title-bar height setting.** `titlebar.height` was removed from
  labwc; the height is now `max(font height, button height) + 2 × padding`. The
  generator sets the button height (20) and solves for the padding (9), which is
  what makes the 38px title bar the design asks for. At 1.25× scale the
  arithmetic lands one pixel short — 47 rather than 48 — because half of an odd
  number is not a whole number of pixels.

## How CI proves it

The **"Check the desktop comes up as Ice-light AquariusOS"** step in
`.github/workflows/build.yml` reads the *finished image* and checks:

- `gsettings` reports `cursor-theme='Adwaita'`, `cursor-size=24`,
  `icon-theme='Aquarius-Ice'`, `sound theme-name='freedesktop'` and
  `sound event-sounds=true` — the exact values a new account gets;
- the packages `adwaita-cursor-theme`, `adwaita-icon-theme` and
  `sound-theme-freedesktop` are installed (`rpm -q`) — Adwaita's icons still
  matter, because our themes inherit from them;
- the folders those settings point at really exist:
  `/usr/share/icons/Adwaita`, `/usr/share/icons/Adwaita/cursors`,
  `/usr/share/icons/Aquarius-Ice`, `/usr/share/icons/Aquarius-Midnight`,
  `/usr/share/sounds/freedesktop`.

The icons get a check of their own on top of that — every icon, in both themes,
at all eight sizes, read back from the PNG's own header rather than assumed. See
the **"Check the Aquarius app icons"** step, and
`build_files/56-aquarius-icons.sh` which does the same inside the build.

`build_files/40-gnome-desktop.sh` checks the same packages and folders at build
time as well, so a missing theme fails the build before the image is even
assembled.

The **window frame** is proved by running the generator rather than by reading a
file, because there is no hand-written file left to read.
`build_files/55-aquarius-session.sh` builds the theme four times inside the
image — Ice and Midnight, at 1× and at 1.25× — and reads back every value the
design sheet names: the title-bar colours, the border hairlines, the button
sizes that add up to a 38px bar, the menu colours, the corner radius, both
button layouts, all sixteen button pictures in each of the four combinations,
and the GTK chrome file for **both** schemes — its two window colours, and a
rule for each of the three window buttons with its pointer and unfocused states.
Never a timestamp — the tooling that packages a bootable image
flattens every clock.

`build_files/check-labwc-drift.sh` does the same thing across the two
repositories: it runs **both** copies of the generator, the shell's and this
image's, against the same palette, and fails if what they produce differs.

## Bench check for Royce

After rebasing the bench to an image built from this branch:

1. **Log in.** The mouse pointer should be the clean GNOME arrow — the same one
   you saw on the login screen, with no flicker or change of shape as the
   desktop appears.
2. **Look at the app grid and Files.** The icons should be the standard
   coherent GNOME (Adwaita) set — no generic grey squares for the built-in apps.
3. **Trigger a sound.** Plug in a USB drive, or let a notification arrive — you
   should hear the standard freedesktop cue. If you would rather have silence,
   Settings → Sound → *System Sounds* off, and it stays off.

### And for the window frame

Do these in the Aquarius Desktop (not GNOME):

4. **Open a window that lets labwc draw its frame, and look at its title bar.**
   ⚠️ Not Files, Settings, the terminal or any other GNOME app — those draw
   their own title bar inside the window and never show labwc's frame, on any
   compositor (bench, 2026-09-07: this is why "the window theme is not there"
   when it was). The quickest window that does: open **Firefox**, right-click
   its toolbar → **Customize Toolbar…** → tick **Title Bar** at the bottom left.
   Firefox drops its own bar and asks the compositor for one, and the Aquarius
   frame appears at once. DaVinci Resolve shows it too, once installed.
   The frame should be the same colour as the bar at the top of the screen,
   with the title centred, a hairline border, and three round buttons. Click another window: the one you left should fade —
   its title, its border and its buttons all go quieter.
5. **Hover the buttons.** The disc under minimise and maximise should deepen
   slightly. The disc under **close** should go red, with a white ×. Holding the
   mouse down will not darken it further; labwc has no pressed state, and that
   is expected rather than a fault.
6. **Open Files, and look at its header bar.** This is the check for the GTK
   half, added 2026-09-07, and it is the one that was missing before. Files
   draws its own bar, so there is no labwc frame here — but the bar should be
   the same colour as the bar at the top of the screen, and the three buttons in
   its top corner should be **round discs**, not GNOME's flat ones. Put the
   pointer on close: the disc goes **red**. Put it on minimise or maximise: the
   disc only deepens. Now click another window without closing Files — every one
   of Files' buttons should **fade**. Then flip the desktop between light and
   dark and do all of it again: it must look right in **both**, because the file
   behind it is rewritten on every flip. Settings, Ptyxis and Text Editor should
   match Files exactly.
7. **Right-click the wallpaper.** The menu should look like the menu under the
   Aquarius mark in the top bar — same card colour, same hairline, same accent
   wash on the row under the pointer, same typeface.
8. **Flip the colour scheme in Quick Settings.** A Resolve window's title bar
   and the desktop menu should change with the shell, in place, **without
   logging out**. In dark mode a Files window should be navy rather than grey.
   Flip back and it should return to Ice.
9. **Run `aq keys windows` in a terminal.** The buttons should move to the right
   of the title bar — in a GTK window *and* in the labwc frame — without logging
   out. `aq keys mac` puts them back on the left.

If step 8 or step 9 does nothing, the first place to look is
`~/.local/state/aquarius-session/session.log`, and the second is
`~/.config/aquarius/labwc/themerc-override`, which is the file the generator
wrote and which says at the top which theme and which size it was built for.

Nothing here should look dramatic — that is the point. It should look
*intentional and finished* rather than like leftover Fedora defaults, and it
should match the login screen you just came through.

---

# The lock screen

*Added 2026-09-06.*

The last piece of identity a person sees every day, and the one with teeth: the
screen you get when you press **Ctrl+⌘Q** (Mac keys) or **Win+L** (Windows keys), pick **Lock Screen** from the
Aquarius menu, or walk away from the machine.

**The whole design of it lives in the shell repository, at
[`docs/lock-screen.md`](https://github.com/stoneharborent/aquarius-shell/blob/main/docs/lock-screen.md).**
Read that page for what it looks like, the three states it moves through, what
it deliberately never shows, and what is not built yet. This section is only the
operating system's half.

## What this image provides

| What | Where | Why it matters |
| --- | --- | --- |
| The PAM rules | `/etc/pam.d/aquarius-lock` | **Without this file nobody can unlock the machine.** One line: `auth include login`. |
| Locking before sleep | `aquarius-lock-on-sleep.service` + `/usr/libexec/aquarius-lock-on-sleep` | A closed laptop lid, the Sleep row, or an automatic suspend all lock the screen on the way past. |
| `wlopm` | a package | Turns the monitor off after fifteen minutes. Not `wlr-randr --off`, which re-arranges your windows. |
| Ctrl+⌘Q (Mac keys) / Win+L (Windows keys) | `/usr/share/aquarius/labwc/rc.xml` | Runs `qs ipc call lock lock` — a message to the shell that is already running, which is why it is instant. |

All of it is installed and read back by
[`build_files/57-lock-screen.sh`](../../build_files/57-lock-screen.sh), and
checked again on the finished image by the *"Check the lock screen can actually
let somebody back in"* step in CI.

## The one thing to understand about it

**The shell never checks your password, and it must not be able to.** It hands
the typed text to PAM — the part of Linux whose job is answering "is this really
you" — through a small separate process that Quickshell forks for the purpose.
That process asks PAM using the rules named `aquarius-lock`, and those rules say
"use this machine's ordinary login rules". So a fingerprint reader or a password
policy added to the machine reaches the lock screen for free, and nothing
AquariusOS ships needs any special powers: the only privileged step in the whole
chain is Fedora's own `/usr/bin/unix_chkpwd`, which will only ever check the
password of the person who ran it.

That is exactly how `swaylock`, `hyprlock` and `gtklock` work on Fedora, down to
the one-line file in `/etc/pam.d/`.

⚠️ **Two repositories have to agree on one word.** The shell asks PAM for
`aquarius-lock`; this image installs a file by that name. Rename either on its
own and nobody gets into the machine — so both the build step and the CI check
read both sides and compare them.

## Bench check for Royce

Do these in order. Two of them are the ones that would be expensive to get
wrong, and they are marked.

1. **Lock with the keyboard.** Press **Ctrl+⌘Q** in Mac mode (**Win+L** in Windows mode — ⌘L stays the address bar, decided 2026-09-07). The
   screen should be covered *immediately* — no pause, no flash of desktop. You
   should see the clock, big, in the middle, on a frosted version of the
   wallpaper.
2. **Lock from the menu.** Unlock, then click the Aquarius mark → **Lock
   Screen**. It should lock straight away, with no "Confirm?" step.
3. **Lock by walking away.** Leave the machine alone. At five minutes the screen
   should go dark but come straight back when you move the mouse — nothing
   locked. At ten minutes it should lock. At fifteen the monitor should switch
   off, and come back into the lock screen when you touch anything.
4. **Wake, then wait.** Touch a key so the card appears, then do nothing for
   thirty seconds. The card should put itself away and go back to the clock.
5. **⚠️ Type before the card appears.** Lock the screen, then immediately start
   typing your password without pausing. **Every character should be in the box
   when the card appears** — the first three should not be missing. Press Enter.
   The desktop should come back exactly as you left it: same windows, same
   places, nothing restarted.
6. **⚠️ Get it wrong three times.** Type a wrong password and press Enter. The
   box should shake once, grow a red ring, and say so. Do it twice more; after
   the third the line should count down from ten seconds and the box should
   refuse to be typed into until it reaches zero. Then unlock properly.
7. **Flip the theme while locked.** With the machine locked, from another
   machine or a text console, switch the system between light and dark. The lock
   screen should change with it — Ice to Midnight — without being restarted.
8. **Two monitors.** Plug in a second screen and lock. **Both** should show the
   veil and the clock. The card should be on whichever screen the mouse pointer
   is on. Then — and this is the part worth checking — **type on the other one**.
   The dots should still appear in the box, and Enter should still unlock. (The
   compositor decides which screen gets the keyboard and it is not always the
   one with the card; the shell is built for that.)
9. **Sleep and come back.** Pick Sleep from the Aquarius menu, wake the machine,
   and check it asks for a password. On a laptop, close and open the lid and
   check the same.
10. **Do not get locked out.** Before any of this, know the way out: **Ctrl+Alt+F3**
    gives a text login on another console, and from there `loginctl` and
    `loginctl terminate-session <id>` end the graphical session. You lose
    whatever was open, and it is a last resort — but a session lock is a promise
    the compositor keeps even if the shell dies, so it is worth knowing.
