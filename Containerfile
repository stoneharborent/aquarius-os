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

# Which xremap — the program behind Aquarius Keys, the Mac-style keyboard
# shortcuts. Nobody packages it for Fedora, so we compile it, and we compile
# ONE exact version. The commit id is the real pin: it is a checksum of the
# whole source tree, so unlike a tag it cannot be moved. Changing these two
# lines is how we move to a newer xremap, deliberately.
# See build_files/74-xremap-build.sh for the full story.
ARG XREMAP_VERSION=0.15.12
ARG XREMAP_COMMIT=7e6649e442ca445b781e4cf0e90c165f86e717db

# ------------------------------------------------------------------------------
# The three pieces of the Aquarius Desktop that do not come from Fedora
# ------------------------------------------------------------------------------
# Two are compiled from source and one is fetched, and all three are pinned to
# an exact commit. Real values live in aquarius-os.env; these defaults exist so
# that a plain `podman build .` still works. Each build script CHECKS the commit
# it got against the one it was asked for and stops if they differ, so a moved
# tag upstream cannot silently change what AquariusOS ships.
#
# Why we build our own at all is explained at length in the three
# build_files/stage-*.sh scripts. The short version:
#   labwc      Fedora 44 has 0.9.6; the HDR and colour-management release is 0.20
#   Quickshell Fedora's package is a 0.2.1 snapshot missing modules our shell
#              imports — and building in-image is what stops the Qt version
#              mismatch that broke the first bench boot
#   the shell  is ours, and lives in its own repository
ARG LABWC_VERSION=0.20.2
ARG LABWC_COMMIT=97f28877a343e062f3178d201f0248cd9c2610cf
ARG QUICKSHELL_VERSION=v0.3.1
ARG QUICKSHELL_COMMIT=1a4716cde794a59928d9d9fc15f2afc7a95de360
ARG AQUARIUS_SHELL_REPO=https://github.com/stoneharborent/aquarius-shell.git
ARG AQUARIUS_SHELL_REF=df62a3126c9109b18d52b272e75c68ef3c7046db

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

# ------------------------------------------------------------------------------
# The keyboard remapper — compiled here, so the finished OS never sees a compiler
# ------------------------------------------------------------------------------
# AquariusOS ships Mac-style keyboard shortcuts turned on. The program that
# does that is called xremap, it is written in Rust, and nobody packages it for
# Fedora — so we build it from its own published source at one pinned version.
#
# It is built in THIS stage, a plain Fedora container that exists only for the
# length of the build, because compiling Rust needs about a gigabyte of
# compiler and none of that belongs in a finished operating system. Only the
# two small finished programs are copied across, in step 75 below. Same
# pattern, same reason, as the NVIDIA stage above.
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS xremap-build
ARG XREMAP_VERSION
ARG XREMAP_COMMIT
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    XREMAP_VERSION="${XREMAP_VERSION}" XREMAP_COMMIT="${XREMAP_COMMIT}" \
    /ctx/build_files/74-xremap-build.sh

# ==============================================================================
# THE THREE WORKSHOPS
# ==============================================================================
# Each of the three stages below is a full, ordinary Fedora container that gets
# thrown away when the build finishes. Compilers, header files and source code
# live here and NEVER reach the operating system — a single COPY line further
# down takes the finished result across and leaves everything else behind.
#
# This is the standard way to compile something for a container image, and it is
# why AquariusOS can ship a program Fedora does not package without also
# shipping a compiler.
#
# `quay.io/fedora/fedora` rather than `fedora-bootc`: the plain Fedora container
# is the same Fedora 44 userland with none of the bootable-image machinery,
# which is all a workshop needs. Same release means the compiled programs work
# on the finished image — this is not two different Fedoras.
#
# The three stages are independent of one another, so a build machine with the
# capacity runs all three at the same time.
# ------------------------------------------------------------------------------

# Workshop 1 — labwc, the window manager. About two minutes.
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS labwc-build
ARG LABWC_VERSION
ARG LABWC_COMMIT
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    LABWC_VERSION="${LABWC_VERSION}" LABWC_COMMIT="${LABWC_COMMIT}" \
    /ctx/build_files/stage-labwc.sh

# Workshop 2 — Quickshell, the runtime that draws the bar. The long one:
# it compiles a Qt application, which is several minutes.
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS quickshell-build
ARG QUICKSHELL_VERSION
ARG QUICKSHELL_COMMIT
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    QUICKSHELL_VERSION="${QUICKSHELL_VERSION}" QUICKSHELL_COMMIT="${QUICKSHELL_COMMIT}" \
    /ctx/build_files/stage-quickshell.sh

# Workshop 3 — the Aquarius Shell itself. Nothing is compiled; this stage exists
# to fetch one folder at one exact commit and leave the repository's test suite,
# development harness and .git folder behind.
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS aquarius-shell-src
ARG AQUARIUS_SHELL_REPO
ARG AQUARIUS_SHELL_REF
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    AQUARIUS_SHELL_REPO="${AQUARIUS_SHELL_REPO}" AQUARIUS_SHELL_REF="${AQUARIUS_SHELL_REF}" \
    /ctx/build_files/stage-aquarius-shell.sh

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
# The build, in ten steps
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

# 5.5 The Aquarius Desktop — our own desktop, added beside GNOME.
#
#     First the three finished trees come across from the workshops above. Each
#     one is laid out exactly like the root of a Linux system, so these are
#     straight copies with no rearranging:
#
#       labwc-build         /usr/bin/labwc and its manual pages
#       quickshell-build    /usr/bin/qs and the QML modules it provides
#       aquarius-shell-src  /usr/share/aquarius/shell — the bar, dock, search
#
#     Then the build script installs the libraries all of that needs, sets up
#     the login-screen entry and the portals, and CHECKS THE RESULT by running
#     both programs and reading what they say. The check that matters most is
#     `qs --version`: it is the exact thing that failed on the bench on
#     2026-09-02 and left a person looking at an empty desktop.
COPY --from=labwc-build /aq-stage/ /
COPY --from=quickshell-build /aq-stage/ /
COPY --from=aquarius-shell-src /aq-stage/ /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/55-aquarius-session.sh

# 6. NVIDIA. Does nothing at all on the AMD / Intel image.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=nvidia-src,source=/,target=/ctx-nvidia \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    NVIDIA="${NVIDIA}" /ctx/build_files/60-nvidia.sh

# 7. Identity. The OS learns to call itself AquariusOS.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_NAME="${IMAGE_NAME}" IMAGE_VENDOR="${IMAGE_VENDOR}" NVIDIA="${NVIDIA}" \
    /ctx/build_files/70-image-info.sh

# 7b. Aquarius Keys: Mac-style keyboard shortcuts, on by default. Installs the
#     two remapper programs built in the xremap-build stage above, and checks
#     the rule files, the service and the `aq keys` switch that came in with
#     system_files at step 5.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=xremap-build,source=/out,target=/ctx-xremap \
    /ctx/build_files/75-aquarius-keys.sh

# 8. The boot path: the Aquarius splash screen, the name in the boot menu, the
#    text login banners, and then a rebuild of the boot ramdisk so that all of
#    it is really used.
#
#    ⚠️ THIS STEP MUST STAY AFTER STEP 6, AND DO NOT REORDER IT.
#    It rebuilds the boot ramdisk, and a boot ramdisk is built for one exact
#    kernel version. Step 6 sometimes REPLACES this image's kernel (the NVIDIA
#    driver only works with the kernel it was compiled against). Run this before
#    that and the NVIDIA image ends up with a ramdisk for a kernel that no
#    longer exists — an image that builds, publishes, and then will not start.
#    The file's own header explains it at length.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    /ctx/build_files/80-boot-branding.sh

# 9. Cleanup. Every temporary file the build made is swept up.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/90-cleanup.sh

# ------------------------------------------------------------------------------
# The final check
# ------------------------------------------------------------------------------
# `bootc container lint` is Fedora's own inspection of a bootable image: it
# looks for the mistakes that produce an image which builds happily and then
# will not boot. If this fails, do not publish the image.
RUN bootc container lint
