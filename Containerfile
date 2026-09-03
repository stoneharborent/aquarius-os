# ==============================================================================
# AquariusOS — the recipe for the operating system
# ==============================================================================
# PLAIN ENGLISH
#
# This file is a recipe. It says "start from Fedora's bare bootable image, then
# run our build scripts on top of it." GitHub Actions reads this file and turns
# it into a bootable operating system.
#
# You almost never need to edit THIS file. Day-to-day changes — adding a
# program, changing a default — happen in the numbered scripts in build_files/,
# and this file just lists them in order.
#
# ------------------------------------------------------------------------------
# WHAT CHANGED, AND WHY THIS FILE LOOKS NOTHING LIKE THE OLD ONE
# ------------------------------------------------------------------------------
# Until 2026-09-02, AquariusOS was built on top of Bazzite — a gaming OS that
# had already made several thousand decisions for us. We spent most of our time
# undoing those decisions.
#
# On 2026-09-02 Royce restarted the project on Fedora's BARE bootable image:
# a kernel, systemd, and a package manager, and nothing else. Every single
# program in AquariusOS is now here because we put it here.
#
# The full reasoning is in ../docs/base-distro-reassessment-2026-09.md.
# The short version is in docs/restart/README.md.
#
# The old Bazzite recipe still exists on the `main` branch and the six images it
# builds are still published, so nobody's computer breaks. Nothing on this
# branch is ever merged into `main`.
#
# ------------------------------------------------------------------------------
# TWO IMAGES COME OUT OF THIS ONE FILE
# ------------------------------------------------------------------------------
#   aquarius-os-next          for AMD and Intel graphics
#   aquarius-os-next-nvidia   for NVIDIA graphics
#
# They are the same recipe. The only difference is a switch called NVIDIA:
# 0 means "no NVIDIA driver", 1 means "install it". There is no second recipe
# and no if-this-image-then-that anywhere in the build scripts beyond that one
# switch, which is the house rule this project has always had.
#
# The word "next" is in the names on purpose. The Bazzite-era images are called
# `aquarius-os`, `aquarius-os-nvidia` and so on, and they are still installed on
# real machines. Publishing under new names means the new line cannot overwrite
# the old one by accident. They take the plain names when Phase R3 closes.
#
# ⚠️ ARGs WRITTEN HERE, ABOVE THE FIRST `FROM`, ARE THE ONLY ONES A `FROM` LINE
# CAN SEE. An ARG written after a FROM belongs to that one stage. Move these
# down and the build fails with a blank image name.
# ==============================================================================

# Which Fedora. Pinned on purpose: a floating tag would mean the OS could change
# release under us without anybody deciding to. Bumping this number is how we
# move to Fedora 45, and it is meant to be a deliberate, tested step.
ARG FEDORA_VERSION=44

# 0 = AMD/Intel image, 1 = NVIDIA image. Nothing else is a valid answer;
# build_files/60-nvidia.sh stops the build on anything else.
ARG NVIDIA=0

# Where the pre-built NVIDIA kernel modules come from. See build_files/60-nvidia.sh
# and docs/restart/nvidia-notes.md for the whole story.
ARG AKMODS_NVIDIA_IMAGE=ghcr.io/ublue-os/akmods-nvidia-open

# ------------------------------------------------------------------------------
# Our own files, gathered up so the build can reach them
# ------------------------------------------------------------------------------
# This "stage" is not part of the finished OS. It is a scratch pile that the
# build script reads from and that is thrown away afterwards, which is why none
# of our scripts end up inside the shipped image.
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files
COPY ingest /ingest

# ------------------------------------------------------------------------------
# The NVIDIA driver parts — fetched ONLY when we are building the NVIDIA image
# ------------------------------------------------------------------------------
# This is a standard trick and it is worth understanding, because it looks
# strange the first time.
#
# We declare two stages with almost the same name:
#
#   nvidia-src-0   empty. Nothing in it at all.
#   nvidia-src-1   Universal Blue's published box of NVIDIA kernel modules
#                  (about 800 MB).
#
# Then a third stage picks between them BY NAME, using the NVIDIA switch:
#
#   FROM nvidia-src-${NVIDIA} AS nvidia-src
#
# A container build only builds the stages it actually needs. So on the AMD /
# Intel image, NVIDIA is 0, the name resolves to the empty stage, and the 800 MB
# download never happens. On the NVIDIA image it resolves to the real one.
#
# This is how "one recipe, two images" stays true without an `if` in the recipe.
FROM scratch AS nvidia-src-0
FROM ${AKMODS_NVIDIA_IMAGE}:main-${FEDORA_VERSION} AS nvidia-src-1
FROM nvidia-src-${NVIDIA} AS nvidia-src

# ==============================================================================
# THE OPERATING SYSTEM ITSELF
# ==============================================================================
# quay.io/fedora/fedora-bootc is Fedora's official "image mode" base: a real
# Fedora system, with a kernel and systemd and dnf, packaged as a container
# image that a computer can boot from directly. It contains no desktop, no
# browser, no drivers beyond the kernel's own — that is the point.
FROM quay.io/fedora/fedora-bootc:${FEDORA_VERSION}

# The ARGs above the first FROM are not visible down here — that is the rule,
# in both directions. Re-declaring them (with no value) inherits them.
ARG FEDORA_VERSION
ARG NVIDIA

# Which of the two images is this, and who publishes it. The build script writes
# these into the OS so that `bootc upgrade` knows where to look for updates and
# the About page knows what to call itself. The defaults mean a plain
# `podman build .` with no arguments still produces a sensible image.
ARG IMAGE_NAME=aquarius-os-next
ARG IMAGE_VENDOR=stoneharborent

# ------------------------------------------------------------------------------
# The build, in seven steps
# ------------------------------------------------------------------------------
# Each RUN below is one layer of the finished image. They are separate on
# purpose rather than one giant step: a computer downloading an update only has
# to fetch the layers that actually changed, so a branding tweak is a small
# download instead of a two-gigabyte one.
#
# Every step borrows the same scratch pile:
#   /ctx          our scripts (/ctx/build_files), settings files
#                 (/ctx/system_files) and the ingest helper (/ctx/ingest)
#   /ctx-nvidia   the NVIDIA parts — empty on the AMD/Intel image, see above
# A mount is borrowed for the length of one command and leaves nothing behind,
# which is why none of our scripts end up inside the finished OS.
#
# The step numbers match the file names in build_files/, so the build log and
# the folder listing read in the same order.

# 1. Software sources: RPM Fusion, so the media step below has something to
#    install from.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/10-repos.sh

# 2. Hardware and media: graphics, sound, networking, Bluetooth, power,
#    firmware, filesystems, and the full set of video and audio codecs. This is
#    the step that makes a camera file open at all.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/20-hardware-media.sh

# 3. The session floor: the login screen, the sandboxing plumbing every modern
#    app expects, Flatpak with Flathub, the fonts, and containers.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/30-session.sh

# 4. The desktop: a deliberately short list of GNOME, not the whole of it.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/40-gnome-desktop.sh

# 5. How that desktop looks and behaves out of the box: Ice light theme, our
#    wallpaper, our fonts, our dock, our logo. This step also copies in
#    everything under system_files/.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/50-aquarius-desktop.sh

# 6. NVIDIA. Does nothing at all on the AMD / Intel image.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=nvidia-src,source=/,target=/ctx-nvidia \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    NVIDIA="${NVIDIA}" /ctx/build_files/60-nvidia.sh

# 7. Identity, then cleanup. The OS learns to call itself AquariusOS, and then
#    every temporary file the build made is swept up.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_NAME="${IMAGE_NAME}" IMAGE_VENDOR="${IMAGE_VENDOR}" NVIDIA="${NVIDIA}" \
    /ctx/build_files/70-image-info.sh \
    && /ctx/build_files/90-cleanup.sh

# ------------------------------------------------------------------------------
# The final check
# ------------------------------------------------------------------------------
# `bootc container lint` is Fedora's own inspection of a bootable image: it
# looks for the mistakes that produce an image which builds happily and then
# will not boot. If this fails, do not publish the image.
RUN bootc container lint
