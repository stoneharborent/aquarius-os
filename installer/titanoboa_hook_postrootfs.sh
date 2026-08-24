#!/usr/bin/env bash
# ==============================================================================
# Payload hook — installs and configures the installer app
# ==============================================================================
# Plain English: this is where the live USB stick gets its actual installer
# (Anaconda, the standard Fedora one), plus the script that tells it "install
# AquariusOS from the copy already on this stick". It also strips out things that
# make no sense in a temporary live session — background updaters, Steam, the
# rpm-ostree command, and so on.
#
# Adapted from ublue-os/bazzite installer/titanoboa_hook_postrootfs.sh
# (Apache-2.0), read at commit 0fb3abacb1135fbb50cbb575a18f53fea683ab0f
# (2026-08-23).
#
# What we dropped from Bazzite's version, and why:
#   - NVIDIA and Steam Deck special-casing — AquariusOS ships neither variant.
#   - Flatpak install steps — AquariusOS preloads no Flatpaks yet (Phase 2).
#   - Conky, custom wallpaper, KDE panel pins, the GNOME branch, the login-time
#     popup script and the bootloader-restore tool — cosmetic Bazzite branding,
#     nothing to do with whether the stick boots or installs.
# What we deliberately KEPT even though it looks Bazzite-flavoured:
#   - The "bazzite_xboot" partition label. AquariusOS is built on Bazzite and
#     inherits its boot layout, so the installed system expects that exact label.
#   - The Universal Blue Secure Boot key. Our kernel modules come from Bazzite
#     and are signed with it, so it still has to be enrolled.
#   - Every service in the disable list — our base image ships all of them.
# ==============================================================================

set -exo pipefail

source /etc/os-release

# Remove all versionlocks, in order to avoid dependency issues
dnf -qy versionlock clear

# Install Anaconda. Firefox is not optional here — Anaconda's modern interface is
# a web page, and Firefox is what displays it.
dnf install -qy --enable-repo=fedora-cisco-openh264 --allowerasing firefox anaconda-live libblockdev-{btrfs,lvm,dm}

mkdir -p /var/lib/rpm-state # Needed for Anaconda Web UI

# Utilities for displaying a dialog prompting users to review secure boot documentation
dnf install -qy --setopt=install_weak_deps=0 qrencode yad

# ------------------------------------------------------------------------------
# Which image do we install?
# ------------------------------------------------------------------------------
# Bazzite discovers this by searching its local container storage for anything
# named "bazzite*". We already know the exact answer — the payload build was told
# it — so we just split the name from the tag and then confirm it really is here.
_ref="${INSTALL_IMAGE_PAYLOAD:?}"
_ref="${_ref##*://}"
if [[ "${_ref##*/}" == *:* ]]; then
    imageref="${_ref%:*}"
    imagetag="${_ref##*:}"
else
    imageref="$_ref"
    imagetag="latest"
fi
podman image exists "${imageref}:${imagetag}" || {
    echo >&2 "::error::${imageref}:${imagetag} was not embedded into the payload image"
    exit 1
}

sbkey='https://github.com/ublue-os/akmods/raw/main/certs/public_key.der'
SECUREBOOT_KEY="/usr/share/ublue-os/sb_pubkey.der"
# AquariusOS is a Bazzite derivative and uses Bazzite's signing key, so Bazzite's
# own Secure Boot walkthrough applies to us word for word. Replace this with an
# AquariusOS page once we have one.
SECUREBOOT_DOC_URL="https://docs.bazzite.gg/sb"
SECUREBOOT_DOC_URL_QR="/usr/share/ublue-os/secure_boot_qr.png"

# Anaconda profile sanity check — the profile file needs this set.
: ${VARIANT_ID:?}

echo "AquariusOS release $VERSION_ID ($VERSION_CODENAME)" >/etc/system-release

# Secureboot Key Fetch
mkdir -p /usr/share/ublue-os
curl -Lo /usr/share/ublue-os/sb_pubkey.der "$sbkey"

# ------------------------------------------------------------------------------
# The install recipe ("kickstart")
# ------------------------------------------------------------------------------
# Anaconda reads this to know what to do. The important line is the
# "ostreecontainer" one near the bottom: it says "install the container image
# already sitting in this stick's local storage", which is why installing works
# with the network unplugged.
cat <<EOF >>/usr/share/anaconda/interactive-defaults.ks

# Create log directory
%pre
mkdir -p /tmp/anacoda_custom_logs
%end

# Check if there is a bitlocker partition and ask the user to disable it
%pre --erroronfail --log=/tmp/anacoda_custom_logs/detect_bitlocker.log
DOCS_QR=/tmp/detect_bitlocker_qr.png
IS_BITLOCKER=\$(lsblk -o FSTYPE --json | jq '.blockdevices | map(select(.fstype == "BitLocker")) | . != []')
{ WARNING_MSG="\$(</dev/stdin)"; } << 'WARNINGEOF'
<span size="x-large">Windows Bitlocker partition detected</span>

It might interrupt the installation process.
In such case, please, do <b>one</b> of the following:
    a) Disconnect its storage drive.
    b) Disable Bitlocker in Windows.
    c) Delete it in GNOME Disks.

Do you wish to continue?
WARNINGEOF

if [[ \$IS_BITLOCKER =~ true ]]; then
    qrencode -o \$DOCS_QR "https://www.wikihow.com/Turn-Off-BitLocker"
    _EXITLOCK=1
    _RETCODE=0
    while [[ \$_EXITLOCK -ne 0 ]]; do
        run0 --user=liveuser yad \
            --on-top \
            --timeout=10 \
            --image=\$DOCS_QR \
            --text="\$WARNING_MSG" \
            --button="Yes, I'm aware, continue":0 --button="Cancel installation":10
        _RETCODE=\$?
        case \$_RETCODE in
            0) _EXITLOCK=0; ;;
            10) _EXITLOCK=0; pkill liveinst; pkill firefox; exit 0 ;;
        esac
    done
fi
%end

# Remove the efi dir, must match efi_dir from the profile config
%pre-install --erroronfail
rm -rf /mnt/sysroot/boot/efi/EFI/fedora
%end

# Relabel the boot partition for the
%pre-install --erroronfail --log=/tmp/anacoda_custom_logs/repartitioning.log
set -x
xboot_dev=\$(findmnt -o SOURCE --nofsroot --noheadings -f --target /mnt/sysroot/boot)
if [[ -z \$xboot_dev ]]; then
  echo "ERROR: xboot_dev not found"
  exit 1
fi
e2label "\$xboot_dev" "bazzite_xboot"
%end

# Open a dialog with the installation logs
%onerror
run0 --user=liveuser yad \
    --timeout=0 \
    --text-info \
    --no-buttons \
    --width=600 \
    --height=400 \
    --text="An error occurred during installation. Please report this issue to the developers." \
    < /tmp/anaconda.log
%end

ostreecontainer --url=$imageref:$imagetag --transport=containers-storage --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
%include /usr/share/anaconda/post-scripts/secureboot-docs.ks

EOF

# ------------------------------------------------------------------------------
# Point the freshly installed system at the registry for future updates
# ------------------------------------------------------------------------------
# The install above came from the copy on the USB stick. Without this step the
# new machine would keep looking for that copy and never find an update again.
#
# DEVIATION FROM BAZZITE: Bazzite adds --enforce-container-sigpolicy here, which
# requires a signing policy for the image's registry to be present in the image.
# AquariusOS signs its images with cosign but does not yet ship a matching
# /etc/containers policy entry for ghcr.io/stoneharborent, so enforcing it would
# make every update fail. Add the flag back the same day the policy ships.
cat <<EOF >>/usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%post --erroronfail --log=/tmp/anacoda_custom_logs/bootc-switch.log
bootc switch --mutate-in-place --transport registry $imageref:$imagetag
%end
EOF

# Enroll Secureboot Key
cat <<EOF >>/usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
%post --erroronfail --nochroot --log=/tmp/anacoda_custom_logs/secureboot-enroll-key.log
set -oue pipefail

readonly ENROLLMENT_PASSWORD="universalblue"
readonly SECUREBOOT_KEY="$SECUREBOOT_KEY"

if [[ ! -d "/sys/firmware/efi" ]]; then
	echo "EFI mode not detected. Skipping key enrollment."
	exit 0
fi

if [[ ! -f "\$SECUREBOOT_KEY" ]]; then
	echo "Secure boot key not provided: \$SECUREBOOT_KEY"
	exit 0
fi

SYS_ID="\$(cat /sys/devices/virtual/dmi/id/product_name)"
if [[ ":Jupiter:Galileo:" =~ ":\$SYS_ID:" ]]; then
	echo "Steam Deck hardware detected. Skipping key enrollment."
	exit 0
fi

mokutil --timeout -1 || :
echo -e "\$ENROLLMENT_PASSWORD\n\$ENROLLMENT_PASSWORD" | mokutil --import "\$SECUREBOOT_KEY" || :
%end
EOF

cat <<EOF >>/usr/share/anaconda/post-scripts/secureboot-docs.ks
%post --nochroot --log=/tmp/anacoda_custom_logs/secureboot-docs.log
SECUREBOOT_KEY="$SECUREBOOT_KEY"
SECUREBOOT_DOC_URL="$SECUREBOOT_DOC_URL"
SECUREBOOT_DOC_URL_QR="$SECUREBOOT_DOC_URL_QR"

LC_ALL=C mokutil -t "\$SECUREBOOT_KEY" | grep -q "is already in the enrollment request" && \
    run0 --user=liveuser yad --timeout=0 --on-top --button=Ok:0 --image="\$SECUREBOOT_DOC_URL_QR" --text="<b>Secure Boot Key added:</b>\nPlease check the documentation to finish enrolling the key\n\$SECUREBOOT_DOC_URL"
%end
EOF

qrencode -o "$SECUREBOOT_DOC_URL_QR" "$SECUREBOOT_DOC_URL"

### Live session runtime tweaks ###

# Turn off everything that tries to update, phone home, or reconfigure hardware.
# None of it makes sense on a throwaway session running from a USB stick, and
# some of it actively breaks the installer.
(
    set +e
    for s in \
        rpm-ostree-countme.service \
        tailscaled.service \
        bazzite-hardware-setup.service \
        ublue-hardware-setup.service \
        bootloader-update.service \
        brew-upgrade.timer \
        brew-update.timer \
        brew-setup.service \
        rpm-ostreed-automatic.timer \
        uupd.timer \
        ublue-guest-user.service \
        ublue-os-media-automount.service \
        ublue-system-setup.service \
        bazzite-flatpak-manager.service \
        ublue-flatpak-manager.service \
        flatpak-add-fedora-repos.service \
        greenboot-set-rollback-trigger.service \
        greenboot-healthcheck.service \
        input-remapper.service \
        switcheroo-control.service \
        check-sb-key.service; do
        if systemctl list-unit-files "$s" >/dev/null 2>&1; then
            systemctl disable "$s"
        fi
    done

    for s in \
        podman-auto-update.timer \
        bazzite-user-setup.service \
        ublue-user-setup.service; do
        if systemctl --global list-unit-files "$s" >/dev/null 2>&1; then
            systemctl --global disable "$s"
        fi
    done
)

# Don't start Steam at login
rm -vf /etc/skel/.config/autostart/steam*.desktop

# Remove packages that shouldn't be used in a live session (also frees up room)
dnf -yq remove steam lutris bazaar waydroid || :

# Don't check for verified image
rm -vf /etc/profile.d/verify_motd.sh

rm -f /usr/share/applications/bbrew.desktop /usr/share/applications/bazzite-steam*.desktop
rm -f /usr/bin/rpm-ostree # Should never under any circumstance be ran on the live ISO

# Partition editor, for people who need to make room before installing
dnf -yq install gparted

###############################
