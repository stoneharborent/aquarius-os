#!/usr/bin/bash
# Add handheld controls to the USB runtime, not to the installed OS payload.
# Run in installer/Containerfile with /output (ISO folder) and /work mounted.
set -euo pipefail
iso=/output/install.iso
[ -f "$iso" ]
work=$(mktemp -d /work/handheld-installer.XXXXXX)
root="$work/runtime"
echo "Installer workspace: $work"
xorriso -osirrox on -indev "$iso" \
    -extract /images/install.img "$work/install.img" \
    -extract /container "$work/payload"
unsquashfs -no-progress -d "$root" "$work/install.img"
grep -qx 'VERSION_ID=44' "$root/usr/lib/os-release"
/installer/restore-controller-drivers.sh "$root" "$work/drivers"

# Lorax moves the installer's repositories out of dnf's way. Use Fedora's
# repositories from the tooling container solely to add the keyboard's shell
# and InputPlumber's two libraries. Never replace the installer kernel.
mkdir -p "$root/etc/yum.repos.d" "$root/var/tmp" "$root/tmp"
chmod 1777 "$root/var/tmp" "$root/tmp"
cp /etc/yum.repos.d/fedora*.repo "$root/etc/yum.repos.d/"
dnf -y --installroot="$root" --releasever=44 \
    --setopt=install_weak_deps=False --exclude='kernel*' \
    install gnome-shell libevdev libiio dbus-daemon ibus acl
# Lorax strips files but keeps their RPM records. Restore tools, icon
# loaders and the full MIME definitions before package triggers rebuild caches.
# Otherwise a regenerated MIME cache contains almost no types and GTK aborts.
dnf -y --installroot="$root" --releasever=44 \
    reinstall glib2 shared-mime-info gdk-pixbuf2 librsvg2
chroot "$root" update-mime-database /usr/share/mime
chroot "$root" gdk-pixbuf-query-loaders-64 --update-cache
python3 /installer/extract-controller.py "$work/payload" "$root" > "$work/payload-digest"
cp -a /installer/runtime/. "$root/"
python3 /installer/apply-branding.py "$root" /assets
mkdir -p "$root/usr/share/aquarius"
cp "$work/payload-digest" "$root/usr/share/aquarius/installer-handheld"

# Anaconda launches gnome-kiosk by this path. Keep Fedora's original executable
# for inspection; our wrapper starts GNOME's shell on the SAME Wayland socket.
[ -x "$root/usr/bin/gnome-kiosk" ]
mv "$root/usr/bin/gnome-kiosk" "$root/usr/libexec/aquarius-gnome-kiosk-original"
ln -s ../libexec/aquarius-installer-compositor "$root/usr/bin/gnome-kiosk"
chroot "$root" glib-compile-schemas --strict /usr/share/glib-2.0/schemas
# systemd needs /proc/self/fd to replace the database atomically. Run the
# runtime compiler with its matching libraries outside the stripped chroot.
LD_LIBRARY_PATH="$root/usr/lib64/systemd:$root/usr/lib64" \
    "$root/usr/bin/systemd-hwdb" --root="$root" update
mkdir -p "$root/usr/lib/systemd/system/anaconda.target.wants"
ln -sf ../aquarius-installer-input.service \
    "$root/usr/lib/systemd/system/anaconda.target.wants/aquarius-installer-input.service"

# Read back actual runtime content before making a new ISO.
chroot "$root" /usr/bin/inputplumber --version
chroot "$root" /usr/bin/gnome-shell --version
for program in inputplumber gnome-shell; do
    libraries=$(chroot "$root" ldd "/usr/bin/$program")
    printf '%s\n' "$libraries"
    if grep -q 'not found' <<< "$libraries"; then
        echo "Missing runtime library for $program" >&2
        exit 1
    fi
done
python3 /installer/verify-runtime.py "$root"

# Build caches are not needed on the USB. Keep its original installer target.
rm -rf "$root/var/cache/libdnf5" "$root/var/cache/dnf"
rm -f "$root/etc/yum.repos.d/"*.repo
[ "$(readlink "$root/etc/systemd/system/default.target")" = /lib/systemd/system/anaconda.target ]
mksquashfs "$root" "$work/install-handheld.img" -noappend -comp zstd -no-progress

# Replaying the original boot metadata preserves BIOS/UEFI bootability. Only
# stage2 changes. The embedded OS, kernel, initramfs, disk choices and kickstart
# are kept byte-for-byte. Recompute Fedora's boot-time media-check checksum.
rebuilt=$(mktemp /output/.install-handheld.XXXXXX)
trap 'rm -f "$rebuilt"' EXIT
xorriso -indev "$iso" -outdev "$rebuilt" \
    -boot_image any replay \
    -map "$work/install-handheld.img" /images/install.img
implantisomd5 --force "$rebuilt"
checkisomd5 "$rebuilt"

# Prove the ISO contains exactly the runtime we just verified.
xorriso -osirrox on -indev "$rebuilt" \
    -extract /images/install.img "$work/readback.img"
python3 - "$work/install-handheld.img" "$work/readback.img" <<'PYVERIFY'
import hashlib
import sys
with open(sys.argv[1], 'rb') as original, open(sys.argv[2], 'rb') as readback:
    assert hashlib.file_digest(original, 'sha256').digest() == hashlib.file_digest(readback, 'sha256').digest()
PYVERIFY
mv "$rebuilt" "$iso"
echo 'Handheld installer runtime added and read back successfully.'
rm -rf "$work"
