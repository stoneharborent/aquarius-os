#!/bin/bash
# ==============================================================================
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
# ------------------------------------------------------------------------------

dnf5 install -y kdeplasma-addons

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
# PHASE 2 — The Creator Layer  (NOT ACTIVE YET — stubs only)
# ==============================================================================
# Everything below is commented out on purpose. It is the shape of what comes
# next, kept visible so the structure is obvious. Do not uncomment casually:
# each of these makes builds slower and adds something we then have to support.
#
# DECISION ON RECORD (ROADMAP.md): creator apps ship as FLATPAKS, not as system
# packages. Flatpaks update independently of the OS and can't break a boot.
#
# The intended mechanism is a "preinstalled Flatpak list" that Bazzite/ublue
# installs on first boot, NOT `flatpak install` here — Flatpaks generally cannot
# be installed during an image build. Confirm the current ublue mechanism before
# implementing (it has historically been a file under
# /usr/share/ublue-os/ shipped via system_files/, plus a systemd unit).
#
# TODO (Phase 2) — creator suite Flatpak IDs:
#   com.blackmagicdesign.resolve      # DaVinci Resolve helper (Flathub: needs
#                                     # the proprietary installer; verify the ID
#                                     # and licensing before shipping)
#   org.kde.kdenlive                  # Kdenlive — video editor
#   com.obsproject.Studio             # OBS Studio — streaming / recording
#   org.kde.krita                     # Krita — painting / design
#   org.blender.Blender               # Blender — 3D
#   org.ardour.Ardour                 # Ardour — DAW
#   org.audacityteam.Audacity         # Audacity — audio editing
#   md.obsidian.Obsidian              # Obsidian — notes
#
# TODO (Phase 2) — system-level pieces that genuinely cannot be Flatpaks:
#   # dnf5 install -y v4l2loopback  # OBS virtual camera kernel module support
#   #                               # (check: Bazzite may already ship this)
#
# TODO (Phase 2) — "Creator Mode" first-boot choice (Gamer / Creator / Both).
#   Needs a first-boot app or systemd unit shipped via system_files/.
#
# (OS identity — "AquariusOS" in About This System — is DONE. It moved out of
#  this TODO list and into the real step at the bottom of this file.)

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
