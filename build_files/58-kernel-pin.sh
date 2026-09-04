#!/usr/bin/bash
# ==============================================================================
# STEP 5.8 — pin the kernel to the one the ready-made modules were built for
# ==============================================================================
# WHAT THIS IS, IN PLAIN ENGLISH
#
# Some pieces of AquariusOS are not ordinary programs. They are KERNEL MODULES:
# code that runs inside the kernel itself. There are four of them in this image
# and each one is a real feature:
#
#   nvidia         the graphics driver on the NVIDIA image
#   v4l2loopback   the fake webcam behind OBS's "Start Virtual Camera" button
#   xone           the Xbox Wireless Adapter (the little USB dongle)
#   xpadneo        Xbox controllers over Bluetooth, with rumble and battery
#
# A kernel module only works with the EXACT kernel version it was built
# against. Not "roughly the same": the exact one, down to the build number.
# Hand a machine a module built for a different kernel and it simply refuses to
# load it.
#
# We do not compile these ourselves. Universal Blue — the people behind Bazzite
# and Bluefin — publish boxes of already-compiled, already-SIGNED modules,
# rebuilt daily:
#
#   ghcr.io/ublue-os/akmods              v4l2loopback, xone, xpadneo   (both images)
#   ghcr.io/ublue-os/akmods-nvidia-open  the NVIDIA driver             (NVIDIA image only)
#
# Already-signed is the point. A module we compiled here would be signed by
# nobody, and a computer with Secure Boot switched on — which is most computers,
# and is the bench — refuses to load an unsigned module. Asking somebody to turn
# Secure Boot off so OBS can pretend to be a webcam is not a trade we offer.
#
# ------------------------------------------------------------------------------
# THE PROBLEM THIS STEP EXISTS TO FIX
# ------------------------------------------------------------------------------
# Universal Blue's boxes were built against SOME Fedora kernel. Our image starts
# from Fedora and therefore contains SOME Fedora kernel. Most days those are the
# same kernel. But Fedora ships a kernel update, the two rebuild on different
# schedules, and for a day or two they differ.
#
# Until 2026-09-04 only the NVIDIA image dealt with this. 60-nvidia.sh swapped
# the image's kernel for the one the driver needed, so the NVIDIA image was
# always correct. The AMD/Intel image did nothing — and so, the first time
# Fedora got ahead (Fedora 7.1.13 against Universal Blue's 7.1.12, build
# 33900370878), the AMD/Intel image quietly shipped with NO virtual camera and
# NO Xbox controller drivers. It built green. Nothing was red. The features were
# simply missing, and the only trace was a line in a file inside the image.
#
# That is exactly the kind of silent, plausible-looking wrongness this repo is
# built to refuse.
#
# ------------------------------------------------------------------------------
# WHAT WE DO INSTEAD
# ------------------------------------------------------------------------------
# One decision, made once, for BOTH images, before anything installs a module:
#
#   THE KERNEL IN AQUARIUSOS IS THE KERNEL UNIVERSAL BLUE'S MODULE BOX WAS
#   BUILT FOR.
#
# Not "usually". Always, by construction. This step reads which kernel that is,
# and if our image has a different one it replaces it — using the copy of that
# exact kernel that Universal Blue ships inside the box for this purpose
# (`/kernel-rpms`, which is their documented layout and the same source their
# own images use).
#
# After this step runs, every later step can simply assume the match, and a
# mismatch anywhere downstream is a real bug rather than a Tuesday.
#
# ------------------------------------------------------------------------------
# WHAT THIS COSTS, SAID HONESTLY
# ------------------------------------------------------------------------------
# AquariusOS's kernel can be a few days behind Fedora's newest. That is the
# correct trade and it is not close:
#
#   * a kernel a few days old is, in practice, the kernel almost every Fedora
#     machine is running anyway;
#   * the alternative is an operating system whose graphics driver, webcam and
#     controller support blink in and out depending on which day it was built.
#
# The NVIDIA image already made this trade and has since day one. This step
# extends it to the AMD/Intel image, which is the only reason the two were ever
# different.
#
# ------------------------------------------------------------------------------
# WHY THE PIN IS NOT LOCKED WITH A dnf VERSION LOCK
# ------------------------------------------------------------------------------
# The obvious next thought is "and versionlock it so nothing can move it". We
# deliberately do not, for two reasons:
#
#   1. Nothing in this build can move it. No step runs `dnf upgrade` or
#      `dnf distro-sync`, and installing a package never drags a kernel upgrade
#      along with it.
#   2. A version lock left behind in the finished image would follow every
#      machine that installs AquariusOS, and in an image-based operating system
#      the kernel is not updated on the machine at all — it arrives with the
#      next image. A lock there would be a confusing no-op at best.
#
# What we do instead is the thing this repo trusts: WRITE DOWN what was pinned,
# in /usr/share/aquarius/kernel.txt, and READ IT BACK. 90-cleanup.sh re-checks
# it at the very end of the build, and GitHub Actions re-checks it again inside
# the finished image. Content, never timestamps, and never an assumption.
#
# ⚠️ THIS STEP MUST RUN BEFORE EVERY STEP THAT INSTALLS A KERNEL MODULE —
#    60-nvidia.sh, 62-virtual-camera.sh and 68-gaming.sh — and before
#    80-boot-branding.sh, which builds the boot ramdisk for one exact kernel.
#    The Containerfile keeps that order and says so at each step.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

NVIDIA="${NVIDIA:-0}"
AKMODS="/ctx-akmods"          # Universal Blue's common module box (both images)
NVIDIA_BOX="/ctx-nvidia"      # their NVIDIA box (empty on the AMD/Intel image)
KERNEL_RPMS="${AKMODS}/kernel-rpms"
STAMP="/usr/share/aquarius/kernel.txt"

# The kernel is five packages. This is the whole list, and it is written out
# rather than globbed so that the image gets exactly these and nothing else —
# the box also contains kernel-devel, kernel-devel-matched and kernel-uki-virt,
# which are several hundred megabytes of things an image-based OS never uses.
AQ_KERNEL_PKGS=(kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra)

# The wider family that a kernel swap has to clear out. If any of these is
# installed at the OLD version it leaves files behind under /usr/lib/modules,
# and an image with two kernel folders in it is one `bootc container lint`
# refuses to publish.
AQ_KERNEL_FAMILY=(
    kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
    kernel-devel kernel-devel-matched kernel-uki-virt
)

install -d -m 0755 /usr/share/aquarius

# ------------------------------------------------------------------------------
# 1. Which kernel does the module box expect?
# ------------------------------------------------------------------------------
# Asked of the package itself, not of a file name. A file name is a guess; the
# version baked into an RPM is a fact written by the tool that built it.
say "Which kernel Universal Blue's modules were built for"

if [ ! -d "${KERNEL_RPMS}" ] || [ -z "$(ls -A "${KERNEL_RPMS}" 2> /dev/null || true)" ]; then
    echo "AQUARIUS ERROR: ${KERNEL_RPMS} is missing or empty." >&2
    echo "                That folder is where Universal Blue ships a copy of the" >&2
    echo "                exact kernel their modules were built against, and it is" >&2
    echo "                how this image decides which kernel to ship." >&2
    echo "                Either the module box was not mounted, or Universal Blue" >&2
    echo "                has changed the layout of their image." >&2
    echo "                What IS in ${AKMODS}:" >&2
    find "${AKMODS}" -maxdepth 2 2> /dev/null | head -40 >&2 || true
    echo "                Their README: https://github.com/ublue-os/akmods" >&2
    exit 1
fi

# Every package in the box is opened and ASKED what it is, rather than having
# its name read off its file name. A file name is a convention that Universal
# Blue could change tomorrow; the name and version inside an RPM are written by
# the tool that built it and are the same in every layout.
declare -A AQ_BOX_RPM_FILE=()
declare -A AQ_BOX_RPM_VER=()
echo "The kernel packages Universal Blue shipped with the modules:"
while IFS= read -r aq_rpm; do
    aq_meta="$(rpm -qp --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}' "${aq_rpm}" 2> /dev/null || true)"
    if [ -z "${aq_meta}" ]; then
        echo "  (could not read ${aq_rpm##*/} — skipping it)"
        continue
    fi
    aq_name="${aq_meta%% *}"
    aq_evr="${aq_meta##* }"
    echo "  ${aq_name}  ${aq_evr}"
    AQ_BOX_RPM_FILE["${aq_name}"]="${aq_rpm}"
    AQ_BOX_RPM_VER["${aq_name}"]="${aq_evr}"
done < <(find "${KERNEL_RPMS}" -maxdepth 1 -name '*.rpm' | sort)

AQ_BOX_KERNEL="${AQ_BOX_RPM_VER[kernel-core]:-}"
if [ -z "${AQ_BOX_KERNEL}" ]; then
    echo "AQUARIUS ERROR: there is no kernel-core package in ${KERNEL_RPMS}." >&2
    echo "                Without it there is no way to say which kernel the" >&2
    echo "                modules belong to. Universal Blue has changed their" >&2
    echo "                layout — the listing above shows what is actually there." >&2
    exit 1
fi
echo "  the modules were built for : ${AQ_BOX_KERNEL}"

# ------------------------------------------------------------------------------
# 2. On the NVIDIA image, the two boxes must agree
# ------------------------------------------------------------------------------
# Universal Blue build the common box and the NVIDIA box from the SAME cached
# kernel, in the same run, so they normally cannot disagree. "Normally cannot"
# is not "cannot", though: if one of the two builds fails, the older image stays
# published and the pair drifts. Installing anyway would mean an image whose
# NVIDIA driver and whose Xbox drivers want different kernels — and only one of
# them can be right.
if [ "${NVIDIA}" = "1" ]; then
    say "Checking the NVIDIA box agrees with the common box"
    AQ_VARS="${NVIDIA_BOX}/rpms/kmods/nvidia-vars"
    if [ ! -r "${AQ_VARS}" ]; then
        echo "AQUARIUS ERROR: ${AQ_VARS} is missing." >&2
        echo "                That file is how the NVIDIA parts say which kernel" >&2
        echo "                they are for. Universal Blue has changed the layout" >&2
        echo "                of their NVIDIA image. What is in it:" >&2
        find "${NVIDIA_BOX}" -maxdepth 3 2> /dev/null | head -40 >&2 || true
        exit 1
    fi
    echo "The NVIDIA parts describe themselves as:"
    sed 's/^/  /' "${AQ_VARS}"
    # shellcheck disable=SC1090
    source "${AQ_VARS}"

    if [ -z "${KERNEL_VERSION:-}" ]; then
        echo "AQUARIUS ERROR: the NVIDIA parts did not say which kernel they are for." >&2
        exit 1
    fi

    if [ "${KERNEL_VERSION}" = "${AQ_BOX_KERNEL}" ]; then
        ok "both Universal Blue boxes were built for ${AQ_BOX_KERNEL}"
    else
        echo "AQUARIUS ERROR: Universal Blue's two module boxes disagree today." >&2
        echo "                  the common box (webcam, controllers): ${AQ_BOX_KERNEL}" >&2
        echo "                  the NVIDIA box (graphics driver)    : ${KERNEL_VERSION}" >&2
        echo "                An image can only contain one kernel, so one of those" >&2
        echo "                two sets of drivers would not load. Stopping rather" >&2
        echo "                than shipping an image that is half broken." >&2
        echo "                This normally means one of their two daily builds" >&2
        echo "                failed. Building again tomorrow fixes it; nothing" >&2
        echo "                here needs changing." >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 3. Which kernel is in the image right now?
# ------------------------------------------------------------------------------
say "Which kernel this image has right now"
AQ_IMAGE_KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
echo "  kernel in this image       : ${AQ_IMAGE_KERNEL}"
echo "  kernel the modules need    : ${AQ_BOX_KERNEL}"
echo
echo "Every kernel package installed:"
rpm -qa --queryformat '  %{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 'kernel*' | sort

AQ_ACTION="already-matched"

if [ "${AQ_IMAGE_KERNEL}" = "${AQ_BOX_KERNEL}" ]; then
    ok "the kernels already match — nothing to swap"
else
    # --------------------------------------------------------------------------
    # 4. The swap
    # --------------------------------------------------------------------------
    say "Replacing this image's kernel with the one the modules were built for"
    echo "This is normal and expected. Fedora and Universal Blue rebuild on"
    echo "different schedules, so for a day or two after a Fedora kernel update"
    echo "the two drift apart. AquariusOS follows Universal Blue, because a"
    echo "slightly older kernel with a working graphics driver, webcam and"
    echo "controllers beats a newer one without them."
    echo

    # Work out the exact file for each package before removing anything. Doing
    # the checking first means a missing file cannot leave the image with no
    # kernel at all.
    AQ_TO_INSTALL=()
    for pkg in "${AQ_KERNEL_PKGS[@]}"; do
        rpmfile="${AQ_BOX_RPM_FILE[${pkg}]:-}"
        rpmver="${AQ_BOX_RPM_VER[${pkg}]:-}"
        if [ -z "${rpmfile}" ]; then
            echo "AQUARIUS ERROR: there is no ${pkg} package in Universal Blue's box." >&2
            echo "                All five kernel packages have to be there or the" >&2
            echo "                swap would leave a half-installed kernel." >&2
            echo "                The listing above shows what IS there." >&2
            exit 1
        fi
        if [ "${rpmver}" != "${AQ_BOX_KERNEL}" ]; then
            echo "AQUARIUS ERROR: the box's ${pkg} is ${rpmver} but its kernel-core" >&2
            echo "                is ${AQ_BOX_KERNEL}. The five kernel packages must" >&2
            echo "                all be the same version — installing a mixture" >&2
            echo "                produces a kernel that does not boot." >&2
            exit 1
        fi
        AQ_TO_INSTALL+=("${rpmfile}")
    done
    echo "Kernel packages to install:"
    printf '  %s\n' "${AQ_TO_INSTALL[@]##*/}"
    echo

    # Clear out the old kernel first, including the parts of it we are not
    # putting back. A kernel-devel or kernel-uki-virt left at the old version
    # keeps a second folder alive under /usr/lib/modules, and an image with two
    # kernel folders is one `bootc container lint` refuses.
    #
    # --no-autoremove matters enormously: without it, removing the kernel takes
    # half the system with it, because a great many packages are (indirectly)
    # marked as having been installed for the kernel's sake.
    AQ_TO_REMOVE=()
    for pkg in "${AQ_KERNEL_FAMILY[@]}"; do
        if rpm -q "${pkg}" > /dev/null 2>&1; then
            AQ_TO_REMOVE+=("${pkg}")
        fi
    done
    echo "Old kernel packages to remove first:"
    printf '  %s\n' "${AQ_TO_REMOVE[@]}"
    aq_dnf remove --no-autoremove "${AQ_TO_REMOVE[@]}" || true

    aq_dnf install "${AQ_TO_INSTALL[@]}"
    AQ_ACTION="swapped-from-${AQ_IMAGE_KERNEL}"

    AQ_IMAGE_KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
    if [ "${AQ_IMAGE_KERNEL}" = "${AQ_BOX_KERNEL}" ]; then
        ok "the kernel is now ${AQ_IMAGE_KERNEL}"
    else
        bad "after the swap the kernel is ${AQ_IMAGE_KERNEL}, not ${AQ_BOX_KERNEL}"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Read the result back
# ------------------------------------------------------------------------------
# The package database saying the right thing is not the same as the files on
# disk being right. A bootable image must have exactly ONE folder under
# /usr/lib/modules, and it must be the one every module is about to be filed
# under.
say "Checking the kernel files on disk"
echo "Folders under /usr/lib/modules:"
find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort

AQ_KDIR_COUNT="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '.' | wc -c)"
if [ "${AQ_KDIR_COUNT}" -eq 1 ]; then
    ok "exactly one kernel folder, which is what a bootable image must have"
else
    bad "${AQ_KDIR_COUNT} kernel folders under /usr/lib/modules — there must be exactly one"
    echo "  Which package each stray folder belongs to:" >&2
    while IFS= read -r d; do
        echo "    ${d} -> $(rpm -qf "${d}" 2> /dev/null || echo 'no package owns it')" >&2
    done < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d)
fi

if [ -d "/usr/lib/modules/${AQ_BOX_KERNEL}" ]; then
    ok "/usr/lib/modules/${AQ_BOX_KERNEL} is there — modules will be filed where the kernel looks"
else
    bad "there is no /usr/lib/modules/${AQ_BOX_KERNEL} — the package database and the files disagree"
fi

echo
echo "Every kernel package installed now:"
rpm -qa --queryformat '  %{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 'kernel*' | sort

# ------------------------------------------------------------------------------
# 6. Write it down
# ------------------------------------------------------------------------------
# This file is the answer to "which kernel is in this image, and why that one?".
# 90-cleanup.sh reads it back at the end of the build and GitHub Actions reads
# it back inside the finished image, so a later step quietly moving the kernel
# cannot go unnoticed.
{
    echo "# Which kernel AquariusOS ships, and why this one."
    echo "# Written by build_files/58-kernel-pin.sh. Read back by 90-cleanup.sh and by CI."
    echo "#"
    echo "# AquariusOS pins its kernel to the one Universal Blue's ready-made,"
    echo "# already-signed kernel modules were built against, because those modules"
    echo "# are the NVIDIA driver, the OBS virtual camera and the Xbox controller"
    echo "# drivers, and a kernel module only loads on the exact kernel it was built"
    echo "# for. See docs/restart/kernel.md."
    echo "kernel=${AQ_BOX_KERNEL}"
    echo "source=ghcr.io/ublue-os/akmods (kernel-rpms)"
    echo "action=${AQ_ACTION}"
} > "${STAMP}"
chmod 0644 "${STAMP}"
echo
echo "Wrote ${STAMP}:"
sed 's/^/       /' "${STAMP}"

aq_finish "Kernel pin"
