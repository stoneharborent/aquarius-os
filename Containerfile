# ==============================================================================
# AquariusOS — the recipe for the operating system
# ==============================================================================
# Plain English: this file says "start from Bazzite, then run our build script on
# top of it." GitHub Actions reads this file and produces a bootable OS image.
# You almost never need to edit this file — day-to-day changes (adding apps,
# changing settings) happen in build_files/build.sh instead.
# ==============================================================================

# ------------------------------------------------------------------------------
# WE BUILD TWO VERSIONS OF AQUARIUSOS FROM THIS ONE FILE
# ------------------------------------------------------------------------------
#   aquarius-os          for AMD and Intel graphics  → ghcr.io/ublue-os/bazzite:stable
#   aquarius-os-nvidia   for NVIDIA graphics         → ghcr.io/ublue-os/bazzite-nvidia-open:stable
#
# They are identical apart from that starting point, so there is deliberately only
# ONE recipe: the starting point is a knob (`BASE_IMAGE`) instead of a fixed line,
# and GitHub Actions builds this file twice, once with each value. The default
# below is the AMD/Intel one, so a plain `podman build .` with no extra arguments
# still produces exactly what it always did.
#
# The real list of image names lives in aquarius-os.env — change it there, not
# here. Why -nvidia-open and not -nvidia: docs/nvidia-variant-research.md.
#
# ⚠️ This line MUST stay above the first FROM. An ARG written after a FROM belongs
# to that one build stage only, and would not be visible to the FROM further down
# that uses it — the build would fail with a blank base image name.
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# ------------------------------------------------------------------------------
# Base Image — what AquariusOS is built on top of
# ------------------------------------------------------------------------------
# Bazzite stable, KDE desktop. This is the gaming layer we inherit for free:
# Steam, Game Mode, GPU drivers, controller support, handheld support.
# (`bazzite:stable` is the KDE desktop variant. The GNOME variant is
# `bazzite-gnome:stable`; handhelds use `bazzite-deck:stable` — Phase 4.)
#
# Which Bazzite this actually is comes from the BASE_IMAGE argument declared at
# the very top of this file, above the first FROM. That placement is what makes
# it usable here.
FROM ${BASE_IMAGE}

## Other possible base images include:
# ghcr.io/ublue-os/bazzite:testing
# ghcr.io/ublue-os/bazzite-deck:stable      # Steam Deck / handheld — Phase 4
# ghcr.io/ublue-os/aurora:stable
#
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
