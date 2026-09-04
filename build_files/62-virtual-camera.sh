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
# WHAT WE DO WHEN THEY DO NOT MATCH — AND WHY IT IS NOT A BUILD FAILURE
# ------------------------------------------------------------------------------
# 60-nvidia.sh, faced with the same problem, REPLACES this image's kernel with
# the one the NVIDIA modules were built for. It can do that because without the
# NVIDIA driver the NVIDIA image has no reason to exist.
#
# We deliberately do NOT do that here. Changing which kernel AquariusOS ships,
# on both images, for a webcam feature, is a much bigger decision than this
# step is entitled to make — and it would mean a kernel chosen by a third
# party's build schedule rather than by us.
#
# So on a mismatch this step SKIPS the module, says so at the top of the build
# log in plain words, removes the "load this at boot" file so the machine is
# not left asking for something that is not there, and writes down what
# happened in a file anybody can read:
#
#     /usr/share/aquarius/virtual-camera.txt
#
# That file is the honest answer to "does the virtual camera work on this
# image?", the CI checks read it, and `aq` can print it. It is the same
# arrangement as /usr/share/aquarius/shell-build.txt, for the same reason: an
# image that is missing one optional feature and says so is far better than
# either a build that will not finish or an image that lies.
#
# Everything else about OBS — screen capture, cameras, capture cards, the
# plug-ins — is unaffected either way.
#
# ⚠️ THIS STEP MUST RUN AFTER 60-nvidia.sh. That step sometimes replaces this
#    image's kernel. Compare against the old one and the answer is about a
#    kernel that is no longer here.
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
    echo "The box is empty or was not mounted."
    disarm
    stamp unavailable "The pre-built module box was not available to this build." \
        "Nothing was installed and nothing will try to load."
    aq_finish "Virtual camera"
    exit 0
fi

echo "Top of the tree:"
find "${AKMODS}" -maxdepth 3 -name '*v4l2*' 2> /dev/null | head -20 || true

# Universal Blue's documented layout is /rpms/kmods/ for the modules and
# /rpms/ublue-os/ for the small package carrying their signing key. Both are
# looked for by pattern rather than by exact name, because a version number in
# a file name is not ours to predict.
AQ_KMOD_RPM="$(find "${AKMODS}" -name 'kmod-v4l2loopback-*.rpm' 2> /dev/null | sort | head -1)"

if [ -z "${AQ_KMOD_RPM}" ]; then
    echo "There is no kmod-v4l2loopback package in the box."
    echo "Everything that IS in it:"
    find "${AKMODS}" -name '*.rpm' -printf '  %f\n' 2> /dev/null | head -40 || true
    disarm
    stamp unavailable "Universal Blue's module box no longer contains v4l2loopback." \
        "Look at the listing in the build log for this step and pick the new name."
    aq_finish "Virtual camera"
    exit 0
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
    echo ""
    echo "  ---------------------------------------------------------------"
    echo "  THE VIRTUAL CAMERA IS NOT IN THIS IMAGE, AND THAT IS NOT A BUG."
    echo "  ---------------------------------------------------------------"
    echo "  This image runs kernel ${AQ_KVER}."
    echo "  The ready-made module was built for a different one, so it would"
    echo "  not load. Rather than ship something that cannot work, it is left"
    echo "  out and written down."
    echo ""
    echo "  This happens for a day or two after a Fedora kernel update, while"
    echo "  Fedora and Universal Blue rebuild on their own schedules. The fix"
    echo "  is to build again tomorrow. Nothing needs changing."
    echo ""
    echo "  Everything else about OBS is unaffected: screen recording,"
    echo "  cameras, capture cards and the plug-ins all still work. Only the"
    echo "  'Start Virtual Camera' button is missing."
    echo "  ---------------------------------------------------------------"
    echo ""
    disarm
    stamp unavailable "Kernel skew: this image runs ${AQ_KVER}," \
        "the pre-built module was made for another kernel. Rebuild in a day or two."
    aq_finish "Virtual camera"
    exit 0
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
