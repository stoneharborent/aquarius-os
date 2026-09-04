#!/usr/bin/bash
# ==============================================================================
# STEP 6b — the virtual camera (v4l2loopback)
# ==============================================================================
# WHAT THIS IS, IN PLAIN ENGLISH
#
# OBS Studio has a button called "Start Virtual Camera". Press it and OBS
# pretends to be a webcam, so Zoom, Google Meet, Discord, Riverside or a plain
# browser can use whatever OBS is showing — your camera with a lower third on
# it, a screen share, three sources cut together — as if it were an ordinary
# camera plugged into the computer.
#
# That button needs a piece of code that lives inside the kernel, called
# v4l2loopback, which creates the fake camera. OBS ships as a Flatpak — a
# sandboxed app — and a sandboxed app cannot install anything into the kernel.
# So if the operating system does not provide it, the button fails, with an
# error message a beginner cannot act on. Providing it is our job, and this
# step is where it happens.
#
# ------------------------------------------------------------------------------
# THE HARD PART, AND IT IS THE SAME HARD PART AS THE NVIDIA DRIVER
# ------------------------------------------------------------------------------
# Code that runs inside the kernel is built against ONE EXACT KERNEL VERSION.
# Not "roughly the same": the exact one, down to the build number. Give a
# machine a module built for a different kernel and it refuses to load it.
#
# There are three ways to get one, and we pick the third:
#
#   1. Compile it here, during the build, against our own kernel. It would
#      always match — but the result is signed by nobody, and a computer with
#      Secure Boot switched on (which is most computers, and is the bench)
#      refuses to load an unsigned module. The person would have to turn
#      Secure Boot off, which is a real security decision to demand of somebody
#      who only wanted a webcam.
#
#   2. RPM Fusion's akmod-v4l2loopback, which compiles itself on the user's
#      machine whenever the kernel updates. That is how a normal Linux install
#      does it, and it does not fit an image-based operating system at all:
#      /usr is read-only, there is no compiler on the machine, and the result
#      is unsigned anyway.
#
#   3. Universal Blue's ready-made box of modules — ghcr.io/ublue-os/akmods —
#      already compiled and already signed with the same key as the NVIDIA
#      modules this image ALREADY trusts and already loads (see 60-nvidia.sh).
#      No compiler, no Secure Boot problem, no work on the user's machine.
#
# The catch with (3) is that their box was built against SOME Fedora kernel and
# this image contains SOME Fedora kernel, and for a day or two after a Fedora
# kernel update those are not the same one.
#
# ------------------------------------------------------------------------------
# THEY CANNOT NOT MATCH ANY MORE — AND A MISMATCH IS NOW A BUILD FAILURE
# ------------------------------------------------------------------------------
# ⚠️ THIS CHANGED ON 2026-09-04 AND IT IS THE POINT OF THIS FILE'S HISTORY.
#
# This step used to treat a kernel mismatch as a normal Tuesday: it skipped the
# module, wrote `status=unavailable` into a stamp file, and let the build go
# green. The reasoning was that changing which kernel AquariusOS ships, for a
# webcam, was a bigger decision than this step was entitled to make.
#
# What actually happened is the thing that reasoning did not predict. Fedora
# shipped kernel 7.1.13 while Universal Blue's modules were still built for
# 7.1.12, and the AMD/Intel image published — green, with no red anywhere — with
# no virtual camera AND no Xbox controller drivers. Nobody would have known
# without reading a file inside the image (build 33900370878).
#
# So the decision was made properly instead, one step earlier and once for both
# images: build_files/58-kernel-pin.sh pins this image's kernel to the one
# Universal Blue's modules were built for. After that step, a mismatch here is
# not a schedule accident — it means the pin did not happen, or something moved
# the kernel afterwards, or Universal Blue changed their layout. Every one of
# those is a real bug, so every one of them now STOPS THE BUILD.
#
# The stamp file stays, because it is still the honest answer to "does the
# virtual camera work on this image?" and both CI and `aq` read it:
#
#     /usr/share/aquarius/virtual-camera.txt
#
# It is simply no longer possible for a published image to have
# `status=unavailable` in it — the build that would have written it does not
# finish.
#
# Everything else about OBS — screen capture, cameras, capture cards, the
# plug-ins — never depended on any of this.
#
# ⚠️ THIS STEP MUST RUN AFTER 58-kernel-pin.sh AND 60-nvidia.sh. Step 5.8
#    sometimes replaces this image's kernel. Ask the question before the swap
#    and the answer is about a kernel that is no longer here.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AKMODS="/ctx-akmods"
STAMP="/usr/share/aquarius/virtual-camera.txt"
MODULES_LOAD="/usr/lib/modules-load.d/aquarius-v4l2loopback.conf"
MODPROBE_CONF="/usr/lib/modprobe.d/aquarius-v4l2loopback.conf"

install -d -m 0755 /usr/share/aquarius

# Write the stamp file. Called from every path out of this script, so the file
# always exists and always says something true.
stamp() {           # stamp <status> <line> ...
    local status="$1"
    shift
    {
        echo "# How the AquariusOS virtual camera turned out on this image."
        echo "# Written by build_files/62-virtual-camera.sh. Read by CI and by docs."
        echo "status=${status}"
        printf 'note=%s\n' "$*"
    } > "${STAMP}"
    chmod 0644 "${STAMP}"
    echo "Wrote ${STAMP}:"
    sed 's/^/       /' "${STAMP}"
}

# The machine is left with no instruction to load a module it does not have.
# Only reached on a failure path now — the build stops straight afterwards — but
# it still runs, so that the half-built image in the build cache is not left
# lying about itself either.
disarm() {
    rm -f "${MODULES_LOAD}"
    echo "Removed ${MODULES_LOAD} — nothing will try to load a module that is not here."
}

# ------------------------------------------------------------------------------
# 1. Which kernel is in this image?
# ------------------------------------------------------------------------------
# Asked of the image, not of the build machine. `uname -r` here would answer
# with GitHub's Ubuntu runner kernel, which has nothing to do with AquariusOS.
say "Which kernel is in this image"
AQ_KVER="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | head -1)"
AQ_KCOUNT="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '.' | wc -c)"
echo "  kernels present: ${AQ_KCOUNT}"
echo "  this image runs: ${AQ_KVER}"

if [ "${AQ_KCOUNT}" -ne 1 ] || [ -z "${AQ_KVER}" ]; then
    echo "AQUARIUS ERROR: this image has ${AQ_KCOUNT} kernels in /usr/lib/modules." >&2
    echo "                A bootable image must have exactly one, and step 6 is" >&2
    echo "                where that goes wrong. Nothing to do with the camera." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. What is in the box of ready-made modules?
# ------------------------------------------------------------------------------
say "The box of ready-made kernel modules"
if [ ! -d "${AKMODS}" ] || [ -z "$(ls -A "${AKMODS}" 2> /dev/null || true)" ]; then
    disarm
    stamp unavailable "The pre-built module box was not available to this build." \
        "Nothing was installed and nothing will try to load."
    echo "AQUARIUS ERROR: ${AKMODS} is empty or was not mounted." >&2
    echo "                That box is fetched for BOTH images by the Containerfile" >&2
    echo "                and step 5.8 has already read a kernel out of it, so an" >&2
    echo "                empty box here means the mount on this step is missing." >&2
    exit 1
fi

echo "Top of the tree:"
find "${AKMODS}" -maxdepth 3 -name '*v4l2*' 2> /dev/null | head -20 || true

# Universal Blue's documented layout is /rpms/kmods/ for the modules and
# /rpms/ublue-os/ for the small package carrying their signing key. Both are
# looked for by pattern rather than by exact name, because a version number in
# a file name is not ours to predict.
AQ_KMOD_RPM="$(find "${AKMODS}" -name 'kmod-v4l2loopback-*.rpm' 2> /dev/null | sort | head -1)"

if [ -z "${AQ_KMOD_RPM}" ]; then
    disarm
    stamp unavailable "Universal Blue's module box no longer contains v4l2loopback." \
        "Look at the listing in the build log for this step and pick the new name."
    echo "AQUARIUS ERROR: there is no kmod-v4l2loopback package in the box." >&2
    echo "                Universal Blue have renamed or dropped it. Everything" >&2
    echo "                that IS in the box:" >&2
    find "${AKMODS}" -name '*.rpm' -printf '                  %f\n' 2> /dev/null | head -40 >&2 || true
    echo "                Their README: https://github.com/ublue-os/akmods" >&2
    exit 1
fi

echo "  found: $(basename "${AQ_KMOD_RPM}")"

# ------------------------------------------------------------------------------
# 3. Was it built for OUR kernel?
# ------------------------------------------------------------------------------
# The honest way to ask is the package's own metadata, not its file name. An
# akmod package REQUIRES the exact kernel it was built against, so that
# requirement is the answer, and it is written by the tool that built it.
say "Was it built for this image's kernel?"
AQ_KMOD_REQUIRES="$(rpm -qp --requires "${AQ_KMOD_RPM}" 2> /dev/null || true)"
echo "It says it needs:"
printf '%s\n' "${AQ_KMOD_REQUIRES}" | sed 's/^/  /'

if printf '%s\n' "${AQ_KMOD_REQUIRES}" | grep -qF "${AQ_KVER}"; then
    ok "it was built for ${AQ_KVER} — the same kernel this image runs"
else
    disarm
    stamp unavailable "Kernel skew: this image runs ${AQ_KVER}," \
        "the pre-built module was made for another kernel."
    echo ""
    echo "  ---------------------------------------------------------------"
    echo "  THIS IS A REAL BUG NOW, AND THE BUILD STOPS HERE."
    echo "  ---------------------------------------------------------------"
    echo "  This image runs kernel ${AQ_KVER}, and the ready-made module was"
    echo "  built for a different one, so it would not load."
    echo ""
    echo "  Until 2026-09-04 that was allowed to happen quietly: the feature"
    echo "  was left out and the image shipped without it. It is not allowed"
    echo "  any more, because build_files/58-kernel-pin.sh runs first and pins"
    echo "  this image's kernel to exactly the one these modules were built"
    echo "  for. If they still disagree, one of these is true:"
    echo ""
    echo "    * step 5.8 did not run, or runs after this step — check the"
    echo "      order of the RUN lines in the Containerfile;"
    echo "    * something between step 5.8 and here moved the kernel;"
    echo "    * Universal Blue publishes two module boxes that disagree with"
    echo "      each other, which step 5.8 also checks for and refuses."
    echo ""
    echo "  What step 5.8 recorded about the kernel:"
    sed 's/^/    /' /usr/share/aquarius/kernel.txt 2> /dev/null \
        || echo "    (there is no /usr/share/aquarius/kernel.txt at all)"
    echo "  ---------------------------------------------------------------"
    echo ""
    echo "::error::The virtual camera module does not match this image's kernel (${AQ_KVER}). See build_files/58-kernel-pin.sh."
    exit 1
fi

# ------------------------------------------------------------------------------
# 4. Install it
# ------------------------------------------------------------------------------
# The ublue-os-akmods package carries their signing key and repository
# description. On the NVIDIA image step 6 has already installed it, and
# installing it twice is not an error — `dnf install` on something already
# present simply says so.
say "Installing the virtual camera module"
AQ_UBLUE_RPM="$(find "${AKMODS}" -name 'ublue-os-akmods*.rpm' 2> /dev/null | sort | head -1)"
if [ -n "${AQ_UBLUE_RPM}" ]; then
    echo "  signing key package: $(basename "${AQ_UBLUE_RPM}")"
    aq_dnf install "${AQ_UBLUE_RPM}"
else
    echo "  NOTE: no ublue-os-akmods package in the box. Continuing — on the"
    echo "        NVIDIA image step 6 has already installed it."
fi

aq_dnf install "${AQ_KMOD_RPM}"

# ------------------------------------------------------------------------------
# 5. Prove it, by looking for the module rather than trusting the installer
# ------------------------------------------------------------------------------
# An RPM can install perfectly and put its file somewhere this kernel will
# never look. The only question that matters is whether the module file is
# inside THIS kernel's module folder, so that is the question asked.
say "Checking the module really landed where the kernel looks"
AQ_KO="$(find "/usr/lib/modules/${AQ_KVER}" -name 'v4l2loopback.ko*' 2> /dev/null | head -1)"
if [ -n "${AQ_KO}" ]; then
    ok "the module is installed: ${AQ_KO}"
else
    echo "AQUARIUS ERROR: kmod-v4l2loopback installed, but no v4l2loopback module" >&2
    echo "                exists under /usr/lib/modules/${AQ_KVER}." >&2
    echo "                Everything under that folder that mentions v4l2:" >&2
    find "/usr/lib/modules/${AQ_KVER}" -name '*v4l2*' 2> /dev/null | sed 's/^/                  /' >&2
    exit 1
fi

# The kernel finds a module through an index, and a module added after the
# index was built is invisible until the index is rebuilt. Skipping this gives
# a machine with the file on disk and "module not found" at boot.
say "Rebuilding the kernel's module index"
depmod -a "${AQ_KVER}"
if grep -q 'v4l2loopback' "/usr/lib/modules/${AQ_KVER}/modules.dep" 2> /dev/null; then
    ok "the kernel's index now knows about v4l2loopback"
else
    bad "v4l2loopback is not in /usr/lib/modules/${AQ_KVER}/modules.dep — the kernel would not find it"
fi

# ------------------------------------------------------------------------------
# 6. The two settings files that make it a usable webcam
# ------------------------------------------------------------------------------
# Both arrived with system_files/ at step 5. They are checked here rather than
# assumed, because each fails silently on its own: no modules-load file means
# the module is never loaded, and no modprobe file means it loads with
# exclusive_caps off, which is the difference between "the virtual camera
# works in a browser" and "the virtual camera is listed and black".
say "The virtual camera's settings"
aq_file_has "${MODULES_LOAD}" '^v4l2loopback$' "the module is loaded at boot"
aq_file_has "${MODPROBE_CONF}" '^options v4l2loopback ' "the module has its settings"
aq_file_has "${MODPROBE_CONF}" 'exclusive_caps=1' "exclusive_caps=1 (or browsers show a black camera)"
aq_file_has "${MODPROBE_CONF}" 'card_label="AquariusOS Virtual Camera"' \
    "it introduces itself as the AquariusOS Virtual Camera"

stamp installed "v4l2loopback for kernel ${AQ_KVER}, from Universal Blue's signed module box." \
    "OBS's Start Virtual Camera button works, and the device is /dev/video9."

aq_finish "Virtual camera"
