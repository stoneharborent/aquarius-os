#!/usr/bin/bash
# ==============================================================================
# STEP 6 — NVIDIA
# ==============================================================================
# This step does absolutely nothing on the AMD / Intel image. On the NVIDIA one
# it is the hardest thing in the whole build, so it is worth explaining properly.
#
# ------------------------------------------------------------------------------
# THE PROBLEM, IN PLAIN ENGLISH
# ------------------------------------------------------------------------------
# NVIDIA's driver has two halves. One half is an ordinary program. The other is
# a KERNEL MODULE — code that runs inside the kernel itself — and a kernel
# module only works with the exact kernel version it was built against. Not
# "roughly the same version": the exact one, down to the build number.
#
# On a normal Linux machine this is handled by compiling the module on your
# computer every time the kernel updates. That is slow, it needs compilers
# installed forever, and the result is unsigned — which means it will not load
# at all on a machine with Secure Boot switched on, which is most machines.
#
# ------------------------------------------------------------------------------
# HOW WE SOLVE IT
# ------------------------------------------------------------------------------
# Universal Blue (the people behind Bazzite and Bluefin) publish a box of
# already-compiled, already-signed NVIDIA kernel modules, rebuilt daily against
# the current Fedora kernel: ghcr.io/ublue-os/akmods-nvidia-open. The
# Containerfile fetches it as `nvidia-src` and it is mounted here at
# /ctx-nvidia.
#
# ⚠️ AND HERE IS THE ONE GENUINELY TRICKY PART.
#
# Their box was built against SOME Fedora kernel. Our image contains SOME Fedora
# kernel. Most days those are the same kernel, because both track mainline
# Fedora — as of 2026-09-02 both are 7.1.12-200.fc44. But "most days" is not
# "always": Fedora ships a kernel update, the two rebuild on different
# schedules, and for a day or two they differ.
#
# If they differ and we install anyway, the image builds perfectly and the
# machine boots to a black screen.
#
# So we do not hope. The box also contains a copy of the exact kernel it was
# built against. This script compares the two, and if they differ it REPLACES
# the kernel in our image with theirs. After that the match is not likely, it is
# guaranteed by construction. This is the mechanism Universal Blue's own README
# documents for exactly this situation.
#
# The cost is that the NVIDIA image's kernel can be a few days behind the
# AMD/Intel image's. That is the correct trade: a slightly older kernel that
# boots beats a newer one that does not.
#
# ------------------------------------------------------------------------------
# WHY NOT RPM FUSION'S akmod-nvidia-open INSTEAD?
# ------------------------------------------------------------------------------
# It exists, and it is the obvious alternative. It was rejected for R1 because:
#
#   * it has to be COMPILED during our build, which adds ten minutes and a
#     compiler toolchain to every single image we publish;
#   * the result is signed with a key nobody has, so Secure Boot machines
#     refuse to load it and the user has to turn Secure Boot off;
#   * the ublue modules are what the 4090 bench machine is ALREADY running,
#     because the Bazzite images used them. Rebasing to this image keeps the
#     same driver family and the same signing key.
#
# The full comparison is in docs/restart/nvidia-notes.md.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

NVIDIA="${NVIDIA:-0}"
AKMODS="/ctx-nvidia"

case "${NVIDIA}" in
    0)
        say "This is the AMD / Intel image — no NVIDIA driver"
        echo "Nothing to do. Mesa, installed in step 2, drives AMD and Intel cards"
        echo "completely, and this image is what people with those cards install."
        # Prove the empty stage really was empty. If this ever has files in it,
        # the conditional-stage trick in the Containerfile has broken and every
        # AMD image is quietly downloading 800 MB of NVIDIA parts.
        if [ -n "$(ls -A "${AKMODS}" 2> /dev/null || true)" ]; then
            echo "AQUARIUS WARNING: ${AKMODS} is not empty on an AMD/Intel build."
            echo "                  The Containerfile's nvidia-src-0 / nvidia-src-1"
            echo "                  stage selection is not working as intended."
            ls -la "${AKMODS}"
        else
            ok "no NVIDIA parts were fetched for this image (correct)"
        fi
        exit 0
        ;;
    1)
        say "This is the NVIDIA image"
        ;;
    *)
        echo "AQUARIUS ERROR: NVIDIA is '${NVIDIA}'. It must be 0 or 1." >&2
        echo "                Anything else would silently build one of the two" >&2
        echo "                images and label it as the other." >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# What did we actually get?
# ------------------------------------------------------------------------------
# Printing the whole tree costs nothing and is the single most useful thing in
# the log when Universal Blue changes their layout.
say "What is in the NVIDIA parts box"
find "${AKMODS}" -maxdepth 3 > /tmp/aq-akmods-tree.txt 2>/dev/null || true
head -60 /tmp/aq-akmods-tree.txt
echo "..."
echo "RPM count: $(find "${AKMODS}" -name '*.rpm' -printf . 2>/dev/null | wc -c)"

# The box carries a small file describing itself: which kernel, which driver
# version. Everything below reads from it rather than guessing from filenames.
AQ_VARS="${AKMODS}/rpms/kmods/nvidia-vars"
if [ ! -r "${AQ_VARS}" ]; then
    echo "AQUARIUS ERROR: ${AQ_VARS} is missing." >&2
    echo "                That file is how the NVIDIA parts describe themselves." >&2
    echo "                Universal Blue has changed the layout of their image." >&2
    echo "                The tree above shows what is actually in it — find the" >&2
    echo "                new location and update the paths at the top of this" >&2
    echo "                script. Their README:" >&2
    echo "                https://github.com/ublue-os/akmods" >&2
    exit 1
fi

echo "The NVIDIA parts describe themselves as:"
cat "${AQ_VARS}"
# shellcheck disable=SC1090
source "${AQ_VARS}"

# ------------------------------------------------------------------------------
# The kernel match
# ------------------------------------------------------------------------------
say "Making the kernel match the driver"

AQ_IMAGE_KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
echo "  kernel in this image      : ${AQ_IMAGE_KERNEL}"
echo "  kernel the driver expects : ${KERNEL_VERSION:-<not set>}"

if [ -z "${KERNEL_VERSION:-}" ]; then
    echo "AQUARIUS ERROR: the NVIDIA parts did not say which kernel they are for." >&2
    exit 1
fi

if [ "${AQ_IMAGE_KERNEL}" = "${KERNEL_VERSION}" ]; then
    ok "the kernels already match — nothing to swap"
else
    echo
    echo "They do not match. Replacing this image's kernel with the one the"
    echo "driver was built against. This is normal and expected: Fedora and"
    echo "Universal Blue rebuild on different schedules, so for a day or two"
    echo "after a Fedora kernel update the two drift apart."
    echo

    AQ_KERNEL_RPMS="${AKMODS}/kernel-rpms"
    if [ ! -d "${AQ_KERNEL_RPMS}" ] || [ -z "$(ls -A "${AQ_KERNEL_RPMS}" 2> /dev/null || true)" ]; then
        echo "AQUARIUS ERROR: this image's kernel is ${AQ_IMAGE_KERNEL} but the NVIDIA" >&2
        echo "                driver needs ${KERNEL_VERSION}, and the box does not" >&2
        echo "                contain a copy of that kernel to swap in." >&2
        echo "                Installing anyway would produce an image that builds" >&2
        echo "                and then boots to a black screen. Stopping instead." >&2
        echo "                Expected the kernel RPMs at: ${AQ_KERNEL_RPMS}" >&2
        exit 1
    fi

    echo "Kernel packages available to swap in:"
    ls -1 "${AQ_KERNEL_RPMS}"

    # --no-autoremove matters: without it, removing the kernel takes half the
    # system with it, because a great many packages are (indirectly) marked as
    # having been installed for the kernel's sake.
    aq_dnf remove --no-autoremove \
        kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
        || true
    aq_dnf install "${AQ_KERNEL_RPMS}"/*.rpm

    AQ_IMAGE_KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
    if [ "${AQ_IMAGE_KERNEL}" = "${KERNEL_VERSION}" ]; then
        ok "the kernel is now ${AQ_IMAGE_KERNEL}, matching the driver"
    else
        bad "after the swap the kernel is ${AQ_IMAGE_KERNEL}, still not ${KERNEL_VERSION}"
        aq_finish "NVIDIA"
    fi
fi

# ------------------------------------------------------------------------------
# The driver
# ------------------------------------------------------------------------------
# Order matters here. The "addons" package is installed first because it is what
# switches on the software sources the rest comes from — the NVIDIA driver
# repository and the container-toolkit repository. Install it second and the
# packages after it are simply not found.
say "Installing the NVIDIA driver"

# RPM Fusion also packages an NVIDIA driver, and if both repositories are
# enabled dnf may pick a mixture of the two, which does not work. Switching RPM
# Fusion off for the length of this step is what Universal Blue's own installer
# does for the same reason. It goes back on afterwards.
if aq_output_has rpmfusion aq_dnf repolist --all; then
    echo "Temporarily switching RPM Fusion off so the two NVIDIA drivers cannot mix."
    aq_dnf config-manager setopt "rpmfusion*".enabled=0
fi

aq_dnf install "${AKMODS}"/rpms/ublue-os/ublue-os-nvidia-addons-*.rpm
aq_dnf config-manager setopt "fedora-nvidia*".enabled=1 nvidia-container-toolkit.enabled=1

AQ_ARCH="$(rpm -E '%{_arch}')"
AQ_KMOD_RPM="${AKMODS}/rpms/kmods/kmod-nvidia-${KERNEL_VERSION}-${NVIDIA_AKMOD_VERSION}.${DIST_ARCH}.rpm"
if [ ! -r "${AQ_KMOD_RPM}" ]; then
    echo "AQUARIUS ERROR: the kernel module package is not where it was expected:" >&2
    echo "                ${AQ_KMOD_RPM}" >&2
    echo "                What is actually there:" >&2
    ls -l "${AKMODS}/rpms/kmods/" >&2
    exit 1
fi

# egl-wayland is what lets NVIDIA cards draw a Wayland desktop at all.
# nvidia-container-toolkit is what lets the graphics card be used from INSIDE a
# container — which is the whole basis of Phase R3's plan to run DaVinci Resolve
# in a Rocky Linux container, so it is not optional here even though nothing
# uses it yet.
aq_dnf install \
    "${AKMODS}"/rpms/nvidia/*."${AQ_ARCH}".rpm \
    "${AKMODS}"/rpms/nvidia/*.noarch.rpm \
    "${AQ_KMOD_RPM}" \
    egl-wayland \
    libva-nvidia-driver \
    nvidia-container-toolkit

# The driver and the kernel module are two separate packages built from the same
# source, and they must be the same version. A mismatch here is the classic
# "NVIDIA kernel module version mismatch" black screen.
AQ_KMOD_VERSION="$(rpm -q --queryformat '%{VERSION}' kmod-nvidia)"
AQ_DRIVER_VERSION="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [ "${AQ_KMOD_VERSION}" = "${AQ_DRIVER_VERSION}" ]; then
    ok "kernel module and driver are both ${AQ_DRIVER_VERSION}"
else
    bad "kernel module is ${AQ_KMOD_VERSION} but the driver is ${AQ_DRIVER_VERSION}"
fi

# Put RPM Fusion back, and switch the NVIDIA repositories off again so that a
# later `dnf install` on this machine cannot pull an unexpected driver update.
say "Putting the software sources back the way they were"
aq_dnf config-manager setopt "fedora-nvidia*".enabled=0 nvidia-container-toolkit.enabled=0
if aq_output_has rpmfusion aq_dnf repolist --all; then
    aq_dnf config-manager setopt "rpmfusion*".enabled=1
fi

# ------------------------------------------------------------------------------
# Boot settings
# ------------------------------------------------------------------------------
# nvidia-drm.modeset=1 tells the driver to take over the screen properly from
# the moment the kernel starts, instead of handing over halfway through boot.
# Without it a Wayland desktop on NVIDIA either refuses to start or flickers
# through a mode change on every boot.
#
# /usr/lib/bootc/kargs.d/ is how a bootc image ships kernel options: the file
# travels with the image, so it applies to every machine that installs it and
# survives every update, without anybody editing a bootloader.
say "Kernel options for NVIDIA"
install -d -m 0755 /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/10-aquarius-nvidia.toml << 'EOF'
# Hand the screen to the NVIDIA driver from the very start of boot.
# Without this, a Wayland desktop on an NVIDIA card either will not start or
# flickers through a mode change every time the machine boots.
kargs = ["nvidia-drm.modeset=1", "nvidia-drm.fbdev=1"]
EOF
cat /usr/lib/bootc/kargs.d/10-aquarius-nvidia.toml

# The driver has to be loaded from the initial ramdisk, before the desktop
# starts, or the machine shows a black screen and then the login prompt appears
# only after a long pause. The addons package ships a dracut config that omits
# it; Universal Blue flips that to force, and pre-loads the built-in Intel/AMD
# graphics too so that Chromium-based apps (Aquarius Editor among them) can
# still find a GPU to accelerate video on.
AQ_DRACUT_CONF="/usr/lib/dracut/dracut.conf.d/99-nvidia.conf"
if [ -f "${AQ_DRACUT_CONF}" ]; then
    sed -i 's@omit_drivers@force_drivers@g' "${AQ_DRACUT_CONF}"
    sed -i 's@ nvidia @ i915 amdgpu nvidia @g' "${AQ_DRACUT_CONF}"
    echo "${AQ_DRACUT_CONF} is now:"
    cat "${AQ_DRACUT_CONF}"
    aq_file_has "${AQ_DRACUT_CONF}" 'force_drivers' "the driver is forced into the boot ramdisk"
else
    bad "${AQ_DRACUT_CONF} is missing — the addons package did not ship it"
fi

# ------------------------------------------------------------------------------
# Services
# ------------------------------------------------------------------------------
# nvidia-cdi-refresh keeps the description of the graphics card that containers
# read up to date across driver updates — again, R3's Resolve container.
# nvidia-powerd manages power on laptops and is not present on every driver
# build, so it is enabled only if it exists.
say "Switching on the NVIDIA services"
for unit in nvidia-cdi-refresh.service nvidia-cdi-refresh.path nvidia-persistenced.service nvidia-powerd.service; do
    if systemctl list-unit-files "${unit}" > /dev/null 2>&1 \
        && [ -f "/usr/lib/systemd/system/${unit}" ]; then
        systemctl enable "${unit}" && ok "enabled ${unit}"
    else
        echo "  NOTE ${unit} is not in this driver build — skipping (this is normal)"
    fi
done

# The SELinux rule that lets containers reach the graphics card. Without it,
# running Resolve in a container fails with permission errors that look like a
# driver problem and are not.
AQ_SELINUX_PP="/usr/share/selinux/packages/nvidia-container.pp"
if [ ! -f "${AQ_SELINUX_PP}" ]; then
    echo "  NOTE ${AQ_SELINUX_PP} not shipped by this addons build — skipping"
elif ! aq_have semodule; then
    # semodule lives in policycoreutils. Installing it rather than skipping,
    # because without this rule Phase R3's Resolve container cannot reach the
    # graphics card and the failure looks like a driver bug.
    aq_dnf install policycoreutils
    semodule --verbose --install "${AQ_SELINUX_PP}" && ok "the container/GPU security rule is installed"
else
    semodule --verbose --install "${AQ_SELINUX_PP}" && ok "the container/GPU security rule is installed"
fi

# ------------------------------------------------------------------------------
# Check it
# ------------------------------------------------------------------------------
say "Checking the NVIDIA layer"

aq_installed kmod-nvidia nvidia-driver egl-wayland nvidia-container-toolkit

# The actual module file, on disk, under the kernel it belongs to. This is the
# check that catches a build where every package installed cleanly and the
# module ended up filed under a kernel that is not in this image.
AQ_MODDIR="/usr/lib/modules/${KERNEL_VERSION}"
echo "Kernels present in this image:"
ls -1 /usr/lib/modules/
if [ -d "${AQ_MODDIR}" ]; then
    ok "the module directory for ${KERNEL_VERSION} exists"
    if compgen -G "${AQ_MODDIR}/extra/nvidia*" > /dev/null; then
        ok "the NVIDIA kernel modules are filed under this image's kernel"
        ls -l "${AQ_MODDIR}"/extra/nvidia* > /tmp/aq-nvidia-mods.txt 2>&1 || true
        sed 's/^/       /' /tmp/aq-nvidia-mods.txt
    else
        bad "no nvidia* modules under ${AQ_MODDIR}/extra — the driver would not load"
        find /usr/lib/modules -name 'nvidia*' > /tmp/aq-nvidia-find.txt 2>/dev/null || true
        head -20 /tmp/aq-nvidia-find.txt
    fi
else
    bad "there is no ${AQ_MODDIR} — the kernel and the driver do not agree after all"
fi

aq_file_has /usr/lib/bootc/kargs.d/10-aquarius-nvidia.toml \
    'nvidia-drm\.modeset=1' "the boot options turn on NVIDIA mode setting"

aq_finish "NVIDIA"
