#!/usr/bin/bash
# Lorax strips controller modules from the live installer. Restore Fedora's
# signed packages for THIS installer's kernel, never the installed OS's kernel.
set -euo pipefail
root=$1
work=$2
mapfile -t kernels < <(find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
[ "${#kernels[@]}" -eq 1 ]
kernel=${kernels[0]}
mkdir -p "$work/rpms" "$work/unpacked"
dnf -y download --destdir="$work/rpms" \
    "kernel-modules-core-$kernel" "kernel-modules-$kernel" "kernel-modules-extra-$kernel"
for package in "$work/rpms/"*.rpm; do
    # dnf's configured Fedora repository supplies these; check RPM signatures
    # as well before unpacking. Its keys were imported by the tooling build.
    rpmkeys --checksig "$package"
    (cd "$work/unpacked"; rpm2cpio "$package" | cpio -idm --quiet --no-absolute-filenames)
done
[ -d "$work/unpacked/lib/modules/$kernel" ]
cp -a "$work/unpacked/lib/modules/$kernel/." "$root/usr/lib/modules/$kernel/"
depmod -b "$root" "$kernel"
for driver in hid_asus xpad uinput uhid; do
    modinfo -b "$root" -k "$kernel" "$driver" > /dev/null
    modprobe -d "$root" -S "$kernel" --show-depends "$driver"
done
echo "Restored controller drivers for installer kernel $kernel"
