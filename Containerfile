# ==============================================================================
# AquariusOS — the recipe for the operating system
# ==============================================================================
# Plain English: this file says "start from Bazzite, then run our build script on
# top of it." GitHub Actions reads this file and produces a bootable OS image.
# You almost never need to edit this file — day-to-day changes (adding apps,
# changing settings) happen in build_files/build.sh instead.
# ==============================================================================

# ------------------------------------------------------------------------------
# WE BUILD THREE VERSIONS OF AQUARIUSOS FROM THIS ONE FILE
# ------------------------------------------------------------------------------
#   aquarius-os          for AMD and Intel graphics  → ghcr.io/ublue-os/bazzite:stable
#   aquarius-os-nvidia   for NVIDIA graphics         → ghcr.io/ublue-os/bazzite-nvidia-open:stable
#   aquarius-os-deck     for gaming handhelds        → ghcr.io/ublue-os/bazzite-deck:stable
#
# They are identical apart from that starting point, so there is deliberately only
# ONE recipe: the starting point is a knob (`BASE_IMAGE`) instead of a fixed line,
# and GitHub Actions builds this file once per value. The default below is the
# AMD/Intel one, so a plain `podman build .` with no extra arguments still
# produces exactly what it always did.
#
# ⚠️ "Identical apart from the starting point" is a rule, not an accident. There
# is NO variant branching in this file or in build_files/build.sh, and adding one
# should be the last resort — every branch is a code path that only one of the
# three images ever exercises. The handheld build was checked against this rule
# when it was added (2026-08-28) and needed no branch at all: everything that
# makes a handheld a handheld is inside bazzite-deck, and everything we layer on
# top is desktop-session-scoped and simply does not run in Game Mode. The
# reasoning is written out in docs/deck-variant-research.md, §"Do our layers
# conflict?".
#
# The real list of image names lives in aquarius-os.env — change it there, not
# here. Why -nvidia-open and not -nvidia: docs/nvidia-variant-research.md.
# Why -deck and not -deck-gnome: docs/deck-variant-research.md.
#
# ⚠️ This line MUST stay above the first FROM. An ARG written after a FROM belongs
# to that one build stage only, and would not be visible to the FROM further down
# that uses it — the build would fail with a blank base image name.
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
# The "Make Editor-Ready" ingest helper. Its source lives in ingest/ so that its tests
# sit next to it; build.sh installs it into the OS from here. (Added with the ingest
# Milestone 2 work — see the matching section at the bottom of build_files/build.sh.)
COPY ingest /ingest
# Shell test suites that the build runs against the OS it has just assembled — at the
# moment, the ones that check how the app launchers decide between the copy of an
# Aquarius app baked into the image and a newer copy downloaded into the user's home
# folder.
# They are run from build_files/creator-apps.sh. None of this is copied into the
# finished image; it is only here so the build can run it.
COPY tests /tests

# ------------------------------------------------------------------------------
# Base Image — what AquariusOS is built on top of
# ------------------------------------------------------------------------------
# Bazzite stable, KDE desktop. This is the gaming layer we inherit for free:
# Steam, Game Mode, GPU drivers, controller support, handheld support.
# (`bazzite:stable` is the KDE desktop variant. The GNOME variant is
# `bazzite-gnome:stable` and we do not use it; handhelds use
# `bazzite-deck:stable`, which is the third variant we build — Phase 2G.)
#
# Which Bazzite this actually is comes from the BASE_IMAGE argument declared at
# the very top of this file, above the first FROM. That placement is what makes
# it usable here.
FROM ${BASE_IMAGE}

## Other possible base images include:
# ghcr.io/ublue-os/bazzite:testing
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

### WHICH IMAGE AM I?
## One recipe builds three images (aquarius-os, aquarius-os-nvidia and
## aquarius-os-deck), and the build script needs to record its own name inside
## the OS — the file at
## /usr/share/ublue-os/image-info.json says which image is installed, and it has
## to be right or update tooling points at the wrong download.
##
## So the name is a knob too, exactly like BASE_IMAGE above. The Justfile fills
## these in for each of the three builds; the defaults below mean a plain
## `podman build .` with no arguments still works and still produces the normal
## AquariusOS image.
##
## These two ARGs must live HERE, below the FROM, so the RUN line can see them.
## (BASE_IMAGE is the opposite case — it is needed BY a FROM, so it has to sit
## above the first one. Same file, opposite rule, for the same reason.)
ARG IMAGE_NAME=aquarius-os
ARG IMAGE_VENDOR=stoneharborent

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.
##
## The two NAME=value words in front of /ctx/build.sh hand those knobs to the
## build script as ordinary variables it can read.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_NAME="${IMAGE_NAME}" IMAGE_VENDOR="${IMAGE_VENDOR}" /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
