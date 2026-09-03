#!/usr/bin/bash
# ==============================================================================
# STEP 8 — Cleanup: sweeping up after the build
# ==============================================================================
# WHY THIS MATTERS MORE THAN IT SOUNDS
#
# On a normal computer, leaving a few hundred megabytes of downloaded package
# files around is untidy. Here it is worse than untidy, for two reasons.
#
# First, the image is the thing that gets downloaded onto every machine, every
# time it updates. Rubbish in it is rubbish everybody downloads, forever.
#
# Second, and less obviously: /var on an image-based system belongs to the
# MACHINE, not to the image. Anything we leave in /var is shipped once, written
# to the disk on first install, and then never updated again — it becomes a
# fossil that no future image can remove. So /var must be empty of our leavings.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

say "Cleaning up"

# Throw away the downloaded packages and the catalogue.
aq_dnf clean all || true

# ------------------------------------------------------------------------------
# Exactly one kernel
# ------------------------------------------------------------------------------
# A bootable image must contain one kernel and no more — `bootc container lint`
# refuses an image with two, because there is no way to say which one it should
# boot. This normally takes care of itself, but the NVIDIA image can swap its
# kernel for the one the driver was built against, and a swap can leave the old
# folder behind holding generated files that no package owns.
say "Checking there is exactly one kernel"
AQ_KERNEL="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
echo "The installed kernel is ${AQ_KERNEL}. Folders under /usr/lib/modules:"
ls -1 /usr/lib/modules/

for d in /usr/lib/modules/*/; do
    name="$(basename "${d}")"
    if [ "${name}" != "${AQ_KERNEL}" ]; then
        echo "Removing leftovers from a kernel that is no longer installed: ${name}"
        rm -rf "${d}"
    fi
done

AQ_KERNEL_COUNT="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf . | wc -c)"
if [ "${AQ_KERNEL_COUNT}" -eq 1 ]; then
    ok "exactly one kernel in the image (${AQ_KERNEL})"
else
    bad "${AQ_KERNEL_COUNT} kernel folders in /usr/lib/modules — a bootable image must have one"
    ls -la /usr/lib/modules/
fi

# ------------------------------------------------------------------------------
# Empty out /var
# ------------------------------------------------------------------------------
# Keep the folders (systemd expects them to exist), remove what is in them.
say "Emptying /var"
for dir in /var/cache /var/log /var/tmp /var/lib/dnf /var/lib/rpm-state; do
    if [ -d "${dir}" ]; then
        find "${dir}" -mindepth 1 -delete 2> /dev/null || true
    fi
done
rm -rf /tmp/* /tmp/.[!.]* 2> /dev/null || true

echo "What is left in /var:"
du -sh /var/* 2> /dev/null || true

# The one thing that must not be there. If a Flatpak remote was added the wrong
# way in step 3, this is where it shows up — and it would be shipped once and
# then frozen on every machine forever.
if [ -e /var/lib/flatpak/repo ]; then
    bad "/var/lib/flatpak/repo exists — Flatpak state must not ship inside the image"
else
    ok "no Flatpak state in /var"
fi

# ------------------------------------------------------------------------------
# Nothing of ours should have escaped into the image
# ------------------------------------------------------------------------------
# The build scripts are mounted, never copied, so none of them should be in the
# finished image. If one is, something in the recipe copied instead of mounting.
#
# /ctx and /ctx-nvidia are deliberately NOT in this list: they are the mounts
# themselves, they are still attached while this script runs, and they vanish
# the moment the step ends. The names below would only exist if somebody had
# written `COPY build_files /` into the recipe by mistake.
say "Making sure none of the build's own files shipped"
for stray in /build_files /system_files /ingest; do
    if [ -e "${stray}" ]; then
        bad "${stray} exists in the finished image — it should only ever have been mounted"
        ls -la "${stray}" > /tmp/aq-stray.txt 2>&1 || true
        head -10 /tmp/aq-stray.txt
    else
        ok "${stray} is not in the image (correct)"
    fi
done

# ------------------------------------------------------------------------------
# How big did it get?
# ------------------------------------------------------------------------------
# Printed for the log so that a jump in size is visible in the build history
# rather than discovered by a slow download.
say "Size of the finished image"
du -sh /usr 2> /dev/null || true
echo "The ten largest things under /usr:"
du -sh /usr/* 2> /dev/null > /tmp/aq-usr-sizes.txt || true
sort -rh /tmp/aq-usr-sizes.txt > /tmp/aq-usr-sorted.txt || true
head -10 /tmp/aq-usr-sorted.txt
rm -f /tmp/aq-usr-sizes.txt /tmp/aq-usr-sorted.txt
echo
echo "Packages installed: $(rpm -qa --queryformat '.' | wc -c)"

aq_finish "Cleanup"
