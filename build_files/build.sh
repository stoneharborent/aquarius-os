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
# PHASE 2 — "MAKE EDITOR-READY" INGEST HELPER  (aq-ingest, Milestone 2)
# ==============================================================================
# ADDED BY THE INGEST M2 BRANCH. This whole block is self-contained: if you ever
# want AquariusOS without the ingest helper, delete from this banner down to the
# "end of the ingest helper" line and nothing else breaks.
#
# What this installs, and why:
#
#   /usr/bin/aq-ingest        the command itself
#   <python site-packages>/aq_ingest/   the code it runs
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

# Python puts third-party modules in a folder whose name contains the Python
# version (…/python3.13/site-packages), and that version changes when Fedora
# moves on. So ask Python where its own folder is rather than guessing.
AQ_INGEST_SITE="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
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
