# ==============================================================================
# AquariusOS — the recipe for the operating system
# ==============================================================================
# Plain English: this file says "start from Bazzite, then run our build script on
# top of it." GitHub Actions reads this file and produces a bootable OS image.
# You almost never need to edit this file — day-to-day changes (adding apps,
# changing settings) happen in build_files/build.sh instead.
# ==============================================================================

# ------------------------------------------------------------------------------
# WE BUILD SIX VERSIONS OF AQUARIUSOS FROM THIS ONE FILE
# ------------------------------------------------------------------------------
# The KDE line — FROZEN at its Wave-2 capstone. Still built and published so
# installed machines keep updating, but no new features land on it:
#   aquarius-os                for AMD and Intel graphics  → ghcr.io/ublue-os/bazzite:stable
#   aquarius-os-nvidia         for NVIDIA graphics         → ghcr.io/ublue-os/bazzite-nvidia-open:stable
#   aquarius-os-deck           for gaming handhelds        → ghcr.io/ublue-os/bazzite-deck:stable
#
# The GNOME line — added 2026-08-31, where all new work goes:
#   aquarius-os-gnome          for AMD and Intel graphics  → ghcr.io/ublue-os/bazzite-gnome:stable
#   aquarius-os-gnome-nvidia   for NVIDIA graphics         → ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable
#   aquarius-os-gnome-deck     for gaming handhelds        → ghcr.io/ublue-os/bazzite-deck-gnome:stable
#
# All six come out of ONE recipe. The starting point is a knob (`BASE_IMAGE`)
# instead of a fixed line, and GitHub Actions builds this file once per value.
# The default below is the AMD/Intel KDE one, so a plain `podman build .` with no
# extra arguments still produces exactly what it always did.
#
# ⚠️ THE HOUSE RULE ON BRANCHING, AND HOW THE GNOME LINE FITS IT
# The rule this file has always carried is "no variant branching" — every branch
# is a code path only some images exercise, so it is the thing that lets the
# images drift apart without anyone noticing. That rule is still in force, and
# the handheld build (2026-08-28) genuinely needed no branch at all
# (docs/deck-variant-research.md, §"Do our layers conflict?").
#
# The GNOME line is the one place a branch was unavoidable, and it is one branch,
# on one word. A GNOME image has no KWin, so a step that compiles a KWin plug-in
# does not "do nothing" there — it fails the build. A KDE image has no GNOME
# Shell, so a GNOME default has nothing to apply to. So there is exactly ONE new
# knob, `AQ_DESKTOP` below, it holds exactly one of two words, and every place it
# is read says out loud why that step belongs to one desktop and not the other.
# Do not add a second knob. Do not branch on the image name for desktop
# questions — that is what this one is for.
#
# The real list of image names lives in aquarius-os.env — change it there, not
# here. Why -nvidia-open and not -nvidia: docs/nvidia-variant-research.md.
# Why the handheld image name must keep the word "deck" in it, on BOTH lines:
# docs/deck-variant-research.md and build_files/image-info.sh, step 1b.
# What the GNOME line ships and why: docs/gnome-variants.md.
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
# Bazzite stable. This is the gaming layer we inherit for free: Steam, Game
# Mode, GPU drivers, controller support, handheld support. Every one of the six
# bases listed at the top of this file carries it — the GNOME editions inherit
# exactly the same gaming layer as the KDE ones, so nothing about gaming changes
# between the two lines.
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

### WHICH DESKTOP AM I WEARING?
## "kde" or "gnome" — nothing else is a valid answer, and build_files/build.sh
## stops the build on anything else.
##
## This is the ONE branch in the whole build (see the long note at the top of
## this file). It exists because a handful of steps are not merely pointless on
## the other desktop, they are impossible there: you cannot compile a KWin
## plug-in on an image with no KWin, and you cannot hand a GNOME Shell setting to
## an image with no GNOME Shell.
##
## The default is "kde" on purpose. That is what every AquariusOS image was
## before 2026-08-31, so a plain `podman build .` with no arguments — and every
## older command line anybody has written down — still produces exactly the image
## it always produced.
ARG AQ_DESKTOP=kde

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.
##
## The three NAME=value words in front of /ctx/build.sh hand those knobs to the
## build script as ordinary variables it can read. They are inherited by the
## smaller scripts build.sh calls in turn (image-info.sh, gnome-desktop.sh and
## the rest), which is how those read AQ_DESKTOP without being passed it again.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_NAME="${IMAGE_NAME}" IMAGE_VENDOR="${IMAGE_VENDOR}" AQ_DESKTOP="${AQ_DESKTOP}" /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
