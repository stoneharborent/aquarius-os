# Gaming on AquariusOS

*This note ships inside the operating system, at
`/usr/share/aquarius/gaming/README.md`. The longer, friendlier version is in the
repository at `docs/restart/gaming.md`.*

---

## What is already here

Nothing to install, nothing to set up:

| Thing | What it is for |
| --- | --- |
| **Steam** | The game shop and launcher. In the app grid, and in "Your creator apps" under **Included with AquariusOS**. |
| **Proton** | Runs Windows games on Linux. It arrives with Steam and turns itself on. |
| **gamescope** | Gives a game its own private screen — useful for locking resolution or frame rate. |
| **gamemode** | A temporary performance boost while a game is running. Starts when asked, stops after. |
| **MangoHud** | The frame-rate and temperature overlay. **Off** until you ask for it. |
| **vkBasalt** | Optional sharpening and colour effects for games. Off until asked for. |
| **umu-launcher** | Runs a Windows game through Proton from outside Steam. Heroic and Lutris use it. |
| **protontricks / winetricks** | Per-game fixes for Windows titles. |
| **Xbox controller drivers** | `xone` for the Xbox wireless dongle, `xpadneo` for Xbox Bluetooth. See below. |

PlayStation controllers (DualShock 4, DualSense) need none of this — Linux
supports them over USB and Bluetooth by itself.

## The three things worth knowing

**1. Steam downloads itself on first launch.** The first time you open Steam it
fetches a few hundred megabytes of its own runtime before the login window
appears. That is Steam's design, not a fault, and it only happens once.

**2. The overlay is off until you ask for it.** To see frame rate and
temperatures in a game: Steam → right-click the game → Properties → Launch
Options, and type `mangohud %command%`. Delete it to turn the overlay off again.

**3. There is no Game Mode session and no handheld support**, on purpose. This
is a desktop gaming machine. See `docs/restart/gaming.md` for why.

## Did the Xbox drivers make it into this image?

    cat /usr/share/aquarius/gaming/controllers.txt

`xone=installed` and `xpadneo=installed` mean yes. `unavailable` means the
ready-made drivers were built for a different kernel than this image runs — it
happens for a day or two after a Fedora kernel update, the next update of
AquariusOS fixes it, and every other controller keeps working meanwhile.
