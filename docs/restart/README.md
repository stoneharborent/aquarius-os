# The Restart — what changed, and how to read the new build

*Written 2026-09-03, for Phase R1. Assumes you have never used Linux.*

---

## The one-paragraph version

AquariusOS used to be built on top of **Bazzite**, a gaming operating system.
On 2 September 2026 Royce decided to start over on **bare Fedora** instead. The
reason is not that Bazzite is bad — it is that Bazzite had already made a few
thousand decisions for us, most of them about handheld gaming consoles, and we
were spending our time undoing them instead of building a creator's machine.
Worse, the exact thing Bazzite is best at (shipping the newest possible
software, very fast) is the exact thing DaVinci Resolve on Linux hates most.

So: same family, different starting point. AquariusOS is still Fedora
underneath. It is just Fedora with *nothing on it*, and everything that is on it
now is there because we chose it.

**The long version, with the research behind it, is one folder up:**
[`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md).

---

## Nothing on your computer broke

This is worth saying plainly, because "we started over" sounds alarming.

The six Bazzite-based images are all still in the registry. The old recipe lives
on the `bazzite-archive` branch — it was `main` until 4 September 2026 — and it
is frozen: no new work lands on it, it is not deleted, and it is not going
anywhere.

**The current images are the plain ones:**

| Image | For |
| --- | --- |
| `ghcr.io/stoneharborent/aquarius-os` | AMD and Intel graphics |
| `ghcr.io/stoneharborent/aquarius-os-nvidia` | NVIDIA graphics |

For two days, while both lines were live, the new one published under temporary
names ending in `-next` so that it could not overwrite images real machines were
following. On 4 September 2026 the plain names came home, and every Bazzite
image was given a permanent `bazzite-final` tag first so that none of them could
be lost. The full story, and the exact clicks it took:
[`final-names.md`](final-names.md) and [`history.md`](history.md).

Moving a machine from one image to another is one command on that PC — `bootc
switch`, or `rpm-ostree rebase` on a machine that does not have `bootc` — and it
is reversible with a single command. That is what
[`bench-rebase.md`](bench-rebase.md) walks through.

---

## What R1 actually builds

R1 is called *"it boots and it's ours, from nothing"*, and that is the whole
ambition. When it is done, the bench machine should start up, show a login
screen with the AquariusOS logo, log into an ice-blue GNOME desktop with our
wallpaper and our dock, and say "AquariusOS" in Settings → About.

That is a lower bar than the Bazzite line cleared months ago, and that is fine:
this is starting from an empty room.

### What is in it

- **A computer that works.** Graphics, sound, Wi-Fi, Bluetooth, battery,
  firmware updates, camera cards, Windows drives.
- **A boot screen that is ours.** The Aquarius mark and the word AquariusOS on
  near-black while the machine starts — no Fedora logo and no computer-maker's
  badge — plus the name AquariusOS in the boot menu and over a text login
  prompt. How it works, and the one trap in it:
  [`boot-branding.md`](boot-branding.md).
- **Every codec.** The full ffmpeg, the AAC encoder, hardware H.264 and H.265
  decoding, HEIC photos from iPhones. This is the part Fedora leaves out for
  patent reasons and it is the part a video machine cannot live without.
- **Two desktops.** GNOME *and* KDE Plasma — a deliberately short, hand-written
  list of each, not the whole of either — with our wallpaper, our fonts, our
  logo on the About page and the login screen, and a dock along the bottom of
  GNOME. One login screen lists both and remembers which you picked. See
  [`desktops.md`](desktops.md).
- **The plumbing for what comes next.** Flatpak with Flathub already set up,
  `distrobox` and `podman` ready for the Resolve container, XWayland ready for
  Resolve itself, and the NVIDIA container toolkit already wired in. R3a turned
  all of that into a working **Install DaVinci Resolve** button.
- **`aq-ingest`**, the "Make Editor-Ready" right-click menu — the one feature no
  other operating system ships.
- **btrfs by default**, declared inside the image, so every installer agrees:
  snapshots and transparent compression on a machine that stores video.

### What is NOT in it yet, and when it arrives

| Missing | Comes back in |
| --- | --- |
| ~~The Aquarius Desktop (our own shell), labwc, Quickshell, greetd~~ | **shipped in R2, and RETIRED on 2026-09-15.** AquariusOS ships GNOME and KDE Plasma instead, both on one login screen — see [`desktops.md`](desktops.md). The retired guide: [`history/aquarius-session.md`](history/aquarius-session.md). |
| The AquariusOS logo button in the top-left corner of the screen | **R2** (see below) |
| ~~DaVinci Resolve, in its own Rocky Linux container~~ | **shipped in R3a** — see [`resolve.md`](resolve.md) |
| ~~Aquarius Editor, Aquarius Writer, OBS, Kdenlive, Blender and the rest of the creator suite~~ | **shipped in R3b** — see [`creator-apps.md`](creator-apps.md) |
| ~~Steam, Proton, MangoHud — desktop gaming~~ | **shipped in R4** — see [`gaming.md`](gaming.md) |
| ~~Game Mode — Steam on the whole screen, and the switch both ways~~ | **shipped in G1** (2026-09-17) — see [`game-mode.md`](game-mode.md) |
| ~~A handheld: the ROG Xbox Ally X, booting straight into Game Mode~~ | **shipped in G2** (2026-09-19) as a THIRD image, `aquarius-os-handheld` — see [`handheld.md`](handheld.md) |

Two smaller absences, so they are not mistaken for bugs:

- **No logo in the top bar.** That button came from a GNOME extension called
  Logo Menu, which Universal Blue packages and Fedora does not. Packaging it
  ourselves is an R2 job. Until then the AquariusOS identity lives on the About
  page, the login screen, the wallpaper and in the system's own name.
- **No printing.** Not on this machine's job list, and the printing stack is
  large. One command adds it for anyone who wants it.

---

## How to read the build

Everything the operating system is made of is described by two kinds of file.

### 1. `Containerfile` — the recipe

Think of it as a numbered list: "start from this, then run step 1, step 2, step
3…". It is short, it is heavily commented, and it almost never changes.

The one part of it worth understanding is how *two* images come out of *one*
recipe. There is a switch called `NVIDIA`, it is `0` or `1`, and the recipe uses
a standard trick so that the AMD/Intel build never even downloads the NVIDIA
parts. The comment above that trick in the file explains it properly.

### 2. `build_files/` — the steps

Thirteen numbered scripts, run in order, plus four `stage-` scripts that are not
part of the operating system at all — they compile or fetch the pieces Fedora
does not give us (labwc, Quickshell, the Aquarius Shell, xremap), in throwaway
containers, and only the results are copied in. The numbers on the rest are the
point: the build log reads in the same order as the folder listing, so when
something goes wrong you can find the file by its heading. Numbers are left
spare between them so a new step can be slotted in without renaming everything
after it.

| File | What it does |
| --- | --- |
| ~~`stage-labwc.sh`, `stage-quickshell.sh`, `stage-aquarius-shell.sh`~~ | **Gone, 2026-09-15.** They compiled or fetched the three pieces of the Aquarius Session. Both desktops are Fedora packages now, so there is nothing to compile. See [`desktops.md`](desktops.md). |
| `stage-resolve-menu.sh` | Not part of the operating system. Builds DaVinci Resolve's small menu adapter inside a Rocky Linux 9 container, because it runs inside Resolve's own container and must match its libraries. |
| `aq-lib.sh` | Shared helpers. Read the top of this one first — it explains the "trust content, never timestamps" rule that shapes every check in the repo. |
| `10-repos.sh` | Adds RPM Fusion, so the next step has real codecs to install. |
| `20-hardware-media.sh` | Makes it a working computer: graphics, sound, network, power, firmware, filesystems, and every codec. The biggest step. |
| `20-hardware-media.sh` (the firmware) | **The programs that live inside the hardware.** Every Wi-Fi and Bluetooth vendor, every graphics vendor, laptop speaker amplifiers, laptop webcams, and both CPU makers' microcode — then counts the actual files on disk to prove they landed. ⚠️ Fedora split `linux-firmware` into about thirty per-vendor packages and the leftovers no longer contain any radio; installing only the old name is what left the bench with "No Wi-Fi Adapter Found" on 2026-09-05. Plain-language guide: [`hardware.md`](hardware.md). |
| `30-session.sh` | The invisible layer between "has drivers" and "has a desktop": the login screen, portals, XWayland, Flatpak, fonts, containers — and, since 2026-09-15, the three small programs our own features talk to a person through (`libnotify`, `zenity`, `wlr-randr`). |
| `30-session.sh` (fingerprint login) | Also installs **fprintd + fprintd-pam**. ⚠️ Fedora's stock login rules name a fingerprint step (`pam_fprintd.so`), but the bare base ships the rule without the module, so every login logged "PAM adding faulty module" — the 2026-09-05 bench journal. Installing the module resolves the reference (matching Fedora Workstation) and makes fingerprint login work on laptops that have a reader; on a machine without one it sits idle. CI now also fails the build if any `/etc/pam.d` rule *requires* a module that is not installed (silent-optional `-` lines, like keyring and wallet, are honoured and skipped). Plain-language guide: [`login.md`](login.md#the-faulty-pam-module-at-every-login). |
| `50-aquarius-desktop.sh` | Makes it *ours*: wallpaper, logos, Ice theme, fonts, dock, the right-click ingest menu. |
| `40-gnome-desktop.sh` | GNOME — a hand-written short list, with a note on everything deliberately left out. Also installs the **desktop-identity themes** (Adwaita cursor + icons, freedesktop sounds) and checks they are really on disk. See [`desktop-identity.md`](desktop-identity.md). |
| `50-aquarius-desktop.sh` | Makes it *ours*: wallpaper, logos, Ice theme, fonts, dock, the right-click ingest menu, and the **cursor / icon / sound defaults** that match the login screen. See [`desktop-identity.md`](desktop-identity.md). |
| `41-kde-desktop.sh` | **KDE Plasma — the second desktop**, a hand-written short list in the same shape as step 4, with a note on everything deliberately left out. ⚠️ **No sddm, no Discover, no plasma-welcome**, and the build fails if any of them arrives as somebody else's dependency: AquariusOS has one login screen, one app store and one welcome. Also installs the Breeze pieces our own GTK windows need on Plasma, and sets GNOME as the desktop a brand-new account lands in. See [`desktops.md`](desktops.md). |
| ~~`55-aquarius-session.sh`, `57-lock-screen.sh`, `78-rfkill.sh`~~ | **Gone, 2026-09-15**, with the Aquarius Session they belonged to. What they installed that was NOT about a desktop — `libnotify`, `zenity`, `wlr-randr` — moved up into `30-session.sh`. See [`desktops.md`](desktops.md) and [`history/aquarius-session.md`](history/aquarius-session.md). |
| `58-kernel-pin.sh` | **Which kernel AquariusOS ships.** Pins it to the one Universal Blue's ready-made, already-signed kernel modules were built for — the NVIDIA driver, the OBS virtual camera and the two Xbox controller drivers all depend on it exactly. Runs on BOTH images and before every step that installs a module. See [`kernel.md`](kernel.md). |
| `60-nvidia.sh` | The NVIDIA driver. Does nothing on the AMD/Intel image. The hardest file in the repo — see [`nvidia-notes.md`](nvidia-notes.md). |
| `62-resolve-runtime.sh` | **DaVinci Resolve — everything except Resolve.** Resolve itself may not be shipped by anybody but Blackmagic, so this puts in place the setup that builds a Rocky Linux container on the user's own machine and installs their own download into it, plus the launcher, the `aq resolve` commands, the USB rules for licence dongles, the graphics-card plumbing, and — since 2026-09-08 — the update flow: a once-a-day check against Blackmagic's release list, one notification when there is something newer, and an "Update DaVinci Resolve" window. Why a container at all: [`resolve.md`](resolve.md). |
| `62-resolve-runtime.sh` (the windows) | Also checks the two DaVinci Resolve windows — Install and Remove — the shared window pieces in `/usr/lib/aquarius/python/aquarius_ui.py`, and the rule that nothing a person reads may name another Linux. |
| `70-image-info.sh` | Teaches the system to call itself AquariusOS. |
| `73-keys-kcm-build.sh` | ⚠️ Does NOT run inside AquariusOS. A throwaway container that compiles ONE small thing: the **"Mac or Windows" page in KDE's System Settings** (source in `kcm/aquarius-keys/`). A page in System Settings has to be a compiled program on Plasma 6 — the CMakeLists sets out the evidence. The compiler stays in the workshop; about 100 KB crosses into the image. |
| `74-xremap-build.sh` | ⚠️ Does NOT run inside AquariusOS. It runs in a throwaway container whose only job is to compile the keyboard remapper, so that a compiler never ends up in the finished operating system. |
| `75-aquarius-keys.sh` | Mac-style keyboard shortcuts, on by default — Copy is Command-C. Installs what the two steps above built, and checks the whole feature. Since 2026-09-16 that includes both **graphical switches** for the Mac-or-Windows choice: our GNOME toggle in the quick settings menu and the KDE System Settings page. Since 2026-09-17 it also checks that the choice is **the keyboard only** — the window buttons are stock and on the right for everybody, and accounts that had them moved before that date are put back once at login. Plain-language guide: [`aquarius-keys.md`](aquarius-keys.md). |
| `62-virtual-camera.sh` | The fake webcam behind OBS Studio's "Start Virtual Camera" button. Takes a ready-made, already-signed kernel module from Universal Blue. ⚠️ Must run after `58-kernel-pin.sh`, which sometimes replaces this image's kernel. Since 2026-09-04 a mismatch STOPS the build instead of quietly leaving the feature out — see [`kernel.md`](kernel.md). |
| `64-creator-apps.sh` | **The creator layer.** Bakes **Aquarius Writer** into the image; checks that **Aquarius Editor is NOT in it** and that everything which fetches it on a real machine is; checks the list of creator Flatpaks against Flathub; validates the extra permissions those apps need; switches the permissions service on (and deliberately leaves the bulk app installer OFF, because the chooser at first login asks the person which apps they want); and promotes the ingest helper. ⚠️ Until 2026-09-04 it also baked in Aquarius Editor, which is 4.1 GB — that is where roughly four of this image's gigabytes used to go. See [`creator-apps.md`](creator-apps.md). |
| `66-creator-apps-chooser.sh` | **The window that offers those apps to a person** — "Your creator apps" at the first login, "Aquarius Apps" in the app grid afterwards. Installs what a GTK window needs to run from Python, checks both menu entries, checks that nothing installs itself any more, checks that **choosing only Aquarius Editor asks for no password at all** and that choosing both kinds runs two installers behind one progress bar, and — the check that matters — reads the real list in the finished image with the window's own parser. See [`creator-apps.md`](creator-apps.md). |
| `67-welcome.sh` | **The welcome** — the window a brand-new person meets first, ten seconds after their first login: how the keyboard should work (Mac or Windows, Mac preselected), then the creator-apps window above as its second step, then a page of three tips. Checks that Mac is still the preselected answer, that the keyboard answer is written by `aq keys` and by nothing else, that an account which already chose its apps is not asked again, and that the OLD first-login entries are gone from both sessions. See [`welcome.md`](welcome.md). |
| `65-installer.sh` | *(2026-09-09)* **Aquarius Installer** — the one app that installs anything. Adds the window, the part that decides (the sorter, the routes, the registry), the app-grid entry and the file-type names Linux does not have, and the tools the routes need (`cpio`, `dpkg-deb`). Then it reads all of it back: the menu entry validates, the shared decider imports with no screen at all, **the desktop's own tool agrees that double-clicking an `.rpm` opens us**, the older app chooser is hidden so there is one visible app, and the installer's own rehearsal really unpacks a real archive into a throwaway home folder, really refuses a payload that wants the operating system, really writes a menu entry and really removes it. See [`installer-app.md`](installer-app.md). |
| `68-gaming.sh` | **The gaming layer.** Adds Terra (and switches it straight off again), installs Steam, umu-launcher, gamescope, gamemode, MangoHud, vkBasalt and the 32-bit graphics libraries a Windows game needs, takes the Xbox controller drivers from the same signed module box as the virtual camera, and proves that none of it replaced Fedora's graphics driver. ⚠️ Must run after `58-kernel-pin.sh`, for the same kernel reason as `62-virtual-camera.sh`. See [`gaming.md`](gaming.md). |
| `71-game-mode.sh` | **Game Mode (Phase G1, 2026-09-17).** Steam owning the whole screen, driven with a controller, and a password-free switch both ways. Takes three packages from Terra completely unmodified (the session, its Steam half, and Valve's handheld service — installed but left asleep), then adds AquariusOS's own half of the switch, which nobody had written for GDM: `/usr/libexec/os-session-select`, a polkit-gated root helper, a "Return to Game Mode" launcher, `aq game`, and a once-per-boot service that keeps a cold boot honest. ⚠️ **A cold boot on these images is unchanged** — `/etc/aquarius/login-mode` ships as `desktop` and the build fails if it ever ships as `game`. ⚠️ Must run AFTER `68-gaming.sh`, which removes Terra on its way out. See [`game-mode.md`](game-mode.md). |
| `78-handheld.sh` | **The handheld layer (Phase G2, 2026-09-19).** The whole of the third image, `aquarius-os-handheld`, built for exactly one computer: Royce's ROG Xbox Ally X (board `RC73XA`). Adds InputPlumber (so the built-in controller reaches Steam as ONE Xbox pad with its paddles and its gyro), Valve's `steamos-manager` and `powerstation` **switched on** so Steam's power sliders move real hardware, the power-button daemon, and two small udev rules about sleep — and ships `/etc/aquarius/login-mode` as `game`, because a handheld with no keyboard cannot get past a password box. ⚠️ **No kernel change of any kind**: Fedora's kernel already drives this machine. ⚠️ On the two DESKTOP images this step installs nothing at all and instead **proves that none of it arrived** — that is the standing guarantee that phase G2 cannot change the computer Royce edits on. ⚠️ Must run AFTER `71-game-mode.sh`, both for Terra's sake and because it replaces the `steamos-manager` that step installs. See [`handheld.md`](handheld.md). |
| `81-decky.sh` | **Decky Loader — OFFERED, never baked (Phase G3, 2026-09-19).** Decky adds a plugins menu INSIDE Game Mode: in Steam's full-screen interface, the "..." button grows a tab with a plug on it — battery readouts, per-game power profiles, screen recorders. ⚠️ **It only ever appears in Game Mode**; Steam in a window on the desktop will never show it. ⚠️ **This step installs no Decky.** Decky is somebody else's program, downloaded from GitHub, run as a background service AS THE ADMINISTRATOR, and its service file names ONE person's home folder — so it is offered, never baked (standing decision 4). The step adds `jq` (which reads GitHub's answer about the newest release), reads back the `aq decky install / update / remove / status` command and the "Decky Loader" launcher, and then **proves the absence** of everything else: no `plugin_loader.service`, no `/home/deck`, no downloaded `PluginLoader`, no `~/homebrew`. ⚠️ Not gated, unlike `78-handheld.sh` — every image has Game Mode, so every image offers Decky. See [`decky.md`](decky.md). |
| `72-gamescope-build.sh` | **A builder stage, NVIDIA image only.** Compiles our own gamescope from one pinned commit carrying the fix for NVIDIA's scan-out corruption (NVIDIA bug 5240452 — Steam draws correctly and a staircase band of another program's window sits across the middle). Installed *beside* Fedora's, never over it, and used only by the Game Mode session. The AMD/Intel image skips the whole stage and keeps Fedora's gamescope. Retires when the fix reaches upstream. See [`game-mode.md`](game-mode.md#-why-the-nvidia-image-carries-its-own-gamescope-and-the-amd-one-does-not). |
| `69-homebrew.sh` | **Homebrew — the `brew` command**, on both images (Royce, 2026-09-12). Installs it for real, packs it into one compressed file in `/usr`, and deletes it from `/var` again. ⚠️ That back-to-front shape is the whole point: Homebrew insists on living under `/home`, which on this system is `/var`, and `/var` is never replaced by an update — so a copy baked in there would reach machines installed from a disc and never reach a machine that simply updated. The copy in `/usr` is carried by every update and unpacked on the machine by `aquarius-brew-setup.service`. Same shape as Universal Blue's, with our own ownership rule. See [`homebrew.md`](homebrew.md). |
| `77-updater.sh` | **"Check for Update".** The window the Aquarius logo menu opens, and `aq update` in a terminal. Checks the whole step: bootc is there, the program loads, every page carries the Aquarius mark, the rehearsal runs, `aq update` is wired in — and, since 2026-09-13, that the two tools the check reads from are present and that its own test passes in the image. ⚠️ **Checking asks for no password; only updating does.** See [`updater.md`](updater.md). |
| `83-remembered-drives.sh` | **An INSIDE drive asks once, then opens at every login** (Royce, 2026-09-14, FEATURES 020). A second SSD or the Windows disk used to ask for an administrator password at every single login. Now AquariusOS asks once per drive and writes one UUID-keyed line into `/etc/fstab`, where mounting does not go through polkit at all. ⚠️ The narrow rule in `49-aquarius-udisks.rules` is **unchanged**, and the gate in `76-automount.sh` that stops the build if it ever widens is untouched — that is the whole point of the design. This step checks the privileged helper, both polkit files, the question the agent asks, and runs the real decision code against fake drives, because the drives it must **refuse** are the safety. See [`hardware.md`](hardware.md#why-an-inside-drive-asks-once-and-an-outside-drive-never-asks). |
| `84-swift.sh` | **Swift comes with the OS** (Royce, 2026-09-14, FEATURES 022). `swift --version` answers on a brand-new machine, the way `python3 --version` already does: the compiler, `swift build` / `swift run` / `swift package`, the REPL, Foundation and `sourcekit-lsp`, from Fedora's own `swift-lang` packages. ⚠️ Swift.org's `swiftly` installer **refuses Fedora** ("Unsupported Linux platform"), so the RPM is the supported path — never a tarball from swift.org. ⚠️ It is the **largest single thing on the image**, about 3 GB, and Royce accepted that cost knowingly; the step prints the real measured size every build. The check that matters is not the version string but a real hello-world built and run with `swift build` and `swift run` in a throwaway folder. See [`swift.md`](swift.md). |
| `80-boot-branding.sh` | Everything you see BEFORE the login screen: the Aquarius boot splash, the name in the boot menu, the text login banners — and a rebuild of the boot ramdisk, without which none of it takes effect. ⚠️ Must run after `58-kernel-pin.sh`; see [`boot-branding.md`](boot-branding.md). |
| `90-cleanup.sh` | Sweeps up, refuses to ship an image with two kernels in it, and re-checks that the kernel is still the one `58-kernel-pin.sh` pinned. |

### There is a SECOND recipe, and it does not build the operating system

`resolve-runtime/Containerfile` builds a small **Rocky Linux** that DaVinci
Resolve runs inside. It is its own image, with its own build
(`.github/workflows/build-resolve-runtime.yml`), and it is downloaded onto a
machine the first time somebody sets Resolve up — never before, because it is
about a gigabyte and not everybody uses it.

It exists because Resolve carries its own copy of a library from 2021 that
clashes with any modern Linux's own and kills it before its window opens.
Enterprise Linux still carries the matching version, so in there the clash
cannot happen. The whole argument is in [`resolve.md`](resolve.md).

There is **no DaVinci Resolve inside it**, and there never will be —
Blackmagic's licence does not allow anyone else to distribute their installer.
Both builds check for its absence and refuse to publish an image containing it.

### 3. `system_files/` — files that are copied in as-is

Whatever is in here is copied to the same place on the finished system. To add
a file to the operating system, put it in the right place under `system_files/`
— there is no list anywhere to update.

The interesting ones are the four `zz1-aquarius-*.gschema.override` files,
which are GNOME's factory settings replaced with ours. Each one has a long
plain-English header explaining what it does and, more usefully, what it
deliberately does *not* do.

A few more worth knowing about, all added in R3b:

| Path | What it is |
| --- | --- |
| `usr/share/flatpak/preinstall.d/aquarius-creator-apps.preinstall` | The shopping list of creator apps. Adding or removing an app is a one-block edit here. |
| `usr/share/aquarius/flatpak-overrides/` | The extra permissions those apps need — a camera for OBS, an external drive for Kdenlive. Its `README.md` explains why they cannot simply be shipped where Flatpak reads them. |
| `usr/libexec/aquarius-creator-apps` | **The app chooser window.** Opens itself once at the first login, and lives in the app grid as "Aquarius Apps". Knows no app names of its own — it reads them from the two files above. |
| `usr/libexec/aquarius-creator-apps-install` | The part that actually installs the **Flathub** apps, one at a time, as an administrator. The window starts it through `pkexec`, which is where the single password prompt comes from. |
| `usr/libexec/aquarius-appimage-install` | *(2026-09-04)* The **other** installer: our own apps, from their GitHub release, into the person's own home folder — no password, no `pkexec`, and it refuses to run under `sudo`. Aquarius Editor is the first app to go through it. It also removes one again and answers "is mine the version this OS offers?". |
| `usr/share/aquarius/apps/catalog.ini` | The human words for every app the chooser shows — the name, the sentence, the shelf, and whether it is ticked by default. Since 2026-09-04 an entry may also be one of ours rather than a Flatpak, in which case it carries the GitHub repository and the **pinned release**. Changing that `Pin=` line is how AquariusOS offers a new Aquarius Editor. |
| `usr/share/aquarius/apps/aquarius-editor.desktop.in` | *(2026-09-04)* The menu entry the installer writes into each person's `~/.local/share/applications/`. It has to be in the image because the app is not. |
| `usr/share/aquarius/gaming/README.md` | *(R4)* The plain-language gaming note that ships inside the OS. Next to it, `controllers.txt` is written by the build and is the honest answer to "are the Xbox drivers in this image?". |
| `usr/share/applications/aquarius-steam-bigpicture.desktop` | *(R4)* **Steam (Big Picture)** in the app grid — the desktop's answer to a console interface, with no separate session behind it. |
| `usr/lib/aquarius/python/aquarius_installer.py` | *(2026-09-09)* **The part of Aquarius Installer that decides.** The sorter (what is this file?), the routes (how does it land?) and the registry (what happened, so that removing it is exact). It has no window in it, which is what lets the window, `aq apps` and the tests be one implementation. |
| `usr/libexec/aquarius-installer` | *(2026-09-09)* **Aquarius Installer** — the window a downloaded `.rpm`, `.deb`, AppImage, `.flatpakref` or tarball opens into. Also removes an app, updates everything at once, and searches. Runs with no screen at all for the build's checks (`--sort`, `--install`, `--list`, `--remove`, `--updates`, `--search`, `--dry-run`). See [`installer-app.md`](installer-app.md). |
| `etc/xdg/mimeapps.list` | *(2026-09-09)* What makes a double-click on a download actually open Aquarius Installer. ⚠️ In `/etc` on purpose: it is a preference, and somebody who wants a different answer should be able to change it and keep the change through every update. A `.zip` and a `.sh` are deliberately NOT claimed. |
| `usr/share/mime/packages/aquarius-installer.xml` | *(2026-09-09)* Names for the file types the shared Linux list has none for — `.run`, and useful ones for `.snap` and `.pkg`. Without a name, a file cannot be offered an app to open it with, so double-clicking it does nothing at all. |
| `usr/libexec/aquarius-welcome` | *(2026-09-04)* **The welcome.** Three steps — keyboard style, creator apps, tips — shown once, at a first login. It writes no settings file of its own: step 1 runs `aq keys`, and step 2 runs the chooser above as a child program. See [`welcome.md`](welcome.md). |
| `usr/libexec/aquarius-updater` | **Check for Update** — one program that is both the window and the `aq update check` / `aq update apply` commands. It compares the fingerprint of the image you booted against the newest published one, which needs no password at all; only the Update button asks, once. See [`updater.md`](updater.md). |
| `usr/libexec/aquarius-brew-setup` | *(2026-09-12)* **The first-boot Homebrew unpack.** Runs at every boot and does nothing almost every time — that is what lets an update deliver `brew` to a machine installed before Homebrew existed. Its guard is proved by `tests/test-brew-setup.sh`, which runs it twice. |
| `usr/libexec/aquarius-brew-update` | *(2026-09-12)* The weekly `brew update`. Refreshes the catalogue and deliberately does **not** run `brew upgrade` — see [`homebrew.md`](homebrew.md). |
| `etc/profile.d/aquarius-brew.sh` | *(2026-09-12)* What makes `brew` work in a terminal. ⚠️ It puts Homebrew at the **end** of PATH, not the front as Homebrew's own instructions say, so that brew's copies of `bash`, `systemd` or `dbus` can never beat Fedora's. |
| `usr/lib/environment.d/70-aquarius-brew.conf` | *(2026-09-12)* The same, for apps started by **clicking** — they never read a profile file. Without it a brew tool works in a terminal and is missing from an app opened off the dock. |
| `etc/xdg/autostart/aquarius-welcome-firstrun.desktop` | What opens the welcome at a first login. **One file, both desktops** — GNOME and KDE Plasma both read `/etc/xdg/autostart`. ⚠️ Until 2026-09-15 the same fact had to be written down a second time for the Aquarius Session, which read only its own file; that copy, and the chance of the two drifting, are gone. *(It replaced `aquarius-creator-apps-firstrun.desktop` on 2026-09-04; the build fails if that one comes back.)* |
| `etc/xdg/kglobalshortcutsrc` | *(2026-09-15)* The Mac shortcuts that have to reach **KDE Plasma itself**: Command-Tab, Command-\`, Command-Space and Control-Command-Q, added to KWin's own bindings rather than replacing them. GNOME answers the first two out of the box; `zz1-aquarius-40-keys.gschema.override` gives it the lock key. ⚠️ In `/etc` so that changing a shortcut in System Settings beats it and survives updates. |

---

## Every step checks its own work

This is the habit that matters most in this repo, and it comes from a real
failure.

On 31 August 2026 a build step decided whether it had done its job by checking
whether one file was *newer* than another. That works on a normal computer. It
is meaningless here, because the tool that packages a bootable image sets every
file's clock to the same value. The check passed every time — including the
times the step had silently done nothing at all.

So: **every check reads actual content.** The text inside `/etc/os-release`. The
value `gsettings` reports when asked. The answer `rpm` gives. The checksum of a
picture. Never a date, never "is this file newer than that one".

It happens twice, on purpose:

1. **During the build**, inside each step, so a failure names the step.
2. **After the build**, in GitHub Actions, by starting the finished image and
   interrogating it the way a real machine would — before anything is published.

The second one is why `.github/workflows/build.yml` is long. It is not
ceremony. It is the difference between "the build was green" and "the image
actually works".

---

## Building it

You do not need a Linux computer. GitHub builds the OS.

- **Every push to `main`** builds and publishes both images. Watch it at
  GitHub → Actions → *Build AquariusOS*.
- **Installer ISOs are built by hand** when they are needed: Actions →
  *Build AquariusOS ISO* → **Run workflow**, pick the variant. It takes 20–40
  minutes and the ISO appears at the bottom of the run's page.

  Pushing a tag named `iso-base-…` or `iso-nvidia-…` does the same thing and is
  the way to build an ISO from a branch. Before 4 September 2026 it was the
  *only* way, because GitHub only shows the "Run workflow" button for workflows
  on the repository's default branch, and this line was not on it yet.

If you *do* have a Linux machine with `podman` on it, `just build` does the same
thing locally. `just` with no arguments lists everything available.

---

## The rules that do not move

1. **Never merge `bazzite-archive` and `main`.** `bazzite-archive` is the
   frozen Bazzite line, kept exactly as it was on the day it stopped.
2. **The images are `aquarius-os` and `aquarius-os-nvidia`.** The temporary
   `-next` names are retired, and the build fails if one reappears outside a
   history note.
3. **One recipe.** The NVIDIA difference is a switch, not a second Containerfile.
   Adding a second recipe is how two images quietly drift apart.
4. **Read the result back.** Content, never timestamps.
5. **Plain language everywhere.** Every file in this repo is written for someone
   who has never used Linux, because that is who has to maintain it.

---

## Where to go next

- **Taking the real names, step by step (the clicks Royce makes):** [`final-names.md`](final-names.md)
- **What the Bazzite line left behind, and how to get any of it back:** [`history.md`](history.md)
- **How the retired Aquarius Session worked (history only):** [`history/aquarius-session.md`](history/aquarius-session.md)
- **Moving the bench machine over:** [`bench-rebase.md`](bench-rebase.md)
- **How the boot screen and the boot menu are branded:** [`boot-branding.md`](boot-branding.md)
- **The welcome — the first three minutes of a new machine:** [`welcome.md`](welcome.md)
- **The creator apps: what ships, how it arrives, how to remove one:** [`creator-apps.md`](creator-apps.md)
- **Installing anything you have downloaded — double-click it and it just installs:** [`installer-app.md`](installer-app.md)
- **Making camera files open in an editor (the ingest helper):** [`ingest.md`](ingest.md)
- **Mac-style keyboard shortcuts (Copy is Command-C):** [`aquarius-keys.md`](aquarius-keys.md)
- **⭐ Changing Mac or Windows WITHOUT a terminal — the switch in GNOME's top-right menu and the page in KDE's System Settings:** [`aquarius-keys.md`](aquarius-keys.md#-the-switch-without-a-terminal)
- **How big things are on the screen (and why it was too small):** [`aquarius-display.md`](aquarius-display.md)
- **The pointer, the icons and the system sounds (and the seam for real Aquarius artwork later):** [`desktop-identity.md`](desktop-identity.md)
- **⚠️ The wallpaper that stayed pale when the desktop went dark (8 September 2026), and the program that now swaps it:** [`desktop-identity.md`](desktop-identity.md#the-wallpaper)
- **⭐ Two desktops, one login screen — how to pick, what each one is, what is the same on both:** [`desktops.md`](desktops.md)
- **The login screen — why it looked like stock Fedora, and the two answers:** [`login.md`](login.md)
- **⚠️ The BLACK login screen — twice, 4 and 5 September — and why AquariusOS now gives the login screen no display file at all:** [`login.md`](login.md#the-black-login-screen--twice-4-and-5-september-2026)
- **DaVinci Resolve — installing it, and why it lives in a container:** [`resolve.md`](resolve.md)
- **Gaming: what ships, the launch options worth knowing, and what is deliberately not here:** [`gaming.md`](gaming.md)
- **Game Mode — Steam on the whole screen, how to switch both ways, the boot setting, and why the NVIDIA image carries its own gamescope:** [`game-mode.md`](game-mode.md)
- **Decky Loader — the plugins menu inside Game Mode: what it is, how to install it, where the plug tab is, that it runs as root and listens only to this computer, and what to do when the icon is not there:** [`decky.md`](decky.md)
- **⚠️ The handheld image — what `aquarius-os-handheld` is, how to install it on the ROG Xbox Ally X (including the controller-chip firmware you must check IN WINDOWS first), what works, what does not yet, `aq handheld status`, and the bench list:** [`handheld.md`](handheld.md)
- **Homebrew — the `brew` command, why it is unpacked at first boot rather than baked in, and what it is (and is not) for:** [`homebrew.md`](homebrew.md)
- **Swift — it is already installed, the five steps to build and run something, and the honest list of what does NOT work (no SwiftUI/AppKit/UIKit, and why the Mac Aquarius apps still do not run here):** [`swift.md`](swift.md)
- **Wi-Fi, Bluetooth and graphics firmware — what it is and how to check it:** [`hardware.md`](hardware.md)
- **⚠️ An external drive that is not there AT ALL — the USB4 / Thunderbolt controller that did not wake up on 7 September 2026, and the retry that now ships (unverified on real hardware):** [`usb4.md`](usb4.md)
- **Reading a drive that came off a Mac — what works, why it is read-only for ever, FileVault, and the disks no PC can read:** [`mac-drives.md`](mac-drives.md)
- **Why a drive INSIDE the computer asks once and then never again, which drives it will never offer, and how to undo a choice (`aq drives`):** [`hardware.md`](hardware.md#why-an-inside-drive-asks-once-and-an-outside-drive-never-asks)
- **Which kernel AquariusOS ships, and why it is pinned:** [`kernel.md`](kernel.md)
- **Why the NVIDIA driver is done the way it is:** [`nvidia-notes.md`](nvidia-notes.md)
- **Why Fedora and not Bazzite/Arch/Ubuntu:** [`../base-distro-reassessment-2026-09.md`](../base-distro-reassessment-2026-09.md)
- **The plan for R2, R3 and R4:** `ROADMAP.md`, one folder above the repo
