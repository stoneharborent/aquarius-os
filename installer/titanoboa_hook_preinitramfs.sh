#!/usr/bin/env bash
# ==============================================================================
# Payload hook — runs BEFORE the live startup image is rebuilt
# ==============================================================================
# Plain English: Bazzite (and therefore AquariusOS) ships its own custom kernel.
# Custom kernels are not signed by Microsoft, so a PC with Secure Boot switched
# on refuses to boot them from a USB stick. So for the *live session only* we rip
# out the custom kernel and put plain signed Fedora kernel back in. The OS that
# actually gets installed still gets the normal AquariusOS kernel — this only
# affects the temporary installer environment.
#
# Adapted from ublue-os/bazzite installer/titanoboa_hook_preinitramfs.sh
# (Apache-2.0), read at commit 0fb3abacb1135fbb50cbb575a18f53fea683ab0f
# (2026-08-23). Only change: the NVIDIA firmware line no longer inspects the
# image name — we install the firmware for both AquariusOS variants and move on
# if it isn't available. (Bazzite looks the name up because its script has no
# other way to know which image it's building; ours is told directly, and the
# real NVIDIA-only work happens in the postrootfs hook.)
# ==============================================================================

set -exo pipefail

# Swap kernel with vanilla and rebuild initramfs.
#
# This is done because we want the initramfs to use a signed
# kernel for secureboot.
kernel_pkgs=(
    kernel
    kernel-core
    kernel-devel
    kernel-devel-matched
    kernel-modules
    kernel-modules-core
    kernel-modules-extra
)
dnf -y versionlock delete "${kernel_pkgs[@]}"
dnf --setopt=protect_running_kernel=False -y remove "${kernel_pkgs[@]}"
(cd /usr/lib/modules && rm -rf -- ./*)
dnf -y --repo fedora,updates --setopt=tsflags=noscripts install kernel kernel-core
kernel=$(find /usr/lib/modules -maxdepth 1 -type d -printf '%P\n' | grep .)
depmod "$kernel"

# Include nvidia-gpu-firmware so the live desktop can at least draw a picture on
# NVIDIA hardware. Best effort — if the package is unavailable, carry on.
dnf install -yq nvidia-gpu-firmware || :
dnf clean all -yq
