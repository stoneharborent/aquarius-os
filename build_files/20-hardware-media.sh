#!/usr/bin/bash
# ==============================================================================
# STEP 2 — Hardware and media: the floor everything else stands on
# ==============================================================================
# WHAT THIS STEP IS
#
# Fedora's bare bootable image has a kernel and almost nothing else. It can talk
# to a disk and a network cable. It cannot draw on a screen, make a sound,
# connect to Wi-Fi, pair a Bluetooth device, know how much battery is left, or
# open a video file.
#
# This step fixes all of that. It is the largest step in the build and it is the
# one that decides whether AquariusOS is a usable computer.
#
# It is written as a series of small named lists rather than one enormous one,
# because when something goes wrong the failure names a list, and the list has a
# heading that says what it was for.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# Graphics
# ------------------------------------------------------------------------------
# Mesa is the open-source graphics stack. It drives AMD and Intel GPUs
# completely, and it also drives NVIDIA cards' 2D/basic 3D until the NVIDIA
# driver takes over — so it belongs in BOTH images, not just the AMD one.
#
# mesa-dri-drivers is the big one. On Fedora 44 it also contains the VA-API
# video-decoding drivers, which used to be a separate mesa-va-drivers package;
# Fedora merged them (mesa-dri-drivers now formally obsoletes mesa-va-drivers).
# Do not go looking for the old package name — it is gone.
say "Graphics (Mesa)"
aq_dnf install \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    mesa-libGL \
    mesa-libEGL \
    mesa-libgbm \
    libva \
    libva-utils \
    vulkan-loader \
    vulkan-tools

# ------------------------------------------------------------------------------
# Hardware video decoding, the version that can actually decode video
# ------------------------------------------------------------------------------
# Fedora's Mesa is built with the H.264 and H.265 decoders stripped out for
# patent reasons. mesa-va-drivers-freeworld is the same code from RPM Fusion
# with them put back. Without it, playing a camera file falls back to the CPU:
# it works, it just burns a whole processor doing what the graphics card was
# designed to do in silence.
#
# ⚠️ There is no mesa-vdpau-drivers-freeworld on Fedora 44 any more. RPM Fusion
# folded it into this same package (it formally obsoletes the old name), so
# installing this one gets you both. If you go looking for the VDPAU package and
# cannot find it, that is why — nothing is missing.
#
# We do NOT install mesa-vulkan-drivers-freeworld. RPM Fusion's build of it is
# an older Mesa than Fedora's (26.0 against 26.1), so installing it would be a
# downgrade of the Vulkan drivers that games and Blender use, in exchange for
# codecs that the VA-API package above already provides.
say "Hardware video decoding (RPM Fusion freeworld drivers)"
aq_dnf install --allowerasing mesa-va-drivers-freeworld

# ------------------------------------------------------------------------------
# The codecs themselves
# ------------------------------------------------------------------------------
# Fedora ships "ffmpeg-free": ffmpeg with the patented encoders and decoders
# taken out. RPM Fusion ships plain "ffmpeg", which is the real thing, and the
# two deliberately conflict so you cannot have both. `swap` is how you trade one
# for the other in a single transaction; if ffmpeg-free is not installed at all
# (which it is not, on the bare bootable image) a plain install does the job.
#
# This matters more here than on most systems, because the "Make Editor-Ready"
# ingest helper further down the build is ffmpeg wearing a right-click menu.
say "Full ffmpeg"
if rpm -q ffmpeg-free > /dev/null 2>&1; then
    echo "ffmpeg-free is installed — swapping it for the full ffmpeg."
    aq_dnf swap ffmpeg-free ffmpeg
else
    echo "ffmpeg-free is not installed — installing the full ffmpeg directly."
    aq_dnf install --allowerasing ffmpeg
fi

# GStreamer is the other multimedia framework — the one GNOME's own apps, the
# file manager's video thumbnails and most desktop software actually use. It is
# split by licence the same way ffmpeg is:
#
#   -good           unencumbered, from Fedora
#   -bad-free       the "not yet mature" set Fedora will ship
#   -bad-freeworld  the same set's patented half, from RPM Fusion (H.265)
#   -ugly           the patented ones, from RPM Fusion (H.264/MPEG via x264)
#   -vaapi          hands decoding to the graphics card
#
# Fedora also has a "gstreamer1-plugins-ugly-free" and it is a different package
# with a different (smaller) contents. We want RPM Fusion's, and they coexist.
say "GStreamer plug-ins"
aq_dnf install --allowerasing \
    gstreamer1 \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly \
    gstreamer1-vaapi \
    gstreamer1-plugin-libav

# fdk-aac is the Fraunhofer AAC encoder — the good one. AAC is the audio track
# inside essentially every camera and phone recording, and it is the format
# DaVinci Resolve on Linux flatly refuses to read, which is the single reason
# the ingest helper exists.
#
# ⚠️ THE PACKAGE IS CALLED `fdk-aac`, NOT `libfdk-aac`. Universal Blue's package
# list says libfdk-aac because they pull it from the negativo17 repository,
# which names it differently. On RPM Fusion — which is where we get ours — that
# name does not exist and asking for it fails the build.
#
# libheif reads the HEIC photos iPhones produce; the -freeworld half adds the
# HEVC decoder that makes them actually open.
say "AAC audio and HEIC photos"
aq_dnf install --allowerasing \
    fdk-aac \
    libheif \
    libheif-freeworld \
    libheif-tools

# ------------------------------------------------------------------------------
# Sound
# ------------------------------------------------------------------------------
# PipeWire replaced both of Linux's previous sound systems. The two "-pulseaudio"
# and "-jack" packages are not extra sound servers: they are shims that let
# software written for the old PulseAudio and JACK interfaces talk to PipeWire
# without knowing. Audio software — Ardour, Reaper, anything professional — asks
# for JACK, so that shim is not optional on a creator machine.
#
# WirePlumber is the piece that decides what is plugged in and where sound
# should go. Without it PipeWire runs and no audio comes out.
say "Sound (PipeWire)"
aq_dnf install \
    pipewire \
    pipewire-alsa \
    pipewire-pulseaudio \
    pipewire-jack-audio-connection-kit \
    pipewire-utils \
    wireplumber \
    alsa-utils

# ------------------------------------------------------------------------------
# Networking, Bluetooth, power and firmware
# ------------------------------------------------------------------------------
# NetworkManager is what the Wi-Fi menu talks to. The -wifi and -bluetooth
# packages are separate plug-ins: without them the menu exists and shows no
# networks, which looks like broken hardware and is not.
#
# tuned-ppd, not power-profiles-daemon: Fedora replaced one with the other in
# Fedora 41. tuned-ppd answers to the same name on the system bus, so GNOME's
# Balanced / Power Saver / Performance switch works exactly as before. Asking
# for the old package would install a second thing that fights it.
#
# linux-firmware is the blob of vendor firmware that Wi-Fi chips, GPUs and
# sound cards need loaded into them at boot. On a bare image it is absent, and
# its absence looks exactly like hardware that does not exist.
say "Networking, Bluetooth, power and firmware"
aq_dnf install \
    NetworkManager \
    NetworkManager-wifi \
    NetworkManager-bluetooth \
    NetworkManager-tui \
    wpa_supplicant \
    bluez \
    bluez-tools \
    bluez-obexd \
    upower \
    tuned-ppd \
    fwupd \
    linux-firmware \
    alsa-firmware \
    alsa-sof-firmware \
    iwlwifi-dvm-firmware \
    iwlwifi-mvm-firmware

# ------------------------------------------------------------------------------
# Boot appearance and memory
# ------------------------------------------------------------------------------
# Plymouth is the graphical boot splash. Without it, starting the computer shows
# a wall of white text. Our own boot artwork is a later job; a stock theme now
# means the boot looks finished rather than broken.
#
# zram-generator-defaults turns a slice of memory into compressed swap. It is
# what Fedora ships on every desktop edition and it is the difference between
# "the machine got slow while exporting" and "the machine froze".
say "Boot splash and compressed swap"
aq_dnf install \
    plymouth \
    plymouth-system-theme \
    plymouth-plugin-two-step \
    zram-generator-defaults

# ------------------------------------------------------------------------------
# Filesystems
# ------------------------------------------------------------------------------
# btrfs is the filesystem the installer uses. exFAT is what camera cards are
# formatted as — every SD card over 32 GB, every CFexpress card. NTFS is what a
# drive shared with a Windows machine is. A creator plugs all three in on the
# same afternoon, and a machine that silently cannot read a camera card is not
# usable for the job.
say "Filesystems (camera cards, Windows drives)"
aq_dnf install \
    btrfs-progs \
    exfatprogs \
    ntfs-3g \
    ntfsprogs \
    dosfstools \
    udisks2 \
    udisks2-btrfs

# ------------------------------------------------------------------------------
# Check the floor is really there
# ------------------------------------------------------------------------------
# Reading the package database back, rather than trusting that the installs
# above printed no errors. `dnf install` of a group of names can succeed having
# quietly substituted something.
say "Checking the hardware and media floor"

aq_installed \
    mesa-dri-drivers \
    mesa-va-drivers-freeworld \
    ffmpeg \
    fdk-aac \
    libheif-freeworld \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly \
    pipewire \
    wireplumber \
    pipewire-pulseaudio \
    NetworkManager \
    NetworkManager-wifi \
    bluez \
    upower \
    tuned-ppd \
    fwupd \
    linux-firmware \
    plymouth \
    zram-generator-defaults \
    btrfs-progs \
    exfatprogs \
    ntfs-3g

# The real test of the codec layer is not "is the package installed" but "can
# ffmpeg actually do the thing". Asking it to list its encoders and looking for
# the patented names proves the RPM Fusion build is the one that got installed
# and not Fedora's stripped one — which has the same command name and the same
# version number, and differs only in what it can do.
say "Asking ffmpeg what it can actually encode"
if aq_have ffmpeg; then
    ffmpeg -hide_banner -version | head -3
    ffmpeg -hide_banner -encoders > /tmp/aq-encoders.txt 2>&1 || true
    ffmpeg -hide_banner -decoders > /tmp/aq-decoders.txt 2>&1 || true

    for enc in libx264 libx265 libfdk_aac; do
        if grep -qw "${enc}" /tmp/aq-encoders.txt; then
            ok "ffmpeg can encode with ${enc}"
        else
            bad "ffmpeg has no ${enc} encoder — this is Fedora's stripped ffmpeg, not RPM Fusion's"
        fi
    done
    for dec in h264 hevc aac; do
        if grep -qw "${dec}" /tmp/aq-decoders.txt; then
            ok "ffmpeg can decode ${dec}"
        else
            bad "ffmpeg cannot decode ${dec} — camera files would not open"
        fi
    done
    rm -f /tmp/aq-encoders.txt /tmp/aq-decoders.txt
else
    bad "ffmpeg is not on the path at all"
fi

aq_finish "Hardware and media floor"
