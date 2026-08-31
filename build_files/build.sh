#!/bin/bash
# =======================================================================# ==============================================================================
# AquariusOS build script
# ==============================================================================
# This is THE file you edit to change what's in AquariusOS.
# It runs inside the build, on top of Bazzite, when GitHub Actions builds the OS.
#
# Rules of thumb:
#   - Install system packages with `dnf5 install -y <package>`
#   - Copy files into the OS by putting them in system_files/ (mirrors "/")
#   - Keep it small. Every package added is a package we own forever.
#
# If a line here fails, the whole build fails and no broken OS ships. That is by
# design ("set -e" below) — a red X in the Actions tab means nothing was released.
# ==============================================================================

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# ==============================================================================
# WHICH DESKTOP IS THIS IMAGE WEARING?
# ==============================================================================
# "kde" or "gnome". It comes in from the Containerfile, which gets it from the
# Justfile, which works it out from the variant name. The whole chain is
# explained at the top of the Containerfile.
#
# ⚠️ WHY THIS EXISTS AT ALL. This file's house rule is "no variant branching",
# and it is a good rule. But a few steps below do not merely have nothing to do
# on the other desktop — they cannot run there at all. Compiling a KWin plug-in
# needs a KWin to compile against, and a GNOME image has none: that step would
# not be a harmless no-op, it would be a red build. So there is ONE knob, it
# holds one of two words, and every place it is read says out loud why the step
# it guards belongs to one desktop and not the other.
#
# The `:-kde` fallback is the same spelling as AQ_IMAGE_NAME further down, and
# for the same reason: this script runs under `set -u`, so an unset variable
# would abort the build here rather than fall through to the sensible default.
# "kde" is the sensible default because it is what every AquariusOS image was
# before 2026-08-31.
AQ_DESKTOP="${AQ_DESKTOP:-kde}"

case "${AQ_DESKTOP}" in
  kde | gnome)
    echo "OK: building the ${AQ_DESKTOP} flavour of AquariusOS."
    ;;
  *)
    echo "AQUARIUS ERROR: AQ_DESKTOP is '${AQ_DESKTOP}'. It must be 'kde' or 'gnome'."
    echo "                Nothing else means anything to this script, and guessing"
    echo "                would produce an image with half a desktop's settings on it."
    exit 1
    ;;
esac

# Belt and braces: prove the word matches the image we are actually standing in.
# Getting this pair wrong is the one mistake that would be invisible until
# somebody booted the result — a GNOME image built as "kde" would come out with
# no AquariusOS look on it at all, and a completely green build.
#
# ⚠️ NOTE THE ASYMMETRY, IT IS DELIBERATE. The GNOME case stops the build; the
# KDE case only warns. The KDE line is frozen and its images must keep building
# no matter what, so nothing new is allowed to become a way for them to fail. A
# wrong-looking KDE build says so loudly in the log and carries on. A wrong
# GNOME build stops, because everything the GNOME layer does after this point
# depends on GNOME actually being here.
if [ "${AQ_DESKTOP}" = "gnome" ] && ! command -v gnome-shell > /dev/null 2>&1; then
  echo "AQUARIUS ERROR: AQ_DESKTOP=gnome but this image has no gnome-shell command."
  echo "                It was almost certainly built on a KDE Bazzite base by mistake."
  echo "                Check the BASE_IMAGE and AQ_DESKTOP build arguments agree."
  exit 1
fi
if [ "${AQ_DESKTOP}" = "kde" ] && ! command -v plasmashell > /dev/null 2>&1; then
  echo "AQUARIUS WARNING: AQ_DESKTOP=kde but this image has no plasmashell command."
  echo "                  If that is a surprise, the BASE_IMAGE and AQ_DESKTOP build"
  echo "                  arguments probably do not agree. Carrying on regardless —"
  echo "                  the KDE line is frozen and must keep building."
fi

# ==============================================================================
# PHASE 1 — "It boots and it's ours"  (current phase)
# ==============================================================================
# Deliberately minimal. The only job of Phase 1 is to prove the pipeline works:
# push a change -> GitHub builds -> a bootable AquariusOS image appears.
#
# htop is a tiny, harmless terminal system monitor. It exists here purely as
# proof that our customization layer is really being applied on top of Bazzite.
# If you boot AquariusOS and `htop` runs, the whole build chain works.
# ------------------------------------------------------------------------------

dnf5 install -y htop

# ==============================================================================
# THE AQUARIUSOS LOOK — fonts
# ==============================================================================
# The design uses three typefaces. All three are free and open-source, so all
# three can legally ship inside the OS.
#
#   Inter           — everything you read in the interface: menus, buttons,
#                     dialogs, labels.
#   JetBrains Mono  — code and the terminal.
#   Sora            — headlines and display text.
#
# Two of them are already packaged by Fedora, so we just ask for them by name.
# A useful side effect: both of those packages also tell the system "when
# something asks for a plain sans-serif font, give it Inter" and "when something
# asks for a monospace font, give it JetBrains Mono". That is exactly the
# behaviour we want, so we get the default fonts for free.
#
# Deliberately NOT installed:
#   rsms-inter-vf-fonts     the variable-font build of Inter. Its font family is
#                           registered as "Inter Variable", not "Inter", so apps
#                           asking for "Inter" would not find it. Confusing for
#                           no gain.
#   jetbrains-mono-fonts-all  drags in the "NL" (no-ligatures) variant too. We
#                           only want the normal one.
# ------------------------------------------------------------------------------

dnf5 install -y rsms-inter-fonts jetbrains-mono-fonts

# Sora is not packaged by Fedora — by anyone, in fact — so the font file itself
# is committed into this repo and copied in by the system_files step above:
#   /usr/share/fonts/sora-fonts/Sora[wght].ttf
#   /usr/share/licenses/sora-fonts/OFL.txt   (the licence must ship with it)
# Where it came from and how to update it: ../branding/README.md.
#
# Now the important bit. Linux keeps an index of every installed font, and that
# index is only rebuilt automatically when a font arrives as an installed
# PACKAGE. Sora arrives as a plain copied file, so nothing rebuilds the index
# and the font would be invisible to every app. This command rebuilds it by hand.
#
# It must run AFTER both the system_files copy and the dnf5 line above, so it
# catches all three fonts in one pass.
#
#   --system-only  write the index into /usr/… (part of the image) and not into
#                  a user's home folder, which on this kind of OS lives in a
#                  place that gets thrown away at build time.
fc-cache --system-only --force --verbose

# ==============================================================================
# THE AQUARIUSOS FLOW — the full-screen app grid
# ==============================================================================
# The top bar's launcher is the "Application Dashboard" — click the AquariusOS
# logo and a full-screen, searchable grid of every app appears. That widget is
# not part of KDE's core; it lives in a package called `kdeplasma-addons`, which
# also carries a pile of other small Plasma widgets.
#
# Fedora's KDE images almost certainly ship this already, so this line will
# usually be a no-op that costs a second of build time. It is here as insurance:
# the desktop layout script names the widget explicitly, and a layout that names
# a widget the machine does not have gives a brand-new user a broken-looking gap
# in their top bar. One dnf line is a cheap price for that never happening.
#
#   The widget's real name is org.kde.plasma.kickerdash. Which package provides
#   it: https://invent.kde.org/plasma/kdeplasma-addons/-/tree/master/applets/kickerdash
#   Why the launcher changed at all: docs/gnome-flow-behavior-layer.md
#
# ⚠️ KDE IMAGES ONLY. On a GNOME image this would install a bag of Plasma
# widgets — and the chunk of KDE it drags behind them — for a desktop that will
# never draw a single one of them. GNOME's own full-screen app grid is the
# Activities overview, which is already there and needs nothing installed.
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then
  dnf5 install -y kdeplasma-addons
else
  echo "NOTE: GNOME image — skipping kdeplasma-addons (its app grid is built in)."
fi

# ==============================================================================
# PHASE 2, TRACK B — THE CODEC LAYER
# ==============================================================================
# The headline: there was almost nothing to install. The codec plan listed four
# things to bake in, and Bazzite already had all four. We checked them one at a
# time against the real published image instead of installing on faith, because
# an unnecessary package is a package we own forever.
#
# Checked against ghcr.io/ublue-os/bazzite:stable, build 44.20260825 (Fedora 44).
# The full audit, including how to re-run it yourself, is in docs/codec-layer.md.
#
#   gstreamer1-plugins-bad-free  ALREADY THERE. This is the package that carries
#                                libgstva.so — the modern VA-API encoders and
#                                decoders (vah264enc, vah265enc and friends) —
#                                plus libgstnvcodec.so for NVIDIA's NVENC/NVDEC.
#                                The "GStreamer VA-API encode gap" in our
#                                research note turned out to be about a FLATPAK
#                                add-on for OBS, not a system package, and
#                                Bazzite already preinstalls that too.
#
#   libheif                      ALREADY THERE — and it is the unrestricted
#                                build from the fedora-multimedia repository,
#                                which includes the HEVC decoder plug-in
#                                (libheif-libde265.so). That is what makes an
#                                iPhone HEIC photo open at all.
#
#   kf6-kimageformats            ALREADY THERE. Ships kimg_heif.so, which is the
#                                piece that gives Dolphin HEIC thumbnails and
#                                previews. Nothing extra needed for KDE.
#
#   libva-utils                  ALREADY THERE. This is the package that
#                                provides the `vainfo` command, which is how a
#                                user checks that hardware video works.
#
#   libva-nvidia-driver          ALREADY THERE — on the NVIDIA image only, which
#                                is exactly right. It bridges NVIDIA's NVDEC to
#                                VA-API and is meaningless on an AMD or Intel
#                                machine.
#                                ⚠️ Do NOT add it to this file. This one script
#                                builds BOTH images, so a line here would put an
#                                NVIDIA-only driver on the AMD/Intel image.
#
#   mesa VA-API drivers          PRESENT, but not under the name you would
#                                expect, and this one has a trap in it. Bazzite
#                                REMOVES Fedora's mesa-va-drivers package and
#                                uses Terra's Mesa instead, whose
#                                mesa-dri-drivers package contains the VA-API
#                                drivers (radeonsi_drv_video.so and friends)
#                                directly.
#                                ⚠️ Never "restore" mesa-va-drivers here. Those
#                                files are already owned by another installed
#                                package, so the build would fail on a file
#                                conflict — or worse, quietly swap out a
#                                version-locked Mesa.
#
# So: no codec package is installed below. The one real gap was a player on the
# command line, which is the next section.
# ------------------------------------------------------------------------------

# ==============================================================================
# THE REFERENCE PLAYER — mpv, with hardware decoding on
# ==============================================================================
# mpv plays anything ffmpeg can read, steps through video a single frame at a
# time, and — the reason it is here — prints exactly which decoder it picked.
# That makes it the honest way to prove hardware video is working on a given
# machine, and a genuinely useful tool when you are checking footage off a card.
#
# Its factory settings are a plain text file that ships with this repo:
#   system_files/etc/mpv/mpv.conf   →   /etc/mpv/mpv.conf
# It turns hardware decoding on and explains itself line by line. Like every
# other default in AquariusOS, a user's own ~/.config/mpv/mpv.conf sits above it
# and wins. (mpv reads BOTH files and the user's answer takes precedence — it is
# a starting point, not a lock.)
#
# The mpv package owns the /etc/mpv directory but ships no mpv.conf of its own,
# so nothing overwrites ours.
# ------------------------------------------------------------------------------

dnf5 install -y mpv

# The desktop's video player is Haruna, which Bazzite installs as a Flatpak on
# first boot and which already hardware-decodes out of the box. mpv is here as a
# tool, not as a rival, so its launcher is hidden — otherwise a second video
# player icon appears in the app grid and can quietly take over "open video
# files with" from Haruna.
#
# Hiding the launcher does not hide the program: typing `mpv` in a terminal
# works exactly as before. This is the same trick Bazzite itself uses to keep
# btop, nvtop and makemkv out of the menus.
desktop-file-edit --set-key=Hidden --set-value=true /usr/share/applications/mpv.desktop

# ==============================================================================
# PHASE 2, TRACK A — The Creator Layer  (LIVE since 2026-08-28)
# ==============================================================================
# This one line is the whole creator app suite. Everything it does lives in its
# own file so that this one stays readable:
#
#     build_files/creator-apps.sh
#
# In short, an app reaches a user in one of three ways:
#   baked in      Aquarius Editor, Aquarius Writer
#   preinstalled  Firefox, Google Chrome — a browser is not optional
#   offered       OBS Studio, Audacity, Blender, DaVinci Resolve — one
#                 tick-box window on the first login, everything pre-ticked
#
# Read that file before changing anything about which apps ship, and which of
# the three groups they land in. Beginner-facing write-up of the result:
# docs/creator-apps.md
#
# DECISION ON RECORD (ROADMAP.md): third-party creator apps ship as FLATPAKS,
# not as system packages. Flatpaks update on their own and a broken one can
# never stop the OS from booting. The only things baked into the image are our
# own two apps, which are not on Flathub.
#
# Still to do in Phase 2, deliberately NOT here yet:
#   * "Creator Mode" first-boot choice (Gamer / Creator / Both) — needs a
#     first-boot app; the screen is designed, the mechanism is not chosen.
#   * v4l2loopback for the OBS virtual camera — check whether Bazzite already
#     ships it before adding anything.
# ------------------------------------------------------------------------------

/ctx/creator-apps.sh

# ==============================================================================
# PHASE 2 — "MAKE EDITOR-READY" INGEST HELPER  (aq-ingest, Milestone 2)
# ==============================================================================
# ADDED BY THE INGEST M2 BRANCH. This whole block is self-contained: if you ever
# want AquariusOS without the ingest helper, delete from this banner down to the
# "end of the ingest helper" line and nothing else breaks.
#
# What this installs, and why:
#
#   /usr/bin/aq-ingest        the command itself
#   /usr/lib/pythonX.Y/site-packages/aq_ingest/
#                             the code it runs. NOT /usr/local — see the long
#                             warning further down before touching that line.
#   /usr/share/kio/servicemenus/aquarius-make-editor-ready.desktop
#                             the Dolphin right-click menu item (copied in by the
#                             system_files step at the top of this file — all we
#                             do here is mark it executable, which KDE requires)
#
# The tool takes files off a camera card and writes editor-friendly copies next
# to them, so DaVinci Resolve opens them with picture AND sound. The design is
# in ../docs/ingest-helper-spec.md; the beginner walkthrough is in
# docs/ingest-right-click.md.
# ------------------------------------------------------------------------------

# notify-send lives in libnotify. It is how the tool tells you it has started and
# finished when you launch it from the right-click menu (there is no terminal
# window to print into). Almost certainly already present on a KDE image; this
# line costs a second and guarantees it.
dnf5 install -y libnotify

# The tool is written in Python (standard library only — nothing to download).
# Every Fedora-based image has Python, but say so plainly if that ever changes.
if ! command -v python3 > /dev/null 2>&1; then
  echo "AQUARIUS ERROR: this image has no python3, so aq-ingest cannot be installed."
  exit 1
fi

# WHERE THE CODE GOES — and why this is not the obvious one-liner.
#
# Python modules live in a folder whose name contains the Python version
# (…/python3.14/site-packages), and that version changes when Fedora moves on,
# so the folder does have to be worked out rather than typed in.
#
# ⚠️ The obvious way to work it out is to ask Python:
#       python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])'
#    DO NOT USE THAT. On Fedora it lies. Fedora patches Python so that outside
#    of a package build that question is answered with /usr/local/lib/… — their
#    way of keeping things you install yourself apart from things the package
#    manager owns. Reasonable on a normal computer; wrong here twice over:
#
#      1. On this kind of OS /usr/local is not a real folder in the image at
#         all. It is redirected to writable storage that does not exist yet at
#         build time, so the build dies with the baffling message
#         "install: cannot create directory '/usr/local': File exists".
#      2. Even if it worked, /usr/local is the user's space, not the image's.
#         Anything we put there is not really part of AquariusOS.
#
#    This cost one red build (Actions run 33219496395). Do not "simplify" it
#    back to sysconfig.
#
# So: build the real system path from the Python version instead. This is the
# folder Fedora's own Python packages live in and it is always searched. It is
# "lib" and not "lib64" on purpose — lib64 is for modules with compiled C
# inside them, and aq-ingest is pure Python.
#
# (The other candidate was `rpm -E %python3_sitelib`, which gives the same
# answer. It was rejected because it only works if the python3-rpm-macros
# package happens to be installed, and when it is not, `rpm -E` cheerfully
# succeeds and prints the text "%python3_sitelib" — we would install into a
# folder literally called that and never notice. Failing loudly beats failing
# quietly, and the two lines below cannot fail quietly.)
AQ_PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
AQ_INGEST_SITE="/usr/lib/python${AQ_PYTHON_VERSION}/site-packages"

# Belt and braces. If that folder is somehow not one this Python actually looks
# in, stop now — installing into a folder nothing reads would give us a
# green build and a command that does not work.
if ! python3 -c "import sys; sys.exit(0 if '${AQ_INGEST_SITE}' in sys.path else 1)"; then
  echo "AQUARIUS ERROR: ${AQ_INGEST_SITE} is not on this image's Python search path."
  echo "                Installing aq-ingest there would produce a broken command."
  echo "                Python looks in:"
  python3 -c "import sys; print('\n'.join('                  ' + p for p in sys.path if p))"
  exit 1
fi

install -d -m 0755 "${AQ_INGEST_SITE}"
rm -rf "${AQ_INGEST_SITE:?}/aq_ingest"
cp -a /ctx/ingest/aq_ingest "${AQ_INGEST_SITE}/aq_ingest"

# Drop any compiled leftovers that came along from a developer's machine, then
# build fresh ones so the first run is not slowed down compiling on the spot.
find "${AQ_INGEST_SITE}/aq_ingest" -name '__pycache__' -type d -prune -exec rm -rf {} +
python3 -m compileall -q "${AQ_INGEST_SITE}/aq_ingest"

install -D -m 0755 /ctx/ingest/aq-ingest /usr/bin/aq-ingest

# KDE ignores a right-click menu file that is not marked executable.
chmod 0755 /usr/share/kio/servicemenus/*.desktop

# Prove it actually works inside the image rather than hoping. If the command
# cannot start, the build fails here instead of shipping a broken menu item.
/usr/bin/aq-ingest --version
/usr/bin/aq-ingest --help > /dev/null

# aq-ingest cannot do anything without ffmpeg. Installing ffmpeg belongs to the
# Phase 2 codec-defaults work, NOT here — two branches installing the same codec
# stack different ways is how images break. So: check, and say so loudly if it is
# missing. This deliberately does not fail the build, because the helper is still
# correctly installed; it just has nothing to drive.
for aq_tool in ffmpeg ffprobe; do
  if ! command -v "${aq_tool}" > /dev/null 2>&1; then
    echo "AQUARIUS WARNING: ${aq_tool} is not in this image, so aq-ingest will refuse"
    echo "                  to run until the Phase 2 codec layer installs it."
  fi
done
# heif-convert (package libheif-tools) is only needed for iPhone HEIC photos; the
# tool falls back to ffmpeg for those, so its absence is a note, not a warning.
command -v heif-convert > /dev/null 2>&1 || echo "AQUARIUS NOTE: heif-convert not installed."

# ------------------------- end of the ingest helper ---------------------------

# ==============================================================================
# DRIVES THAT MOUNT THEMSELVES, AND DRIVES ON THE DESKTOP
# ==============================================================================
# Two behaviours Royce asked for on 2026-08-30, wired up here. The full
# reasoning for both lives in the scripts' own comments and in
# docs/drives-and-desktop-icons.md; this section is only the switching-on.
#
#   1. EVERY INTERNAL DATA DRIVE MOUNTS ITSELF AT BOOT — the Windows game drive
#      on a dual-boot machine especially. Bazzite's own automounter only handles
#      labelled ext4 and btrfs; ours picks up everything it walks past (NTFS,
#      exFAT, XFS, F2FS, FAT and unnamed drives), skipping swap, the EFI boot
#      partition, Windows' recovery partition, anything /etc/fstab already
#      claims, and the disk we are booted from.
#        /usr/libexec/aquarius-internal-automount
#        /usr/lib/systemd/system/aquarius-internal-automount.service
#
#   2. MOUNTED DRIVES APPEAR ON THE DESKTOP, macOS-style, the system drive
#      included and labelled "AquariusOS" — and application icons are kept off
#      the desktop.
#        /usr/libexec/aquarius-desktop-volumes
#        /usr/lib/systemd/user/aquarius-desktop-volumes.service
#
# Both files were copied into place by the system_files step at the top of this
# script. All that is left is to mark them runnable and switch the two services
# on.
# ------------------------------------------------------------------------------

chmod 0755 /usr/libexec/aquarius-internal-automount
chmod 0755 /usr/libexec/aquarius-desktop-volumes

# Prove they can at least start, inside the image, rather than finding out on
# somebody's machine. `python3 -m py_compile` reads the whole file and fails the
# build on a typo — which is the cheapest possible version of this check, since
# neither script can actually be RUN at build time (there are no disks to mount
# and no desktop to draw on inside a container).
python3 -m py_compile /usr/libexec/aquarius-internal-automount
python3 -m py_compile /usr/libexec/aquarius-desktop-volumes
# py_compile leaves a __pycache__ folder next to the file. /usr/libexec is not a
# place Python imports from, so those files would never be read again.
rm -rf /usr/libexec/__pycache__

# The boot-time drive mounter. An ordinary system service.
systemctl enable aquarius-internal-automount.service

# The desktop drive icons. This is a USER service — one copy per logged-in
# person — so it is switched on with `--global`, which means "for every account
# on this machine".
#
# ⚠️ `--global` is the important word and it is not interchangeable with
# anything else here. It writes the enablement into /etc/systemd/user/, which
# every account's own systemd reads. Without it we would be back to the problem
# the desktop layout script has: a setting that only ever reaches a BRAND NEW
# account. Royce's existing installs have to get this too.
#   Source: systemctl(1) — "--global: When used with enable and disable, operate
#   on the global user configuration directory, thus enabling or disabling a
#   unit file globally for all future logins of all users."
systemctl --global enable aquarius-desktop-volumes.service

# ==============================================================================
# THE LOGIN SCREEN, AT THE RIGHT SIZE ON A SMALL SCREEN
# ==============================================================================
# On Royce's 7-inch ROG Xbox Ally the login screen came up enormous and cut off
# at the edges, while the desktop behind it was fine. That is not a bug in
# anything — it is KWin working out how much to magnify a screen from its
# physical size, taking its "phone screens" branch because a handheld has no
# laptop lid, and landing on 210% for a 7-inch 1080p panel. The desktop escapes
# it because your account has a saved answer; the login screen runs as a
# different account with no saved answer, so it guesses afresh.
#
# The fix is to give the login screen a saved answer too. The whole explanation,
# with the KWin source it was read out of, is at the top of the script:
#
#   /usr/libexec/aquarius-greeter-scale                        the script
#   /usr/lib/systemd/system/aquarius-greeter-scale.service     when it runs
#   /usr/share/aquarius/greeter/kwinoutputconfig.json          what it installs
#
# ⚠️ THIS IS NOT SCOPED TO THE HANDHELD IMAGE, and that is deliberate. Whether a
# login screen is too big is a question about the SCREEN, not about which of our
# three images somebody installed — a desktop image installed on an Ally has the
# same problem, and the handheld image docked to a monitor does not. So the
# script asks the hardware instead: Bazzite's own /usr/libexec/hwsupport/
# needs-100-scale list first, plus the ROG Xbox Ally, which is missing from it.
# On every other machine the service records itself as skipped and writes
# nothing at all.
# ------------------------------------------------------------------------------

chmod 0755 /usr/libexec/aquarius-greeter-scale

# Prove the pieces are really in the image before switching anything on. A
# missing file here would be a service that silently does nothing forever.
test -x /usr/libexec/aquarius-greeter-scale
test -r /usr/share/aquarius/greeter/kwinoutputconfig.json
python3 -c "import json; json.load(open('/usr/share/aquarius/greeter/kwinoutputconfig.json'))"

# And prove the script's own decision works inside the image: a container has no
# handheld hardware, so the honest answer here is "no, this machine does not need
# it", and the script must say so rather than falling over.
if /usr/libexec/aquarius-greeter-scale --check-device; then
  echo "AQUARIUS NOTE: the build machine claims to need the login-screen fix."
else
  echo "OK: aquarius-greeter-scale correctly leaves an ordinary machine alone."
fi

systemctl enable aquarius-greeter-scale.service

# ==============================================================================
# HANDHELD-ONLY SETTINGS — kept on the handheld image, deleted from the others
# ==============================================================================
# A handheld needs a small number of KDE defaults that a desktop PC actively does
# not want. The important one: turn the game controller into a mouse and keyboard
# on the desktop, which is the only way to use an ROG Xbox Ally with nothing
# plugged into it. On a desktop PC the same setting means a controller plugged in
# for a game starts shoving the mouse pointer around, which nobody asked for.
# The other one is a gentler window blur, because a handheld's graphics chip and
# its battery are the same budget.
#
#   /usr/share/aquarius/xdg-handheld/kwinrc   ← read that file; the reasoning,
#                                               the button map and the sources
#                                               are all inside it
#
# HOW "HANDHELD ONLY" IS DONE, and why it is done backwards
#   The folder is copied onto EVERY image by the system_files step at the top of
#   this script, and then deleted again here on the two desktop images. Shipping
#   and un-shipping is deliberately the wrong way round from how it sounds,
#   because it is the way that cannot fail quietly: the file is always in the
#   repo, always reviewed, always in one place, and the only variant-specific
#   thing in the whole arrangement is one `rm -rf`.
#
#   The other half of the switch is in the little script that puts our folders on
#   KDE's search path, system_files/etc/xdg/plasma-workspace/env/zz-aquarius.sh.
#   It adds this folder only `if [ -d ... ]`, so on a desktop image — where we
#   have just deleted it — the folder simply is not part of the machine.
#
# ⚠️ NOTE ON THE HOUSE RULE. The Containerfile says there is no variant branching
# in this script, and that adding one should be the last resort. This is that
# last resort, and it is the same shape as the branch build_files/image-info.sh
# already has to work out the edition name — `case "$IMAGE_NAME"`, matching on
# the word "deck", which Bazzite's own handheld checks match on too. The rule the
# Containerfile is really protecting is "do not let the three images drift", and
# this is one folder that does not exist on two of them, tested by its absence.
# ------------------------------------------------------------------------------

# `${IMAGE_NAME:-aquarius-os}` and not a bare `${IMAGE_NAME}` because this script
# runs under `set -u`: an unset variable would abort the whole build here rather
# than fall through to the sensible default. Same spelling as image-info.sh.
# ⚠️ SECOND CONDITION, ADDED WITH THE GNOME LINE. The file this folder holds is
# a `kwinrc` — a KWin settings file. KWin is KDE's window manager, and a GNOME
# image does not have one, so on the GNOME handheld this folder is not "the
# handheld settings", it is a file nothing will ever read. It is therefore
# removed from every GNOME image, handheld included.
#
# The GNOME handheld still needs an answer to the same question — how do you
# drive a desktop with only a game controller — and it does not have one yet.
# That is a G2 item, written down in docs/gnome-variants.md rather than bodged
# here. Do not "fix" this by keeping the kwinrc; it would not work.
AQ_IMAGE_NAME="${IMAGE_NAME:-aquarius-os}"

case "${AQ_DESKTOP}:${AQ_IMAGE_NAME}" in
  kde:*deck*)
    echo "OK: '${AQ_IMAGE_NAME}' is the KDE handheld image — keeping /usr/share/aquarius/xdg-handheld."
    # Prove it is really there. A typo in the path above, or a file that quietly
    # stopped being copied, would otherwise ship a handheld with no way to move
    # the pointer — and nothing would go red.
    test -f /usr/share/aquarius/xdg-handheld/kwinrc
    grep -q '^gamecontrollerEnabled=true$' /usr/share/aquarius/xdg-handheld/kwinrc
    ;;
  gnome:*)
    echo "NOTE: '${AQ_IMAGE_NAME}' is a GNOME image — removing the KWin-only handheld settings."
    echo "      Controller-as-mouse on the GNOME handheld is a G2 item (docs/gnome-variants.md)."
    rm -rf /usr/share/aquarius/xdg-handheld
    ;;
  *)
    echo "NOTE: '${AQ_IMAGE_NAME}' is a desktop image — removing the handheld-only settings."
    rm -rf /usr/share/aquarius/xdg-handheld
    ;;
esac

# ==============================================================================
# TIER 2, TRACK B — THE KWIN EFFECTS LAYER (rounded windows)
# ==============================================================================
# One line again, for the same reason as the creator apps above: all the detail
# lives in its own file.
#
#     build_files/kwin-effects.sh
#
# What it does: downloads the source code of one community KDE add-on —
# KDE-Rounded-Corners — and COMPILES it here, inside the build, against the
# exact KWin this image ships. That is unusual and it is deliberate: a KWin
# effect only works with the precise KWin it was built for, and when it does
# not match it fails silently rather than loudly. Building it here welds it to
# our KWin, so an update ships both or neither, and a Plasma bump that upstream
# has not caught up with turns a broken desktop into a red build. If it fails
# to compile, no image is published. That is the point, not a bug — read the
# top of that file before "fixing" a failure.
#
# ⚠️ It used to build TWO add-ons. The second, Better Blur DX, made whole
# windows frosted glass; it was removed on 2026-08-30 along with all the
# transparency in the design, because the blur it existed to draw never
# rendered on this Plasma. The reasoning is at the top of kwin-effects.sh and
# the investigation is in docs/blur-known-issue.md.
#
# The settings that switch it on are ordinary defaults in the xdg cascade:
#   system_files/usr/share/aquarius/xdg/kwinrc     (rounded corners, outlines)
#   system_files/usr/share/aquarius/xdg/breezerc   (window shadows)
#   system_files/usr/share/aquarius/xdg-handheld/kwinrc  (controller-as-mouse)
#
# It runs HERE, after the handheld folder has been trimmed above, so its check
# of the handheld file only happens on the image that actually keeps it.
# Beginner-facing write-up: docs/kwin-effects-layer.md
#
# ⚠️ KDE IMAGES ONLY, AND THIS IS THE ONE THAT REALLY MATTERS. Everything else
# guarded by AQ_DESKTOP would merely be pointless on the other desktop. This one
# would be FATAL: the script installs kwin-devel and compiles a plug-in against
# this image's KWin headers, and a GNOME image has no KWin and no such package.
# Running it there does not produce a plain-looking desktop, it produces a red
# build and no image at all. GNOME draws its own rounded window corners, so
# there is nothing to replace it with — that is the whole point of the "work with
# GNOME's grain" posture (docs/gnome-variants.md).
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then
  /ctx/kwin-effects.sh
else
  echo "NOTE: GNOME image — skipping the KWin effects layer (GNOME rounds its own corners)."
fi

# ==============================================================================
# THE GLASS DESKTOP — give the Plasma style a fresh version number
# ==============================================================================
# One line, and it has to run on every build. Without it, people who update
# AquariusOS keep seeing the OLD panel and popup artwork, because Plasma caches
# the pictures it has already drawn and only rebuilds that cache when the theme's
# version number changes. The reasoning is written out in full inside the script.
#
# ⚠️ KDE IMAGES ONLY. The thing being version-stamped is a Plasma style — the
# panel and popup artwork. GNOME has no such object and reads none of it.
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then
  /ctx/plasma-style-version.sh
else
  echo "NOTE: GNOME image — skipping the Plasma style version stamp (no Plasma style to stamp)."
fi

# ==============================================================================
# THE TOP BAR'S APP NAME — check our own widget really landed
# ==============================================================================
# The bold "Dolphin" / "Firefox" in the top bar is a small widget of our own,
# copied into the image by the system_files step at the top of this script. It
# needs no packages and nothing compiled, so there is nothing to install here —
# only something to check.
#
# WHY CHECK AT ALL. The desktop layout script asks for this widget by its id,
# `com.aquariusos.appname`. If the folder is missing, or the id inside
# metadata.json stops matching the folder name, KDE's answer is to build the top
# bar WITHOUT an app name and say nothing. There is no error, no log line and no
# gap on screen — the bar just quietly looks like the old one. That is the worst
# kind of failure, so it gets caught here instead.
#
# WHAT THIS CANNOT PROVE. There is no desktop and no logged-in person inside a
# build container, so nothing here can start Plasma and watch it draw the
# widget. The bench checklist for that is in docs/app-name-widget.md.
#
# ⚠️ KDE IMAGES ONLY. The widget is a Plasma applet. Its files still SHIP on the
# GNOME images — they are plain text, nothing deletes them, and nothing on GNOME
# reads them — so there is nothing to break and nothing to check. GNOME puts the
# running app's name in its own top bar without being asked.
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then

APPNAME_DIR=/usr/share/plasma/plasmoids/com.aquariusos.appname

# The two files the widget is made of.
test -d "${APPNAME_DIR}"
test -r "${APPNAME_DIR}/metadata.json"
test -r "${APPNAME_DIR}/contents/ui/main.qml"

# metadata.json must still be readable JSON. A stray comma here means KDE cannot
# read the widget at all, which is the silent failure described above.
python3 -c "import json; json.load(open('${APPNAME_DIR}/metadata.json'))"

# And the id inside it must match the folder it lives in, because that pair is
# what the layout script's `topBar.addWidget("com.aquariusos.appname")` line
# resolves against.
python3 - "${APPNAME_DIR}" <<'PY'
import json, os, sys
folder = sys.argv[1]
meta = json.load(open(os.path.join(folder, "metadata.json")))
plugin_id = meta["KPlugin"]["Id"]
expected = os.path.basename(folder)
if plugin_id != expected:
    sys.exit(
        f"FAIL: the app-name widget's Id is '{plugin_id}' but its folder is "
        f"'{expected}'. KDE matches those two, so the top bar would come up "
        f"with no app name and no error. Make them agree."
    )
if meta.get("KPackageStructure") != "Plasma/Applet":
    sys.exit("FAIL: the app-name widget is not declared as a Plasma/Applet.")
print(f"OK: the app-name widget is installed as {plugin_id}.")
PY

else
  echo "NOTE: GNOME image — not checking the Plasma app-name widget (GNOME has its own)."
fi

# ==============================================================================
# OUR OWN DESKTOP WIDGETS — check they are complete and their libraries are here
# ==============================================================================
# AquariusOS ships a Plasma widget of its own: the clock at the right-hand end of
# the top bar, whose popup is the notifications panel. It was copied into place
# by the system_files step at the top of this file, like everything else.
#
# QML is not compiled, so nothing has checked any of it yet. This step does the
# two checks that are worth doing against the FINISHED image: every file the
# widget needs is really here, and the two KDE QML libraries it imports are
# really installed. The second one is the important one — it is what turns "a
# Bazzite rebase quietly dropped a library" into a failed build instead of a
# broken top bar on somebody's machine.
#
# Beginner-facing write-up: docs/clock-notifications-widget.md
#
# ⚠️ KDE IMAGES ONLY. This script looks for KDE QML libraries. On a GNOME image
# they are genuinely not installed, so it would fail the build over the absence
# of something a GNOME image is not supposed to have. GNOME's top bar already
# carries a clock whose popup is the notifications list.
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then
  /ctx/shell-widgets.sh
else
  echo "NOTE: GNOME image — skipping the Plasma clock/notifications widget checks."
fi

# ==============================================================================
# QUICK SETTINGS — check the widget's KDE dependencies are really in the image
# ==============================================================================
# Our Quick Settings panel is built on KDE's own networking, Bluetooth,
# notification, volume, brightness and battery plumbing. Several of those pieces
# are marked `private` by KDE, which means they may be renamed or removed in any
# release with no warning — and we do not control when Plasma moves, because it
# arrives with Bazzite.
#
# The failure mode is silent: a widget that imports something missing does not
# crash, it just does not load, and the panel opens with a dead tile nobody
# notices. This script turns that into a red build on the day it happens.
#
# It reads the widget's own QML to work out what to check, so adding a tile
# extends the check automatically and there is no list to forget to update.
#
# It runs HERE, after the system_files copy at the top of this file has put the
# widget into /usr/share/plasma/plasmoids/ — it inspects the installed copy, not
# the one in the repo, because only the installed one is what users get.
# Beginner-facing write-up: docs/quick-settings-widget.md
#
# ⚠️ KDE IMAGES ONLY, for the same reason as the step above: what it checks for
# is KDE's own plumbing, which a GNOME image does not have. GNOME's Quick
# Settings menu is part of GNOME Shell.
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then
  /ctx/quick-settings-check.sh
else
  echo "NOTE: GNOME image — skipping the Plasma Quick Settings checks (GNOME has its own menu)."
fi

# ==============================================================================
# THE DOCK — check our own widget will actually load
# ==============================================================================
# The dock is not a stock KDE widget. It is KDE's icons-only task manager,
# copied into this image with three additions the design asks for: the hover
# lift, the dot under a running app, and the dashed "+" tile.
#
# Copied code leans on pieces of KDE that Bazzite supplies, and a move to a newer
# Plasma can rename or remove any of them. When that happens the build still
# succeeds and the DOCK IS SIMPLY MISSING on the booted machine, with nothing
# anywhere saying why. This one line turns that into a failed build instead.
#
# Full reasoning: the header of dock-check.sh, and docs/aquarius-dock.md
#
# ⚠️ KDE IMAGES ONLY. Our dock is a fork of KDE's task manager and needs Plasma
# to load it. The GNOME line has a dock too — Dash to Dock, baked in by
# build_files/gnome-extensions.sh — and it is checked by that script instead.
# ------------------------------------------------------------------------------

if [ "${AQ_DESKTOP}" = "kde" ]; then
  /ctx/dock-check.sh
else
  echo "NOTE: GNOME image — skipping the Plasma dock checks (its dock is Dash to Dock)."
fi

# ==============================================================================
# AQUARIUSOS IDENTITY — make the OS call itself AquariusOS
# ==============================================================================
# Everything above this point installs things. This last step renames things:
# it rewrites the small files that hold the name of the operating system, so
# KDE's "About This System", the login screen and `neofetch` all say
# "AquariusOS" instead of "Bazzite".
#
# Note "files", plural. There are two, and it took a shipped image to find that
# out: os-release, which nearly everything reads, AND a KDE-only override file
# (/etc/xdg/kcm-about-distrorc) that the About This System page reads FIRST.
# Bazzite ships its own copy of the second one. Miss it and the About page keeps
# saying Bazzite forever, no matter how correct os-release is.
#
# It is deliberately the LAST step, so that nothing installed afterwards can
# overwrite the names we just set. If you add new steps to this file, add them
# ABOVE this line.
#
# The details, and the list of things we purposely leave saying "Bazzite" and
# why, are all commented inside the script itself:
#   build_files/image-info.sh
# Background research: docs/os-release-branding-research.md
# ------------------------------------------------------------------------------

/ctx/image-info.sh

# ==============================================================================
# Examples kept from the upstream template, for reference
# ==============================================================================
# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images.
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1
#
# Use a COPR (a third-party package repo):
#   dnf5 -y copr enable ublue-os/staging
#   dnf5 -y install package
#   # Disable COPRs so they don't end up enabled on the final image:
#   dnf5 -y copr disable ublue-os/staging
#
# Enable a system service:
#   systemctl enable podman.socket
