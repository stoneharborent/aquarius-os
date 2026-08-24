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
# TODO (Phase 3) — OS identity ("AquariusOS" in About This System, boot splash).
#   The upstream template does NOT provide a supported mechanism for rewriting
#   /usr/lib/os-release, and hand-editing it can break bootc/rpm-ostree updates.
#   Do not improvise this. Research the ublue-supported approach first and
#   record the decision in ../ROADMAP.md before writing any code here.
#   See branding/README.md.

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
