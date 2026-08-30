#!/usr/bin/env python3
# ==============================================================================
# Tests for "which drives should mount themselves at boot?"
# ==============================================================================
# The script under test is
#   system_files/usr/libexec/aquarius-internal-automount
# and the question it exists to answer is a list of yes/no decisions: for each
# disk in this machine, do we mount it or leave it alone?
#
# Getting that list wrong is not a cosmetic bug. Mounting the EFI boot partition
# puts a folder on somebody's desktop that they must never edit; mounting a
# partition /etc/fstab already claims fights the system's own settings; mounting
# a Windows drive with the wrong options can put files on it that Windows can
# then never open. So every rule in that script has a test here.
#
# Nothing is mounted by these tests and no disks are touched. Each test hands the
# decision function a made-up description of a disk — the same shape of thing
# `lsblk` really produces — and checks the answer.
#
# HOW TO RUN IT
#   ./tests/test-aquarius-automount.py
#   ./tests/test-aquarius-automount.py /usr/libexec/aquarius-internal-automount
# ==============================================================================

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SCRIPT = os.path.join(
    HERE, "..", "system_files", "usr", "libexec", "aquarius-internal-automount"
)


def load(path: str):
    """Import a script that has no `.py` on the end of its name.

    Our scripts are commands, not modules, so they are named the way commands
    are. Python can still import one if it is told explicitly where it is and
    what to call it — this is the same trick the shell tests use when they
    `source` a library that lives in /usr/libexec.
    """
    spec = importlib.util.spec_from_loader(
        "aquarius_internal_automount",
        importlib.machinery.SourceFileLoader("aquarius_internal_automount", path),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PASSED = 0
FAILED = 0


def check(description: str, condition: bool) -> None:
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  OK    {description}")
    else:
        FAILED += 1
        print(f"  FAIL  {description}")


def disk(**overrides) -> dict:
    """A perfectly ordinary, mountable second data drive.

    Every test starts from this and changes the one thing it is about, so what a
    test is actually testing is whatever it overrides.
    """
    device = {
        "name": "/dev/sda2",
        "kname": "/dev/sda2",
        "type": "part",
        "fstype": "ext4",
        "label": "Footage",
        "partlabel": None,
        "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4",  # ordinary Linux data
        "partuuid": "11111111-2222-3333-4444-555555555555",
        "uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "hotplug": False,
        "ro": False,
        "mountpoints": [None],
    }
    device.update(overrides)
    return device


def main(argv: list[str]) -> int:
    script = argv[0] if argv else DEFAULT_SCRIPT
    if not os.path.isfile(script):
        print(f"test-aquarius-automount: cannot find the script at {script}", file=sys.stderr)
        return 1

    module = load(script)
    skip = module.skip_reason
    no_fstab: set[str] = set()

    # -------------------------------------------------------------------------
    print("\nDrives that SHOULD mount themselves")
    print("-" * 70)
    # -------------------------------------------------------------------------
    for fstype, why in [
        ("ext4", "an ordinary Linux data drive"),
        ("btrfs", "a btrfs data drive"),
        ("xfs", "an XFS data drive"),
        ("f2fs", "an F2FS data drive"),
        ("ntfs", "THE WINDOWS GAME DRIVE — the whole reason this exists"),
        ("exfat", "an exFAT drive, the format big portable SSDs ship in"),
        ("vfat", "a FAT drive"),
    ]:
        check(f"{why} ({fstype}) mounts", skip(disk(fstype=fstype), no_fstab) is None)

    check(
        "an ext4 drive nobody bothered to NAME still mounts "
        "(Bazzite's own automounter skips these)",
        skip(disk(label=None, partlabel=None), no_fstab) is None,
    )
    check(
        "a whole disk with a filesystem straight on it — no partitions — mounts",
        skip(disk(type="disk", name="/dev/sdb", parttype=None, partuuid=None), no_fstab) is None,
    )

    # -------------------------------------------------------------------------
    print("\nDrives that must NEVER be touched")
    print("-" * 70)
    # -------------------------------------------------------------------------
    check(
        "the disk we are booted from — it is already mounted at /",
        skip(disk(mountpoints=["/"]), no_fstab) is not None,
    )
    check(
        "anything Bazzite's own automounter mounted first",
        skip(disk(mountpoints=["/run/media/system/Archive"]), no_fstab) is not None,
    )
    check(
        "swap — it is virtual memory, not a folder",
        skip(disk(fstype="swap"), no_fstab) is not None,
    )
    check(
        "the EFI boot partition, recognised by its partition type",
        skip(
            disk(fstype="vfat", parttype="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"),
            no_fstab,
        )
        is not None,
    )
    check(
        "the EFI boot partition on an old-style MBR disk, too",
        skip(disk(fstype="vfat", parttype="0xef"), no_fstab) is not None,
    )
    check(
        "Windows' recovery partition — a folder nobody should be editing",
        skip(
            disk(fstype="ntfs", parttype="de94bba4-06d1-4d40-a16a-bfd50179d6ac"),
            no_fstab,
        )
        is not None,
    )
    check(
        "the Microsoft Reserved partition",
        skip(
            disk(fstype="ntfs", parttype="e3c9e316-0b5c-4db8-817d-f92df00215ae"),
            no_fstab,
        )
        is not None,
    )
    check(
        "swap said the other way round, by partition type",
        skip(disk(fstype="ext4", parttype="0x82"), no_fstab) is not None,
    )
    check(
        "a LUKS-encrypted drive — there is nobody to ask for the password at boot",
        skip(disk(fstype="crypto_LUKS"), no_fstab) is not None,
    )
    check(
        "a BitLocker-encrypted Windows drive, for the same reason",
        skip(disk(fstype="BitLocker"), no_fstab) is not None,
    )
    check(
        "one slice of an LVM volume — the assembled volume is what gets mounted",
        skip(disk(fstype="LVM2_member"), no_fstab) is not None,
    )
    check(
        "one disk out of a RAID array",
        skip(disk(fstype="linux_raid_member"), no_fstab) is not None,
    )
    check(
        "removable media — that is KDE's job, not ours",
        skip(disk(hotplug=True), no_fstab) is not None,
    )
    check(
        "a blank, unformatted disk",
        skip(disk(fstype=None), no_fstab) is not None,
    )
    check(
        "a filesystem we have no settings for is left alone rather than guessed at",
        skip(disk(fstype="hfsplus"), no_fstab) is not None,
    )
    check(
        "a CD or DVD is not a fixed data drive",
        skip(disk(type="rom", fstype="iso9660"), no_fstab) is not None,
    )

    # -------------------------------------------------------------------------
    print("\nWhen /etc/fstab already has an opinion, it wins")
    print("-" * 70)
    # -------------------------------------------------------------------------
    # Somebody who has written an fstab line for a drive has said exactly how and
    # where they want it. We must not quietly mount it somewhere else instead.
    for key, value in [
        ("device path", "/dev/sda2"),
        ("filesystem UUID", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        ("partition UUID", "11111111-2222-3333-4444-555555555555"),
        ("label", "Footage"),
    ]:
        check(
            f"fstab naming the drive by its {key} is respected",
            skip(disk(), {value}) is not None,
        )

    check(
        "an fstab entry for some OTHER drive does not block this one",
        skip(disk(), {"/dev/sdz9"}) is None,
    )

    # -------------------------------------------------------------------------
    print("\nThe mount settings themselves")
    print("-" * 70)
    # -------------------------------------------------------------------------
    ntfs = module.mount_options("ntfs3", 1000, 1000)
    check("the Windows driver we ask for is the fast in-kernel one", module.FS_DRIVER["ntfs"] == "ntfs3")
    check("a Windows drive is handed to a real person (uid=1000)", "uid=1000" in ntfs)
    check("...and their group (gid=1000)", "gid=1000" in ntfs)
    check(
        "...and refuses to create filenames Windows itself could never open",
        "windows_names" in ntfs,
    )
    check("...and is mounted read-write to begin with", ntfs.startswith("rw,"))
    check(
        "...and programs on it can be run, so a Steam library on it works",
        ",exec" in ntfs,
    )
    check(
        "we never use ntfs3's `force`, which would write to a hibernated Windows",
        "force" not in ntfs,
    )

    ext4 = module.mount_options("ext4", 1000, 1000)
    check(
        "an ext4 drive goes read-only if it starts reporting corruption",
        "errors=remount-ro" in ext4,
    )
    check(
        "an ext4 drive is NOT given an owner — it stores its own ownership",
        "uid=" not in ext4,
    )
    for fstype in ("ext4", "btrfs", "xfs", "ntfs3", "exfat", "vfat"):
        options = module.mount_options(fstype, 1000, 1000)
        check(
            f"a broken {fstype} drive can never stop the machine booting (nofail)",
            "nofail" in options,
        )
        check(
            f"a {fstype} drive can be ejected without a password (users)",
            "users" in options,
        )
    check(
        "a filesystem we do not know is refused settings rather than given a guess",
        module.mount_options("hfsplus", 1000, 1000) is None,
    )

    # -------------------------------------------------------------------------
    print("\nWhere each drive ends up")
    print("-" * 70)
    # -------------------------------------------------------------------------
    taken: set[str] = set()
    check(
        "a drive is named after itself",
        module.mount_point_for(disk(label="Footage"), taken) == "/run/media/system/Footage",
    )
    check(
        "a second drive with the same name does not overwrite the first",
        module.mount_point_for(disk(label="Footage"), taken) == "/run/media/system/Footage-2",
    )
    check(
        "a drive with no name of its own falls back to the partition table's name",
        module.mount_point_for(disk(label=None, partlabel="Games"), set())
        == "/run/media/system/Games",
    )
    check(
        "a drive with no name at all still gets a folder named from its unique id",
        module.mount_point_for(disk(label=None, partlabel=None), set())
        == "/run/media/system/Disk-aaaaaaaa",
    )
    check(
        "...and if it has no filesystem id either, its partition id will do",
        module.mount_point_for(disk(label=None, partlabel=None, uuid=None), set())
        == "/run/media/system/Disk-11111111",
    )
    check(
        "a slash in a drive's name cannot create a folder inside another folder",
        module.mount_point_for(disk(label="Photos/2026"), set())
        == "/run/media/system/Photos-2026",
    )
    check(
        "a name starting with a dot cannot make the drive invisible",
        not os.path.basename(
            module.mount_point_for(disk(label=".hidden"), set())
        ).startswith("."),
    )
    check(
        "every drive lands under /run/media/system, where the rest of the OS looks",
        module.mount_point_for(disk(), set()).startswith("/run/media/system/"),
    )

    print()
    print(f"{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
