#!/usr/bin/bash
# ==============================================================================
# STEP 82 — Reading a Mac drive
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# Royce works on a Mac and on this computer. A drive that comes off the Mac is
# formatted APFS, and until now plugging one into AquariusOS did nothing at all:
# Linux's kernel cannot read APFS, so udisks2 (step 76's drive-mounting service)
# had nothing to mount it with, and the drive was a brick.
#
# This step installs the one thing that CAN read APFS — `apfs-fuse`, a program
# that reads it in ordinary user space — and then checks, in the finished image,
# every piece of the path that makes it work with no terminal:
#
#   apfs-fuse, apfsutil    Fedora's own package. READ-ONLY, and that is the
#                          honest ceiling: Apple has never published how APFS
#                          works, so every Linux program that WRITES it is
#                          working from guesswork, and guessing is not something
#                          to do with somebody's only copy of a shoot.
#   fuse3 / fusermount3    the standard piece of Linux that lets an ordinary
#                          program mount something. It has to be there and it
#                          has to be set up to work for a person who is not the
#                          administrator, or nothing below matters.
#   70-aquarius-apfs.rules a udev rule that hands an APFS drive to whoever is
#                          logged in at the screen, so apfs-fuse can open it
#                          with no privilege of any kind.
#   aquarius-media-dir     makes /run/media/<you> at login and makes it YOURS,
#                          which is what lets your own session create a folder
#                          to mount onto.
#   aquarius-automount     the agent from step 76, which now takes the Mac path
#                          for an APFS drive instead of asking udisks2.
#   aquarius-drive-unlock  the notification and the window for a drive with
#                          FileVault on it.
#   aq drive               list / eject / unlock, for anybody who prefers to type.
#
# ⚠️ WHY SO MANY CHECKS FOR ONE FEATURE. Every single failure mode of this
# feature looks EXACTLY the same from a person's chair: you plug the drive in
# and nothing happens. A missing package, an unreadable device, a folder you may
# not write to, a setuid bit that is not set — all of them are "nothing
# happened". None of them produces an error anybody sees. So each one is asked
# about here, by name, with the consequence written next to it.
#
# After step 76 (the automount agent this extends) and step 5 (which copies in
# every file under system_files/).
#
# Plain-English guide: docs/restart/mac-drives.md
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AGENT="/usr/libexec/aquarius-automount"
UNLOCK="/usr/libexec/aquarius-drive-unlock"
MEDIA_DIR="/usr/libexec/aquarius-media-dir"
SHARED="/usr/lib/aquarius/python/aquarius_apfs.py"
UDEV_RULE="/usr/lib/udev/rules.d/70-aquarius-apfs.rules"
DROPIN="/usr/lib/systemd/system/user@.service.d/aquarius-media-dir.conf"
AQ="/usr/bin/aq"

# ------------------------------------------------------------------------------
# 1. The program that reads APFS
# ------------------------------------------------------------------------------
say "The Mac-drive reader"

# apfs-fuse is in Fedora's own repository — a 2020 snapshot of the upstream
# project (sgan81/apfs-fuse), packaged as apfs-fuse-0-33.20200928gitee71aa5.
# We install the PACKAGE and never build from source: a compiler in this image
# is a compiler in everybody's operating system.
#
# fuse3 is named explicitly even though apfs-fuse already requires it, because
# what we actually depend on is /usr/bin/fusermount3, and "a dependency that
# happens to pull in the thing we need" is not a promise anybody made us.
aq_dnf install apfs-fuse fuse3

aq_installed apfs-fuse fuse3

for program in /usr/bin/apfs-fuse /usr/bin/apfsutil; do
    if [ -x "${program}" ]; then
        ok "${program} is present and runnable"
    else
        bad "${program} is missing — a Mac drive would do nothing at all when plugged in"
    fi
done

# apfsutil is the one that lists a drive's volumes. Ask it for its own syntax,
# which it prints when given nothing, and which needs no drive to answer.
if aq_output_has "Syntax" /usr/bin/apfsutil; then
    ok "apfsutil runs and states its syntax"
else
    bad "apfsutil did not answer — the agent could not find out what is on a Mac drive"
fi

# ------------------------------------------------------------------------------
# 2. ⚠️ fusermount3, and the bit that makes it work for a person
# ------------------------------------------------------------------------------
# This is the check that is easiest to get wrong and hardest to notice.
#
# A normal program cannot mount anything — mounting is an administrator's job.
# FUSE gets around that with one small setuid-root program, fusermount3: apfs-fuse
# asks IT to attach the mount, and it checks that you own the folder you are
# mounting onto before it does. If the setuid bit on that program is missing, our
# whole design collapses to "you must be root to read a Mac drive", and the only
# symptom is a drive that never appears.
say "The piece that lets an ordinary program mount something"
if [ -x /usr/bin/fusermount3 ]; then
    perms="$(stat -c '%a %U' /usr/bin/fusermount3)"
    echo "  /usr/bin/fusermount3 is ${perms}"
    case "${perms}" in
        4*" root")
            ok "fusermount3 is setuid root, so a person can mount a Mac drive with no password"
            ;;
        *)
            bad "fusermount3 is ${perms} — without the setuid bit and root ownership,"
            bad "reading a Mac drive would need an administrator, and the drive would"
            bad "simply never appear for anybody else. This is a packaging fault."
            ;;
    esac
else
    bad "/usr/bin/fusermount3 is missing — nothing could mount a Mac drive"
fi

# ------------------------------------------------------------------------------
# 3. ⚠️ And the piece that lets the DOCK put it away again
# ------------------------------------------------------------------------------
# The dock's Eject runs `gio mount -u -f <folder>`, which for a mount udisks2
# does not know about ends up running `umount <folder>` as the person. That only
# works because of a rule inside util-linux: since version 2.34, umount lets you
# unmount a FUSE filesystem when the kernel's mount table says the mount belongs
# to your user number — no /etc/fstab entry, no password, no polkit.
#
# apfs-fuse's mounts always carry that user number (FUSE puts user_id= on every
# mount it makes), so the rule applies. If this image ever shipped a util-linux
# older than 2.34, or one whose umount was not setuid, Eject would fail with
# "operation not permitted" and the only way to put a Mac drive away would be
# `aq drive eject`. So both halves are read back here.
say "The piece that lets the dock's Eject work on a Mac drive"
version_line="$(umount --version 2>&1 | head -n 1 || true)"
echo "  ${version_line}"
util_version="$(printf '%s' "${version_line}" | grep -oE '[0-9]+\.[0-9]+' | head -n 1)"
if [ -n "${util_version}" ]; then
    major="${util_version%%.*}"
    minor="${util_version##*.}"
    if [ "${major}" -gt 2 ] || { [ "${major}" -eq 2 ] && [ "${minor}" -ge 34 ]; }; then
        ok "util-linux ${util_version} is new enough (2.34+) for a person to unmount their own FUSE mount"
    else
        bad "util-linux ${util_version} is older than 2.34, so the dock's Eject would be"
        bad "refused on a Mac drive. 'aq drive eject' still works; the dock would not."
    fi
else
    bad "could not read umount's version — the dock's Eject on a Mac drive is unverified"
fi

if [ -e /usr/bin/umount ]; then
    perms="$(stat -c '%a %U' /usr/bin/umount)"
    echo "  /usr/bin/umount is ${perms}"
    case "${perms}" in
        4*" root") ok "umount is setuid root, which is what lets that rule be applied at all" ;;
        *) bad "umount is ${perms} — not setuid root, so the dock's Eject would be refused" ;;
    esac
else
    bad "/usr/bin/umount is missing"
fi

# The two other commands the `aq drive` front door uses.
if [ -x /usr/bin/lsblk ]; then
    ok "lsblk is present ('aq drive unlock' uses it to find Mac drives)"
else
    bad "lsblk is missing — 'aq drive unlock' could not find a drive by name"
fi
if aq_have gio; then
    ok "gio is present ('aq drive eject' uses it for non-Mac drives, like the dock)"
else
    bad "gio is missing — 'aq drive eject' could not put an ordinary drive away"
fi
aq_installed libnotify

# ------------------------------------------------------------------------------
# 4. ⚠️ /etc/fuse.conf — the thing we deliberately do NOT need
# ------------------------------------------------------------------------------
# There is an option called `allow_other` which makes a FUSE mount readable by
# every account on the computer, and switching it on needs `user_allow_other` in
# /etc/fuse.conf. Plenty of guides on the internet tell you to do both.
#
# We do neither, on purpose: the mount is made BY the person FOR the person, and
# their own desktop is the only thing that has to see it. Turning it on would
# hand every Mac drive to every account on the machine for no gain at all.
#
# So this checks in both directions — that we do not ask for it, and that the
# image has not quietly switched it on.
#
# ⚠️ HOW THIS CHECK IS WRITTEN, AND THE TRAP IT AVOIDS. Both programs SAY the
# words "never allow_other" out loud — in their comments, and in the rehearsal
# text the build prints. A check that simply grepped for "allow_other" would
# therefore fail on the very sentence promising it is not there. (Step 76 has
# the same lesson written on it, in the same words, from 2026-09-08.)
#
# So this does not grep for the word. It reads the ONE line in each program that
# actually builds the mount options — the `options = "ro,…"` line — and looks
# inside that. It also fails if that line has gone missing, because a check with
# nothing to check is not a check.
say "allow_other: not asked for, and not switched on"
option_lines="$(grep -h 'options = "ro,' "${AGENT}" "${UNLOCK}" || true)"
count="$(printf '%s\n' "${option_lines}" | grep -c 'options = "ro,' || true)"
if [ "${count}" -lt 2 ]; then
    bad "expected both the agent and the unlock helper to build their mount options"
    bad "with a line reading 'options = \"ro,…\"', and found ${count}. The mount-options"
    bad "shape has changed; read mount_apfs() and unlock() and update this check."
else
    ok "both programs build their mount options from one readable line (${count} found)"
    printf '%s\n' "${option_lines}" | sed 's/^[[:space:]]*/       /'
    if printf '%s\n' "${option_lines}" | grep -q 'allow_other'; then
        bad "one of them passes allow_other to apfs-fuse. That hands the drive to every"
        bad "account on this computer. Remove it — see the comment in mount_apfs()."
    else
        ok "and neither passes allow_other"
    fi
    same="$(printf '%s\n' "${option_lines}" | grep -c 'ro,uid=%d,gid=%d,subtype=apfs' || true)"
    if [ "${same}" -eq "${count}" ]; then
        ok "and both mount read-only, as the person, marked as a Mac drive"
    else
        bad "the two mount-option lines are not the same. The agent and the unlock"
        bad "helper must mount a drive identically, or an unlocked drive would behave"
        bad "differently from one that was never locked."
    fi
fi

if [ -r /etc/fuse.conf ]; then
    if grep -Eq '^[[:space:]]*user_allow_other' /etc/fuse.conf; then
        bad "/etc/fuse.conf switches on user_allow_other. We do not need it and it"
        bad "widens every FUSE mount on the machine. Remove that line."
    else
        ok "/etc/fuse.conf does not switch on user_allow_other (we do not need it)"
    fi
else
    ok "there is no /etc/fuse.conf, which is the same as user_allow_other being off"
fi

# ------------------------------------------------------------------------------
# 5. The udev rule that hands the drive to the person at the screen
# ------------------------------------------------------------------------------
say "The rule that lets you open the drive at all"
if [ -r "${UDEV_RULE}" ]; then
    ok "${UDEV_RULE} is installed"
else
    bad "${UDEV_RULE} is missing — a Mac drive could only be read by an administrator,"
    bad "so it would never appear for the person who plugged it in"
fi

aq_file_has "${UDEV_RULE}" 'ENV\{ID_FS_TYPE\}=="apfs"' \
    "the rule matches only devices Linux has identified as APFS"
aq_file_has "${UDEV_RULE}" 'TAG\+="uaccess"' \
    "the rule hands the device to the person logged in at the screen (uaccess)"
aq_file_has "${UDEV_RULE}" 'SUBSYSTEM=="block"' \
    "the rule is limited to disks and partitions"

# ⚠️ THE FILE NAME IS PART OF THE FEATURE. udev reads its rules in number order:
# 60-persistent-storage.rules is what works out ID_FS_TYPE, and 73-seat-late.rules
# is what ACTS on the uaccess tag. A rule numbered outside 61–72 either tests a
# value that does not exist yet or adds a tag after the only thing that reads it.
# Both are silent. So the number itself is checked.
rule_number="$(basename "${UDEV_RULE}")"
rule_number="${rule_number%%-*}"
if [ "${rule_number}" -gt 60 ] && [ "${rule_number}" -lt 73 ]; then
    ok "it is numbered ${rule_number} — after 60 (which sets ID_FS_TYPE) and before 73 (which acts on uaccess)"
else
    bad "the rule is numbered ${rule_number}. Below 61 it tests a value udev has not"
    bad "worked out yet; 73 or above it adds a tag after the only rule that reads it."
    bad "Either way it does nothing, silently. Rename it to 70-aquarius-apfs.rules."
fi

# udev refuses to load a rule file it cannot parse, at runtime, with nothing on
# screen. `udevadm verify` is systemd's own checker for exactly that.
if aq_have udevadm; then
    if udevadm verify --help > /dev/null 2>&1; then
        if udevadm verify "${UDEV_RULE}" > /tmp/aq-udev.txt 2>&1; then
            ok "udev itself reads the rule file and understands every line of it"
        else
            bad "udev cannot parse ${UDEV_RULE}:"
            sed 's/^/       /' /tmp/aq-udev.txt
        fi
        rm -f /tmp/aq-udev.txt
    else
        echo "  note   this systemd's udevadm has no 'verify', so the rule's syntax"
        echo "         was not machine-checked here. The line-by-line checks above"
        echo "         are what guard it."
    fi
else
    bad "udevadm is not in the image — no udev rule of ours would ever be read"
fi

# ------------------------------------------------------------------------------
# 6. The folder every drive appears in, made at login
# ------------------------------------------------------------------------------
say "The folder every drive appears in"
if [ -x "${MEDIA_DIR}" ]; then
    ok "${MEDIA_DIR} is present and runnable"
else
    bad "${MEDIA_DIR} is missing — /run/media/<you> would not exist until udisks2"
    bad "made it, and a Mac drive would have nowhere it is allowed to mount"
fi

if bash -n "${MEDIA_DIR}" 2> /tmp/aq-media-sh.txt; then
    ok "it is valid shell"
else
    bad "it has a syntax error:"
    sed 's/^/       /' /tmp/aq-media-sh.txt
fi
rm -f /tmp/aq-media-sh.txt

if "${MEDIA_DIR}" --dry-run > /tmp/aq-media-dry.txt 2>&1; then
    ok "its rehearsal (--dry-run) runs and changes nothing"
else
    bad "'aquarius-media-dir --dry-run' failed inside this image:"
    sed 's/^/       /' /tmp/aq-media-dry.txt
fi
aq_file_has /tmp/aq-media-dry.txt 'always exits 0' \
    "its rehearsal states the rule that keeps it off the critical path of a login"
rm -f /tmp/aq-media-dry.txt

# The drop-in, which is the ONLY thing that ever runs it.
say "The systemd addition that runs it at every login"
if [ -r "${DROPIN}" ]; then
    ok "${DROPIN} is installed"
else
    bad "${DROPIN} is missing — the folder would never be made at login"
fi
aq_file_has "${DROPIN}" '^ExecStartPre=-\+/usr/libexec/aquarius-media-dir %i$' \
    "it runs the helper as the administrator (+), ignoring any failure (-), with the user number (%i)"

# ⚠️ THE "-" IS THE ONE CHARACTER A LOGIN DEPENDS ON. Said again on its own,
# because losing it turns a convenience into "this account cannot log in".
if grep -q '^ExecStartPre=[^ ]*-' "${DROPIN}"; then
    ok "⚠️ and the '-' really is there, so a failure here can never stop a login"
else
    bad "⚠️ the '-' is missing from ExecStartPre. A failure would then STOP THE LOGIN"
    bad "of every account on this computer. Put it back."
fi

# ------------------------------------------------------------------------------
# 7. The agent's Mac path, and the shared reader
# ------------------------------------------------------------------------------
say "The shared reader both programs use"
if [ -r "${SHARED}" ]; then
    ok "${SHARED} is installed"
else
    bad "${SHARED} is missing — neither program could work out what is on a Mac drive"
fi
if python3 -c 'import sys; sys.path.insert(0, "/usr/lib/aquarius/python"); import aquarius_apfs' 2> /tmp/aq-apfs-import.txt; then
    ok "it imports cleanly with the Python in this image"
else
    bad "aquarius_apfs cannot be imported:"
    sed 's/^/       /' /tmp/aq-apfs-import.txt
fi
rm -f /tmp/aq-apfs-import.txt

say "The agent's Mac path"
# Pattern greps, the same style as step 76's. Comments are stripped first, so
# that an explanation of a rule cannot be mistaken for the rule.
agent_code="$(grep -v '^[[:space:]]*#' "${AGENT}")"
check_agent() {
    if printf '%s\n' "${agent_code}" | grep -q "$1"; then
        ok "$2"
    else
        bad "$2 — /$1/ is not in ${AGENT}"
    fi
}
check_agent 'id_type(object_path) == APFS' \
    "the agent sends an APFS drive down the Mac path instead of to udisks2"
check_agent 'ro,uid=%d,gid=%d,subtype=apfs' \
    "it mounts read-only, as the person, marked in the mount table as a Mac drive"
check_agent 'aquarius_apfs.APFS_FUSE' \
    "it mounts with apfs-fuse"
check_agent 'InterfacesRemoved' \
    "it notices when the drive is unplugged (nothing else would put our mount away)"
check_agent 'FUSERMOUNT, "-u", "-z"' \
    "and closes the mount with fusermount3 -u -z"
check_agent 'self.apfs_locked(device, volume)' \
    "a FileVault drive gets the unlock offer rather than a silent nothing"

# ------------------------------------------------------------------------------
# 8. The unlock window, and the promise about the password
# ------------------------------------------------------------------------------
say "The window for a drive with FileVault on it"
if [ -x "${UNLOCK}" ]; then
    ok "${UNLOCK} is present and runnable"
else
    bad "${UNLOCK} is missing — a locked Mac drive could only be opened from a terminal"
fi

if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-unlock.pyc", doraise=True)' "${UNLOCK}" 2> /tmp/aq-unlock-py.txt; then
    ok "it is valid Python"
else
    bad "it has a syntax error:"
    sed 's/^/       /' /tmp/aq-unlock-py.txt
fi
rm -f /tmp/aq-unlock.pyc /tmp/aq-unlock-py.txt

if "${UNLOCK}" --dry-run > /tmp/aq-unlock-dry.txt 2>&1; then
    ok "its rehearsal (--dry-run) runs in a container with no drives and no screen"
else
    bad "'aquarius-drive-unlock --dry-run' failed inside this image:"
    sed 's/^/       /' /tmp/aq-unlock-dry.txt
fi
aq_file_has /tmp/aq-unlock-dry.txt 'NEVER stores it' \
    "its rehearsal states that the password is never stored"
aq_file_has /tmp/aq-unlock-dry.txt 'pretend terminal' \
    "and that the password never goes on a command line"
rm -f /tmp/aq-unlock-dry.txt

# ⚠️ THE PASSWORD MUST NOT REACH A COMMAND LINE. apfs-fuse has a `-r <password>`
# option and an `-o pass=...` option, and both would be far simpler than what we
# do. They are also both visible in this machine's process list for as long as
# the drive stays mounted, which could be all day. If either ever appears in our
# code, this stops the build.
unlock_code="$(grep -v '^[[:space:]]*#' "${UNLOCK}")"
if printf '%s\n' "${unlock_code}" | grep -Eq '"-r"|pass=%s|"pass="'; then
    bad "the unlock helper puts the password on apfs-fuse's command line ('-r' or"
    bad "'pass='). Anything on a command line is visible in this machine's process"
    bad "list for as long as the drive is mounted. Use the pty, as before."
else
    ok "the password never goes on a command line — apfs-fuse is asked through a pty"
fi
if printf '%s\n' "${unlock_code}" | grep -q 'import pty'; then
    ok "and the pty really is how it is done"
else
    bad "the unlock helper no longer opens a pty — apfs-fuse turns terminal echo off"
    bad "before it reads, and refuses a plain pipe, so a password fed any other way"
    bad "comes back as 'wrong password'."
fi

# ------------------------------------------------------------------------------
# 9. `aq drive`
# ------------------------------------------------------------------------------
say "The 'aq drive' commands"
aq_file_has "${AQ}" '^    drive \| drives\)$' \
    "'aq drive' is wired into the aq command"
aq_file_has "${AQ}" 'aq drive list' \
    "'aq drive' is in aq's own help, so somebody can find it"
for word in list eject unlock; do
    if grep -q "        ${word}" "${AQ}" || grep -q "${word} |" "${AQ}"; then
        ok "'aq drive ${word}' is there"
    else
        bad "'aq drive ${word}' is missing"
    fi
done
if bash -n "${AQ}" 2> /tmp/aq-sh.txt; then
    ok "aq is still valid shell after the addition"
else
    bad "aq has a syntax error:"
    sed 's/^/       /' /tmp/aq-sh.txt
fi
rm -f /tmp/aq-sh.txt

# ------------------------------------------------------------------------------
# 10. ⚠️ And the checks that actually exercise the code
# ------------------------------------------------------------------------------
# Everything above is "is it there and does it say the right words". Step 76's
# own header explains at length why that is not enough — a check that cannot
# fail is not a check. These two run the real programs.
say "The Mac-drive path really works (against captured drives and a fake bus)"
if [ -r /ctx/tests/test-automount-mount.py ]; then
    if python3 -B /ctx/tests/test-automount-mount.py "${AGENT}"; then
        ok "the agent reads a Mac drive, mounts it read-only, and puts it away again"
    else
        bad "the Mac-drive path does not work — see the lines above."
    fi
else
    bad "/ctx/tests/test-automount-mount.py is missing"
fi

if [ -r /ctx/tests/test-media-dir.sh ]; then
    if bash /ctx/tests/test-media-dir.sh "${MEDIA_DIR}"; then
        ok "the login-time folder is made correctly, and never stops a login"
    else
        bad "aquarius-media-dir is not behaving — see the lines above."
    fi
else
    bad "/ctx/tests/test-media-dir.sh is missing"
fi

# Nothing of the tests, or of importing our own module, may stay in the image.
# Python writes a __pycache__ folder beside any module it imports, and /usr is
# meant to be read-only and identical on every machine.
rm -rf /usr/libexec/__pycache__ /usr/lib/aquarius/python/__pycache__

aq_finish "Reading a Mac drive"
