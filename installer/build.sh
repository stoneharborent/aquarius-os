#!/usr/bin/bash
# ==============================================================================
# AquariusOS installer payload — main build script
# ==============================================================================
# Plain English: this runs *inside* the payload image build (see Containerfile)
# and turns a normal AquariusOS image into a bootable live installer image.
#
# In order, it:
#   1. Tucks a copy of the real AquariusOS image inside this one, so the
#      installer can write it to disk with no internet connection.
#   2. Swaps in a plain Fedora kernel (preinitramfs hook) so Secure Boot works.
#   3. Adds "dracut-live" and rebuilds the startup image, which is what lets a
#      read-only disc boot into a working desktop at all.
#   4. Adds "livesys-scripts", the bits that auto-create the temporary "liveuser"
#      account and start a desktop session.
#   5. Installs and configures the Anaconda installer (postrootfs hook).
#   6. Adds the EFI boot files a disc needs, and the iso.yaml config Titanoboa
#      requires.
#
# If any line fails, the whole build fails — nothing half-finished ships.
#
# Adapted from ublue-os/bazzite installer/build.sh (Apache-2.0),
# read at commit 0fb3abacb1135fbb50cbb575a18f53fea683ab0f (2026-08-23).
# Bazzite in turn credits https://github.com/ondrejbudai/bootc-isos
#
# What we changed vs Bazzite:
#   - No Flatpak preinstall. Bazzite preloads Flathub apps into the live image so
#     the installer can copy them onto the new machine. AquariusOS ships no
#     preinstalled Flatpaks yet (Phase 2), so there is nothing to preload. This
#     has no effect on whether the USB stick boots.
#   - No GNOME branch. We only build the KDE variant today.
#   - Everything that affects live booting is kept as-is.
# ==============================================================================

set -exo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_IMAGE=${BASE_IMAGE:?}
INSTALL_IMAGE_PAYLOAD=${INSTALL_IMAGE_PAYLOAD:?}

# Create the directory that /root is symlinked to
mkdir -p "$(realpath /root)"

# Some tools sandbox themselves and want to write /proc/sys/user/max_user_namespaces,
# which is mounted read-only inside a container build. Remount it writable.
mount -o remount,rw /proc/sys

# ------------------------------------------------------------------------------
# Put a copy of AquariusOS inside the live image
# ------------------------------------------------------------------------------
# This is the actual OS that gets installed. Embedding it is what makes the USB
# stick work offline. It is also why this build needs --cap-add sys_admin: we are
# running podman inside a container build.
if mountpoint -q /usr/lib/containers/storage; then
    # We load our image from the host container storage if possible
    podman save --format oci-archive "$INSTALL_IMAGE_PAYLOAD" | podman load --storage-opt additionalimagestore=''
else
    podman pull "$INSTALL_IMAGE_PAYLOAD"
fi

# Copy system files
echo "Copying shared system files..."
cp -a /src/system_files/shared/. /

# ------------------------------------------------------------------------------
# Point the Anaconda installer profile at whatever this image calls itself
# ------------------------------------------------------------------------------
# Anaconda picks its settings file by matching the ID= line in /etc/os-release.
# AquariusOS is branded now, but ID is one of the few fields we deliberately
# leave saying "bazzite" (build_files/image-info.sh explains why), so that is
# still the value this matches today. Rather than hard-code either name and have
# it silently stop matching if that decision is ever revisited, we read the real
# value here and write it into the profile. Nothing to remember later.
# shellcheck source=/dev/null
source /etc/os-release
sed -i "s/@OS_ID@/${ID}/" /etc/anaconda/profile.d/aquarius-os.conf
grep -q "os_id = ${ID}" /etc/anaconda/profile.d/aquarius-os.conf

# Run the preinitramfs hook (swaps in a Secure Boot friendly kernel)
"$SCRIPT_DIR/titanoboa_hook_preinitramfs.sh"

# ------------------------------------------------------------------------------
# Live-boot support
# ------------------------------------------------------------------------------
# "dmsquash-live" is the piece that knows how to boot a squashed, read-only disc
# image and give it a writable overlay in memory. Without this the USB stick
# boots to a black screen.
dnf install -y dracut-live
kernel=$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version')
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# livesys-scripts creates the temporary "liveuser" account and starts a desktop.
dnf install -y livesys-scripts
sed -i "s/^livesys_session=.*/livesys_session=kde/" /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

# Run the postrootfs hook (installs and configures the Anaconda installer)
"$SCRIPT_DIR/titanoboa_hook_postrootfs.sh"

# Copy system files
echo "Copying overrides of system files..."
cp -af /src/system_files/overrides/. /

# image-builder needs gcdx64.efi
dnf install -y grub2-efi-x64-cdboot

# image-builder expects the EFI directory to be in /boot/efi
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/

# Remove fallback efi
cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi # NOTE: remove this line if breaks bootloader

# Set the timezone to UTC
rm -f /etc/localtime
systemd-firstboot --timezone UTC

# / in a booted live ISO is an overlayfs with upperdir pointed somewhere under /run
# This means that /var/tmp is also technically under /run.
# /run is of course a tmpfs, but set with quite a small size.
# ostree needs quite a lot of space on /var/tmp for temporary files so /run is not enough.
# Mount a larger tmpfs to /var/tmp at boot time to avoid this issue.
rm -rf /var/tmp
mkdir /var/tmp
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

# ------------------------------------------------------------------------------
# The file Titanoboa insists on
# ------------------------------------------------------------------------------
# This is the gap that used to make the ISO workflow fail. Titanoboa reads the
# disc label and boot menu from here and refuses to run without it.
mkdir -p /usr/lib/bootc-image-builder
cp /src/iso.yaml /usr/lib/bootc-image-builder/iso.yaml

# Clean up dnf cache to save space
dnf clean all
