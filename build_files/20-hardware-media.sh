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
# Networking, Bluetooth and power
# ------------------------------------------------------------------------------
# NetworkManager is what the Wi-Fi menu talks to. The -wifi and -bluetooth
# packages are separate plug-ins: without them the menu exists and shows no
# networks, which looks like broken hardware and is not.
#
# ⚠️ These are the PROGRAMS. The chips they drive also need firmware, and that
# is a separate list immediately below — the two together are what makes Wi-Fi
# work, and having only this half is precisely the bug of 2026-09-05.
#
# tuned-ppd, not power-profiles-daemon: Fedora replaced one with the other in
# Fedora 41. tuned-ppd answers to the same name on the system bus, so GNOME's
# Balanced / Power Saver / Performance switch works exactly as before. Asking
# for the old package would install a second thing that fights it.
say "Networking, Bluetooth and power"
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
    fwupd

# ------------------------------------------------------------------------------
# Firmware — the small programs that live inside the hardware
# ------------------------------------------------------------------------------
# WHAT FIRMWARE IS, IN ONE PARAGRAPH
#
# A Wi-Fi chip, a graphics card and a laptop speaker amplifier are all tiny
# computers of their own, and they ship from the factory with no program in
# them. Linux hands each one its program at boot, out of a folder of vendor
# blobs in /usr/lib/firmware. If the blob for your exact chip is not in that
# folder, the driver loads, finds nothing to feed the chip, and gives up — and
# the desktop then tells you the hardware is not there at all. That is not a
# figure of speech: GNOME's own words are "No Wi-Fi Adapter Found".
#
# ⚠️ THE TRAP THAT COST US A BENCH BOOT (2026-09-05)
#
# Up to Fedora 39, `linux-firmware` was ONE package containing every vendor's
# blobs. It is not any more. Fedora split it into about thirty per-vendor
# sub-packages, and the package still called `linux-firmware` is now only the
# ~50 MB leftovers — no MediaTek, no Realtek, no Atheros, no Broadcom, no
# graphics firmware at all.
#
# The split package "Recommends" the vendor ones, which on an ordinary Fedora
# desktop quietly drags them all in. It does NOT here: Fedora's container base
# images turn weak dependencies off (`install_weak_deps=False` in dnf.conf) so
# that images stay small. So `dnf install linux-firmware` in this build did
# exactly what it was asked and produced a machine with no Wi-Fi.
#
# That is what happened on Royce's bench on 5 September 2026. The board is an
# MSI X870 Tomahawk WIFI, whose radio is a MediaTek MT7925. The kernel loaded
# its `mt7925e` driver, looked in /usr/lib/firmware/mediatek/mt7925/, found an
# empty shelf, and the Wi-Fi menu reported no adapter.
#
# WHY WE SHIP THE WHOLE RADIO SET AND NOT JUST MEDIATEK
#
# Naming only the chip on today's bench would fix today's bench and break the
# next machine. AquariusOS is meant to be installed on laptops, and a laptop's
# Wi-Fi is whichever of five vendors the manufacturer got a good price on that
# quarter. Every one of these packages is between 1 and 60 MB, and a radio you
# did not ship is an install that ends at "there is no internet on this
# computer" — with no way to download the fix.
#
# So the rule for this list is: every Wi-Fi and Bluetooth vendor, every GPU
# vendor, every laptop audio amplifier, and both CPU vendors' microcode. What
# we leave out is at the bottom of this block, with reasons.
say "Firmware — Wi-Fi, Bluetooth, graphics, audio, CPU microcode"
aq_dnf install \
    linux-firmware \
    linux-firmware-whence \
    mt7xxx-firmware \
    mediatek-firmware \
    atheros-firmware \
    realtek-firmware \
    brcmfmac-firmware \
    iwlwifi-dvm-firmware \
    iwlwifi-mvm-firmware \
    iwlwifi-mld-firmware \
    iwlegacy-firmware \
    nxpwireless-firmware \
    tiwilink-firmware \
    libertas-firmware \
    qcom-wwan-firmware \
    amd-gpu-firmware \
    intel-gpu-firmware \
    nvidia-gpu-firmware \
    intel-vsc-firmware \
    alsa-firmware \
    alsa-sof-firmware \
    cirrus-audio-firmware \
    intel-audio-firmware \
    amd-ucode-firmware \
    microcode_ctl

# WHAT EACH OF THOSE IS FOR, AND ROUGHLY HOW BIG (Fedora 44, 20260810-1.fc44)
#
#   RADIOS — Wi-Fi and Bluetooth. All of them, deliberately.
#     mt7xxx-firmware        31 MB  MediaTek Wi-Fi 6E/7 — MT7921, MT7922,
#                                   MT7925 (Royce's bench board), MT7927,
#                                   MT7996. The Bluetooth half of the same
#                                   chips is in this package too, which is why
#                                   there is no separate MediaTek BT package to
#                                   look for.
#     mediatek-firmware       5 MB  The rest of MediaTek: SoC parts and the
#                                   Wi-Fi offload engines on their routers-on-
#                                   a-chip. Cheap to carry, completes the set.
#     atheros-firmware       45 MB  Qualcomm Atheros — ath9k, ath10k, ath11k,
#                                   ath12k, plus QCA Bluetooth. The biggest
#                                   radio package and one of the two most
#                                   common in laptops.
#     realtek-firmware        7 MB  Realtek — rtlwifi, rtw88, rtw89 and RTL
#                                   Bluetooth. The other most common, and what
#                                   nearly every cheap USB Wi-Fi stick is.
#     brcmfmac-firmware      10 MB  Broadcom and Cypress. Macs, a lot of
#                                   ultrabooks, Raspberry Pis.
#     iwlwifi-dvm-firmware    2 MB  Intel, the old generation.
#     iwlwifi-mvm-firmware   63 MB  Intel, the current generation. Already here
#                                   before this change.
#     iwlwifi-mld-firmware   20 MB  Intel Wi-Fi 7. It used to arrive by
#                                   accident, as something else's dependency.
#                                   Named here so it can never quietly leave.
#     iwlegacy-firmware       1 MB  Intel 3945/4965, from the 2008 laptops.
#     nxpwireless-firmware    2 MB  NXP Wi-Fi/Bluetooth/UWB.
#     tiwilink-firmware       5 MB  Texas Instruments WiLink.
#     libertas-firmware       1 MB  Marvell Libertas.
#     qcom-wwan-firmware      1 MB  Qualcomm mobile-broadband modems — the SIM
#                                   card slot in a business laptop.
#
#   GRAPHICS — every vendor, on BOTH images.
#     amd-gpu-firmware       27 MB  amdgpu and radeon. NOT optional: a modern
#                                   Radeon card or Ryzen APU does not start at
#                                   all without it, so the AMD/Intel image was
#                                   shipping without the firmware for the
#                                   hardware it is named after.
#     intel-gpu-firmware     12 MB  i915 and xe — the GuC/HuC microcontrollers
#                                   behind Intel's built-in graphics and Arc.
#     nvidia-gpu-firmware   101 MB  The open `nouveau` driver's firmware,
#                                   including GSP for Turing and newer (a 4090
#                                   is `ad102`). Shipped on BOTH images on
#                                   purpose: it is what puts a picture on the
#                                   screen if someone installs the AMD/Intel
#                                   image on an NVIDIA machine, which is the
#                                   one situation where they cannot download
#                                   the fix. It does not clash with the
#                                   proprietary driver — that one keeps its
#                                   firmware under a folder named after the
#                                   driver version, not the chip.
#
#   CAMERAS AND AUDIO
#     intel-vsc-firmware      8 MB  Intel Visual Sensing Controller — the
#                                   webcam in most 2023-and-newer laptops.
#     alsa-firmware           —     Older sound cards. Already here.
#     alsa-sof-firmware       —     Intel/AMD Sound Open Firmware — the audio
#                                   DSP in essentially every modern laptop.
#                                   Already here.
#     cirrus-audio-firmware   3 MB  Cirrus CS35L41/L56/L63 speaker amplifiers.
#                                   Without it the laptop has headphones and
#                                   silent speakers, which reads as a broken
#                                   machine.
#     intel-audio-firmware    3 MB  Intel's own audio DSP amplifiers.
#
#   CPU MICROCODE — the processor's own errata fixes, loaded at boot.
#     amd-ucode-firmware      1 MB  AMD. Royce's bench is a Ryzen on an X870
#                                   board, so this is the one that matters here.
#     microcode_ctl          16 MB  Intel, plus the tool that assembles both
#                                   into the boot ramdisk.
#
#   linux-firmware-whence     —     The licence text for all of the above. Legal
#                                   hygiene, not a feature; a few hundred KB.
#
# WHAT WE DELIBERATELY LEAVE OUT, AND WHY (about 350 MB avoided)
#
# Everything skipped is firmware for equipment that is not a personal computer.
# None of it can appear in a creator's desktop or laptop:
#
#     qcom-firmware         148 MB  Qualcomm Snapdragon SoCs — Adreno GPU,
#                                   Venus video, modem DSPs. That is an ARM
#                                   phone or an ARM laptop. Standing decision 5
#                                   says AquariusOS is x86_64 only. This is by
#                                   far the largest single saving. (Note the
#                                   name trap: `qcom-firmware` is the ARM SoC
#                                   one; Qualcomm's *Wi-Fi* lives in
#                                   `atheros-firmware`, which we DO ship.)
#     mlxsw_spectrum-firmware 102 MB Mellanox Spectrum switch ASICs. This is
#                                   the firmware for a rack-mounted network
#                                   switch, not for anything inside a PC.
#     mrvlprestera-firmware  71 MB  Marvell Prestera switch ASICs — same thing,
#                                   different vendor.
#     qcom-accel-firmware    11 MB  Qualcomm Cloud AI datacentre accelerators.
#     qed-firmware           10 MB  Marvell FastLinQ 25/40/100-gigabit server
#                                   network cards.
#     netronome-firmware      4 MB  Netronome SmartNICs — datacentre again.
#     liquidio-firmware       1 MB  Cavium LiquidIO server adapters.
#     dvb-firmware            1 MB  DVB broadcast-television tuner cards. Worth
#                                   saying out loud because it sounds like it
#                                   might be video-capture hardware and is not:
#                                   DVB is over-the-air TV reception. A capture
#                                   card (Elgato, Blackmagic) is USB video or a
#                                   kernel driver, and neither reads this.
#
# If a machine ever turns up that needs one of these, adding it is one line
# here — and the check below will start proving it is present.

# ------------------------------------------------------------------------------
# Boot appearance and memory
# ------------------------------------------------------------------------------
# Plymouth is the graphical boot splash. Without it, starting the computer shows
# a wall of white text.
#
# The AquariusOS splash itself is built in step 8 (build_files/80-boot-branding.sh
# — read that file's header for how the whole boot path is branded). These are
# the parts it is built out of:
#
#   plymouth                   the splash program itself
#   plymouth-system-theme      Fedora's default theme. We do NOT use it — we
#                              replace it — but it is what a bare image falls
#                              back to, and having it means step 8 has something
#                              to compare ours against.
#   plymouth-plugin-two-step   the drawing plug-in our theme uses. See the long
#                              note in system_files/.../aquarius.plymouth for
#                              why this one and not the scripting plug-in.
#   plymouth-plugin-label      draws TEXT on the splash. Without it the
#                              "type your disk password" prompt would appear
#                              as a box with no words in it.
#   plymouth-theme-spinner     Fedora's plain grey password-box pictures, which
#                              step 8 borrows rather than re-drawing. Also what
#                              Fedora's own default theme takes its artwork from.
#
# zram-generator-defaults turns a slice of memory into compressed swap. It is
# what Fedora ships on every desktop edition and it is the difference between
# "the machine got slow while exporting" and "the machine froze".
say "Boot splash and compressed swap"
aq_dnf install \
    plymouth \
    plymouth-system-theme \
    plymouth-plugin-two-step \
    plymouth-plugin-label \
    plymouth-theme-spinner \
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
    plymouth-plugin-two-step \
    plymouth-plugin-label \
    plymouth-theme-spinner \
    zram-generator-defaults \
    btrfs-progs \
    exfatprogs \
    ntfs-3g

# ------------------------------------------------------------------------------
# Check the firmware is really there — by package AND by file
# ------------------------------------------------------------------------------
# Two checks, because they catch different mistakes.
#
# The package check catches a typo: `dnf` would have stopped the build on an
# unknown name, but a package that got *replaced* by something else would slip
# through, and rpm is the only honest answer to "is this installed".
#
# The file check catches the thing the package check cannot see: that the blob
# for a particular chip is actually on disk under the name the kernel will ask
# for. It is the difference between "we installed the MediaTek package" and
# "an MT7925 will find its program at boot".
say "Checking the firmware for every radio, graphics card and CPU"

aq_installed \
    linux-firmware \
    linux-firmware-whence \
    mt7xxx-firmware \
    mediatek-firmware \
    atheros-firmware \
    realtek-firmware \
    brcmfmac-firmware \
    iwlwifi-dvm-firmware \
    iwlwifi-mvm-firmware \
    iwlwifi-mld-firmware \
    iwlegacy-firmware \
    nxpwireless-firmware \
    tiwilink-firmware \
    libertas-firmware \
    qcom-wwan-firmware \
    amd-gpu-firmware \
    intel-gpu-firmware \
    nvidia-gpu-firmware \
    intel-vsc-firmware \
    alsa-firmware \
    alsa-sof-firmware \
    cirrus-audio-firmware \
    intel-audio-firmware \
    amd-ucode-firmware \
    microcode_ctl

# aq_firmware_dir <folder> <how many files at least> "<whose hardware this is>"
#
# Counts what is under a firmware folder. Two details that both look like
# nothing and both matter:
#
#   * Fedora ships every blob xz-compressed — WIFI_RAM_CODE_MT7925_1_1.bin.xz,
#     not .bin — and the kernel unpacks it on the way in. So this counts entries
#     of ANY name; looking for `.bin` would report an empty shelf on a full one.
#   * Some entries are symbolic links rather than plain files (Intel's Wi-Fi
#     blobs are reachable under two names). `-type f` alone would miss those,
#     so links count too.
aq_firmware_dir() {
    local dir="$1" least="$2" who="$3" n
    if [ ! -d "${dir}" ]; then
        bad "${who}: ${dir} does not exist — that hardware would report itself missing"
        return
    fi
    n="$(find "${dir}" \( -type f -o -type l \) 2> /dev/null | wc -l | tr -d ' ')" || n=0
    if [ "${n}" -ge "${least}" ]; then
        ok "${who}: ${n} firmware files in ${dir}"
    else
        bad "${who}: only ${n} files in ${dir}, expected at least ${least}"
    fi
}

# The bench board first, because it is the reason this whole block exists.
# An MSI X870 Tomahawk WIFI carries a MediaTek MT7925, and the three files in
# this folder are its Wi-Fi program, its Wi-Fi patch and its Bluetooth program.
aq_firmware_dir /usr/lib/firmware/mediatek/mt7925 3 "MediaTek MT7925 Wi-Fi 7 + Bluetooth (the bench board)"
aq_firmware_dir /usr/lib/firmware/mediatek       40 "MediaTek radios"
aq_firmware_dir /usr/lib/firmware/rtw89           8 "Realtek Wi-Fi 6/7"
aq_firmware_dir /usr/lib/firmware/rtl_bt         20 "Realtek Bluetooth"
aq_firmware_dir /usr/lib/firmware/ath11k          8 "Qualcomm Atheros Wi-Fi 6"
aq_firmware_dir /usr/lib/firmware/ath12k          4 "Qualcomm Atheros Wi-Fi 7"
aq_firmware_dir /usr/lib/firmware/qca            20 "Qualcomm Bluetooth"
aq_firmware_dir /usr/lib/firmware/brcm           50 "Broadcom / Cypress Wi-Fi + Bluetooth"
aq_firmware_dir /usr/lib/firmware/amdgpu        100 "AMD graphics"
aq_firmware_dir /usr/lib/firmware/i915           50 "Intel graphics"
aq_firmware_dir /usr/lib/firmware/nvidia/ad102    1 "NVIDIA graphics, nouveau fallback (RTX 40-series)"
aq_firmware_dir /usr/lib/firmware/intel/vsc      10 "Intel laptop webcams"
aq_firmware_dir /usr/lib/firmware/cirrus         20 "Cirrus laptop speaker amplifiers"
aq_firmware_dir /usr/lib/firmware/amd-ucode       1 "AMD CPU microcode"

# Intel's Wi-Fi blobs are the odd ones out. They live in
# /usr/lib/firmware/intel/iwlwifi/ and are ALSO reachable by their old names at
# the top of /usr/lib/firmware, where some of the entries are symbolic links
# rather than real files. So this counts by name across the whole tree and does
# not care which of the two a given entry turns out to be — `find -type f`
# alone would report an empty shelf on a full one.
n_iwl="$(find /usr/lib/firmware -name 'iwlwifi-*' \( -type f -o -type l \) 2> /dev/null | wc -l | tr -d ' ')" || n_iwl=0
if [ "${n_iwl}" -ge 40 ]; then
    ok "Intel Wi-Fi: ${n_iwl} iwlwifi blobs"
else
    bad "Intel Wi-Fi: only ${n_iwl} iwlwifi blobs, expected at least 40"
fi

# The real test of the codec layer is not "is the package installed" but "can
# ffmpeg actually do the thing". Asking it to list its encoders and looking for
# the patented names proves the RPM Fusion build is the one that got installed
# and not Fedora's stripped one — which has the same command name and the same
# version number, and differs only in what it can do.
say "Asking ffmpeg what it can actually encode"
if aq_have ffmpeg; then
    ffmpeg -hide_banner -version > /tmp/aq-ffmpeg-version.txt 2>&1 || true
    head -3 /tmp/aq-ffmpeg-version.txt
    rm -f /tmp/aq-ffmpeg-version.txt
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
