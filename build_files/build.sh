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
