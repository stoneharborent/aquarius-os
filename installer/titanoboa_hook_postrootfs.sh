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
#   - Steam Deck special-casing — AquariusOS has no handheld variant yet (Phase 4).
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

# ------------------------------------------------------------------------------
# Handhelds: give the live installer an on-screen keyboard
# ------------------------------------------------------------------------------
# THIS IS THE ONE THING A HANDHELD ISO GENUINELY NEEDS THAT THE OTHERS DO NOT.
#
# The situation: a ROG Xbox Ally has a touchscreen and no keyboard. Anaconda asks
# for a user name and a password. With no on-screen keyboard there is literally
# no way to answer it — the install is impossible until somebody finds a USB
# keyboard and a hub. So this is not a nicety, it is the difference between an
# ISO that installs and one that dead-ends.
#
# Why it has to be done HERE and not inherited: the live session of a handheld
# ISO is our *desktop* image (see the header of .github/workflows/build-iso.yml
# for why), and the desktop image has no reason to carry handheld keyboard
# settings. Only the ISO build knows that the thing being installed is a
# handheld, so only the ISO build can join the two facts up.
#
# `imageref` is worked out near the top of this file from INSTALL_IMAGE_PAYLOAD —
# the image being INSTALLED, not the one the live session is made of — so this
# test asks the right question even though the surrounding filesystem is the
# desktop image. Same variable the NVIDIA blocks below use.
#
# Part 1 is lifted from ublue-os/bazzite's own copy of this hook (Apache-2.0),
# which does exactly this for its deck ISOs — Bazzite moves the Maliit keyboard's
# launcher out of a backup folder to switch it on for KDE. The `|| :` is theirs
# too: a base image that stops shipping the backup copy must not fail an ISO
# build over it, so we print a loud warning instead of dying.
if [[ $imageref == *-deck* ]]; then
    echo "Handheld image detected — enabling the on-screen keyboard in the live session."

    if [[ -f /usr/share/ublue-os/backup/com.github.maliit.keyboard.desktop ]]; then
        mv -v /usr/share/ublue-os/backup/com.github.maliit.keyboard.desktop \
            /usr/share/applications/com.github.maliit.keyboard.desktop
    else
        echo "::warning::No Maliit keyboard launcher found to restore. A handheld"
        echo "::warning::installing from this ISO may need a USB keyboard. Check"
        echo "::warning::whether the base image renamed /usr/share/ublue-os/backup/."
    fi

    # Part 2 goes one step further than Bazzite, on purpose.
    #
    # Restoring the launcher makes the keyboard available; it does not switch
    # Plasma's virtual keyboard ON. On an INSTALLED handheld that second half
    # arrives with the deck base, in the two lines that Bazzite's
    # `steamdeck-kde-presets` package puts in /etc/xdg/kwinrc. The live session
    # is built from the desktop image, whose preset package deliberately deletes
    # that file — so those two lines are exactly what is missing here, and they
    # are the same two lines the installed system will have. We write them
    # ourselves rather than hoping the launcher alone is enough.
    #
    # If a future base image starts shipping /etc/xdg/kwinrc on the desktop
    # variant too, this appends to it rather than replacing it, so nothing of
    # theirs is lost.
    mkdir -p /etc/xdg
    if ! grep -q '^VirtualKeyboardEnabled=true' /etc/xdg/kwinrc 2>/dev/null; then
        cat >>/etc/xdg/kwinrc <<'KWINEOF'

[Wayland]
InputMethod[$e]=/usr/share/applications/org.kde.plasma.keyboard.desktop
VirtualKeyboardEnabled=true
KWINEOF
    fi
    echo "--- /etc/xdg/kwinrc in the live image is now: ---"
    cat /etc/xdg/kwinrc
fi

# ------------------------------------------------------------------------------
# NVIDIA machines: make the live session able to draw a picture
# ------------------------------------------------------------------------------
# Only runs when building the ISO for aquarius-os-nvidia. Background: the
# preinitramfs hook swapped AquariusOS's kernel for a plain signed Fedora one so
# Secure Boot machines will boot the USB stick — and NVIDIA's real drivers are
# built against the kernel we just removed, so they are not usable in the live
# session. The installed system gets them properly; the temporary installer
# desktop falls back to the open-source nouveau driver, and these two blocks are
# what make that fallback actually work.
#
# Lifted from ublue-os/bazzite installer/titanoboa_hook_postrootfs.sh
# (Apache-2.0), same commit as the rest of this file — Bazzite hits the identical
# problem on its own NVIDIA ISOs. We have since had to fix their version of the
# Mesa reinstall, which does not work from a derived image; the long comment on
# that block explains exactly why.

# GTK apps refuse to open under the default renderer on NVIDIA. Force the GL one.
if [[ $imageref == *-nvidia* ]]; then
    mkdir -p /etc/environment.d /etc/skel/.config/environment.d
    echo "GSK_RENDERER=gl" >>/etc/environment.d/99-nvidia-fix.conf
    echo "GSK_RENDERER=gl" >>/etc/skel/.config/environment.d/99-nvidia-fix.conf
fi

# ---- Re-enable nouveau -------------------------------------------------------
# The NVIDIA image deliberately deletes one small file — the nouveau "ICD", the
# note that tells Vulkan the open-source NVIDIA driver exists — so that games use
# NVIDIA's real driver instead. The live session needs that file back, because in
# here the real driver is the one that doesn't work.
#
# Getting it back means reinstalling the package that owns it, so rpm writes the
# deleted file out again. That is the whole trick.
#
# ⚠️ THE `--enable-repo=terra-mesa` BELOW IS LOAD-BEARING. Do not delete it.
# Bazzite does not use Fedora's Mesa; it uses Valve's patched build from a repo
# called "terra-mesa", and then switches that repo OFF in the shipped image.
# So a plain `dnf reinstall mesa-vulkan-drivers` inside this build can only see
# Fedora's Mesa, which is a different version, and dies with:
#
#     Installed packages for argument 'mesa-vulkan-drivers' are not available
#     in repositories in the same version ... cannot reinstall.
#
# (Run 32822911806, 2026-08-25. The `|| dnf install` fallback we inherited from
# Bazzite does NOT save it — the package is already installed, so that command
# succeeds while changing nothing, and the ICD stays missing.) Switching the repo
# back on for just this one command is exactly what Bazzite's own image build
# does whenever it needs Valve's Mesa.
#
# The `upgrade` fallback covers the day terra-mesa has moved to a newer build
# than the one in the image: there is then nothing to "reinstall", but upgrading
# rewrites the same files, which is all we actually need.
#
# nvidia-gpu-firmware is the easy one — it comes from Fedora's own repos and
# reinstalls without any of this.
if [[ $imageref == *-nvidia* ]]; then
    dnf -yq reinstall --allowerasing nvidia-gpu-firmware ||
        dnf -yq install --allowerasing nvidia-gpu-firmware

    # Note the trailing `|| :` — if BOTH of these fail we deliberately keep going
    # rather than letting `set -e` kill the script here. dnf's own error still
    # gets printed, and one step further down is the check that knows how to say
    # what went wrong in plain English. One failure point, not two.
    if ! dnf -yq reinstall --enable-repo=terra-mesa --allowerasing mesa-vulkan-drivers; then
        dnf -yq upgrade --enable-repo=terra-mesa --allowerasing mesa-vulkan-drivers || :
    fi

    # Did it actually come back? If not, stop. An ISO that boots to a black
    # screen is worse than no ISO, and this check is the only thing standing
    # between us and one. Never "fix" a failure here by deleting this check.
    (
        shopt -u nullglob
        ls /usr/share/vulkan/icd.d/nouveau_icd.*.json >/dev/null
    ) || {
        # Print what we can see, so the next person doesn't have to spend an
        # hour re-running the build just to find out what state things were in.
        echo >&2 "--- what mesa is actually installed ---"
        rpm -q mesa-vulkan-drivers >&2 || :
        echo >&2 "--- does the driver library itself exist? ---"
        ls -l /usr/lib64/libvulkan_nouveau.so >&2 || :
        echo >&2 "--- is the terra-mesa repo present? ---"
        dnf repo list --all 2>/dev/null | grep -i terra >&2 || :
        echo >&2 "::error::No nouveau vulkan icds found at /usr/share/vulkan/icd.d/nouveau_icd.*.json"
        exit 1
    }
fi

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
