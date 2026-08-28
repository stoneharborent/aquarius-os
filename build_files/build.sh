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
# PHASE 2, TRACK A — The Creator Layer  (LIVE since 2026-08-28)
# ==============================================================================
# This one line is the whole creator app suite. Everything it does — the Flatpak
# shopping list, baking in Aquarius Editor and Aquarius Writer, and the DaVinci
# Resolve installer — lives in its own file so that this one stays readable:
#
#     build_files/creator-apps.sh
#
# Read that file before changing anything about which apps ship. Beginner-facing
# write-up of the result: docs/creator-apps.md
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
